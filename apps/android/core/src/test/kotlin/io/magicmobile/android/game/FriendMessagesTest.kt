package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors apps/ios/MagicMobileTests/FriendMessagesTests.swift. */
class FriendMessagesTest {
    @Test fun parsesTheServerShapes() {
        val conversations = FriendMessageRules.parseConversations("""
            [{"username":"Aria_Blade","unread":2,"last":{"id":6,"body":"Want to play?","sentAt":"2026-10-17T19:16:34.123456+00:00","fromMe":false,"read":false}},
             {"username":"ManaFiend","unread":0,"last":{"id":4,"body":"Well played!","sentAt":"2026-10-16T08:00:00+00:00","fromMe":true,"read":true}}]
        """)
        assertEquals(listOf("Aria_Blade", "ManaFiend"), conversations.map { it.username })
        assertEquals(2, conversations[0].unread)
        assertFalse(conversations[0].last.fromMe)
        val thread = FriendMessageRules.parseThread(
            """{"username":"Aria_Blade","hasMore":true,"messages":[{"id":5,"body":"hi","sentAt":"2026-10-17T19:15:00+00:00","fromMe":true,"read":true}]}""")!!
        assertTrue(thread.hasMore)
        assertEquals(5L, thread.messages.first().id)
        assertEquals("ok", FriendMessageRules.parseMessage("""{"id":9,"body":"ok","sentAt":"2026-10-17T19:20:00.5+00:00","fromMe":true,"read":false}""")?.body)
    }

    @Test fun sanitizeMaskAndMerge() {
        assertNull(FriendMessageRules.sanitize("   \n\t "))
        assertEquals("up for a game?", FriendMessageRules.sanitize("  up  for\na game?  "))
        assertEquals(FriendMessageRules.MAX_CODE_POINTS, FriendMessageRules.sanitize("x".repeat(600))?.length)
        val theirs = FriendMessage(2, "well shit", 1_000, fromMe = false, read = false)
        val mine = FriendMessage(1, "well shit", 1_000, fromMe = true, read = true)
        assertEquals("well s***", FriendMessageRules.shown(theirs))
        assertEquals("well shit", FriendMessageRules.shown(mine))
        val merged = FriendMessageRules.merged(listOf(theirs, mine), listOf(theirs.copy(read = true), FriendMessage(3, "new", 1_000, false, false)))
        assertEquals(listOf(1L, 2L, 3L), merged.map { it.id })
        assertTrue(merged[1].read)
    }

    @Test fun friendsOrderedByLastMessageThenName() {
        val conversations = listOf(
            MessageConversation("Old", 0, FriendMessage(3, "a", 1_000, true, true)),
            MessageConversation("New", 1, FriendMessage(8, "b", 1_000, false, false)),
            MessageConversation("Gone", 0, FriendMessage(9, "c", 1_000, false, true)))
        val rows = FriendMessageRules.ordered(listOf("zed", "Old", "New", "amy"), conversations)
        assertEquals(listOf("New", "Old", "amy", "zed"), rows.map { it.first })
        assertNull(rows[2].second)
    }
}
