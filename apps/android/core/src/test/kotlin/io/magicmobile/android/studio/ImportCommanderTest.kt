package io.magicmobile.android.studio

import io.magicmobile.android.core.DoubleFacedCards
import io.magicmobile.android.core.PrintingIndex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImportCommanderTest {
    private fun importer() = OnDeviceDeckLinkImporter(OnDeviceDeckResolver(PrintingIndex(("#\t${"c".repeat(64)}\t${"a".repeat(40)}\n" +
        "Sol Ring\tC21\t263\nForest\tM21\t274\nKardur, Doomscourge\tKHC\t10\nFire\tMH2\t290\n=\tFire // Ice\tFire\n").byteInputStream())))

    @Test fun chosenCommanderLeadsWhetherOrNotTheListMarkedOne() {
        val importer = importer()
        // Unmarked: the one main-deck copy is promoted, keeping its printing.
        val unmarked = importer.preview("1 Kardur, Doomscourge (KHC) 10\n3 Forest", "Plain list")
        assertNull(unmarked.deck.commander)
        val led = importer.preview(unmarked, "Kardur, Doomscourge")
        assertEquals("Kardur, Doomscourge", led.deck.commander?.cardName)
        assertEquals(unmarked.deck.entries.first().printing, led.deck.commander?.printing)
        assertEquals(listOf("Forest"), led.deck.entries.map { it.cardName })
        assertEquals(unmarked.deck.totalCards, led.deck.totalCards)
        assertEquals(unmarked.annotations, led.annotations)
        // A different marked commander joins the main deck; nothing is lost.
        val marked = importer.preview("Commander\n1 Forest\nDeck\n1 Kardur, Doomscourge", "Marked")
        val swapped = importer.preview(marked, "Kardur, Doomscourge")
        assertEquals("Kardur, Doomscourge", swapped.deck.commander?.cardName)
        assertEquals(listOf(DeckEntry("Forest", 1, "deck")), swapped.deck.entries)
        // Absent from the list: added. Already the commander: unchanged.
        val short = importer.preview("2 Forest", "Short")
        assertEquals(short.deck.totalCards + 1, importer.preview(short, "Kardur, Doomscourge").deck.totalCards)
        assertEquals(marked.deck, OnDeviceDeckLinkImporter.choosingCommander("Forest", marked.deck))
        // A partner already in the command zone takes the lead and the old lead stays beside it.
        val partners = DeckList("Partners", DeckEntry("Kardur, Doomscourge", 1, "commanders"), listOf(DeckEntry("Forest", 1, "commanders")))
        val flipped = OnDeviceDeckLinkImporter.choosingCommander("Forest", partners)
        assertEquals("Forest", flipped.commander?.cardName)
        assertEquals(listOf(DeckEntry("Kardur, Doomscourge", 1, "commanders")), flipped.entries)
    }

    @Test fun archidektUsernameListKeepsOnlyPublicDecksAndPages() {
        assertEquals("https://archidekt.com/api/decks/v3/?ownerUsername=Caleb_F.1&pageSize=50&page=2",
            OnDeviceDeckLinkImporter.archidektDeckListEndpoint(" Caleb_F.1 ", 2))
        for (bad in listOf("", "a b", "x/../y", "name?x=1", "a".repeat(65))) {
            org.junit.Assert.assertThrows(ResolutionError::class.java) { OnDeviceDeckLinkImporter.archidektDeckListEndpoint(bad, 1) }
        }
        org.junit.Assert.assertThrows(ResolutionError::class.java) { OnDeviceDeckLinkImporter.archidektDeckListEndpoint("caleb", 0) }
        val page = OnDeviceDeckLinkImporter.decodeArchidektDeckPage("""{"count":3,"next":"https://archidekt.com/api/decks/v3/?page=2","results":[
            {"id":1,"name":"Edgar","size":100,"updatedAt":"2026-10-01T12:00:00Z","private":false,"unlisted":false,"deckFormat":3},
            {"id":2,"name":"Secret","private":true},{"id":3,"name":"Hidden","unlisted":true}]}""")
        assertEquals(listOf(1L), page.decks.map { it.id })
        assertEquals("2026-10-01", page.decks.first().updatedDay)
        assertEquals("https://archidekt.com/decks/1", page.decks.first().link)
        assertEquals(true, page.hasMore)
        assertEquals(false, OnDeviceDeckLinkImporter.decodeArchidektDeckPage("""{"next":null,"results":[]}""").hasMore)
        org.junit.Assert.assertThrows(ResolutionError::class.java) { OnDeviceDeckLinkImporter.decodeArchidektDeckPage("<html>") }
    }

    @Test fun eitherFaceNamesTheOther() {
        val faces = DoubleFacedCards()
        assertNull(faces.otherFace("Valakut Awakening"))
        faces.setReverseFaces(mapOf("Valakut Stoneforge" to "Valakut Awakening", "Insectile Aberration" to "Delver of Secrets"))
        assertEquals(DoubleFacedCards.Face("Valakut Stoneforge", true), faces.otherFace("Valakut Awakening"))
        assertEquals(DoubleFacedCards.Face("Delver of Secrets", false), faces.otherFace("Insectile Aberration"))
        assertNull(faces.otherFace("Sol Ring"))
    }
}
