package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors the smart-pass cases in apps/ios/MagicMobileTests/OnDeviceYieldPolicyTests.swift. */
class OnDeviceSmartPassTest {
    private fun context(myTurn: Boolean = true, emptyStack: Boolean = true) = OnDeviceYieldPolicy.Context(
        "match", "seat", "viewer", if (myTurn) "viewer" else "other", 3, "running", true, true, emptyStack, true, false,
        OnDeviceYieldPolicy.Prompt("prompt", 10, "SELECT", "priority", true, false, "viewer"))

    private fun situation(hasPlay: Boolean, step: String? = "PRECOMBAT_MAIN", myTurn: Boolean = true, emptyStack: Boolean = true) =
        OnDeviceSmartPass.Situation(context(myTurn, emptyStack), step, hasPlay, false)

    private val settings = OnDeviceSmartPass.Settings()

    @Test fun passesWithNothingToPlayAndStopsWhereMarked() {
        assertNotNull(OnDeviceSmartPass.passPrompt(situation(false), settings))
        assertNotNull(OnDeviceSmartPass.passPrompt(situation(false, emptyStack = false), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true, "POSTCOMBAT_MAIN"), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true, "END_TURN", myTurn = false), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true, "DECLARE_ATTACKERS", myTurn = false), settings))
        assertNotNull(OnDeviceSmartPass.passPrompt(situation(true, "UPKEEP"), settings))
        assertNotNull(OnDeviceSmartPass.passPrompt(situation(true, "PRECOMBAT_MAIN", myTurn = false), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true, "UPKEEP", emptyStack = false), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true, "mystery"), settings))
        val custom = settings.copy(stops = setOf(OnDeviceSmartPass.stopKey(OnDeviceSmartPass.Step.UPKEEP, true)))
        assertNull(OnDeviceSmartPass.passPrompt(situation(true, "UPKEEP"), custom))
        assertNotNull(OnDeviceSmartPass.passPrompt(situation(true), custom))
    }

    @Test fun neverAnswersAChoiceFloatingManaOrWhenOff() {
        assertNull(OnDeviceSmartPass.passPrompt(situation(false).copy(manaFloating = true), settings))
        assertNull(OnDeviceSmartPass.passPrompt(situation(false), OnDeviceSmartPass.Settings(enabled = false)))
        val base = situation(false)
        val prompt = base.context.prompt!!
        val changes = listOf(
            base.context.copy(prompt = prompt.copy(kind = "ASK")), base.context.copy(prompt = prompt.copy(selectMode = "attackers")),
            base.context.copy(prompt = prompt.copy(selectMode = "blockers")), base.context.copy(prompt = prompt.copy(submitted = true)),
            base.context.copy(prompt = prompt.copy(manaPlayerID = "other")), base.context.copy(prompt = null),
            base.context.copy(selfAuthority = false), base.context.copy(resyncRequired = true), base.context.copy(foreground = false),
            base.context.copy(localHumanEnabled = false), base.context.copy(phase = "ended"))
        for (change in changes) assertNull(OnDeviceSmartPass.passPrompt(base.copy(context = change), settings))
    }

    @Test fun readsPlayablesManaAndStoredStops() {
        fun view(category: String, row: String) = Json.parseToJsonElement("""{"canPlayObjects":{"objects":{"card":{"$category":[$row]}}}}""")
        assertFalse(OnDeviceSmartPass.hasPlay(null))
        assertFalse(OnDeviceSmartPass.hasPlay(view("basicManaAbilities", """{"id":"a"}""")))
        assertFalse(OnDeviceSmartPass.hasPlay(view("other", """{"id":"a","manaAbility":true}""")))
        assertTrue(OnDeviceSmartPass.hasPlay(view("other", """{"id":"a"}""")))
        assertTrue(OnDeviceSmartPass.hasPlay(view("basicPlayAbilities", """{"id":"a"}""")))
        assertFalse(OnDeviceSmartPass.manaFloating(Json.parseToJsonElement("""{"manaPool":{"black":0,"green":0}}""")))
        assertTrue(OnDeviceSmartPass.manaFloating(Json.parseToJsonElement("""{"manaPool":{"black":0,"green":1}}""")))
        assertEquals(OnDeviceSmartPass.defaultStops, OnDeviceSmartPass.Settings.decode(null))
        assertEquals(emptySet<String>(), OnDeviceSmartPass.Settings.decode(""))
        assertEquals(OnDeviceSmartPass.defaultStops,
            OnDeviceSmartPass.Settings.decode(OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops)))
        mapOf("UPKEEP" to OnDeviceSmartPass.Step.UPKEEP, "precombat-main" to OnDeviceSmartPass.Step.MAIN1,
            "BEGIN_COMBAT" to OnDeviceSmartPass.Step.BEGIN_COMBAT, "FIRST_COMBAT_DAMAGE" to OnDeviceSmartPass.Step.COMBAT_DAMAGE,
            "END_TURN" to OnDeviceSmartPass.Step.END, "POSTCOMBAT_MAIN" to OnDeviceSmartPass.Step.MAIN2)
            .forEach { (raw, step) -> assertEquals(raw, step, OnDeviceSmartPass.Step.fromEngine(raw)) }
        assertNull(OnDeviceSmartPass.Step.fromEngine("UNTAP"))
        // The stored keys are the iOS raw values, so both apps read the same words.
        assertEquals("mine.declareAttackers", OnDeviceSmartPass.stopKey(OnDeviceSmartPass.Step.DECLARE_ATTACKERS, true))
    }

    /** Mirrors testOnlyPassesSentForThePlayerCountAsAutomatic: passes sent for the player show no waiting pop-up. */
    @Test fun onlyPassesSentForThePlayerCountAsAutomatic() {
        assertTrue(OnDeviceYieldPolicy.isAutomaticPass(OnDeviceYieldPolicy.SMART_PASS_ACTION_PREFIX + "p1"))
        assertTrue(OnDeviceYieldPolicy.isAutomaticPass(OnDeviceYieldPolicy.YIELD_PASS_ACTION_PREFIX + "p1"))
        for (tapped in listOf(null, "pass_priority-p1", "cast-spell-42", "auto-ability-7", "starting-roll-p1")) {
            assertFalse("$tapped", OnDeviceYieldPolicy.isAutomaticPass(tapped))
        }
    }

    /** Engine release A: your own spell or trigger on top resolves (unless you asked to stop for those); an opponent's
     *  stops only with a play that answers it; an attack with nothing that answers it passes even at a stop. */
    @Test fun usesStackControllersAndResponses() {
        fun value(step: String = "UPKEEP", empty: Boolean = false, mine: Boolean?, response: Boolean, myTurn: Boolean = true) =
            situation(true, step, myTurn, empty).copy(topStackIsMine = mine, hasResponse = response)
        assertNotNull("own trigger resolves", OnDeviceSmartPass.passPrompt(value(mine = true, response = true), settings))
        assertNull(OnDeviceSmartPass.passPrompt(value(mine = true, response = true), settings.copy(stopForOwnSpells = true)))
        assertNull("an answer to their spell stops", OnDeviceSmartPass.passPrompt(value(mine = false, response = true), settings))
        assertNotNull("nothing answers it", OnDeviceSmartPass.passPrompt(value(mine = false, response = false), settings))
        assertNull("older engine: today's stop", OnDeviceSmartPass.passPrompt(value(mine = null, response = true), settings))
        assertNull(OnDeviceSmartPass.passPrompt(value("DECLARE_ATTACKERS", true, null, true, myTurn = false), settings))
        assertNotNull(OnDeviceSmartPass.passPrompt(value("DECLARE_ATTACKERS", true, null, false, myTurn = false), settings))
        assertNull(OnDeviceSmartPass.passPrompt(value("PRECOMBAT_MAIN", true, null, false), settings))
    }

    @Test fun readsEngineControllersAndResponseFlags() {
        val root = Json.parseToJsonElement("""{"stackOrder":["s2","s1"],"stackControllers":{"s2":"viewer","s1":"other"}}""")
        assertEquals(true, OnDeviceSmartPass.topStackIsMine(root, "viewer"))
        assertEquals(false, OnDeviceSmartPass.topStackIsMine(root, "other"))
        assertNull(OnDeviceSmartPass.topStackIsMine(Json.parseToJsonElement("""{"stackOrder":["s2"]}"""), "viewer"))
        fun view(rows: String) = Json.parseToJsonElement("""{"canPlayObjects":{"objects":{"c1":{"spells":$rows}}}}""")
        assertFalse(OnDeviceSmartPass.hasResponse(view("""[{"respondsToStack":false}]""")))
        assertTrue(OnDeviceSmartPass.hasResponse(view("""[{"respondsToStack":false},{"respondsToStack":true}]""")))
        assertTrue("a missing flag counts as a response", OnDeviceSmartPass.hasResponse(view("[{}]")))
        assertFalse("mana abilities never count", OnDeviceSmartPass.hasResponse(view("""[{"manaAbility":true}]""")))
    }

    /** Caleb, 2026-10-27: Zur's attack trigger resolved before Gogo could copy it. Your own trigger stops when an ability
     *  of yours could answer it, and still resolves with only a counterspell in hand. */
    @Test fun ownTriggerStopsForAnAbilityThatCanUseIt() {
        val own = situation(true, "DECLARE_ATTACKERS", true, false).copy(topStackIsMine = true, hasResponse = true)
        assertNotNull("a counterspell alone doesn't stop your trigger", OnDeviceSmartPass.passPrompt(own, settings))
        assertNull("Gogo gets the chance to copy it", OnDeviceSmartPass.passPrompt(own.copy(hasAbilityResponse = true), settings))
        fun view(rows: String) = Json.parseToJsonElement("""{"canPlayObjects":{"objects":{"c1":{"other":$rows}}}}""")
        val counterspell = """{"spellAbility":true,"respondsToStack":true}"""
        assertTrue(OnDeviceSmartPass.hasAbilityResponse(view("""[$counterspell,{"spellAbility":false,"respondsToStack":true}]""")))
        assertFalse("spells don't count", OnDeviceSmartPass.hasAbilityResponse(view("[$counterspell]")))
        assertFalse("only an explicit flag counts", OnDeviceSmartPass.hasAbilityResponse(view("""[{"spellAbility":false}]""")))
    }
}
