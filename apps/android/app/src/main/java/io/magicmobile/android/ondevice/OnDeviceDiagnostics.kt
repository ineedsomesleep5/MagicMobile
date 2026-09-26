package io.magicmobile.android.ondevice

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.IosTextButton
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfText
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import java.io.InputStream
import java.time.Instant

/**
 * Port of OnDeviceDiagnostics.swift: the latest local engine failure only, plus this app's own
 * crash, ANR and native-crash summaries from Android's exit history. No snapshots, action payloads,
 * networking, or automatic sharing. Kept in no-backup storage. Main thread only.
 */
class OnDeviceDiagnostics(private val directory: File,
                          private val appVersion: String = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                          private val platform: String = OnDeviceSystemReports.platform()) {
    /** What the report sheet shows and shares: the engine failure, then any crash and ANR summaries. */
    var report by mutableStateOf<String?>(null); private set
    var isHistorical by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null)
    private var engineReport: String? = null
    private var persistedReport: String? = null
    private var systemReport: String? = null
    private var captureGeneration = 0
    private var clearing = false
    private val file: File get() = File(directory, "latest-engine-failure.txt")

    init {
        try {
            if (file.exists()) {
                if (file.length() > MAX_BYTES) throw IllegalStateException("The saved report is too large.")
                engineReport = file.readText(Charsets.UTF_8)
                persistedReport = engineReport
                isHistorical = true
            }
        } catch (error: Exception) { errorMessage = "Could not load the saved engine report: ${error.message}" }
        systemReport = OnDeviceSystemReports.section(OnDeviceSystemReports.load(directory))
        publish()
    }

    private fun publish() {
        val parts = listOfNotNull(engineReport, systemReport)
        report = if (parts.isEmpty()) null else parts.joinToString("\n\n")
        // Crash and ANR summaries always describe an earlier session.
        if (engineReport == null) isHistorical = systemReport != null
    }

    /** Exit reports recorded after this store opened (the startup reader runs in the background). */
    fun reloadSystemReports() {
        systemReport = OnDeviceSystemReports.section(OnDeviceSystemReports.load(directory))
        publish()
    }

    fun beginAttempt() {
        captureGeneration += 1
        if (report != null) isHistorical = true
    }

    fun save(engineReport: String, status: String) {
        // Reopening the sheet must not date an existing incident as a new failure.
        val current = this.engineReport
        if (current != null && persistedReport == current) {
            val split = current.indexOf("\n\n")
            if (split >= 0 && engineReport.startsWith(current.substring(split + 2))) return
        }
        val text = """
            |MagicMobile local engine diagnostic
            |App: $appVersion
            |OS: $platform
            |Captured: ${Instant.now()}
            |Status: ${status.take(200)}
            |Private: error text may contain card information. Share only by explicit choice.
            |
            |""".trimMargin() + engineReport
        val bytes = boundedUtf8(text, MAX_BYTES)
        this.engineReport = String(bytes, Charsets.UTF_8)
        isHistorical = false
        errorMessage = null
        publish()
        try {
            prepare(directory)
            val temporary = File(directory, "latest-engine-failure.txt.tmp")
            temporary.writeBytes(bytes)
            if (!temporary.renameTo(file)) throw IllegalStateException("Could not replace the saved report.")
            persistedReport = this.engineReport
        } catch (error: Exception) {
            errorMessage = "Report is available to share now, but could not be saved on this device: ${error.message}"
            throw error
        }
    }

    /** Deletes the engine report and the crash and ANR summaries. */
    fun clear() {
        captureGeneration += 1
        if (file.exists() && !file.delete()) throw IllegalStateException("Could not delete the saved report.")
        engineReport = null; persistedReport = null
        OnDeviceSystemReports.clear(directory)
        systemReport = null
        errorMessage = null; isHistorical = false
        publish()
    }

    suspend fun capture(status: String, read: suspend () -> String?) {
        if (clearing) return
        val generation = captureGeneration
        try {
            val report = read() ?: return
            if (generation != captureGeneration) return
            save(report, status)
        } catch (error: Exception) {
            if (generation != captureGeneration) return
            if (errorMessage == null) errorMessage = "Could not capture the local engine report: ${error.message}"
        }
    }

    suspend fun clear(engine: suspend () -> Unit) {
        if (clearing) return
        captureGeneration += 1; clearing = true
        try { engine(); clear() } finally { clearing = false }
    }

    companion object {
        const val MAX_BYTES = 65_536
        private var shared: OnDeviceDiagnostics? = null

        fun directory(context: Context): File = File(context.noBackupFilesDir, "Diagnostics")

        /** The app's one store, like iOS's root @StateObject. Main thread only. */
        fun shared(context: Context): OnDeviceDiagnostics =
            shared ?: OnDeviceDiagnostics(directory(context.applicationContext)).also { shared = it }

        internal fun current(): OnDeviceDiagnostics? = shared

        /** Private to the app; the directory is also outside Android backups. */
        fun prepare(directory: File) {
            if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException("Could not create the diagnostics folder.")
        }

        /** UTF-8 bytes of [text], cut at a code point boundary to at most [limit] bytes. */
        fun boundedUtf8(text: String, limit: Int): ByteArray {
            val bytes = text.toByteArray(Charsets.UTF_8)
            if (bytes.size <= limit) return bytes
            var end = limit
            // Continuation bytes are 10xxxxxx: never end inside a multi-byte sequence.
            while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end -= 1
            return bytes.copyOf(end)
        }
    }
}

