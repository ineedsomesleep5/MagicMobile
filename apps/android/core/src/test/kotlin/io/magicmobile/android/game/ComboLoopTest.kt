package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Mirrors apps/ios/MagicMobileTests/ComboLoopTests.swift; both read parity/combo-loop-cases.json. */
class ComboLoopTest {
    private fun step(code: String): ComboStep {
        val p = code.split("|")
        return ComboStep(ComboStep.Kind.entries.first { it.raw == p[0] }, p[1], p[2].ifEmpty { null }, p[3], if (p[4].isEmpty()) emptyList() else p[4].split(","))
    }

    @Test fun sharedCases() {
        val json = Json.parseToJsonElement(File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/combo-loop-cases.json").readText()).jsonObject
        val steps = json["steps"]!!.jsonObject.mapValues { step(it.value.jsonPrimitive.content) }
        for (item in json["cases"]!!.jsonArray) {
            val case = item.jsonObject
            val history = case["history"]!!.jsonPrimitive.content.map { steps[it.toString()]!! }
            assertEquals(case["name"]!!.jsonPrimitive.content, case["expected"]!!.jsonPrimitive.int, ComboLoop.cycle(history)?.size ?: 0)
        }
    }

    // A small game: you have Ashnod's Altar and two Squirrels; the opponent has 12 life.
    private fun card(id: String, name: String) = ZoneCard(id, CardIdentity(name, "Artifact"))
    private fun zones(battlefield: List<ZoneCard> = emptyList(), stack: List<ZoneCard> = emptyList()) =
        PlayerZones(emptyList(), emptyList(), battlefield, emptyList(), emptyList(), emptyList(), stack)
    private fun snapshot(prompt: Boolean = false, altarAction: Boolean = true, opponentStack: Boolean = false, opponentLife: Int = 12) = GameSnapshot(
        id = "game-1", phase = "main1", turn = 4, log = emptyList(), viewerPlayerId = "me", bridgeRevision = 7,
        players = listOf(
            PlayerGameState("me", "Caleb", 20, 0, 0, zones = zones(listOf(card("altar-1", "Ashnod's Altar"), card("sq-9", "Squirrel"), card("sq-10", "Squirrel")))),
            PlayerGameState("ai", "Tavern AI", opponentLife, 0, 0, zones = zones(stack = if (opponentStack) listOf(card("bolt-1", "Lightning Bolt")) else emptyList()))),
        legalActions = if (altarAction) listOf(LegalAction("act-77", "activate_ability", "me", "Sacrifice a creature: Add {C}{C}.", promptId = "p-1",
            sourceInstanceId = "altar-1", abilityId = "ab-1", messageId = 3)) else null,
        promptEnvelopeV2 = if (prompt) PromptEnvelopeV2("p-2", "GAME_TARGET", 4, "me", "target", "Sacrifice a creature",
            targets = listOf(ChoicePromptOption("sq-10", "Squirrel"), ChoicePromptOption("altar-1", "Ashnod's Altar")),
            responseCommand = XmageResponseCommand("choose_target", "p-2", 4)) else null)

    @Test fun stepsAreKeptByNameAndReplayedWithTodaysIDs() {
        val decision = snapshot()
        val activate = ComboLoop.commandFrom(decision.legalActions!![0], "game-1", 7)
        val step = ComboLoop.step(activate, "Sacrifice a creature: Add {C}{C}.", "act-77", decision)!!
        assertEquals(ComboStep.Kind.ACTION, step.kind)
        assertEquals("Ashnod's Altar", step.source)
        assertEquals("sacrifice a creature: add {c}{c}.", step.label)
        val replay = ComboLoop.command(step, decision)!!
        assertEquals("altar-1", replay.command.sourceInstanceId)
        assertEquals("act-77", replay.actionID)

        val asked = snapshot(prompt = true)
        val pick = GameCommand("choose_target", "game-1", "me", promptId = "p-2", messageId = 4, targetIds = listOf("sq-10"))
        val target = ComboLoop.step(pick, "Squirrel", "target-x", asked)!!
        assertEquals(ComboStep.Kind.PROMPT, target.kind)
        assertEquals(listOf("Squirrel"), target.targets)
        val again = ComboLoop.command(target, asked)!!
        assertEquals("choose_target", again.command.type)
        assertEquals(listOf("sq-10"), again.command.targetIds)
        assertNull(ComboLoop.command(ComboStep(ComboStep.Kind.PROMPT, "choose_target", null, "GAME_TARGET", listOf("Goblin")), asked))
        assertNull("the altar's ability isn't offered", ComboLoop.command(step, snapshot(altarAction = false)))
    }

    @Test fun digestOpponentResponseAndSummary() {
        val before = snapshot()
        assertFalse(ComboLoop.opponentResponded(before))
        assertTrue(ComboLoop.opponentResponded(snapshot(opponentStack = true)))
        val after = snapshot(opponentLife = 0)
        assertNotEquals(ComboLoop.digest(before), ComboLoop.digest(after))
        assertEquals(ComboLoop.digest(before), ComboLoop.digest(snapshot()))
        assertEquals("Repeated 12 times · Tavern AI 12 → 0", ComboLoop.summary(12, before, after))
        assertEquals("Activate Ashnod's Altar", ComboLoop.describe(listOf(ComboStep(ComboStep.Kind.ACTION, "activate_ability", "Ashnod's Altar", "x"))))
        assertNotNull(ComboLoop.cycle(List(3) { ComboStep(ComboStep.Kind.ACTION, "activate_ability", "Krark-Clan Ironworks", "x") }))
    }
}
