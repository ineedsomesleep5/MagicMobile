package io.magicmobile.android.game

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * The app's CPU time so far, in milliseconds (CPUReading in Swift). The graphics chip's work isn't in it: the system doesn't say.
 * Board is the main thread, ai the engine's search threads, and the rest is game updates: polling, decoding, the engine's game thread.
 */
@Serializable
data class CPUReading(val total: Long = 0, val board: Long = 0, val ai: Long = 0) {
    val updates: Long get() = maxOf(0L, total - board - ai)
}

/** How a game looked (GameBoardNote in Swift). Android has no moving worlds yet, so it names neither table nor motion. */
@Serializable
data class GameBoardNote(val board: String, val table: String? = null, val motion: String? = null, val effects: String)

/** Reads the app's search threads out of /proc/self/task/<id>/stat, the way CPUMeter does on iOS. */
object ThreadCPU {
    fun isSearchThread(name: String): Boolean = name.startsWith("AI-")

    /** The thread's name and its CPU ticks from one stat line; null when the line isn't one. The name can hold spaces and brackets. */
    fun parse(stat: String): Pair<String, Long>? {
        val open = stat.indexOf('(')
        val close = stat.lastIndexOf(')')
        if (open < 0 || close < open) return null
        // After the name, utime and stime are fields 12 and 13 (state is field 1).
        val fields = stat.substring(close + 1).trim().split(' ')
        val user = fields.getOrNull(11)?.toLongOrNull() ?: return null
        val system = fields.getOrNull(12)?.toLongOrNull() ?: return null
        return stat.substring(open + 1, close) to user + system
    }
}

