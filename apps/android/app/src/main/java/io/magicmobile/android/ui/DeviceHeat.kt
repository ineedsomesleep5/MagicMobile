package io.magicmobile.android.ui

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.GamePerformanceEntry
import io.magicmobile.android.game.GamePerformanceLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Heat and memory awareness (PerformanceAwareness.swift; docs/LIGHTER_ENGINE_PLAN.md step 2, app only). While the phone reports
 * heat, board effects draw at half rate; memory trims free the artwork cache (MainActivity); every game keeps a small performance
 * record for Diagnostics. While hot, games the engine runs on this phone (not ranked, not online) ask the AI to think for less time
 * (OnDeviceSession.devicePaceHot, engine release C).
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

/** The per-game performance log (GamePerformanceLog in Swift), kept in the app's preferences, never uploaded. */
object GamePerformanceRecorder {
    private const val KEY = "magicmobile.performance.games"
    private const val TAG = "MagicMobilePerf"
    private var app: Context? = null
    private var current: GamePerformanceEntry? = null
    private var sampler: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun init(context: Context) { app = context.applicationContext }

    private val prefs get() = app?.getSharedPreferences("magicmobile.performance", Context.MODE_PRIVATE)

    val entries: List<GamePerformanceEntry> get() = GamePerformanceLog.decode(prefs?.getString(KEY, null))

    fun begin(mode: String, aiSkill: Int?) {
        end()
        current = GamePerformanceEntry(System.currentTimeMillis(), mode, aiSkill)
        sample()
        sampler = scope.launch { while (isActive) { delay(10_000); sample() } }
    }

    /** One reading: the app's whole memory (the engine runs in this process), the system's headroom and the thermal state. */
    fun sample() {
        val entry = current ?: return
        val context = app ?: return
        val pssMB = runCatching { Debug.MemoryInfo().also(Debug::getMemoryInfo).totalPss / 1024 }.getOrNull()
        val availableMB = runCatching {
            ActivityManager.MemoryInfo().also { context.getSystemService(ActivityManager::class.java)?.getMemoryInfo(it) }.availMem / 1_048_576
        }.getOrNull()?.toInt()?.takeIf { it > 0 }
        current = entry.absorb(System.currentTimeMillis(), pssMB, availableMB, DeviceHeat.level)
    }

    fun noteTurn(turn: Int?) { if (turn != null) current = current?.let { it.copy(turns = maxOf(it.turns, turn)) } }

    fun noteMemoryWarning() {
        current = current?.let { it.copy(memoryWarnings = it.memoryWarnings + 1) }
        Log.i(TAG, "memory trim during a game")
    }

    fun end() {
        sampler?.cancel(); sampler = null
        val entry = current ?: return
        current = null
        val prefs = prefs ?: return
        prefs.edit().putString(KEY, GamePerformanceLog.append(entries, entry, System.currentTimeMillis())).apply()
        Log.i(TAG, "game performance: ${entries.lastOrNull()?.line}")
    }
}
