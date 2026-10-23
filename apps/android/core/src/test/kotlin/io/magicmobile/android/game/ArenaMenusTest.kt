package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Arena menus' rules, as iOS Menus/ArenaPlayPanel.swift, ArenaDeckBox.swift, ArenaHomeView.swift and OnDeviceRootView.swift apply them. */
class ArenaMenusTest {
    private fun match(id: String, date: Long, mode: PlayMode, deck: String, outcome: RankOutcome, foe: String? = "Krenko") =
        MatchRecord(id = id, date = date, mode = mode, opponents = listOfNotNull(foe?.let { MatchOpponent(it, null, true) }),
            deckID = deck, deckName = "Deck $deck", deckBracket = 2, outcome = outcome, turns = 8)

    @Test fun tabsKeepTheOlderMenusIdentifiers() {
        assertEquals(listOf("menu.tab.home", "menu.profile", "menu.decks", "menu.tab.ranked", "menu.howToPlay"),
            ArenaMenuTab.entries.map { it.identifier })
        assertEquals(listOf("Home", "Profile", "Decks", "Ranked", "Learn"), ArenaMenuTab.entries.map { it.title })
    }

    @Test fun aUtilityPanelLightsItsIconInsteadOfATab() {
        assertNull(ArenaMenuTab.lit(utilityOpen = true, decksOpen = true, learnOpen = false, lobby = null))
        assertEquals(ArenaMenuTab.DECKS, ArenaMenuTab.lit(false, true, true, "profile"))
        assertEquals(ArenaMenuTab.LEARN, ArenaMenuTab.lit(false, false, true, null))
        assertEquals(ArenaMenuTab.PROFILE, ArenaMenuTab.lit(false, false, false, "profile"))
        assertEquals(ArenaMenuTab.RANKED, ArenaMenuTab.lit(false, false, false, "leaderboard"))
        assertEquals(ArenaMenuTab.HOME, ArenaMenuTab.lit(false, false, false, null))
        assertEquals("menu.settings", ArenaTopBarLit.of(options = true, updates = true, downloads = false, friends = false))
        assertEquals("menu.friends", ArenaTopBarLit.of(false, false, false, true))
        assertNull(ArenaTopBarLit.of(false, false, false, false))
    }

    @Test fun titlesAreSerifFromSeventeenPoints() {
        assertFalse(ArenaMenuType.isTitle(16.9f))
        assertTrue(ArenaMenuType.isTitle(17f))
        assertTrue(ArenaMenuType.isTitle(24f))
    }

    @Test fun quickMatchResolvesMatchMyDeckToAtMostOptimized() {
        assertEquals(2, ArenaPlayRules.quickResolvedBracket(0, null))
        assertEquals(3, ArenaPlayRules.quickResolvedBracket(0, CommanderBracket.UPGRADED))
        assertEquals(4, ArenaPlayRules.quickResolvedBracket(0, CommanderBracket.CEDH))
        assertEquals(1, ArenaPlayRules.quickResolvedBracket(1, CommanderBracket.OPTIMIZED))
        assertEquals("Match my deck · B4", ArenaPlayRules.matchedLabel(CommanderBracket.CEDH))
        assertEquals("Match my deck", ArenaPlayRules.matchedLabel(null))
    }

    @Test fun rankedAllowsDecksUpToTheTiersLimit() {
        assertTrue(ArenaPlayRules.rankedEligible(CommanderBracket.CORE, RankTier.BRONZE))
        assertFalse(ArenaPlayRules.rankedEligible(CommanderBracket.UPGRADED, RankTier.BRONZE))
        assertTrue(ArenaPlayRules.rankedEligible(CommanderBracket.OPTIMIZED, RankTier.DIAMOND))
        assertFalse(ArenaPlayRules.rankedEligible(null, RankTier.MYTHIC))
    }

