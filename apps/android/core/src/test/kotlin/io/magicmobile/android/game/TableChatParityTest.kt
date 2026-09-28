package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

/** chat-cases.json: chat text, the language filter, invite links and profile rules (iOS TableChatTests.swift). */
class TableChatParityTest {
    private val root = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/chat-cases.json").readText()).jsonObject

    private fun text(value: Any?): String? = (value as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull

    @Test fun sanitize() {
        assertEquals(root["maxScalars"]!!.jsonPrimitive.int, TableChatText.MAX_CODE_POINTS)
        for (item in root["sanitize"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals("sanitize · ${text(item["name"])}", text(item["output"]), TableChatText.sanitize(text(item["input"])!!))
        }
    }

    @Test fun filter() {
        for (item in root["filter"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(text(item["input"]), text(item["output"]), TableChatFilter.filtered(text(item["input"])!!))
        }
    }

    @Test fun inviteLinks() {
        for (item in root["links"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(text(item["link"]), text(item["code"]), TableJoinLink.code(text(item["link"])!!))
        }
        val share = root["shareLink"]!!.jsonObject
        assertEquals(text(share["url"]), TableJoinLink.url(text(share["code"])!!))
        assertNull(TableJoinLink.url("nope"))
    }

    @Test fun profileRules() {
        for (item in root["usernames"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(text(item["name"]), item["valid"]!!.jsonPrimitive.boolean, PlayerAccountRules.isValidUsername(text(item["name"])!!))
        }
        for ((code, message) in root["messages"]!!.jsonObject) assertEquals(code, text(message), PlayerAccountRules.message(code))
        for (item in root["requestResults"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(text(item["text"]), PlayerAccountRules.requestResult(text(item["result"])!!, text(item["username"])!!))
        }
    }

    @Test fun friendRowsDecodeAndOnlyOnlineFriendsWithSeatsAreJoinable() {
        val rows = PlayerFriend.decodeList("""[
            {"id":"a","username":"Host","relation":"friend","online":true,"last_seen_at":"2026-09-28T04:23:48.401014+00:00","platform":"ios","hosting_code":"abc234","hosting_open_seats":1},
            {"id":"b","username":"Full","relation":"friend","online":true,"last_seen_at":null,"platform":"android","hosting_code":"ABC234","hosting_open_seats":0},
            {"id":"c","username":"Asker","relation":"incoming","online":false,"last_seen_at":null,"platform":null,"hosting_code":null,"hosting_open_seats":null}]""")
        assertEquals(listOf("ABC234", null, null), rows.map { it.joinableCode })
        assertEquals(listOf(true, true, false), rows.map { it.isFriend })
        assertEquals("2026-09-28T04:23:48.401014+00:00", rows[0].lastSeenAt)
    }
}
