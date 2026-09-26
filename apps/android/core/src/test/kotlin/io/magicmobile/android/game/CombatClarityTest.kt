package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Combat clarity: mirrors the iOS cases in BoardCardPresentationTests, BoardEventTimelineTests and
 * GameLogPresentationTests. Shared transition and message cases: parity/combat-cases.json.
 */
class CombatClarityTest {
    private fun combatant(id: String, name: String, icons: List<String> = emptyList(), rules: String? = null,
                          attacking: Boolean? = null, blocking: List<String>? = null): ZoneCard =
        ZoneCard(id, CardIdentity(name, "Creature", rules, manaCost = "{R}"), summoningSickness = false,
            cardIcons = icons.map { XmageCardIcon(it, category = "ABILITY") }, power = 6, toughness = 4, isCreaturePermanent = true,
            isAttacking = attacking, blocking = blocking)

    private fun player(id: String, life: Int = 40, battlefield: List<ZoneCard> = emptyList(), graveyard: List<ZoneCard> = emptyList()) =
        PlayerGameState(id, id, life, 0, 0, null, PlayerZones(emptyList(), emptyList(), battlefield, graveyard, emptyList(), emptyList(), emptyList()))

    private fun combatSnapshot(step: String, revision: Int, lifeA: Int = 40, a: List<ZoneCard>, b: List<ZoneCard>,
                               graveyardA: List<ZoneCard> = emptyList(), blocked: Boolean): GameSnapshot {
        val combat = XmageCombatGroup("a", "a", "player", blocked, b.filter { it.isAttacking == true }, a.filter { !it.blocking.isNullOrEmpty() })
        val xmage = XmageMobileSnapshot(1, "match", revision, null, emptyList(), emptyList(), listOf(combat), emptyList(), emptyList(),
            emptyList(), emptyList(), emptyList(), emptyList(), XmagePanels(false, true, true, true, false, false, false))
        return GameSnapshot("match", "xmage-ondevice", "b", "combat", step, 3, "a", players = listOf(player("a", lifeA, a, graveyardA), player("b", 40, b)),
            log = emptyList(), xmage = xmage, bridgeRevision = revision, viewerPlayerId = "a")
    }

    /** Atarka gains double strike when it attacks; a deathtouch Typhoid Rats blocks. */
    private val atarkaCombat: Triple<GameSnapshot, GameSnapshot, GameSnapshot> get() {
        val atarka = combatant("atarka", "Atarka, World Render", listOf("ABILITY_FLYING", "ABILITY_TRAMPLE", "ABILITY_DOUBLE_STRIKE"),
            "Flying\nTrample", attacking = true)
        val rats = combatant("rats", "Typhoid Rats", listOf("ABILITY_DEATHTOUCH"), "Deathtouch", blocking = listOf("atarka"))
        val dead = combatant("rats", "Typhoid Rats", rules = "Deathtouch")
        return Triple(combatSnapshot("DECLARE_BLOCKERS", 10, a = listOf(rats), b = listOf(atarka), blocked = true),
            combatSnapshot("FIRST_COMBAT_DAMAGE", 11, a = emptyList(), b = listOf(atarka), graveyardA = listOf(dead), blocked = true),
            combatSnapshot("COMBAT_DAMAGE", 12, lifeA = 34, a = emptyList(), b = listOf(atarka), graveyardA = listOf(dead), blocked = true))
    }

    @Test fun gainedDoubleStrikeIsACombatKeywordOfTheLivePermanent() {
        val atarka = combatant("atarka", "Atarka, World Render", listOf("ABILITY_FLYING", "ABILITY_TRAMPLE", "ABILITY_DOUBLE_STRIKE", "COMMANDER"),
            "Flying\nTrample\nWhenever a Dragon you control attacks, it gains double strike until end of turn.", attacking = true)
        assertEquals(listOf(CombatKeyword.DOUBLE_STRIKE, CombatKeyword.TRAMPLE, CombatKeyword.FLYING), atarka.combatKeywords)
        assertTrue(atarka.isInCombat)
        assertTrue(CombatKeyword.strikesFirst(atarka.combatKeywords.toSet()))
        assertTrue("double strike hits in both steps", CombatKeyword.strikesInRegularStep(atarka.combatKeywords.toSet()))
        assertFalse("first strike alone hits only first", CombatKeyword.strikesInRegularStep(setOf(CombatKeyword.FIRST_STRIKE)))
        assertFalse(CombatKeyword.strikesFirst(setOf(CombatKeyword.DEATHTOUCH)))
    }