    @Test fun headingsAndRulesFollowTheTabAndMode() {
        assertEquals("Quick Match", ArenaPlayRules.heading(ArenaPlayTab.FIND, ArenaPlayMode.QUICK))
        assertEquals("Custom Table", ArenaPlayRules.heading(ArenaPlayTab.FIND, ArenaPlayMode.CUSTOM))
        assertEquals("Play with Friends", ArenaPlayRules.heading(ArenaPlayTab.FRIENDS, ArenaPlayMode.RANKED))
        assertEquals("Recently Played", ArenaPlayRules.heading(ArenaPlayTab.RECENT, ArenaPlayMode.QUICK))
        assertEquals("100 cards · 1v1", ArenaPlayRules.rulesLine(ArenaPlayMode.RANKED))
        assertEquals("100 cards · up to 4 players", ArenaPlayRules.rulesLine(ArenaPlayMode.CUSTOM))
    }

    @Test fun thePlaqueIsNamedForTheChoice() {
        val quick = ArenaPlayRules.primary(ArenaPlayTab.FIND, ArenaFriendWay.CHALLENGE, ArenaPlayMode.QUICK, false, mayStart = false, rankedEligible = true)
        assertEquals(ArenaPlayPrimary("Play", "quick.start", false, ArenaPlayAction.START_QUICK), quick)
        val ranked = ArenaPlayRules.primary(ArenaPlayTab.FIND, ArenaFriendWay.CHALLENGE, ArenaPlayMode.RANKED, false, mayStart = true, rankedEligible = false)
        assertEquals("ranked.find", ranked.identifier)
        assertFalse(ranked.enabled)
        assertEquals("Set Up Table", ArenaPlayRules.primary(ArenaPlayTab.FIND, ArenaFriendWay.HOST, ArenaPlayMode.CUSTOM, false, false, false).title)
        assertEquals(ArenaPlayAction.HOST, ArenaPlayRules.primary(ArenaPlayTab.FRIENDS, ArenaFriendWay.HOST, ArenaPlayMode.QUICK, false, false, false).action)
        assertEquals("Join Table", ArenaPlayRules.primary(ArenaPlayTab.FRIENDS, ArenaFriendWay.JOIN, ArenaPlayMode.QUICK, false, false, false).title)
        // No tables yet: the plaque leads to Find Match; after a game it plays the chosen table's way.
        assertEquals(ArenaPlayAction.FIND_MATCH_TAB, ArenaPlayRules.primary(ArenaPlayTab.RECENT, ArenaFriendWay.CHALLENGE, ArenaPlayMode.QUICK, true, true, true).action)
        assertEquals(ArenaPlayAction.START_QUICK, ArenaPlayRules.primary(ArenaPlayTab.RECENT, ArenaFriendWay.CHALLENGE, ArenaPlayMode.QUICK, false, true, true).action)
    }

    @Test fun recentlyPlayedKeepsTheNewestTableOfEachWayAndDeck() {
        val matches = listOf(
            match("a", 10, PlayMode.QUICK, "precon:x", RankOutcome.LOSS),
            match("b", 30, PlayMode.QUICK, "precon:x", RankOutcome.WIN, foe = "Atraxa"),
            match("c", 20, PlayMode.RANKED, "precon:x", RankOutcome.DRAW, foe = null),
            match("d", 40, PlayMode.CASUAL, "local:gone", RankOutcome.WIN))
        val recent = ArenaPlayRules.recentGames(matches, setOf("precon:x"))
        assertEquals(listOf("b", "c"), recent.map { it.id })
        assertEquals("vs Atraxa", recent[0].detail)
        assertEquals(true, recent[0].won)
        assertEquals("vs the table", recent[1].detail)
        assertNull(recent[1].won)
        assertEquals("Ranked", recent[1].modeTitle)
        assertEquals(2, ArenaPlayRules.recentGames((1..10).map { match("m$it", it.toLong(), PlayMode.entries[it % 3], "d$it", RankOutcome.WIN) },
            (1..10).map { "d$it" }.toSet(), limit = 2).size)
    }

