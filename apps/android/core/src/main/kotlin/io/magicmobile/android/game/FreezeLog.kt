package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import java.time.Instant
import java.util.Locale

/**
 * When a game that still responds has stopped moving (docs/FREEZE_LOG.md; iOS FreezeRules). Inputs are seconds; the
 * shared cases are parity/freeze-cases.json.
 */
object FreezeRules {
    const val HANG = "hang"
    const val ANSWER_NOT_ACCEPTED = "answer-not-accepted"
    const val ENGINE_QUIET = "engine-quiet"
    const val REPORTED = "reported"

    const val HANG_SECONDS = 2.0
    const val ANSWER_SECONDS = 20.0
    /** AI turns run up to about 70 s; a person at the table may think longer. */
    const val QUIET_SOLO_SECONDS = 120.0
    const val QUIET_WITH_PEOPLE_SECONDS = 180.0
    /**
     * A hang this long is a freeze worth asking about; shorter hitches stay in the log for the report sheet (Danny,
     * 2026-10-26: "The last game froze" at every launch after games that never froze).
     */
    const val ASK_HANG_SECONDS = 8.0
    /** The launch question asks at most once in this long. */
    const val ASK_INTERVAL_SECONDS = 3 * 86_400.0

    /** Waiting on you, or on another person at the table who is thinking, is not a freeze. */
    fun stall(inGame: Boolean, over: Boolean, waitingOnYou: Boolean, answerPendingSeconds: Double?, quietSeconds: Double,
              withPeople: Boolean, waitingOnPerson: Boolean = false): String? {
        if (!inGame || over) return null
        if (answerPendingSeconds != null && answerPendingSeconds >= ANSWER_SECONDS) return ANSWER_NOT_ACCEPTED
        if (waitingOnYou || waitingOnPerson) return null
        return if (quietSeconds >= (if (withPeople) QUIET_WITH_PEOPLE_SECONDS else QUIET_SOLO_SECONDS)) ENGINE_QUIET else null
    }

    /** Whether the launch question asks about an incident: a stall, or a hang of [ASK_HANG_SECONDS] or more. */
    fun worthAsking(kind: String, durationSeconds: Double?): Boolean = when (kind) {
        ANSWER_NOT_ACCEPTED, ENGINE_QUIET -> true
        HANG -> (durationSeconds ?: 0.0) >= ASK_HANG_SECONDS
        else -> false
    }

    /** Whether the launch question may ask now, [secondsSinceAsked] after it last asked (null: never). */
    fun mayAsk(secondsSinceAsked: Double?): Boolean = secondsSinceAsked == null || secondsSinceAsked < 0 || secondsSinceAsked >= ASK_INTERVAL_SECONDS
}

/**
 * One game's stall watch: when an answer went out, when the game last changed, and whether this episode was recorded.
 * Progress (a new snapshot, or the answer landing) starts a new episode, so each stall is recorded once.
 */
class FreezeStallTracker(now: Double = 0.0) {
    var answerSentAt: Double? = null; private set
    var changedAt: Double = now; private set
    private var recorded = false

    fun restart(now: Double) { answerSentAt = null; changedAt = now; recorded = false }
    fun answerSent(now: Double) { if (answerSentAt == null) answerSentAt = now }
    fun answerLanded() { if (answerSentAt != null) { answerSentAt = null; recorded = false } }
    fun changed(now: Double) { changedAt = now; recorded = false }
    /** Back from the background, where nothing polls: the clocks start again, an answer still counts as pending. */
    fun resumed(now: Double) { changedAt = now; if (answerSentAt != null) answerSentAt = now }

    fun answerPendingSeconds(now: Double): Double? = answerSentAt?.let { now - it }
    fun quietSeconds(now: Double): Double = now - changedAt

    /** The stall's kind the first time this episode qualifies; null otherwise. */
    fun check(now: Double, inGame: Boolean, over: Boolean, waitingOnYou: Boolean, withPeople: Boolean, waitingOnPerson: Boolean = false): String? {
        val kind = FreezeRules.stall(inGame, over, waitingOnYou, answerPendingSeconds(now), quietSeconds(now), withPeople, waitingOnPerson) ?: return null
        if (recorded) return null
        recorded = true
        return kind
    }
}

/** The last [capacity] breadcrumbs, "+12.3s text" from process start. Any thread. */
class FreezeBreadcrumbs(val capacity: Int = CAPACITY) {
    private val lines = ArrayDeque<String>()

    @Synchronized fun add(secondsSinceStart: Double, text: String) {
        val line = "+${String.format(Locale.ROOT, "%.1f", secondsSinceStart)}s ${clean(text)}"
        if (lines.size >= capacity) lines.removeFirst()
        lines.addLast(line)
    }

    @Synchronized fun snapshot(): List<String> = lines.toList()

    companion object {
        const val CAPACITY = 80
        const val MAX_LINE = 200
        fun clean(text: String): String = text.map { if (Character.isISOControl(it)) ' ' else it }.joinToString("").trim().take(MAX_LINE)
    }
}

