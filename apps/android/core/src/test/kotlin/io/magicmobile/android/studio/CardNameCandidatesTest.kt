package io.magicmobile.android.studio

import io.magicmobile.android.core.PrintingIndex
import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** parity/card-name-cases.json: the names a deck link's card is looked up by (iOS OnDeviceDeckResolverTests, web deckStudio.test.ts). */
class CardNameCandidatesTest {
    @Test fun sharedCases() {
        val root = Json.parseToJsonElement(
            File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
                "apps/android/core/src/test/resources/parity/card-name-cases.json").readText()).jsonObject
        for (case in root["cases"]!!.jsonArray) {
            val fields = case.jsonObject
            val name = fields["name"]!!.jsonPrimitive.content
            assertEquals(name, fields["candidates"]!!.jsonArray.map { it.jsonPrimitive.content }, NativeDeckCanonicalNames.candidates(name))
        }
    }

    /** parity/ellipsis-deck-cases.json: a deck saved with the tight ellipsis still loads the spaced-dot printing. */
    @Test fun savedEllipsisNamesStillResolve() {
        val root = Json.parseToJsonElement(File(repoRoot(), "apps/android/core/src/test/resources/parity/ellipsis-deck-cases.json").readText()).jsonObject
        val tsv = buildString {
            append("#\t").append("c".repeat(64)).append('\t').append("a".repeat(40)).append('\n')
            for (card in root["cards"]!!.jsonArray) {
                val row = card.jsonObject
                append(row["name"]!!.jsonPrimitive.content).append('\t')
                append(row["setCode"]!!.jsonPrimitive.content).append('\t')
                append(row["collectorNumber"]!!.jsonPrimitive.content).append('\n')
            }
        }
        val resolver = OnDeviceDeckResolver(PrintingIndex(tsv.byteInputStream()))
        val deck = root["deck"]!!.jsonObject
        val entries = deck["main"]!!.jsonArray.map { DeckEntry(it.jsonPrimitive.content, 1, "deck") }
        val resolved = resolver.resolve(DeckList(deck["name"]!!.jsonPrimitive.content,
            DeckEntry(deck["commander"]!!.jsonPrimitive.content, 1, "commander"), entries))
        val main = checkNotNull(resolved["main"].array)
        val expected = root["resolvedMain"]!!.jsonArray
        assertEquals(expected.size, main.size)
        expected.forEachIndexed { index, want ->
            val row = want.jsonObject
            assertEquals(row["name"]!!.jsonPrimitive.content, main[index]["name"].string)
            assertEquals(row["setCode"]!!.jsonPrimitive.content, main[index]["setCode"].string)
            assertEquals(row["collectorNumber"]!!.jsonPrimitive.content, main[index]["collectorNumber"].string)
        }
        assertEquals("Sol Ring", checkNotNull(resolved["commanders"].array).single()["name"].string)
    }

    private fun repoRoot(): File =
        generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory }
}
