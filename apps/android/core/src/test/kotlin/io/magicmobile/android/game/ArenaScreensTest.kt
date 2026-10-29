package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Arena board's full-table screens (phase D): which screen takes a question, its copy, and the trigger order. */
class ArenaScreensTest {
    private fun ability(id: String) = XmagePromptAbility(id, "Trigger $id")
    private fun object_(name: String, type: String = "TRIGGERED_ABILITY") = XmageStackObject(id = "o-$name", objectType = type, name = name, sourceName = name)

    @Test fun headlineKeepsShortQuestionsWhole() {
        val short = ArenaScreens.headline("Pay 2 life?", null, null)
        assertEquals("Pay 2 life?", short.title)
        assertNull(short.detail)
    }

    @Test fun headlineSplitsALongQuestionAtItsMarkAndNeverRepeatsIt() {
        val message = "Use Esper Sentinel's ability? An opponent cast a noncreature spell and may pay {X} to stop you drawing a card."
        val headline = ArenaScreens.headline(message, object_("Esper Sentinel"), null)
        assertEquals("Use Esper Sentinel's ability?", headline.title)
        assertEquals("An opponent cast a noncreature spell and may pay {X} to stop you drawing a card.", headline.detail)
    }

    @Test fun headlineNamesTheAbilityWhenTheMessageIsAboutIt() {
        val message = "Whenever a Goblin you control enters, you may put a quest counter on Quest for the Goblin Lord and keep going."
        val headline = ArenaScreens.headline(message, object_("Quest for the Goblin Lord"), null)
        assertEquals("Use Quest for the Goblin Lord's ability?", headline.title)
        assertEquals(message, headline.detail)
    }

    @Test fun headlineKeepsOneLongSentenceWhole() {
        val message = "Return target creature card with mana value three or less from your graveyard to the battlefield tapped"
        val card = ZoneCard("c1", CardIdentity("Some Creature", "Creature"))
        val headline = ArenaScreens.headline(message, null, card)
        assertEquals(message, headline.title)
        assertNull(headline.detail)
    }

