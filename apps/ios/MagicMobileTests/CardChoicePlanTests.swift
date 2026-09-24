import XCTest
@testable import MagicMobile

final class CardChoicePlanTests: XCTestCase {
    private let player = "00000000-0000-0000-0000-000000000001"
    private let ids = (1...7).map { String(format: "10000000-0000-0000-0000-%012d", $0) }

    func testCommandFailureHandoffIgnoresStaleFallbackButRecognizesNewFailure() {
        let setup = CardChoiceCommandFailure("Old setup failure", source: .setup)
        let session = CardChoiceCommandFailure("Old session failure", source: .session)
        XCTAssertFalse(CardChoiceCommandFailure.isNewFailure(from: setup, to: session))
        XCTAssertTrue(CardChoiceCommandFailure.isNewFailure(from: session, to: setup))
        XCTAssertTrue(CardChoiceCommandFailure.isNewFailure(
            from: session, to: CardChoiceCommandFailure("Old session failure", source: .setup)))
        XCTAssertTrue(CardChoiceCommandFailure.isNewFailure(from: nil, to: session))
        XCTAssertFalse(CardChoiceCommandFailure.isNewFailure(from: setup, to: nil))
        XCTAssertFalse(CardChoiceCommandFailure.isNewFailure(from: setup, to: setup))
    }

    func testSelectionBoundsAndDraftToggle() {
        XCTAssertEqual(CardChoicePlan.selectionBounds("Select targets (selected 0 of 3)")?.0, 0)
        XCTAssertEqual(CardChoicePlan.selectionBounds("Select targets (selected 2 of 6, min 3)")?.0, 3)
        XCTAssertNil(CardChoicePlan.selectionBounds("Select up to one target"))
        XCTAssertNil(CardChoicePlan.selectionBounds("Select targets (selected 2, min 1)"))
        XCTAssertEqual(CardChoicePlan.toggled([ids[0], ids[1]], id: ids[0]), [ids[1]])
        XCTAssertEqual(CardChoicePlan.toggled([ids[1]], id: ids[0]), [ids[1], ids[0]])
    }

    func testGenericSingleTargetRemainsManual() throws {
        let single = try snapshot(message: "Select up to one target", revision: 1,
                                  candidates: [ids[0]], chosen: [])
        XCTAssertFalse(CardChoicePlan.supportsDraft(try XCTUnwrap(single.promptEnvelopeV2)))
    }

    private func snapshot(message: String, revision: Int, candidates: [String], chosen: [String]? = nil,
                          promptID: String = "prompt", turn: Int = 1, done: Bool = false,
                          phase: String = "MAIN", activePlayerID: String? = nil, step: String? = nil) throws -> GameSnapshot {
        var options: [String: Any] = [:]
        if let chosen { options["chosenTargets"] = chosen }
        let cards = candidates.map { id in
            ["instanceId": id, "card": ["name": "Card \(id.suffix(2))", "typeLine": "Creature"],
             "selectable": true] as [String: Any]
        }
        let prompt: [String: Any] = [
            "id": promptID, "method": "game_get_choice", "messageId": revision, "playerId": player,
            "responseKind": "target", "message": message, "responseCommand": ["type": "choose_target"],
            "cards": cards, "targets": [], "options": options
        ]
        let actions: [[String: Any]] = done ? [[
            "id": "done-\(revision)", "type": "answer_yes_no", "playerId": player, "label": "Done",
            "promptId": promptID, "messageId": revision, "confirmed": false
        ]] : []
        var root: [String: Any] = [
            "id": "game", "phase": phase, "turn": turn, "players": [], "log": [],
            "legalActions": actions, "promptEnvelopeV2": prompt, "viewerPlayerId": player
        ]
        if let activePlayerID { root["activePlayerId"] = activePlayerID }
        if let step { root["step"] = step }
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
    }

    func testChangedMaximumOrPhaseStopsBeforeNextResponse() throws {
        let first = try snapshot(message: "Choose (selected 0 of 6, min 2)", revision: 1,
                                 candidates: ids, chosen: [], activePlayerID: player, step: "PRECOMBAT_MAIN")
        var changedBounds = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                           selected: [ids[0], ids[1]])
        XCTAssertEqual(changedBounds.next(in: first, pending: false)?.targetIds, [ids[0]])
        let largerMaximum = try snapshot(message: "Choose (selected 1 of 7, min 2)", revision: 2,
                                         candidates: ids, chosen: [ids[0]], activePlayerID: player,
                                         step: "PRECOMBAT_MAIN")
        XCTAssertNil(changedBounds.next(in: largerMaximum, pending: false))
        XCTAssertTrue(changedBounds.stopped)