    @Test fun onlyAttackersAndBlockersAreInCombat() {
        assertFalse(combatant("x", "Rats", rules = "Deathtouch").isInCombat)
        assertFalse(combatant("x", "Rats", rules = "Deathtouch", attacking = false, blocking = emptyList()).isInCombat)
        assertTrue(combatant("x", "Rats", rules = "Deathtouch", blocking = listOf("atarka")).isInCombat)
    }

    @Test fun badgePlanAlwaysNamesTheMostImportantKeyword() {
        val tiny = CombatKeywordBadgePlan(listOf(CombatKeyword.FIRST_STRIKE, CombatKeyword.DEATHTOUCH, CombatKeyword.LIFELINK), 44f, 50f)
        assertEquals(listOf(CombatKeyword.FIRST_STRIKE), tiny.visible)
        assertEquals(2, tiny.hiddenCount)
        assertEquals("1st strike", tiny.label(CombatKeyword.FIRST_STRIKE))
        val roomy = CombatKeywordBadgePlan(CombatKeyword.entries, 120f, 170f)
        assertEquals("at most three, first strike folded into double strike",
            listOf(CombatKeyword.DOUBLE_STRIKE, CombatKeyword.DEATHTOUCH, CombatKeyword.TRAMPLE), roomy.visible)
        assertEquals(6, roomy.hiddenCount)
        assertEquals("Indestructible", roomy.label(CombatKeyword.INDESTRUCTIBLE))
    }

    @Test fun snapshotKeywordsOfCombatantsReachTheBoardState() {
        val state = BoardFXState.of(atarkaCombat.first)
        assertEquals(setOf(CombatKeyword.DOUBLE_STRIKE, CombatKeyword.TRAMPLE, CombatKeyword.FLYING), state.cards["atarka"]?.keywords)
        assertEquals(setOf(CombatKeyword.DEATHTOUCH), state.cards["rats"]?.keywords)
        assertEquals(setOf("atarka"), state.blockedAttackers)
        assertEquals("declare-blockers", state.step)
        assertEquals(BoardEventDiffer.firstStrikeStep, BoardFXState.of(atarkaCombat.second).step)
    }

    @Test fun firstStrikeStepPlaysItsOwnLabelledBeatBeforeTheRegularDamage() {
        val (blocks, firstStrike, regular) = atarkaCombat
        val start = 7_000_000L
        val director = BoardFXDirector()
        director.ingest(blocks, BoardFXLevel.FULL, start)
        val first = director.ingest(firstStrike, BoardFXLevel.FULL, start)
        assertEquals(listOf(BoardFXEvent.FirstStrikeBeat, BoardFXEvent.CombatStrike("atarka", BoardFXStrikeTarget.Card("rats"), BoardFXTint.RED, true),
            BoardFXEvent.LeftBattlefield("rats", "a", BoardFXZone.GRAVEYARD, BoardFXTint.RED)), first.map { it.event })
        val label = first[0]
        assertEquals(0.0, label.delay, 0.0)
        assertTrue("the label spans the whole first-strike beat", label.end >= first.maxOf { it.end })
        // The regular damage arrives while the first-strike beat still plays: it waits for it.
        val later = start + 400
        val second = director.ingest(regular, BoardFXLevel.FULL, later)
        assertEquals(listOf(BoardFXEvent.CombatStrike("atarka", BoardFXStrikeTarget.Player("a"), BoardFXTint.RED, false),
            BoardFXEvent.LifeChanged("a", -6)), second.map { it.event })
        assertEquals(start + label.end * 1000, later + second[0].delay * 1000, 1.0)
        // The double striker flies twice; its tile hides only while each strike flies.
        val windows = director.cardMotion("a").hidden["atarka"] ?: emptyList()
        assertEquals(2, windows.size)
        assertEquals(BoardFXCardMotion.Hidden(start, first[1].delay, first[1].end), windows[0])
        assertEquals(BoardFXCardMotion.Hidden(later, second[0].delay, second[0].end), windows[1])
        assertTrue(start + windows[0].until * 1000 < later + windows[1].from * 1000)
    }

