package io.magicmobile.android.game

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Finished games reach the profile server without ever blocking play: sent once confirmed, retried when they could not be (iOS GameUploaderTests.swift). */
class GameUploaderTest {
    private fun match(index: Int) = MatchRecord(id = "game-$index", date = 1_780_000_000_000L + index * 3_600_000L, mode = PlayMode.QUICK, opponents = emptyList(), deckID = "d",
        deckName = "Deck", commander = "Krenko, Mob Boss", colors = listOf("R"), deckBracket = 2, outcome = RankOutcome.WIN, turns = 7)

    /** Newest first, like the record. */
    private fun record(count: Int) = (0 until count).map(::match).asReversed()

    private fun folder() = Files.createTempDirectory("uploader").toFile()

    @Test fun sendsOldestFirstAndRemembersWhatTheServerConfirmed() = runTest {
        val uploader = GameUploader(File(folder(), "u.json"))
        val games = record(3)
        val order = ArrayList<String>()
        assertEquals(3, uploader.flush(games) { order += it.id; GameUploadResult.SENT })
        assertEquals(games.asReversed().map { it.id }, order)
        assertTrue(uploader.pending(games).isEmpty())
        assertEquals(0, uploader.flush(games) { error("sent twice") })
    }

    @Test fun stopsAtTheFirstGameThatCannotBeSentAndRetriesItLater() = runTest {
        val uploader = GameUploader(File(folder(), "u.json"))
        val games = record(4)
        var calls = 0
        assertEquals(2, uploader.flush(games) { calls++; if (calls == 3) GameUploadResult.RETRY_LATER else GameUploadResult.SENT })
        assertEquals(3, calls)
        assertEquals(listOf(games[1].id, games[0].id), uploader.pending(games).map { it.id })
        val retried = ArrayList<String>()
        assertEquals(2, uploader.flush(games) { retried += it.id; GameUploadResult.SENT })
        assertEquals(listOf(games[1].id, games[0].id), retried)
    }

    @Test fun aServerWithoutGameRecordingKeepsEverythingPending() = runTest {
        val uploader = GameUploader(File(folder(), "u.json"))
        val games = record(3)
        var calls = 0
        assertEquals(0, uploader.flush(games) { calls++; GameUploadResult.UNAVAILABLE })
        assertEquals(1, calls)
        assertEquals(3, uploader.pending(games).size)
    }

    @Test fun aGameTheServerRefusesIsNotSentAgain() = runTest {
        val uploader = GameUploader(File(folder(), "u.json"))
        val games = record(2)
        assertEquals(1, uploader.flush(games) { if (it.id == games[1].id) GameUploadResult.REJECTED else GameUploadResult.SENT })
        assertTrue(uploader.pending(games).isEmpty())
    }

    @Test fun onlyTheNewestGamesAreConsideredAndOnePassIsBounded() = runTest {
        val uploader = GameUploader(File(folder(), "u.json"))
        val games = record(100)
        assertEquals(GameUploader.WINDOW, uploader.pending(games).size)
        assertEquals(games[GameUploader.WINDOW - 1].id, uploader.pending(games).first().id)
        var calls = 0
        assertEquals(GameUploader.PER_PASS, uploader.flush(games) { calls++; GameUploadResult.SENT })
        assertEquals(GameUploader.PER_PASS, calls)
        assertEquals(GameUploader.WINDOW - GameUploader.PER_PASS, uploader.pending(games).size)
    }

    @Test fun whatWasSentSurvivesARestart() = runTest {
        val file = File(folder(), "u.json")
        val games = record(3)
        GameUploader(file).flush(games) { GameUploadResult.SENT }
        val restarted = GameUploader(file)
        assertTrue(restarted.pending(games).isEmpty())
        assertEquals(1, restarted.pending(record(4)).size)
    }

    @Test fun aPassAlreadyRunningMakesAnotherOneANoOp() = runTest {
        val uploader = GameUploader(null)
        val games = record(2)
        var nested = -1
        uploader.flush(games) { nested = uploader.flush(games) { error("ran inside a running pass") }; GameUploadResult.SENT }
        assertEquals(0, nested)
    }
}
