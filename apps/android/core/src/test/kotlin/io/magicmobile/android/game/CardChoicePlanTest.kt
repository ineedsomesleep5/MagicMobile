package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of apps/ios/MagicMobileTests/CardChoicePlanTests.swift, case for case. */
class CardChoicePlanTest {
    private val player = "00000000-0000-0000-0000-000000000001"
    private val ids = (1..7).map { "10000000-0000-0000-0000-%012d".format(it) }

    private fun snapshot(message: String, revision: Int, candidates: List<String>, chosen: List<String>? = null, promptID: String = "prompt",
                         turn: Int = 1, done: Boolean = false, phase: String = "MAIN", activePlayerID: String? = null, step: String? = null): GameSnapshot {
        val options = buildJsonObject { if (chosen != null) put("chosenTargets", JsonArray(chosen.map(::JsonPrimitive))) }
        val cards = buildJsonArray {
            for (id in candidates) add(buildJsonObject {
                put("instanceId", id)
                put("card", buildJsonObject { put("name", "Card ${id.takeLast(2)}"); put("typeLine", "Creature") })
                put("selectable", true)
            })
        }
        val prompt = buildJsonObject {
            put("id", promptID); put("method", "game_get_choice"); put("messageId", revision); put("playerId", player)
            put("responseKind", "target"); put("message", message); put("responseCommand", buildJsonObject { put("type", "choose_target") })
            put("cards", cards); put("targets", JsonArray(emptyList())); put("options", options)
        }
        val actions = if (done) buildJsonArray {
            add(buildJsonObject {
                put("id", "done-$revision"); put("type", "answer_yes_no"); put("playerId", player); put("label", "Done")
                put("promptId", promptID); put("messageId", revision); put("confirmed", false)
            })
        } else JsonArray(emptyList())
        val root = LinkedHashMap<String, JsonElement>()
        root["id"] = JsonPrimitive("game"); root["phase"] = JsonPrimitive(phase); root["turn"] = JsonPrimitive(turn)
        root["players"] = JsonArray(emptyList()); root["log"] = JsonArray(emptyList()); root["legalActions"] = actions
        root["promptEnvelopeV2"] = prompt; root["viewerPlayerId"] = JsonPrimitive(player)
        if (activePlayerID != null) root["activePlayerId"] = JsonPrimitive(activePlayerID)
        if (step != null) root["step"] = JsonPrimitive(step)
        return EngineJson.format.decodeFromJsonElement(GameSnapshot.serializer(), JsonObject(root))
    }

    private fun plan(snapshot: GameSnapshot, selected: List<String>, top: List<String> = emptyList()) =
        CardChoicePlan(snapshot, snapshot.promptEnvelopeV2!!, selected, top)

    @Test fun commandFailureHandoffIgnoresStaleFallbackButRecognizesNewFailure() {
        val setup = CardChoiceCommandFailure.of("Old setup failure", CardChoiceCommandFailure.Source.SETUP)
        val session = CardChoiceCommandFailure.of("Old session failure", CardChoiceCommandFailure.Source.SESSION)
        assertFalse(CardChoiceCommandFailure.isNewFailure(setup, session))
        assertTrue(CardChoiceCommandFailure.isNewFailure(session, setup))
        assertTrue(CardChoiceCommandFailure.isNewFailure(session, CardChoiceCommandFailure.of("Old session failure", CardChoiceCommandFailure.Source.SETUP)))
        assertTrue(CardChoiceCommandFailure.isNewFailure(null, session))
        assertFalse(CardChoiceCommandFailure.isNewFailure(setup, null))
        assertFalse(CardChoiceCommandFailure.isNewFailure(setup, setup))
    }

    @Test fun selectionBoundsAndDraftToggle() {
        assertEquals(0, CardChoicePlan.selectionBounds("Select targets (selected 0 of 3)")?.first)
        assertEquals(3, CardChoicePlan.selectionBounds("Select targets (selected 2 of 6, min 3)")?.first)
        assertNull(CardChoicePlan.selectionBounds("Select up to one target"))
        assertNull(CardChoicePlan.selectionBounds("Select targets (selected 2, min 1)"))
        assertEquals(listOf(ids[1]), CardChoicePlan.toggled(listOf(ids[0], ids[1]), ids[0]))
        assertEquals(listOf(ids[1], ids[0]), CardChoicePlan.toggled(listOf(ids[1]), ids[0]))
    }

    @Test fun genericSingleTargetRemainsManual() {
        val single = snapshot("Select up to one target", 1, listOf(ids[0]), emptyList())
        assertFalse(CardChoicePlan.supportsDraft(single.promptEnvelopeV2!!))
    }