/** One recorded freeze. [context] is ordered label → value; [sent] once the developer has it; [declined] after Not now. */
data class FreezeIncident(
    val id: String, val kind: String, val atMillis: Long, val durationSeconds: Double? = null,
    val context: List<Pair<String, String>> = emptyList(), val breadcrumbs: List<String> = emptyList(),
    val sent: Boolean = false, val declined: Boolean = false,
) {
    fun json(): JsonObject = JsonObject(buildMap<String, JsonElement> {
        put("id", JsonPrimitive(id)); put("kind", JsonPrimitive(kind)); put("at", JsonPrimitive(atMillis))
        put("duration", durationSeconds?.let(::JsonPrimitive) ?: JsonNull)
        put("context", JsonArray(context.map { (label, value) -> JsonArray(listOf(JsonPrimitive(label), JsonPrimitive(value))) }))
        put("breadcrumbs", JsonArray(breadcrumbs.map(::JsonPrimitive)))
        put("sent", JsonPrimitive(sent)); put("declined", JsonPrimitive(declined))
    })

    companion object {
        fun parse(value: JsonElement): FreezeIncident? = runCatching {
            val fields = value.jsonObject
            FreezeIncident(fields["id"]!!.jsonPrimitive.content, fields["kind"]!!.jsonPrimitive.content, fields["at"]!!.jsonPrimitive.longOrNull!!,
                (fields["duration"] as? JsonPrimitive)?.doubleOrNull,
                fields["context"]?.jsonArray.orEmpty().map { row -> row.jsonArray.let { it[0].jsonPrimitive.content to it[1].jsonPrimitive.content } },
                fields["breadcrumbs"]?.jsonArray.orEmpty().map { it.jsonPrimitive.content }.takeLast(FreezeBreadcrumbs.CAPACITY),
                (fields["sent"] as? JsonPrimitive)?.booleanOrNull ?: false, (fields["declined"] as? JsonPrimitive)?.booleanOrNull ?: false)
        }.getOrNull()
    }
}

/** freeze-log.json in the diagnostics folder: the last [LIMIT] incidents, oldest first. Callers serialize access. */
class FreezeStore(private val directory: File) {
    private val file get() = File(directory, FILE_NAME)

    fun load(): List<FreezeIncident> = runCatching {
        if (!file.exists() || file.length() > MAX_BYTES) return emptyList()
        Json.parseToJsonElement(file.readText(Charsets.UTF_8)).jsonArray.mapNotNull(FreezeIncident::parse).takeLast(LIMIT)
    }.getOrDefault(emptyList())

    fun save(incidents: List<FreezeIncident>) {
        if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException("Could not create the diagnostics folder.")
        val temporary = File(directory, "$FILE_NAME.tmp")
        temporary.writeText(JsonArray(incidents.takeLast(LIMIT).map { it.json() }).toString(), Charsets.UTF_8)
        if (!temporary.renameTo(file)) throw IllegalStateException("Could not save the freeze log.")
    }

    /** Load, change and save; returns what was saved. */
    fun update(change: (List<FreezeIncident>) -> List<FreezeIncident>): List<FreezeIncident> =
        change(load()).takeLast(LIMIT).also(::save)

    fun clear() { if (file.exists() && !file.delete()) throw IllegalStateException("Could not delete the freeze log.") }

    companion object {
        const val FILE_NAME = "freeze-log.json"
        const val LIMIT = 5
        const val MAX_BYTES = 512 * 1024L
    }
}

/** The text a freeze report holds: what's sent with Send, and what the diagnostics sheet shows. */
object FreezeReport {
    /** mm_send_diagnostic takes up to 65,536 characters. */
    const val MAX_CHARACTERS = 65_000

    fun incident(incident: FreezeIncident): String = buildString {
        append("Freeze · ${incident.kind} · ${Instant.ofEpochMilli(incident.atMillis)}")
        if (incident.sent) append(" · sent")
        append('\n')
        if (incident.kind == FreezeRules.HANG) {
            append(incident.durationSeconds?.let { "Main thread stuck for ${String.format(Locale.ROOT, "%.1f", it)} s" }
                ?: "Main thread stuck; it had not recovered when this was saved").append('\n')
        }
        for ((label, value) in incident.context) append(label).append(": ").append(value).append('\n')
        append("Breadcrumbs (oldest first):")
        if (incident.breadcrumbs.isEmpty()) append(" none")
        for (line in incident.breadcrumbs) append("\n  ").append(line)
    }

    /** What Send uploads: the incident, then the phone's crash and ANR summaries, cut to [MAX_CHARACTERS]. */
    fun sent(incident: FreezeIncident, systemReports: String?): String =
        listOfNotNull("MagicMobile freeze report", incident(incident), systemReports).joinToString("\n\n").take(MAX_CHARACTERS)

    /** The diagnostics sheet's section, or null when nothing was recorded. */
    fun section(incidents: List<FreezeIncident>): String? {
        if (incidents.isEmpty()) return null
        return (listOf("Freeze log (${incidents.size}, newest last)") + incidents.map(::incident)).joinToString("\n\n")
    }
}
