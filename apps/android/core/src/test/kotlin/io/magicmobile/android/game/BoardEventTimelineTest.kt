package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors BoardEventTimelineTests.swift testCommanderCastAndEntranceAreCeremonial (iOS build 26). */
class BoardEventTimelineTest {
    private fun state(cards: List<BoardFXState.Card>, stack: List<BoardFXState.StackItem> = emptyList()) =
        BoardFXState("match", "main", mapOf("a" to 40, "b" to 40), cards.associateBy { it.id }, stack)

    private fun fxCard(id: String, player: String, zone: BoardFXZone = BoardFXZone.BATTLEFIELD, name: String = "Bear") =
        BoardFXState.Card(id, player, zone, name, BoardFXTint.GREEN, 0, 0, false)

    private fun moment(id: String, player: String = "a", name: String = "Bear", counters: Map<String, Int> = emptyMap(),
                       power: Int = 2, toughness: Int = 2, phasedOut: Boolean = false) =
        BoardFXState.Card(id, player, BoardFXZone.BATTLEFIELD, name, BoardFXTint.GREEN, 0, counters.values.sum(), false,
            counterKinds = counters, power = power, toughness = toughness, phasedOut = phasedOut)

    /** Mirrors testCountersAndLifeGainAreReported / testCounterKindsAreReportedSeparatelyAndRemovalsToo (iOS). */
    @Test fun counterKindsAddedAndRemoved() {
        val before = state(listOf(moment("bear"), moment("walker", name = "Liliana", counters = mapOf("loyalty" to 5))))
        val after = state(listOf(moment("bear", counters = mapOf("-1/-1" to 1, "shield" to 1), power = 1, toughness = 1),
            moment("walker", name = "Liliana", counters = mapOf("loyalty" to 3))))
        assertEquals(listOf(BoardFXEvent.CountersChanged("bear", BoardFXCounterKind.MINUS_ONE, 1),
            BoardFXEvent.CountersChanged("bear", BoardFXCounterKind.OTHER, 1),
            BoardFXEvent.CountersChanged("walker", BoardFXCounterKind.LOYALTY, -2)), BoardEventDiffer.events(before, after))
        val grown = state(listOf(moment("bear", counters = mapOf("+1/+1" to 2), power = 4, toughness = 4)))
        assertEquals(listOf(BoardFXEvent.CountersChanged("bear", BoardFXCounterKind.PLUS_ONE, 2)),
            BoardEventDiffer.events(state(listOf(moment("bear"))), grown))
    }

    /** Mirrors testPumpIsAStatsChangeBeyondWhatCountersExplain and testCounterLabelsSayWhatTheCountersDo (iOS). */
    @Test fun pumpAndLabels() {
        val pumped = state(listOf(moment("bear", counters = mapOf("+1/+1" to 1), power = 6, toughness = 3)))
        assertEquals(listOf(BoardFXEvent.CountersChanged("bear", BoardFXCounterKind.PLUS_ONE, 1), BoardFXEvent.StatsChanged("bear", 3, 0)),
            BoardEventDiffer.events(state(listOf(moment("bear"))), pumped))
        assertEquals("-2/-2", BoardFXCounterKind.MINUS_ONE.label(2))
        assertEquals("+3/+3", BoardFXCounterKind.PLUS_ONE.label(3))
        assertEquals("-1/-1", BoardFXCounterKind.PLUS_ONE.label(-1))
        assertEquals("-3", BoardFXCounterKind.LOYALTY.label(-3))
        assertEquals("+1", BoardFXCounterKind.of("charge").label(1))
    }

    /** Mirrors testPhasingTransformAndControlChange (iOS). */
    @Test fun phasingTransformAndControl() {
        val before = state(listOf(moment("bear"), moment("delver", name = "Delver of Secrets"), moment("ogre")))
        val after = state(listOf(moment("bear", phasedOut = true), moment("delver", name = "Insectile Aberration", power = 3), moment("ogre", player = "b")))
        assertEquals(listOf(BoardFXEvent.Phased("bear", true), BoardFXEvent.Transformed("delver", "Insectile Aberration"),
            BoardFXEvent.ControlChanged("ogre", "a", "b")), BoardEventDiffer.events(before, after))
        val back = state(listOf(moment("bear"), moment("delver", name = "Insectile Aberration", power = 3), moment("ogre", player = "b")))
        assertEquals(listOf(BoardFXEvent.Phased("bear", false)), BoardEventDiffer.events(after, back))
    }