/**
 * One game's performance record (GamePerformanceEntry in PerformanceAwareness.swift; docs/LIGHTER_ENGINE_PLAN.md step 2): memory
 * peak, lowest headroom, hottest thermal state on iOS's scale (0 nominal, 1 fair, 2 serious, 3 critical), hot minutes, memory
 * warnings, CPU and how the game looked. Goes to the server once the game ends (docs/SERVER_CONTROLS.md "Heat reports").
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
    /** What the report needs. A record without an id, from an earlier build, is never sent. */
    val id: String? = null,
    val build: Int? = null,
    val setup: GameBoardNote? = null,
    /** Milliseconds the app was awake for: readings further apart than AWAKE_GAP had it in the background. */
    val activeMillis: Long = 0,
    val warmMinutes: Double = 0.0,
    val secondsToWarm: Double? = null,
    val secondsToHot: Double? = null,
    val cpu: CPUReading? = null,
    val lastCPU: CPUReading? = null,
    val frames: Int = 0,
    val slowFrames: Int = 0,
    val batteryStart: Int? = null,
    val batteryEnd: Int? = null,
    /** The battery's temperature in °C, which only Android tells. */
    val tempStart: Double? = null,
    val tempPeak: Double? = null,
    /** The app never got to end this game: it stopped at its last saved minute. */
    val interrupted: Boolean = false,
    /** The server has it, or refused it for good. */
    val sent: Boolean = false,
) {
    /** Takes one reading. Time since the previous reading counts as hot when this reading is hot. */
    fun absorb(now: Long, memoryMB: Int?, availableMB: Int?, thermal: Int, onCharger: Boolean = false, lowPowerMode: Boolean = false,
               cpu: CPUReading? = null, battery: Int? = null, temperature: Double? = null): GamePerformanceEntry = absorbLoad(now, thermal, cpu, battery, temperature).copy(
        startThermal = startThermal ?: thermal,
        charging = charging || onCharger,
        lowPower = lowPower || lowPowerMode,
        peakMemoryMB = maxOf(peakMemoryMB, memoryMB ?: 0),
        lowestAvailableMB = availableMB?.let { minOf(lowestAvailableMB ?: it, it) } ?: lowestAvailableMB,
        hottest = maxOf(hottest, thermal),
        hotMinutes = hotMinutes + if (lastSample != null && thermal >= HOT) maxOf(0L, now - lastSample) / 60_000.0 else 0.0,
        lastSample = now)

    /** What happened since the previous reading. */
    private fun absorbLoad(now: Long, thermal: Int, reading: CPUReading?, battery: Int?, temperature: Double?): GamePerformanceEntry {
        val gap = lastSample?.let { maxOf(0L, now - it) } ?: 0L
        val awake = gap <= AWAKE_GAP
        val active = activeMillis + if (awake) gap else 0L
        val used = if (awake && reading != null && lastCPU != null) (cpu ?: CPUReading()).let {
            CPUReading(it.total + maxOf(0L, reading.total - lastCPU.total), it.board + maxOf(0L, reading.board - lastCPU.board),
                it.ai + maxOf(0L, reading.ai - lastCPU.ai))
        } else cpu
        return copy(activeMillis = active, cpu = used, lastCPU = reading ?: lastCPU,
            warmMinutes = warmMinutes + if (awake && thermal >= WARM) gap / 60_000.0 else 0.0,
            secondsToWarm = secondsToWarm ?: if (thermal >= WARM) active / 1000.0 else null,
            secondsToHot = secondsToHot ?: if (thermal >= HOT) active / 1000.0 else null,
            batteryStart = batteryStart ?: battery, batteryEnd = battery ?: batteryEnd,
            tempStart = tempStart ?: temperature,
            tempPeak = temperature?.let { maxOf(tempPeak ?: it, it) } ?: tempPeak)
    }

    fun noteFrames(count: Int, slow: Int): GamePerformanceEntry = copy(frames = frames + count, slowFrames = slowFrames + slow)

    private val batteryUsed: Int? get() = if (batteryStart != null && batteryEnd != null && !charging) maxOf(0, batteryStart - batteryEnd) else null

    /** Percent of one core while the app was awake. */
    private fun percent(millis: Long): Double = if (activeMillis > 0) Math.round(millis * 1000.0 / activeMillis) / 10.0 else 0.0

    private val slowPercent: Double get() = Math.round(1000.0 * slowFrames / maxOf(frames, 1)) / 10.0

    /** mm_game_heat's parameters, or null for a record with nothing to say: one from an earlier build, or a game under a minute. */
    fun report(device: String, system: String): Map<String, JsonElement>? {
        if (id == null || build == null || activeMillis < SHORTEST) return null
        fun tenth(value: Double) = Math.round(value * 10) / 10.0
        val minutes = activeMillis / 60_000.0
        val stats = linkedMapOf<String, JsonElement>("minutes" to JsonPrimitive(tenth(minutes)), "turns" to JsonPrimitive(turns), "hottest" to JsonPrimitive(hottest),
            "hotMinutes" to JsonPrimitive(tenth(minOf(hotMinutes, minutes))), "warmMinutes" to JsonPrimitive(tenth(warmMinutes)),
            "peakMB" to JsonPrimitive(peakMemoryMB), "memoryWarnings" to JsonPrimitive(memoryWarnings), "charging" to JsonPrimitive(charging),
            "lowPower" to JsonPrimitive(lowPower), "interrupted" to JsonPrimitive(interrupted))
        startThermal?.let { stats["startThermal"] = JsonPrimitive(it) }
        secondsToWarm?.let { stats["secondsToWarm"] = JsonPrimitive(Math.round(it)) }
        secondsToHot?.let { stats["secondsToHot"] = JsonPrimitive(Math.round(it)) }
        lowestAvailableMB?.let { stats["lowestHeadroomMB"] = JsonPrimitive(it) }
        cpu?.let {
            stats["cpu"] = JsonPrimitive(percent(it.total))
            stats["cpuBoard"] = JsonPrimitive(percent(it.board))
            stats["cpuUpdates"] = JsonPrimitive(percent(it.updates))
            stats["cpuAI"] = JsonPrimitive(percent(it.ai))
        }
        if (frames > 0) stats["slowFrames"] = JsonPrimitive(slowPercent)
        batteryUsed?.let { stats["batteryUsed"] = JsonPrimitive(it) }
        tempStart?.let { stats["tempStart"] = JsonPrimitive(tenth(it)) }
        tempPeak?.let { stats["tempPeak"] = JsonPrimitive(tenth(it)) }
        val report = linkedMapOf<String, JsonElement>("p_client_id" to JsonPrimitive(id), "p_played_at" to JsonPrimitive(Instant.ofEpochMilli(started).toString()),
            "p_platform" to JsonPrimitive("android"), "p_build" to JsonPrimitive(build), "p_device" to JsonPrimitive(device.take(40)),
            "p_os" to JsonPrimitive(system.take(40)), "p_mode" to JsonPrimitive(mode), "p_stats" to JsonObject(stats))
        aiSkill?.let { report["p_ai_skill"] = JsonPrimitive(it) }
        setup?.let { note ->
            report["p_board"] = JsonPrimitive(note.board)
            report["p_effects"] = JsonPrimitive(note.effects)
            note.table?.let { report["p_table"] = JsonPrimitive(it) }
            note.motion?.let { report["p_motion"] = JsonPrimitive(it) }
        }
        return report
    }

    val line: String get() {
        val day = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss").format(Instant.ofEpochMilli(started).atZone(ZoneId.systemDefault()))
        val parts = mutableListOf("$day $mode" + (aiSkill?.let { " skill $it" } ?: "") + (build?.let { " build $it" } ?: ""), "%.0f min, %d turns".format(minutes, turns), "peak $peakMemoryMB MB")
        lowestAvailableMB?.let { parts += "lowest headroom $it MB" }
        parts += "hottest ${THERMAL_NAMES[hottest.coerceIn(0, 3)]}"
        if (hotMinutes >= 0.5) parts += "hot %.0f min".format(hotMinutes)
        startThermal?.takeIf { it > 0 }?.let { parts += "began ${THERMAL_NAMES[it.coerceAtMost(3)]}" }
        if (charging) parts += "charging"
        if (lowPower) parts += "low power"
        if (memoryWarnings > 0) parts += "$memoryWarnings memory warning" + if (memoryWarnings == 1) "" else "s"
        cpu?.let { parts += "CPU %.0f%% (board %.0f, updates %.0f, AI %.0f)".format(percent(it.total), percent(it.board), percent(it.updates), percent(it.ai)) }
        if (frames > 0) parts += "%.1f%% slow frames".format(slowPercent)
        batteryUsed?.let { parts += "battery $it%" }
        tempPeak?.let { parts += "battery peak %.0f°C".format(it) }
        if (interrupted) parts += "cut short"
        return parts.joinToString(", ")
    }

    companion object {
        const val WARM = 1
        const val HOT = 2
        const val AWAKE_GAP = 30_000L
        const val SHORTEST = 60_000L
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
        json.encodeToString(serializer, (existing + entry.copy(minutes = maxOf(0L, now - entry.started) / 60_000.0, lastSample = null, lastCPU = null)).takeLast(LIMIT))

    /** A game the app never got to end: it counts up to its last saved minute. */
    fun interrupted(entry: GamePerformanceEntry): GamePerformanceEntry =
        entry.copy(interrupted = true, minutes = entry.activeMillis / 60_000.0, lastSample = null, lastCPU = null)

    fun encode(entry: GamePerformanceEntry): String = json.encodeToString(GamePerformanceEntry.serializer(), entry)

    fun decodeRunning(text: String?): GamePerformanceEntry? =
        text?.let { runCatching { json.decodeFromString(GamePerformanceEntry.serializer(), it) }.getOrNull() }

    fun markSent(entries: List<GamePerformanceEntry>, id: String?): String =
        json.encodeToString(serializer, entries.map { if (it.id == id) it.copy(sent = true) else it })

    /** The Diagnostics text, newest first, or null before the first game. */
    fun section(entries: List<GamePerformanceEntry>, appVersion: String): String? =
        if (entries.isEmpty()) null
        else (listOf("MagicMobile game performance (${entries.size} games, newest first), app $appVersion") + entries.reversed().map { it.line }).joinToString("\n")
}
