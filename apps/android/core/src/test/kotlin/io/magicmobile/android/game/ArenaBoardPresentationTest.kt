package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Arena board's presentation rules (core ArenaBoardPresentation.kt): ArenaBattlefieldCard's glow and colour line, the
 * lane plans, the corner's words, the caption, the amount pill and Auto Pay's colour answer, and Stop for Removal (iOS
 * OnDeviceYieldPolicyTests testSmartPassStopsForAnOpponentsRemovalEvenWithoutAnAnswer and testThreatsAreTargets…).
 */
class ArenaBoardPresentationTest {
    private fun card(id: String, type: String, name: String = id, cost: String? = null, creature: Boolean? = null, tapped: Boolean? = null,
                     attacking: Boolean? = null, attachedTo: String? = null, counters: Map<String, Int>? = null) =
        ZoneCard(instanceId = id, card = CardIdentity(name, type, null, cost), tapped = tapped, isCreaturePermanent = creature, isAttacking = attacking,
            attachedToInstanceId = attachedTo, counters = counters)

    private fun player(id: String, battlefield: List<ZoneCard>) =
        PlayerGameState(id, id, 40, 0, 0, null, PlayerZones(emptyList(), emptyList(), battlefield, emptyList(), emptyList(), emptyList(), emptyList()))

    @Test fun glowFollowsTheChoiceThenCombatThenWhatYouCanUse() {
        val bear = card("b", "Creature — Bear")
        assertEquals(ArenaGlowTone.SELECTED to 1f, ArenaCardLook.glow(bear, selected = true, legal = true, targetable = true, paying = false))
        assertEquals(ArenaGlowTone.ATTACKING, ArenaCardLook.glow(bear.copy(isAttacking = true), false, true, true, false)?.first)
        assertEquals(ArenaGlowTone.BLOCKING, ArenaCardLook.glow(bear.copy(blocking = listOf("x")), false, false, false, false)?.first)
        assertEquals(ArenaGlowTone.TARGET, ArenaCardLook.glow(bear, false, true, true, false)?.first)
        assertEquals(ArenaGlowTone.PAYABLE, ArenaCardLook.glow(bear, false, true, false, true)?.first)
        assertEquals(ArenaGlowTone.PLAYABLE to 0.85f, ArenaCardLook.glow(bear, false, true, false, false))
        assertEquals("a usable ability glows yellow, apart from a card to cast", ArenaGlowTone.ABILITY to 0.95f,
            ArenaCardLook.glow(bear, false, true, false, false, ability = true))
        assertEquals("paying keeps its orange", ArenaGlowTone.PAYABLE, ArenaCardLook.glow(bear, false, true, false, true, ability = true)?.first)
        assertEquals("lands you could tap glow softer", 0.65f, ArenaCardLook.glow(card("f", "Basic Land — Forest"), false, true, false, false)!!.second, 0f)
        assertNull(ArenaCardLook.glow(bear, false, false, false, false))
        assertNull("phased out never glows", ArenaCardLook.glow(bear.copy(phasedIn = false), true, true, true, false))
    }

    @Test fun anAttackerKeepsItsColourOnTheArenaBoard() {
        val attacker = card("a", "Creature", tapped = true, attacking = true)
        assertFalse(ArenaCardLook.showsTapped(attacker, arena = true))
        assertTrue(ArenaCardLook.showsTapped(attacker, arena = false))
        assertTrue(ArenaCardLook.showsTapped(card("t", "Land", tapped = true), arena = true))
    }

    @Test fun colourLineAndShield() {
        assertEquals("R", ArenaCardLook.colorKey(card("g", "Creature", cost = "{1}{R}")))
        assertEquals("M", ArenaCardLook.colorKey(card("m", "Creature", cost = "{W}{U}")))
        assertEquals("G", ArenaCardLook.colorKey(card("f", "Basic Land — Forest")))
        assertEquals("", ArenaCardLook.colorKey(card("w", "Land")))
        val walker = card("w", "Legendary Planeswalker — Liliana", counters = mapOf("loyalty" to 3, "Oil" to 1))
        assertEquals(3 to false, ArenaCardLook.shieldCounter(walker))
        assertEquals(listOf("Oil"), ArenaCardLook.chipBadges(walker, plainTile = true).map { it.name })
        assertEquals(2, ArenaCardLook.chipBadges(walker, plainTile = false).size)
        assertEquals(5 to true, ArenaCardLook.shieldCounter(card("s", "Battle — Siege", counters = mapOf("defense" to 5))))
        assertNull(ArenaCardLook.shieldCounter(card("c", "Creature", counters = mapOf("loyalty" to 3))))
    }

