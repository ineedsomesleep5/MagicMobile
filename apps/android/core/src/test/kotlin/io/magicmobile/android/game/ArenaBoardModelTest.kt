package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/** Mirrors apps/ios/MagicMobileTests/ArenaBoardModelTests.swift: the same cases, the same numbers. */
class ArenaBoardModelTest {
    private fun mana(id: String, source: String, label: String, produced: List<String>? = null, card: String? = null) =
        LegalAction(id = id, type = "make_mana", playerId = "p1", label = label, sourceInstanceId = source, cardInstanceId = source,
            producedMana = produced, cardName = card)

    private fun tap(actionID: String, color: String? = null) = ArenaAutoPay.Step.Tap(actionID, color)

    @Test fun boardModeDefaultsToArena() {
        assertEquals(BoardMode.ARENA, BoardMode.resolved("arena"))
        assertEquals(BoardMode.HEARTH, BoardMode.resolved("hearth"))
        assertEquals(BoardMode.ARENA, BoardMode.resolved("tavern"))
        assertEquals(BoardMode.ARENA, BoardMode.resolved(""))
        assertEquals(BoardMode.ARENA, BoardMode.resolved(null))
        assertEquals("arena", BoardMode.defaultValue)
        assertEquals(BoardMode.ARENA, BoardMode.entries.first())
        assertEquals("magicmobile.boardMode", BoardMode.key)
        assertTrue(CardFramesPreference.hearthDefault)
        assertFalse(CardFramesPreference.arenaDefault)
    }

    @Test fun needReadsXMagePaymentText() {
        val need = ArenaAutoPay.need("Pay {2}{R}{R}")
        assertEquals(2, need.generic)
        assertEquals(2, need.symbols["R"])
        assertEquals(mapOf("R" to 1), ArenaAutoPay.need("Pay {X}{R}").symbols.toMap())
        assertEquals(1, ArenaAutoPay.need("{R/P}").symbols["R"])
        assertEquals(listOf(listOf("W", "U")), ArenaAutoPay.need("{W/U}").hybrids.toList())
        assertEquals(1, ArenaAutoPay.need("{C}").symbols["C"])
        assertTrue(ArenaAutoPay.need("Paid").isEmpty)
    }

    @Test fun productionReadsManaAbilityLabels() {
        assertEquals(listOf(listOf("R")), ArenaAutoPay.production(mana("a", "m", "{T}: Add {R}."))?.options)
        assertEquals(listOf(listOf("W"), listOf("U")), ArenaAutoPay.production(mana("a", "d", "{T}: Add {W} or {U}."))?.options)
        val ring = ArenaAutoPay.production(mana("a", "s", "{T}: Add {C}{C}."))!!
        assertEquals(2, ring.amount)
        assertTrue(ring.colorlessOnly)
        assertTrue(ArenaAutoPay.production(mana("a", "t", "{T}: Add one mana of any color in your commander's color identity."))!!.anyColor)
        assertNull(ArenaAutoPay.production(mana("a", "x", "{1}, {T}: Add {G}{G}.")))
        assertNull(ArenaAutoPay.production(mana("a", "x", "{T}, Pay 1 life: Add {B}.")))
        assertEquals(listOf(listOf("G")), ArenaAutoPay.production(mana("a", "x", "Basic", listOf("g")))?.options)
        assertEquals(2, ArenaAutoPay.production(mana("a", "x", "Tap Sol Ring", listOf("C", "C")))?.amount)
        assertEquals(listOf(listOf("W"), listOf("U")), ArenaAutoPay.production(mana("a", "x", "Tap", listOf("W", "U")))?.options)
        // A painland's damage rider never reads as mana.
        assertEquals(listOf(listOf("R"), listOf("W")),
            ArenaAutoPay.production(mana("a", "p", "{T}: Add {R} or {W}. Battlefield Forge deals 1 damage to you."))?.options)
    }

    @Test fun colouredPipsComeFirstAndGenericTakesTheRest() {
        val mountain = mana("mountain", "m1", "{T}: Add {R}.")
        val island = mana("island", "i1", "{T}: Add {U}.")
        assertEquals(tap("mountain"), ArenaAutoPay.next("Pay {1}{R}", emptyMap(), listOf(island, mountain)))
        assertEquals(tap("island"), ArenaAutoPay.next("Pay {1}", emptyMap(), listOf(island)))
        assertEquals(ArenaAutoPay.Step.Done, ArenaAutoPay.next("Paid", emptyMap(), listOf(island)))
    }

    @Test fun singleColourSourcesBeforeDualsAndRocksThatFit() {
        val mountain = mana("mountain", "m1", "{T}: Add {R}.")
        val ventsU = mana("vents-u", "v1", "{T}: Add {U}.")
        val ventsR = mana("vents-r", "v1", "{T}: Add {R}.")
        assertEquals(tap("mountain"), ArenaAutoPay.next("{R}", emptyMap(), listOf(ventsU, ventsR, mountain)))
        val ring = mana("ring", "s1", "{T}: Add {C}{C}.")
        // {1}: a basic, so the two-mana rock isn't half wasted; {2}: the rock.
        assertEquals(tap("mountain"), ArenaAutoPay.next("{1}", emptyMap(), listOf(ring, mountain)))
        assertEquals(tap("ring"), ArenaAutoPay.next("{2}", emptyMap(), listOf(ring, mountain)))
    }

