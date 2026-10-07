package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/** The profile rules shared with iOS (PlayerAccountRules in PlayerAccount.swift; parity/chat-cases.json checks both). */
object PlayerAccountRules {
    /** 3–20 letters, digits or underscores; unique ignoring case on the server. */
    fun isValidUsername(name: String): Boolean =
        name.length in 3..20 && name.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' }

    /** What the player reads for a server error code (the mm_* functions raise these). */
    fun message(code: String): String = when (code) {
        "username_taken" -> "That name is taken. Try another."
        "invalid_username" -> "Use 3–20 letters, numbers or underscores."
        "not_found" -> "No player has that name."
        "self" -> "That's you."
        "no_username" -> "Choose your name first."
        "too_many_requests" -> "You have too many friend requests waiting."
        "too_many_reports" -> "You've sent a lot of reports. Try again later."
        "anonymous_provider_disabled", "anonymous_disabled" -> "Profiles aren't available right now. You can still play."
        "offline" -> "You're offline. Profiles and friends come back when you reconnect."
        "feature_unavailable" -> "That part of the profile server isn't ready yet. Try again after the next update."
        "invalid_visibility" -> "Choose Public, Friends only or Private."
        "too_many_games" -> "You've played a lot of games. Your game history catches up later."
        else -> "Something went wrong. Try again."
    }

    /** A friend request's result, as the player reads it. */
    fun requestResult(result: String, username: String): String = when (result) {
        "accepted" -> "You and $username are now friends."
        "already_friends" -> "You're already friends with $username."
        else -> "Friend request sent to $username."
    }
}

/** One row of mm_friends(): a friend, or a request either way (iOS PlayerFriend). */
data class PlayerFriend(val id: String, val username: String, val relation: String, val online: Boolean, val lastSeenAt: String?,
                        val platform: String?, val hostingCode: String?, val hostingOpenSeats: Int?) {
    val isFriend: Boolean get() = relation == "friend"
    val isIncoming: Boolean get() = relation == "incoming"
    val isOutgoing: Boolean get() = relation == "outgoing"
    /** A table this online friend is hosting with a seat still open. */
    val joinableCode: String? get() =
        if (isFriend && online && (hostingOpenSeats ?: 0) > 0) hostingCode?.let(TableJoinLink::normalized) else null

    companion object {
        fun decodeList(body: String): List<PlayerFriend> {
            val rows = Json.parseToJsonElement(body) as? JsonArray ?: return emptyList()
            return rows.mapNotNull { row ->
                val fields = row as? JsonObject ?: return@mapNotNull null
                fun text(key: String) = (fields[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
                PlayerFriend(text("id") ?: return@mapNotNull null, text("username") ?: return@mapNotNull null,
                    text("relation") ?: return@mapNotNull null, (fields["online"] as? JsonPrimitive)?.booleanOrNull ?: false,
                    text("last_seen_at"), text("platform"), text("hosting_code"), (fields["hosting_open_seats"] as? JsonPrimitive)?.intOrNull)
            }
        }
    }
}
