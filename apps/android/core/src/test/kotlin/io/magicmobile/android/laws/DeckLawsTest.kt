package io.magicmobile.android.laws

import io.magicmobile.android.core.CardEntry
import io.magicmobile.android.core.CardPrinting
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.DeckTextImport
import io.magicmobile.android.laws.Laws.forAll
import io.magicmobile.android.laws.Laws.pick
import org.junit.Assert.assertEquals
import kotlin.random.Random
import org.junit.Test

/** Deck import and export never drop, invent or move a card. */
class DeckLawsTest {
    /** Real card names, including the awkward ones: split cards, commas, quotes, apostrophes, digits, accents. */
    private val names = listOf(
        "Sol Ring", "Forest", "Island", "Lightning Bolt", "Fire // Ice", "Who // What // When // Where // Why",
        "Borrowing 100,000 Arrows", "Kongming, \"Sleeping Dragon\"", "\"Ach! Hans, Run!\"", "Lim-Dûl's Vault", "Æther Vial",
        "Jötun Grunt", "Urza's Saga", "1996 World Champion", "Atraxa, Praetors' Voice", "Krenko, Mob Boss",
        "Miirym, Sentinel Wyrm", "Edgar Markov", "The Ur-Dragon", "Y'shtola, Night's Blessed", "Giada, Font of Hope",
        "Circle of Protection: Red", "Asmoranomardicadaistinaculdacar", "Our Market Research Shows That Players Like Really Long Card Names So We Made this Card to Have the Absolute Longest Card Name Ever Elemental",
    )
    private val sections = listOf("deck", "commanders", "sideboard", "maybeboard", "companions")

    private fun Random.deck(withPrintings: Boolean): Deck {
        val rows = (1..nextInt(1, 40)).map {
            val printing = if (withPrintings && nextInt(3) == 0) CardPrinting.of(pick(listOf("cmm", "lea", "2x2", "mh3")), "${nextInt(1, 400)}") else null
            CardEntry(pick(names), nextInt(1, 30), pick(sections), printing)
        }
        return Deck("Deck ${nextInt(1000)}", rows)
    }

    private fun counts(deck: Deck) = deck.entries.groupBy { it.section to it.name }.mapValues { (_, rows) -> rows.sumOf { it.quantity } }

    @Test fun jsonExportRoundTripsEveryRowAndPrinting() = forAll("deck JSON round trip") { random ->
        val deck = random.deck(withPrintings = true)
        assertEquals(deck, DeckTextImport.preview(deck.name, DeckTextImport.exportJSON(deck)).deck)
    }

    @Test fun textExportKeepsEveryCountForRealCardNames() = forAll("deck text round trip") { random ->
        val deck = random.deck(withPrintings = false)
        val text = DeckTextImport.exportText(deck) // throws if the text would lose a card
        assertEquals(counts(deck), counts(DeckTextImport.preview(deck.name, text).deck))
    }

    @Test fun addingThenRemovingCopiesRestoresTheDeck() = forAll("deck +n then -n") { random ->
        val deck = random.deck(withPrintings = true)
        val index = random.nextInt(deck.entries.size)
        val room = 2000 - deck.entries.sumOf { it.quantity }
        if (room < 1) return@forAll
        val n = random.nextInt(1, minOf(room, 50) + 1)
        assertEquals(deck, deck.change(index, n).change(index, -n))
    }
}
