package io.magicmobile.android.studio

import io.magicmobile.android.core.PrintingIndex
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.J
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** The Play controller's visible phases: Checking, then a pass selects the source deck; Cancel and failures never do. */
class DeckStudioPlaySelectionControllerTest {
    private val upstream = "a".repeat(40)
    private val catalogue = "c".repeat(64)
    private val resolver = OnDeviceDeckResolver(PrintingIndex(("#\t$catalogue\t$upstream\n" +
        "Sol Ring\tC21\t263\nForest\tM21\t274\nKardur, Doomscourge\tKHC\t10\n").byteInputStream()))
    private val deck = DeckList("Kardur", DeckEntry("Kardur, Doomscourge", 1, "commander"),
        listOf(DeckEntry("Sol Ring", 1, "deck"), DeckEntry("Forest", 30, "deck"), DeckEntry("Forest", 2, "sideboard")))

    private fun store() = DeckStudioReceiptStore(File(Files.createTempDirectory("play-controller").toFile(), "results-v1.json"))

    private fun passed(request: J) = DeckStudioValidationReceipt.success(
        JsonObject(mapOf("valid" to JsonPrimitive(true), "validator" to JsonPrimitive("Commander"), "upstream" to JsonPrimitive(upstream),
            "catalogueHash" to JsonPrimitive(catalogue), "issues" to JsonArray(emptyList()))),
        String(EngineJson.encode(request), Charsets.UTF_8), upstream, catalogue, "10")

    @Test fun aPassSelectsTheSourceDeckAfterChecking() = runBlocking {
        val gate = CompletableDeferred<Unit>()
        var checks = 0
        val selected = ArrayList<String>()
        val flow = DeckStudioPlayFlow(store(), "10") { request, _ -> checks += 1; gate.await(); passed(request) }
        val selection = DeckStudioPlaySelection(this, gameLive = { false }, select = { selected += it }, selectedID = { "precon:token-triumph" }, flow = flow)
        selection.play(DeckStudioPlaySelection.source("local:1", deck), resolver)
        assertEquals(DeckStudioPlaySelection.Phase.Checking("Kardur"), selection.phase)
        selection.play(DeckStudioPlaySelection.source("local:2", deck), resolver)
        yield()
        assertEquals(1, checks)
        assertTrue(selected.isEmpty())
        gate.complete(Unit)
        while (selection.checking) yield()
        assertEquals(listOf("local:1"), selected)
        assertEquals(DeckStudioPlaySelection.Phase.Finished(DeckStudioPlayFlow.Outcome.Playing("local:1", "Kardur", 2, checkedNow = true)), selection.phase)
        selection.dismiss()
        assertEquals(DeckStudioPlaySelection.Phase.Idle, selection.phase)
    }

    @Test fun cancelAndALiveGameLeaveThePlayingDeckAlone() = runBlocking {
        val selected = ArrayList<String>()
        val never = CompletableDeferred<Unit>()
        var live = false
        val flow = DeckStudioPlayFlow(store(), "10") { request, _ -> never.await(); passed(request) }
        val selection = DeckStudioPlaySelection(this, gameLive = { live }, select = { selected += it }, selectedID = { "local:1" }, flow = flow)
        selection.play(DeckStudioPlaySelection.source("local:1", deck), resolver)
        yield()
        assertTrue(selection.checking)
        selection.cancel()
        yield()
        assertEquals(DeckStudioPlaySelection.Phase.Idle, selection.phase)
        live = true
        selection.play(DeckStudioPlaySelection.source("local:1", deck), resolver)
        assertEquals(DeckStudioPlaySelection.Phase.Finished(DeckStudioPlayFlow.Outcome.GameLive), selection.phase)
        assertFalse(selection.checking)
        assertTrue(selected.isEmpty())
    }
}
