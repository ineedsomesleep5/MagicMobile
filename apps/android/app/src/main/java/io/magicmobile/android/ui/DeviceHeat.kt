package io.magicmobile.android.ui

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.BoardActivity
import io.magicmobile.android.game.CPUReading
import io.magicmobile.android.game.GameBoardNote
import io.magicmobile.android.game.GamePerformanceEntry
import io.magicmobile.android.game.GamePerformanceLog
import io.magicmobile.android.game.GameUploadResult
import io.magicmobile.android.game.ThreadCPU
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.util.UUID

/**
 * Heat and memory awareness (PerformanceAwareness.swift; docs/LIGHTER_ENGINE_PLAN.md step 2, app only). While the phone reports
 * heat, board effects draw at half rate; memory trims free the artwork cache (MainActivity); every game keeps a small performance
 * record that goes to the server once it ends (docs/SERVER_CONTROLS.md "Heat reports"). While hot, games the engine runs on this
 * phone (not ranked, not online) ask the AI to think for less time (OnDeviceSession.devicePaceHot, engine release C).
 */
object DeviceHeat {
    /** iOS's scale: 0 nominal, 1 fair, 2 serious, 3 critical (GamePerformanceEntry.thermalLevel). */
    var level by mutableIntStateOf(0)
        private set
    val isHot: Boolean get() = level >= GamePerformanceEntry.HOT
    private var listener: Any? = null

    fun init(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || listener != null) return
        val power = context.getSystemService(PowerManager::class.java) ?: return
        level = GamePerformanceEntry.thermalLevel(power.currentThermalStatus)
        val callback = PowerManager.OnThermalStatusChangedListener { status ->
            level = GamePerformanceEntry.thermalLevel(status)
            GamePerformanceRecorder.sample()
        }
        power.addThermalStatusListener(context.mainExecutor, callback)
        listener = callback
    }
}

/** Splits the app's CPU time by what the threads do (CPUMeter in Swift). The engine names its search threads AI-SIM-…. */
private class CPUMeter {
    private val tickMillis = runCatching { 1000.0 / android.system.Os.sysconf(android.system.OsConstants._SC_CLK_TCK) }.getOrDefault(10.0)
    private var searchThreads = emptyMap<String, Long>()
    private var ai = 0L
    private var read = false

    /** Called on the main thread, for the board's share. The thread files are read on a worker just before (`searchTicks`). */
    fun reading(ticks: Map<String, Long>): CPUReading {
        if (read) for ((thread, count) in ticks) ai += Math.round(maxOf(0L, count - (searchThreads[thread] ?: 0L)) * tickMillis)
        searchThreads = ticks
        read = true
        return CPUReading(Process.getElapsedCpuTime(), SystemClock.currentThreadTimeMillis(), ai)
    }

    fun searchTicks(): Map<String, Long> = runCatching {
        File("/proc/self/task").listFiles().orEmpty().mapNotNull { task ->
            val (name, ticks) = runCatching { ThreadCPU.parse(File(task, "stat").readText()) }.getOrNull() ?: return@mapNotNull null
            if (ThreadCPU.isSearchThread(name)) task.name to ticks else null
        }.toMap()
    }.getOrDefault(emptyMap())
}

/** Times the board's frames for a few seconds, a minute apart and never while it rests (BoardFrameSampler in Swift). */
private class FrameSampler(private val context: Context) {
    private var callback: Choreographer.FrameCallback? = null

    fun run(seconds: Int, done: (frames: Int, slow: Int) -> Unit) {
        if (callback != null) return
        val rate = runCatching { context.getSystemService(android.hardware.display.DisplayManager::class.java)?.getDisplay(android.view.Display.DEFAULT_DISPLAY)?.refreshRate }.getOrNull() ?: 60f
        val frame = 1_000_000_000L / maxOf(rate, 1f).toLong()
        var last = 0L; var frames = 0; var slow = 0; var until = 0L
        val tick = object : Choreographer.FrameCallback {
            override fun doFrame(now: Long) {
                if (callback !== this) return
                if (last == 0L) until = now + seconds * 1_000_000_000L
                else { frames++; if (now - last > frame * 3 / 2) slow++ }
                last = now
                if (now >= until) { callback = null; done(frames, slow) } else Choreographer.getInstance().postFrameCallback(this)
            }
        }
        callback = tick
        Choreographer.getInstance().postFrameCallback(tick)
    }

    fun stop() { callback = null }
}

/** The per-game performance log (GamePerformanceLog in Swift), kept in the app's preferences. Each game goes to the server once it ends. */
object GamePerformanceRecorder {
    private const val KEY = "magicmobile.performance.games"
    /** The game running now, saved each minute, so one the app never got to end (heat, memory, a force quit) still counts. */
    private const val RUNNING_KEY = "magicmobile.performance.running"
    private const val TAG = "MagicMobilePerf"
    private var app: Context? = null
    private var current: GamePerformanceEntry? = null
    private var sampler: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val meter = CPUMeter()
    private var frames: FrameSampler? = null
    private var boardNote: GameBoardNote? = null
    private var flushing = false

