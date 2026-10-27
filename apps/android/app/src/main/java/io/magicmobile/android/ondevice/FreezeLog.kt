package io.magicmobile.android.ondevice

import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.game.FreezeBreadcrumbs
import io.magicmobile.android.game.FreezeIncident
import io.magicmobile.android.game.FreezeReport
import io.magicmobile.android.game.FreezeRules
import io.magicmobile.android.game.FreezeStore
import kotlinx.coroutines.CompletableDeferred
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** The board's "Report a freeze" (the game menu): opens the root's confirmation. Null outside a game. */
val LocalFreezeReport = compositionLocalOf<(() -> Unit)?> { null }

/**
 * The freeze log (docs/FREEZE_LOG.md; iOS FreezeLog.swift): breadcrumbs in memory, incidents in the diagnostics folder,
 * a main-thread watchdog. Nothing leaves the phone until the player taps Send. Breadcrumbs and incidents may be added
 * from any thread; every file write runs on one background thread.
 */
object FreezeLog {
    // nanoTime, not SystemClock: the session's JVM tests reach these calls.
    private val startedAt = System.nanoTime()
    private val startedAtWall = System.currentTimeMillis()
    private val crumbs = FreezeBreadcrumbs()
    private val io = Executors.newSingleThreadExecutor { Thread(it, "MagicMobile-freeze-log").apply { isDaemon = true } }
    private var directory: File? = null
    private var power: PowerManager? = null
    private var watchdog: Watchdog? = null

    /** The game's own lines (OnDeviceSession.freezeContext), kept current on the main thread for a hang to read. */
    @Volatile var game: List<Pair<String, String>> = emptyList()
    /** Quick, ranked, casual, custom or table: set by the root when a game starts. */
    @Volatile var mode: String = "none"
    @Volatile private var foreground = true
    /** nanoTime of the game's last change; 0 with no game. */
    @Volatile private var gameChangedAt = 0L

    /** An unsent freeze from an earlier run, for the main menu's question (main thread). */
    var launchOffer by mutableStateOf<FreezeIncident?>(null); private set

    /** Once per process, from MainActivity: the watchdog, and the earlier run's unsent freeze. */
    fun start(context: Context) {
        if (directory != null) return
        val app = context.applicationContext
        directory = OnDeviceDiagnostics.directory(app)
        power = app.getSystemService(PowerManager::class.java)
        val main = Handler(Looper.getMainLooper())
        io.execute {
            val offer = runCatching { store()?.load() }.getOrNull().orEmpty()
                .lastOrNull { !it.sent && !it.declined && FreezeRules.worthAsking(it.kind, it.durationSeconds) && it.atMillis < startedAtWall && it.duringGame }
            if (offer != null) main.post { launchOffer = offer }
        }
        watchdog = Watchdog(main).also { it.start() }
    }

    private fun store(): FreezeStore? = directory?.let(::FreezeStore)

    /** The launch question names "the last game": a hang on the menus is kept for the report sheet only. */
    private val FreezeIncident.duringGame: Boolean get() = context.any { (label, value) -> label == "Mode" && value != "none" }

    fun crumb(text: String) = crumbs.add((System.nanoTime() - startedAt) / 1e9, text)

    fun setForeground(value: Boolean) {
        if (foreground == value) return
        foreground = value
        crumb(if (value) "Foreground" else "Background")
        watchdog?.paused = !value
    }

    fun gameChanged() { gameChangedAt = System.nanoTime() }
    fun gameEnded() { gameChangedAt = 0L; game = emptyList() }

    /** Records an incident now (its file write follows on the log's thread). */
    fun record(kind: String, durationSeconds: Double? = null, game: List<Pair<String, String>> = this.game): FreezeIncident {
        val incident = FreezeIncident(UUID.randomUUID().toString(), kind, System.currentTimeMillis(), durationSeconds, context(game), crumbs.snapshot())
        crumb("Recorded freeze: $kind")
        write { list -> list + incident }
        return incident
    }

    private fun write(change: (List<FreezeIncident>) -> List<FreezeIncident>) {
        io.execute { runCatching { store()?.update(change) } }
    }

