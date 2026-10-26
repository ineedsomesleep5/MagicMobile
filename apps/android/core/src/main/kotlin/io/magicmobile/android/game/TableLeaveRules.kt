package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * When a player leaves a table with people, the others play on (iOS TableLeaveRules; Caleb, 2026-10-26: one player had
 * to go and the game couldn't continue for the other two). A guest who taps Leave, or whose connection the table gives up
 * on, is conceded at once. A guest who is away (dropped or in the background) is waited for; after [VOTE_AFTER_SECONDS]
 * everyone still at the table may vote to go on without them, and when they all agree the host concedes the seat. Only the
 * host's phone runs the game, so the host leaving still ends it. Shared cases: parity/table-leave-cases.json.
 */
object TableLeaveRules {
    const val VOTE_AFTER_SECONDS = 15.0

    /** Everyone still at the table agrees. */
    fun passes(yes: Int, eligible: Int): Boolean = eligible > 0 && yes >= eligible

    fun leftNotice(name: String): String = "$name left. The game goes on."

    const val LEFT_BEHIND_MESSAGE = "The others went on without you after you left the table."

    /** "Continue without Jed (1/2)". */
    fun buttonTitle(vote: TableContinueVote): String = "Continue without ${vote.name} (${vote.voters.size}/${vote.needed})"
}

/**
 * The vote to go on without one away player: the seats that said yes and how many must. The host sends it to the guests
 * in a `vote` packet whenever it changes; seat "" with needed 0 means no vote is open.
 */
data class TableContinueVote(val seatID: String, val name: String, val voters: List<String>, val needed: Int, val voted: Boolean) {
    fun packet(epoch: String): JsonObject = JsonObject(linkedMapOf(
        "type" to JsonPrimitive("vote"), "epoch" to JsonPrimitive(epoch), "seat" to JsonPrimitive(seatID),
        "voters" to JsonArray(voters.map(::JsonPrimitive)), "needed" to JsonPrimitive(needed.toLong())))

    companion object {
        val NONE = TableContinueVote("", "", emptyList(), 0, false)
        private val SEATS = setOf("player1", "player2", "player3", "player4")

        /** A host's `vote` packet; null when no vote is open. Throws on anything malformed. */
        fun parse(value: JsonElement, names: Map<String, String>, localSeat: String?): TableContinueVote? {
            val fields = value as? JsonObject ?: throw IllegalArgumentException("Invalid table vote.")
            require(fields.keys == setOf("type", "epoch", "seat", "voters", "needed")) { "Invalid table vote." }
            val seat = (fields["seat"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw IllegalArgumentException("Invalid table vote.")
            val raw = fields["voters"] as? JsonArray ?: throw IllegalArgumentException("Invalid table vote.")
            val needed = (fields["needed"] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull ?: throw IllegalArgumentException("Invalid table vote.")
            val voters = raw.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: throw IllegalArgumentException("Invalid table vote.") }
            require(raw.size <= 4 && needed in 0..4 && voters.all { it in SEATS } && (seat.isEmpty() || seat in SEATS) &&
                seat.isEmpty() == (needed == 0L)) { "Invalid table vote." }
            if (seat.isEmpty()) return null
            return TableContinueVote(seat, names[seat] ?: "A player", voters, needed.toInt(), localSeat != null && localSeat in voters)
        }
    }
}