    private fun board(a: List<ZoneCard>, b: List<ZoneCard>, revision: Int): GameSnapshot {
        fun seat(id: String, battlefield: List<ZoneCard>) =
            PlayerGameState(id, id, 40, 0, 0, null, PlayerZones(emptyList(), emptyList(), battlefield, emptyList(), emptyList(), emptyList(), emptyList()))
        return GameSnapshot("match", "xmage-ondevice", "a", "main", "main", 3, "a", players = listOf(seat("a", a), seat("b", b)),
            log = emptyList(), bridgeRevision = revision, viewerPlayerId = "a")
    }

    /** Mirrors testArrivalSoundsFollowLandTypesCardTypesAndCreatureTypes (iOS). */
    @Test fun arrivalSoundsFollowLandTypesCardTypesAndCreatureTypes() {
        fun plan(type: String, cost: String? = null, isToken: Boolean = false, commander: Boolean = false) =
            BoardFXArrivalSound.plan(CardIdentity("x", type, null, manaCost = cost), isToken, commander)
        fun creature(heavy: Boolean, voice: String?) = BoardFXArrivalSound.Creature(heavy, voice)
        assertEquals(BoardFXArrivalSound.BasicLand("forest"), plan("Basic Land — Forest"))
        assertEquals(BoardFXArrivalSound.BasicLand("swamp"), plan("Basic Land - Swamp"))
        assertEquals("a dual sounds like its first basic type", BoardFXArrivalSound.BasicLand("island"), plan("Land — Island Mountain"))
        assertEquals(BoardFXArrivalSound.BasicLand("forest"), plan("Land Creature — Forest Dryad"))
        assertEquals(BoardFXArrivalSound.OtherLand, plan("Land"))
        assertEquals(creature(false, "wizard"), plan("Creature — Merfolk Wizard", "{1}{U}"))
        assertEquals("no voice yet: a card placed", creature(false, null), plan("Creature — Merfolk", "{1}{U}"))
        assertEquals(creature(true, null), plan("Creature — Spirit", "{6}"))
        assertEquals(creature(false, "bear"), plan("Creature — Bear", "{1}{G}"))
        assertEquals(creature(false, "human"), plan("Creature — Human Soldier", "{1}{W}"))
        assertEquals("the first subtype with a voice", creature(false, "human"), plan("Creature — Human Wizard", "{U}"))
        assertEquals(creature(false, "elf"), plan("Creature — Elf Druid", "{G}"))
        assertEquals(creature(true, "dragon"), plan("Creature — Dragon", "{4}{R}{R}"))
        assertEquals(creature(false, "dragon"), plan("Creature — Drake", "{1}{U}"))
        assertEquals(creature(true, "goblin"), plan("Legendary Creature — Goblin Shaman", "{R}", commander = true))
        assertEquals(creature(false, "squirrel"), plan("Token Creature — Squirrel", isToken = true))
        assertEquals("a creature first", creature(true, "sliver"), plan("Artifact Creature — Sliver", "{6}"))
        assertEquals(creature(false, "orc"), plan("Creature — Ogre Warrior", "{3}{R}"))
        assertEquals(creature(true, "giant"), plan("Creature — Giant", "{5}{R}"))
        assertEquals(creature(false, "beast"), plan("Creature — Hydra", "{X}{G}{G}"))
        assertEquals(creature(true, "dinosaur"), plan("Creature — Dinosaur", "{5}{G}"))
        assertEquals(creature(true, "horror"), plan("Creature — Demon", "{3}{B}{B}"))
        assertEquals(creature(false, "rat"), plan("Creature — Rat", "{B}"))
        assertEquals(creature(false, "critter"), plan("Creature — Fox", "{W}"))
        assertEquals(creature(true, "eldrazi"), plan("Legendary Creature — Eldrazi", "{11}"))
        assertEquals(creature(false, "insect"), plan("Token Creature — Spider", isToken = true))
        assertEquals(creature(false, "wolf"), plan("Creature — Werewolf", "{2}{G}"))
        assertEquals(BoardFXArrivalSound.Artifact, plan("Artifact", "{1}"))
        assertEquals(BoardFXArrivalSound.Enchantment, plan("Enchantment — Aura", "{1}{W}{U}"))
        assertEquals(BoardFXArrivalSound.Planeswalker, plan("Legendary Planeswalker — Liliana", "{1}{B}{B}"))
        assertEquals("one sound for every planeswalker", BoardFXArrivalSound.Planeswalker, plan("Legendary Planeswalker — Ajani", "{4}{W}"))
        assertEquals(BoardFXArrivalSound.Other, plan("Battle — Siege", "{2}{R}"))
    }

