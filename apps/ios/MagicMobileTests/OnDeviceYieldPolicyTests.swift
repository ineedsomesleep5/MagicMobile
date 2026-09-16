import XCTest
@testable import MagicMobile

final class OnDeviceYieldPolicyTests: XCTestCase {
    private func context() -> OnDeviceYieldPolicy.Context {
        .init(matchID: "match", seatID: "seat", viewerID: "viewer", activePlayerID: "viewer", turn: 3,
              phase: "running", localHumanEnabled: true, foreground: true, emptyStack: true,
              selfAuthority: true, resyncRequired: false,
              prompt: .init(id: "prompt", revision: 10, kind: "SELECT", selectMode: "priority",
                            allowsBoolean: true, submitted: false, manaPlayerID: "viewer"))
    }

    func testOnlyOrdinarySelfPriorityCanStart() {
        XCTAssertTrue(OnDeviceYieldPolicy.canStart(context()))
        for kind in ["ASK", "PICK_TARGET", "AMOUNT", "MULTI_AMOUNT", "PLAY_MANA", "PLAY_X_MANA", "CHOOSE_CHOICE"] {
            var value = context(); value.prompt?.kind = kind
            XCTAssertFalse(OnDeviceYieldPolicy.canStart(value), kind)
        }
        for mode in ["attackers", "blockers", "unknown"] {
            var value = context(); value.prompt?.selectMode = mode
            XCTAssertFalse(OnDeviceYieldPolicy.canStart(value))
        }
        var value = context(); value.prompt?.allowsBoolean = false
        XCTAssertFalse(OnDeviceYieldPolicy.canStart(value))
        value = context(); value.prompt?.manaPlayerID = "other"
        XCTAssertFalse(OnDeviceYieldPolicy.canStart(value))
    }

    func testStopsForEverySafetyBoundary() {
        let changes: [(inout OnDeviceYieldPolicy.Context) -> Void] = [
            { $0.emptyStack = false }, { $0.selfAuthority = false }, { $0.resyncRequired = true },
            { $0.turn += 1 }, { $0.activePlayerID = "other" }, { $0.matchID = "other" },
            { $0.seatID = "other" }, { $0.viewerID = "other" }, { $0.foreground = false },
            { $0.localHumanEnabled = false }, { $0.phase = "failed" }, { $0.phase = "closed" },
            { $0.phase = "ended" }, { $0.prompt?.kind = "ASK" }, { $0.prompt?.selectMode = "attackers" },
            { $0.prompt?.selectMode = "blockers" }, { $0.prompt?.manaPlayerID = "other" }
        ]
        for change in changes {
            var policy = OnDeviceYieldPolicy()
            XCTAssertTrue(policy.start(context(), now: 0))
            var value = context(); change(&value)
            guard case .stop = policy.evaluate(value, now: 1) else { XCTFail("Unsafe continuation"); continue }
            XCTAssertFalse(policy.isActive)
        }
    }

    func testMissingSubmittedAndRepeatedPromptsNeverSendAgain() {
        var policy = OnDeviceYieldPolicy()
        XCTAssertTrue(policy.start(context(), now: 0))
        guard case .pass(let prompt) = policy.evaluate(context(), now: 1) else { return XCTFail() }
        policy.recordPass(prompt)
        XCTAssertEqual(policy.evaluate(context(), now: 2), .wait)
        var value = context(); value.prompt = nil
        XCTAssertEqual(policy.evaluate(value, now: 3), .wait)
        value = context(); value.prompt?.id = "next"; value.prompt?.revision = 11; value.prompt?.submitted = true
        XCTAssertEqual(policy.evaluate(value, now: 4), .wait)
        value.prompt?.submitted = false
        guard case .pass = policy.evaluate(value, now: 5) else { return XCTFail() }
        value.prompt?.revision = 9
        XCTAssertEqual(policy.evaluate(value, now: 6), .wait)
    }

    func testCancellationAndTimeBudgetRequireExplicitRestart() {
        var policy = OnDeviceYieldPolicy()
        XCTAssertTrue(policy.start(context(), now: 0))
        policy.stop()
        XCTAssertEqual(policy.evaluate(context(), now: 1), .wait)
        XCTAssertTrue(policy.start(context(), now: 2))
        XCTAssertEqual(policy.evaluate(context(), now: 62), .stop(.limit))
        XCTAssertFalse(policy.isActive)
    }

    func testPassBudgetBoundsRetainedIdentities() {
        var policy = OnDeviceYieldPolicy()
        XCTAssertTrue(policy.start(context(), now: 0))
        for index in 0..<64 {
            var value = context(); value.prompt?.id = "p-\(index)"; value.prompt?.revision = Int64(index + 10)
            guard case .pass(let prompt) = policy.evaluate(value, now: 1) else { return XCTFail() }
            policy.recordPass(prompt)
        }
        XCTAssertEqual(policy.evaluate(context(), now: 2), .stop(.limit))
    }

