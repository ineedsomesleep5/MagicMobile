package io.magicmobile.android.game

import io.magicmobile.android.core.Deck
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** ranked-cases.json: the ladder, seasons, brackets and AI pools (iOS RankedParityTests.swift). */
class RankedParityTest {
    private val repo = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory }
    private val root = Json.parseToJsonElement(File(repo, "apps/android/core/src/test/resources/parity/ranked-cases.json").readText()).jsonObject
    private val rules = BracketRules.parse(File(repo, "apps/ios/MagicMobile/Resources/commander-brackets.json").readText())
    private val bracketDecks = AIDeckPool.parse(File(repo, "apps/ios/MagicMobile/Resources/ai-decks.json").readText())
    /** The five precons are Core AI decks too (PreconCatalog.swift; the app reads them from precons.json). */
    private val pool = Regex("""id:\s*"([^"]+)"""").findAll(File(repo, "apps/ios/MagicMobile/PreconCatalog.swift").readText())
        .map { AIDeck(it.groupValues[1], it.groupValues[1], "", "", "", CommanderBracket.CORE, Deck(it.groupValues[1], emptyList())) }.toList() + bracketDecks

    private fun rows(key: String) = root[key]!!.jsonArray.map { it.jsonObject }
    private fun int(o: JsonObject, key: String) = o[key]!!.jsonPrimitive.int
    private fun str(o: JsonObject, key: String) = o[key]!!.jsonPrimitive.content
    private fun position(value: Any?): RankPosition {
        val o = value as JsonObject
        return RankPosition.make(RankTier.of(str(o, "tier"))!!, int(o, "division"), int(o, "pips"))
    }

    @Test fun ladder() {
        assertEquals(int(root, "pipsPerDivision"), RankPosition.PIPS_PER_DIVISION)
        for (item in rows("ladder")) {
            val name = str(item, "name")
            val start = RankState.fresh("2026-10").let { it.copy(position = position(item["before"]), peak = position(item["before"]), winStreak = int(item, "streak")) }
            val outcome = RankOutcome.entries.first { it.raw == str(item, "outcome") }
            val (state, change) = RankLadder.apply(outcome, start, int(item, "deckBracket"))
            assertEquals(name, position(item["after"]), state.position)
            assertEquals(name, int(item, "streakAfter"), state.winStreak)
            assertEquals(name, int(item, "delta"), change.pipDelta)
            assertEquals(name, item["bonuses"]!!.jsonArray.map { it.jsonPrimitive.content }, change.bonuses.map { it.raw })
            assertEquals(name, str(item, "kind"), change.kind.raw)
        }
    }

    @Test fun positionsAndTiers() {
        for (item in rows("positions")) {
            val p = RankPosition.ofPoints(int(item, "points"))
            assertEquals("$item", int(item, "step"), p.step)
            assertEquals(str(item, "title"), p.title)
            assertEquals(int(item, "pips"), p.pips)
            assertEquals(int(item, "opponentBracket"), p.opponentBracket)
            assertEquals(int(item, "points"), p.points)
        }
        for (item in rows("tiers")) {
            val tier = RankTier.of(str(item, "tier"))!!
            assertEquals(item["opponentBrackets"]!!.jsonArray.map { it.jsonPrimitive.int }, listOf(tier.opponentBrackets.first, tier.opponentBrackets.last))
            assertEquals(int(item, "maxDeckBracket"), tier.maxDeckBracket)
            assertEquals(int(item, "aiSkill"), tier.aiSkill)
        }
    }

    @Test fun seasons() {
        for (item in rows("seasons")) assertEquals(str(item, "season"), RankLadder.season(item["millis"]!!.jsonPrimitive.long))
        for (item in rows("seasonEnds")) assertEquals(item["millis"]!!.jsonPrimitive.long, RankLadder.seasonEnd(str(item, "season")))
        for (item in rows("rollover")) {
            val name = str(item, "name")
            val state = RankState.fresh(str(item, "season")).copy(position = position(item["position"]), peak = position(item["peak"]),
                wins = int(item, "wins"), losses = int(item, "losses"))
            val next = RankLadder.rollover(state, str(item, "to"))
            assertEquals(name, position(item["after"]), next.position)
            val history = item["history"]!!.jsonArray.map { it.jsonObject }
            assertEquals(name, history.size, next.history.size)
            next.history.zip(history).forEach { (record, expected) ->
                assertEquals(name, str(expected, "season"), record.season)
                assertEquals(name, position(expected["final"]), record.final)
                assertEquals(name, position(expected["peak"]), record.peak)
                assertEquals(name, int(expected, "wins"), record.wins)
                assertEquals(name, int(expected, "losses"), record.losses)
            }
        }
    }

    @Test fun brackets() {
        assertEquals("the February 2026 list", 53, rules.gameChangers.size)
        for (item in rows("brackets")) {
            val name = str(item, "name")
            val report = rules.evaluate(item["cards"]!!.jsonArray.map { it.jsonPrimitive.content })
            assertEquals(name, int(item, "minimum"), report.minimum.level)
            assertEquals(name, item["gameChangers"]!!.jsonArray.map { it.jsonPrimitive.content }, report.gameChangers)
            assertEquals(name, item["massLandDenial"]!!.jsonArray.map { it.jsonPrimitive.content }, report.massLandDenial)
            assertEquals(name, item["extraTurns"]!!.jsonArray.map { it.jsonPrimitive.content }, report.extraTurns)
            assertEquals(name, int(item, "combos"), report.combos.size)
            assertEquals(name, int(item, "earlyCombos"), report.earlyCombos.size)
        }
        for (item in rows("effective")) {
            val declared = item["declared"].takeIf { it != null && it !is JsonNull }?.jsonPrimitive?.int?.let(CommanderBracket::of)
            assertEquals("$item", int(item, "effective"), DeckBracketPreference.effective(CommanderBracket.of(int(item, "minimum"))!!, declared).level)
        }
        for (item in rows("choices")) {
            assertEquals(item["choices"]!!.jsonArray.map { it.jsonPrimitive.int },
                DeckBracketPreference.choices(CommanderBracket.of(int(item, "minimum"))!!).map { it.level })
        }
    }

    @Test fun poolsAndColors() {
        for (item in rows("pools")) {
            val found = AIDeckPool.pool(int(item, "bracket"), pool)
            assertEquals("$item", int(item, "count"), found.size)
            assertEquals("$item", setOf(int(item, "poolBracket")), found.map { it.bracket.level }.toSet())
        }
        for (item in rows("colors")) {
            val cost = item["manaCost"].takeIf { it != null && it !is JsonNull }?.jsonPrimitive?.content
            assertEquals("$item", item["colors"]!!.jsonArray.map { it.jsonPrimitive.content }, PlayerStats.colors(cost))
        }
    }

    @Test fun aiDecksAreHundredsAtTheirBrackets() {
        assertEquals(21, bracketDecks.size)
        val basics = setOf("Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes")
        for (deck in bracketDecks) {
            assertEquals(deck.id, 100, deck.deck.entries.sumOf { it.quantity })
            assertEquals(deck.id, deck.commander, deck.deck.entries.single { it.section == "commanders" }.name)
            assertTrue(deck.id, deck.deck.entries.none { it.quantity > 1 && it.name !in basics })
            assertTrue("${deck.id} lists above its bracket", rules.evaluate(deck.deck).minimum.level <= maxOf(2, deck.bracket.level))
        }
    }

    @Test fun pickAvoidsYourCommanderAndRecentDecks() {
        val three = AIDeckPool.pool(3, pool)
        for (roll in three.indices) {
            val pick = AIDeckPool.pick(3, "Krenko, Mob Boss", emptyList(), pool) { roll }!!
            assertNotEquals("Krenko, Mob Boss", pick.commander)
        }
        val fresh = AIDeckPool.pick(3, null, three.drop(1).map { it.id }, pool) { 0 }!!
        assertEquals(three[0].id, fresh.id)
    }

    @Test fun recordStoreRanksAndRollsOver() {
        val october = 1_791_000_000_000L; val december = 1_797_292_800_000L
        var file = PlayerRecordFile(RankState.fresh(RankLadder.season(october)))
        fun play(now: Long, mode: PlayMode, outcome: RankOutcome, colors: List<String> = listOf("R"), human: Boolean = false): RankChange? {
            val (next, change) = file.recording(now, mode, outcome, listOf(MatchOpponent("Foe", "Edgar Markov", !human)), 2, 3,
                "precon:x", "Goblins", "C-${colors.first()}", colors, 2, 9, "ai-edgar-markov-core")
            file = next; return change
        }
        assertEquals(null, play(october, PlayMode.QUICK, RankOutcome.WIN))
        assertEquals(RankPosition.make(RankTier.BRONZE, 4, 1), play(october, PlayMode.RANKED, RankOutcome.WIN)!!.after)
        play(december, PlayMode.RANKED, RankOutcome.LOSS)
        assertEquals("2026-12", file.rank.season)
        assertEquals("2026-10", file.rank.history.first().season)
        assertEquals(listOf("ai-edgar-markov-core"), file.recentAIDecks)
        // Round trip through the saved file.
        val text = PlayerRecordFile.json.encodeToString(PlayerRecordFile.serializer(), file)
        assertEquals(file, PlayerRecordFile.json.decodeFromString(PlayerRecordFile.serializer(), text))
        listOf("W", "U", "B", "R", "G").forEach { play(december, PlayMode.QUICK, RankOutcome.WIN, listOf(it)) }
        play(december, PlayMode.RANKED, RankOutcome.WIN, human = true)
        val unlocked = Achievement.unlocked(file.matches, file.rank)
        assertTrue(unlocked.containsAll(listOf(Achievement.FIRST_WIN, Achievement.FIRST_RANKED_WIN, Achievement.STREAK5, Achievement.PRISMATIC, Achievement.HUMAN_WIN)))
        assertFalse(unlocked.contains(Achievement.SILVER))
        assertEquals(9, PlayerStats(file.matches).games)
    }

    private class FakeQueue(var enqueued: RankedTicket) : RankedQueueService {
        val polls = ArrayDeque<RankedTicket>()
        var cancelResult = RankedTicket("t", "cancelled", null, null, null, null, null)
        var fail = false
        override suspend fun enqueue(protocol: String, rankStep: Int, deckBracket: Int): RankedTicket { if (fail) error("offline"); return enqueued }
        override suspend fun poll(ticket: String) = polls.removeFirstOrNull() ?: enqueued
        override suspend fun cancel(ticket: String) = cancelResult
        override suspend fun setTable(match: String, code: String) {}
        override suspend fun report(match: String, outcome: RankOutcome) {}
    }

    private val waiting = RankedTicket("t", "waiting", null, null, null, null, null)
    private fun matched(role: String, code: String? = null) = RankedTicket("t", "matched", "m", role, code, "RankTwo", 8)

    @Test fun matchmaker() = runTest {
        assertEquals(RankedSearch.AI, RankedMatchmaker(null).search("p", 0, 2))
        assertEquals(RankedSearch.Human(matched("host")), RankedMatchmaker(FakeQueue(matched("host")), sleep = {}).search("p", 8, 2))
        val guest = FakeQueue(waiting).apply { polls.addAll(listOf(waiting, matched("guest"), matched("guest", "ABCDEF"))) }
        assertEquals(RankedSearch.Human(matched("guest", "ABCDEF")), RankedMatchmaker(guest, sleep = {}).search("p", 8, 2))
        // Nobody arrives within the search window: an AI game. The clock jumps 41 s per check.
        var now = 0L
        val timeout = RankedMatchmaker(FakeQueue(waiting), sleep = {}, clock = { now.also { now += 41_000 } })
        assertEquals(RankedSearch.AI, timeout.search("p", 8, 2))
        // Server trouble: an AI game.
        assertEquals(RankedSearch.AI, RankedMatchmaker(FakeQueue(waiting).apply { fail = true }, sleep = {}).search("p", 8, 2))
        // Timed out, but matched meanwhile: the person wins.
        now = 0L
        val late = FakeQueue(waiting).apply { cancelResult = matched("guest", "ABCDEF") }
        assertEquals(RankedSearch.Human(matched("guest", "ABCDEF")),
            RankedMatchmaker(late, sleep = {}, clock = { now.also { now += 41_000 } }).search("p", 8, 2))
        // Cancelled by the player during the search.
        val selfCancel = object { lateinit var m: RankedMatchmaker }
        selfCancel.m = RankedMatchmaker(FakeQueue(waiting), sleep = { selfCancel.m.cancel() })
        assertEquals(RankedSearch.Cancelled, selfCancel.m.search("p", 8, 2))
        assertEquals(RankedMatchmaker.Phase.Idle, selfCancel.m.phase)
    }
}