    @Test fun tileUnitsCountPeekingAttachmentsAndLandPiles() {
        val bear = card("bear", "Creature — Bear")
        val aura = card("aura", "Enchantment — Aura", attachedTo = "bear")
        val sword = card("sword", "Artifact — Equipment", attachedTo = "bear")
        assertEquals(listOf(1.6f), ArenaCardLook.tileUnits(listOf(bear, aura, sword), emptySet(), emptySet(), emptySet()))
        val forests = (1..4).map { card("f$it", "Basic Land — Forest", name = "Forest") }
        assertEquals(1.36f, ArenaCardLook.tileUnits(forests, emptySet(), emptySet(), emptySet()).single(), 0.0001f)
        // Piles open into single cards while they are chosen from.
        assertEquals(4, ArenaCardLook.tileUnits(forests, setOf("f2"), emptySet(), emptySet()).size)
    }

    @Test fun lanePlansPutEachPermanentInItsSection() {
        val battlefield = listOf(card("bear", "Creature — Bear"), card("walker", "Legendary Planeswalker — Ajani"), card("oath", "Enchantment"),
            card("forest", "Basic Land — Forest"), card("ring", "Artifact", name = "Sol Ring").let { it.copy(card = it.card.copy(oracleText = "{T}: Add {C}{C}.")) })
        val me = player("me", battlefield)
        val choice = ArenaLaneChoice(emptySet(), emptySet(), emptySet(), false)
        for (screen in listOf(BoardSize(956f, 440f), BoardSize(440f, 956f))) {
            val canvas = ArenaCanvas(screen)
            val plans = ArenaLanePlanner.plans(me, true, battlefield, setOf("me"), canvas, choice, frames = false).associateBy { it.title }
            assertEquals(listOf("bear"), plans.getValue("Your board").cards.map { it.instanceId })
            assertEquals(listOf("walker"), plans.getValue("Your permanents").cards.map { it.instanceId })
            assertEquals(listOf("forest"), plans.getValue("Your lands").cards.map { it.instanceId })
            assertEquals(setOf("ring", "oath"), plans.getValue("Your artifacts").cards.map { it.instanceId }.toSet())
            assertEquals(ArenaLaneAlignment.LEADING, plans.getValue("Your lands").alignment)
            assertEquals(ArenaLaneAlignment.TRAILING, plans.getValue("Your permanents").alignment)
            for (plan in plans.values) assertTrue("${plan.title} on the screen", plan.rect.minX >= 0 && plan.rect.maxX <= screen.width + 0.5f)
        }
        // Landscape: the side section stands a size up at the table's right edge.
        val landscape = ArenaLanePlanner.plans(me, true, battlefield, setOf("me"), ArenaCanvas(BoardSize(956f, 440f)), choice, false).associateBy { it.title }
        assertTrue(landscape.getValue("Your permanents").card.width > landscape.getValue("Your board").card.width)
        assertEquals(248f, landscape.getValue("Your permanents").rect.midY, 0.5f)
    }

    @Test fun sectionsFollowWhatACardIsAttachedTo() {
        val cards = listOf(card("bear", "Creature"), card("aura", "Enchantment — Aura", attachedTo = "bear"), card("oath", "Enchantment"))
        val (leading, trailing) = ArenaLanePlanner.sections(cards, { ArenaFrontSection.of(it) == ArenaFrontSection.SUPPORT }, { 0 })
        assertEquals(listOf("bear", "aura"), leading.map { it.instanceId })
        assertEquals(listOf("oath"), trailing.map { it.instanceId })
        val (left, right) = ArenaLanePlanner.split(BoardRect(0f, 0f, 300f, 60f), 100f)
        assertEquals(190f, left.width, 0.0001f)
        assertEquals(200f, right.minX, 0.0001f)
        assertEquals(BoardRect.zero, ArenaLanePlanner.split(BoardRect(0f, 0f, 300f, 60f), 0f).second)
    }

