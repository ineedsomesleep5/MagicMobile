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
}
