package io.magicmobile.android.studio

import io.magicmobile.android.core.PrintingIndex
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Deck Studio "Play this deck" (DeckStudioPlaySelectionTests.swift): the flow, stored check results, the projection and the shared words. */
class DeckStudioPlaySelectionTest {
    private val upstream = "a".repeat(40)
    private val catalogue = "c".repeat(64)

    private fun resolver(): OnDeviceDeckResolver = OnDeviceDeckResolver(PrintingIndex(("#\t$catalogue\t$upstream\n" +
        "Sol Ring\tC21\t263\nForest\tM21\t274\nKardur, Doomscourge\tKHC\t10\nArcane Signet\tC21\t236\nFire\tMH2\t290\n=\tFire // Ice\tFire\n").byteInputStream()))

    private fun deck(vararg extra: DeckEntry) = DeckList("Kardur", DeckEntry("Kardur, Doomscourge", 1, "commander"),
        listOf(DeckEntry("Sol Ring", 1, "deck"), DeckEntry("Forest", 30, "main")) + extra)

    private fun store() = DeckStudioReceiptStore(File(Files.createTempDirectory("check-results").toFile(), "results-v1.json"))

    private fun passed(deck: J, build: String = "10", now: Long = 1_000) = DeckStudioValidationReceipt.success(
        JsonObject(mapOf("valid" to JsonPrimitive(true), "validator" to JsonPrimitive("Commander"), "upstream" to JsonPrimitive(upstream),
            "catalogueHash" to JsonPrimitive(catalogue), "issues" to JsonArray(emptyList()))),
        String(EngineJson.encode(deck), Charsets.UTF_8), upstream, catalogue, build, now)

    private fun rejected(deck: J, vararg issues: Triple<String, String?, String?>, build: String = "10") = DeckStudioValidationReceipt.rejection(
        JsonObject(mapOf("validator" to JsonPrimitive("Commander"), "issues" to JsonArray(issues.map { (message, group, card) ->
            JsonObject(buildMap {
                put("type", JsonPrimitive("OTHER")); put("message", JsonPrimitive(message))
                group?.let { put("group", JsonPrimitive(it)) }; card?.let { put("cardName", JsonPrimitive(it)) }
            })
        }))), "Deck failed the pinned XMage Commander validator", String(EngineJson.encode(deck), Charsets.UTF_8), upstream, catalogue, build)

    private fun result(deckID: String, request: String, valid: Boolean = true, at: Long = 1_000, build: String = "10") = DeckStudioCheckResult(
        DeckStudioCheckKey.of(deckID, request, upstream, catalogue, build), at, valid,
        if (valid) emptyList() else listOf(DeckStudioValidationReceipt.Issue(0, "OTHER", null, "Too few cards", null)), if (valid) 0 else 1,
        if (valid) "Passed" else "Failed")

    /** A draft source that counts its saves, like DeckStudioEditorModel.playSource(). */
    private class DraftSource(val deckID: String, var deck: DeckList, var dirty: Boolean, val saveFails: Boolean = false) : DeckStudioPlayFlow.Source {
        var saves = 0
        override fun prepare(): Result<DeckStudioPlayFlow.Prepared> {
            val id = DeckStudioPlayRules.sourceID(deckID.removePrefix("local:"), readOnly = false, needsSave = dirty) {
                saves += 1
                if (saveFails) null else { dirty = false; deckID.removePrefix("local:") }
            } ?: return Result.failure(IllegalStateException("Give this draft a nonempty name."))
            return Result.success(DeckStudioPlayFlow.Prepared(id, deck))
        }
    }

    private class Validator(val answer: (J) -> DeckStudioValidationReceipt) {
        val requests = ArrayList<J>()
        suspend fun validate(deck: J, @Suppress("UNUSED_PARAMETER") resolver: OnDeviceDeckResolver): DeckStudioValidationReceipt { requests += deck; return answer(deck) }
    }

    // Stored check results: key, match, invalidation and cap.