    private fun context(game: List<Pair<String, String>>): List<Pair<String, String>> = buildList {
        add("App" to "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        // The device lines are Android calls; each is skipped if it fails (as in a JVM test).
        runCatching { add("OS" to OnDeviceSystemReports.platform()) }
        runCatching { add("Device" to "${Build.MANUFACTURER} ${Build.MODEL}") }
        runCatching { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power?.let { add("Thermal" to thermal(it.currentThermalStatus)) } }
        val runtime = Runtime.getRuntime()
        val native = runCatching { " · native ${Debug.getNativeHeapAllocatedSize() / MB} MB" }.getOrDefault("")
        add("Memory" to "Java ${(runtime.totalMemory() - runtime.freeMemory()) / MB} of ${runtime.maxMemory() / MB} MB$native")
        add("Foreground" to if (foreground) "yes" else "no")
        add("Mode" to mode)
        addAll(game)
        val changed = gameChangedAt
        if (changed != 0L) add("Game last changed" to "${(System.nanoTime() - changed) / 1_000_000_000} s ago")
    }

    private fun thermal(status: Int): String = when (status) {
        0 -> "none"; 1 -> "light"; 2 -> "moderate"; 3 -> "severe"; 4 -> "critical"; 5 -> "emergency"; 6 -> "shutdown"; else -> "$status"
    }

    /** Not now: this freeze isn't asked about again. */
    fun decline(incident: FreezeIncident) {
        if (launchOffer?.id == incident.id) launchOffer = null
        write { list -> list.map { if (it.id == incident.id) it.copy(declined = true) else it } }
    }

    /**
     * Send (only on the player's tap): the incident as saved now plus the phone's crash and ANR summaries, through
     * mm_send_diagnostic. True once the server stored it; the incident is then marked sent.
     */
    suspend fun send(incident: FreezeIncident, upload: suspend (kind: String, report: String) -> Boolean): Boolean {
        val text = CompletableDeferred<String>()
        io.execute {
            val saved = runCatching { store()?.load() }.getOrNull()?.firstOrNull { it.id == incident.id } ?: incident
            val system = directory?.let { runCatching { OnDeviceSystemReports.section(OnDeviceSystemReports.load(it)) }.getOrNull() }
            text.complete(FreezeReport.sent(saved, system))
        }
        val sent = runCatching { upload(incident.kind, text.await()) }.getOrDefault(false)
        if (sent) {
            if (launchOffer?.id == incident.id) launchOffer = null
            crumb("Freeze report sent")
            write { list -> list.map { if (it.id == incident.id) it.copy(sent = true) else it } }
        }
        return sent
    }

    /**
     * Pings the main thread every 500 ms. A ping left waiting 2 s is a hang, saved at once (the system may end a stuck
     * app before it recovers); its duration is filled in when the main thread answers. Paused in the background.
     */
    private class Watchdog(private val main: Handler) : Thread("MagicMobile-freeze-watchdog") {
        @Volatile var paused = false
            set(value) { field = value; synchronized(lock) { lock.notifyAll() } }
        private val lock = Object()
        /** Uptime when the waiting ping was posted, 0 when none waits. */
        @Volatile private var pingedAt = 0L
        @Volatile private var answeredAt = 0L
        private val ping = Runnable { answeredAt = SystemClock.uptimeMillis(); pingedAt = 0L }

        init { isDaemon = true; priority = MIN_PRIORITY }

        override fun run() {
            var hang: FreezeIncident? = null
            var hangStart = 0L
            while (true) {
                try { sleep(500) } catch (_: InterruptedException) { return }
                if (paused) {
                    // Time in the background is not a hang; start over when the app is back.
                    synchronized(lock) { while (paused) try { lock.wait() } catch (_: InterruptedException) { return } }
                    main.removeCallbacks(ping); pingedAt = 0L; hang = null
                    continue
                }
                val waiting = pingedAt
                val now = SystemClock.uptimeMillis()
                if (waiting == 0L) {
                    hang?.let { open ->
                        val seconds = (answeredAt - hangStart) / 1000.0
                        crumb("Main thread recovered after ${"%.1f".format(java.util.Locale.ROOT, seconds)} s")
                        FreezeLog.write { list -> list.map { if (it.id == open.id) it.copy(durationSeconds = seconds) else it } }
                        hang = null
                    }
                    pingedAt = now
                    main.post(ping)
                } else if (hang == null && now - waiting >= (FreezeRules.HANG_SECONDS * 1000).toLong()) {
                    hangStart = waiting
                    hang = FreezeLog.record(FreezeRules.HANG)
                }
            }
        }
    }

    private const val MB = 1024 * 1024
}
