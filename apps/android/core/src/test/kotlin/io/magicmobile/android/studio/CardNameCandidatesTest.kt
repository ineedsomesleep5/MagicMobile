package io.magicmobile.android.studio

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
}
