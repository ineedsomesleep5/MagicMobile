package io.magicmobile.android.game

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * A friend challenge as the server reports it (mm_challenge_* in supabase/migrations/20261004180000_friend_challenges.sql).
 * Port of FriendChallenges.swift.
 */
data class FriendChallenge(val id: String, val mode: String, val status: String, val role: String?, val challenger: String?,
                           val challenged: String?, val challengerStep: Int?, val protocol: String?, val tableCode: String?,
                           val matchId: String?) {
    val isRanked: Boolean get() = mode == PlayMode.RANKED.raw
    val playMode: PlayMode get() = if (isRanked) PlayMode.RANKED else PlayMode.QUICK
    val isPending: Boolean get() = status == "pending"

    companion object {
        /** What a challenge reads as once nothing is known about it any more. */
        fun closed(id: String) = FriendChallenge(id, "quick", "cancelled", null, null, null, null, null, null, null)

        fun parse(value: JsonObject, id: String? = null): FriendChallenge {
            fun s(key: String) = (value[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
            val parsedID = s("id") ?: return closed(id ?: throw IllegalArgumentException("challenge without id"))
            return FriendChallenge(parsedID, s("mode") ?: "quick", s("status") ?: "cancelled", s("role"), s("challenger"), s("challenged"),
                s("challengerStep")?.toIntOrNull(), s("protocol"), s("tableCode"), s("matchId"))
        }
    }
}

object FriendChallengeRules {
    /** A challenge waits this long for an answer (the server's limit). */
    const val EXPIRY_MILLIS = 120_000L

    /**
     * Ranked friend games need the same tier, Gold with Gold (Caleb, 2026-10-04). A friend without a published standing this
     * season is a fresh Bronze IV, as the server reads them.
     */
    fun mayRank(myStep: Int, friendStep: Int?): Boolean = RankPosition.atStep(myStep).tier == RankPosition.atStep(friendStep ?: 0).tier

    fun message(code: String): String = when (code) {
        "rank_mismatch" -> "Ranked challenges need the same tier."
        "not_friends" -> "You can only challenge friends."
        "challenge_closed" -> "That challenge has closed."
        "protocol_mismatch" -> "You're on different app versions. Update both phones to play."
        else -> PlayerAccountRules.message(code)
    }
}

interface FriendChallengeService {
    suspend fun send(username: String, mode: PlayMode, protocol: String, rankStep: Int, tableCode: String): FriendChallenge
    suspend fun incoming(): List<FriendChallenge>
    suspend fun status(id: String): FriendChallenge
    suspend fun accept(id: String, protocol: String, rankStep: Int): FriendChallenge
    suspend fun decline(id: String)
    suspend fun cancel(id: String): FriendChallenge
}

sealed interface ChallengeAnswer {
    data class Accepted(val challenge: FriendChallenge) : ChallengeAnswer
    data object Declined : ChallengeAnswer
    data object Expired : ChallengeAnswer
    data object Cancelled : ChallengeAnswer
    /** A server error code (FriendChallengeRules.message). */
    data class Failed(val code: String) : ChallengeAnswer
}

/**
 * Sends challenges and waits for the answer; watches for challenges sent to this player while the menu is open.
 * Port of FriendChallengeCoordinator (FriendChallenges.swift). `codeOf` turns a server failure into its error code.
 */
class FriendChallengeCoordinator(var service: FriendChallengeService?, private val sleep: suspend (Long) -> Unit = { delay(it) },
                                 private val clock: () -> Long = System::currentTimeMillis,
                                 private val codeOf: (Throwable) -> String = { "error" }) {
    /** The challenge this player sent, while waiting for the friend. */
    var outgoing: FriendChallenge? = null; private set
    /** Challenges waiting for this player, newest first. */
    var incoming: List<FriendChallenge> = emptyList(); private set
    /** Told whenever `outgoing` or `incoming` changes (the app mirrors them into Compose state). */
    var onChange: (() -> Unit)? = null
    @Volatile private var cancelRequested = false
    private val answered = mutableSetOf<String>()

    val isWaiting: Boolean get() = outgoing != null

    private fun setOutgoing(value: FriendChallenge?) { outgoing = value; onChange?.invoke() }
    private fun setIncoming(value: List<FriendChallenge>) { if (value != incoming) { incoming = value; onChange?.invoke() } }

    /** Sends a challenge for a table this player already opened, then waits for the answer. */
    suspend fun challenge(username: String, mode: PlayMode, protocol: String, rankStep: Int, tableCode: String): ChallengeAnswer {
        val service = service ?: return ChallengeAnswer.Failed("offline")
        if (outgoing != null) return ChallengeAnswer.Failed("error")
        cancelRequested = false
        try {
            var current = service.send(username, mode, protocol, rankStep, tableCode)
            setOutgoing(current)
            val started = clock()
            while (current.isPending) {
                if (cancelRequested || clock() - started > FriendChallengeRules.EXPIRY_MILLIS + 5_000) {
                    // An answer that arrived meanwhile still stands.
                    val final = runCatching { service.cancel(current.id) }.getOrElse { FriendChallenge.closed(current.id) }
                    if (final.status == "accepted") return ChallengeAnswer.Accepted(final)
                    return if (cancelRequested) ChallengeAnswer.Cancelled else ChallengeAnswer.Expired
                }
                sleep(2_000)
                current = service.status(current.id)
            }
            return when (current.status) {
                "accepted" -> ChallengeAnswer.Accepted(current)
                "declined" -> ChallengeAnswer.Declined
                "expired" -> ChallengeAnswer.Expired
                else -> ChallengeAnswer.Cancelled
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return ChallengeAnswer.Failed(codeOf(e))
        } finally {
            setOutgoing(null)
        }
    }

    /** Withdraws the challenge being waited on. */
    fun cancelOutgoing() { cancelRequested = true }

    /** Checks for challenges until cancelled (run while the menu is showing). */
    suspend fun watch() {
        while (true) {
            refreshIncoming()
            sleep(WATCH_MILLIS)
        }
    }

    suspend fun refreshIncoming() {
        val service = service ?: return setIncoming(emptyList())
        val list = try { service.incoming() } catch (e: CancellationException) { throw e } catch (e: Exception) { return }
        setIncoming(list.filter { it.isPending && it.id !in answered })
    }

    /** Accepts: the challenge with its table code (and the ranked match for ranked). */
    suspend fun accept(challenge: FriendChallenge, protocol: String, rankStep: Int): FriendChallenge {
        answered += challenge.id
        setIncoming(incoming.filter { it.id != challenge.id })
        val service = service ?: throw IllegalStateException("offline")
        return service.accept(challenge.id, protocol, rankStep)
    }

    suspend fun decline(challenge: FriendChallenge) {
        answered += challenge.id
        setIncoming(incoming.filter { it.id != challenge.id })
        try { service?.decline(challenge.id) } catch (e: CancellationException) { throw e } catch (_: Exception) {}
    }

    companion object {
        /** How often the menu checks for challenges. */
        const val WATCH_MILLIS = 5_000L
    }
}
