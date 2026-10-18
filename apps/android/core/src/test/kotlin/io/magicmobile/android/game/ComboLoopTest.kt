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
    private fun target(code: String): ComboTarget {
        val parts = code.split("@")
        if (parts.size != 2) return ComboTarget(code)
        val detail = parts[1].split("/")
        return ComboTarget(parts[0], detail[0], detail[1], detail[2] == "token")
    }

    private fun step(code: String): ComboStep {
        val p = code.split("|")
        return ComboStep(ComboStep.Kind.entries.first { it.raw == p[0] }, p[1], p[2].ifEmpty { null }, p[3],
            if (p[4].isEmpty()) emptyList() else p[4].split(";").map(::target))
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

    // A small game: Chatterfang, a Treasure and a Squirrel token; the opponent has two creatures and 12 life.
    private fun card(id: String, name: String, type: String, token: Boolean = false, toughness: Int? = null) =
        ZoneCard(id, CardIdentity(name, type, isToken = if (token) true else null), power = toughness?.let { 1 }, toughness = toughness)
    private fun zones(battlefield: List<ZoneCard> = emptyList(), stack: List<ZoneCard> = emptyList()) =
        PlayerZones(emptyList(), emptyList(), battlefield, emptyList(), emptyList(), emptyList(), stack)
    private fun snapshot(prompt: Boolean = false, callerAlive: Boolean = true, ownTrigger: Boolean = false, opponentStack: Boolean = false,
                         opponentLife: Int = 12, callerToughness: Int = 3, passOffered: Boolean = false): GameSnapshot {
        val theirs = listOfNotNull(if (callerAlive) card("cal-1", "Kinjalli's Caller", "Creature — Human Cleric", toughness = callerToughness) else null,
            card("zac-1", "Zacama, Primal Calamity", "Legendary Creature — Elder Dinosaur", toughness = 4))
        val actions = listOfNotNull(LegalAction("act-77", "activate_ability", "me", "{B}, Sacrifice X Squirrels: Target creature gets +X/-X until end of turn.",
            promptId = "p-1", sourceInstanceId = "chat-1", abilityId = "ab-1", messageId = 3),
            if (passOffered) LegalAction("p-1:pass_priority", "pass_priority", "me", "Pass priority", promptId = "p-1", messageId = 3) else null)
        val targets = listOfNotNull(if (callerAlive) ChoicePromptOption("cal-1", "Kinjalli's Caller", "cal-1") else null,
            ChoicePromptOption("zac-1", "Zacama, Primal Calamity", "zac-1"), ChoicePromptOption("sq-9", "Squirrel Token", "sq-9"))
        return GameSnapshot(
            id = "game-1", phase = "main1", turn = 15, log = emptyList(), viewerPlayerId = "me", bridgeRevision = 7,
            players = listOf(
                PlayerGameState("me", "Caleb", 20, 0, 0, zones = zones(listOf(card("chat-1", "Chatterfang, Squirrel General", "Legendary Creature — Squirrel Warrior"),
                    card("tr-1", "Treasure Token", "Token Artifact — Treasure", token = true), card("sq-9", "Squirrel Token", "Token Creature — Squirrel", token = true),
                    card("sov-1", "Squirrel Sovereign", "Creature — Squirrel Noble")))),
                PlayerGameState("ai", "Tavern AI", opponentLife, 0, 0, zones = zones(theirs, if (opponentStack) listOf(card("bolt-1", "Lightning Bolt", "Instant")) else emptyList()))),
            legalActions = actions,
            xmage = if (ownTrigger) XmageMobileSnapshot(1, "game-1", 7, null, emptyList(),
                listOf(XmageStackObject("st-1", name = "Pitiless Plunderer trigger", sourceInstanceId = "plu-1", controllerId = "me")),
                emptyList(), emptyList(), emptyList(), emptyList(), emptyList(), emptyList(), emptyList(),
                XmagePanels(stack = true, command = false, graveyard = false, exile = false, revealed = false, lookedAt = false, search = false)) else null,
            promptEnvelopeV2 = if (prompt) PromptEnvelopeV2("p-2", "GAME_TARGET", 4, "me", "target", "Select a creature", targets = targets,
                responseCommand = XmageResponseCommand("choose_target", "p-2", 4)) else null)
    }

    @Test fun stepsKeepKindsAndReplayTheSameTargetUntilItsGone() {
        val decision = snapshot()
        val activate = ComboLoop.commandFrom(decision.legalActions!![0], "game-1", 7)
        val step = ComboLoop.step(activate, "x", "act-77", decision)!!
        assertEquals("Chatterfang, Squirrel General", step.source)
        assertTrue(step.stackEmpty)
        assertEquals("act-77", ComboLoop.command(step, decision)?.actionID)

        val asked = snapshot(prompt = true)
        val pick = GameCommand("choose_target", "game-1", "me", promptId = "p-2", messageId = 4, targetIds = listOf("cal-1"))
        val target = ComboLoop.step(pick, "Kinjalli's Caller", "t", asked)!!
        assertEquals(listOf(ComboTarget("Kinjalli's Caller", "opponent", "creature", false)), target.targets)
        // While it lives, the same creature; once it's gone, another opponent's creature (never your own Squirrel).
        val same = ComboLoop.command(target, asked, listOf("Kinjalli's Caller"))!!
        assertEquals(listOf("cal-1"), same.command.targetIds)
        assertNull(same.retargeted)
        val next = ComboLoop.command(target, snapshot(prompt = true, callerAlive = false), listOf("Kinjalli's Caller"))!!
        assertEquals(listOf("zac-1"), next.command.targetIds)
        assertEquals("Kinjalli's Caller" to "Zacama, Primal Calamity", next.retargeted)
        // A Squirrel token choice never takes Squirrel Sovereign.
        val squirrel = ComboStep(ComboStep.Kind.PROMPT, "choose_target", null, "GAME_TARGET", listOf(ComboTarget("Squirrel Token", "you", "creature", true)))
        assertEquals(listOf("sq-9"), ComboLoop.command(squirrel, asked)?.command?.targetIds)
        assertEquals("no Squirrel Token token left", ComboLoop.missing(squirrel))
        assertEquals("no opponent's creature left to choose", ComboLoop.missing(target))
    }

    @Test fun passesAreIgnoredAndOwnTriggersResolveFirst() {
        val decision = snapshot(passOffered = true)
        val pass = GameCommand("pass_priority", "game-1", "me", promptId = "p-1", messageId = 3)
        assertEquals(ComboNote.Ignore, ComboLoop.note(pass, "Pass priority", "p-1:pass_priority", decision))
        assertEquals(ComboNote.Breaks, ComboLoop.note(GameCommand("declare_attackers", "game-1", "me"), "Attack", "x", decision))
        val step = ComboLoop.step(ComboLoop.commandFrom(decision.legalActions!![0], "game-1", 7), "x", "act-77", decision)!!
        val resolving = snapshot(ownTrigger = true, passOffered = true)
        assertTrue("the round started with an empty stack", ComboLoop.waitsForStack(step, resolving))
        assertFalse("the trigger is ours", ComboLoop.opponentResponded(resolving))
        assertEquals("pass_priority", ComboLoop.pass(resolving)?.command?.type)
        assertFalse(ComboLoop.waitsForStack(step, decision))
    }

    @Test fun digestSeesToughnessAndSummaries() {
        val before = snapshot()
        assertNotEquals("−1/−1 until end of turn is progress", ComboLoop.digest(before), ComboLoop.digest(snapshot(callerToughness = 2)))
        assertEquals(ComboLoop.digest(before), ComboLoop.digest(snapshot()))
        assertTrue(ComboLoop.opponentResponded(snapshot(opponentStack = true)))
        assertEquals("Repeated 12 times · Tavern AI 12 → 0", ComboLoop.summary(12, before, snapshot(opponentLife = 0)))
        val round = listOf(ComboStep(ComboStep.Kind.ACTION, "activate_ability", "Chatterfang", "x"),
            ComboStep(ComboStep.Kind.PROMPT, "choose_target", null, "GAME_TARGET", listOf(ComboTarget("Kinjalli's Caller", "opponent", "creature"))))
        assertEquals(listOf("Activate Chatterfang", "Choose an opponent's creature"), ComboLoop.preview(round))
        assertEquals("Round 3 · Activate Chatterfang → Kinjalli's Caller", ComboLoop.roundLine(3, round, listOf("Kinjalli's Caller")))
        assertTrue(ComboRepeat.Times(10).watchable)
        assertFalse(ComboRepeat.Times(20).watchable)
        assertFalse(ComboRepeat.UntilWin.watchable)
        assertNotNull(ComboLoop.cycle(List(3) { ComboStep(ComboStep.Kind.ACTION, "activate_ability", "Krark-Clan Ironworks", "x") }))
        assertNull(snapshot(prompt = true).withoutPrompts().promptEnvelopeV2)
    }
}