    @Test fun changedMaximumOrPhaseStopsBeforeNextResponse() {
        val first = snapshot("Choose (selected 0 of 6, min 2)", 1, ids, emptyList(), activePlayerID = player, step = "PRECOMBAT_MAIN")
        val changedBounds = plan(first, listOf(ids[0], ids[1]))
        assertEquals(listOf(ids[0]), changedBounds.next(first, false)?.targetIds)
        val larger = snapshot("Choose (selected 1 of 7, min 2)", 2, ids, listOf(ids[0]), activePlayerID = player, step = "PRECOMBAT_MAIN")
        assertNull(changedBounds.next(larger, false))
        assertTrue(changedBounds.stopped)

        val changedPhase = plan(first, listOf(ids[0], ids[1]))
        assertEquals(listOf(ids[0]), changedPhase.next(first, false)?.targetIds)
        val nextPhase = snapshot("Choose (selected 1 of 6, min 2)", 2, ids, listOf(ids[0]), phase = "COMBAT", activePlayerID = player, step = "BEGIN_COMBAT")
        assertNull(changedPhase.next(nextPhase, false))
        assertTrue(changedPhase.stopped)
    }

    @Test fun previouslyKnownPlayerOrStepDisappearingStopsBeforeNextResponse() {
        val first = snapshot("Choose (selected 0 of 6, min 2)", 1, ids, emptyList(), activePlayerID = player, step = "PRECOMBAT_MAIN")
        for ((active, step) in listOf<Pair<String?, String?>>(null to "PRECOMBAT_MAIN", player to null)) {
            val p = plan(first, listOf(ids[0], ids[1]))
            assertEquals(listOf(ids[0]), p.next(first, false)?.targetIds)
            val changed = snapshot("Choose (selected 1 of 6, min 2)", 2, ids, listOf(ids[0]), activePlayerID = active, step = step)
            assertNull(p.next(changed, false))
            assertTrue(p.stopped)
        }
    }

    @Test fun sixSelectionsRequireFreshMatchingPromptsAndDone() {
        val first = snapshot("Choose (selected 0 of 6, min 6)", 1, ids, emptyList())
        val p = plan(first, ids.take(6))
        for (count in 0 until 6) {
            val current = snapshot("Choose (selected $count of 6, min 6)", count + 1, ids, ids.take(count))
            assertEquals(listOf(ids[count]), p.next(current, false)?.targetIds)
            assertNull(p.next(current, false))
            assertNull(p.next(current, true))
        }
        val complete = snapshot("Choose (selected 6 of 6, min 6)", 7, ids, ids.take(6), done = true)
        assertEquals(false, p.next(complete, false)?.confirmed)
        assertNull(p.next(complete, false))
    }

    /** XMage's discard of 14: one card per prompt, and no Done step because min == max. */
    @Test fun fourteenDiscardsAnswerEachPromptInOrderWithoutDone() {
        val hand = (1..16).map { "20000000-0000-0000-0000-%012d".format(it) }
        val order = hand.shuffled().take(14)
        val first = snapshot("Select a card to discard (selected 0 of 14, min 14)", 1, hand, emptyList())
        val p = plan(first, order)
        for (count in 0 until 14) {
            val current = snapshot("Select a card to discard (selected $count of 14, min 14)", count + 1, hand, order.take(count))
            assertEquals("card ${count + 1} in the chosen order", listOf(order[count]), p.next(current, false)?.targetIds)
            assertNull("never answers the same prompt twice", p.next(current, false))
            assertFalse(p.stopped)
        }
    }

    @Test fun pendingClearWithUnchangedPromptRequiresManualReview() {
        val first = snapshot("Choose (selected 0 of 6, min 2)", 1, ids, emptyList())
        val p = plan(first, listOf(ids[0], ids[1]))
        assertFalse(p.submittedPromptIsUnchanged(first))
        assertEquals(listOf(ids[0]), p.next(first, false)?.targetIds)
        assertTrue(p.submittedPromptIsUnchanged(first))
        val refreshed = snapshot("Choose (selected 1 of 6, min 2)", 2, ids, listOf(ids[0]))
        assertFalse(p.submittedPromptIsUnchanged(refreshed))
    }

    @Test fun deselectionAndChangedContextStopSafely() {
        val first = snapshot("Choose (selected 2 of 3)", 1, ids, listOf(ids[0], ids[1]))
        val p = plan(first, listOf(ids[1]))
        assertEquals(listOf(ids[0]), p.next(first, false)?.targetIds)
        val wrong = snapshot("Choose something else", 2, ids, listOf(ids[1]))
        assertNull(p.next(wrong, false))
        assertTrue(p.stopped)
    }