    @Test fun phaseStripLightsTheReferenceStep() {
        assertEquals(8, ArenaPhaseStripRules.icons.size)
        assertEquals(0, ArenaPhaseStripRules.current("UPKEEP"))
        assertEquals(1, ArenaPhaseStripRules.current("PRECOMBAT_MAIN"))
        assertEquals(2, ArenaPhaseStripRules.current("DECLARE_ATTACKERS"))
        assertEquals(3, ArenaPhaseStripRules.current("declare-blockers"))
        assertEquals(4, ArenaPhaseStripRules.current("FIRST_COMBAT_DAMAGE"))
        assertEquals(6, ArenaPhaseStripRules.current("POSTCOMBAT_MAIN"))
        assertEquals(7, ArenaPhaseStripRules.current("END_TURN"))
        assertNull(ArenaPhaseStripRules.current(null))
    }

    private fun snapshot(json: String) = EngineJson.format.decodeFromString(GameSnapshot.serializer(), json)

    private fun table(step: String, active: String = "a", stack: String = "[]", prompt: String? = null, battlefield: String = "[]", actions: String = "[]") = snapshot("""
        {"id":"match","phase":"$step","step":"$step","turn":3,"activePlayerId":"$active","viewerPlayerId":"a","priorityPlayerId":"a","log":[],
         "legalActions":$actions,${if (prompt != null) "\"promptEnvelopeV2\":$prompt," else ""}
         "players":[{"playerId":"a","displayName":"You","life":40,"poison":0,"commanderTax":0,"zones":{"library":[],"hand":[],"battlefield":$battlefield,
           "graveyard":[],"exile":[],"command":[],"stack":[],"handCount":1,"libraryCount":50}},
           {"playerId":"b","displayName":"AI","life":40,"poison":0,"commanderTax":0,"zones":{"library":[],"hand":[],"battlefield":[],"graveyard":[],"exile":[],
           "command":[],"stack":[],"handCount":1,"libraryCount":50}}],
         "xmage":{"schemaVersion":1,"gameId":"match","bridgeRevision":1,"callbackCoverage":[],"players":[],"stack":$stack,"combat":[],"exileZones":[],
           "revealed":[],"lookedAt":[],"companion":[],"playableObjects":[],
           "panels":{"stack":true,"command":true,"graveyard":true,"exile":true,"revealed":false,"lookedAt":false,"search":false}}}""")

    private val pass = LegalAction(id = "pass", type = "pass_priority", playerId = "a", label = "Pass")

    @Test fun passTitlesUseTheReferenceWords() {
        assertEquals("Next" to "To Main", ArenaCornerText.passTitle(pass, table("UPKEEP")))
        assertEquals("Next" to "To Combat", ArenaCornerText.passTitle(pass, table("PRECOMBAT_MAIN")))
        assertEquals("Next" to "To Main 2", ArenaCornerText.passTitle(pass, table("DECLARE_ATTACKERS")))
        assertEquals("End Turn" to null, ArenaCornerText.passTitle(pass, table("POSTCOMBAT_MAIN")))
        assertEquals("Pass" to null, ArenaCornerText.passTitle(pass, table("PRECOMBAT_MAIN", active = "b")))
        val stack = """[{"id":"s1","objectType":"SPELL","name":"Shock","controllerId":"b"}]"""
        assertEquals("Resolve" to null, ArenaCornerText.passTitle(pass, table("PRECOMBAT_MAIN", stack = stack)))
        assertEquals("Opponent’s Turn", ArenaCornerText.waitingTitle(table("PRECOMBAT_MAIN", active = "b")))
        assertEquals("Waiting…", ArenaCornerText.waitingTitle(table("PRECOMBAT_MAIN")))
    }

