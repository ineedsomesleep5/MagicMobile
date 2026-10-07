package io.magicmobile.android.studio

import io.magicmobile.android.core.CardArtChoices
import io.magicmobile.android.core.CardEntry
import io.magicmobile.android.core.CardPrinting
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.DeckTextImport
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The chosen printing of a deck row: validation, how it is saved, exported and imported again, and which printing a
 * card name shows. CardPrintingTests.swift and CardArtChoicesTests.swift follow the same cases, and both platforms
 * read parity/printing-cases.json.
 */
class CardPrintingTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val cases: JsonObject by lazy {
        Json.parseToJsonElement(File(repo, "apps/android/core/src/test/resources/parity/printing-cases.json").readText()).jsonObject
    }
    private fun JsonObject.text(key: String): String? = (get(key) as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content

    private val solRing = CardPrinting.of("CMM", "400")!!
    private fun printing(set: String, number: String) = CardPrinting.of(set, number)

    @Test fun setCodeAndCollectorNumberAreValidatedAndNormalized() {
        assertEquals("cmm", solRing.setCode)
        assertEquals("cmm/400", solRing.key)
        assertEquals("(CMM) 400", solRing.exportSuffix)
        assertEquals("CMM 400", solRing.label)
        for (number in listOf("107m", "★1", "A-12", "123†", "1")) assertNotNull(number, printing("plst", number))
        for ((set, number) in listOf("c" to "1", "toolong1" to "1", "cmm" to "", "cmm" to "1/2", "cm m" to "1", "cmm" to "1?x=1", "cmm" to "../1", "é" to "1",
            "cmm" to "1".repeat(17))) assertNull("$set $number", printing(set, number))
    }

    @Test fun deckListSuffixParsesOnlyWhenItNamesOnePrinting() {
        assertEquals(solRing, CardPrinting.parseSuffix("(CMM) 400"))
        assertEquals(solRing, CardPrinting.parseSuffix(" (cmm) 400 "))
        assertNull("a set code alone does not pick a printing", CardPrinting.parseSuffix("(clb)"))
        assertNull(CardPrinting.parseSuffix("CMM 400"))
        assertEquals("1234★", CardPrinting.parseSuffix("(SLD) 1234★")?.number)
    }

    @Test fun imageRouteRequestsExactlyThisPrintingAndEncodesThePath() {
        assertEquals("https://api.scryfall.com/cards/cmm/400?format=image&version=normal", solRing.imageUrl("normal"))
        assertEquals("https://api.scryfall.com/cards/cmm/400", solRing.cardUrl())
        val star = printing("sld", "★1")!!
        assertEquals("https://api.scryfall.com/cards/sld/%E2%98%851?format=image&version=large&face=back", star.imageUrl("large", back = true))
    }

    @Test fun savedEntryKeepsTheChoiceAsSetCodeAndCollectorNumber() {
        val entry = DeckEntry("Sol Ring", 1, "deck", solRing)
        val json = entry.json()
        assertEquals("cmm", (json["setCode"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertEquals("400", (json["collectorNumber"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertEquals(entry, DeckEntry.decode(json))
        // A row with no choice saves exactly the three fields it always had.
        assertEquals(setOf("cardName", "quantity", "section"), DeckEntry("Forest", 3, "deck").json().keys)
        val row = NativeDeckRow(cardName = "Sol Ring", printing = solRing)
        assertEquals(row, NativeDeckRow.decode(row.json()))
    }

    @Test fun decksSavedBeforeArtChoicesAndDamagedChoicesStillLoad() {
        val base = """{"cardName":"Forest","quantity":2,"section":"deck""""
        assertNull(DeckEntry.decode(Json.parseToJsonElement("$base}")).printing)
        for (damaged in listOf(""","setCode":"cmm"""", ""","setCode":"cmm","collectorNumber":"" """.trim(), ""","setCode":"x","collectorNumber":"1"""",
            ""","setCode":"cmm","collectorNumber":"../1"""", ""","collectorNumber":"1"""")) {
            val entry = DeckEntry.decode(Json.parseToJsonElement("$base$damaged}"))
            assertNull(damaged, entry.printing)
            assertEquals("Forest", entry.cardName)
        }
    }

    @Test fun entriesWithTheSameNameButDifferentArtStayDistinct() {
        val one = DeckEntry("Forest", 1, "deck", printing("unf", "1")); val two = DeckEntry("Forest", 1, "deck", printing("unf", "2"))
        assertNotEquals(one, two)
        assertNotEquals(one, DeckEntry("Forest", 1, "deck"))
    }

    @Test fun plainTextExportWritesChosenPrintingsAndImportRestoresThem() {
        val deck = DeckList("Art", DeckEntry("Atraxa, Praetors' Voice", 1, "commanders", printing("c16", "28")),
            listOf(DeckEntry("Sol Ring", 1, "deck", solRing), DeckEntry("Forest", 20, "deck"),
                DeckEntry("Swords to Plowshares", 1, "sideboard", printing("sld", "★12"))))
        val text = DeckStudioTextExport.text(deck)
        assertEquals("Commander\n1 Atraxa, Praetors' Voice (C16) 28\n\nDeck\n1 Sol Ring (CMM) 400\n20 Forest\n\nSideboard\n1 Swords to Plowshares (SLD) ★12\n", text)
        val back = OnDeviceDeckEditing.importText(text, "Art").deck
        assertEquals(printing("c16", "28"), back.commander?.printing)
        assertEquals(listOf(solRing, null, printing("sld", "★12")), back.entries.map { it.printing })
        assertEquals(listOf("Sol Ring", "Forest", "Swords to Plowshares"), back.entries.map { it.cardName })
        assertEquals(listOf(1, 20, 1), back.entries.map { it.quantity })
    }

    @Test fun providerExportsKeepTheirPrintingsWhileTheReviewStillListsTheSuffix() {
        val result = OnDeviceDeckEditing.importText("""
            1x Sol Ring (cmm) 400 [Ramp]
            1 Arcane Signet (CMM) 384 *F*
            2 Rampant Growth (9ED) 263
            1x Emmara, Soul of the Accord (grn) [Maybeboard]
        """.trimIndent(), "Providers")
        assertEquals(listOf(solRing, printing("cmm", "384"), printing("9ed", "263"), null), result.deck.entries.map { it.printing })
        assertTrue(result.annotations.contains(OnDeviceDeckEditing.TextAnnotation(3, "(9ED) 263")))
        assertTrue(result.annotations.contains(OnDeviceDeckEditing.TextAnnotation(4, "(grn)")))
    }

    @Test fun nativeJsonExportRoundTripsPrintings() {
        val deck = DeckList("Json", null, listOf(DeckEntry("Sol Ring", 1, "deck", solRing)))
        assertEquals(deck, OnDeviceDeckEditing.importJSON(OnDeviceDeckEditing.exportJSON(deck)))
    }

    @Test fun draftRowsCarryTheChoiceThroughEditingSavingAndRecovery() {
        var draft = NativeDeckDraft.of(DeckList("Rows", DeckEntry("Atraxa", 1, "commanders", solRing), listOf(DeckEntry("Sol Ring", 1, "deck", solRing))))
        assertEquals(listOf(solRing, solRing), draft.rows.map { it.printing })
        assertEquals(solRing, draft.deck().entries.first().printing)
        assertEquals(solRing, draft.deck().commander?.printing)
        assertEquals(draft, NativeDeckDraft.decode(draft.json()))
        // More copies of the same card keep its art.
        draft = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "deck", 2)
        assertEquals(3, draft.rows.last().quantity)
        assertEquals(solRing, draft.rows.last().printing)
        // A draft from before art choices still decodes.
        val old = Json.parseToJsonElement("""{"name":"Old","rows":[{"id":"${java.util.UUID.randomUUID().toString().uppercase()}","cardName":"Forest","quantity":1,"section":"deck","isPrimaryCommander":false}]}""")
        assertNull(NativeDeckDraft.decode(old).rows.first().printing)
    }

    @Test fun libraryStorageKeepsThePrintingAndPlainDecksSaveAsBefore() {
        val deck = DeckList("Stored", DeckEntry("Atraxa", 1, "commanders", printing("c16", "28")), listOf(DeckEntry("Sol Ring", 1, "deck", solRing), DeckEntry("Forest", 9, "deck")))
        val stored = deck.storedDeck()
        assertEquals(listOf(printing("c16", "28"), solRing, null), stored.entries.map { it.printing })
        assertEquals(deck, DeckList.fromStored(Deck.decode(stored.json())))
        val plain = Deck("Plain", listOf(CardEntry("Forest", 3))).json()
        @Suppress("UNCHECKED_CAST") val rows = plain["entries"] as List<Map<String, Any?>>
        assertEquals(setOf("name", "quantity", "section"), rows.single().keys)
    }

    @Test fun deckJsonImporterAcceptsAChosenPrintingAndRejectsAHalfPair() {
        val text = """{"name":"Ios","commander":null,"entries":[{"cardName":"Sol Ring","quantity":1,"section":"deck","setCode":"cmm","collectorNumber":"400"}]}"""
        assertEquals(solRing, DeckTextImport.preview("Ios", text).deck.entries.single().printing)
        val half = text.replace(",\"collectorNumber\":\"400\"", "")
        assertTrue(runCatching { DeckTextImport.preview("Ios", half) }.isFailure)
        // What it exports it reads back, printing included.
        val exported = DeckTextImport.exportJSON(Deck("Out", listOf(CardEntry("Sol Ring", 1, "deck", solRing))))
        assertEquals(solRing, DeckTextImport.preview("Out", exported).deck.entries.single().printing)
    }

    @Test fun replacingACardClearsTheChoiceThatBelongedToTheOldOne() {
        val draft = NativeDeckDraft.of(DeckList("Replace", null, listOf(DeckEntry("Sol Ring", 1, "deck", solRing))))
        val replaced = DeckStudioEditorOperations.replaceCard(draft, draft.rows[0].id, "Arcane Signet")
        assertEquals("Arcane Signet", replaced.rows[0].cardName)
        assertNull(replaced.rows[0].printing)
        // Promoting a main-deck copy to commander keeps its art on the commander.
        val promoted = DeckStudioEditorOperations.replacePrimaryCommander(
            NativeDeckDraft.of(DeckList("P", DeckEntry("Old Boss", 1, "commanders"), listOf(DeckEntry("Atraxa", 2, "deck", solRing)))), "Atraxa", keepOld = false)
        assertEquals(solRing, promoted.rows.first { it.isPrimaryCommander }.printing)
    }

    @Test fun textEditReportsAChangedPrintingAsAnArtChange() {
        val draft = NativeDeckDraft.of(DeckList("Diff", null, listOf(DeckEntry("Sol Ring", 1, "deck", solRing), DeckEntry("Forest", 2, "deck"))))
        val exported = DeckStudioTextExport.text(draft.deck())
        assertTrue(DeckStudioTextDiff.between(draft, DeckStudioTextDiff.draft(exported, draft).first).isEmpty)
        val edited = exported.replace("Sol Ring (CMM) 400", "Sol Ring (C21) 263").replace("2 Forest", "2 Forest (UNF) 5")
        val result = DeckStudioTextDiff.draft(edited, draft).first
        val diff = DeckStudioTextDiff.between(draft, result)
        assertFalse(diff.isEmpty)
        assertTrue(diff.added.isEmpty() && diff.removed.isEmpty())
        assertEquals(listOf("Forest · default art → UNF 5", "Sol Ring · CMM 400 → C21 263"), diff.art.map { it.label })
        assertEquals(draft.rows.map { it.id }, result.rows.map { it.id })
        assertEquals(listOf(printing("c21", "263"), printing("unf", "5")), result.rows.map { it.printing })
        val cleared = DeckStudioTextDiff.draft(exported.replace(" (CMM) 400", ""), draft).first
        assertEquals(listOf("Sol Ring · CMM 400 → default art"), DeckStudioTextDiff.between(draft, cleared).art.map { it.label })
    }

    @Test fun sharedPrintingCasesMatchIOS() {
        val valid = cases["valid"]!!.jsonArray
        assertTrue(valid.isNotEmpty())
        for (item in valid.map { it.jsonObject }) {
            val printing = CardPrinting.of(item.text("set")!!, item.text("number")!!)
            assertNotNull("$item", printing)
            assertEquals("$item", item.text("key"), printing!!.key)
            assertEquals("$item", item.text("export"), printing.exportSuffix)
            assertEquals("$item", item.text("label"), printing.label)
        }
        val invalid = cases["invalid"]!!.jsonArray
        assertTrue(invalid.isNotEmpty())
        for (pair in invalid.map { it.jsonArray }) assertNull("$pair", CardPrinting.of(pair[0].jsonPrimitive.content, pair[1].jsonPrimitive.content))
        for (item in cases["suffixes"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(item.text("suffix"), item.text("key"), CardPrinting.parseSuffix(item.text("suffix")!!)?.key)
        }
        for (item in cases["imageUrls"]!!.jsonArray.map { it.jsonObject }) {
            val printing = CardPrinting.of(item.text("set")!!, item.text("number")!!)!!
            assertEquals(item.text("url"), printing.imageUrl(item.text("version")!!, back = item["back"]!!.jsonPrimitive.boolean))
        }
    }

    @Test fun sharedDeckListLinesAndExportsMatchIOS() {
        for (item in cases["textLines"]!!.jsonArray.map { it.jsonObject }) {
            val text = item.text("text")!!
            val entry = OnDeviceDeckEditing.importText(text, "Lines").deck.entries.first()
            assertEquals(text, item.text("name"), entry.cardName)
            assertEquals(text, item["quantity"]!!.jsonPrimitive.int, entry.quantity)
            assertEquals(text, item.text("key"), entry.printing?.key)
        }
        for (item in cases["exports"]!!.jsonArray.map { it.jsonObject }) {
            val set = item.text("set"); val number = item.text("number")
            val printing = if (set != null && number != null) CardPrinting.of(set, number) else null
            val deck = DeckList("Export", null, listOf(DeckEntry(item.text("name")!!, item["quantity"]!!.jsonPrimitive.int, "deck", printing)))
            assertEquals("Deck\n${item.text("line")}\n", DeckStudioTextExport.text(deck))
        }
    }

    // CardArtChoicesTests.swift: which printing a name shows.

    private fun deck(vararg rows: Pair<String, CardPrinting?>, commander: Pair<String, CardPrinting?>? = null) =
        DeckList("Test", commander?.let { DeckEntry(it.first, 1, "commanders", it.second) }, rows.map { DeckEntry(it.first, 1, "deck", it.second) })

    @Test fun aPlayingDecksChoiceWinsAndItsDefaultArtIsNeverReplacedByAnotherDecks() {
        val c21 = printing("c21", "263")!!
        val choices = CardArtChoices()
        choices.update(listOf(CardArtChoices.SavedDeck("a", deck("Sol Ring" to c21, "Arcane Signet" to c21), 200),
            CardArtChoices.SavedDeck("b", deck("Sol Ring" to solRing, "Forest" to null), 100)), "b")
        assertEquals(solRing, choices.printing("Sol Ring"))
        assertEquals(c21, choices.printing("Arcane Signet"))
        choices.update(listOf(CardArtChoices.SavedDeck("a", deck("Sol Ring" to c21), 200), CardArtChoices.SavedDeck("b", deck("Sol Ring" to null), 100)), "b")
        assertNull("the playing deck holds Sol Ring with default art", choices.printing("Sol Ring"))
    }

    @Test fun withoutAPlayingSavedDeckTheMostRecentlySavedDeckWinsAndNamesIgnoreCase() {
        val choices = CardArtChoices()
        choices.update(listOf(CardArtChoices.SavedDeck("old", deck("Sol Ring" to printing("c21", "263")), 1),
            CardArtChoices.SavedDeck("new", deck(commander = "Sol Ring" to solRing), 2)), "precon:x")
        assertEquals(solRing, choices.printing("sol ring "))
        assertNull(choices.printing("Forest"))
        assertFalse(choices.isEmpty)
        choices.update(emptyList(), null)
        assertTrue(choices.isEmpty)
    }

    @Test fun aReverseFaceShowsTheBackOfItsFrontsChosenPrintingAndChangesAreAnnouncedOnlyWhenTheyMatter() {
        val isd = printing("isd", "51")!!
        val choices = CardArtChoices()
        var announced = 0
        choices.addListener { announced++ }
        val saved = CardArtChoices.SavedDeck("a", deck("Delver of Secrets" to isd), 1)
        choices.update(listOf(saved), "a")
        choices.update(listOf(saved), "a")
        assertEquals(1, announced)
        assertNull("reverse faces are unknown until the catalogue names them", choices.selection("Insectile Aberration"))
        assertTrue(choices.needsReverseFaces)
        choices.setReverseFaces(mapOf("Insectile Aberration" to "Delver of Secrets"))
        assertEquals(CardArtChoices.Selection(isd, false), choices.selection("Delver of Secrets"))
        assertEquals(CardArtChoices.Selection(isd, true), choices.selection("Insectile Aberration"))
        assertFalse(choices.needsReverseFaces)
    }

    @Test fun scryfallPrintingsRequestAndReadingAreExactAndBounded() {
        assertEquals("https://api.scryfall.com/cards/search?q=%21%22Sol+Ring%22&unique=prints&order=released&dir=desc&page=2", DeckStudioPrintings.requestUrl("Sol Ring", 2))
        assertNull(DeckStudioPrintings.requestUrl("Ach! \"Hans\"", 1))
        assertNull(DeckStudioPrintings.requestUrl("Sol Ring", 11))
        assertFalse(DeckStudioPrintings.isSearchable("a\\b"))
        val json = """{"object":"list","has_more":true,"data":[
            {"id":"1","name":"Sol Ring","set":"cmm","set_name":"Commander Masters","collector_number":"400","released_at":"2023-08-04","image_uris":{"small":"https://cards.scryfall.io/small/front/a.jpg"}},
            {"id":"2","name":"Delver","set":"isd","set_name":"Innistrad","collector_number":"51","released_at":"2011-09-30",
             "card_faces":[{"image_uris":{"small":"https://cards.scryfall.io/small/front/b.jpg"}},{"image_uris":{"small":"https://cards.scryfall.io/small/back/b.jpg"}}]},
            {"id":"3","name":"Evil","set":"zzz","set_name":"Evil","collector_number":"1/2","image_uris":{"small":"https://evil.test/a.jpg"}}]}"""
        val page = DeckStudioPrintings.parse(json, 1)
        assertTrue(page.hasMore)
        assertEquals(listOf("cmm/400", "isd/51", null), page.printings.map { it.printing?.key })
        assertEquals("Commander Masters · 2023", page.printings[0].caption)
        assertEquals("https://cards.scryfall.io/small/front/b.jpg", page.printings[1].thumbnail)
        assertNull("only Scryfall's image host is trusted", page.printings[2].thumbnail)
        assertTrue(runCatching { DeckStudioPrintings.parse("""{"object":"error"}""", 1) }.isFailure)
    }
}
