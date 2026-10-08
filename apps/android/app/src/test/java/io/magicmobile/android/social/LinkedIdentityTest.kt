package io.magicmobile.android.social

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** chat-cases.json "linkedIdentities" (iOS TableChatTests.testLinkedIdentitiesSkipTheAnonymousStart). */
class LinkedIdentityTest {
    private val fixture = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/chat-cases.json").readText()).jsonObject["linkedIdentities"]!!.jsonObject

    @Test fun skipsTheAnonymousStart() {
        val parsed = LinkedIdentity.parse(fixture["user"]!!.jsonObject)
        val expected = fixture["expected"]!!.jsonArray.map { it.jsonObject }
        assertEquals(expected.map { it["provider"]!!.jsonPrimitive.content }, parsed.map { it.provider })
        assertEquals(expected.map { it["title"]!!.jsonPrimitive.content }, parsed.map { it.title })
        assertEquals(expected.map { it["email"]!!.jsonPrimitive.content }, parsed.map { it.email })
        assertEquals(emptyList<LinkedIdentity>(), LinkedIdentity.parse(Json.parseToJsonElement("""{"identities":[{"provider":"anonymous"}]}""") as JsonObject))
    }
}
