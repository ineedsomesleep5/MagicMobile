package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * The online turn timer (port of TurnClock.swift; shared cases in parity/turn-clock-cases.json).
 *
 * Phone-hosted tables only. The host runs one clock for every human seat: each decision the
 * engine asks a player gets [decision] seconds, and the rope burns through the last [rope].
 * When a decision runs out, the host answers it the way passing would (pass priority, finish
 * declaring, cancel a payment or an optional target); a question with no such answer gets
 * [grace] more seconds instead. Each timeout is a strike, a decision the player answers
 * themselves clears them, and the [strikesToForfeit]-th straight timeout concedes the seat.
 * All times are seconds of the host's uptime clock.
 */
data class TurnClockRules(
    val decision: Double = 60.0,
    val rope: Double = 20.0,
    val grace: Double = 20.0,
    val strikesToForfeit: Int = 3,
    /** A paused clock comes back with at least this long, so nobody returns to an instant timeout. */
    val resumeFloor: Double = 10.0,
) {
    companion object { val ONLINE = TurnClockRules() }
}

data class TurnClockPrompt(val id: String, val revision: Long)

enum class TurnClockTimeout(val wire: String) { ANSWER("answer"), GRACE("grace"), FORFEIT("forfeit") }

/** One seat's clock as shown on every phone. */
data class TurnClockEntry(val seat: String, val remaining: Double, val limit: Double, val strikes: Int)

class TurnClock(val rules: TurnClockRules = TurnClockRules.ONLINE) {
    private data class Running(val prompt: TurnClockPrompt, var deadline: Double, var limit: Double,
                               var frozen: Double?, var handled: Boolean = false)

    private val running = sortedMapOf<String, Running>()
    private val strikes = HashMap<String, Int>()
    private val answeredByClock = HashMap<String, TurnClockPrompt>()
    var paused = false
        private set

    fun strikes(seat: String): Int = strikes[seat] ?: 0

    /**
     * The seat's open question as the host's latest poll shows it, or null (none, or already answered).
     * Returns true when the clocks on screen changed.
     */
    fun observe(seat: String, prompt: TurnClockPrompt?, now: Double): Boolean {
        val current = running[seat]
        if (current != null && current.prompt == prompt) return false
        if (current == null && prompt == null) return false
        if (current != null) {
            // The player moved on by themselves: their timeouts no longer run in a row.
            if (answeredByClock[seat] != current.prompt) strikes.remove(seat)
            answeredByClock.remove(seat)
        }
        if (prompt == null) running.remove(seat)
        else running[seat] = Running(prompt, now + rules.decision, rules.decision, if (paused) rules.decision else null)
        return true
    }

    /** Pauses while any phone is away or the table is still rolling for first player. */
    fun setPaused(value: Boolean, now: Double): Boolean {
        if (value == paused) return false
        paused = value
        for (clock in running.values) {
            if (value) clock.frozen = max(0.0, clock.deadline - now)
            else { clock.deadline = now + max(clock.frozen ?: 0.0, min(rules.resumeFloor, clock.limit)); clock.frozen = null }
        }
        return true
    }

    /** Seats whose current decision ran out, in seat order. */
    fun expired(now: Double): List<Pair<String, TurnClockPrompt>> =
        if (paused) emptyList()
        else running.filter { !it.value.handled && now >= it.value.deadline }.map { it.key to it.value.prompt }

    /**
     * Records a timeout on [prompt] and says what the host does about it. Null when the
     * seat has moved on since. [hasDefault]: the question has a pass-like answer ([defaultAnswer]).
     */
    fun timeout(seat: String, prompt: TurnClockPrompt, hasDefault: Boolean, now: Double): TurnClockTimeout? {
        val clock = running[seat]?.takeIf { it.prompt == prompt && !it.handled } ?: return null
        val count = strikes(seat) + 1
        strikes[seat] = count
        return when {
            count >= rules.strikesToForfeit -> { clock.handled = true; TurnClockTimeout.FORFEIT }
            hasDefault -> { clock.handled = true; answeredByClock[seat] = prompt; TurnClockTimeout.ANSWER }
            else -> { clock.deadline = now + rules.grace; clock.limit = rules.grace; TurnClockTimeout.GRACE }
        }
    }

    /** The host's answer did not land (the engine refused it): the decision gets a grace period instead. */
    fun answerFailed(seat: String, prompt: TurnClockPrompt, now: Double) {
        val clock = running[seat]?.takeIf { it.prompt == prompt } ?: return
        clock.handled = false; clock.deadline = now + rules.grace; clock.limit = rules.grace
        answeredByClock.remove(seat)
    }

    fun clear() { running.clear(); strikes.clear(); answeredByClock.clear(); paused = false }

    fun entries(now: Double): List<TurnClockEntry> = running.filter { !it.value.handled }.map { (seat, clock) ->
        TurnClockEntry(seat, clock.frozen ?: max(0.0, clock.deadline - now), clock.limit, strikes(seat))
    }