    @Test fun colourAnswerNamesTheColourThePlanWanted() {
        val question = EngineJson.format.decodeFromString(PromptEnvelopeV2.serializer(), """{"id":"p","method":"GAME_CHOOSE_CHOICE","messageId":3,
            "playerId":"a","responseKind":"choice","message":"Choose mana color","choices":[{"id":"1","label":"White"},{"id":"2","label":"Green"}]}""")
        assertEquals("2", ArenaCornerText.colorChoice(question, "G"))
        assertEquals("1", ArenaCornerText.colorChoice(question, null))
        val other = question.copy(choices = listOf(ChoicePromptOption("x", "Elf")))
        assertNull("not a colour question", ArenaCornerText.colorChoice(other, "G"))
    }

    @Test fun stackObjectsReadAsSpellsOrAbilities() {
        fun item(type: String?, cost: String? = null) = XmageStackObject(id = "s", objectType = type, name = "X",
            sourceCard = cost?.let { ZoneCard(instanceId = "c", card = CardIdentity("Bolt", "Instant", null, it)) })
        assertFalse(ArenaTableRules.isAbility(item("SPELL")))
        assertTrue(ArenaTableRules.isAbility(item("TRIGGERED_ABILITY")))
        assertFalse(ArenaTableRules.isAbility(item(null)))
        assertEquals("R", ArenaTableRules.arrivalColor(item("SPELL", "{R}"), commander = false))
        assertEquals("M", ArenaTableRules.arrivalColor(item("SPELL", "{R}{G}"), commander = false))
        assertEquals("M", ArenaTableRules.arrivalColor(item("SPELL", "{R}"), commander = true))
        assertEquals("", ArenaTableRules.arrivalColor(item("SPELL", "{2}"), commander = false))
    }

    @Test fun playerCardStaysOnTheScreen() {
        val screen = BoardSize(800f, 360f)
        val center = ArenaTableRules.playerCardCenter(BoardPoint(70f, 330f), viewer = true, landscape = true, screen)
        assertTrue(center.y - 168 >= 12 - 0.01f)
        assertTrue(center.x + 150 <= screen.width - 12 + 0.01f)
        val portrait = ArenaTableRules.playerCardCenter(BoardPoint(42f, 36f), viewer = false, landscape = false, BoardSize(400f, 860f))
        assertEquals(36f + 40 + 180, portrait.y, 0.01f)
    }

    @Test fun captionSaysWhatTheTableWants() {
        assertNull(ArenaCornerText.caption(table("PRECOMBAT_MAIN"), CombatSelectionState()))
        val attack = """{"id":"t","method":"GAME_SELECT","messageId":2,"playerId":"a","responseKind":"target","message":"Select attackers",
            "responseCommand":{"type":"choose_target","promptId":"t"},"targets":[{"id":"mine","label":"Bear"}]}"""
        val mine = """[{"instanceId":"mine","card":{"name":"Bear","typeLine":"Creature"}}]"""
        assertEquals("Choose attackers.", ArenaCornerText.caption(table("DECLARE_ATTACKERS", prompt = attack, battlefield = mine), CombatSelectionState()))
        // A card's own target question in that step (Gogo copying an attack trigger) says what it asks.
        val target = attack.replace("GAME_SELECT", "GAME_TARGET").replace("Select attackers", "Select target creature")
        assertEquals("Select target creature", ArenaCornerText.caption(table("DECLARE_ATTACKERS", prompt = target, battlefield = mine), CombatSelectionState()))
    }

    @Test fun amountPillStartsXAtWhatYourManaPays() {
        val prompt = """{"id":"x","method":"GAME_GET_AMOUNT","messageId":4,"playerId":"a","responseKind":"amount","message":"Announce the value for {X}",
            "minChoices":0,"maxChoices":20,"responseCommand":{"type":"choose_amount","promptId":"x"}}"""
        val lands = (1..5).joinToString(",") { """{"instanceId":"m$it","card":{"name":"Mountain","typeLine":"Basic Land — Mountain"}}""" }
        val stack = """[{"id":"s1","objectType":"SPELL","name":"Fireball","controllerId":"a","sourceCard":{"instanceId":"fb","card":{"name":"Fireball","typeLine":"Sorcery","manaCost":"{X}{R}"}}}]"""
        val snap = table("PRECOMBAT_MAIN", prompt = prompt, battlefield = "[$lands]", stack = stack)
        val amount = ArenaTableRules.amountPrompt(snap, startingRollVisible = false)
        assertNotNull(amount)
        val setup = ArenaTableRules.amountSetup(amount!!, snap)
        assertEquals("Pay X", setup.label)
        assertEquals(4, setup.initial)
        assertNull("the starting roll answers its own", ArenaTableRules.amountPrompt(snap, startingRollVisible = true))
    }

