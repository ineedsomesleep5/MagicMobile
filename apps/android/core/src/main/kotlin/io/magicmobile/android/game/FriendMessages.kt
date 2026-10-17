package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.time.OffsetDateTime

/** Messages between friends (mm_message_*; FriendMessages.swift). */
data class FriendMessage(val id: Long, val body: String, val sentAt: Long, val fromMe: Boolean, val read: Boolean)

/** A conversation with a friend: the last message and how many of theirs are unread. */
data class MessageConversation(val username: String, val unread: Int, val last: FriendMessage)

/** A page of one conversation, oldest first. */
data class MessageThread(val username: String, val messages: List<FriendMessage>, val hasMore: Boolean)

object FriendMessageRules {
    /** Code points in one message (the server allows 500 characters). */
    const val MAX_CODE_POINTS = 500
    /** How often an open conversation asks for new messages. */
    const val POLL_MILLIS = 5_000L

    /** What gets sent: one tidy line, or nothing. */
    fun sanitize(raw: String): String? = TableChatText.sanitize(raw, MAX_CODE_POINTS)

    /** A friend's message as shown: strong language masked, like table chat. Your own show as typed. */
    fun shown(message: FriendMessage): String = if (message.fromMe) message.body else TableChatFilter.filtered(message.body)

    /** A newer page merged into what's on screen: one copy of each message (the newer copy wins), oldest first. */
    fun merged(existing: List<FriendMessage>, page: List<FriendMessage>): List<FriendMessage> =
        (existing + page).associateBy { it.id }.values.sortedBy { it.id }

    /**
     * Friends ordered for the Messages tab: conversations by their last message (newest first), then friends you haven't
     * written to yet, alphabetically. Conversations with players who aren't friends any more are left out.
     */
    fun ordered(friends: List<String>, conversations: List<MessageConversation>): List<Pair<String, MessageConversation?>> {
        val byName = conversations.associateBy { it.username }
        val talked = conversations.filter { it.username in friends }.sortedByDescending { it.last.id }.map { it.username to it }
        val quiet = friends.filter { it !in byName }.sortedBy { it.lowercase() }.map { it to null }
        return talked + quiet
    }

    fun parseMessage(fields: JsonObject): FriendMessage? {
        fun text(key: String) = (fields[key] as? JsonPrimitive)?.contentOrNull
        return FriendMessage((fields["id"] as? JsonPrimitive)?.longOrNull ?: return null, text("body") ?: return null,
            text("sentAt")?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() } ?: return null,
            (fields["fromMe"] as? JsonPrimitive)?.booleanOrNull ?: false, (fields["read"] as? JsonPrimitive)?.booleanOrNull ?: false)
    }

    fun parseMessage(body: String): FriendMessage? = (Json.parseToJsonElement(body) as? JsonObject)?.let(::parseMessage)

    fun parseConversations(body: String): List<MessageConversation> =
        (Json.parseToJsonElement(body) as? JsonArray).orEmpty().mapNotNull { row ->
            val fields = row as? JsonObject ?: return@mapNotNull null
            MessageConversation((fields["username"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null,
                (fields["unread"] as? JsonPrimitive)?.intOrNull ?: 0, (fields["last"] as? JsonObject)?.let(::parseMessage) ?: return@mapNotNull null)
        }

    fun parseThread(body: String): MessageThread? {
        val fields = Json.parseToJsonElement(body) as? JsonObject ?: return null
        return MessageThread((fields["username"] as? JsonPrimitive)?.contentOrNull ?: return null,
            (fields["messages"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::parseMessage) },
            (fields["hasMore"] as? JsonPrimitive)?.booleanOrNull ?: false)
    }
}