    @Test fun anyColourSourcesWaitUntilNeeded() {
        val tower = mana("tower", "t1", "{T}: Add one mana of any color in your commander's color identity.")
        val forest = mana("forest", "f1", "{T}: Add {G}.")
        assertEquals(tap("forest"), ArenaAutoPay.next("{G}", emptyMap(), listOf(tower, forest)))
        assertEquals(tap("tower", "G"), ArenaAutoPay.next("{G}", emptyMap(), listOf(tower)))
    }

    /** Caleb's Squirrel Girl ({1}{G}{G}{G}): the Treasure is spent only because nothing else makes the third green. */
    @Test fun treasurePaysTheColourNothingElseMakes() {
        val forest = mana("forest", "f1", "{T}: Add {G}.")
        val oran = mana("oran", "o1", "{T}: Add {G}.")
        val swarmyard = mana("swarmyard", "y1", "{T}: Add {C}.")
        val swamp = mana("swamp", "s1", "{T}: Add {B}.")
        val treasure = mana("treasure", "t1", "{T}, Sacrifice this artifact: Add one mana of any color.")
        val actions = listOf(treasure, swamp, swarmyard, oran, forest)
        val plan = ArenaAutoPay.plan(ArenaAutoPay.need("{1}{G}{G}{G}"), ArenaAutoPay.sources(actions))!!
        assertEquals(setOf("f1", "o1", "t1", "y1"), plan.map { it.key }.toSet())
        assertEquals("G", plan.first { it.key == "t1" }.color)
        assertTrue(ArenaAutoPay.next("{1}{G}{G}{G}", emptyMap(), actions) is ArenaAutoPay.Step.Tap)
        // With a second green land the Treasure stays.
        val forest2 = mana("forest2", "f2", "{T}: Add {G}.")
        val without = ArenaAutoPay.plan(ArenaAutoPay.need("{G}{G}{G}"), ArenaAutoPay.sources(actions + forest2))!!
        assertFalse(without.any { it.key == "t1" })
    }

    /** A tri-land makes one mana of three colours; a land that can tap or sacrifice is only tapped when tapping is enough. */
    @Test fun triLandsMakeOneManaAndLandsAreTappedBeforeSacrificed() {
        val triome = mana("triome", "x1", "{T}: Add {W}, {B}, or {G}.")
        assertEquals(listOf(listOf("W"), listOf("B"), listOf("G")), ArenaAutoPay.production(triome)?.options)
        assertNull("one tap can't pay two pips", ArenaAutoPay.plan(ArenaAutoPay.need("{W}{B}"), ArenaAutoPay.sources(listOf(triome))))
        val veinTap = mana("vein-tap", "v1", "{T}: Add {C}.")
        val veinSac = mana("vein-sac", "v1", "{T}, Sacrifice Crystal Vein: Add {C}{C}.", card = "Crystal Vein")
        val plains = mana("plains", "p1", "{T}: Add {W}.")
        val plan = ArenaAutoPay.plan(ArenaAutoPay.need("{2}"), ArenaAutoPay.sources(listOf(veinSac, veinTap, plains)))!!
        assertEquals(setOf("vein-tap", "plains"), plan.map { it.actionID }.toSet())
        // With nothing else it still sacrifices when it has to.
        val alone = ArenaAutoPay.plan(ArenaAutoPay.need("{2}"), ArenaAutoPay.sources(listOf(veinSac, veinTap)))!!
        assertEquals(listOf("vein-sac"), alone.map { it.actionID })
    }

    /** Colours are checked before the first tap: two white from one Plains can't be paid, so nothing is tapped. */
    @Test fun colourShortCostIsBlockedBeforeAnyTap() {
        val plains = mana("plains", "p1", "{T}: Add {W}.")
        val swamp = mana("swamp", "s1", "{T}: Add {B}.")
        val island = mana("island", "i1", "{T}: Add {U}.")
        assertTrue("only one white source", ArenaAutoPay.next("{W}{W}", emptyMap(), listOf(plains, swamp, island)) is ArenaAutoPay.Step.Blocked)
        // A tri-land is spent after the lands that make one colour, and a bounce land pays both its colours.
        val triome = mana("triome", "x1", "{T}: Add {W}, {B}, or {G}.")
        val triomeB = mana("triome-b", "x1", "{T}: Add {B}.")
        assertEquals(tap("swamp"), ArenaAutoPay.next("{B}", emptyMap(), listOf(triomeB, triome, swamp)))
        val bounce = ArenaAutoPay.plan(ArenaAutoPay.need("{B}{R}"),
            listOf(ArenaAutoPay.Source("c1", mutableListOf(ArenaAutoPay.Source.Yield("carnarium", listOf("B", "R"), 10)))))!!
        assertEquals(listOf("c1"), bounce.map { it.key })
    }

    /** A sacrifice of anything but the source itself (Ashnod's Altar) or a life payment stays a manual choice. */
    @Test fun onlySelfSacrificeCountsAsAManaSource() {
        assertNull(ArenaAutoPay.production(mana("a", "x", "Sacrifice a creature: Add {C}{C}.")))
        assertEquals(true, ArenaAutoPay.production(mana("a", "x", "Sacrifice this artifact: Add one mana of any color."))?.sacrifices)
    }