    @Test fun aRecentTableIsChosenByItsDeckAndWay() {
        val game = ArenaRecentGame("g", PlayMode.CASUAL, "precon:x", "X", null, emptyList(), "vs Foe", null)
        assertTrue(ArenaPlayRules.isChosen(game, "precon:x", ArenaPlayMode.CUSTOM))
        assertFalse(ArenaPlayRules.isChosen(game, "precon:x", ArenaPlayMode.QUICK))
        assertFalse(ArenaPlayRules.isChosen(game, "precon:y", ArenaPlayMode.CUSTOM))
        assertEquals(ArenaPlayMode.RANKED, ArenaPlayMode.of("ranked"))
        assertEquals(ArenaPlayMode.QUICK, ArenaPlayMode.of("unknown"))
    }

    @Test fun theDeckGridFitsAtLeastTwoBoxes() {
        assertEquals(2 to 133f, ArenaPlayRules.deckGrid(308f, compact = true))
        val (columns, width) = ArenaPlayRules.deckGrid(600f, compact = false)
        assertEquals(4, columns)
        assertEquals(129f, width)
        assertEquals(2, ArenaPlayRules.deckGrid(100f, compact = false).first)
    }

    @Test fun theBoxKeepsTheReferenceProportions() {
        val g = ArenaBoxGeometry(120f)
        assertEquals(108.6f, g.frontWidth, 0.01f)
        assertEquals(1.34f, g.frontWidth / g.frontHeight, 0.0001f)
        assertEquals(g.top + g.lidBand, g.frontTop(0f), 0.0001f)
        assertEquals(g.top + g.cut, g.frontTop(1f), 0.0001f)
        assertEquals(24f, ArenaBoxGeometry(70f).plateHeight, 0.0001f)
        assertEquals(13f, ArenaBoxGeometry(70f).pip, 0.0001f)
    }

    @Test fun deckColoursFollowTheCommandersInWubrgOrder() {
        val identities = mapOf("Atraxa" to listOf("G", "W", "U", "B"), "Krenko" to listOf("R"), "Kozilek" to emptyList())
        assertEquals(listOf("W", "U", "B", "G"), ArenaDeckColors.colors(listOf("Atraxa"), identities::get))
        assertEquals(listOf("R"), ArenaDeckColors.colors(listOf("Krenko", "Kozilek"), identities::get))
        assertEquals(emptyList<String>(), ArenaDeckColors.colors(listOf("Krenko", "Unknown"), identities::get))
        assertEquals(emptyList<String>(), ArenaDeckColors.colors(emptyList(), identities::get))
    }

    @Test fun homeArtKeepsItsFocusInViewWithoutShowingAnEdge() {
        // A square picture in a wide frame: it fills the width and moves up to bring a focus near the top into view.
        val wide = ArenaHomeArtCrop.place(1000f, 1000f, 400f, 200f, 0.5f, 0.2f)
        assertEquals(400f, wide.width, 0.01f)
        assertEquals(0f, wide.x, 0.01f)
        assertEquals(0f, wide.y, 0.01f)
        val low = ArenaHomeArtCrop.place(1000f, 1000f, 400f, 200f, 0.5f, 0.6f)
        assertEquals(-140f, low.y, 0.01f)
        // The focus never pulls the picture past its edge.
        val edge = ArenaHomeArtCrop.place(1000f, 1000f, 400f, 200f, 0.5f, 1f)
        assertEquals(-200f, edge.y, 0.01f)
        val tall = ArenaHomeArtCrop.place(1252f, 916f, 100f, 300f, 0.62f, 0.3f)
        assertEquals(300f, tall.height, 0.01f)
        assertTrue(tall.x <= 0f && tall.x >= 100f - tall.width)
    }

    @Test fun featuresTurnBothWaysAndWrap() {
        assertEquals(0, ArenaFeatureTurn.step(3, 1, 4))
        assertEquals(3, ArenaFeatureTurn.step(0, -1, 4))
        assertEquals(0, ArenaFeatureTurn.step(2, 1, 0))
        assertEquals(1, ArenaFeatureTurn.swipe(-61f))
        assertEquals(-1, ArenaFeatureTurn.swipe(61f))
        assertEquals(0, ArenaFeatureTurn.swipe(-40f))
    }
}