/**
 * This app's crashes, ANRs and native crashes as Android records them (ApplicationExitInfo,
 * Android 11+), read once at startup and kept only in the diagnostics folder. A summary holds the
 * time, app and Android versions, the system's short description, memory use, the signal of a
 * native crash, and the main thread's frames from an ANR trace. Package, process and device
 * details are left out; the iOS counterpart summarizes MetricKit crash and hang reports.
 */
object OnDeviceSystemReports {
    /** One recorded process exit, copied from ApplicationExitInfo so it can be formatted anywhere. */
    data class Exit(val timestampMillis: Long, val pid: Int, val reason: Int, val status: Int, val description: String?,
                    val pssKb: Long, val rssKb: Long, val trace: String?)

    data class Entry(val kind: String, val id: String, val at: Long, val text: String)

    /** ApplicationExitInfo.REASON_CRASH, REASON_CRASH_NATIVE and REASON_ANR. */
    const val REASON_CRASH = 4
    const val REASON_CRASH_NATIVE = 5
    const val REASON_ANR = 6
    const val FILE_NAME = "crash-and-anr-reports.json"
    const val LIMIT = 5
    const val MAX_ENTRY_CHARACTERS = 8_000
    const val MAX_FRAMES = 32
    private const val MAX_TRACE_BYTES = 512 * 1024

    fun platform(): String = "Android ${Build.VERSION.RELEASE ?: "unknown"} (API ${Build.VERSION.SDK_INT})"

    /** A summary of a crash, ANR or native crash; null for every other exit reason. */
    fun entry(exit: Exit, appVersion: String, platform: String): Entry? {
        val kind = when (exit.reason) {
            REASON_CRASH -> "Crash"; REASON_CRASH_NATIVE -> "Native crash"; REASON_ANR -> "ANR"
            else -> return null
        }
        val lines = ArrayList<String>()
        lines += "$kind · ${Instant.ofEpochMilli(exit.timestampMillis)}"
        lines += "Seen by app $appVersion · $platform"
        if (exit.reason == REASON_CRASH_NATIVE) lines += "Signal ${exit.status}${signalName(exit.status)?.let { " ($it)" } ?: ""}"
        clean(exit.description, 300)?.let { lines += "Reason: $it" }
        if (exit.pssKb > 0 || exit.rssKb > 0) lines += "Memory: PSS ${exit.pssKb / 1024} MB · RSS ${exit.rssKb / 1024} MB"
        exit.trace?.let(::mainThread)?.let { (state, frames) ->
            if (frames.isNotEmpty()) {
                lines += "Main thread${state?.let { " ($it)" } ?: ""}:"
                frames.take(MAX_FRAMES).forEachIndexed { index, frame -> lines += "  $index $frame" }
                if (frames.size > MAX_FRAMES) lines += "  … ${frames.size - MAX_FRAMES} more frames"
            }
        }
        return Entry(kind, "${exit.reason}-${exit.timestampMillis}-${exit.pid}", exit.timestampMillis,
            lines.joinToString("\n").take(MAX_ENTRY_CHARACTERS))
    }

