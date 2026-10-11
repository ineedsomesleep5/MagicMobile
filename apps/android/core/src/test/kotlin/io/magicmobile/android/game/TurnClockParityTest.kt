package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File

/** turn-clock-cases.json: the online turn timer's rules, packet and rope (iOS TurnClockTests.swift). */
class TurnClockParityTest {
    private val root = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/turn-clock-cases.json").readText()).jsonObject

    private fun number(value: J?): Double = (value as JsonPrimitive).content.toDouble()
    private fun prompt(value: J?): TurnClockPrompt? = value.string?.let { TurnClockPrompt(it, 1) }
    private fun entries(value: J?) = value.array!!.map {
        TurnClockEntry(it["seat"].string!!, number(it["remaining"]), number(it["limit"]), it["strikes"].integer!!.toInt())
    }

    @Test fun rules() {
        val rules = root["rules"]!!
        assertEquals(TurnClockRules(number(rules["decision"]), number(rules["rope"]), number(rules["grace"]),
            rules["strikesToForfeit"].integer!!.toInt(), number(rules["resumeFloor"])), TurnClockRules.ONLINE)
    }

    @Test fun scenarios() {
        for (scenario in root["scenarios"]!!.jsonArray) {
            val name = scenario["name"].string
            val clock = TurnClock()
            for (step in scenario["steps"]!!.jsonArray) {
                val at = number(step["at"])
                val label = "$name @ $at"
                step["observe"]?.let { observe ->
                    val changed = clock.observe(observe["seat"].string!!, prompt(observe["prompt"]), at)
                    step["changed"]?.let { assertEquals(label, it.bool, changed) }
                }
                step["pause"]?.let { pause ->
                    val changed = clock.setPaused(pause.bool!!, at)
                    step["changed"]?.let { assertEquals(label, it.bool, changed) }
                }
                step["timeout"]?.let { timeout ->
                    val result = clock.timeout(timeout["seat"].string!!, prompt(timeout["prompt"])!!, timeout["hasDefault"].bool!!, at)
                    assertEquals(label, step["result"].string, result?.wire)
                }
                step["answerFailed"]?.let { clock.answerFailed(it["seat"].string!!, prompt(it["prompt"])!!, at) }
                step["expired"]?.let { expected ->
                    assertEquals(label, expected.array!!.map { it.string }, clock.expired(at).map { it.first })
                }
                step["entries"]?.let { assertEquals(label, entries(it), clock.entries(at)) }
                step["strikes"]?.obj?.forEach { (seat, count) -> assertEquals("$label $seat", count.integer!!.toInt(), clock.strikes(seat)) }
            }
        }
    }

    @Test fun defaultAnswers() {
        for (item in root["defaultAnswers"]!!.jsonArray) {
            val shape = item["prompt"]!!.jsonObject
            val prompt = EnginePrompt(JsonObject(shape + mapOf("promptId" to JsonPrimitive("p"), "revision" to JsonPrimitive(1),
                "submitted" to JsonPrimitive(false), "min" to JsonPrimitive(0), "max" to JsonPrimitive(1))))
            val expected = item["answer"].takeUnless { it is JsonNull }
            assertEquals(item["name"].string, expected, TurnClock.defaultAnswer(prompt))
        }
    }

    @Test fun wire() {
        for (item in root["wire"]!!["valid"]!!.jsonArray) {
            val packet = item["packet"]!!
            val (paused, parsed) = TurnClockWire.parse(packet)
            assertEquals(item["name"].string, packet, TurnClockWire.packet("E", paused, parsed))
        }
        for (item in root["wire"]!!["invalid"]!!.jsonArray) {
            assertThrows(item["name"].string, EngineError::class.java) { TurnClockWire.parse(item["packet"]!!) }
        }
    }

    @Test fun ropes() {
        for (item in root["ropes"]!!.jsonArray) {
            val name = item["name"].string
            val board = TurnClockBoard(item["board"]!!["paused"].bool!!, item["board"]!!["clocks"].array!!.map {
                TurnClockBoard.Clock(it["seat"].string!!, number(it["deadline"]), number(it["limit"]), it["strikes"].integer!!.toInt())
            })
            val local = item["local"].string
            val now = number(item["now"])
            val rope = board.rope(local, now)
            val expected = item["rope"].takeUnless { it is JsonNull }
            if (expected == null) assertNull(name, rope)
            else assertEquals(name, TurnClockBoard.Rope(expected["seat"].string!!, expected["isLocal"].bool!!,
                number(expected["remaining"]), number(expected["fraction"]), expected["strikes"].integer!!.toInt()), rope)
            val until = item["untilRope"].takeUnless { it is JsonNull }
            assertEquals(name, until?.let(::number), board.secondsUntilRope(local, now))
        }
    }
}