    companion object {
        /**
         * The answer passing would give, or null when the question has none: pass priority,
         * finish declaring attackers or blockers, cancel a mana payment, or skip an optional
         * target or ability. Everything else (mulligans, required targets, choices) gets grace.
         */
        fun defaultAnswer(prompt: EnginePrompt): J? {
            if ("boolean" !in prompt.responseTypes) return null
            return when (prompt.kind) {
                "SELECT" -> if (prompt.payload["selectMode"].string in setOf("priority", "attackers", "blockers"))
                    EnginePrompt.answer("boolean", JsonPrimitive(true)) else null
                "PLAY_MANA" -> EnginePrompt.answer("boolean", JsonPrimitive(false))
                "PICK_TARGET", "CHOOSE_ABILITY", "PICK_ABILITY" ->
                    if (prompt.payload["required"].bool == false) EnginePrompt.answer("boolean", JsonPrimitive(false)) else null
                else -> null
            }
        }

        /** The clock a seat's poll implies: an unanswered question, or none. */
        fun prompt(poll: MatchPoll): TurnClockPrompt? =
            poll.prompt?.takeIf { !it.submitted && poll.phase == "running" }?.let { TurnClockPrompt(it.id, it.revision) }
    }
}

/**
 * The host's `clock` packet: `{"type":"clock","epoch":…,"paused":bool,"clocks":[{"seat","remainingMillis","limitMillis","strikes"}]}`.
 * Remaining time travels instead of a deadline, so the phones' clocks never need to agree.
 */
object TurnClockWire {
    const val MAX_LIMIT_MILLIS = 120_000L
    private val seatPattern = Regex("player[1-4]")

    fun packet(epoch: String, paused: Boolean, entries: List<TurnClockEntry>): J = jsonObject(
        "type" to JsonPrimitive("clock"), "epoch" to JsonPrimitive(epoch), "paused" to JsonPrimitive(paused),
        "clocks" to JsonArray(entries.map {
            jsonObject("seat" to JsonPrimitive(it.seat), "remainingMillis" to JsonPrimitive((it.remaining * 1000).roundToLong()),
                "limitMillis" to JsonPrimitive((it.limit * 1000).roundToLong()), "strikes" to JsonPrimitive(it.strikes.toLong()))
        }))

    /** Strict: exactly these keys, at most four seats, each once, with sane times. */
    fun parse(value: J): Pair<Boolean, List<TurnClockEntry>> {
        val fields = value.obj
        val paused = fields?.get("paused").bool
        val clocks = fields?.get("clocks").array
        if (fields == null || fields.keys != setOf("type", "epoch", "paused", "clocks") || fields["type"].string != "clock" ||
            paused == null || clocks == null || clocks.size > 4) throw EngineError.InvalidMessage("Invalid turn clock.")
        val entries = clocks.map { item ->
            val entry = item.obj
            val seat = entry?.get("seat").string
            val remaining = entry?.get("remainingMillis").integer
            val limit = entry?.get("limitMillis").integer
            val strikes = entry?.get("strikes").integer
            if (entry == null || entry.keys != setOf("seat", "remainingMillis", "limitMillis", "strikes") || seat == null ||
                !seatPattern.matches(seat) || limit == null || limit !in 1..MAX_LIMIT_MILLIS || remaining == null ||
                remaining !in 0..limit || strikes == null || strikes !in 0..3) throw EngineError.InvalidMessage("Invalid turn clock.")
            TurnClockEntry(seat, remaining / 1000.0, limit / 1000.0, strikes.toInt())
        }
        if (entries.map { it.seat }.toSet().size != entries.size) throw EngineError.InvalidMessage("Invalid turn clock.")
        return paused to entries
    }
}

/** What a phone shows: the clocks with deadlines on its own uptime clock. */
data class TurnClockBoard(val paused: Boolean = false, val clocks: List<Clock> = emptyList()) {
    data class Clock(val seat: String, val deadline: Double, val limit: Double, val strikes: Int)
    data class Rope(val seat: String, val isLocal: Boolean, val remaining: Double, val fraction: Double, val strikes: Int)

    /**
     * The one rope to burn: the local seat's own decision first, otherwise the clock that runs out
     * soonest. Null while paused or until a clock is inside its last [TurnClockRules.rope] seconds.
     */
    fun rope(localSeat: String?, now: Double, rules: TurnClockRules = TurnClockRules.ONLINE): Rope? {
        if (paused) return null
        val pick = clocks.firstOrNull { it.seat == localSeat } ?: clocks.minByOrNull { it.deadline } ?: return null
        val remaining = max(0.0, pick.deadline - now)
        val window = min(rules.rope, pick.limit)
        if (remaining > window || remaining <= 0.0) return null
        return Rope(pick.seat, pick.seat == localSeat, remaining, remaining / window, pick.strikes)
    }

    /** Seconds until [rope] could first return something, or null when nothing will (paused, no clocks). */
    fun secondsUntilRope(localSeat: String?, now: Double, rules: TurnClockRules = TurnClockRules.ONLINE): Double? {
        if (paused) return null
        val pick = clocks.firstOrNull { it.seat == localSeat } ?: clocks.minByOrNull { it.deadline } ?: return null
        val remaining = pick.deadline - now
        if (remaining <= 0.0) return null
        return max(0.0, remaining - min(rules.rope, pick.limit))
    }

    companion object {
        fun from(paused: Boolean, entries: List<TurnClockEntry>, now: Double) =
            TurnClockBoard(paused, entries.map { Clock(it.seat, now + it.remaining, it.limit, it.strikes) })
    }
}
