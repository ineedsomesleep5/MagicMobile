package io.magicmobile.android.game

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * One game's performance record (GamePerformanceEntry in PerformanceAwareness.swift; docs/LIGHTER_ENGINE_PLAN.md step 2): memory
 * peak, lowest headroom, hottest thermal state on iOS's scale (0 nominal, 1 fair, 2 serious, 3 critical), hot minutes and memory
 * warnings. Kept on the phone only and shared from Diagnostics to compare builds.
 */
@Serializable
data class GamePerformanceEntry(
    val started: Long, val mode: String, val aiSkill: Int? = null, val minutes: Double = 0.0, val turns: Int = 0,
    val peakMemoryMB: Int = 0, val lowestAvailableMB: Int? = null, val hottest: Int = 0, val hotMinutes: Double = 0.0,
    val memoryWarnings: Int = 0, val lastSample: Long? = null,
    /** The state at the first reading: a game that began warm didn't heat the phone by itself. */
    val startThermal: Int? = null,
    /** On a charger at any reading (charging heats a phone by itself). */
    val charging: Boolean = false,
    /** Battery saver at any reading. */
    val lowPower: Boolean = false,
) {
    /** Takes one reading. Time since the previous reading counts as hot when this reading is hot. */
    fun absorb(now: Long, memoryMB: Int?, availableMB: Int?, thermal: Int, onCharger: Boolean = false, lowPowerMode: Boolean = false): GamePerformanceEntry = copy(
        startThermal = startThermal ?: thermal,
        charging = charging || onCharger,
        lowPower = lowPower || lowPowerMode,
        peakMemoryMB = maxOf(peakMemoryMB, memoryMB ?: 0),
        lowestAvailableMB = availableMB?.let { minOf(lowestAvailableMB ?: it, it) } ?: lowestAvailableMB,
        hottest = maxOf(hottest, thermal),
        hotMinutes = hotMinutes + if (lastSample != null && thermal >= HOT) maxOf(0L, now - lastSample) / 60_000.0 else 0.0,
        lastSample = now)

    val line: String get() {
        val day = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss").format(Instant.ofEpochMilli(started).atZone(ZoneId.systemDefault()))
        val parts = mutableListOf("$day $mode" + (aiSkill?.let { " skill $it" } ?: ""), "%.0f min, %d turns".format(minutes, turns), "peak $peakMemoryMB MB")
        lowestAvailableMB?.let { parts += "lowest headroom $it MB" }
        parts += "hottest ${THERMAL_NAMES[hottest.coerceIn(0, 3)]}"
        if (hotMinutes >= 0.5) parts += "hot %.0f min".format(hotMinutes)
        startThermal?.takeIf { it > 0 }?.let { parts += "began ${THERMAL_NAMES[it.coerceAtMost(3)]}" }
        if (charging) parts += "charging"
        if (lowPower) parts += "low power"
        if (memoryWarnings > 0) parts += "$memoryWarnings memory warning" + if (memoryWarnings == 1) "" else "s"
        return parts.joinToString(", ")
    }

    companion object {
        const val HOT = 2
        val THERMAL_NAMES = listOf("nominal", "fair", "serious", "critical")

        /** Android's PowerManager thermal status on iOS's four-step scale: severe is iOS's serious. */
        fun thermalLevel(androidStatus: Int): Int = when {
            androidStatus <= 0 -> 0
            androidStatus <= 2 -> 1
            androidStatus == 3 -> 2
            else -> 3
        }
    }
}

/** The last twenty records, newest last, as JSON (GamePerformanceLog in Swift). */
object GamePerformanceLog {
    const val LIMIT = 20
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val serializer = ListSerializer(GamePerformanceEntry.serializer())

    fun decode(text: String?): List<GamePerformanceEntry> = text?.let { runCatching { json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()

    /** Adds a finished game (its minutes from `now`) and keeps the last twenty. */
    fun append(existing: List<GamePerformanceEntry>, entry: GamePerformanceEntry, now: Long): String =
        json.encodeToString(serializer, (existing + entry.copy(minutes = maxOf(0L, now - entry.started) / 60_000.0, lastSample = null)).takeLast(LIMIT))

    /** The Diagnostics text, newest first, or null before the first game. */
    fun section(entries: List<GamePerformanceEntry>, appVersion: String): String? =
        if (entries.isEmpty()) null
        else (listOf("MagicMobile game performance (${entries.size} games, newest first), app $appVersion") + entries.reversed().map { it.line }).joinToString("\n")
}
