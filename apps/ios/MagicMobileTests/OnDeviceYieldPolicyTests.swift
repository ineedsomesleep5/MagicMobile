import XCTest
import MagicMobileOnDevice
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

    private func situation(hasPlay: Bool, step: String? = "PRECOMBAT_MAIN", myTurn: Bool = true,
                           emptyStack: Bool = true) -> OnDeviceSmartPass.Situation {
        var value = context()
        value.activePlayerID = myTurn ? "viewer" : "other"; value.emptyStack = emptyStack
        return .init(context: value, step: step, hasPlay: hasPlay, manaFloating: false)
    }

    func testSmartPassPassesWithNothingToPlayAndStopsWhereMarked() {
        let settings = OnDeviceSmartPass.Settings()
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: false), settings: settings))
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: false, emptyStack: false), settings: settings))
        // Default stops: your main phases, their attacks and end step.
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true), settings: settings))
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "POSTCOMBAT_MAIN"), settings: settings))
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "END_TURN", myTurn: false), settings: settings))
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "DECLARE_ATTACKERS", myTurn: false), settings: settings))
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "UPKEEP"), settings: settings))
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "PRECOMBAT_MAIN", myTurn: false), settings: settings))
        // Something to answer on the stack always stops; an unknown step never passes a playable.
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "UPKEEP", emptyStack: false), settings: settings))
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "mystery"), settings: settings))
        var custom = settings; custom.stops = [OnDeviceSmartPass.stopKey(.upkeep, myTurn: true)]
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true, step: "UPKEEP"), settings: custom))
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: true), settings: custom))
    }

    /// Engine release A: your own spell or trigger on top resolves (unless you asked to stop for those); an opponent's
    /// stops only with a play that answers it; an attack with nothing that answers it passes even at a stop.
    func testSmartPassUsesStackControllersAndResponses() {
        let settings = OnDeviceSmartPass.Settings()
        func value(_ step: String = "UPKEEP", empty: Bool = false, mine: Bool?, response: Bool, myTurn: Bool = true) -> OnDeviceSmartPass.Situation {
            var v = situation(hasPlay: true, step: step, myTurn: myTurn, emptyStack: empty)
            v.topStackIsMine = mine; v.hasResponse = response
            return v
        }
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(value(mine: true, response: true), settings: settings), "own trigger resolves")
        var stopOwn = settings; stopOwn.stopForOwnSpells = true
        XCTAssertNil(OnDeviceSmartPass.passPrompt(value(mine: true, response: true), settings: stopOwn))
        XCTAssertNil(OnDeviceSmartPass.passPrompt(value(mine: false, response: true), settings: settings), "an answer to their spell stops")
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(value(mine: false, response: false), settings: settings), "nothing answers it")
        XCTAssertNil(OnDeviceSmartPass.passPrompt(value(mine: nil, response: true), settings: settings), "older engine: today's stop")
        // Their attack, a default stop: only a play that answers it stops.
        XCTAssertNil(OnDeviceSmartPass.passPrompt(value("DECLARE_ATTACKERS", empty: true, mine: nil, response: true, myTurn: false), settings: settings))
        XCTAssertNotNil(OnDeviceSmartPass.passPrompt(value("DECLARE_ATTACKERS", empty: true, mine: nil, response: false, myTurn: false), settings: settings))
        // Main phases keep their stops whatever the response flag says.
        XCTAssertNil(OnDeviceSmartPass.passPrompt(value("PRECOMBAT_MAIN", empty: true, mine: nil, response: false), settings: settings))
    }

    func testSmartPassReadsEngineControllersAndResponseFlags() {
        typealias J = MagicMobileOnDevice.JSONValue
        let root: J = .object(["stackOrder": .array([.string("s2"), .string("s1")]),
                               "stackControllers": .object(["s2": .string("viewer"), "s1": .string("other")])])
        XCTAssertEqual(OnDeviceSmartPass.topStackIsMine(root, viewer: "viewer"), true)
        XCTAssertEqual(OnDeviceSmartPass.topStackIsMine(root, viewer: "other"), false)
        XCTAssertNil(OnDeviceSmartPass.topStackIsMine(.object(["stackOrder": .array([.string("s2")])]), viewer: "viewer"))
        func view(_ rows: [J]) -> J { .object(["canPlayObjects": .object(["objects": .object(["c1": .object(["spells": .array(rows)])])])]) }
        XCTAssertFalse(OnDeviceSmartPass.hasResponse(view([.object(["respondsToStack": .bool(false)])])))
        XCTAssertTrue(OnDeviceSmartPass.hasResponse(view([.object(["respondsToStack": .bool(false)]), .object(["respondsToStack": .bool(true)])])))
        XCTAssertTrue(OnDeviceSmartPass.hasResponse(view([.object([:])])), "a missing flag counts as a response")
        XCTAssertFalse(OnDeviceSmartPass.hasResponse(view([.object(["manaAbility": .bool(true)])])), "mana abilities never count")
    }

    func testSmartPassNeverAnswersAChoiceFloatingManaOrWhenOff() {
        let settings = OnDeviceSmartPass.Settings()
        var value = situation(hasPlay: false)
        value.manaFloating = true
        XCTAssertNil(OnDeviceSmartPass.passPrompt(value, settings: settings))
        XCTAssertNil(OnDeviceSmartPass.passPrompt(situation(hasPlay: false), settings: .init(enabled: false)))
        let changes: [(inout OnDeviceYieldPolicy.Context) -> Void] = [
            { $0.prompt?.kind = "ASK" }, { $0.prompt?.selectMode = "attackers" }, { $0.prompt?.selectMode = "blockers" },
            { $0.prompt?.submitted = true }, { $0.prompt?.manaPlayerID = "other" }, { $0.prompt = nil },
            { $0.selfAuthority = false }, { $0.resyncRequired = true }, { $0.foreground = false },
            { $0.localHumanEnabled = false }, { $0.phase = "ended" }
        ]
        for change in changes {
            var value = situation(hasPlay: false)
            change(&value.context)
            XCTAssertNil(OnDeviceSmartPass.passPrompt(value, settings: settings))
        }
    }

    func testSmartPassReadsPlayablesAndStoredStops() {
        typealias J = MagicMobileOnDevice.JSONValue
        func view(_ category: String, _ row: [String: J]) -> J {
            .object(["canPlayObjects": .object(["objects": .object(["card": .object([category: .array([.object(row)])])])])])
        }
        XCTAssertFalse(OnDeviceSmartPass.hasPlay(nil))
        XCTAssertFalse(OnDeviceSmartPass.hasPlay(view("basicManaAbilities", ["id": .string("a")])))
        XCTAssertFalse(OnDeviceSmartPass.hasPlay(view("other", ["id": .string("a"), "manaAbility": .bool(true)])))
        XCTAssertTrue(OnDeviceSmartPass.hasPlay(view("other", ["id": .string("a")])))
        XCTAssertTrue(OnDeviceSmartPass.hasPlay(view("basicPlayAbilities", ["id": .string("a")])))
        XCTAssertEqual(OnDeviceSmartPass.Settings.decode(nil), OnDeviceSmartPass.defaultStops)
        XCTAssertEqual(OnDeviceSmartPass.Settings.decode(""), [])
        XCTAssertEqual(OnDeviceSmartPass.Settings.decode(OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops)),
                       OnDeviceSmartPass.defaultStops)
        for (raw, step) in [("UPKEEP", OnDeviceSmartPass.Step.upkeep), ("precombat-main", .main1), ("BEGIN_COMBAT", .beginCombat),
                            ("FIRST_COMBAT_DAMAGE", .combatDamage), ("END_TURN", .end), ("POSTCOMBAT_MAIN", .main2)] {
            XCTAssertEqual(OnDeviceSmartPass.Step(engine: raw), step, raw)
        }
        XCTAssertNil(OnDeviceSmartPass.Step(engine: "UNTAP"))
    }

    /// Passes the session sends for the player show no waiting pop-up; anything the player tapped still does.
    func testOnlyPassesSentForThePlayerCountAsAutomatic() {
        XCTAssertTrue(OnDeviceYieldPolicy.isAutomaticPass(actionID: OnDeviceYieldPolicy.smartPassActionPrefix + "p1"))
        XCTAssertTrue(OnDeviceYieldPolicy.isAutomaticPass(actionID: OnDeviceYieldPolicy.yieldPassActionPrefix + "p1"))
        for tapped in [nil, "pass_priority-p1", "cast-spell-42", "auto-ability-7", "starting-roll-p1"] {
            XCTAssertFalse(OnDeviceYieldPolicy.isAutomaticPass(actionID: tapped), String(describing: tapped))
        }
    }
}
