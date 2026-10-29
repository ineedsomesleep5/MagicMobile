package io.magicmobile.android.laws

import io.magicmobile.android.game.GameResumeSettings
import io.magicmobile.android.game.GameResumeSidecar
import io.magicmobile.android.game.GameResumeStore
import io.magicmobile.android.game.jsonObject
import io.magicmobile.android.laws.Laws.forAll
import io.magicmobile.android.laws.Laws.pick
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.file.Files
import kotlin.random.Random

/** A saved game reads back exactly as it was written: the menu can always offer the same Resume and Rematch. */
class ResumeLawsTest {
    private val words = listOf("Aurelia", "Kozilek", "Meren", "Y'shtola", "Krenko, Mob Boss", "Æther \"quoted\"", "émoji 🐉", "")

    private fun Random.settings(): GameResumeSettings = GameResumeSettings(
        deckID = "deck-${nextInt(1000)}", aiDeckIDs = List(nextInt(0, 4)) { "ai-${nextInt(100)}" }, aiSkill = nextInt(1, 7),
        startingPlayerMode = pick(listOf("roll", "random", "me", "opponent")),
        mode = if (nextBoolean()) pick(listOf("quick", "ranked")) else null, deckBracket = if (nextBoolean()) nextInt(1, 6) else null)

    private fun Random.sidecar(): GameResumeSidecar {
        val seats = JsonArray(List(nextInt(1, 4)) { jsonObject("controller" to JsonPrimitive("ai"), "name" to JsonPrimitive(pick(words))) })
        val configuration = jsonObject("seats" to seats, "checkpoint" to JsonPrimitive("/tmp/checkpoint.bin"))
        val created = nextLong(1_700_000_000_000, 1_900_000_000_000)
        return GameResumeSidecar(
            appBuild = "0.1.1 (${nextInt(1, 99)})", engineIdentity = "xmage/protocol-1/dac400b/${nextInt(1 shl 20)}",
            createdAt = created, lastCheckpointAt = created + nextLong(0, 3_600_000), leftAt = if (nextBoolean()) created + nextLong(0, 7_200_000) else null,
            turn = nextLong(1, 60), playerDeckName = pick(words).ifEmpty { "Deck" },
            opponents = GameResumeSidecar.opponents(configuration),
            setup = GameResumeSidecar.setup(configuration, "seat-${nextInt(4)}", if (nextBoolean()) settings() else null))
    }

    @Test fun settingsRoundTrip() = forAll("resume settings round trip") { random ->
        val settings = random.settings()
        assertEquals(settings, GameResumeSettings.decode(settings.json()))
    }

    @Test fun aSavedGameReadsBackExactly() {
        val directory = Files.createTempDirectory("resume-laws").toFile()
        try {
            val store = GameResumeStore(directory).also { it.prepare() }
            forAll("resume.json write then read", runs = 200) { random ->
                val sidecar = random.sidecar()
                assertEquals(sidecar, GameResumeSidecar.decode(sidecar.json()))
                store.write(sidecar)
                assertEquals(sidecar, store.read())
            }
        } finally { directory.deleteRecursively() }
    }
}