        var changedPhase = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                          selected: [ids[0], ids[1]])
        XCTAssertEqual(changedPhase.next(in: first, pending: false)?.targetIds, [ids[0]])
        let nextPhase = try snapshot(message: "Choose (selected 1 of 6, min 2)", revision: 2,
                                     candidates: ids, chosen: [ids[0]], phase: "COMBAT",
                                     activePlayerID: player, step: "BEGIN_COMBAT")
        XCTAssertNil(changedPhase.next(in: nextPhase, pending: false))
        XCTAssertTrue(changedPhase.stopped)
    }

    func testPreviouslyKnownPlayerOrStepDisappearingStopsBeforeNextResponse() throws {
        let first = try snapshot(message: "Choose (selected 0 of 6, min 2)", revision: 1,
                                 candidates: ids, chosen: [], activePlayerID: player, step: "PRECOMBAT_MAIN")
        for (activePlayerID, step) in [(nil, "PRECOMBAT_MAIN"), (player, nil)] as [(String?, String?)] {
            var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                      selected: [ids[0], ids[1]])
            XCTAssertEqual(plan.next(in: first, pending: false)?.targetIds, [ids[0]])
            let changed = try snapshot(message: "Choose (selected 1 of 6, min 2)", revision: 2,
                                       candidates: ids, chosen: [ids[0]],
                                       activePlayerID: activePlayerID, step: step)
            XCTAssertNil(plan.next(in: changed, pending: false))
            XCTAssertTrue(plan.stopped)
        }
    }

    func testSixSelectionsRequireFreshMatchingPromptsAndDone() throws {
        let first = try snapshot(message: "Choose (selected 0 of 6, min 6)", revision: 1, candidates: ids, chosen: [])
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2), selected: Array(ids.prefix(6)))
        for count in 0..<6 {
            let current = try snapshot(message: "Choose (selected \(count) of 6, min 6)",
                                       revision: count + 1, candidates: ids, chosen: Array(ids.prefix(count)))
            XCTAssertEqual(plan.next(in: current, pending: false)?.targetIds, [ids[count]])
            XCTAssertNil(plan.next(in: current, pending: false))
            XCTAssertNil(plan.next(in: current, pending: true))
        }
        let complete = try snapshot(message: "Choose (selected 6 of 6, min 6)",
                                    revision: 7, candidates: ids, chosen: Array(ids.prefix(6)), done: true)
        XCTAssertEqual(plan.next(in: complete, pending: false)?.confirmed, false)
        XCTAssertNil(plan.next(in: complete, pending: false))
    }

    /// XMage's discard of 14: one card per prompt, and no Done step because min == max.
    func testFourteenDiscardsAnswerEachPromptInOrderWithoutDone() throws {
        let hand = (1...16).map { String(format: "20000000-0000-0000-0000-%012d", $0) }
        let order = Array(hand.shuffled().prefix(14))
        let first = try snapshot(message: "Select a card to discard (selected 0 of 14, min 14)", revision: 1, candidates: hand, chosen: [])
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2), selected: order)
        for count in 0..<14 {
            let current = try snapshot(message: "Select a card to discard (selected \(count) of 14, min 14)",
                                       revision: count + 1, candidates: hand, chosen: Array(order.prefix(count)))
            XCTAssertEqual(plan.next(in: current, pending: false)?.targetIds, [order[count]], "card \(count + 1) in the chosen order")
            XCTAssertNil(plan.next(in: current, pending: false), "never answers the same prompt twice")
            XCTAssertFalse(plan.stopped)
        }
    }

    func testPendingClearWithUnchangedPromptRequiresManualReview() throws {
        let first = try snapshot(message: "Choose (selected 0 of 6, min 2)", revision: 1,
                                 candidates: ids, chosen: [])
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                  selected: [ids[0], ids[1]])
        XCTAssertFalse(plan.submittedPromptIsUnchanged(in: first))
        XCTAssertEqual(plan.next(in: first, pending: false)?.targetIds, [ids[0]])
        XCTAssertTrue(plan.submittedPromptIsUnchanged(in: first))
        let refreshed = try snapshot(message: "Choose (selected 1 of 6, min 2)", revision: 2,
                                     candidates: ids, chosen: [ids[0]])
        XCTAssertFalse(plan.submittedPromptIsUnchanged(in: refreshed))
    }

    func testDeselectionAndChangedContextStopSafely() throws {
        let first = try snapshot(message: "Choose (selected 2 of 3)", revision: 1,
                                 candidates: ids, chosen: [ids[0], ids[1]])
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2), selected: [ids[1]])
        XCTAssertEqual(plan.next(in: first, pending: false)?.targetIds, [ids[0]])
        let wrong = try snapshot(message: "Choose something else", revision: 2, candidates: ids, chosen: [ids[1]])
        XCTAssertNil(plan.next(in: wrong, pending: false))
        XCTAssertTrue(plan.stopped)
    }

    func testScryBottomThenReversedTopOrderAndUnexpectedPromptStops() throws {
        let scry = try snapshot(message: "Cards (scry): choose cards to put on the bottom of your library",
                                revision: 1, candidates: Array(ids.prefix(4)), chosen: [])
        var plan = CardChoicePlan(snapshot: scry, prompt: try XCTUnwrap(scry.promptEnvelopeV2),
                                  selected: [ids[1], ids[0]], top: [ids[2], ids[3]])
        XCTAssertEqual(plan.next(in: scry, pending: false)?.targetIds, [ids[1]])
        let second = try snapshot(message: scry.promptEnvelopeV2!.message, revision: 2,
                                  candidates: Array(ids.prefix(4)), chosen: [ids[1]])
        XCTAssertEqual(plan.next(in: second, pending: false)?.targetIds, [ids[0]])
        let selected = try snapshot(message: scry.promptEnvelopeV2!.message, revision: 3,
                                    candidates: Array(ids.prefix(4)), chosen: [ids[1], ids[0]], done: true)
        XCTAssertEqual(plan.next(in: selected, pending: false)?.confirmed, false)
        let bottom = try snapshot(message: "Select card order to put on bottom of your library (last one chosen will be bottommost)",
                                  revision: 4, candidates: [ids[0], ids[1]])
        XCTAssertEqual(plan.next(in: bottom, pending: false)?.targetIds, [ids[1]])
        let bottomLast = try snapshot(message: bottom.promptEnvelopeV2!.message, revision: 5, candidates: [ids[0]])
        XCTAssertEqual(plan.next(in: bottomLast, pending: false)?.targetIds, [ids[0]])
        let top = try snapshot(message: "Select card order to put on top of your library (last one chosen will be topmost)",
                               revision: 6, candidates: [ids[2], ids[3]])
        XCTAssertEqual(plan.next(in: top, pending: false)?.targetIds, [ids[3]])
        let topLast = try snapshot(message: top.promptEnvelopeV2!.message, revision: 7, candidates: [ids[2]])
        XCTAssertEqual(plan.next(in: topLast, pending: false)?.targetIds, [ids[2]])
    }

    func testScryOneBottomSkipsBottomOrderAndZeroBottomStartsTop() throws {
        let message = "Cards (scry): choose cards to put on the bottom of your library"
        let topMessage = "Select card order to put on top of your library (last one chosen will be topmost)"
        let first = try snapshot(message: message, revision: 1, candidates: Array(ids.prefix(4)), chosen: [])
        var one = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                 selected: [ids[0]], top: [ids[1], ids[2], ids[3]])
        XCTAssertEqual(one.next(in: first, pending: false)?.targetIds, [ids[0]])
        let done = try snapshot(message: message, revision: 2, candidates: Array(ids.prefix(4)),
                                chosen: [ids[0]], done: true)
        XCTAssertEqual(one.next(in: done, pending: false)?.confirmed, false)
        let top = try snapshot(message: topMessage, revision: 3, candidates: [ids[1], ids[2], ids[3]])
        XCTAssertEqual(one.next(in: top, pending: false)?.targetIds, [ids[3]])
        XCTAssertEqual(one.next(in: try snapshot(message: topMessage, revision: 4, candidates: [ids[1], ids[2]]),
                                pending: false)?.targetIds, [ids[2]])

        var zero = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                  selected: [], top: Array(ids.prefix(4)))
        let firstDone = try snapshot(message: message, revision: 1, candidates: Array(ids.prefix(4)),
                                     chosen: [], done: true)
        XCTAssertEqual(zero.next(in: firstDone, pending: false)?.confirmed, false)
        let allTop = try snapshot(message: topMessage, revision: 2, candidates: Array(ids.prefix(4)))
        XCTAssertEqual(zero.next(in: allTop, pending: false)?.targetIds, [ids[3]])
    }

    func testScryFiveThreeBottomAndAllBottom() throws {
        let message = "Cards (scry): choose cards to put on the bottom of your library"
        let bottomMessage = "Select card order to put on bottom of your library (last one chosen will be bottommost)"
        let first = try snapshot(message: message, revision: 1, candidates: Array(ids.prefix(5)), chosen: [])
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                  selected: [ids[0], ids[1], ids[2]], top: [ids[3], ids[4]])
        for count in 0..<3 {
            let step = try snapshot(message: message, revision: count + 1,
                                    candidates: Array(ids.prefix(5)), chosen: Array(ids.prefix(count)))
            XCTAssertEqual(plan.next(in: step, pending: false)?.targetIds, [ids[count]])
        }
        let ready = try snapshot(message: message, revision: 4, candidates: Array(ids.prefix(5)),
                                 chosen: Array(ids.prefix(3)), done: true)
        XCTAssertEqual(plan.next(in: ready, pending: false)?.confirmed, false)
        XCTAssertEqual(plan.next(in: try snapshot(message: bottomMessage, revision: 5, candidates: Array(ids.prefix(3))),
                                pending: false)?.targetIds, [ids[0]])
        XCTAssertEqual(plan.next(in: try snapshot(message: bottomMessage, revision: 6, candidates: [ids[1], ids[2]]),
                                pending: false)?.targetIds, [ids[1]])
        let topMessage = "Select card order to put on top of your library (last one chosen will be topmost)"
        XCTAssertEqual(plan.next(in: try snapshot(message: topMessage, revision: 7, candidates: [ids[3], ids[4]]),
                                pending: false)?.targetIds, [ids[4]])

        var all = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                 selected: Array(ids.prefix(5)), top: [])
        for count in 0..<5 {
            let step = try snapshot(message: message, revision: count + 1,
                                    candidates: Array(ids.prefix(5)), chosen: Array(ids.prefix(count)))
            XCTAssertEqual(all.next(in: step, pending: false)?.targetIds, [ids[count]])
        }
        let allReady = try snapshot(message: message, revision: 6, candidates: Array(ids.prefix(5)),
                                    chosen: Array(ids.prefix(5)), done: true)
        XCTAssertEqual(all.next(in: allReady, pending: false)?.confirmed, false)
        XCTAssertEqual(all.next(in: try snapshot(message: bottomMessage, revision: 7, candidates: Array(ids.prefix(5))),
                                pending: false)?.targetIds, [ids[0]])
    }

    func testGenericTopOrderFourAndUnrelatedOrderContextStops() throws {
        let message = "Select card order to put on top of your library (last one chosen will be topmost)"
        let first = try snapshot(message: message, revision: 1, candidates: Array(ids.prefix(4)))
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2),
                                  selected: Array(ids.prefix(4)))
        for count in 0..<4 {
            let step = try snapshot(message: message, revision: count + 1,
                                    candidates: Array(ids.prefix(4 - count)))
            XCTAssertEqual(plan.next(in: step, pending: false)?.targetIds, [ids[3 - count]])
        }
        let unrelated = try snapshot(message: "Select card order to put on top of your library (last one chosen will be topmost) for another effect",
                                     revision: 5, candidates: [ids[0]])
        XCTAssertNil(plan.next(in: unrelated, pending: false))
    }

    func testStalePromptAndChangedTurnNeverRetry() throws {
        let first = try snapshot(message: "Choose", revision: 1, candidates: ids, chosen: [])
        var plan = CardChoicePlan(snapshot: first, prompt: try XCTUnwrap(first.promptEnvelopeV2), selected: [ids[0]])
        XCTAssertEqual(plan.next(in: first, pending: false)?.targetIds, [ids[0]])
        XCTAssertNil(plan.next(in: first, pending: false))
        let changed = try snapshot(message: "Choose", revision: 2, candidates: ids, chosen: [ids[0]], turn: 2)
        XCTAssertNil(plan.next(in: changed, pending: false))
        XCTAssertTrue(plan.stopped)
    }
}