    /** The "main" thread's state and frames from an ANR trace (the text of `traces.txt`). */
    fun mainThread(trace: String): Pair<String?, List<String>>? {
        val lines = trace.lineSequence().iterator()
        while (lines.hasNext()) {
            val header = lines.next()
            if (!header.startsWith("\"main\"")) continue
            val state = header.trim().split(Regex("\\s+")).lastOrNull()?.takeIf { it.isNotEmpty() && !it.contains('=') }
            val frames = ArrayList<String>()
            while (lines.hasNext()) {
                val line = lines.next()
                if (line.isBlank()) break
                val frame = line.trim()
                if (frame.startsWith("at ") || frame.startsWith("- ") || frame.startsWith("native: ")) {
                    clean(frame, 200)?.let(frames::add)
                    if (frames.size > MAX_FRAMES + 64) break
                }
            }
            return state to frames
        }
        return null
    }

    private fun clean(value: String?, limit: Int): String? {
        val text = value?.filter { !Character.isISOControl(it) }?.trim().orEmpty()
        return text.takeIf { it.isNotEmpty() }?.take(limit)
    }

    private fun signalName(signal: Int): String? = mapOf(4 to "SIGILL", 5 to "SIGTRAP", 6 to "SIGABRT", 7 to "SIGBUS", 8 to "SIGFPE",
        9 to "SIGKILL", 11 to "SIGSEGV", 13 to "SIGPIPE", 15 to "SIGTERM")[signal]

    /** New summaries join the saved ones; a repeated exit is kept once; the newest [LIMIT], oldest first. */
    fun merged(existing: List<Entry>, new: List<Entry>): List<Entry> {
        val byID = LinkedHashMap<String, Entry>()
        (existing + new).forEach { byID.putIfAbsent(it.id, it) }
        return byID.values.sortedBy { it.at }.takeLast(LIMIT)
    }

    /** The export text, or null when this phone has no crash or ANR report. */
    fun section(entries: List<Entry>): String? {
        if (entries.isEmpty()) return null
        return (listOf("MagicMobile crash and ANR reports (${entries.size}, newest last, from Android on this phone)") +
            entries.map { it.text }).joinToString("\n\n")
    }

    fun load(directory: File): List<Entry> = runCatching {
        val file = File(directory, FILE_NAME)
        if (!file.exists() || file.length() > LIMIT * MAX_ENTRY_CHARACTERS * 4L + 4_096) return emptyList()
        Json.parseToJsonElement(file.readText(Charsets.UTF_8)).jsonArray.mapNotNull { row ->
            val fields = row.jsonObject
            val kind = fields["kind"]?.jsonPrimitive?.content ?: return@mapNotNull null
            val id = fields["id"]?.jsonPrimitive?.content ?: return@mapNotNull null
            val at = fields["at"]?.jsonPrimitive?.longOrNull ?: return@mapNotNull null
            val text = fields["text"]?.jsonPrimitive?.content ?: return@mapNotNull null
            Entry(kind, id, at, text.take(MAX_ENTRY_CHARACTERS))
        }.takeLast(LIMIT)
    }.getOrDefault(emptyList())

    fun save(entries: List<Entry>, directory: File) {
        OnDeviceDiagnostics.prepare(directory)
        val json = JsonArray(entries.takeLast(LIMIT).map {
            JsonObject(mapOf("kind" to JsonPrimitive(it.kind), "id" to JsonPrimitive(it.id), "at" to JsonPrimitive(it.at), "text" to JsonPrimitive(it.text)))
        })
        val temporary = File(directory, "$FILE_NAME.tmp")
        temporary.writeText(json.toString(), Charsets.UTF_8)
        if (!temporary.renameTo(File(directory, FILE_NAME))) throw IllegalStateException("Could not save the crash reports.")
    }

    /** Adds the summaries of [exits]; true when something new was saved. */
    fun record(exits: List<Exit>, directory: File, appVersion: String, platform: String): Boolean {
        val new = exits.mapNotNull { entry(it, appVersion, platform) }
        if (new.isEmpty()) return false
        val existing = load(directory)
        val combined = merged(existing, new)
        if (combined == existing) return false
        return runCatching { save(combined, directory) }.isSuccess
    }

    fun clear(directory: File) {
        val file = File(directory, FILE_NAME)
        if (file.exists() && !file.delete()) throw IllegalStateException("Could not delete the crash reports.")
    }