    @Test fun triggerPlanPlacesThePicksInReverseAndEndsAtPriority() {
        val order = listOf(ability("a"), ability("b"), ability("c"))
        // a resolves first, so it goes on the stack last.
        assertEquals(listOf("c", "b", "a"), ArenaScreens.triggerPlan(order))
        val prompt = PromptEnvelopeV2(id = "p", method = "GAME_PICK_ABILITY", messageId = 2, playerId = "human", responseKind = "ability",
            message = "Pick triggered ability (goes to the stack first)", abilities = listOf(ability("a"), ability("b")),
            responseCommand = XmageResponseCommand("choose_ability", "p", 2))
        val snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.NORMAL_BATTLEFIELD).copy(promptEnvelopeV2 = prompt)
        // c is on the stack already: b is next.
        val step = ArenaScreens.triggerStep(snapshot, listOf("c", "b", "a"), "p:1", pending = false)
        assertEquals(listOf("b", "a"), step.plan)
        assertEquals("b", step.pick?.id)
        assertEquals("p:2", step.sent)
        // The same prompt again: nothing more to send.
        assertNull(ArenaScreens.triggerStep(snapshot, step.plan, step.sent, pending = false).pick)
        // While the plan answers it, the browser stays away.
        assertTrue(ArenaScreens.triggerPlanAnswers(snapshot, ArenaScreenContext(triggerPlan = listOf("b", "a"), triggerSent = "p:1")))
        assertNull(ArenaScreens.abilityPrompt(snapshot, ArenaScreenContext(triggerPlan = listOf("b", "a"), triggerSent = "p:1")))
        assertNotNull(ArenaScreens.abilityPrompt(snapshot, ArenaScreenContext()))
        val priority = snapshot.copy(promptEnvelopeV2 = prompt.copy(id = "q", method = "GAME_SELECT", abilities = null, responseKind = "priority",
            responseCommand = XmageResponseCommand("pass_priority", "q", 3)))
        assertTrue(ArenaScreens.triggerStep(priority, listOf("a"), "p:2", pending = false).plan.isEmpty())
    }

    @Test fun modeBrowserTitleAndCountRule() {
        val snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.MODE_CHOICE)
        val modes = ArenaScreens.modePrompt(snapshot)!!
        assertEquals("Choose modes", ArenaScreens.modeTitle(modes))
        assertEquals("Up to 3, at least 1", ArenaScreens.modeDetail(modes))
        assertEquals("Create a Treasure token. You lose 1 life.", ArenaScreens.modeText("1. Create a Treasure token. You lose 1 life."))
        assertEquals(2, ArenaScreens.modeColumns(3, landscape = false))
        assertEquals(3, ArenaScreens.modeColumns(3, landscape = true))
        assertNull("the mode browser takes it, not the question stage", ArenaScreens.question(snapshot, emptySet(), null, false, ArenaScreenContext()))
    }

    @Test fun mayTriggerIsAQuestionAboutItsCard() {
        val snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.MAY_TRIGGER_PROMPT)
        val question = ArenaScreens.question(snapshot, emptySet(), null, false, ArenaScreenContext())
        assertNotNull(question)
        assertEquals("preview-may-trigger:6", question!!.key)
        assertFalse(ArenaScreens.screenPrompt(snapshot, ArenaScreenContext()))
        assertTrue(ArenaScreens.declines("No"))
        assertFalse(ArenaScreens.declines("Yes"))
        // The opening hand has its own screen.
        assertNull(ArenaScreens.question(GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.OPENING_HAND), emptySet(), null, false, ArenaScreenContext()))
    }

    @Test fun startingPlayerQuestionIsAPlayerChoice() {
        val snapshot = GameBoardPreviewFixtures.startingPlayerPrompt()
        val players = ArenaScreens.playerPrompt(snapshot, ArenaScreenContext())
        assertNotNull(players)
        assertEquals(2, players!!.seats.size)
        assertEquals("You", players.seats.first().name)
        assertEquals("choose_target", players.type)
        assertEquals("Choose who goes first", ArenaScreens.playerChoiceTitle(players.prompt.message))
        assertNull("the roll answers it while it is up", ArenaScreens.playerPrompt(snapshot, ArenaScreenContext(startingRollVisible = true)))
        assertEquals(2, ArenaScreens.playerColumns(4, landscape = false))
    }

    @Test fun splitSetupAndItsLine() {
        val snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.DAMAGE_ASSIGNMENT_PROMPT)
        val split = ArenaScreens.splitPrompt(snapshot, ArenaScreenContext())!!
        val setup = ArenaScreens.splitSetup(split, snapshot)
        assertEquals(2, setup.rows.size)
        assertEquals(listOf(1, 1), setup.rows.map { it.initial })
        assertEquals("4 of 6 left to give", ArenaScreens.splitDetail(2, 6, 6))
        assertEquals("All 6 given out", ArenaScreens.splitDetail(6, 6, 6))
        assertEquals("1 too many", ArenaScreens.splitDetail(7, 6, 6))
        assertEquals("3 given", ArenaScreens.splitDetail(3, null, null))
    }

    @Test fun cardChoiceCopy() {
        val scry = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.SCRY_CHOICE).promptEnvelopeV2!!
        val kind = if (CardChoicePlan.supportsDraft(scry)) CardChoicePlan.kind(scry) else null
        assertEquals("Scry", ArenaCardChoice.title(kind, scry.message))
        assertEquals(ArenaCardChoice.Zones.SCRY, ArenaCardChoice.zones(kind, scry.message))
        assertNull("the wells say where cards go", ArenaCardChoice.instruction(kind, scry))
        val search = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.LIBRARY_CHOICE).promptEnvelopeV2!!
        val searchKind = if (CardChoicePlan.supportsDraft(search)) CardChoicePlan.kind(search) else null
        assertEquals("Search your library", ArenaCardChoice.title(searchKind, search.message))
        assertEquals("Search your library for a land card", ArenaCardChoice.instruction(searchKind, search))
        // Landscape keeps the title room under the opponent's medallion: a 360 dp tall phone gets small cards, never below 74.
        assertEquals(120f, ArenaCardChoice.cardWidth(800f, 360f, 3, false, false), 0.01f)
        assertEquals(74f, ArenaCardChoice.cardWidth(800f, 260f, 3, false, false), 0.01f)
        assertEquals(ArenaScreens.zoneColumns(1), 1)
        assertEquals(ArenaScreens.zoneColumns(7), 3)
        assertEquals("No cards", ArenaScreens.zoneDetail("Your graveyard", emptyList(), false))
        assertEquals("Face down", ArenaScreens.zoneDetail("Library", emptyList(), false))
    }

    @Test fun deckPickerOpensOnTheChosenShelfOrPreconsWhenYouHaveNoDecks() {
        val shelves = listOf("mine" to emptyList(), "precons" to listOf("precon:a", "precon:b"), "included-2" to listOf("bracket:x"))
        assertEquals("precons", ArenaPlayRules.landingShelf(shelves, "precon:b"))
        assertEquals("included-2", ArenaPlayRules.landingShelf(shelves, "bracket:x"))
        assertEquals("an empty My Decks never comes first", "precons", ArenaPlayRules.landingShelf(shelves, "missing"))
        assertNull(ArenaPlayRules.landingShelf(listOf("mine" to listOf("local:1"), "precons" to listOf("precon:a")), "missing"))
    }

    @Test fun decksPageBoxesFitAShortLandscapePage() {
        val tall = io.magicmobile.android.studio.ArenaDecksPage.grid(780f, 600f)
        assertEquals(io.magicmobile.android.studio.ArenaDecksPage.grid(780f), tall)
        val short = io.magicmobile.android.studio.ArenaDecksPage.grid(780f, 180f)
        val geometry = ArenaBoxGeometry(short.boxWidth)
        assertTrue(short.columns > tall.columns)
        assertTrue("a whole box with its plate fits above the strip",
            geometry.rise * 1.5f + geometry.boxHeight + geometry.plateHeight - geometry.plateOverlap <= 180f - 52f)
    }

    @Test fun startingPlayerHeadingAndResult() {
        val base = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.OPENING_HAND)
        assertEquals("You Go First", base.copy(turn = 1, activePlayerId = base.viewerID).startingPlayerHeading)
        assertEquals("${base.playerLabel("ai-1")} Goes First", base.copy(turn = 1, activePlayerId = "ai-1").startingPlayerHeading)
        assertNull(base.copy(turn = 2, activePlayerId = "ai-1").startingPlayerHeading)
        val victory = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.VICTORY)
        assertEquals(ArenaGameResult.Outcome.VICTORY, ArenaGameResult.outcome(victory))
        assertEquals(ArenaGameResult.Outcome.DRAW, ArenaGameResult.outcome(victory.copy(winnerPlayerIds = emptyList())))
        assertEquals(ArenaGameResult.Outcome.DEFEAT, ArenaGameResult.outcome(victory.copy(winnerPlayerIds = listOf("ai-1"))))
    }
}
