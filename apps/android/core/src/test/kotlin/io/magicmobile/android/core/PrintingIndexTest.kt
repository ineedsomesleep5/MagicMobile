package io.magicmobile.android.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The generated assets (build/generated/magicmobile-assets) are checked when present. */
class PrintingIndexTest {
    private val assets = File(System.getProperty("user.dir"), "../app/build/generated/magicmobile-assets")

    @Test fun resolvesEveryPreconLikeTheFullCatalogue() {
        val tsv = File(assets, "printings.tsv")
        if (!tsv.exists()) return
        val index = PrintingIndex(tsv.inputStream())
        val catalogue = Catalogue(File(assets, "catalogue.jsonl").inputStream())
        assertEquals(catalogue.registryHash, index.catalogueHash)
        assertEquals(catalogue.upstreamCommit, index.upstreamCommit)
        assertEquals(catalogue.cards.size, index.size)
        val precons = Wire.decode(File(assets, "precons.json").readBytes()).array("decks").map { Deck.decode(Wire.objectValue(it)) }
        for (deck in precons) assertEquals(deck.name, catalogue.resolve(deck, true), index.resolve(deck, true))
        for (card in catalogue.cards) assertEquals(card.name, card.collector, index.find(card.name)?.collectorNumber)
    }

    @Test fun plainFastPathMatchesTheFullCleanupOnEveryRulesText() {
        val file = File(assets, "catalogue.jsonl")
        if (!file.exists()) return
        var checked = 0
        file.readLines().drop(1).filter { it.isNotBlank() }.forEach { line ->
            val text = io.magicmobile.core.Json.parseObject(line)["oracleText"] as? String ?: return@forEach
            // "&#0;" decodes to nothing but forces the regex loop.
            assertEquals(text, Decisions.plain("$text&#0;"), Decisions.plain(text))
            checked++
        }
        assertTrue(checked > 20_000)
    }

    @Test fun plainFastPathMatchesMarkupEdgeCases() {
        val samples = listOf("a<a<br>b>c", "x <y z> w", "<<i>b>", "one<br/>two<BR >three<br / >four", "tag <i>unclosed", "a < b and c > d",
            "<b>Bold</b> <sup>1</sup>\n\n  spaced   out  ", "<script>bad()</script>ok", "<br><br>", "trail <", "  nbsp  ", "tab\tand\u000Bvt")
        for (text in samples) assertEquals(text, Decisions.plain("$text&#0;"), Decisions.plain(text))
    }
}
