package io.magicmobile.android.ui

import io.magicmobile.android.board.BoardFXSound
import io.magicmobile.android.game.BoardFXArrivalSound
import io.magicmobile.android.game.BoardFXEntrance
import io.magicmobile.android.game.BoardFXEvent
import io.magicmobile.android.game.BoardFXTint
import io.magicmobile.android.game.BoardFXZone
import io.magicmobile.android.game.CardIdentity
import io.magicmobile.android.game.ScheduledBoardFX
import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Mirrors testEveryCreatureVoiceSlotHasItsSoundAndFiles (iOS): every voice slot plays, and its files ship. */
class GameSoundVoicesTest {
    private val audio = File("../../ios/MagicMobile/Resources/Audio")

    @Test fun everyCreatureVoiceSlotHasItsSoundAndFiles() {
        for (slot in BoardFXArrivalSound.creatureVoices.values.toSet()) {
            val sound = GameSound.voice(slot)
            assertNotNull("no GameSound for $slot", sound)
            for (n in 1..sound!!.variants) {
                val file = if (sound.variants > 1) "${sound.fileBase}-$n" else sound.fileBase
                assertTrue("missing $file", File(audio, "$file.m4a").exists() || File(audio, "$file.caf").exists())
            }
        }
        assertEquals("giants share the first two orc voices", "creature-orc", GameSound.CREATURE_GIANT.fileBase)
    }

    @Test fun everySoundHasItsFile() {
        for (sound in GameSound.entries) for (n in 1..sound.variants) {
            val file = if (sound.variants > 1) "${sound.fileBase}-$n" else sound.fileBase
            assertTrue("missing $file", File(audio, "$file.m4a").exists() || File(audio, "$file.caf").exists())
        }
    }

    /** Mirrors testACreaturesVoicePlaysAsItsCardComesInAndEndsAsItLands (iOS). */
    @Test fun aCreaturesVoicePlaysAsItsCardComesInAndEndsAsItLands() {
        fun fx(id: String) = ScheduledBoardFX(id.hashCode(), BoardFXEvent.EnteredBattlefield(id, "me", BoardFXZone.HAND, BoardFXTint.GREEN,
            BoardFXEntrance.SHOWCASE), 0.3, 0.5, true)
        val entering = fx("elf"); val landing = fx("merfolk")
        val cues = BoardFXSound.cues(listOf(entering, landing), "me", mapOf(
            "elf" to BoardFXSound.Arrival(CardIdentity("Llanowar Elves", "Creature — Elf Druid", null, manaCost = "{G}")),
            "merfolk" to BoardFXSound.Arrival(CardIdentity("Coral Merfolk", "Creature — Merfolk", null, manaCost = "{1}{U}"))), false)
        assertEquals(GameSound.CREATURE_ELF, cues.first().sound)
        assertEquals("the voice starts as the card starts entering", entering.delay, cues.first().at, 1e-9)
        assertEquals("and is timed to finish as it lands", entering.landing, cues.first().endsBy!!, 1e-9)
        assertEquals(GameSound.ARRIVE_CREATURE, cues.last().sound)
        assertEquals("a card with no voice lands with the card sound", landing.landing, cues.last().at, 1e-9)
        assertNull(cues.last().endsBy)
    }
}