    /** Mirrors testCastSoundsFollowTheSpellsType (iOS). */
    @Test fun castSoundsFollowTheSpellsType() {
        fun cast(type: String) = BoardFXCastSound.of(CardIdentity("x", type, null))
        assertEquals(BoardFXCastSound.INSTANT, cast("Instant"))
        assertEquals(BoardFXCastSound.INSTANT, cast("Tribal Instant — Goblin"))
        assertEquals(BoardFXCastSound.SORCERY, cast("Sorcery"))
        assertEquals(BoardFXCastSound.PERMANENT, cast("Creature — Elf"))
        assertEquals(BoardFXCastSound.PERMANENT, cast("Artifact"))
        assertEquals(BoardFXCastSound.PERMANENT, BoardFXCastSound.of(null))
    }

    /** Mirrors testStolenCardIsHiddenUntilTheChainDragsItHome (iOS). */
    @Test fun stolenCardIsHiddenUntilTheChainDragsItHome() {
        val ogre = ZoneCard("ogre", CardIdentity("Grizzly Bears", "Creature", null, manaCost = "{1}{G}"), power = 2, toughness = 2, isCreaturePermanent = true)
        val start = 2_500_000L
        val director = BoardFXDirector()
        director.ingest(board(emptyList(), listOf(ogre), 1), BoardFXLevel.FULL, start)
        director.ingest(board(listOf(ogre), emptyList(), 2), BoardFXLevel.FULL, start)
        val steal = director.active.first { it.scheduled.event == BoardFXEvent.ControlChanged("ogre", "b", "a") }.scheduled
        assertEquals("Grizzly Bears", director.subjects["ogre"]?.card?.name)
        assertEquals(steal.delay + steal.duration * BoardFXScheduler.stealLandingFraction, steal.landing, 1e-9)
        assertTrue(BoardFXScheduler.stealHookFraction < BoardFXScheduler.stealLandingFraction)
        assertEquals(listOf(BoardFXCardMotion.Hidden(start, 0.0, steal.landing)), director.cardMotion("a").hidden["ogre"])
        val reduced = BoardFXDirector()
        reduced.ingest(board(emptyList(), listOf(ogre), 1), BoardFXLevel.REDUCED, start)
        reduced.ingest(board(listOf(ogre), emptyList(), 2), BoardFXLevel.REDUCED, start)
        assertNull("reduced motion keeps the tile in place", reduced.cardMotion("a").hidden["ogre"])
    }

    @Test fun commanderCastIsItsOnlyCeremony() {
        val inCommand = state(listOf(fxCard("cmd", "a", BoardFXZone.COMMAND, name = "Atraxa")))
        val cast = state(emptyList(), listOf(BoardFXState.StackItem("s", "Atraxa", "a", BoardFXTint.MULTICOLOR, manaValue = 4)))
        assertEquals(listOf(BoardFXEvent.SpellCast("s", "Atraxa", "a", BoardFXTint.MULTICOLOR, BoardFXSpellWeight.COMMANDER)),
            BoardEventDiffer.events(inCommand, cast, setOf("Atraxa")))
        val entered = state(listOf(fxCard("cmd-2", "a", name = "Atraxa")))
        // The cast was the ceremony; the commander then flies off the stack without a second one.
        assertEquals(listOf(BoardFXEvent.EnteredBattlefield("cmd-2", "a", BoardFXZone.STACK, BoardFXTint.GREEN, BoardFXEntrance.PLAIN)),
            BoardEventDiffer.events(cast, entered, setOf("Atraxa")))
        // Put straight onto the battlefield (no cast seen), it gets the ceremony on arrival.
        assertEquals(BoardFXEvent.EnteredBattlefield("cmd-2", "a", null, BoardFXTint.GREEN, BoardFXEntrance.COMMANDER),
            BoardEventDiffer.events(inCommand, entered, setOf("Atraxa")).last())
    }

    /** Mirrors testSmartPassHoldsForSpellsAndRemovalButNotTriggers. */
    @Test fun smartPassHoldsForSpellsAndRemovalButNotTriggers() {
        val held = listOf(
            BoardFXEvent.SpellCast("s", "Path to Exile", "b", BoardFXTint.WHITE, BoardFXSpellWeight.SPELL),
            BoardFXEvent.LeftBattlefield("bear", "a", BoardFXZone.EXILE, BoardFXTint.GREEN),
            BoardFXEvent.EnteredBattlefield("angel", "b", BoardFXZone.HAND, BoardFXTint.WHITE, BoardFXEntrance.SHOWCASE))
        val quick = listOf(
            BoardFXEvent.SpellCast("t", "Soul Warden", "b", BoardFXTint.WHITE, BoardFXSpellWeight.ABILITY),
            BoardFXEvent.LifeChanged("b", 1),
            BoardFXEvent.EnteredBattlefield("land", "a", BoardFXZone.HAND, BoardFXTint.COLORLESS, BoardFXEntrance.PLAIN))
        for (level in listOf(BoardFXLevel.FULL, BoardFXLevel.REDUCED)) {
            assertTrue("$level", BoardFXScheduler.schedule(held, level).all { it.holdsSmartPass })
            assertFalse("$level", BoardFXScheduler.schedule(quick, level).any { it.holdsSmartPass })
        }
    }