    @Test fun checkKeyHashesTheExactRequest() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", DeckStudioCheckKey.sha256("abc"))
        val key = DeckStudioCheckKey.of("local:1", "{}", upstream, catalogue, "10")
        assertEquals(DeckStudioCheckKey.sha256("{}"), key.requestSHA256)
        assertEquals(key, DeckStudioCheckKey.of("local:1", "{}", upstream, catalogue, "10"))
        for (other in listOf(DeckStudioCheckKey.of("local:2", "{}", upstream, catalogue, "10"), DeckStudioCheckKey.of("local:1", "{ }", upstream, catalogue, "10"),
            DeckStudioCheckKey.of("local:1", "{}", "b".repeat(40), catalogue, "10"), DeckStudioCheckKey.of("local:1", "{}", upstream, "d".repeat(64), "10"),
            DeckStudioCheckKey.of("local:1", "{}", upstream, catalogue, "11"))) assertNotEquals(key, other)
    }

    @Test fun storedResultsMatchOnlyTheWholeKey() {
        val store = store()
        assertEquals(DeckStudioPlayStatus.NOT_CHECKED, store.status(null))
        store.record(result("local:1", "request-a"))
        store.record(result("precon:grave-danger", "request-b", valid = false))
        assertEquals(DeckStudioPlayStatus.READY, store.status(DeckStudioCheckKey.of("local:1", "request-a", upstream, catalogue, "10")))
        assertEquals(DeckStudioPlayStatus.NEEDS_FIXES, store.status(DeckStudioCheckKey.of("precon:grave-danger", "request-b", upstream, catalogue, "10")))
        // An edited deck, another deck, a new engine, catalogue or app build all read as Not checked.
        for (key in listOf(DeckStudioCheckKey.of("local:1", "request-a2", upstream, catalogue, "10"), DeckStudioCheckKey.of("local:9", "request-a", upstream, catalogue, "10"),
            DeckStudioCheckKey.of("local:1", "request-a", "b".repeat(40), catalogue, "10"), DeckStudioCheckKey.of("local:1", "request-a", upstream, "d".repeat(64), "10"),
            DeckStudioCheckKey.of("local:1", "request-a", upstream, catalogue, "11"))) {
            assertNull(store.result(key)); assertEquals(DeckStudioPlayStatus.NOT_CHECKED, store.status(key))
        }
        store.remove("local:1")
        assertEquals(DeckStudioPlayStatus.NOT_CHECKED, store.status(DeckStudioCheckKey.of("local:1", "request-a", upstream, catalogue, "10")))
    }

    @Test fun storeKeepsTheNewest200AndFivePerDeck() {
        val store = store()
        for (index in 0 until 250) assertTrue(store.record(result("local:$index", "request", at = index.toLong())))
        assertEquals(DeckStudioReceiptStore.maximumResults, store.all().size)
        assertNull(store.result(DeckStudioCheckKey.of("local:49", "request", upstream, catalogue, "10")))
        assertEquals(DeckStudioPlayStatus.READY, store.status(DeckStudioCheckKey.of("local:50", "request", upstream, catalogue, "10")))
        for (edit in 0 until 8) store.record(result("local:249", "edit-$edit", at = 1_000L + edit))
        val kept = store.all().filter { it.key.deckID == "local:249" }
        assertEquals(DeckStudioReceiptStore.maximumPerDeck, kept.size)
        assertEquals(listOf("edit-7", "edit-6", "edit-5", "edit-4", "edit-3").map(DeckStudioCheckKey::sha256), kept.map { it.key.requestSHA256 })
        // Storing the same key again replaces it rather than adding a copy.
        store.record(result("local:249", "edit-7", valid = false, at = 2_000))
        assertEquals(1, store.all().count { it.key == DeckStudioCheckKey.of("local:249", "edit-7", upstream, catalogue, "10") })
        assertEquals(DeckStudioPlayStatus.NEEDS_FIXES, store.status(DeckStudioCheckKey.of("local:249", "edit-7", upstream, catalogue, "10")))
    }

    @Test fun storedResultsSurviveRelaunchAndAnUnreadableFileIsOnlyACacheMiss() {
        val file = File(Files.createTempDirectory("check-results").toFile(), "results-v1.json")
        var changes = 0
        DeckStudioReceiptStore(file) { changes += 1 }.record(result("local:1", "request"))
        assertEquals(1, changes)
        assertEquals(DeckStudioPlayStatus.READY, DeckStudioReceiptStore(file).status(DeckStudioCheckKey.of("local:1", "request", upstream, catalogue, "10")))
        file.writeText("{\"schema\":1,\"results\":[{\"deckID\":\"local:1\",\"valid\":true}]}")
        val reread = DeckStudioReceiptStore(file)
        assertEquals(DeckStudioPlayStatus.NOT_CHECKED, reread.status(DeckStudioCheckKey.of("local:1", "request", upstream, catalogue, "10")))
        assertTrue(reread.record(result("local:2", "other")))
        assertEquals(1, DeckStudioReceiptStore(file).all().size)
    }

    @Test fun checkResultsRoundTripAndKeepTheFirst100Issues() {
        val deck = resolver().resolve(deck())
        val issues = (1..130).map { Triple("Issue $it", if (it % 2 == 0) "Deck" else null, if (it == 1) "Sol Ring" else null) }.toTypedArray()
        val result = DeckStudioCheckResult.of("local:1", rejected(deck, *issues))
        assertEquals(DeckStudioCheckResult.maximumIssues, result.issues.size)
        assertEquals(130, result.issueCount)
        assertEquals(result, DeckStudioCheckResult.decode(result.json()))
        val request = String(EngineJson.encode(deck), Charsets.UTF_8)
        assertEquals(request, result.receipt(request)?.request)
        assertNull(result.receipt("$request "))
    }

    // The play projection: every game start and every check leave sideboard, maybeboard and considering out.

    @Test fun playProjectionLeavesOtherBoardsOut() {
        val projection = DeckStudioPlayProjection(deck(DeckEntry("Arcane Signet", 1, "sideboard"), DeckEntry("Fire", 2, "Maybeboard"), DeckEntry("Forest", 3, "considering"),
            DeckEntry("Arcane Signet", 1, "companions")))
        assertEquals(6, projection.excluded.sumOf { it.quantity })
        assertEquals(listOf("deck", "main", "companions"), projection.playing.entries.map { it.section })
        val request = projection.resolve(resolver())
        val names = listOf("main", "commanders", "companions").flatMap { section -> request[section].array!!.map { it["name"].string } }
        assertEquals(listOf("Sol Ring", "Forest", "Kardur, Doomscourge", "Arcane Signet"), names)
        assertEquals(31, request["main"].array!!.sumOf { (it as JsonObject)["count"].toString().toInt() })
        try { DeckStudioPlayProjection(deck(DeckEntry("Sol Ring", 1, "tokens"))); throw AssertionError("An unknown section must not be dropped") } catch (expected: ResolutionError) {}
    }

    // Play: source rules, the dirty-draft save and the flow.

    @Test fun playSelectsTheSourceDeckAndSavesOnlyWhenNeeded() {
        var saves = 0
        val save = { saves += 1; "new-id" }
        assertEquals("precon:grave-danger", DeckStudioPlayRules.sourceID("precon:grave-danger", readOnly = true, needsSave = false, save = save))
        assertEquals("local:cloud", DeckStudioPlayRules.sourceID("cloud", readOnly = true, needsSave = false, save = save))
        assertEquals(0, saves)
        assertEquals("local:saved", DeckStudioPlayRules.sourceID("saved", readOnly = false, needsSave = false, save = save))
        assertEquals(0, saves)
        assertEquals("local:new-id", DeckStudioPlayRules.sourceID("saved", readOnly = false, needsSave = true, save = save))
        assertEquals("local:new-id", DeckStudioPlayRules.sourceID(null, readOnly = false, needsSave = false, save = save))
        assertEquals(2, saves)
        assertNull(DeckStudioPlayRules.sourceID(null, readOnly = false, needsSave = true) { null })
    }

    @Test fun aLiveGameStopsPlayBeforeSavingOrChecking() = runBlocking {
        val validator = Validator { passed(it) }
        val source = DraftSource("local:1", deck(), dirty = true)
        val outcome = DeckStudioPlayFlow(store(), "10", validator::validate).play(source, gameLive = true, resolver = resolver())
        assertEquals(DeckStudioPlayFlow.Outcome.GameLive, outcome)
        assertEquals(0, source.saves); assertTrue(validator.requests.isEmpty())
    }

    @Test fun aDirtyDraftIsSavedThenCheckedAndTheSourceDeckIsSelected() = runBlocking {
        val store = store()
        val validator = Validator { passed(it) }
        val flow = DeckStudioPlayFlow(store, "10", validator::validate)
        val source = DraftSource("local:1", deck(DeckEntry("Arcane Signet", 2, "sideboard"), DeckEntry("Fire", 1, "maybeboard")), dirty = true)
        var checking: String? = null
        val outcome = flow.play(source, gameLive = false, resolver = resolver()) { checking = it }
        assertEquals(1, source.saves)
        assertEquals("Kardur", checking)
        assertEquals(DeckStudioPlayFlow.Outcome.Playing("local:1", "Kardur", excludedCards = 3, checkedNow = true), outcome)
        // XMage checked the projection: no sideboard or maybeboard card was sent.
        assertEquals(resolver().resolve(DeckStudioPlayProjection(source.deck).playing), validator.requests.single())
        assertEquals(DeckStudioPlayStatus.READY, DeckStudioPlayRules.status("local:1", source.deck, resolver(), "10", store))
        // Playing again reuses the stored pass: no save (clean now) and no second check.
        assertEquals(DeckStudioPlayFlow.Outcome.Playing("local:1", "Kardur", 3, checkedNow = false), flow.play(source, false, resolver()))
        assertEquals(1, source.saves); assertEquals(1, validator.requests.size)
        // A new app build invalidates the stored result, so XMage checks again.
        DeckStudioPlayFlow(store, "11", validator::validate).play(source, false, resolver())
        assertEquals(2, validator.requests.size)
    }

    @Test fun aFailedSaveOrAnUnresolvableDeckNeverReachesXMage() = runBlocking {
        val validator = Validator { passed(it) }
        val flow = DeckStudioPlayFlow(store(), "10", validator::validate)
        val unsaved = flow.play(DraftSource("local:1", deck(), dirty = true, saveFails = true), false, resolver())
        assertEquals(DeckStudioPlayFlow.Outcome.CannotPlay(null, "", "Give this draft a nonempty name.", emptyList()), unsaved)
        val loading = flow.play(DraftSource("local:1", deck(), dirty = false), false, null) as DeckStudioPlayFlow.Outcome.CannotPlay
        assertEquals(DeckStudioPlayText.catalogueLoading, loading.message)
        val unknown = flow.play(DraftSource("local:1", deck(DeckEntry("Imaginary Card", 1, "deck"), DeckEntry("Mystery", 1, "sideboard")), dirty = false), false, resolver())
        unknown as DeckStudioPlayFlow.Outcome.CannotPlay
        assertEquals("local:1", unknown.deckID)
        assertEquals(listOf("Imaginary Card"), unknown.cards)
        assertTrue(unknown.message.contains("Imaginary Card"))
        assertTrue(validator.requests.isEmpty())
    }

    @Test fun aRejectedDeckIsStoredAndNotSelectedAndIsCheckedAgainNextTime() = runBlocking {
        val store = store()
        val validator = Validator { rejected(it, Triple("Sol Ring is banned", "Banned", "Sol Ring"), Triple("Deck must have 100 cards", "Deck", null),
            Triple("Sol Ring is restricted", "Banned", "Sol Ring")) }
        val flow = DeckStudioPlayFlow(store, "10", validator::validate)
        val source = DraftSource("local:1", deck(), dirty = false)
        val blocked = flow.play(source, false, resolver()) as DeckStudioPlayFlow.Outcome.Blocked
        assertEquals("local:1", blocked.deckID)
        assertEquals(3, blocked.result.issueCount)
        assertEquals(listOf("Sol Ring"), DeckStudioPlayRules.issueCards(blocked.result))
        assertEquals(listOf("Banned" to 2, "Deck" to 1), DeckStudioPlayRules.groupedIssues(blocked.result.issues).map { it.first to it.second.size })
        assertEquals(DeckStudioPlayStatus.NEEDS_FIXES, DeckStudioPlayRules.status("local:1", source.deck, resolver(), "10", store))
        // A stored failure never blocks a new check: Play asks XMage again.
        flow.play(source, false, resolver())
        assertEquals(2, validator.requests.size)
    }

    @Test fun anEngineFailureStoresNothing() = runBlocking {
        val store = store()
        val flow = DeckStudioPlayFlow(store, "10") { _, _ -> throw IllegalStateException("The rules engine is still closing.") }
        val outcome = flow.play(DraftSource("local:1", deck(), dirty = false), false, resolver())
        assertEquals(DeckStudioPlayFlow.Outcome.CheckFailed("local:1", "Kardur", "The rules engine is still closing."), outcome)
        assertTrue(store.all().isEmpty())
    }

    @Test fun unplayableCardsNameUnknownCardsSectionsAndSplits() {
        val deck = DeckList("Test", DeckEntry("Kardur, Doomscourge", 1, "commander"), listOf(DeckEntry("Imaginary", 1, "deck"), DeckEntry("Sol Ring", 1, "tokens"),
            DeckEntry("Forest", 1, "deck"), DeckEntry("Forest", 1, "companions"), DeckEntry("Nope", 1, "maybeboard"), DeckEntry("Ice", 1, "deck")))
        assertEquals(listOf("Imaginary", "Sol Ring", "Forest"), DeckStudioPlayRules.unplayableCards(deck, resolver()))
        assertTrue(DeckStudioPlayRules.unplayableCards(deck(), resolver()).isEmpty())
    }

    @Test fun sharedWordsMatchIOS() {
        assertEquals("1 rule issue blocks play", DeckStudioPlayText.issuesBlockPlay(1))
        assertEquals("3 rule issues block play", DeckStudioPlayText.issuesBlockPlay(3))
        assertEquals("1 issue", DeckStudioPlayText.issues(1)); assertEquals("2 issues", DeckStudioPlayText.issues(2))
        assertEquals("Sideboard and maybeboard stay out of play (1 card).", DeckStudioPlayText.excluded(1))
        assertEquals("Sideboard and maybeboard stay out of play (7 cards).", DeckStudioPlayText.excluded(7))
        assertEquals("Now playing Kardur", DeckStudioPlayText.nowPlaying("Kardur"))
        assertEquals("Now playing: Kardur · Ready", DeckStudioPlayText.nowPlayingStrip("Kardur", DeckStudioPlayStatus.READY))
        assertEquals("XMage is checking Kardur against the Commander rules on this device.", DeckStudioPlayText.checking("Kardur"))
        assertEquals("This is your playing deck. Token Triumph will be selected instead.", DeckStudioPlayText.deletePlaying("Token Triumph"))
        assertEquals(listOf("Ready", "Needs fixes", "Not checked"), DeckStudioPlayStatus.entries.map { it.title })
        assertEquals(listOf("Ready · checked on this device", "Needs fixes · Fix in Deck Studio", "Not checked — Start will check it"),
            DeckStudioPlayStatus.entries.map(DeckStudioPlayText::setupStatus))
        assertFalse(DeckStudioPlayText.play == DeckStudioPlayText.saveAndPlay)
    }
}