    @Test fun scryBottomThenReversedTopOrderAndUnexpectedPromptStops() {
        val message = "Cards (scry): choose cards to put on the bottom of your library"
        val scry = snapshot(message, 1, ids.take(4), emptyList())
        val p = plan(scry, listOf(ids[1], ids[0]), listOf(ids[2], ids[3]))
        assertEquals(listOf(ids[1]), p.next(scry, false)?.targetIds)
        val second = snapshot(message, 2, ids.take(4), listOf(ids[1]))
        assertEquals(listOf(ids[0]), p.next(second, false)?.targetIds)
        val selected = snapshot(message, 3, ids.take(4), listOf(ids[1], ids[0]), done = true)
        assertEquals(false, p.next(selected, false)?.confirmed)
        val bottomMessage = "Select card order to put on bottom of your library (last one chosen will be bottommost)"
        assertEquals(listOf(ids[1]), p.next(snapshot(bottomMessage, 4, listOf(ids[0], ids[1])), false)?.targetIds)
        assertEquals(listOf(ids[0]), p.next(snapshot(bottomMessage, 5, listOf(ids[0])), false)?.targetIds)
        val topMessage = "Select card order to put on top of your library (last one chosen will be topmost)"
        assertEquals(listOf(ids[3]), p.next(snapshot(topMessage, 6, listOf(ids[2], ids[3])), false)?.targetIds)
        assertEquals(listOf(ids[2]), p.next(snapshot(topMessage, 7, listOf(ids[2])), false)?.targetIds)
    }

    @Test fun scryOneBottomSkipsBottomOrderAndZeroBottomStartsTop() {
        val message = "Cards (scry): choose cards to put on the bottom of your library"
        val topMessage = "Select card order to put on top of your library (last one chosen will be topmost)"
        val first = snapshot(message, 1, ids.take(4), emptyList())
        val one = plan(first, listOf(ids[0]), listOf(ids[1], ids[2], ids[3]))
        assertEquals(listOf(ids[0]), one.next(first, false)?.targetIds)
        assertEquals(false, one.next(snapshot(message, 2, ids.take(4), listOf(ids[0]), done = true), false)?.confirmed)
        assertEquals(listOf(ids[3]), one.next(snapshot(topMessage, 3, listOf(ids[1], ids[2], ids[3])), false)?.targetIds)
        assertEquals(listOf(ids[2]), one.next(snapshot(topMessage, 4, listOf(ids[1], ids[2])), false)?.targetIds)

        val zero = plan(first, emptyList(), ids.take(4))
        assertEquals(false, zero.next(snapshot(message, 1, ids.take(4), emptyList(), done = true), false)?.confirmed)
        assertEquals(listOf(ids[3]), zero.next(snapshot(topMessage, 2, ids.take(4)), false)?.targetIds)
    }

    @Test fun scryFiveThreeBottomAndAllBottom() {
        val message = "Cards (scry): choose cards to put on the bottom of your library"
        val bottomMessage = "Select card order to put on bottom of your library (last one chosen will be bottommost)"
        val topMessage = "Select card order to put on top of your library (last one chosen will be topmost)"
        val first = snapshot(message, 1, ids.take(5), emptyList())
        val p = plan(first, listOf(ids[0], ids[1], ids[2]), listOf(ids[3], ids[4]))
        for (count in 0 until 3) assertEquals(listOf(ids[count]), p.next(snapshot(message, count + 1, ids.take(5), ids.take(count)), false)?.targetIds)
        assertEquals(false, p.next(snapshot(message, 4, ids.take(5), ids.take(3), done = true), false)?.confirmed)
        assertEquals(listOf(ids[0]), p.next(snapshot(bottomMessage, 5, ids.take(3)), false)?.targetIds)
        assertEquals(listOf(ids[1]), p.next(snapshot(bottomMessage, 6, listOf(ids[1], ids[2])), false)?.targetIds)
        assertEquals(listOf(ids[4]), p.next(snapshot(topMessage, 7, listOf(ids[3], ids[4])), false)?.targetIds)

        val all = plan(first, ids.take(5), emptyList())
        for (count in 0 until 5) assertEquals(listOf(ids[count]), all.next(snapshot(message, count + 1, ids.take(5), ids.take(count)), false)?.targetIds)
        assertEquals(false, all.next(snapshot(message, 6, ids.take(5), ids.take(5), done = true), false)?.confirmed)
        assertEquals(listOf(ids[0]), all.next(snapshot(bottomMessage, 7, ids.take(5)), false)?.targetIds)
    }

    @Test fun genericTopOrderFourAndUnrelatedOrderContextStops() {
        val message = "Select card order to put on top of your library (last one chosen will be topmost)"
        val first = snapshot(message, 1, ids.take(4))
        val p = plan(first, ids.take(4))
        for (count in 0 until 4) assertEquals(listOf(ids[3 - count]), p.next(snapshot(message, count + 1, ids.take(4 - count)), false)?.targetIds)
        val unrelated = snapshot("$message for another effect", 5, listOf(ids[0]))
        assertNull(p.next(unrelated, false))
    }

    @Test fun stalePromptAndChangedTurnNeverRetry() {
        val first = snapshot("Choose", 1, ids, emptyList())
        val p = plan(first, listOf(ids[0]))
        assertEquals(listOf(ids[0]), p.next(first, false)?.targetIds)
        assertNull(p.next(first, false))
        val changed = snapshot("Choose", 2, ids, listOf(ids[0]), turn = 2)
        assertNull(p.next(changed, false))
        assertTrue(p.stopped)
    }
}