    fun init(context: Context) {
        app = context.applicationContext
        frames = FrameSampler(context.applicationContext)
    }

    private val prefs get() = app?.getSharedPreferences("magicmobile.performance", Context.MODE_PRIVATE)

    val entries: List<GamePerformanceEntry> get() = GamePerformanceLog.decode(prefs?.getString(KEY, null))

    fun begin(mode: String, aiSkill: Int?) {
        end()
        recoverInterrupted()
        current = GamePerformanceEntry(System.currentTimeMillis(), mode, aiSkill, id = UUID.randomUUID().toString(), build = BuildConfig.RELEASE_BUILD)
        sampler = scope.launch {
            var tick = 0
            while (isActive) {
                sample(withContext(Dispatchers.IO) { meter.searchTicks() })
                delay(10_000)
                if (++tick % 6 == 0) minuteMark()
            }
        }
    }

    /** One reading: the app's whole memory (the engine runs in this process), the system's headroom and the thermal state. */
    fun sample(searchTicks: Map<String, Long>? = null) {
        val entry = current ?: return
        val context = app ?: return
        val pssMB = runCatching { Debug.MemoryInfo().also(Debug::getMemoryInfo).totalPss / 1024 }.getOrNull()
        val availableMB = runCatching {
            ActivityManager.MemoryInfo().also { context.getSystemService(ActivityManager::class.java)?.getMemoryInfo(it) }.availMem / 1_048_576
        }.getOrNull()?.toInt()?.takeIf { it > 0 }
        // The battery broadcast is sticky: asking for it with no receiver reads the last one and needs no permission.
        val battery = runCatching { context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) }.getOrNull()
        val onCharger = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val tenths = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val lowPowerMode = runCatching { context.getSystemService(PowerManager::class.java)?.isPowerSaveMode == true }.getOrDefault(false)
        current = entry.copy(setup = boardNote ?: entry.setup).absorb(System.currentTimeMillis(), pssMB, availableMB, DeviceHeat.level, onCharger, lowPowerMode,
            cpu = searchTicks?.let(meter::reading), battery = if (level >= 0 && scale > 0) level * 100 / scale else null,
            temperature = tenths.takeIf { it != Int.MIN_VALUE }?.let { it / 10.0 })
    }

    /** The board on screen. It can arrive before `begin`. */
    fun noteBoard(note: GameBoardNote) { boardNote = note }

    /** Once a minute: keeps the running game safe, and times the board's frames unless it's resting. */
    private fun minuteMark() {
        current?.let { prefs?.edit()?.putString(RUNNING_KEY, GamePerformanceLog.encode(it))?.apply() }
        if (!BoardActivity.idle) frames?.run(3) { count, slow -> current = current?.noteFrames(count, slow) }
    }

    fun noteTurn(turn: Int?) { if (turn != null) current = current?.let { it.copy(turns = maxOf(it.turns, turn)) } }

    fun noteMemoryWarning() {
        current = current?.let { it.copy(memoryWarnings = it.memoryWarnings + 1) }
        Log.i(TAG, "memory trim during a game")
    }

    fun end() {
        sampler?.cancel(); sampler = null
        frames?.stop()
        if (current == null) return
        sample(meter.searchTicks())
        val entry = current ?: return
        current = null
        boardNote = null
        val prefs = prefs ?: return
        prefs.edit().remove(RUNNING_KEY).putString(KEY, GamePerformanceLog.append(entries, entry, System.currentTimeMillis())).apply()
        Log.i(TAG, "game performance: ${entries.lastOrNull()?.line}")
    }

    /** A game the app never got to end counts up to its last saved minute. */
    private fun recoverInterrupted() {
        val prefs = prefs ?: return
        if (current != null) return
        val running = prefs.getString(RUNNING_KEY, null) ?: return
        val edit = prefs.edit().remove(RUNNING_KEY)
        GamePerformanceLog.decodeRunning(running)?.let { entry ->
            val cut = GamePerformanceLog.interrupted(entry)
            edit.putString(KEY, GamePerformanceLog.append(entries, cut, cut.started + cut.activeMillis))
        }
        edit.apply()
    }

    /** Sends every finished game the server doesn't have, oldest first, and stops at the first that can't go for now. */
    suspend fun flush(send: suspend (Map<String, JsonElement>) -> GameUploadResult) {
        if (flushing) return
        flushing = true
        try {
            recoverInterrupted()
            val device = "${Build.MANUFACTURER} ${Build.MODEL}"
            for (entry in entries.filter { it.id != null && !it.sent }) {
                entry.report(device, Build.VERSION.RELEASE.orEmpty())?.let { report ->
                    when (send(report)) {
                        GameUploadResult.SENT, GameUploadResult.REJECTED -> Unit
                        else -> return
                    }
                }
                prefs?.edit()?.putString(KEY, GamePerformanceLog.markSent(entries, entry.id))?.apply()
            }
        } finally { flushing = false }
    }
}
