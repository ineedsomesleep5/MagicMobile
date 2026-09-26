package io.magicmobile.android.studio

import io.magicmobile.android.core.CardInfo
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
import java.util.UUID
import kotlin.random.Random

/**
 * Builder improvements: ports of DeckStudioPreflightTests.swift and the builder section of
 * DeckStudioCoreTests.swift, so both phones share the same rules and strings.
 */
class DeckStudioBuilderTest {
    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit): T {
        try { block() } catch (error: Throwable) { if (error is T) return error; throw AssertionError("Unexpected ${error::class.simpleName}: ${error.message}", error) }
        fail("Expected ${T::class.simpleName}"); throw IllegalStateException()
    }

    private fun row(name: String, quantity: Int = 1, section: String = "deck", primary: Boolean = false) =
        NativeDeckRow(cardName = name, quantity = quantity, section = section, isPrimaryCommander = primary)

    // DeckStudioPreflightTests.swift

    private fun facts(name: String, typeLine: String, oracle: String?, identity: List<String>?) =
        CardInfo(name, "TST", "1", typeLine, oracle, null, identity)
    private val facts = listOf(
        facts("Atraxa, Praetors' Voice", "Legendary Creature — Phyrexian Angel Horror", "Flying", listOf("W", "U", "B", "G")),
        facts("Kraum, Ludevic's Opus", "Legendary Creature — Zombie Horror", "Partner", listOf("U", "R")),
        facts("Tymna the Weaver", "Legendary Creature — Human Cleric", "Partner", listOf("W", "B")),
        facts("Sol Ring", "Artifact", "{T}: Add {C}{C}.", emptyList()),
        facts("Lightning Bolt", "Instant", "Lightning Bolt deals 3 damage to any target.", listOf("R")),
        facts("Forest", "Basic Land — Forest", "{T}: Add {G}.", listOf("G")),
        facts("Snow-Covered Island", "Basic Snow Land — Island", "{T}: Add {U}.", listOf("U")),
        facts("Relentless Rats", "Creature — Rat", "A deck can have any number of cards named Relentless Rats.", listOf("B")),
        facts("Seven Dwarves", "Creature — Dwarf", "A deck can have up to seven cards named Seven Dwarves.", listOf("R")),
        facts("Nazgûl", "Creature — Wraith Knight", "Deathtouch\nA deck can have up to nine cards named Nazgûl.", listOf("B")),
        facts("Mystery Card", "Artifact", null, null),
    ).associateBy { it.name }

    private fun check(rows: List<NativeDeckRow>, resolves: ((String) -> Boolean)? = { true }) =
        DeckStudioPreflight(NativeDeckDraft("Test", rows), { facts[it] }, resolves)

    @Test fun countsMainAndCommandersAgainstOneHundred() {
        val result = check(listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true), row("Forest", 96),
            row("Sol Ring", 1, "sideboard"), row("Lightning Bolt", 1, "maybeboard"), row("Sol Ring", 1, "considering")))
        assertEquals(97, result.count)
        assertFalse(result.missingCommander)
        assertEquals(0, result.issueCount)
        assertEquals("3 cards to go · No issues found", result.summary)
        assertEquals("1 card over · No issues found", check(listOf(row("Atraxa, Praetors' Voice", 1, "commanders"), row("Forest", 100))).summary)
        assertEquals("No issues found", check(listOf(row("Atraxa, Praetors' Voice", 1, "commanders"), row("Forest", 99))).summary)
    }

    @Test fun missingCommanderIsOneIssueAndSkipsIdentity() {
        val result = check(listOf(row("Lightning Bolt"), row("Forest", 2)))
        assertTrue(result.missingCommander)
        assertNull(result.commanderIdentity)
        assertTrue("No commander means no identity to judge", result.rows(DeckStudioPreflight.Issue.OFF_IDENTITY).isEmpty())
        assertEquals(listOf(DeckStudioPreflight.Issue.MISSING_COMMANDER), result.activeIssues)
        assertEquals("Missing commander", result.chipTitle(DeckStudioPreflight.Issue.MISSING_COMMANDER))
        assertEquals("97 cards to go · 1 issue", result.summary)
    }

    @Test fun offIdentityRowsUseTheCommanderIdentityAndIgnoreOtherBoards() {
        val bolt = row("Lightning Bolt"); val companionBolt = row("Lightning Bolt", 1, "companion"); val maybe = row("Lightning Bolt", 1, "maybeboard")
        val result = check(listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true), bolt, companionBolt, maybe, row("Sol Ring"), row("Forest")))
        assertEquals(setOf("W", "U", "B", "G"), result.commanderIdentity)
        assertEquals(setOf(bolt.id, companionBolt.id), result.rows(DeckStudioPreflight.Issue.OFF_IDENTITY))
        assertEquals(listOf(DeckStudioPreflight.Issue.OFF_IDENTITY, DeckStudioPreflight.Issue.DUPLICATE), result.issues(bolt.id))
        assertTrue("Maybeboard cards stay out of play", result.issues(maybe.id).isEmpty())
        assertEquals("Off-color · 2", result.chipTitle(DeckStudioPreflight.Issue.OFF_IDENTITY))
    }

    @Test fun partnerCommandersAreTreatedConservatively() {
        // Two commanders: identity is their union, and the pairing itself is XMage's call.
        val bolt = row("Lightning Bolt")
        val result = check(listOf(row("Kraum, Ludevic's Opus", 1, "commanders", primary = true), row("Tymna the Weaver", 1, "commanders"), bolt))
        assertEquals(setOf("U", "R", "W", "B"), result.commanderIdentity)
        assertTrue(result.rows(DeckStudioPreflight.Issue.OFF_IDENTITY).isEmpty())
        assertEquals(0, result.issueCount)
        // A commander with unknown identity switches the identity check off instead of guessing.
        val unknown = check(listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true), row("Mystery Card", 1, "commanders"), bolt))
        assertNull(unknown.commanderIdentity)
        assertTrue(unknown.rows(DeckStudioPreflight.Issue.OFF_IDENTITY).isEmpty())
    }

    @Test fun duplicatesHonourBasicsAndAnyNumberAndUpToLimits() {
        val solA = row("Sol Ring"); val solB = row("Sol Ring", 1, "maybeboard"); val solC = row("Sol Ring", 1, "commanders")
        val dwarves = row("Seven Dwarves", 7); val moreDwarves = row("Seven Dwarves", 8)
        val base = listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true))
        val ok = check(base + listOf(solA, solB, row("Forest", 30), row("Snow-Covered Island", 5), row("Relentless Rats", 40), dwarves, row("Nazgûl", 9)))
        assertTrue("Basics, 'any number' and 'up to seven/nine' cards stay within their limits; maybeboard copies do not count",
            ok.rows(DeckStudioPreflight.Issue.DUPLICATE).isEmpty())
        assertEquals(setOf(moreDwarves.id), check(base + moreDwarves).rows(DeckStudioPreflight.Issue.DUPLICATE))
        assertEquals(1, check(base + row("Nazgûl", 10)).issueCount)
        // A card in the command zone and the main deck is a duplicate across both rows.
        assertEquals(setOf(solA.id, solC.id), check(base + listOf(solA, solC)).rows(DeckStudioPreflight.Issue.DUPLICATE))
        assertEquals("Duplicates · 1", check(base + row("Sol Ring", 2)).chipTitle(DeckStudioPreflight.Issue.DUPLICATE))
        assertNull(DeckStudioPreflight.copyLimit(facts.getValue("Relentless Rats")))
        assertEquals(7, DeckStudioPreflight.copyLimit(facts.getValue("Seven Dwarves")))
        assertEquals(9, DeckStudioPreflight.copyLimit(facts.getValue("Nazgûl")))
        assertNull(DeckStudioPreflight.copyLimit(facts.getValue("Snow-Covered Island")))
        assertEquals(1, DeckStudioPreflight.copyLimit(facts.getValue("Sol Ring")))
    }

    @Test fun unresolvedPlayingRowsOnlyWhenACatalogueIsLoaded() {
        val unknown = row("Not A Real Card"); val maybeUnknown = row("Also Fake", 1, "maybeboard")
        val base = listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true))
        val resolved = check(base + listOf(unknown, maybeUnknown), resolves = { it in facts })
        assertEquals(setOf(unknown.id), resolved.rows(DeckStudioPreflight.Issue.UNRESOLVED))
        assertEquals(listOf(DeckStudioPreflight.Issue.UNRESOLVED), resolved.issues(unknown.id))
        assertEquals("Unresolved · 1", resolved.chipTitle(DeckStudioPreflight.Issue.UNRESOLVED))
        assertTrue("No catalogue yet: nothing is judged unresolved", check(base + unknown, resolves = null).rows(DeckStudioPreflight.Issue.UNRESOLVED).isEmpty())
    }

    @Test fun issueCountTextIsSingularOrPlural() {
        assertEquals("1 issue", DeckStudioPreflight.issueCountText(1))
        assertEquals("2 issues", DeckStudioPreflight.issueCountText(2))
        assertEquals("0 issues", DeckStudioPreflight.issueCountText(0))
        assertEquals("Quick check · XMage confirms when you play", DeckStudioPreflight.caption)
        assertEquals("97 cards to go · 2 issues", check(listOf(row("Lightning Bolt"), row("Sol Ring", 2))).summary)
    }

    // DeckStudioCoreTests.swift, builder improvements

    private var collector = 0
    private fun entry(name: String, types: List<String>, typeLine: String, oracle: String, mana: Int, identity: List<String>, set: String,
                      roles: List<String> = emptyList()) = JsonObject(buildMap {
        collector += 1
        put("name", JsonPrimitive(name)); put("setCode", JsonPrimitive(set)); put("collectorNumber", JsonPrimitive("$collector"))
        put("types", JsonArray(types.map(::JsonPrimitive))); put("typeLine", JsonPrimitive(typeLine)); put("oracleText", JsonPrimitive(oracle))
        put("manaValue", JsonPrimitive(mana)); put("colorIdentity", JsonArray(identity.map(::JsonPrimitive))); put("setCodes", JsonArray(listOf(JsonPrimitive(set))))
        if (roles.isNotEmpty()) put("roles", JsonArray(roles.map(::JsonPrimitive)))
    })

    private val catalogue: NativeDeckMetadataCatalogue by lazy {
        val rows = listOf(
            entry("Atraxa, Praetors' Voice", listOf("CREATURE"), "Legendary Creature — Phyrexian Angel Horror", "Flying, vigilance, deathtouch, lifelink", 4, listOf("W", "U", "B", "G"), "C16"),
            entry("Daretti, Scrap Savant", listOf("PLANESWALKER"), "Legendary Planeswalker — Daretti", "Daretti, Scrap Savant can be your commander.", 4, listOf("R"), "C14"),
            entry("Isamaru, Hound of Konda", listOf("CREATURE"), "Legendary Creature — Dog", "", 1, listOf("W"), "CHK"),
            entry("Sol Ring", listOf("ARTIFACT"), "Artifact", "{T}: Add {C}{C}.", 1, emptyList(), "C21", listOf("ramp")),
            entry("Solemn Simulacrum", listOf("ARTIFACT", "CREATURE"), "Artifact Creature — Golem",
                "When this creature enters, you may search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.\nWhen this creature dies, you may draw a card.",
                4, emptyList(), "C21", listOf("ramp", "cardFlow")),
            entry("Counterspell", listOf("INSTANT"), "Instant", "Counter target spell.", 2, listOf("U"), "C21"),
            entry("Lightning Bolt", listOf("INSTANT"), "Instant", "Lightning Bolt deals 3 damage to any target.", 1, listOf("R"), "M10"),
            entry("Grizzly Bears", listOf("CREATURE"), "Creature — Bear", "", 2, listOf("G"), "M10"),
            entry("Forest", listOf("LAND"), "Basic Land — Forest", "{T}: Add {G}.", 0, listOf("G"), "M10"),
            entry("Soldevi Sage", listOf("CREATURE"), "Creature — Human Wizard", "{T}, Sacrifice two lands: Draw three cards, then discard one of them.", 3, listOf("U"), "ALL"),
            entry("Séance", listOf("ENCHANTMENT"), "Enchantment", "At the beginning of each upkeep, you may exile target creature card from your graveyard.", 4, listOf("W"), "SHM"),
        )
        val header = JsonObject(mapOf("catalogueHash" to JsonPrimitive("c".repeat(64)), "upstreamCommit" to JsonPrimitive("a".repeat(40)),
            "sourceMetadataSHA256" to JsonPrimitive("b".repeat(64)), "nameAliases" to JsonObject(emptyMap())))
        NativeDeckMetadataCatalogue(Catalogue((listOf(header) + rows).joinToString("\n") { it.toString() }.byteInputStream()))
    }

    @Test fun catalogueBackedPreflightUsesMetadataWhenNoResolverIsLoaded() {
        val draft = NativeDeckDraft("Atraxa", listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true), row("Sol Ring"), row("Lightning Bolt"), row("Unknown Thing")))
        val result = DeckStudioPreflight(draft, catalogue, null)
        assertEquals(setOf("W", "U", "B", "G"), result.commanderIdentity)
        assertEquals(1, result.rows(DeckStudioPreflight.Issue.OFF_IDENTITY).size)
        assertEquals(1, result.rows(DeckStudioPreflight.Issue.UNRESOLVED).size)
        assertEquals(0, DeckStudioPreflight(NativeDeckDraft("Atraxa", listOf(row("Atraxa, Praetors' Voice", 1, "commanders"), row("Unknown Thing"))), null, null).issueCount)
    }

    @Test fun quickAddGrammarAcceptsCountsAndIgnoresSetsAndTags() {
        assertEquals(DeckStudioQuickAdd(1, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse("Sol Ring"))
        assertEquals(DeckStudioQuickAdd(2, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse("  2 Sol Ring "))
        assertEquals(DeckStudioQuickAdd(2, "Sol Ring", emptyList()), DeckStudioQuickAdd.parse("2x Sol Ring"))
        assertEquals(DeckStudioQuickAdd(12, "Forest", emptyList()), DeckStudioQuickAdd.parse("12X Forest"))
        val decorated = DeckStudioQuickAdd.parse("1x Sol Ring (clb) 123 [Ramp]")
        assertEquals(DeckStudioQuickAdd(1, "Sol Ring", listOf("(clb) 123", "[Ramp]")), decorated)
        assertEquals("Ignored (clb) 123 [Ramp] · sets and tags aren't saved", decorated?.note)
        assertEquals(listOf("(C21)"), DeckStudioQuickAdd.parse("Sol Ring (C21)")?.ignored)
        assertNull(DeckStudioQuickAdd.parse("Sol Ring")?.note)
        // Names with ordinary parentheses or punctuation survive.
        assertEquals("B.F.M. (Big Furry Monster)", DeckStudioQuickAdd.parse("B.F.M. (Big Furry Monster)")?.name)
        assertEquals("Circle of Protection: Red", DeckStudioQuickAdd.parse("Circle of Protection: Red")?.name)
        // An exact card name that starts with a number beats the count.
        assertEquals("1996 World Champion", DeckStudioQuickAdd.parse("1996 World Champion") { it == "1996 World Champion" }?.name)
        assertEquals(1996, DeckStudioQuickAdd.parse("1996 World Champion")?.quantity)
        for (invalid in listOf("", "   ", "2x", "0 Sol Ring", "2001 Forest", "[Ramp]")) assertNull(invalid, DeckStudioQuickAdd.parse(invalid))
    }

    @Test fun quickAddAndCommanderFirstEditsAreSingleDraftChanges() {
        var draft = DeckStudioEditorOperations.startWithCommander(NativeDeckDraft(), "Atraxa, Praetors' Voice")
        assertEquals("An untouched default name becomes the commander's name", "Atraxa, Praetors' Voice", draft.name)
        assertEquals(listOf("Atraxa, Praetors' Voice"), draft.rows.map { it.cardName })
        assertTrue(draft.rows[0].isPrimaryCommander)
        val named = DeckStudioEditorOperations.startWithCommander(NativeDeckDraft("My Superfriends"), "Atraxa, Praetors' Voice")
        assertEquals("A name the player chose is kept", "My Superfriends", named.name)

        draft = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "deck", 2)
        draft = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "main", 1)
        draft = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "maybeboard", 1)
        draft = DeckStudioEditorOperations.addCopies(draft, "Sol Ring", "considering", 1)
        assertEquals("Main merges; considering is the maybeboard", listOf(3, 2), draft.rows.filter { it.cardName == "Sol Ring" }.map { it.quantity })
        val before = draft
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.addCopies(before, "Sol Ring", "deck", 0) }
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.addCopies(before, " ", "deck", 1) }

        val history = DeckStudioEditHistory(NativeDeckDraft()).edited { DeckStudioEditorOperations.addCopies(it, "Forest", "deck", 30) }
        assertEquals(listOf(30), history.value.rows.map { it.quantity })
        assertTrue("One Undo removes the whole quick add", history.undone().value.rows.isEmpty())
    }

    @Test fun bulkMoveQuantityAndRemoveAreAtomic() {
        val a = row("Sol Ring"); val b = row("Counterspell", 2); val commander = row("Atraxa, Praetors' Voice", 1, "commanders", primary = true)
        var draft = NativeDeckDraft("Bulk", listOf(commander, a, b))
        draft = DeckStudioEditorOperations.moveRows(draft, setOf(a.id, commander.id), "maybeboard")
        assertEquals(listOf("maybeboard", "maybeboard", "deck"), draft.rows.map { it.section })
        assertFalse("Moving the commander clears its primary flag", draft.rows[0].isPrimaryCommander)
        draft = DeckStudioEditorOperations.setQuantity(draft, setOf(a.id, b.id), 4)
        assertEquals(listOf(1, 4, 4), draft.rows.map { it.quantity })
        val before = draft
        assertThrows<DeckEditingError> { DeckStudioEditorOperations.setQuantity(before, setOf(a.id), 0) }
        assertThrows<DeckEditingError.MissingEntry> { DeckStudioEditorOperations.removeRows(before, setOf(a.id, UUID.randomUUID())) }
        assertThrows<DeckEditingError.MissingEntry> { DeckStudioEditorOperations.moveRows(before, emptySet(), "deck") }
        draft = DeckStudioEditorOperations.removeRows(draft, setOf(a.id, b.id))
        assertEquals(listOf("Atraxa, Praetors' Voice"), draft.rows.map { it.cardName })
        // One whole-draft transaction is one undo step.
        assertEquals(before, DeckStudioEditHistory(before).edited { DeckStudioEditorOperations.removeRows(it, setOf(a.id, b.id)) }.undone().value)
        assertEquals("maybeboard", DeckStudioDraftPresentation.normalizedSection("Considering"))
    }

    @Test fun textDiffReviewsAddsRemovesAndKeepsRowsAndPrimaryCommander() {
        val tymna = row("Tymna the Weaver", section = "commanders")
        val kraum = row("Kraum, Ludevic's Opus", section = "commanders", primary = true)
        val sol = row("Sol Ring", section = "main")
        val island = row("Island", 3)
        val maybe = row("Counterspell", section = "considering")
        val draft = NativeDeckDraft("Partners", listOf(tymna, kraum, sol, island, maybe))
        val exported = DeckStudioTextExport.text(draft.deck())
        // Round trip: exporting and applying unchanged text is not a change.
        val same = DeckStudioTextDiff.draft(exported, draft).first
        assertTrue(DeckStudioTextDiff.between(draft, same).isEmpty)
        assertEquals("The chosen primary commander stays primary", "Kraum, Ludevic's Opus", same.rows.first { it.isPrimaryCommander }.cardName)
        assertEquals(sol.id, same.rows.first { it.cardName == "Sol Ring" }.id)
        assertEquals("Unchanged rows keep their section spelling", "main", same.rows.first { it.cardName == "Sol Ring" }.section)
        assertEquals("considering", same.rows.first { it.cardName == "Counterspell" }.section)

        val edited = exported.replace("3 Island", "1 Island\n2 Lightning Bolt (M10) 146").replace("1 Sol Ring\n", "")
        val (result, notes) = DeckStudioTextDiff.draft(edited, draft)
        val diff = DeckStudioTextDiff.between(draft, result)
        assertEquals(listOf("+2 Lightning Bolt · Deck"), diff.added.map { it.label })
        assertEquals(listOf("−2 Island · Deck", "−1 Sol Ring · Deck"), diff.removed.map { it.label })
        assertEquals("Partners", result.name)
        assertEquals(island.id, result.rows.first { it.cardName == "Island" }.id)
        assertEquals(listOf("Line 7: (M10) 146"), notes)
        assertEquals(2, result.rows.count { DeckStudioDraftPresentation.section(it) == "commanders" })

        // Clearing the text removes everything, as one reviewed change.
        val cleared = DeckStudioTextDiff.draft("  \n", draft).first
        assertTrue(cleared.rows.isEmpty())
        assertEquals(5, DeckStudioTextDiff.between(draft, cleared).removed.size)
        assertThrows<OnDeviceDeckEditing.TextImportError> { DeckStudioTextDiff.draft("Deck\nSol Ring", draft) }
        assertEquals("Maybeboard", DeckStudioTextDiff.title("maybeboard"))
        assertEquals("Tokens", DeckStudioTextDiff.title("tokens"))
    }

    @Test fun roleGroupsAllowSeveralRolesAndHonourReviews() {
        val sol = row("Sol Ring"); val solemn = row("Solemn Simulacrum"); val bears = row("Grizzly Bears", 2); val counter = row("Counterspell")
        val extraSol = row("Sol Ring", section = "main")
        val rows = listOf(sol, solemn, bears, counter, extraSol)
        val groups = DeckStudioRoleGroups.membership(rows, catalogue::card, emptyMap())
        assertEquals("One card sits under every role it has", listOf("Ramp", "Draw / card flow"), groups[solemn.id])
        assertEquals(listOf("Ramp"), groups[sol.id])
        assertEquals(listOf("Ramp"), groups[extraSol.id])
        assertEquals(listOf("Targeted interaction"), groups[counter.id])
        assertEquals(listOf("Other"), groups[bears.id])
        assertEquals("Headers count unique cards", 2, DeckStudioRoleGroups.uniqueCards(listOf(sol, extraSol, solemn)))
        val reviewed = DeckStudioRoleGroups.membership(rows, catalogue::card, mapOf("Grizzly Bears" to setOf(DeckStudioRole.PROTECTION), "Solemn Simulacrum" to emptySet()))
        assertEquals("Your own review replaces automatic hints", listOf("Protection"), reviewed[bears.id])
        assertEquals(listOf("Other"), reviewed[solemn.id])
        assertEquals("Other", DeckStudioRoleGroups.order.last())
        assertEquals("Ramp", DeckStudioRoleGroups.order.first())
    }

    @Test fun sampleHandDrawsSevenLondonMulligansAndKeepsCommandersOut() {
        val draft = NativeDeckDraft("Hand", listOf(row("Atraxa, Praetors' Voice", 1, "commanders", primary = true), row("Forest", 10), row("Sol Ring", section = "main"),
            row("Counterspell", section = "maybeboard"), row("Grizzly Bears", section = "companion")))
        val names = DeckStudioSampleHand.libraryNames(draft)
        assertEquals(11, names.size)
        assertEquals("Commanders, companions and other boards stay out of the library", setOf("Forest", "Sol Ring"), names.toSet())
        val random = Random(7)
        var hand = DeckStudioSampleHand.of(names).dealt(random)
        assertEquals(7, hand.hand.size); assertEquals(4, hand.library.size)
        assertEquals(1, hand.turn); assertTrue(hand.canMulligan)
        hand = hand.mulliganed(random)
        assertEquals("London: draw a fresh seven", 7, hand.hand.size)
        assertEquals(1, hand.toBottom)
        assertFalse("Choose the bottom card first", hand.canDraw)
        hand = hand.mulliganed(random)
        assertEquals("No second mulligan before bottoming", 1, hand.mulligans)
        val bottom = hand.hand[2]
        hand = hand.puttingOnBottom(bottom.id)
        assertEquals(6, hand.hand.size); assertEquals(bottom, hand.library.last()); assertEquals(0, hand.toBottom)
        hand = hand.mulliganed(random)
        assertEquals(2, hand.mulligans); assertEquals(2, hand.toBottom)
        hand = hand.puttingOnBottom(hand.hand[0].id).let { it.puttingOnBottom(it.hand[0].id) }.let { it.puttingOnBottom(it.hand[0].id) }
        assertEquals("Only as many as the mulligans taken go to the bottom", 5, hand.hand.size)
        val top = hand.library.first()
        hand = hand.drawn()
        assertEquals(top, hand.hand.last()); assertEquals(2, hand.turn)
        assertFalse("No mulligans after the first draw", hand.canMulligan)
        assertEquals("No card is lost or duplicated", 11, hand.hand.size + hand.library.size)
        while (hand.canDraw) hand = hand.drawn()
        assertTrue(hand.library.isEmpty()); assertEquals(11, hand.hand.size)
        hand = hand.dealt(random)
        assertEquals(7, hand.hand.size); assertEquals(0, hand.mulligans); assertEquals(1, hand.turn)
        assertEquals(11, (hand.hand + hand.library).map { it.id }.toSet().size)
        val small = DeckStudioSampleHand.of(listOf("Forest", "Forest", "Sol Ring")).dealt(random)
        assertEquals(3, small.hand.size); assertFalse(small.canDraw)
        assertEquals(DeckStudioSampleHand.of(names).dealt(Random(3)), DeckStudioSampleHand.of(names).dealt(Random(3)))
    }

    @Test fun searchSyntaxParsesTypesOracleManaValueAndIdentity() {
        val syntax = DeckStudioSearchSyntax.parse("""t:"legendary creature" o:draw mv<=3 mv>=1 id:wu angel""")
        assertEquals(listOf("legendary creature"), syntax.types)
        assertEquals(listOf("draw"), syntax.oracle)
        assertEquals(3.0, syntax.maximumManaValue); assertEquals(1.0, syntax.minimumManaValue)
        assertEquals(setOf("W", "U"), syntax.identity)
        assertEquals("angel", syntax.text)
        assertEquals(2.0, DeckStudioSearchSyntax.parse("MV=2").minimumManaValue)
        assertEquals(2.0, DeckStudioSearchSyntax.parse("mv=2").maximumManaValue)
        assertEquals(emptySet<String>(), DeckStudioSearchSyntax.parse("id:c").identity)
        assertEquals(listOf("Instant"), DeckStudioSearchSyntax.parse("T:Instant").types)
        // Plain text and names with colons stay text; half-typed terms filter nothing yet.
        assertFalse(DeckStudioSearchSyntax.parse("Circle of Protection: Red").hasFilters)
        assertEquals("Circle of Protection: Red", DeckStudioSearchSyntax.parse("Circle of Protection: Red").text)
        assertEquals("sol", DeckStudioSearchSyntax.parse("sol t:").text)
        assertFalse(DeckStudioSearchSyntax.parse("sol t: mv<=").hasFilters)
        assertEquals("id:xyz", DeckStudioSearchSyntax.parse("id:xyz").text)
        assertEquals("mv<=abc", DeckStudioSearchSyntax.parse("mv<=abc").text)
    }

    @Test fun searchSyntaxFiltersLocalCatalogueAndCommanderPicker() {
        fun names(query: String, identity: List<String>? = null) = DeckStudioBuilderSearch.cards(catalogue, query, allowedIdentity = identity).map { it.name }
        assertEquals(listOf("Counterspell", "Lightning Bolt"), names("t:instant"))
        assertEquals(listOf("Soldevi Sage", "Solemn Simulacrum"), names("o:draw"))
        assertEquals(listOf("Sol Ring"), names("t:artifact mv<=1"))
        assertEquals(listOf("Atraxa, Praetors' Voice", "Solemn Simulacrum"), names("mv>=4 t:creature"))
        assertEquals(listOf("Counterspell"), names("id:u t:instant"))
        assertEquals(listOf("Sol Ring", "Solemn Simulacrum"), names("id:c"))
        assertEquals(listOf("Sol Ring", "Solemn Simulacrum"), names("sol t:artifact"))
        assertEquals("A half-typed term does not empty the results", listOf("Sol Ring", "Soldevi Sage", "Solemn Simulacrum"), names("sol t:"))
        assertEquals("Commander identity and id: both apply", listOf("Lightning Bolt"), names("t:instant", identity = listOf("R")))
        assertTrue(names("id:wu t:instant", identity = listOf("R")).isEmpty())
        assertEquals(listOf("Solemn Simulacrum"), DeckStudioBuilderSearch.cards(catalogue, "t:creature", type = "Artifact").map { it.name })
        assertEquals(listOf("Counterspell"), DeckStudioBuilderSearch.cards(catalogue, "t:instant", minimumManaValue = 2.0).map { it.name })
        assertTrue(DeckStudioBuilderSearch.cards(catalogue, "o:counter", limit = 0).isEmpty())
        // Case- and diacritic-insensitive, like the iOS search.
        assertEquals(listOf("Séance"), names("seance t:enchantment"))
        // Quick Add suggestions match names only; exact and prefix matches lead.
        assertEquals(listOf("Sol Ring", "Soldevi Sage", "Solemn Simulacrum"), DeckStudioBuilderSearch.nameSuggestions(catalogue, "sol").map { it.name })
        assertTrue(DeckStudioBuilderSearch.nameSuggestions(catalogue, "draw").isEmpty())
        assertEquals(listOf("Sol Ring"), DeckStudioBuilderSearch.nameSuggestions(catalogue, "SOL RING", limit = 1).map { it.name })
        // Commander-first: legendary creatures and cards that say they can be your commander.
        assertEquals(listOf("Atraxa, Praetors' Voice", "Daretti, Scrap Savant", "Isamaru, Hound of Konda"), DeckStudioBuilderSearch.commanders(catalogue, "").map { it.name })
        assertEquals(listOf("Isamaru, Hound of Konda"), DeckStudioBuilderSearch.commanders(catalogue, "id:w").map { it.name })
        assertEquals(listOf("Isamaru, Hound of Konda"), DeckStudioBuilderSearch.commanders(catalogue, "hound").map { it.name })
    }
}