    @Test fun floatingManaIsSpentFirst() {
        val mountain = mana("mountain", "m1", "{T}: Add {R}.")
        assertEquals(ArenaAutoPay.Step.Spend("R"), ArenaAutoPay.next("{R}", mapOf("R" to 1), listOf(mountain)))
        assertEquals(ArenaAutoPay.Step.Spend("G"), ArenaAutoPay.next("{1}{R}", mapOf("G" to 2), listOf(mountain)))
    }

    @Test fun neverStartsACostItCannotFinish() {
        val mountain = mana("mountain", "m1", "{T}: Add {R}.")
        val ventsU = mana("vents-u", "v1", "{T}: Add {U}.")
        val ventsR = mana("vents-r", "v1", "{T}: Add {R}.")
        assertTrue("needs green", ArenaAutoPay.next("{G}", emptyMap(), listOf(mountain)) is ArenaAutoPay.Step.Blocked)
        // A dual land counts once however many abilities it has.
        assertTrue("three owed, two sources", ArenaAutoPay.next("{3}", emptyMap(), listOf(mountain, ventsU, ventsR)) is ArenaAutoPay.Step.Blocked)
    }

    @Test fun handRestsTuckedUntilOpened() {
        assertEquals(ArenaHandPosture.RESTING, ArenaHandPosture.resolve(ArenaHandPosture.Situation()))
        assertEquals(ArenaHandPosture.RAISED, ArenaHandPosture.resolve(ArenaHandPosture.Situation(opened = true)))
        assertEquals(ArenaHandPosture.RESTING, ArenaHandPosture.resolve(ArenaHandPosture.Situation(opened = true, boardDecision = true)))
        assertEquals(ArenaHandPosture.RESTING, ArenaHandPosture.resolve(ArenaHandPosture.Situation(opened = true, dragging = true)))
        assertEquals(ArenaHandPosture.RESTING, ArenaHandPosture.resolve(ArenaHandPosture.Situation(opened = true, spectating = true)))
    }

    @Test fun fanSlotsCentreAndSpread() {
        val hand = ArenaLayout.landscapeLayout.hand
        val only = ArenaHandFanLayout.slot(0, 1, ArenaHandPosture.RAISED, hand)
        assertEquals(hand.centerX, only.center.x, 0.0001f)
        assertEquals(0f, only.rotation, 0.0001f)
        val left = ArenaHandFanLayout.slot(0, 7, ArenaHandPosture.RAISED, hand)
        val right = ArenaHandFanLayout.slot(6, 7, ArenaHandPosture.RAISED, hand)
        assertEquals(hand.centerX * 2, left.center.x + right.center.x, 0.001f)
        assertTrue(left.rotation < 0)
        assertTrue(left.center.y > ArenaHandFanLayout.slot(3, 7, ArenaHandPosture.RAISED, hand).center.y)
        val resting = ArenaHandFanLayout.slot(0, 7, ArenaHandPosture.RESTING, hand)
        assertEquals(hand.downScale, resting.scale, 0.0001f)
        assertTrue(resting.center.y > left.center.y)
    }

    /** A full raised hand stays whole on the landscape screen: no card's lowest corner reaches below the floor. */
    @Test fun raisedLandscapeHandNeverRunsOffTheScreen() {
        val hand = ArenaLayout.landscapeLayout.hand
        for (count in 1..12) for (index in 0 until count) {
            val slot = ArenaHandFanLayout.slot(index, count, ArenaHandPosture.RAISED, hand)
            val tilt = Math.toRadians(abs(slot.rotation).toDouble())
            val corner = slot.center.y + hand.card.height / 2 * cos(tilt).toFloat() + hand.card.width / 2 * sin(tilt).toFloat()
            assertTrue("card $index of $count", corner <= hand.upFloor + 0.001f)
        }
        assertEquals(hand.upY, ArenaHandFanLayout.slot(0, 1, ArenaHandPosture.RAISED, hand).center.y, 0.0001f)
    }

    @Test fun canvasScalesEachAxisAndSizesByTheSmaller() {
        val max = ArenaCanvas(BoardSize(956f, 440f))
        assertTrue(max.layout.landscape)
        assertEquals(BoardPoint(478f, 220f), max.point(BoardPoint(478f, 220f)))
        val small = ArenaCanvas(BoardSize(375f, 667f))
        assertFalse(small.layout.landscape)
        assertEquals(small.scaleY, small.scale, 0.0001f)
        assertEquals(100f * 667 / 956, small.length(100f), 0.001f)
        // A design rectangle keeps its centre by axis and sizes by the smaller scale; an area stretches both ways.
        val wide = ArenaCanvas(BoardSize(800f, 360f))
        val rect = wide.rect(BoardRect(100f, 100f, 50f, 50f))
        assertEquals(125f * wide.scaleX, rect.midX, 0.001f)
        assertEquals(50f * wide.scale, rect.width, 0.001f)
        assertEquals(50f * wide.scaleX, wide.area(BoardRect(100f, 100f, 50f, 50f)).width, 0.001f)
    }

