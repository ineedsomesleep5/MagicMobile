package io.magicmobile.android.studio

import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Card picture sync against a fake server, running every scenario in parity/card-art-sync-cases.json
 * (docs/CARD_ART_SYNC.md), the same cases iOS and the web run.
 */
class CardArtSyncTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val cases = Json.parseToJsonElement(File(repo, "apps/android/core/src/test/resources/parity/card-art-sync-cases.json").readText())["cases"].array!!

    private class Refused(val code: String) : Exception(code)

    /** The server's rows and the player's folder; a picture's bytes are its name. */
    private class FakeServer(rows: List<Pair<String, String?>>, private val refuse: String?) : CardArtSyncAPI {
        val rows = LinkedHashMap<String, ServerCardArt>()
        val files = mutableSetOf<String>()
        private var seq = 0L

        init {
            for ((key, picture) in rows) write(key, picture)
            files += this.rows.values.mapNotNull { it.picture }
        }

        private fun write(key: String, picture: String?): ServerCardArt {
            val row = ServerCardArt(key, picture, ++seq)
            rows.remove(key); rows[key] = row
            return row
        }

        override suspend fun since(cursor: Long): CardArtSyncAPI.Page {
            val arts = rows.values.filter { it.changeSeq > cursor }.sortedBy { it.changeSeq }
            return CardArtSyncAPI.Page(arts, arts.lastOrNull()?.changeSeq ?: cursor, false)
        }

        override suspend fun set(cardKey: String, picture: String?): ServerCardArt {
            if (cardKey == refuse) throw Refused("too_many_pictures")
            if (picture != null && picture !in files) throw Refused("picture_missing")
            return write(cardKey, picture)
        }

        override suspend fun upload(picture: String, bytes: ByteArray) { assertEquals(picture, String(bytes)); files += picture }
        override suspend fun download(picture: String): ByteArray = if (picture in files) picture.toByteArray() else throw Refused("not_found")
        override suspend fun removeFile(picture: String) { files -= picture }
    }

    private class FakeLocal(val pictures: MutableMap<String, String>) : CardArtLocal {
        override fun keys() = pictures.keys.sorted()
        override fun hash(cardKey: String) = pictures[cardKey]
        override fun bytes(cardKey: String) = pictures[cardKey]?.toByteArray()
        override fun store(cardKey: String, bytes: ByteArray) { pictures[cardKey] = String(bytes) }
        override fun remove(cardKey: String) { pictures.remove(cardKey) }
    }

    private fun strings(value: kotlinx.serialization.json.JsonElement?): Map<String, String> =
        (value as JsonObject).mapValues { it.value.string!! }

    @Test
    fun sharedCases() = runBlocking {
        assertEquals(11, cases.size)
        for (item in cases) {
            val name = item["name"].string!!
            val expect = item["expect"]
            val stored = arrayOf<String?>(null)
            val record = (item["record"] as JsonObject).let { if ("account" in it) it else JsonObject(it + ("account" to kotlinx.serialization.json.JsonPrimitive("me"))) }
            stored[0] = record.toString()
            val state = CardArtSyncState({ stored[0] }, { stored[0] = it })
            val local = FakeLocal(strings(item["local"]).toMutableMap())
            val server = FakeServer(item["server"].array!!.map { it["cardKey"].string!! to it["picture"].string }, item["refuse"].string)
            CardArtSync(local, state, server) { (it as? Refused)?.code }.sync("me")
            assertEquals(name, strings(expect["local"]), local.pictures)
            assertEquals(name, (expect["server"] as JsonObject).mapValues { (_, v) -> if (v is JsonNull) null else v.string },
                server.rows.mapValues { it.value.picture })
            assertEquals(name, expect["files"].array!!.map { it.string!! }.sorted(), server.files.sorted())
            assertEquals(name, strings(expect["synced"]), state.record.synced)
            assertEquals(name, emptyList<CardArtSyncState.Removal>(), state.record.removed)
            assertEquals(name, "me", state.record.account)
            // What was saved reads back the same.
            assertEquals(name, state.record, CardArtSyncState({ stored[0] }, {}).record)
        }
    }

    @Test
    fun aRemovalHereWaitsForTheNextSyncAndSurvivesARestart() {
        val stored = arrayOf<String?>("""{"account":"me","cursor":0,"synced":{"gojo":"p1"},"removed":[]}""")
        val state = CardArtSyncState({ stored[0] }, { stored[0] = it })
        val sync = CardArtSync(FakeLocal(mutableMapOf()), state, FakeServer(emptyList(), null)) { null }
        sync.noteRemoved("gojo")
        assertTrue(sync.hasPending())
        assertEquals(listOf(CardArtSyncState.Removal("gojo", "p1")), CardArtSyncState({ stored[0] }, {}).record.removed)
    }
}