    func testExplicitModesAllowStackPriorityButNeverMandatoryAnswers() {
        for mode in [OnDeviceYieldPolicy.Mode.endTurnSkippingResponses, .untilMyTurn] {
            var value = context(); value.emptyStack = false
            XCTAssertFalse(OnDeviceYieldPolicy.canStart(value))
            var policy = OnDeviceYieldPolicy()
            XCTAssertTrue(policy.start(value, now: 0, mode: mode))
            XCTAssertEqual(policy.evaluate(value, now: 1), .pass(value.prompt!))
            for kind in ["ASK", "PICK_TARGET", "AMOUNT", "MULTI_AMOUNT", "PLAY_MANA", "PLAY_X_MANA", "CHOOSE_CHOICE"] {
                XCTAssertTrue(policy.start(value, now: 0, mode: mode))
                var mandatory = value; mandatory.prompt?.kind = kind
                XCTAssertFalse(OnDeviceYieldPolicy.canStart(mandatory, mode: mode))
                XCTAssertEqual(policy.evaluate(mandatory, now: 1), .stop(.decision))
                XCTAssertEqual(policy.evaluate(value, now: 2), .wait) // No implicit resume.
            }
            for selection in ["attackers", "blockers", "discard", "payment", "targets"] {
                XCTAssertTrue(policy.start(value, now: 0, mode: mode))
                var mandatory = value; mandatory.prompt?.selectMode = selection
                XCTAssertEqual(policy.evaluate(mandatory, now: 1), .stop(.decision))
            }
        }
    }

    func testUntilMyTurnCrossesOpponentsButStopsBeforeNextOwnPriority() {
        var policy = OnDeviceYieldPolicy()
        var value = context()
        XCTAssertTrue(policy.start(value, now: 0, mode: .untilMyTurn))
        XCTAssertEqual(policy.evaluate(value, now: 1), .pass(value.prompt!))
        for opponent in ["opponent2", "opponent3", "opponent4"] {
            value.turn += 1; value.activePlayerID = opponent; value.emptyStack = false
            XCTAssertEqual(policy.evaluate(value, now: 2), .pass(value.prompt!))
        }
        value.turn += 1; value.activePlayerID = value.viewerID
        XCTAssertEqual(policy.evaluate(value, now: 3), .stop(.turnChanged))
        // An extra own turn also terminates, without needing an observed opponent poll.
        XCTAssertTrue(policy.start(context(), now: 0, mode: .untilMyTurn))
        value = context(); value.turn += 1
        XCTAssertEqual(policy.evaluate(value, now: 1), .stop(.turnChanged))
    }

    func testUntilMyTurnCanArmWhileOpponentHasNoPrompt() {
        var value = context(); value.activePlayerID = "opponent"; value.prompt = nil
        var policy = OnDeviceYieldPolicy()
        XCTAssertTrue(policy.start(value, now: 0, mode: .untilMyTurn))
        XCTAssertEqual(policy.evaluate(value, now: 1), .wait)
        value.turn += 1; value.activePlayerID = value.viewerID
        XCTAssertEqual(policy.evaluate(value, now: 2), .stop(.turnChanged))
        XCTAssertFalse(OnDeviceYieldPolicy.canStart(value, mode: .endTurnSkippingResponses))
    }

    func testAggressiveModesKeepAuthorityCancellationAndExplicitBudgets() {
        for mode in [OnDeviceYieldPolicy.Mode.endTurnSkippingResponses, .untilMyTurn] {
            var policy = OnDeviceYieldPolicy()
            XCTAssertTrue(policy.start(context(), now: 0, mode: mode))
            XCTAssertEqual(policy.evaluate(context(), now: mode.duration), .stop(.limit))
            let changes: [(inout OnDeviceYieldPolicy.Context) -> Void] = [
                { $0.selfAuthority = false }, { $0.foreground = false }, { $0.resyncRequired = true },
                { $0.localHumanEnabled = false }, { $0.phase = "failed" }, { $0.seatID = "other" },
                { $0.prompt?.manaPlayerID = "other" }
            ]
            for change in changes {
                XCTAssertTrue(policy.start(context(), now: 0, mode: mode))
                var value = context(); change(&value)
                guard case .stop = policy.evaluate(value, now: 1) else { XCTFail(); continue }
            }
            XCTAssertTrue(policy.start(context(), now: 0, mode: mode))
            for index in 0..<256 {
                var value = context(); value.prompt?.id = "p-\(index)"; value.prompt?.revision = Int64(index + 10)
                XCTAssertEqual(policy.evaluate(value, now: 1), .pass(value.prompt!))
                policy.recordPass(value.prompt!)
                if index < 255 { XCTAssertEqual(policy.evaluate(value, now: 1), .wait) }
            }
            XCTAssertEqual(policy.evaluate(context(), now: 2), .stop(.limit))
            XCTAssertTrue(policy.start(context(), now: 0, mode: mode))
            policy.stop()
            XCTAssertEqual(policy.evaluate(context(), now: 1), .wait)
        }
    }

    func testEndTurnSkippingStopsAtFirstTurnTransition() {
        var policy = OnDeviceYieldPolicy()
        XCTAssertTrue(policy.start(context(), now: 0, mode: .endTurnSkippingResponses))
        var value = context(); value.turn += 1; value.activePlayerID = "opponent"
        XCTAssertEqual(policy.evaluate(value, now: 1), .stop(.turnChanged))
    }
}