    // MARK: Stop for Removal

    private fun context(emptyStack: Boolean = true, threat: Boolean = false) = OnDeviceYieldPolicy.Context(
        "match", "seat", "viewer", "viewer", 3, "running", true, true, emptyStack, true, false,
        OnDeviceYieldPolicy.Prompt("prompt", 10, "SELECT", "priority", true, false, "viewer"), threat)

    /** Caleb, 2026-10-21: an opponent's board wipe resolved before he could read it. Their removal stops for you, answer or not. */
    @Test fun smartPassStopsForAnOpponentsRemovalEvenWithoutAnAnswer() {
        val base = OnDeviceSmartPass.Situation(context(emptyStack = false).copy(activePlayerID = "other"), "PRECOMBAT_MAIN", false, false,
            topStackIsMine = false, hasResponse = false, threatensMe = true)
        val settings = OnDeviceSmartPass.Settings()
        assertNull("a sweeper waits for you", OnDeviceSmartPass.passPrompt(base, settings))
        assertNotNull("unless you turned the stop off", OnDeviceSmartPass.passPrompt(base, settings.copy(stopForThreats = false)))
        assertNotNull("a harmless spell still passes", OnDeviceSmartPass.passPrompt(base.copy(threatensMe = false), settings))
        val policy = OnDeviceYieldPolicy()
        assertTrue(policy.start(context(), 0.0, OnDeviceYieldPolicy.Mode.END_TURN_SKIPPING_RESPONSES))
        assertEquals(OnDeviceYieldPolicy.Decision.Stop(OnDeviceYieldPolicy.StopReason.THREAT), policy.evaluate(context(emptyStack = false, threat = true), 1.0))
    }

    @Test fun threatsAreTargetsOnYourThingsAndUntargetedSweepers() {
        val bear = """[{"instanceId":"mine-1","card":{"name":"Bear","typeLine":"Creature"}}]"""
        fun spell(text: String, controller: String = "b", targets: String = "[]") =
            """[{"id":"s1","objectId":"s1","objectType":"SPELL","name":"Spell","rulesText":"$text","controllerId":"$controller","targetIds":$targets}]"""
        fun threat(stack: String, battlefield: String = bear) = OnDeviceSmartPass.threatensViewer(table("PRECOMBAT_MAIN", "b", stack, battlefield = battlefield))
        assertTrue(threat(spell("Destroy all creatures, then return a creature card put into a graveyard this way.")))
        assertTrue(threat(spell("Destroy target creature.", targets = """["mine-1"]""")))
        assertTrue(threat(spell("Each opponent sacrifices a creature.")))
        assertFalse("nothing of yours touched", threat(spell("Draw two cards.")))
        assertFalse("your own spell", threat(spell("Destroy all creatures.", controller = "a")))
        assertFalse("you have nothing to lose", threat(spell("Destroy all creatures."), battlefield = "[]"))
    }

    /** The stack card steps aside for the object the player tucked and while they pick on the table (iOS ArenaBoardModelTests). */
    @Test fun theStackTucksForItsTopObjectAndWhilePicking() {
        assertFalse(ArenaStackTuck.isTucked("a", null, null, false))
        assertTrue(ArenaStackTuck.isTucked("a", "a", null, false))
        assertFalse("the next one shows", ArenaStackTuck.isTucked("b", "a", null, false))
        assertTrue("picking tucks it", ArenaStackTuck.isTucked("b", null, null, true))
        assertFalse("brought back while picking", ArenaStackTuck.isTucked("b", null, "b", true))
        assertTrue(ArenaStackTuck.isTucked("c", null, "b", true))
    }
}