    @Test fun firstStrikeBeatFollowsTheEffectLevels() {
        val (blocks, firstStrike, _) = atarkaCombat
        val events = BoardEventDiffer.events(BoardFXState.of(blocks), BoardFXState.of(firstStrike))
        assertEquals(emptyList<ScheduledBoardFX>(), BoardFXScheduler.schedule(events, BoardFXLevel.OFF))
        val reduced = BoardFXScheduler.schedule(events, BoardFXLevel.REDUCED)
        assertEquals("reduced keeps the label, without motion", BoardFXEvent.FirstStrikeBeat, reduced.first().event)
        assertFalse(reduced.any { it.usesMotion })
        assertEquals(reduced.first().end, reduced.first().holdsLaterBatchesUntil)
        // The label is information, not decoration: a crowded batch never drops it.
        val crowded = listOf(BoardFXEvent.FirstStrikeBeat) + (0 until 20).map { BoardFXEvent.DamageMarked("c$it", 1) }
        val planned = BoardFXScheduler.schedule(crowded, BoardFXLevel.FULL)
        assertEquals(BoardFXEvent.FirstStrikeBeat, planned.first().event)
        assertEquals(BoardFXScheduler.decorativeLimit + 1, planned.size)
    }

    @Test fun combatReasonsComeFromTheStepAndKeywordsWhenTheEntryAppears() {
        val atarkaID = "a7a4ca00-6d1e-4c2a-9f10-0000000000a1"
        val ratsID = "7e9a0000-5b1d-4d2e-8f00-0000000000b2"
        val atarkaName = "<font color='#FF6347' object_id='$atarkaID'>Atarka, World Render</font> [a7a]"
        val ratsName = "<font color='#696969' object_id='$ratsID'>Typhoid Rats</font> [7e9]"
        val attacking = combatant(atarkaID, "Atarka, World Render", listOf("ABILITY_DOUBLE_STRIKE", "ABILITY_TRAMPLE"), attacking = true)
        val blocking = combatant(ratsID, "Typhoid Rats", listOf("ABILITY_DEATHTOUCH"), blocking = listOf(atarkaID))
        fun board(step: String, battlefield: List<ZoneCard>, log: List<Pair<String, String>>, turn: Int = 3, game: String = "match") =
            GameSnapshot(game, "xmage-ondevice", "b", "combat", step, turn, "a", players = listOf(player("a", battlefield = battlefield)),
                log = log.map { GameLogEntry(it.first, it.second) }, bridgeRevision = 1, viewerPlayerId = "a")
        val earlier = "old" to "$atarkaName deals 6 damage to $ratsName"
        val reasons = CombatLogReasons()
        // Entries already there when the game is first seen have no known step: no reason.
        reasons.observe(board("DECLARE_BLOCKERS", listOf(attacking, blocking), listOf(earlier)))
        assertEquals(emptyMap<String, String>(), reasons.reasons)
        reasons.observe(board("FIRST_COMBAT_DAMAGE", listOf(attacking),
            listOf(earlier, "hit" to "$atarkaName deals 6 damage to $ratsName", "died" to "$ratsName died")))
        assertEquals(mapOf("hit" to "Atarka, World Render has double strike (first-strike damage)",
            "died" to "Typhoid Rats dies to first-strike damage before dealing damage"), reasons.reasons)
        // Next turn Atarka no longer has double strike; the recorded reasons do not change.
        val calm = combatant(atarkaID, "Atarka, World Render", listOf("ABILITY_TRAMPLE"))
        reasons.observe(board("UPKEEP", listOf(calm), listOf("hit" to "", "died" to ""), turn = 4))
        assertEquals("Atarka, World Render has double strike (first-strike damage)", reasons.reasons["hit"])
        // Entries that leave the retained log drop their reasons; another game starts clean.
        reasons.observe(board("UPKEEP", listOf(calm), listOf("died" to ""), turn = 4))
        assertEquals(setOf("died"), reasons.reasons.keys)
        reasons.observe(board("FIRST_COMBAT_DAMAGE", emptyList(), listOf("died" to ""), game = "other"))
        assertEquals(emptyMap<String, String>(), reasons.reasons)
    }
}