    /** Mirrors testRemovalPlaysInOrderBeforeAnythingElse (Caleb, 2026-10-15: Path to Exile flashed by under the next plays). */
    @Test fun removalPlaysInOrderBeforeAnythingElse() {
        for (level in listOf(BoardFXLevel.FULL, BoardFXLevel.REDUCED)) {
            val batch = BoardFXScheduler.schedule(listOf(
                BoardFXEvent.SpellCast("s", "Path to Exile", "b", BoardFXTint.WHITE, BoardFXSpellWeight.SPELL),
                BoardFXEvent.LeftBattlefield("commander", "a", BoardFXZone.EXILE, BoardFXTint.GREEN),
                BoardFXEvent.EnteredBattlefield("plains", "b", BoardFXZone.HAND, BoardFXTint.WHITE, BoardFXEntrance.PLAIN),
                BoardFXEvent.LifeChanged("b", 1)), level)
            assertTrue("$level: the exile waits for the whole read", batch[1].delay >= batch[0].end - 1e-9)
            assertTrue("$level: the next play waits for the exile", batch[2].delay >= batch[1].end - 1e-9)
            assertEquals(batch[0].end, batch[0].holdsLaterBatchesUntil)
            assertEquals(batch[1].end, batch[1].holdsLaterBatchesUntil)
        }
        val triggers = BoardFXScheduler.schedule(listOf(
            BoardFXEvent.SpellCast("t", "Trigger", "b", BoardFXTint.WHITE, BoardFXSpellWeight.ABILITY),
            BoardFXEvent.LifeChanged("b", 1)), BoardFXLevel.FULL)
        assertTrue("repeated triggers keep their pace", triggers[1].delay < triggers[0].end)
    }

    /** Mirrors testTokenPileChoosesTheNextAndShowsChosenBeside. */
    @Test fun tokenPileChoosesTheNextAndShowsChosenBeside() {
        val squirrels = (1..10).map { ZoneCard("sq$it", CardIdentity("Squirrel", "Token Creature — Squirrel", isToken = true)) }
        val pile = BattlefieldCardGroup("pile", squirrels)
        val all = squirrels.map { it.instanceId }.toSet()
        assertEquals(listOf(10), BattlefieldTokenStack.displayGroups(pile, false, emptySet()).map { it.count })
        assertEquals("sq1", BattlefieldTokenStack.nextTargetable(pile, all, emptySet())?.instanceId)
        val chosen = setOf("sq1", "sq2")
        val tiles = BattlefieldTokenStack.displayGroups(pile, false, chosen)
        assertEquals(listOf(8, 1, 1), tiles.map { it.count })
        assertEquals("pile", tiles.first().id)
        assertEquals(listOf("sq1", "sq2"), tiles.drop(1).map { it.representative.instanceId })
        assertEquals("sq3", BattlefieldTokenStack.nextTargetable(pile, all, chosen)?.instanceId)
        assertEquals(listOf(9, 1), BattlefieldTokenStack.displayGroups(pile, false, setOf("sq2")).map { it.count })
        assertEquals(10, BattlefieldTokenStack.displayGroups(pile, true, chosen).size)
        assertNull(BattlefieldTokenStack.nextTargetable(pile, all, all))
    }

    /** Restacking (PortraitPolishTests.testOpenedPilesRestack on iOS). */
    @Test fun openedPilesRestack() {
        val squirrels = (1..3).map { ZoneCard("sq$it", CardIdentity("Squirrel", "Token Creature — Squirrel", isToken = true)) }
        val pile = BattlefieldCardGroup("pile", squirrels)
        val lone = BattlefieldCardGroup("card:x", listOf(squirrels[0]))
        assertEquals(mapOf("sq3" to "pile"), BattlefieldTokenStack.stackChipPiles(listOf(pile, lone), setOf("pile", "card:x")))
        assertEquals(emptyMap<String, String>(), BattlefieldTokenStack.stackChipPiles(listOf(pile), emptySet()))
        assertEquals(setOf("look"), BattlefieldTokenStack.openAfterChoice(setOf("look", "choose"), setOf("choose")))
    }
}