    @Test fun creatureLanesGrowTowardTheirOwner() {
        val layout = ArenaLayout.portraitLayout
        assertEquals(2, layout.maxCreatureRows)
        assertEquals(1, ArenaLayout.landscapeLayout.maxCreatureRows)
        val mine = layout.creatureLane(true, 2); val mineOne = layout.creatureLane(true, 1)
        assertEquals(mineOne.minY, mine.minY, 0.0001f)
        assertTrue(mine.maxY > mineOne.maxY)
        val theirs = layout.creatureLane(false, 2); val theirsOne = layout.creatureLane(false, 1)
        assertEquals(theirsOne.maxY, theirs.maxY, 0.0001f)
        assertTrue(theirs.minY < theirsOne.minY)
    }

    /** Landscape's front row is the table's full width (788 pt): eight cards at full size, then they shrink, a thirteenth scrolls. */
    @Test fun landscapeFrontRowFitsTwelveCardsBeforeScrolling() {
        val layout = ArenaLayout.landscapeLayout
        val width = layout.creatureLane(true, 1).width
        val card = layout.tiles(false).first.width
        fun fit(count: Int, side: Int = 0) = ArenaRowFit.fit(List(count) { 1f }, List(side) { 1f }, width, card, layout.maxCreatureRows)
        assertEquals(788f, width, 0.0001f)
        assertEquals(card, fit(8).cardWidth, 0.0001f)
        assertTrue(fit(9).cardWidth < card)
        assertFalse(fit(12).overflows)
        assertTrue(fit(12).cardWidth >= card * ArenaRowFit.minimumScale)
        assertTrue(fit(13).overflows)
        assertEquals(1, fit(13).rows)
        // A planeswalker's section takes its share of the same row at the same card size.
        val walker = fit(8, side = 1)
        assertTrue(walker.cardWidth < card)
        assertEquals(ArenaRowFit.sectionWidth(listOf(1f), walker.cardWidth), walker.trailingWidth, 0.0001f)
        assertEquals(ArenaRowFit.sectionWidth(listOf(1f, 1f), card), fit(0, side = 2).trailingWidth, 0.0001f)
    }

    /** Portrait opens a second front row before cards get much smaller, and holds twelve before scrolling. */
    @Test fun portraitFrontRowOpensASecondRowThenShrinks() {
        val layout = ArenaLayout.portraitLayout
        val width = layout.creatureLane(true, 1).width
        val card = layout.tiles(false).first.width
        fun fit(count: Int) = ArenaRowFit.fit(List(count) { 1f }, emptyList(), width, card, layout.maxCreatureRows, card * 0.85f)
        assertEquals(1, fit(5).rows)
        assertEquals(2, fit(6).rows)
        assertEquals(card, fit(6).cardWidth, 0.0001f)
        assertFalse(fit(12).overflows)
        assertTrue(fit(13).overflows)
        // Two planeswalkers stack into the two rows beside ten creatures.
        val walkers = ArenaRowFit.fit(List(10) { 1f }, listOf(1f, 1f), width, card, layout.maxCreatureRows, card * 0.85f)
        assertFalse(walkers.overflows)
        assertEquals(2, walkers.rows)
        assertEquals(ArenaRowFit.sectionWidth(listOf(1f), walkers.cardWidth), walkers.trailingWidth, 0.0001f)
        // One pile never needs two rows, however wide.
        assertEquals(1, ArenaRowFit.fit(listOf(4f), emptyList(), 200f, card, 2).rows)
    }

    private fun card(type: String, creature: Boolean? = null, name: String = type, id: String = type) =
        ZoneCard(instanceId = id, card = CardIdentity(name, type, null), isCreaturePermanent = creature)

    @Test fun planeswalkersBattlesAndSagasTakeTheSideSection() {
        assertEquals(ArenaFrontSection.CREATURES, ArenaFrontSection.of(card("Creature — Bear")))
        assertEquals(ArenaFrontSection.SIDE, ArenaFrontSection.of(card("Legendary Planeswalker — Liliana")))
        assertEquals(ArenaFrontSection.SIDE, ArenaFrontSection.of(card("Battle — Siege")))
        assertEquals(ArenaFrontSection.SIDE, ArenaFrontSection.of(card("Enchantment — Saga")))
        // A crewed Vehicle is a creature while it is one.
        assertEquals(ArenaFrontSection.CREATURES, ArenaFrontSection.of(card("Artifact — Vehicle", creature = true)))
        assertEquals(ArenaFrontSection.SUPPORT, ArenaFrontSection.of(card("Artifact — Vehicle")))
        assertEquals(ArenaFrontSection.SUPPORT, ArenaFrontSection.of(card("Artifact — Equipment")))
        assertEquals(ArenaFrontSection.SUPPORT, ArenaFrontSection.of(card("Enchantment")))
        assertTrue(ArenaFrontSection.sideRank(card("Legendary Planeswalker — Liliana")) > ArenaFrontSection.sideRank(card("Enchantment — Saga")))
    }

    // MARK: Real XMage polls (Fixtures/OnDevice: the production engine, recorded on the JVM)

