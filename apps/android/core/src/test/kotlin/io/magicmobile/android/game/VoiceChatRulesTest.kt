package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** parity/voice-cases.json (iOS VoiceChatRulesTests, web voiceChat.test.ts). */
class VoiceChatRulesTest {
    private val root = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/voice-cases.json").readText()).jsonObject

    private fun text(value: kotlinx.serialization.json.JsonElement?): String? = if (value == null || value is JsonNull) null else value.jsonPrimitive.content

    @Test fun sharedCases() {
        assertEquals(VoiceChatRules.SPEAKING_LEVEL, root["speakingLevel"]!!.jsonPrimitive.double, 0.0)
        assertEquals(VoiceChatRules.HOLD_SECONDS, root["holdSeconds"]!!.jsonPrimitive.double, 0.0)
        for (case in root["channel"]!!.jsonArray) {
            val f = case.jsonObject
            assertEquals("$f", text(f["channel"]), VoiceChatRules.channel(text(f["epoch"])))
        }
        for (case in root["account"]!!.jsonArray) {
            val f = case.jsonObject
            assertEquals("$f", text(f["account"]), VoiceChatRules.account(text(f["seat"])))
        }
        for (case in root["level"]!!.jsonArray) {
            val f = case.jsonObject
            assertEquals("$f", f["speaking"]!!.jsonPrimitive.boolean, VoiceChatRules.isSpeaking(f["level"]!!.jsonPrimitive.double))
        }
        for (case in root["hold"]!!.jsonArray) {
            val f = case.jsonObject
            val heardAt = f["heardAt"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.double }
            assertEquals("$f", f["speaking"]!!.jsonPrimitive.boolean, VoiceChatRules.stillSpeaking(heardAt, f["now"]!!.jsonPrimitive.double))
        }
        for (case in root["shown"]!!.jsonArray) {
            val f = case.jsonObject
            fun b(key: String) = f[key]!!.jsonPrimitive.boolean
            assertEquals("$f", b("shown"), VoiceChatRules.shown(b("switchOn"), b("solo"), b("channel"), b("account"), b("unavailable")))
        }
    }

    @Test fun theSwitchStaysOffUntilTheServerNamesIt() {
        assertFalse(AppConfig().isOn(VoiceChatRules.SWITCH, default = false))
        assertTrue(AppConfig(switches = mapOf(VoiceChatRules.SWITCH to true)).isOn(VoiceChatRules.SWITCH, default = false))
        assertTrue(AppConfig().isOn("stackAutoTuck"))
    }
}
