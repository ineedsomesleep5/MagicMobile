package io.magicmobile.android.studio

import io.magicmobile.android.core.Catalogue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import kotlin.random.Random

/** Builder improvements (preflight, Quick Add, text edit, roles, bulk edits, sample hand, search syntax); mirrors DeckStudioPreflightTests.swift. */
class DeckStudioBuilderTest {
    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit): T {
        try { block() } catch (error: Throwable) { if (error is T) return error; throw AssertionError("Unexpected ${error::class.simpleName}: ${error.message}", error) }
        fail("Expected ${T::class.simpleName}"); throw IllegalStateException()
    }

    private var index = 0
    private fun card(name: String, typeLine: String, types: List<String>, identity: List<String>, mana: Int = 0, oracle: String? = null,
                     roles: List<String> = emptyList(), set: String = "TST") = JsonObject(buildMap {
        index += 1
        put("name", JsonPrimitive(name)); put("setCode", JsonPrimitive(set)); put("collectorNumber", JsonPrimitive("$index"))
        put("types", JsonArray(types.map(::JsonPrimitive))); put("typeLine", JsonPrimitive(typeLine))
        put("manaValue", JsonPrimitive(mana)); put("colorIdentity", JsonArray(identity.map(::JsonPrimitive))); put("setCodes", JsonArray(listOf(JsonPrimitive(set))))
        if (roles.isNotEmpty()) put("roles", JsonArray(roles.map(::JsonPrimitive)))
        oracle?.let { put("oracleText", JsonPrimitive(it)) }
    })

    private val catalogue: NativeDeckMetadataCatalogue by lazy {
        val rows = listOf(
            card("Atraxa, Praetors' Voice", "Legendary Creature — Phyrexian Angel Horror", listOf("CREATURE"), listOf("W", "U", "B", "G"), 4, "Flying, vigilance, deathtouch, lifelink"),
            card("Tymna the Weaver", "Legendary Creature — Human Cleric", listOf("CREATURE"), listOf("W"), 3, "Partner"),
            card("Thrasios, Triton Hero", "Legendary Creature — Merfolk Wizard", listOf("CREATURE"), listOf("G", "U"), 2, "Partner"),
            card("Teferi, Temporal Archmage", "Legendary Planeswalker — Teferi", listOf("PLANESWALKER"), listOf("U"), 6, "Teferi, Temporal Archmage can be your commander."),
            card("Sol Ring", "Artifact", listOf("ARTIFACT"), emptyList(), 1, "{T}: Add {C}{C}.", roles = listOf("ramp")),
            card("Sol Talisman", "Artifact", listOf("ARTIFACT"), emptyList(), 0, "Suspend 3—{1}"),
            card("Lightning Bolt", "Instant", listOf("INSTANT"), listOf("R"), 1, "Lightning Bolt deals 3 damage to any target."),
            card("Counterspell", "Instant", listOf("INSTANT"), listOf("U"), 2, "Counter target spell."),
            card("Swords to Plowshares", "Instant", listOf("INSTANT"), listOf("W"), 1, "Exile target creature. Its controller gains life equal to its power."),
            card("Mystic Remora", "Enchantment", listOf("ENCHANTMENT"), listOf("U"), 1, "Draw a card."),
            card("Relentless Rats", "Creature — Rat", listOf("CREATURE"), listOf("B"), 3, "A deck can have any number of cards named Relentless Rats."),
            card("Seven Dwarves", "Creature — Dwarf", listOf("CREATURE"), listOf("R"), 2, "A deck can have up to seven cards named Seven Dwarves."),
            card("Forest", "Basic Land — Forest", listOf("LAND"), listOf("G"), 0),
            card("Snow-Covered Island", "Basic Snow Land — Island", listOf("LAND"), listOf("U"), 0),
            card("Command Tower", "Land", listOf("LAND"), emptyList(), 0, "{T}: Add one mana of any color in your commander's color identity."),
            card("Rampant Growth", "Sorcery", listOf("SORCERY"), listOf("G"), 2,
                "Search your library for a basic land card, put it onto the battlefield tapped, then shuffle."),
            card("Grizzly Bears", "Creature — Bear", listOf("CREATURE"), listOf("G"), 2),
        )
        val header = JsonObject(mapOf("catalogueHash" to JsonPrimitive("c".repeat(64)), "upstreamCommit" to JsonPrimitive("a".repeat(40)),
            "sourceMetadataSHA256" to JsonPrimitive("b".repeat(64)), "nameAliases" to JsonObject(emptyMap())))
        NativeDeckMetadataCatalogue(Catalogue((listOf(header) + rows).joinToString("\n") { it.toString() }.byteInputStream()))
    }

    private fun row(name: String, quantity: Int = 1, section: String = "deck", primary: Boolean = false) =
        NativeDeckRow(cardName = name, quantity = quantity, section = section, isPrimaryCommander = primary)

    // Preflight

    @Test fun preflightCountsPlayingCardsAndFlagsEachRule() {
        val draft = NativeDeckDraft("Atraxa", listOf(row("Atraxa, Praetors' Voice", section = "commanders", primary = true), row("Sol Ring", 2),
            row("Lightning Bolt"), row("Forest", 30), row("Relentless Rats", 20), row("Seven Dwarves", 7), row("Mystery Card"),
            row("Lightning Bolt", section = "sideboard"), row("Unknown Maybe", section = "maybeboard"), row("Counterspell", 3, "maybeboard")))
        val check = DeckStudioPreflight(draft, catalogue::card)
        assertEquals(62, check.count)
        assertEquals(100, check.target)
        assertEquals(setOf("W", "U", "B", "G"), check.identity)
        val chips = check.chips.associateBy { it.kind }
        assertEquals(setOf(DeckStudioPreflight.Kind.OFF_COLOR, DeckStudioPreflight.Kind.DUPLICATE, DeckStudioPreflight.Kind.UNRESOLVED), chips.keys)
        // Seven Dwarves is red: off-color, but seven copies are within its own "up to seven" rule.
        assertEquals(setOf("Lightning Bolt", "Seven Dwarves"), chips.getValue(DeckStudioPreflight.Kind.OFF_COLOR).names)
        // Basics and "any number" cards are exempt; sideboard and maybeboard never count.
        assertEquals(setOf("Sol Ring"), chips.getValue(DeckStudioPreflight.Kind.DUPLICATE).names)
        assertEquals(setOf("Mystery Card"), chips.getValue(DeckStudioPreflight.Kind.UNRESOLVED).names)
        assertEquals("Off-color · 2 cards", chips.getValue(DeckStudioPreflight.Kind.OFF_COLOR).title)
        assertEquals("Duplicates · 1 card", chips.getValue(DeckStudioPreflight.Kind.DUPLICATE).title)
        assertEquals("Unresolved · 1 card", chips.getValue(DeckStudioPreflight.Kind.UNRESOLVED).title)
        assertEquals(listOf(DeckStudioPreflight.Kind.OFF_COLOR), check.issues(draft.rows[2]))
        assertTrue(check.issues(draft.rows[7]).isEmpty())
        assertEquals(listOf(draft.rows[1]), check.rows(DeckStudioPreflight.Kind.DUPLICATE, draft.rows))
        assertEquals("Quick check · XMage confirms when you play", DeckStudioPreflight.label)
    }

    @Test fun preflightCopyLimitsHonourAnyNumberAndUpToCards() {
        fun limit(name: String) = DeckStudioPreflight.copyLimit(name, catalogue.card(name))
        assertEquals(Int.MAX_VALUE, limit("Relentless Rats"))
        assertEquals(7, limit("Seven Dwarves"))
        assertEquals(Int.MAX_VALUE, limit("Forest"))
        assertEquals(Int.MAX_VALUE, limit("Snow-Covered Island"))
        assertEquals(Int.MAX_VALUE, DeckStudioPreflight.copyLimit("Wastes", null))
        assertEquals(1, limit("Sol Ring"))
        assertEquals(1, DeckStudioPreflight.copyLimit("Unknown", null))
        val eight = NativeDeckDraft("Dwarves", listOf(row("Tymna the Weaver", section = "commanders"), row("Seven Dwarves", 8)))
        assertTrue(DeckStudioPreflight(eight, catalogue::card).chips.any { it.kind == DeckStudioPreflight.Kind.DUPLICATE })
        // A card in both the command zone and the main deck is a duplicate as well.
        val twice = NativeDeckDraft("Twice", listOf(row("Tymna the Weaver", section = "commanders"), row("Tymna the Weaver")))
        assertEquals(setOf("Tymna the Weaver"), DeckStudioPreflight(twice, catalogue::card).chips.single().names)
    }

    @Test fun preflightTreatsPartnerAndUnknownCommandersConservatively() {
        // Partners use the union of their identities: Swords (W) and Counterspell (U) fit Tymna + Thrasios.
        val partners = NativeDeckDraft("Partners", listOf(row("Tymna the Weaver", section = "commanders", primary = true), row("Thrasios, Triton Hero", section = "commanders"),
            row("Swords to Plowshares"), row("Counterspell"), row("Rampant Growth"), row("Lightning Bolt")))
        val check = DeckStudioPreflight(partners, catalogue::card)
        assertEquals(setOf("W", "U", "G"), check.identity)
        assertEquals(listOf(DeckStudioPreflight.Chip(DeckStudioPreflight.Kind.OFF_COLOR, setOf("Lightning Bolt"))), check.chips)
        // An unknown commander means the identity is unknown: no off-color guess, only the unresolved card.
        val unknown = partners.copy(rows = partners.rows + row("Homebrew Commander", section = "commanders"))
        val guarded = DeckStudioPreflight(unknown, catalogue::card)
        assertNull(guarded.identity)
        assertEquals(listOf(DeckStudioPreflight.Kind.UNRESOLVED), guarded.chips.map { it.kind })
        // No commander at all: the chip says so and nothing is treated as off-color.
        val empty = DeckStudioPreflight(NativeDeckDraft("Empty", listOf(row("Lightning Bolt"))), catalogue::card)
        assertEquals(listOf(DeckStudioPreflight.Kind.MISSING_COMMANDER), empty.chips.map { it.kind })
        assertEquals("No commander", empty.chips.single().title)
        // Companions are playing cards: checked against the identity, but not counted toward 100.
        val companion = NativeDeckDraft("Companion", listOf(row("Tymna the Weaver", section = "commanders"), row("Lightning Bolt", section = "companions")))
        val companionCheck = DeckStudioPreflight(companion, catalogue::card)
        assertEquals(1, companionCheck.count)
        assertEquals(setOf("Lightning Bolt"), companionCheck.chips.single().names)
    }

    @Test fun commanderSearchOffersLegendaryCreaturesAndCanBeYourCommanderCards() {
        val names = DeckStudioCommanderSearch.candidates(catalogue, "").map { it.name }
        assertEquals(listOf("Atraxa, Praetors' Voice", "Teferi, Temporal Archmage", "Thrasios, Triton Hero", "Tymna the Weaver"), names)
        assertEquals(listOf("Teferi, Temporal Archmage"), DeckStudioCommanderSearch.candidates(catalogue, "tef").map { it.name })
        assertTrue(DeckStudioCommanderSearch.candidates(catalogue, "sol").isEmpty())
        assertEquals(1, DeckStudioCommanderSearch.candidates(catalogue, "", limit = 1).size)
    }

    @Test fun newDeckStartsWithCommanderAndTakesItsName() {
        val started = DeckStudioEditorOperations.startWithCommander(NativeDeckDraft(), "Atraxa, Praetors' Voice")
        assertEquals("Atraxa, Praetors' Voice", started.name)
        assertEquals(listOf(row("Atraxa, Praetors' Voice", section = "commanders", primary = true).copy(id = started.rows[0].id)), started.rows)
        val named = DeckStudioEditorOperations.startWithCommander(NativeDeckDraft("My Deck"), "Tymna the Weaver")
        assertEquals("My Deck", named.name)
    }

    // Quick Add

    @Test fun quickAddGrammar() {
        assertNull(DeckStudioQuickAdd.parse("  "))
        assertEquals(DeckStudioQuickAdd.Entry(1, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse("Sol Ring"))
        assertEquals(DeckStudioQuickAdd.Entry(2, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse("2 Sol Ring"))
        assertEquals(DeckStudioQuickAdd.Entry(2, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse("2x Sol Ring"))
        assertEquals(DeckStudioQuickAdd.Entry(3, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse(" 3X   Sol   Ring "))
        val decorated = DeckStudioQuickAdd.parse("1x Sol Ring (clb) [Ramp]")!!
        assertEquals(DeckStudioQuickAdd.Entry(1, "Sol Ring", listOf("(clb)", "[Ramp]")), decorated)
        assertEquals("Ignored (clb) [Ramp] · printings and tags aren't saved", decorated.note)
        assertEquals(DeckStudioQuickAdd.Entry(1, "Sol Ring", listOf("(CMM) 396")), DeckStudioQuickAdd.parse("1 Sol Ring (CMM) 396"))
        assertNull(DeckStudioQuickAdd.parse("Sol Ring")!!.note)
        assertThrows<DeckStudioQuickAdd.Invalid> { DeckStudioQuickAdd.parse("0 Sol Ring") }
        assertThrows<DeckStudioQuickAdd.Invalid> { DeckStudioQuickAdd.parse("2001 Sol Ring") }
        assertThrows<DeckStudioQuickAdd.Invalid> { DeckStudioQuickAdd.parse("2 [Ramp]") }
        // Without a following name, a number is just text.
        assertEquals(DeckStudioQuickAdd.Entry(1, "2x", emptyList()), DeckStudioQuickAdd.parse("2x"))
    }

    @Test fun quickAddSuggestsNamesAndResolvesExactOrTopMatch() {
        assertEquals(listOf("Sol Ring", "Sol Talisman"), DeckStudioQuickAdd.suggestions(catalogue, "2x sol").map { it.name })
        assertEquals(1, DeckStudioQuickAdd.suggestions(catalogue, "sol", limit = 1).size)
        // Names only: rules text mentioning "counter" does not suggest Swords to Plowshares.
        assertEquals(listOf("Counterspell"), DeckStudioQuickAdd.suggestions(catalogue, "counter").map { it.name })
        assertTrue(DeckStudioQuickAdd.suggestions(catalogue, "0 Sol Ring").isEmpty())
        assertEquals("Sol Ring", DeckStudioQuickAdd.resolve(catalogue, DeckStudioQuickAdd.parse("sol ring")!!))
        assertEquals("Sol Ring", DeckStudioQuickAdd.resolve(catalogue, DeckStudioQuickAdd.parse("so")!!))
        assertNull(DeckStudioQuickAdd.resolve(catalogue, DeckStudioQuickAdd.parse("zzz")!!))
    }

    @Test fun quickAddMergesIntoTheSameBoardRow() {
        val draft = NativeDeckDraft("Adds", listOf(row("Sol Ring"), row("Sol Ring", section = "considering")))
        val main = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "deck", 2)
        assertEquals(listOf(3, 1), main.rows.map { it.quantity })
        assertEquals(draft.rows[0].id, main.rows[0].id)
        // Considering is a maybeboard, so a maybeboard add merges into it.
        val maybe = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "maybeboard", 1)
        assertEquals(listOf(1, 2), maybe.rows.map { it.quantity })
        val appended = DeckStudioEditorOperations.addCopies(draft, "Counterspell", "maybeboard", 2)
        assertEquals(row("Counterspell", 2, "maybeboard").copy(id = appended.rows[2].id), appended.rows[2])
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "deck", 0) }
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.addCopies(NativeDeckDraft("Full", listOf(row("Forest", 2000))), "Forest", "deck", 1) }
    }

    // Edit as text

    @Test fun textEditReviewsAddedAndRemovedAndKeepsUnchangedRows() {
        val commander = row("Atraxa, Praetors' Voice", section = "commanders", primary = true)
        val sol = row("Sol Ring"); val forest = row("Forest", 30); val maybe = row("Counterspell", section = "considering"); val side = row("Lightning Bolt", section = "sideboard")
        val draft = NativeDeckDraft("Atraxa", listOf(commander, sol, forest, maybe, side))
        val text = DeckStudioTextEdit.text(draft)
        assertEquals("Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n1 Sol Ring\n30 Forest\n\nSideboard\n1 Lightning Bolt\n\nMaybeboard\n1 Counterspell\n", text)
        // The untouched export is no change at all, even for the "considering" row.
        val same = DeckStudioTextEdit.review(draft, text)
        assertTrue(same.isEmpty)
        assertEquals(draft, same.result)
        val edited = "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n32 Forest\n1 Swords to Plowshares\n\nMaybeboard\n1 Counterspell\n1 Sol Ring (clb) [Ramp]\n"
        val review = DeckStudioTextEdit.review(draft, edited)
        assertEquals(listOf(DeckStudioTextEdit.Change("Forest", "deck", 2), DeckStudioTextEdit.Change("Swords to Plowshares", "deck", 1),
            DeckStudioTextEdit.Change("Sol Ring", "maybeboard", 1)), review.added)
        assertEquals(listOf(DeckStudioTextEdit.Change("Sol Ring", "deck", 1), DeckStudioTextEdit.Change("Lightning Bolt", "sideboard", 1)), review.removed)
        assertEquals(1, review.ignoredLines)
        // Unchanged rows keep ID, section spelling and the primary mark; changed rows keep their ID.
        assertEquals(listOf(commander, forest.copy(quantity = 32), maybe), review.result.rows.take(3))
        assertEquals(listOf("Swords to Plowshares" to "deck", "Sol Ring" to "maybeboard"), review.result.rows.drop(3).map { it.cardName to it.section })
        assertEquals("Atraxa", review.result.name)
        assertEquals("Maybeboard", DeckStudioTextEdit.boardTitle("maybeboard"))
    }

    @Test fun textEditHandlesEmptyDraftsBlankTextAndCustomSections() {
        assertEquals("", DeckStudioTextEdit.text(NativeDeckDraft("New")))
        val created = DeckStudioTextEdit.review(NativeDeckDraft("New"), "2x Sol Ring\n")
        assertEquals(listOf(DeckStudioTextEdit.Change("Sol Ring", "deck", 2)), created.added)
        val draft = NativeDeckDraft("Two", listOf(row("Sol Ring"), row("Forest", 2)))
        val cleared = DeckStudioTextEdit.review(draft, "  \n")
        assertEquals(2, cleared.removed.size)
        assertTrue(cleared.result.rows.isEmpty())
        // Merged duplicate rows collapse into the first row only when the count changes.
        val split = NativeDeckDraft("Split", listOf(row("Forest", 2), row("Island"), row("Forest", 3)))
        assertEquals(split.rows, DeckStudioTextEdit.review(split, "5 Forest\n1 Island\n").result.rows)
        assertEquals(listOf(split.rows[0].copy(quantity = 6), split.rows[1]), DeckStudioTextEdit.review(split, "6 Forest\n1 Island\n").result.rows)
        assertThrows<DeckStudioTextExport.RequiresJSON> { DeckStudioTextEdit.text(NativeDeckDraft("Custom", listOf(row("Forest", section = "tokens")))) }
        assertThrows<DeckStudioTextExport.RequiresJSON> { DeckStudioTextEdit.review(NativeDeckDraft("Custom", listOf(row("Forest", section = "tokens"))), "1 Forest") }
        assertThrows<OnDeviceDeckEditing.TextImportError> { DeckStudioTextEdit.review(draft, "Sol Ring") }
    }

    // Group by Role

    @Test fun roleGroupsPlaceACardUnderEveryRoleAndReviewsWin() {
        val rows = listOf(row("Atraxa, Praetors' Voice", section = "commanders", primary = true), row("Sol Ring"), row("Rampant Growth"),
            row("Counterspell"), row("Mystic Remora"), row("Forest", 30), row("Mystery Card"), row("Swords to Plowshares", section = "maybeboard"))
        val groups = DeckStudioRoleGroups.groups(rows, catalogue::card, emptyMap())
        assertEquals(listOf("Ramp", "Draw / card flow", "Targeted interaction", "Other"), groups.keys.toList())
        assertEquals(listOf("Sol Ring", "Rampant Growth"), groups.getValue("Ramp").map { it.cardName })
        assertEquals(listOf("Forest", "Mystery Card"), groups.getValue("Other").map { it.cardName })
        // Multi-membership: a reviewed card appears under each role it was given, and the review replaces automatic hints.
        val reviewed = DeckStudioRoleGroups.groups(rows, catalogue::card, mapOf("Counterspell" to setOf(DeckStudioRole.INTERACTION, DeckStudioRole.PROTECTION),
            "Sol Ring" to emptySet()))
        assertEquals(listOf("Counterspell"), reviewed.getValue("Protection").map { it.cardName })
        assertEquals(listOf("Counterspell"), reviewed.getValue("Targeted interaction").map { it.cardName })
        assertEquals(listOf("Rampant Growth"), reviewed.getValue("Ramp").map { it.cardName })
        assertEquals(listOf("Sol Ring", "Forest", "Mystery Card"), reviewed.getValue("Other").map { it.cardName })
        val memberships = reviewed.values.sumOf { group -> group.count { it.cardName == "Counterspell" } }
        assertEquals(2, memberships)
        assertEquals(2, DeckStudioRoleGroups.uniqueCards(listOf(row("Forest", 30), row("Forest", 2), row("Island"))))
        assertEquals(DeckStudioRole.entries.map { it.title } + "Other", DeckStudioRoleGroups.order)
    }

    // Bulk actions

    @Test fun bulkActionsApplyToEverySelectedRowAtOnce() {
        val a = row("Sol Ring"); val b = row("Counterspell", 2); val c = row("Atraxa, Praetors' Voice", section = "commanders", primary = true)
        val draft = NativeDeckDraft("Bulk", listOf(a, b, c))
        val moved = DeckStudioEditorOperations.moveRows(draft, setOf(a.id, c.id), "maybeboard")
        assertEquals(listOf("maybeboard", "deck", "maybeboard"), moved.rows.map { it.section })
        assertFalse(moved.rows[2].isPrimaryCommander)
        assertEquals(listOf(4, 4, 1), DeckStudioEditorOperations.setQuantity(draft, setOf(a.id, b.id), 4).rows.map { it.quantity })
        assertEquals(listOf(c), DeckStudioEditorOperations.removeRows(draft, setOf(a.id, b.id)).rows)
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.removeRows(draft, setOf(a.id, java.util.UUID.randomUUID())) }
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.setQuantity(draft, setOf(a.id), 0) }
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.moveRows(draft, emptySet(), "deck") }
        // One whole-draft transaction is one undo step.
        val history = DeckStudioEditHistory(draft).edited { DeckStudioEditorOperations.removeRows(it, setOf(a.id, b.id)) }
        assertEquals(draft, history.undone().value)
        assertEquals("maybeboard", DeckStudioDraftPresentation.normalizedSection("Considering"))
    }

    // Sample hand

    @Test fun sampleHandDrawsSevenAndKeepsCommandersAndOtherBoardsOut() {
        val draft = NativeDeckDraft("Hand", listOf(row("Atraxa, Praetors' Voice", section = "commanders", primary = true), row("Forest", 10), row("Sol Ring"),
            row("Lightning Bolt", section = "sideboard"), row("Counterspell", section = "maybeboard"), row("Seven Dwarves", section = "companions")))
        val names = DeckStudioSampleHand.library(draft)
        assertEquals(11, names.size)
        assertEquals(setOf("Forest", "Sol Ring"), names.toSet())
        val hand = DeckStudioSampleHand.start(names, Random(7))
        assertEquals(7, hand.hand.size); assertEquals(4, hand.library.size)
        assertEquals(1, hand.turn); assertEquals(0, hand.toBottom)
        assertTrue(hand.canMulligan); assertTrue(hand.canDraw)
        assertEquals(hand, DeckStudioSampleHand.start(names, Random(7)))
        val drawn = hand.draw()
        assertEquals(8, drawn.hand.size); assertEquals(hand.library.first(), drawn.hand.last()); assertEquals(1, drawn.turn)
        assertFalse(drawn.canMulligan)
        val next = drawn.nextTurn()
        assertEquals(2, next.turn); assertEquals(9, next.hand.size)
        val small = DeckStudioSampleHand.start(listOf("Forest", "Island"), Random(1))
        assertEquals(2, small.hand.size); assertTrue(small.library.isEmpty()); assertFalse(small.canDraw)
        assertEquals(small, small.draw())
        assertTrue(DeckStudioSampleHand.library(NativeDeckDraft("Empty")).isEmpty())
    }

    @Test fun sampleHandLondonMulliganPutsOneCardOnTheBottomPerMulligan() {
        val names = (1..40).map { "Card $it" }
        val opening = DeckStudioSampleHand.start(names, Random(3))
        val first = opening.mulligan(Random(4))
        assertEquals(1, first.mulligans); assertEquals(7, first.hand.size); assertEquals(33, first.library.size); assertEquals(1, first.toBottom)
        assertFalse(first.canDraw)
        val second = first.mulligan(Random(5))
        assertEquals(2, second.mulligans); assertEquals(2, second.toBottom); assertEquals(40, second.size)
        val bottomed = second.putOnBottom(second.hand[0].id)
        assertEquals(6, bottomed.hand.size); assertEquals(second.hand[0], bottomed.library.last()); assertEquals(1, bottomed.toBottom)
        assertFalse(bottomed.canMulligan)
        // Cards not in hand, or extra cards once the count is met, are ignored.
        assertEquals(bottomed, bottomed.putOnBottom(-1))
        val kept = bottomed.putOnBottom(bottomed.hand[0].id)
        assertEquals(5, kept.hand.size); assertEquals(0, kept.toBottom); assertTrue(kept.canDraw)
        assertEquals(kept, kept.putOnBottom(kept.hand[0].id))
        assertEquals(40, kept.size)
        assertEquals(names.toSet(), (kept.hand + kept.library).map { it.name }.toSet())
        var limited = opening
        repeat(9) { limited = limited.mulligan(Random(it)) }
        assertEquals(7, limited.mulligans); assertEquals(7, limited.toBottom); assertFalse(limited.canMulligan)
    }

    // Search syntax

    @Test fun searchSyntaxParsesTypesTextManaValueAndIdentity() {
        val query = DeckStudioSearchSyntax.parse("""t:instant o:"target spell" mv<=2 mv>=1 id:uw counter""")
        assertEquals(DeckStudioSearchSyntax.Query("counter", listOf("instant"), listOf("target spell"), 1.0, 2.0, setOf("U", "W")), query)
        assertTrue(query.hasSyntax)
        assertFalse(DeckStudioSearchSyntax.parse("sol ring").hasSyntax)
        assertEquals(emptySet<String>(), DeckStudioSearchSyntax.parse("ID:C").identity)
        assertEquals(1.0, DeckStudioSearchSyntax.parse("mv<=3 MV<=1").maximumManaValue)
        for (bad in listOf("t:", "o:\"\"", "mv<=x", "mv>=-1", "id:wx", "id:wc")) {
            assertThrows<DeckStudioSearchSyntax.Invalid> { DeckStudioSearchSyntax.parse(bad) }
        }
    }

    @Test fun searchSyntaxFiltersBeforeTheCapAndKeepsPlainSearchUnchanged() {
        fun names(input: String, identity: List<String>? = null, type: String = "") = DeckStudioSearchSyntax.cards(catalogue, input, type, identity).map { it.name }
        assertEquals(listOf("Counterspell", "Lightning Bolt", "Swords to Plowshares"), names("t:instant"))
        assertEquals(listOf("Counterspell"), names("t:instant o:\"target spell\""))
        assertEquals(listOf("Lightning Bolt", "Swords to Plowshares"), names("t:instant mv<=1"))
        assertEquals(listOf("Counterspell"), names("t:instant mv>=2"))
        // id: means the card fits within those colours; colourless cards always fit.
        assertEquals(listOf("Counterspell", "Swords to Plowshares"), names("t:instant id:wu"))
        assertEquals(listOf("Command Tower", "Sol Ring", "Sol Talisman"), names("id:c"))
        assertEquals(listOf("Snow-Covered Island"), names("t:\"snow land\""))
        // The sheet's commander identity and type filters combine with the syntax.
        assertEquals(listOf("Counterspell"), names("mv<=2", identity = listOf("U"), type = "Instant"))
        assertEquals(listOf("Sol Ring"), names("ring t:artifact"))
        // Plain queries are the existing search, byte for byte.
        assertEquals(DeckStudioCatalogueSearch.cards(catalogue, "sol", allowedIdentity = listOf("G")).map { it.name }, names("sol", identity = listOf("G")))
        assertEquals(1, DeckStudioSearchSyntax.cards(catalogue, "t:instant", limit = 1).size)
    }
}