    private val fixtures = File(File(System.getProperty("magicmobile.repo") ?: "../../.."), "apps/ios/MagicMobileTests/Fixtures/OnDevice")
    private fun snapshot(name: String): GameSnapshot {
        val poll = MatchPoll(EngineJson.decode(File(fixtures, "$name.json").readBytes()))
        return OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID)
    }

    /** Target questions recorded from the real engine (target-*.json, iOS ArenaBoardModelTests): where each one's choices are. */
    private fun targetQuestion(name: String): Pair<GameSnapshot, Set<String>> {
        val snapshot = snapshot(name)
        return snapshot to snapshot.promptEnvelopeV2!!.targetIds!!.toSet()
    }

    private fun names(snapshot: GameSnapshot, ids: List<String>) = ids.mapNotNull { id -> snapshot.players.firstOrNull { it.playerId == id }?.displayName }.toSet()

    /** Gogo copying Zur's attack trigger: the abilities on the stack are the choices, named by their source. */
    @Test fun gogosChoicesAreTheAbilitiesOnTheStack() {
        val (snapshot, targetable) = targetQuestion("target-stack-ability")
        val reach = ArenaTargetReach.of(snapshot, targetable)
        assertEquals(targetable, reach.stack.toSet())
        assertFalse(reach.onTable)
        assertNull(reach.opponentToShow)
        assertEquals(setOf("Zur the Enchanter’s ability", "Gogo, Master of Mimicry’s ability"),
            snapshot.promptEnvelopeV2?.targets.orEmpty().map { it.label }.toSet())
        assertEquals(reach, ArenaTargetReach.of(snapshot))
    }

    /** Counterspell with two spells on the stack chooses on the stack too. */
    @Test fun aCounterspellChoosesOnTheStack() {
        val (snapshot, targetable) = targetQuestion("target-stack-spell")
        val reach = ArenaTargetReach.of(snapshot, targetable)
        assertEquals(listOf("Shock", "Lightning Bolt"), reach.stack.mapNotNull { id -> snapshot.stackTopFirst.firstOrNull { it.id == id }?.displayName })
    }

    /** A card in a graveyard is neither on the stack nor the table: the card browser shows it. */
    @Test fun graveyardChoicesAreTheBrowsersCards() {
        for (name in listOf("target-graveyard", "target-any-graveyard")) {
            val (snapshot, targetable) = targetQuestion(name)
            val reach = ArenaTargetReach.of(snapshot, targetable)
            assertTrue(name, reach.stack.isEmpty() && !reach.onTable && reach.opponentToShow == null)
            assertEquals(name, targetable, snapshot.promptEnvelopeV2?.cards.orEmpty().map { it.id }.toSet())
        }
    }

    /** Four players, Doom Blade: the creatures are Rook's and Bryn's while the board shows Wren; it turns once per question. */
    @Test fun fourPlayersTurnToAnOpponentWithChoices() {
        val (snapshot, targetable) = targetQuestion("target-four-player-creature")
        assertEquals("Wren", snapshot.opponent?.displayName)
        val reach = ArenaTargetReach.of(snapshot, targetable)
        assertFalse(reach.onTable)
        assertEquals(setOf("Rook", "Bryn"), names(snapshot, reach.hiddenOpponents))
        var tracker = BoardFocusTracker().observe(snapshot, followTurns = true)
        tracker = tracker.showTargets(BoardOpponentFocus.snapshot(snapshot, tracker.focusedID), targetable)
        assertEquals(reach.opponentToShow, tracker.focusedID)
        assertTrue(ArenaTargetReach.of(BoardOpponentFocus.snapshot(snapshot, tracker.focusedID), targetable).onTable)
        val wren = snapshot.players.first { it.displayName == "Wren" }.playerId
        tracker = tracker.select(wren).let { it.showTargets(BoardOpponentFocus.snapshot(snapshot, it.focusedID), targetable) }
        assertEquals(wren, tracker.focusedID)
    }

    /** Shock in the same game can aim at you, so the board stays and the swap row marks the others. */
    @Test fun fourPlayersStayWhenTheTableHasAChoice() {
        val (snapshot, targetable) = targetQuestion("target-four-player")
        val reach = ArenaTargetReach.of(snapshot, targetable)
        assertTrue(reach.onTable)
        assertNull(reach.opponentToShow)
        assertEquals(setOf("Rook", "Bryn"), names(snapshot, reach.hiddenOpponents))
    }

    /** XMage's real PLAY_MANA while casting Isamaru ({W}): Auto Pay taps a Plains with the same make_mana a tap on the land sends. */
    @Test fun autoPayTapsALandXMageOffersForTheRealCost() {
        val poll = MatchPoll(EngineJson.decode(File(fixtures, "2p-mana.json").readBytes()))
        val snapshot = OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID)
        assertEquals(true, snapshot.manaPayment?.active)
        assertEquals(mapOf("W" to 1), ArenaAutoPay.need(snapshot.manaPayment!!.remainingText!!).symbols.toMap())
        val step = ArenaAutoPay.next(snapshot) as ArenaAutoPay.Step.Tap
        val action = snapshot.legalActions!!.first { it.id == step.actionID }
        assertEquals("make_mana", action.type)
        val source = action.sourceInstanceId!!
        val land = snapshot.human!!.zones.battlefield.first { it.instanceId == source }
        assertTrue(land.card.typeLine.contains("Plains"))
        val command = GameCommand(type = action.type, gameId = snapshot.id, playerId = action.playerId, sourceInstanceId = source,
            promptId = action.promptId, messageId = action.messageId)
        assertEquals(EnginePrompt.answer("uuid", kotlinx.serialization.json.JsonPrimitive(source)),
            OnDevicePromptAdapter.answer(command, poll.prompt!!, snapshot.viewerID))
    }

    /** The real attacker selection reads as declaring attackers; the priority poll before it isn't combat. */
    @Test fun combatPhaseReadsTheRealAttackerPrompt() {
        val attackers = snapshot("2p-attackers")
        assertEquals(ArenaCombatPhase.ATTACKERS, ArenaCombatPhase.current(attackers))
        assertFalse(attackers.promptEnvelopeV2?.targets.isNullOrEmpty())
        assertTrue(attackers.legalActions?.any { it.type == "answer_yes_no" && it.confirmed != false } == true)
        assertNull(ArenaCombatPhase.current(snapshot("2p-priority")))
        val resolving = snapshot("2p-stack")
        assertNull(ArenaCombatPhase.current(resolving))
        assertEquals(ArenaAutoPay.Step.Done, ArenaAutoPay.next(resolving))
    }

    /**
     * Gogo copying Zur's attack trigger asks for a target in the declare attackers step: that question is a target to pick, not
     * the attack declaration. A library search there is a search.
     */
    @Test fun otherQuestionsDuringDeclareAttackersAreNotCombat() {
        val attackers = snapshot("2p-attackers")
        val prompt = attackers.promptEnvelopeV2!!
        val gogo = attackers.copy(legalActions = emptyList(), promptEnvelopeV2 = prompt.copy(method = "GAME_PICK_TARGET",
            message = "Select target activated or triggered ability you control"))
        assertNull(ArenaCombatPhase.current(gogo))
        assertTrue(MobilePromptPresentation.make(gogo, emptyList())?.kind != MobilePromptKind.COMBAT)
        val search = attackers.copy(legalActions = emptyList(), promptEnvelopeV2 = prompt.copy(method = "GAME_CHOOSE_CARD",
            responseKind = "choose_card", responseCommand = XmageResponseCommand(type = "choose_card")))
        assertNull(ArenaCombatPhase.current(search))
        assertTrue(MobilePromptPresentation.make(search, emptyList())?.kind != MobilePromptKind.COMBAT)
    }

    @Test fun extraHandHoldsOnlyCardsPlayableFromGraveyardOrExile() {
        fun sorcery(id: String, name: String) = ZoneCard(instanceId = id, card = CardIdentity(name, "Sorcery", null))
        val zones = PlayerZones(emptyList(), listOf(sorcery("h1", "Shock")), emptyList(),
            listOf(sorcery("g1", "Think Twice"), sorcery("g2", "Lava Spike")), listOf(sorcery("e1", "Light Up the Stage"), sorcery("e2", "Gone")),
            emptyList(), emptyList())
        val player = PlayerGameState("p1", "You", 40, 0, 0, null, zones)
        val actions = listOf("g1", "e1", "h1").map { LegalAction(id = "cast-$it", type = "cast_spell", playerId = "p1", label = "Cast", cardInstanceId = it) }
        assertEquals(listOf("g1", "e1"), ArenaExtraHand.cards(player, actions).map { it.instanceId })
        assertTrue(ArenaExtraHand.cards(player, emptyList()).isEmpty())
    }

    /** Caleb's replacement-effect question: two answers and their "Remember answer" twins become two cards and a toggle. */
    @Test fun choiceListPairsRememberedAnswersAndNamesTheCard() {
        val options = ArenaChoiceList.options(listOf(
            "a" to "Doubling Season: If an effect would create one or more tokens, it creates twice that many instead.",
            "b" to "Chatterfang, Squirrel General: If one or more tokens would be created, those plus that many Squirrels are created.",
            "c" to "Remember answer: Doubling Season: If an effect would create one or more tokens, it creates twice that many instead.",
            "d" to "Remember answer: Chatterfang, Squirrel General: If one or more tokens would be created, those plus that many Squirrels are created."))
        assertEquals(listOf("a", "b"), options.map { it.id })
        assertEquals(listOf("c", "d"), options.map { it.rememberID })
        assertEquals(listOf("Doubling Season", "Chatterfang, Squirrel General"), options.map { it.name })
        assertTrue(options[0].text.startsWith("If an effect"))
        assertNull("a plain word names no card", ArenaChoiceList.options(listOf("x" to "Elf")).first().name)
        assertEquals("XMage's id after the name", "Doubling Season",
            ArenaChoiceList.options(listOf("y" to "Doubling Season [8f2]: If an effect would create tokens…")).first().name)
        assertEquals("R", ArenaChoiceList.colorSymbol("Red"))
        assertEquals("G", ArenaChoiceList.colorSymbol("Green mana"))
        assertNull(ArenaChoiceList.colorSymbol("Goblin"))
    }

    @Test fun loyaltyCostsSplitFromPlaneswalkerAbilities() {
        assertEquals("+1", ArenaLoyalty.split("+1: Create a 2/2 black Zombie.")?.first)
        assertEquals("−4", ArenaLoyalty.split("-4: Each player sacrifices two creatures.")?.first)
        assertEquals("Each opponent chooses…", ArenaLoyalty.split("−9: Each opponent chooses…")?.second)
        assertEquals("0", ArenaLoyalty.split("0: Draw a card.")?.first)
        assertNull(ArenaLoyalty.split("Whenever a creature dies, draw a card."))
    }

    /** The X pill steps through XMage's values and starts at the most your mana pays. */
    @Test fun amountRangeStepsAndAffordableX() {
        val range = ArenaAmountRange(listOf(0, 1, 2, 3, 4, 5, 6, 7), null, null)
        assertEquals(7, range.step(3, 5))
        assertEquals(0, range.step(3, -5))
        assertEquals(4, range.step(3, 1))
        assertEquals("an open maximum stops 99 above", 100, ArenaAmountRange(null, 1, null).maximum)
        assertEquals("XMage's own bounds, negative too", listOf(-3, -2, -1), ArenaAmountRange(null, -3, -1).values)
        assertEquals(2, ArenaAmountRange(listOf(0, 2, 4), null, null).clamp(3))
        assertEquals("Devil's Play with eleven mana", 10, ArenaAmountRange.affordableX("{X}{R}", 11))
        assertEquals("Hydroid Krasis-style double X", 3, ArenaAmountRange.affordableX("{X}{X}{G}{U}", 8))
        assertEquals(0, ArenaAmountRange.affordableX("{X}{2}{R}", 2))
        assertNull(ArenaAmountRange.affordableX("{2}{R}", 9))
    }

    @Test fun splitRowsNameTheirCardAndLethalDamage() {
        assertEquals("Grizzly Bears", ArenaSplit.name("Grizzly Bears, P/T: 2/2"))
        assertEquals("Serra Angel", ArenaSplit.name("Serra Angel [4cb]"))
        assertEquals(3, ArenaSplit.lethal(4, 1, false))
        assertEquals(1, ArenaSplit.lethal(4, 0, true))
        assertEquals(1, ArenaSplit.lethal(2, 5, false))
    }

    @Test fun glossaryExplainsTheKeywordsACardHas() {
        assertEquals(listOf("Flying", "Vigilance", "Flashback"), ArenaKeywordGlossary.entries("Flying, vigilance\nFlashback {1}{G}").map { it.first })
        assertTrue("flashback isn't flash", ArenaKeywordGlossary.entries("Flashback {2}").all { it.first != "Flash" })
        assertTrue("equipped isn't equip", ArenaKeywordGlossary.entries("Equipped creature gets +1/+1.").isEmpty())
    }

    /** A carried card plays anywhere on the table above the hand but not over the corner, back in the hand, or after a wiggle. */
    @Test fun dropsCountOverTheWholeTableOutOfTheCorner() {
        val landscape = ArenaLayout.landscapeLayout
        assertTrue("your land row, from a popped card", landscape.drops(BoardPoint(240f, 320f), BoardPoint(330f, 300f)))
        assertTrue("the table's right side", landscape.drops(BoardPoint(820f, 150f), BoardPoint(500f, 330f)))
        assertFalse("the controls corner", landscape.drops(BoardPoint(780f, 330f), BoardPoint(500f, 330f)))
        assertFalse("back in the hand", landscape.drops(BoardPoint(500f, 400f), BoardPoint(500f, 300f)))
        assertFalse("a wiggle", landscape.drops(BoardPoint(330f, 280f), BoardPoint(330f, 300f)))
        assertFalse("a short slide sideways", landscape.drops(BoardPoint(380f, 300f), BoardPoint(330f, 300f)))
        val portrait = ArenaLayout.portraitLayout
        assertTrue("your land row", portrait.drops(BoardPoint(100f, 660f), BoardPoint(150f, 720f)))
        assertTrue("the far side", portrait.drops(BoardPoint(220f, 120f), BoardPoint(220f, 720f)))
        assertFalse("the hand", portrait.drops(BoardPoint(100f, 760f), BoardPoint(150f, 600f)))
    }

    /** Your piles leave room between them for their count badges, which hang 8 pt past a pile's right edge, and clear your medallion. */
    @Test fun viewerPilesLeaveRoomForTheirCounts() {
        for (layout in listOf(ArenaLayout.landscapeLayout, ArenaLayout.portraitLayout)) {
            val half = layout.viewerPile.width / 2
            val piles = (listOf(layout.viewerGraveyard, layout.viewerLibrary) + if (layout.landscape) listOf(layout.viewerExile) else emptyList()).sortedBy { it.x }
            for ((left, right) in piles.zipWithNext()) if (abs(left.y - right.y) < 1) assertTrue((right.x - half) - (left.x + half) >= 10)
            assertTrue("the first pile clears your medallion", layout.viewerMedallion.x + layout.viewerMedallionDiameter / 2 < piles[0].x - half)
        }
    }

    private fun stealSnapshot(theirs: String): GameSnapshot {
        fun zones(field: String) = """{"library":[],"hand":[],"battlefield":$field,"graveyard":[],"exile":[],"command":[],"stack":[],"handCount":1,"libraryCount":50}"""
        val json = """{"id":"match","phase":"PRECOMBAT_MAIN","turn":9,"activePlayerId":"b","viewerPlayerId":"a","priorityPlayerId":"b","log":[],
            "players":[{"playerId":"a","displayName":"You","life":40,"poison":0,"commanderTax":0,"zones":${zones("[]")},
                "commanders":[{"id":"c1","name":"Chatterfang, Squirrel General","ownerPlayerId":"a"}]},
              {"playerId":"b","displayName":"AI 1","life":32,"poison":0,"commanderTax":0,"zones":${zones(theirs)}}]}"""
        return EngineJson.format.decodeFromString(GameSnapshot.serializer(), json)
    }

    /** Your commander on an opponent's battlefield is noticed, with who has it (Caleb, 2026-10-21: Necromantic Selection). */
    @Test fun commanderTakenByAnOpponentIsNoticed() {
        assertEquals(emptyList<String>(), ArenaCommanderSteal.taken(stealSnapshot("[]")))
        val stolen = stealSnapshot("""[{"instanceId":"x","card":{"name":"Chatterfang, Squirrel General","typeLine":"Legendary Creature"}}]""")
        val taken = ArenaCommanderSteal.taken(stolen)
        assertEquals(listOf("Chatterfang, Squirrel General|b"), taken)
        val notice = ArenaCommanderSteal.notice(taken[0], stolen)
        assertTrue(notice, notice.startsWith("AI 1 took Chatterfang, Squirrel General."))
    }

    /** The spread hand: one flat row of whole cards over the rail, never overlapping; four fit, more swipe sideways. */
    @Test fun spreadHandIsOneFlatRowThatSwipes() {
        val hand = ArenaLayout.portraitLayout.hand
        fun frames(count: Int, scroll: Float = 0f): List<BoardRect> = (0 until count).map { index ->
            val slot = ArenaHandFanLayout.slot(index, count, ArenaHandPosture.SPREAD, hand, scroll)
            assertEquals(0f, slot.rotation, 0.0001f)
            val width = hand.card.width * slot.scale; val height = hand.card.height * slot.scale
            BoardRect(slot.center.x - width / 2, slot.center.y - height / 2, width, height)
        }
        for (count in listOf(1, 4, 9)) {
            val row = frames(count)
            assertEquals("one row", 1, row.map { it.midY }.toSet().size)
            for ((a, b) in row.zipWithNext()) assertTrue("$count cards don't overlap", b.minX > a.maxX)
            assertTrue(row[0].maxY <= hand.spreadBottom!! + 0.5f)
        }
        assertTrue("four fit whole", frames(4).all { it.minX >= 0 && it.maxX <= 440 })
        val grid = ArenaHandFanLayout.spread(9, hand)!!
        assertTrue(grid.maxScroll > 0)
        assertTrue("the first card shows whole", frames(9)[0].minX >= 0)
        assertTrue("a full swipe shows the last card whole", frames(9, grid.maxScroll)[8].maxX <= 440.001f)
        assertEquals("the swipe stops at the end", frames(9, grid.maxScroll)[8].maxX, frames(9, 10_000f)[8].maxX, 0.0001f)
        assertNull(ArenaHandFanLayout.spread(5, ArenaLayout.landscapeLayout.hand))
        assertEquals(ArenaHandPosture.SPREAD, ArenaHandPosture.resolve(ArenaHandPosture.Situation(spread = true)))
        assertEquals("it steps aside for a decision", ArenaHandPosture.RESTING,
            ArenaHandPosture.resolve(ArenaHandPosture.Situation(spread = true, boardDecision = true)))
    }

    @Test fun boardWipeRecapNamesTheSpellAndWhatWent() {
        val deaths = (1..4).map { BoardFXEvent.LeftBattlefield("c$it", "a", BoardFXZone.GRAVEYARD, BoardFXTint.GREEN) } +
            BoardFXEvent.LeftBattlefield("e", "b", BoardFXZone.EXILE, BoardFXTint.BLUE)
        assertEquals("Necromantic Selection: 4 to the graveyard, 1 exiled", ArenaSweepRecap.text("Necromantic Selection", deaths))
        assertNull("one removal needs no recap", ArenaSweepRecap.text("Murder", deaths.take(1)))
    }

    /** The landscape stack card sits under the opponent's piles and above the raised phase strip and its pills. */
    @Test fun landscapeStackCardClearsThePilesAndTheCorner() {
        val layout = ArenaLayout.landscapeLayout
        assertTrue(layout.stack.minY >= layout.opponentLibrary.y + layout.opponentPile.height / 2)
        assertTrue(layout.stack.maxY < layout.phaseStripRaisedY - 24)
    }

    @Test fun layoutNumbersMatchTheIOSCanvases() {
        val landscape = ArenaLayout.landscapeLayout
        assertEquals(BoardSize(956f, 440f), landscape.canvas)
        assertEquals(BoardRect(716f, 60f, 158f, 222f), landscape.stack)
        assertEquals(BoardRect(708f, 388f, 176f, 36f), landscape.primary)
        assertEquals(BoardPoint(876f, 28f), landscape.menu)
        assertNull(landscape.railTop)
        val portrait = ArenaLayout.portraitLayout
        assertEquals(BoardSize(440f, 956f), portrait.canvas)
        assertEquals(815f, portrait.railTop!!, 0f)
        assertEquals(808f, portrait.hand.spreadBottom!!, 0f)
        assertEquals(BoardRect(312f, 363f, 116f, 166f), portrait.stack)
        assertEquals(BoardSize(80f, 67f) to BoardSize(62f, 52f), portrait.tiles(false))
        assertEquals(portrait.tile to portrait.land, portrait.tiles(true))
        assertNotNull(ArenaLayout.current(BoardSize(900f, 400f)).opponentSupport)
    }
}