    /**
     * Called once from MainActivity: reads this app's recent exits on a background thread. Needs no
     * permission (the app reads only its own history) and sends nothing anywhere.
     */
    fun recordAtStartup(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val app = context.applicationContext
        Thread({ runCatching { recordExits(app) } }, "MagicMobile-exit-reports").start()
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun recordExits(app: Context) {
        val manager = app.getSystemService(ActivityManager::class.java) ?: return
        val exits = manager.getHistoricalProcessExitReasons(app.packageName, 0, 16)
            .filter { it.reason == REASON_CRASH || it.reason == REASON_CRASH_NATIVE || it.reason == REASON_ANR }
            .map(::exit)
        val appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
        if (record(exits, OnDeviceDiagnostics.directory(app), appVersion, platform())) {
            Handler(Looper.getMainLooper()).post { OnDeviceDiagnostics.current()?.reloadSystemReports() }
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun exit(info: ApplicationExitInfo): Exit {
        // Only an ANR's trace is text; a native crash's tombstone is binary and left out.
        val trace = if (info.reason == REASON_ANR) runCatching { info.traceInputStream?.use(::readBounded) }.getOrNull() else null
        return Exit(info.timestamp, info.pid, info.reason, info.status, info.description, info.pss, info.rss, trace)
    }

    private fun readBounded(stream: InputStream): String {
        val buffer = ByteArray(MAX_TRACE_BYTES)
        var length = 0
        while (length < buffer.size) {
            val read = stream.read(buffer, length, buffer.size - length)
            if (read < 0) break
            length += read
        }
        return String(buffer, 0, length, Charsets.UTF_8)
    }
}

/**
 * The setup screen's entry to the local report (iOS: "Engine error report" and its sheet). The
 * report appears once there is one; the player reviews it and shares it only by choice.
 */
@Composable
fun OnDeviceDiagnosticsEntry(setup: OnDeviceSetupModel) {
    val context = LocalContext.current
    val store = remember { OnDeviceDiagnostics.shared(context) }
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val failure = setup.errorMessage ?: setup.session.errorMessage
    LaunchedEffect(failure) { if (failure != null) store.capture(setup.status) { setup.diagnosticReport() } }
    if (store.report != null) {
        IosTextButton("Engine error report", { store.beginAttempt(); open = true },
            Modifier.semantics { contentDescription = "Engine error report" }, color = BrandTheme.ember)
    }
    if (open) {
        LaunchedEffect(Unit) { store.capture(setup.status) { setup.diagnosticReport() } }
        BoardSheet({ open = false }, skipPartiallyExpanded = true) {
            Column(Modifier.fillMaxWidth().heightIn(max = 640.dp).verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Engine error report", color = MagicPalette.parchment, style = SfText.headline())
                Text("Only the latest engine error report and this app's recent crash and ANR summaries are kept on this phone, " +
                    "excluded from backups. Error text may contain private card information. Nothing is uploaded automatically; " +
                    "review it before sharing.", color = MagicPalette.parchment, style = SfText.footnote())
                store.errorMessage?.let { Text(it, color = Color(1f, 0.45f, 0.4f), style = SfText.footnote()) }
                val report = store.report
                if (report != null) {
                    Text(if (store.isHistorical) "Saved report from an earlier session" else "Latest local incident",
                        color = MagicPalette.parchment, style = SfText.headline())
                    IosTextButton("Share report", {
                        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, report) }
                        runCatching { context.startActivity(Intent.createChooser(send, "Share report")) }
                    }, color = BrandTheme.ember, bold = true)
                }
                if (report != null || store.errorMessage != null) {
                    IosTextButton("Delete saved report", { confirmDelete = true }, color = Color(1f, 0.27f, 0.23f))
                }
                if (report != null) Text(report, color = MagicPalette.parchment, style = SfText.caption(design = SfDesign.MONOSPACED))
                else if (store.errorMessage == null) Text("No engine exception has been captured yet. Try starting the match again, then return here if it stops.",
                    color = MagicPalette.parchment, style = SfText.footnote())
                IosTextButton("Done", { open = false }, color = BrandTheme.ember, bold = true)
            }
        }
    }
    if (confirmDelete) {
        ConfirmationDialog("Delete the local engine report?", "This removes the saved report and its in-memory copy. Reports you already shared are not removed.",
            listOf(ConfirmationAction("Delete report", destructive = true) {
                scope.launch {
                    try { store.clear { setup.clearDiagnostics() } }
                    catch (error: Exception) { store.errorMessage = "Could not delete the local engine report: ${error.message}" }
                }
            })) { confirmDelete = false }
    }
}
