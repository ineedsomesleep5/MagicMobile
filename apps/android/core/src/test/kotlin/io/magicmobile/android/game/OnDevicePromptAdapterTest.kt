package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/** Mirrors OnDevicePromptAdapterTests.swift cases added for the Walnut Tavern builds. */
class OnDevicePromptAdapterTest {
    private val viewer = "00000000-0000-0000-0000-000000000001"
    private val first = "11111111-0000-0000-0000-000000000000"
    private val second = "22222222-0000-0000-0000-000000000000"

    private fun player(id: String, battlefield: String): PlayerGameState = EngineJson.format.decodeFromString(PlayerGameState.serializer(), """
        {"playerId": "$id", "life": 40, "poison": 0, "commanderTax": 0, "zones": {"library": [], "hand": [], "battlefield": [$battlefield], "graveyard": [], "exile": [], "command": [], "stack": []}}
    """.trimIndent())

    private fun card(id: String, blocking: List<String>): String =
        """{"instanceId": "$id", "card": {"name": "Creature", "typeLine": "Creature"}, "blocking": [${blocking.joinToString { "\"$it\"" }}]}"""

    @Test fun declaredBlockerRemainsSelectableSoTheBlockCanBeTakenBack() {
        val attacker = "33333333-0000-0000-0000-000000000000"
        val otherBlocker = "55555555-0000-0000-0000-000000000000"
        val players = listOf(
            player(viewer, card(first, listOf(attacker)) + ", " + card(second, emptyList())),
            player(second, card(attacker, emptyList()) + ", " + card(otherBlocker, listOf(first))))
        // The engine no longer offers a creature that already blocks; the board still lists it so a tap sends its
        // UUID again, which XMage takes as removing the block.
        val prompt = EnginePrompt(Json.parseToJsonElement("""
            {"promptId": "p-blockers", "revision": 41, "kind": "SELECT", "submitted": false, "responseTypes": ["uuid", "boolean"], "min": 0, "max": 0,
             "payload": {"message": "Select blockers", "required": true, "selectMode": "blockers", "options": {"possibleBlockers": ["$second"]}}}
        """.trimIndent()))
        val view = OnDevicePromptAdapter.presentation(prompt, viewer, emptyList(), players)
        assertEquals("Only the viewer's own blockers are added", listOf(second, first), view.envelope.targets?.map { it.id })
        val command = PromptCommandBuilder.command("match", view.envelope, "choose_target", prompt.id, viewer, listOf(first))
        assertNotNull(command)
        assertEquals(EnginePrompt.answer("uuid", kotlinx.serialization.json.JsonPrimitive(first)), OnDevicePromptAdapter.answer(command!!, prompt, viewer))
    }
}
