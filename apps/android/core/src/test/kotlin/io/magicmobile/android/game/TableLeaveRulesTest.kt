package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** parity/table-leave-cases.json (iOS TableLeaveRulesTests). */
class TableLeaveRulesTest {
    private val root = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/table-leave-cases.json").readText()).jsonObject

    @Test fun sharedCases() {
        assertEquals(TableLeaveRules.VOTE_AFTER_SECONDS, root["voteAfterSeconds"]!!.jsonPrimitive.double, 0.0)
        for (case in root["passes"]!!.jsonArray) {
            val fields = case.jsonObject
            assertEquals(fields["name"]!!.jsonPrimitive.content, fields["expect"]!!.jsonPrimitive.boolean,
                TableLeaveRules.passes(fields["yes"]!!.jsonPrimitive.int, fields["eligible"]!!.jsonPrimitive.int))
        }
        for (case in root["packets"]!!.jsonArray) {
            val fields = case.jsonObject
            val name = fields["name"]!!.jsonPrimitive.content
            val local = fields["localSeat"]?.jsonPrimitive?.content
            val parsed = runCatching { TableContinueVote.parse(fields["packet"]!!, mapOf("player3" to "Jed"), local) }
            when (val expect = fields["expect"]) {
                is JsonObject -> {
                    val vote = parsed.getOrThrow()!!
                    assertEquals(name, expect["seat"]!!.jsonPrimitive.content, vote.seatID)
                    assertEquals(name, expect["voters"]!!.jsonArray.map { it.jsonPrimitive.content }, vote.voters)
                    assertEquals(name, expect["needed"]!!.jsonPrimitive.int, vote.needed)
                    assertEquals(name, expect["voted"]!!.jsonPrimitive.boolean, vote.voted)
                }
                is JsonPrimitive -> if (expect is JsonNull) assertNull(name, parsed.getOrThrow()) else assertTrue(name, parsed.isFailure)
                else -> assertNull(name, parsed.getOrThrow())
            }
        }
    }

    @Test fun thePacketRoundTripsAndTheButtonCounts() {
        val vote = TableContinueVote("player3", "Jed", listOf("player1"), 2, false)
        assertEquals(vote.copy(voted = true), TableContinueVote.parse(vote.packet("E"), mapOf("player3" to "Jed"), "player1"))
        assertEquals("Continue without Jed (1/2)", TableLeaveRules.buttonTitle(vote))
        assertNull(TableContinueVote.parse(TableContinueVote.NONE.packet("E"), emptyMap(), null))
    }
}
