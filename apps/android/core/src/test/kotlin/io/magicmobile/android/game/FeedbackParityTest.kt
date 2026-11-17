package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** feedback-cases.json: the Send feedback note, its contact, and the fixed payload (iOS FeedbackTests, web feedback.test). */
class FeedbackParityTest {
    private val root = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/feedback-cases.json").readText()).jsonObject

    private fun text(value: Any?): String? = (value as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull

    @Test fun capsMatchTheServer() {
        assertEquals(root["maxMessage"]!!.jsonPrimitive.int, FeedbackDraft.MAX_MESSAGE)
        assertEquals(root["maxContact"]!!.jsonPrimitive.int, FeedbackDraft.MAX_CONTACT)
    }

    @Test fun messagesAndContacts() {
        for (item in root["messages"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(text(item["name"]), text(item["output"]), FeedbackDraft.message(text(item["input"]) ?: ""))
        }
        for (item in root["contacts"]!!.jsonArray.map { it.jsonObject }) {
            val contact = FeedbackDraft.contact(text(item["input"]) ?: "")
            assertEquals(text(item["name"]), item["ok"]!!.jsonPrimitive.boolean, contact.ok)
            assertEquals(text(item["name"]), text(item["output"]), contact.value)
        }
    }

    @Test fun lengthCapsAndCleaning() {
        assertNull(FeedbackDraft.message("a".repeat(FeedbackDraft.MAX_MESSAGE + 1)))
        assertEquals("a".repeat(FeedbackDraft.MAX_MESSAGE), FeedbackDraft.message("a".repeat(FeedbackDraft.MAX_MESSAGE)))
        assertFalse(FeedbackDraft.contact("a".repeat(FeedbackDraft.MAX_CONTACT + 1)).ok)
        assertTrue(FeedbackDraft.contact("a".repeat(FeedbackDraft.MAX_CONTACT)).ok)
        assertEquals(FeedbackDraft.MAX_MESSAGE, FeedbackDraft.chars(FeedbackDraft.cleanMessage("a".repeat(FeedbackDraft.MAX_MESSAGE + 5))))
        assertEquals(FeedbackDraft.MAX_CONTACT, FeedbackDraft.chars(FeedbackDraft.cleanContact("a".repeat(FeedbackDraft.MAX_CONTACT + 10))))
        assertEquals("ab\nc", FeedbackDraft.cleanMessage("a\u0001b\nc"))
        assertEquals("ab", FeedbackDraft.cleanContact("a\nb"))
    }

    @Test fun payloadIsTheNoteAndTheDeviceOnly() {
        val keys = root["payloadKeys"]!!.jsonArray.map { it.jsonPrimitive.content }.toSet()
        for (item in root["payloads"]!!.jsonArray.map { it.jsonObject }) {
            val name = text(item["name"]) ?: ""
            val params = FeedbackDraft.params(
                text(item["kind"])!!, text(item["message"]) ?: "", text(item["contact"]) ?: "",
                text(item["platform"])!!, text(item["version"])!!, text(item["build"])!!, text(item["device"])!!)
            if (item["ok"]!!.jsonPrimitive.boolean) {
                val body = params ?: error(name)
                assertEquals(name, keys, body.keys)
                assertFalse(name, body.keys.any { it.contains("deck", ignoreCase = true) })
                assertEquals(name, text(item["messageOut"]), body["p_message"])
                assertEquals(name, text(item["contactOut"]), body["p_contact"])
                assertEquals(text(item["platform"]), body["p_platform"])
            } else {
                assertNull(name, params)
            }
        }
    }

    @Test fun notices() {
        for ((code, message) in root["notices"]!!.jsonObject) assertEquals(code, text(message), FeedbackDraft.notice(code))
        assertEquals(FeedbackDraft.notice("error"), FeedbackDraft.notice("nope"))
        for (code in listOf("invalid_feedback", "too_many_feedback", "not_signed_in")) {
            assertEquals(code, PlayerAccountRules.message(code), FeedbackDraft.notice(code))
        }
    }
}
