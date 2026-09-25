package io.magicmobile.android.ondevice

import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.random.Random

/**
 * Port of OnDeviceStartingRoll.swift: a complete, host-recorded D20 result. Every device
 * animates these same values; animation timing never determines who starts the game.
 */
class OnDeviceStartingRoll private constructor(val rounds: List<Map<String, Int>>, val winnerSeatID: String, val seatOrder: List<String>) {
    data class Step(val roundIndex: Int, val seatID: String, val value: Int)

    val steps: List<Step> get() = rounds.flatMapIndexed { roundIndex, round ->
        seatOrder.mapNotNull { seat -> round[seat]?.let { Step(roundIndex, seat, it) } }
    }

    override fun equals(other: Any?): Boolean = other is OnDeviceStartingRoll && rounds == other.rounds &&
        winnerSeatID == other.winnerSeatID && seatOrder == other.seatOrder
    override fun hashCode(): Int = (rounds.hashCode() * 31 + winnerSeatID.hashCode()) * 31 + seatOrder.hashCode()

    fun encoded(seatIDs: List<String>): J {
        validate(seatIDs)
        return JsonObject(mapOf(
            "rounds" to JsonArray(rounds.map { round ->
                JsonArray(seatIDs.mapNotNull { seat -> round[seat]?.let { value ->
                    JsonObject(mapOf("seatId" to JsonPrimitive(seat), "value" to JsonPrimitive(value.toLong())))
                } })
            }),
            "winnerSeatId" to JsonPrimitive(winnerSeatID)))
    }

    private fun validate(seatIDs: List<String>) {
        if (seatIDs != seatOrder || seatIDs.size !in 2..4 || seatIDs.toSet().size != seatIDs.size || rounds.isEmpty() || rounds.size > 32) {
            throw EngineError.InvalidMessage("Invalid starting-roll roster.")
        }
        var contenders = seatIDs.toSet()
        rounds.forEachIndexed { index, round ->
            val highest = round.values.maxOrNull()
            if (round.keys != contenders || !round.values.all { it in 1..20 } || highest == null) {
                throw EngineError.InvalidMessage("Starting-roll round does not match the roster.")
            }
            contenders = round.filterValues { it == highest }.keys
            if (contenders.size <= 1 && index != rounds.lastIndex) throw EngineError.InvalidMessage("Starting roll continues after a winner.")
        }
        if (contenders != setOf(winnerSeatID)) throw EngineError.InvalidMessage("Starting-roll winner does not match the dice.")
    }

    companion object {
        fun generate(seatIDs: List<String>, draw: () -> Int = { Random.nextInt(1, 21) }): OnDeviceStartingRoll {
            if (seatIDs.size !in 2..4 || seatIDs.toSet().size != seatIDs.size || seatIDs.any { it.isEmpty() }) {
                throw EngineError.InvalidMessage("A starting roll needs 2–4 distinct seats.")
            }
            var contenders = seatIDs
            val rounds = mutableListOf<Map<String, Int>>()
            // An extremely unlikely run of ties must fail visibly, not loop forever.
            repeat(32) {
                val rolls = LinkedHashMap<String, Int>()
                for (seat in contenders) {
                    val value = draw()
                    if (value !in 1..20) throw EngineError.InvalidMessage("Invalid D20 value.")
                    rolls[seat] = value
                }
                rounds += rolls
                val high = rolls.values.max()
                contenders = contenders.filter { rolls[it] == high }
                if (contenders.size == 1) return OnDeviceStartingRoll(rounds, contenders[0], seatIDs)
            }
            throw EngineError.InvalidMessage("The starting roll tied too many times. Try the match again.")
        }

        fun decode(value: J, seatIDs: List<String>): OnDeviceStartingRoll {
            val fields = value.obj
            val rows = fields?.get("rounds").array
            val winner = fields?.get("winnerSeatId").string
            if (fields == null || fields.keys != setOf("rounds", "winnerSeatId") || rows == null || rows.isEmpty() || rows.size > 32 || winner == null) {
                throw EngineError.InvalidMessage("Invalid shared starting roll.")
            }
            val rounds = rows.map { row ->
                val entries = row.array
                if (entries == null || entries.size > 4) throw EngineError.InvalidMessage("Invalid shared starting roll round.")
                val result = LinkedHashMap<String, Int>()
                for (entry in entries) {
                    val item = entry.obj
                    val seat = item?.get("seatId").string
                    val number = item?.get("value").integer
                    if (item == null || item.keys != setOf("seatId", "value") || seat == null || number == null || number !in 1L..20L || result.containsKey(seat)) {
                        throw EngineError.InvalidMessage("Invalid shared D20 value.")
                    }
                    result[seat] = number.toInt()
                }
                result
            }
            return OnDeviceStartingRoll(rounds, winner, seatIDs).also { it.validate(seatIDs) }
        }
    }
}

/** One shared cursor through the host's result. Humans advance only their own turn; the host advances AI turns. */
class OnDeviceStartingRollProgress(val roll: OnDeviceStartingRoll, val humanSeatIDs: Set<String>) {
    var revealedCount = 0; private set
    val nextSeatID: String? get() = roll.steps.getOrNull(revealedCount)?.seatID
    val isComplete: Boolean get() = revealedCount == roll.steps.size

    fun advance(seatID: String, automated: Boolean): Int {
        if (nextSeatID != seatID || humanSeatIDs.contains(seatID) == automated) throw EngineError.InvalidMessage("It is not this player's turn to roll.")
        return revealedCount++
    }

    fun acceptHostAdvance(index: Int) {
        if (index != revealedCount || nextSeatID == null) throw EngineError.ReplayedMessage
        revealedCount += 1
    }
}

/**
 * Port of OnDeviceStartingPlayerChoice.swift: converts a shared pregame winner into the exact
 * current XMage prompt answer. Ambiguity or a changed prompt fails closed.
 */
object OnDeviceStartingPlayerChoice {
    fun candidateIDs(snapshot: GameSnapshot): List<String>? {
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        val candidates = prompt.targetIds ?: return null
        if (snapshot.source != "xmage-ondevice" || prompt.playerId != snapshot.viewerID ||
            prompt.method !in setOf("GAME_PICK_TARGET", "PICK_TARGET") ||
            !prompt.message.lowercase().contains("starting player") ||
            prompt.responseCommand?.type != "choose_target" || prompt.responseCommand?.promptId != prompt.id ||
            prompt.responseCommand?.messageId != prompt.messageId ||
            candidates.size !in 2..4 || candidates.toSet().size != candidates.size ||
            !candidates.all { id -> snapshot.players.any { it.playerId == id } } || snapshot.bridgeRevision == null) return null
        return candidates
    }

    fun commandForName(snapshot: GameSnapshot, winnerName: String): GameCommand? {
        val matches = snapshot.players.filter { it.displayName == winnerName }
        return if (matches.size == 1) command(snapshot, winnerPlayerID = matches[0].playerId) else null
    }

    fun command(snapshot: GameSnapshot, winnerPlayerID: String): GameCommand? {
        val candidates = candidateIDs(snapshot) ?: return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        val revision = snapshot.bridgeRevision ?: return null
        if (winnerPlayerID !in candidates) return null
        return GameCommand("choose_target", snapshot.id, snapshot.viewerID, promptId = prompt.id, messageId = prompt.messageId,
            targetIds = listOf(winnerPlayerID), expectedBridgeRevision = revision)
    }
}
