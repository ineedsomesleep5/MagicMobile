package io.magicmobile.android.studio

import io.magicmobile.android.core.Catalogue
import io.magicmobile.android.core.PrintingIndex
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Ports of OnDeviceDeckEditingTests.swift and DeckStudioCoreTests.swift: the same grammar and rules on both phones. */
class DeckStudioTest {
    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit): T {
        try { block() } catch (error: Throwable) { if (error is T) return error; throw AssertionError("Unexpected ${error::class.simpleName}: ${error.message}", error) }
        fail("Expected ${T::class.simpleName}"); throw IllegalStateException()
    }

    private fun annotations(vararg values: Pair<Int, String>) = values.map { OnDeviceDeckEditing.TextAnnotation(it.first, it.second) }

    @Test fun exactProviderHostedCopiedSyntax() {
        val samples = listOf(
            Triple("1x Sol Ring (clb) [Ramp]", "deck", listOf("Category retained: [Ramp]", "(clb)")),
            Triple("1 Sol Ring (CMM) 396 #!Mana Ramp", "deck", listOf("#!Mana Ramp", "(CMM) 396")))
        for ((source, section, notes) in samples) {
            val result = OnDeviceDeckEditing.importText(source, "Copied example")
            assertEquals(1, result.deck.entries.size)
            assertEquals("Sol Ring", result.deck.entries[0].cardName)
            assertEquals(1, result.deck.entries[0].quantity)
            assertEquals(section, result.deck.entries[0].section)
            assertEquals(notes.map { OnDeviceDeckEditing.TextAnnotation(1, it) }, result.annotations)
        }
    }

    @Test fun textExportHeadersKeepCommanderPartnerCompanionAndBoards() {
        val result = OnDeviceDeckEditing.importText("""
            Commander
            1 Tymna the Weaver
            1x Thrasios, Triton Hero
            Companion:
            1 Zirda, the Dawnwaker
            // Mainboard
            2x Forest
            # Sideboard
            1 Forest
            Maybeboard
            1 Unknown New Card
        """.trimIndent(), "Pasted")
        assertEquals("Tymna the Weaver", result.deck.commander?.cardName)
        assertEquals(listOf("commanders", "companions", "deck", "sideboard", "maybeboard"), result.deck.entries.map { it.section })
        assertEquals(7, result.deck.totalCards)
        assertEquals("Unknown New Card", result.deck.entries.last().cardName)
    }

    @Test fun moxfieldPrintingFoilAndBulkTagsRetainNamesAndAnnotations() {
        val result = OnDeviceDeckEditing.importText("1 Sol Ring (CMM) 396 #!Mana Ramp\n1 Arcane Signet (CMM) 384 *F*\n2 Rampant Growth (9ED) 263", "Moxfield")
        assertEquals(listOf("Sol Ring", "Arcane Signet", "Rampant Growth"), result.deck.entries.map { it.cardName })
        assertEquals(4, result.deck.totalCards)
        assertTrue(result.annotations.containsAll(annotations(1 to "#!Mana Ramp", 2 to "*F*", 3 to "(9ED) 263")))
    }

    @Test fun archidektCategoryPrintingLabelAndCommanderTop() {
        val result = OnDeviceDeckEditing.importText("""
            1x Emmara, Soul of the Accord (grn) *F* [Commander{top}] ^Owned,#000000^
            1x Sol Ring (clb) [Ramp]
            2x Swamp (ltr) 267 [Land]
            1x Unknown Future Card [Maybeboard]
            1x Forest [Sideboard]
        """.trimIndent(), "Archidekt")
        assertEquals("Emmara, Soul of the Accord", result.deck.commander?.cardName)
        assertEquals(listOf("Sol Ring", "Swamp", "Unknown Future Card", "Forest"), result.deck.entries.map { it.cardName })
        assertEquals(listOf("deck", "deck", "maybeboard", "sideboard"), result.deck.entries.map { it.section })
        assertEquals(6, result.deck.totalCards)
        assertTrue(OnDeviceDeckEditing.TextAnnotation(1, "^Owned,#000000^") in result.annotations)
    }

    @Test fun textImportPreservesPunctuationAndUnknownCustomSections() {
        val names = listOf("Fire // Ice", "B.F.M. (Big Furry Monster)", "\"Ach! Hans, Run!\"", "Who/What/When/Where/Why", "Asmoranomardicadaistinaculdacar",
            "Éowyn, Shieldmaiden", "Urza's Saga")
        val result = OnDeviceDeckEditing.importText("// Unrecognized custom section\n" + names.joinToString("\n") { "1 $it" }, "Punctuation")
        assertEquals(names, result.deck.entries.map { it.cardName })
        assertTrue(result.deck.entries.all { it.section == "deck" })
        assertTrue(OnDeviceDeckEditing.TextAnnotation(1, "Grouping retained in deck: Unrecognized custom section") in result.annotations)
    }

    @Test fun archidektGroupingsPreserveMainDeckAndExplicitZones() {
        val result = OnDeviceDeckEditing.importText("""
            1x Emmara, Soul of the Accord [Commander{top}]
            // Creatures
            2x Unknown Creature [Creature]
            // Ramp
            1x Sol Ring [Ramp]
            // Lands
            3x Forest [Land]
            Sideboard
            // Creatures
            1x Unknown Sideboard Creature [Creature]
            Maybeboard
            // Future ideas
            1x Unknown Future Card [Custom Group]
        """.trimIndent(), "Grouped export")
        assertEquals("Emmara, Soul of the Accord", result.deck.commander?.cardName)
        assertEquals(listOf("deck", "deck", "deck", "sideboard", "maybeboard"), result.deck.entries.map { it.section })
        assertEquals(listOf(2, 1, 3, 1, 1), result.deck.entries.map { it.quantity })
        assertEquals(9, result.deck.totalCards)
        assertTrue(OnDeviceDeckEditing.TextAnnotation(9, "Grouping retained in sideboard: Creatures") in result.annotations)
        assertEquals(1, assertThrows<OnDeviceDeckEditing.TextImportError> { OnDeviceDeckEditing.importText("1x Forest [Land{noDeck}]", "Ambiguous") }.line)
    }

    @Test fun textImportBOMCRLFAndExactErrorLineNumbers() {
        val deck = OnDeviceDeckEditing.importText("﻿Commander\r\n1 Leader\r\n\r\nDeck\r\n2x Forest", "Windows").deck
        assertEquals("Leader", deck.commander?.cardName)
        assertEquals(3, deck.totalCards)
        for (invalid in listOf("0 Forest", "-1 Forest", "1.5 Forest", "999999999999999999999 Forest", "1", "Some unknown heading", "1 Sol Ring [Ramp] [Draw]",
            "1 Sol Ring [", "1 Sol Ring ^Bad label^", "1 Sol Ring [Ramp{top}]")) {
            val error = assertThrows<OnDeviceDeckEditing.TextImportError> { OnDeviceDeckEditing.importText("Deck\r\n1 Forest\r\n\r\n$invalid", "Invalid") }
            assertEquals(invalid, 4, error.line)
            assertTrue(error.message!!.contains("No cards were imported."))
        }
    }

    @Test fun textImportRejectsConflictingRolesAndLimitsWithoutDroppingRows() {
        for (text in listOf("Sideboard\n1 Sol Ring [Commander]", "Commander\n1 Sol Ring [Maybeboard]", "2000 Forest\n1 Island")) {
            assertEquals(2, assertThrows<OnDeviceDeckEditing.TextImportError> { OnDeviceDeckEditing.importText(text, "Invalid") }.line)
        }
        assertThrows<Exception> { OnDeviceDeckEditing.importText("Commander\n", "Empty") }
        assertThrows<Exception> { OnDeviceDeckEditing.importText("x".repeat(OnDeviceDeckEditing.maximumJSONBytes + 1), "Large") }
        assertThrows<Exception> { OnDeviceDeckEditing.importText("1 Forest", " ") }
        val result = OnDeviceDeckEditing.importText("Sideboard\n1 Forest [Land]", "Excluded")
        assertEquals("sideboard", result.deck.entries.first().section)
        assertTrue(OnDeviceDeckEditing.TextAnnotation(2, "Category retained: [Land]") in result.annotations)
    }

    @Test fun deletingDeckRecoveryRemovesAllRevisionsIncludingCorruptPayloads() {
        val defaults = MemoryDefaults()
        val draft = NativeDeckDraft(rows = listOf(NativeDeckRow(cardName = "Forest")))
        NativeDeckDraftRecovery.save(draft, "deck.1", defaults)
        NativeDeckDraftRecovery.save(draft, "deck.2", defaults)
        defaults.set("deckStudio.draft.deck.3", "broken")
        NativeDeckDraftRecovery.clearRecord("deck", defaults)
        for (revision in 1..3) assertNull(defaults.string("deckStudio.draft.deck.$revision"))
        NativeDeckDraftRecovery.clearRecord("deck", defaults)
    }

    @Test fun deletingDeckRecoveryPreservesOtherRecordsNewDraftAndPreferences() {
        val defaults = MemoryDefaults()
        val draft = NativeDeckDraft(name = "Keep me")
        for (key in listOf("deck.1", "deck-other.1", "deck.child.1", "other.1", "new")) NativeDeckDraftRecovery.save(draft, key, defaults)
        defaults.set("magicmobile.deckArtworkNetworkEnabled", "true")
        NativeDeckDraftRecovery.clearRecord("deck", defaults)
        assertNull(NativeDeckDraftRecovery.load("deck.1", defaults))
        for (key in listOf("deck-other.1", "deck.child.1", "other.1", "new")) assertEquals(draft, NativeDeckDraftRecovery.load(key, defaults))
        assertEquals("true", defaults.string("magicmobile.deckArtworkNetworkEnabled"))
    }

    @Test fun recoveryPreservesIncompleteNameRowIdentityAndSections() {
        val defaults = MemoryDefaults()
        val draft = NativeDeckDraft(name = "", rows = listOf(NativeDeckRow(cardName = "Unknown", section = "sideboard")))
        NativeDeckDraftRecovery.save(draft, "deck.revision1", defaults)
        assertEquals(draft, NativeDeckDraftRecovery.load("deck.revision1", defaults))
        assertNull(NativeDeckDraftRecovery.load("deck.revision2", defaults))
        NativeDeckDraftRecovery.clear("deck.revision1", defaults)
        assertNull(NativeDeckDraftRecovery.load("deck.revision1", defaults))
    }

    @Test fun corruptRecoveryIsReportedAndRetained() {
        val defaults = MemoryDefaults()
        defaults.set("deckStudio.draft.new", "broken")
        assertThrows<Exception> { NativeDeckDraftRecovery.load("new", defaults) }
        assertEquals("broken", defaults.string("deckStudio.draft.new"))
    }

    @Test fun basicLandToolsOnlyChangeMainDeckAndPreserveStableIdentity() {
        var draft = NativeDeckDraft(name = "", rows = listOf(NativeDeckRow(cardName = "Forest", quantity = 4), NativeDeckRow(cardName = "Forest", quantity = 2, section = "main"),
            NativeDeckRow(cardName = "Forest", quantity = 3, section = "sideboard"), NativeDeckRow(cardName = "Forest", quantity = 1, section = "commanders", isPrimaryCommander = true)))
        val firstID = draft.rows[0].id
        val protected = draft.rows.takeLast(2)
        assertEquals(6, draft.basicLandCount("Forest"))
        draft = draft.settingBasicLandCount("Forest", 10)
        assertEquals(10, draft.basicLandCount("Forest"))
        assertEquals(firstID, draft.rows.last().id)
        assertEquals(protected, draft.rows.take(2))
        draft = draft.settingBasicLandCount("Forest", 0)
        assertEquals(protected, draft.rows)
        draft = draft.settingBasicLandCount("Wastes", 2)
        assertEquals(2, draft.basicLandCount("Wastes"))
    }

    @Test fun invalidBasicLandEditsAreAtomic() {
        var draft = NativeDeckDraft(name = "Limit", rows = listOf(NativeDeckRow(cardName = "Island", quantity = 2000)))
        val original = draft.rows
        for ((name, count) in listOf("Forest" to 1, "Island" to -1, "Island" to 2001, "Sol Ring" to 1)) {
            assertThrows<Exception> { draft = draft.settingBasicLandCount(name, count) }
            assertEquals(original, draft.rows)
        }
        draft = draft.settingBasicLandCount("Island", 1999).settingBasicLandCount("Forest", 1)
        assertEquals(2000, draft.deck().totalCards)
    }

    private val input = DeckList("Editing copy", DeckEntry("Tymna the Weaver", 1, "commander"), listOf(
        DeckEntry("Thrasios, Triton Hero", 1, "commanders"), DeckEntry("Zirda, the Dawnwaker", 1, "Companion"),
        DeckEntry("Forest", 12, "deck"), DeckEntry("Island", 3, "unsupported-custom-section")))

    @Test fun primaryCommanderRoleSurvivesDifferentSectionAndJSONRoundTrip() {
        for (section in listOf("deck", "companions", " Unknown original section ")) {
            val original = DeckList("Role", DeckEntry("Tymna the Weaver", 1, section), listOf(DeckEntry("Thrasios, Triton Hero", 1, "commanders")))
            var draft = NativeDeckDraft.of(original)
            assertTrue(draft.rows[0].isPrimaryCommander); assertFalse(draft.rows[1].isPrimaryCommander)
            assertEquals(original, draft.deck())
            assertEquals(original, NativeDeckDraft.importJSON(draft.exportJSON()).deck())
            draft = draft.copy(rows = listOf(draft.rows[1], draft.rows[0]))
            assertEquals(original, draft.deck())
        }
    }

    @Test fun multiplePrimaryMarkersRejectAndExplicitSectionEditClearsRole() {
        var draft = NativeDeckDraft.of(input)
        draft = draft.copy(rows = draft.rows.mapIndexed { i, row -> if (i == 1) row.copy(isPrimaryCommander = true) else row })
        assertThrows<DeckEditingError> { draft.deck() }
        assertThrows<DeckEditingError> { draft.exportJSON() }
        draft = draft.copy(rows = draft.rows.mapIndexed { i, row -> when (i) { 1 -> row.copy(isPrimaryCommander = false); 0 -> row.copy(section = "deck", isPrimaryCommander = false); else -> row } })
        val result = draft.deck()
        assertEquals("Thrasios, Triton Hero", result.commander?.cardName)
        assertEquals("Tymna the Weaver", result.entries.first().cardName)
        assertEquals("deck", result.entries.first().section)
    }

    @Test fun unmarkedFirstCommanderFallbackPreservesSectionVerbatim() {
        val draft = NativeDeckDraft("Fallback", listOf(NativeDeckRow(cardName = "Forest", section = "unknown"),
            NativeDeckRow(cardName = "Tymna the Weaver", section = " Commanders "), NativeDeckRow(cardName = "Thrasios, Triton Hero", section = "commanders")))
        assertEquals(" Commanders ", draft.deck().commander?.section)
        assertEquals(listOf("unknown", "commanders"), draft.deck().entries.map { it.section })
    }

    @Test fun draftByteAndCountLimitsIncludingCommander() {
        NativeDeckDraft("é".repeat(256)).deck()
        assertThrows<DeckEditingError> { NativeDeckDraft("é".repeat(257)).deck() }
        val valid = NativeDeckRow(cardName = "é".repeat(1000), quantity = 2000, section = "unknown")
        assertEquals(2000, NativeDeckDraft("Bound", listOf(valid)).deck().totalCards)
        assertThrows<DeckEditingError> { NativeDeckDraft("Bound", listOf(valid.copy(cardName = valid.cardName + "x"))).deck() }
        assertThrows<DeckEditingError> { NativeDeckDraft("Bound", listOf(valid.copy(quantity = 2001))).deck() }
        assertThrows<DeckEditingError> { NativeDeckDraft("Bound", listOf(valid, NativeDeckRow(cardName = "Commander", section = "commanders"))).deck() }
        assertThrows<DeckEditingError> { NativeDeckDraft("Bound", listOf(valid.copy(section = "x".repeat(2001)))).deck() }
    }

    @Test fun jsonLimitIsCheckedBeforeDecodeAndMalformedInputRejects() {
        assertThrows<DeckEditingError.OversizedJSON> { NativeDeckDraft.importJSON(" ".repeat(OnDeviceDeckEditing.maximumJSONBytes + 1)) }
        assertThrows<Exception> { NativeDeckDraft.importJSON("not json") }
        assertThrows<Exception> { NativeDeckDraft.importJSON("""{"name":"Invalid","entries":[{"cardName":"Forest","quantity":9223372036854775807,"section":"deck"}]}""") }
        val empty = NativeDeckDraft("Empty draft")
        assertEquals(empty.deck(), NativeDeckDraft.importJSON(empty.exportJSON()).deck())
    }

    @Test fun draftRoundTripPreservesCommanderPartnerCompanionAndUnknownSections() {
        val draft = NativeDeckDraft.of(input)
        assertEquals(input, draft.deck())
        assertEquals(draft.rows.size, draft.rows.map { it.id }.toSet().size)
        assertEquals(input, NativeDeckDraft.importJSON(draft.exportJSON()).deck())
    }

    @Test fun draftAllowsIncompleteCountsButRejectsBlankFieldsAndBadQuantities() {
        assertEquals(0, NativeDeckDraft("Draft").deck().totalCards)
        assertThrows<DeckEditingError> { NativeDeckDraft("  \n").deck() }
        for (row in listOf(NativeDeckRow(cardName = ""), NativeDeckRow(cardName = "Forest", quantity = 0), NativeDeckRow(cardName = "Forest", quantity = -1),
            NativeDeckRow(cardName = "Forest", section = ""))) assertThrows<DeckEditingError> { NativeDeckDraft("Draft", listOf(row)).deck() }
        assertThrows<DeckEditingError> { NativeDeckDraft("Overflow", listOf(NativeDeckRow(cardName = "Forest", quantity = Int.MAX_VALUE), NativeDeckRow(cardName = "Island"))).deck() }
        NativeDeckDraft("Unresolved", listOf(NativeDeckRow(cardName = "Unresolved exact input"))).deck()
    }

    @Test fun duplicateNamesInDifferentSectionsRemainSeparateRows() {
        val draft = NativeDeckDraft("Sections", listOf(NativeDeckRow(cardName = "Forest", quantity = 3, section = "deck"), NativeDeckRow(cardName = "Forest", quantity = 2, section = "sideboard")))
        assertEquals(2, draft.deck().entries.size)
        assertEquals(draft.deck(), NativeDeckDraft.importJSON(draft.exportJSON()).deck())
    }

    @Test fun textExportRoundTripsTheStandardBoards() {
        val deck = DeckList("Export", DeckEntry("Tymna the Weaver", 1, "commanders"), listOf(DeckEntry("Thrasios, Triton Hero", 1, "commanders"),
            DeckEntry("Forest", 30, "deck"), DeckEntry("Island", 2, "sideboard")))
        val text = DeckStudioTextExport.text(deck)
        assertTrue(text.startsWith("Commander\n1 Tymna the Weaver\n1 Thrasios, Triton Hero\n\nDeck\n30 Forest"))
        assertThrows<DeckStudioTextExport.RequiresJSON> { DeckStudioTextExport.text(DeckList("Custom", null, listOf(DeckEntry("Forest", 1, "tokens")))) }
    }

    // DeckStudioCoreTests.swift

    private fun catalogue(rows: List<JsonObject>, aliases: Map<String, String> = emptyMap()): NativeDeckMetadataCatalogue {
        val header = JsonObject(mapOf("catalogueHash" to JsonPrimitive("c".repeat(64)), "upstreamCommit" to JsonPrimitive("a".repeat(40)),
            "sourceMetadataSHA256" to JsonPrimitive("b".repeat(64)), "nameAliases" to JsonObject(aliases.mapValues { JsonPrimitive(it.value) })))
        val text = (listOf(header) + rows).joinToString("\n") { it.toString() }
        return NativeDeckMetadataCatalogue(Catalogue(text.byteInputStream()))
    }

    private fun card(name: String, type: String, identity: List<String>, set: String, mana: Int, index: Int, oracle: String? = null) = JsonObject(buildMap {
        put("name", JsonPrimitive(name)); put("setCode", JsonPrimitive(set)); put("collectorNumber", JsonPrimitive("$index"))
        put("types", JsonArray(listOf(JsonPrimitive(type)))); put("typeLine", JsonPrimitive(type.lowercase().replaceFirstChar { it.uppercase() }))
        put("manaValue", JsonPrimitive(mana)); put("colorIdentity", JsonArray(identity.map(::JsonPrimitive))); put("setCodes", JsonArray(listOf(JsonPrimitive(set))))
        oracle?.let { put("oracleText", JsonPrimitive(it)) }
    })

    private fun searchRankingCatalogue(): NativeDeckMetadataCatalogue {
        val rows = (0 until 2101).map { card("A%04d".format(it), "CREATURE", listOf("G"), "TST", 3, it, "Search for a Forest.") } + listOf(
            card("Forest", "LAND", listOf("G"), "TST", 0, 9001), card("Forest Brook", "CREATURE", listOf("W"), "ALT", 3, 9002),
            card("Forest Glade", "CREATURE", listOf("G"), "TST", 3, 9003), card("Z Forest", "CREATURE", listOf("G"), "TST", 3, 9004))
        return catalogue(rows.reversed())
    }

    @Test fun searchRankingBeforeCapsAndIdentitySubsetMerge() {
        val catalogue = searchRankingCatalogue()
        for (identity in listOf(null, listOf("W", "G"))) {
            val results = DeckStudioCatalogueSearch.cards(catalogue, "  fOrEsT\n", allowedIdentity = identity)
            assertEquals(80, results.size)
            assertEquals(listOf("Forest", "Forest Brook", "Forest Glade", "Z Forest", "A0000", "A0001"), results.take(6).map { it.name })
            assertEquals(listOf("Forest"), DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = identity, limit = 1).map { it.name })
            assertEquals(2000, DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = identity, limit = 3000).size)
            assertEquals(listOf("A0000", "A0001"), DeckStudioCatalogueSearch.cards(catalogue, " \n", allowedIdentity = identity, limit = 2).map { it.name })
        }
        assertEquals(listOf("Forest"), catalogue.search(NativeDeckMetadataCatalogue.SearchFilter(query = " FOREST "), 1).map { it.name })
        assertTrue(DeckStudioCatalogueSearch.cards(catalogue, "forest", limit = 0).isEmpty())
    }

    @Test fun searchRankingNeverRestoresFilteredExactMatch() {
        val catalogue = searchRankingCatalogue()
        for (identity in listOf(null, listOf("G", "W"))) {
            assertEquals(listOf("Forest Brook"), DeckStudioCatalogueSearch.cards(catalogue, "forest", "Creature", identity, limit = 1).map { it.name })
            assertEquals(listOf("Forest Brook"), DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = identity, setCode = "ALT", limit = 1).map { it.name })
            assertEquals(listOf("Forest Brook"), DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = identity, minimumManaValue = 2.0, maximumManaValue = 4.0, limit = 1).map { it.name })
            assertTrue(DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = identity, minimumManaValue = 4.0).isEmpty())
        }
        assertEquals(listOf("Forest Brook"), DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = listOf("W"), limit = 1).map { it.name })
        assertTrue(DeckStudioCatalogueSearch.cards(catalogue, "forest", allowedIdentity = emptyList()).isEmpty())
        assertEquals(listOf("Forest Brook"), catalogue.search(NativeDeckMetadataCatalogue.SearchFilter(query = "forest", colorIdentity = setOf("W")), 1).map { it.name })
    }

    @Test fun searchIncludesPartnerAndDiacriticsAndStableTies() {
        val first = DeckStudioShelfItem("local:a", "Élan", listOf("One", "Partner"), listOf("Tokens"), DeckStudioShelfItem.Origin.LOCAL, null)
        val second = DeckStudioShelfItem("precon:a", "Élan", listOf("Two"), emptyList(), DeckStudioShelfItem.Origin.INCLUDED, null)
        var query = DeckStudioLibraryQuery(text = "  ELAN PARTNER ")
        assertEquals(listOf("local:a"), query.apply(listOf(second, first), emptySet()).map { it.id })
        query = query.copy(text = "", filter = DeckStudioLibraryQuery.Filter.FAVORITES)
        assertEquals(listOf("precon:a"), query.apply(listOf(second, first), setOf("precon:a")).map { it.id })
        query = query.copy(filter = DeckStudioLibraryQuery.Filter.ALL, sort = DeckStudioLibraryQuery.Sort.NAME)
        assertEquals(listOf("local:a", "precon:a"), query.apply(listOf(second, first), emptySet()).map { it.id })
    }

    @Test fun atomicFailurePreservesHistoryAndDraft() {
        val history = DeckStudioEditHistory(listOf(1, 2))
        val token = history.generation
        assertThrows<IllegalStateException> { history.edited { it + 3; throw IllegalStateException("expected") } }
        assertEquals(listOf(1, 2), history.value); assertEquals(token, history.generation)
        assertFalse(history.canUndo); assertFalse(history.isDirty)
    }

    @Test fun undoRedoHaveNewGenerationEvenWhenContentsReturnToBaseline() {
        var history = DeckStudioEditHistory("a")
        val initial = history.generation
        history = history.edited { "b" }; val changed = history.generation
        history = history.undone()
        assertEquals("a", history.value); assertFalse(history.isDirty)
        assertNotEquals(initial, history.generation); assertNotEquals(changed, history.generation)
        history = history.redone().saved(); assertFalse(history.isDirty)
        history = history.undone(); assertTrue(history.isDirty)
        history = history.edited { "c" }; assertFalse(history.canRedo)
    }

    @Test fun boundedRecoveryAndNoOp() {
        var history = DeckStudioEditHistory(0, limit = 2)
        val token = history.generation
        history = history.edited { it }; assertEquals(token, history.generation)
        history = history.edited { 1 }.edited { 2 }.edited { 3 }
        history = history.undone().undone().undone(); assertEquals(1, history.value)
        history = history.restored(8); assertTrue(history.isDirty)
        history = history.undone(); assertEquals(1, history.value)
    }

    @Test fun probabilityMatchesIndependentExactEnumeration() {
        for (successes in 0..6) for (draws in 0..6) {
            val samples = (0 until 64).filter { Integer.bitCount(it) == draws }
            for (threshold in -1..7) {
                val passing = samples.count { mask -> Integer.bitCount(mask and ((1 shl successes) - 1)) >= threshold }
                assertEquals(passing.toDouble() / samples.size, DeckStudioProbability.atLeast(threshold, successes, 6, draws), 1e-12)
            }
        }
        assertThrows<DeckStudioProbability.InvalidPopulation> { DeckStudioProbability.atLeast(1, 8, 7, 7) }
        assertThrows<DeckStudioProbability.InvalidPopulation> { DeckStudioProbability.atLeast(1, 1, 2001, 7) }
    }

    @Test fun edhrecBrowsingPolicyDoesNotConfuseLookalikeHosts() {
        assertTrue(DeckStudioEDHRECPolicy.allowsEmbeddedNavigation("https://edhrec.com/commanders"))
        for (value in listOf("https://edhrec.com.evil.example", "https://user@edhrec.com", "http://edhrec.com", "https://edhrec.com:8443", "file:///tmp/private", "javascript:alert(1)")) {
            assertFalse(value, DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(value))
        }
    }

    @Test fun identityFilteringOccursBeforeResultCap() {
        val rows = (0 until 2100).map { card("A%04d Red card".format(it), "CREATURE", listOf("R"), "TST", 1, it) } + listOf(
            card("Z Colorless", "CREATURE", emptyList(), "TST", 1, 5001), card("Z Green", "CREATURE", listOf("G"), "TST", 1, 5002),
            card("Z Green White", "CREATURE", listOf("G", "W"), "TST", 1, 5003), card("Z White", "CREATURE", listOf("W"), "TST", 1, 5004),
            JsonObject(mapOf("name" to JsonPrimitive("Z Unknown"), "setCode" to JsonPrimitive("TST"), "collectorNumber" to JsonPrimitive("5005"))))
        val catalogue = catalogue(rows)
        assertEquals(listOf("Z Colorless", "Z Green", "Z Green White", "Z White"), DeckStudioCatalogueSearch.cards(catalogue, allowedIdentity = listOf("G", "W"), limit = 80).map { it.name })
        assertEquals(listOf("Z Colorless"), DeckStudioCatalogueSearch.cards(catalogue, allowedIdentity = emptyList()).map { it.name })
        assertEquals(listOf("Z Colorless"), DeckStudioCatalogueSearch.cards(catalogue, allowedIdentity = listOf("G"), limit = 1).map { it.name })
        assertTrue(DeckStudioCatalogueSearch.cards(catalogue, allowedIdentity = listOf("X")).isEmpty())
        assertEquals(2, DeckStudioCatalogueSearch.cards(catalogue, "Green", allowedIdentity = listOf("G", "W")).size)
        assertTrue(DeckStudioCatalogueSearch.cards(catalogue, type = "Land", allowedIdentity = listOf("G", "W")).isEmpty())
    }

    // The resolver and link importer.

    private fun resolver(): OnDeviceDeckResolver = OnDeviceDeckResolver(PrintingIndex(("#\t${"c".repeat(64)}\t${"a".repeat(40)}\n" +
        "Sol Ring\tC21\t263\nForest\tM21\t274\nKardur, Doomscourge\tKHC\t10\nFire\tMH2\t290\n=\tFire // Ice\tFire\n").byteInputStream()))

    @Test fun resolverMapsSectionsAndRejectsASplitBetweenThem() {
        val resolver = resolver()
        val deck = DeckList("Test", DeckEntry("Kardur, Doomscourge", 1, "commander"), listOf(DeckEntry("Sol Ring", 1, "deck"), DeckEntry("Forest", 30, "main")))
        val resolved = resolver.resolve(deck)
        assertEquals(listOf("Kardur, Doomscourge"), (resolved as JsonObject)["commanders"]!!.let { (it as JsonArray).map { row -> (row as JsonObject)["name"].toString().trim('"') } })
        assertEquals("Fire", resolver.canonicalCardName("Fire // Ice"))
        assertEquals("Fire", resolver.canonicalCardName("Ice"))
        assertThrows<ResolutionError> { resolver.resolve(DeckList("Split", null, listOf(DeckEntry("Forest", 1, "deck"), DeckEntry("Forest", 1, "companions")))) }
        assertThrows<ResolutionError> { resolver.resolve(DeckList("Side", null, listOf(DeckEntry("Forest", 1, "sideboard")))) }
    }

    @Test fun linkImporterAcceptsOnlyPublicDeckLinks() {
        assertEquals(OnDeviceDeckLinkImporter.Provider.ARCHIDEKT, OnDeviceDeckLinkImporter.source("https://archidekt.com/decks/123456/my-deck").provider)
        assertEquals("https://api2.moxfield.com/v3/decks/all/abcdefghijklmnopqrstuv", OnDeviceDeckLinkImporter.source("https://www.moxfield.com/decks/abcdefghijklmnopqrstuv").endpoint)
        for (bad in listOf("http://archidekt.com/decks/1", "https://archidekt.com/decks/1?x=1", "https://user@archidekt.com/decks/1", "https://example.com/decks/1",
            "https://moxfield.com/decks/short")) assertThrows<OnDeviceDeckLinkImporter.ImportError> { OnDeviceDeckLinkImporter.source(bad) }
    }

    @Test fun moxfieldDecodeKeepsBoardsAndCanonicalNames() {
        val importer = OnDeviceDeckLinkImporter(resolver())
        val source = OnDeviceDeckLinkImporter.source("https://moxfield.com/decks/abcdefghijklmnopqrstuv")
        val json = """{"publicId":"abcdefghijklmnopqrstuv","name":"Mox","visibility":"public","boards":{
            "commanders":{"cards":{"a":{"quantity":1,"card":{"name":"Kardur, Doomscourge"}}}},
            "mainboard":{"cards":{"b":{"quantity":1,"card":{"name":"Sol Ring"}},"c":{"quantity":30,"card":{"name":"Forest"}}}},
            "sideboard":{"cards":{"d":{"quantity":1,"card":{"name":"Forest"}}}}}}"""
        assertThrows<OnDeviceDeckLinkImporter.ImportError> { importer.decode(json, source) }
        val deck = importer.decode(json, source, excludeSideboards = true)
        assertEquals("Kardur, Doomscourge", deck.commander?.cardName)
        assertEquals(31, deck.entries.sumOf { it.quantity })
        val review = importer.decode(json.replace("Sol Ring", "Brand New Card"), source, excludeSideboards = true, reviewOnly = true)
        assertTrue(review.entries.any { it.cardName == "Brand New Card" })
        assertEquals(listOf("Brand New Card"), importer.preview(review).unresolvedNames)
    }

    @Test fun roleClassifierReadsDirectEffectsAndSkipsConditionalOnes() {
        val ramp = DeckStudioRoleClassifier.classify("{T}: Add {G}.", listOf("ARTIFACT"))
        assertEquals(listOf(DeckStudioRole.RAMP), ramp.map { it.role })
        assertTrue(DeckStudioRoleClassifier.classify("{T}: Add {G}.", listOf("LAND")).isEmpty())
        assertEquals(listOf(DeckStudioRole.CARD_FLOW), DeckStudioRoleClassifier.classify("Draw two cards.", listOf("SORCERY")).map { it.role })
        assertTrue(DeckStudioRoleClassifier.classify("Whenever a creature dies, draw a card.", listOf("ENCHANTMENT")).isEmpty())
        assertTrue(DeckStudioRoleClassifier.classify("Choose one —\n• Destroy target creature.\n• Draw a card.", listOf("INSTANT")).isEmpty())
        val reviewed = DeckStudioRoleClassifier.classify("Draw two cards.", listOf("SORCERY"), reviewed = setOf(DeckStudioRole.TUTOR))
        assertEquals(listOf(DeckStudioRoleEvidence.Source.REVIEWED), reviewed.map { it.source })
    }

    @Test fun spellbookDeckNormalizesAndRejectsNumericNames() {
        val deck = SpellbookDeck(listOf(SpellbookDeck.Card("Sol Ring", 1), SpellbookDeck.Card("sol ring", 1), SpellbookDeck.Card("Forest", 3)),
            listOf(SpellbookDeck.Card("Kardur, Doomscourge", 1)))
        assertEquals(listOf(SpellbookDeck.Card("Forest", 3), SpellbookDeck.Card("Sol Ring", 2)), deck.main)
        assertEquals("""{"commanders":[{"card":"Kardur, Doomscourge","quantity":1}],"main":[{"card":"Forest","quantity":3},{"card":"Sol Ring","quantity":2}]}""", deck.encoded())
        assertThrows<SpellbookError> { SpellbookDeck(listOf(SpellbookDeck.Card("12345", 1)), listOf(SpellbookDeck.Card("Kardur, Doomscourge", 1))) }
        assertThrows<SpellbookError> { SpellbookDeck(listOf(SpellbookDeck.Card("Forest", 1)), emptyList()) }
        assertEquals(200, SpellbookAPI.nextOffset("https://backend.commanderspellbook.com/find-my-combos?limit=100&offset=200", 100))
        assertThrows<SpellbookError> { SpellbookAPI.nextOffset("https://evil.example/find-my-combos?limit=100&offset=200", 100) }
        assertThrows<SpellbookError> { SpellbookAPI.nextOffset("https://backend.commanderspellbook.com/find-my-combos?limit=100&offset=50", 100) }
    }
}
