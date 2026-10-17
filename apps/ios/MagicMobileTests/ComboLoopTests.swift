import XCTest
@testable import MagicMobile

/// The combo loop shortcut (ComboLoop.swift). Android's ComboLoopTest reads the same parity/combo-loop-cases.json.
final class ComboLoopTests: XCTestCase {
    private func step(_ code: String) -> ComboStep {
        let parts = code.components(separatedBy: "|")
        return ComboStep(kind: ComboStep.Kind(rawValue: parts[0])!, type: parts[1], source: parts[2].isEmpty ? nil : parts[2], label: parts[3],
                         targets: parts[4].isEmpty ? [] : parts[4].components(separatedBy: ","))
    }

    func testSharedCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/core/src/test/resources/parity/combo-loop-cases.json").standardizedFileURL
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let steps = (json["steps"] as! [String: String]).mapValues(step)
        for item in json["cases"] as! [[String: Any]] {
            let history = (item["history"] as! String).map { steps[String($0)]! }
            XCTAssertEqual(ComboLoop.cycle(in: history)?.count ?? 0, item["expected"] as! Int, item["name"] as! String)
        }
    }

    // A small game: you have Ashnod's Altar and two Squirrels; the opponent has 12 life.
    private func snapshot(prompt: Bool = false, altarAction: Bool = true, opponentStack: Bool = false, opponentLife: Int = 12) throws -> GameSnapshot {
        func card(_ id: String, _ name: String) -> [String: Any] { ["instanceId": id, "card": ["name": name, "typeLine": "Artifact", "oracleText": NSNull()]] }
        func zones(_ battlefield: [[String: Any]], stack: [[String: Any]] = []) -> [String: Any] {
            ["library": [], "hand": [], "battlefield": battlefield, "graveyard": [], "exile": [], "command": [], "stack": stack]
        }
        var root: [String: Any] = [
            "id": "game-1", "phase": "main1", "turn": 4, "log": [], "viewerPlayerId": "me", "bridgeRevision": 7,
            "players": [
                ["playerId": "me", "displayName": "Caleb", "life": 20, "poison": 0, "commanderTax": 0,
                 "zones": zones([card("altar-1", "Ashnod's Altar"), card("sq-9", "Squirrel"), card("sq-10", "Squirrel")])],
                ["playerId": "ai", "displayName": "Tavern AI", "life": opponentLife, "poison": 0, "commanderTax": 0,
                 "zones": zones([], stack: opponentStack ? [card("bolt-1", "Lightning Bolt")] : [])],
            ],
        ]
        if altarAction {
            root["legalActions"] = [["id": "act-77", "type": "activate_ability", "playerId": "me", "label": "Sacrifice a creature: Add {C}{C}.",
                                     "sourceInstanceId": "altar-1", "abilityId": "ab-1", "promptId": "p-1", "messageId": 3]]
        }
        if prompt {
            root["promptEnvelopeV2"] = ["id": "p-2", "method": "GAME_TARGET", "messageId": 4, "playerId": "me", "responseKind": "target",
                                        "message": "Sacrifice a creature", "targets": [["id": "sq-10", "label": "Squirrel"], ["id": "altar-1", "label": "Ashnod's Altar"]],
                                        "responseCommand": ["type": "choose_target", "promptId": "p-2", "messageId": 4]]
        }
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
    }

    func testStepsAreKeptByNameAndReplayedWithTodaysIDs() throws {
        let decision = try snapshot()
        let activate = GameCommand(action: decision.legalActions![0], gameId: "game-1", bridgeRevision: 7)
        let step = try XCTUnwrap(ComboLoop.step(command: activate, label: "Sacrifice a creature: Add {C}{C}.", actionID: "act-77", snapshot: decision))
        XCTAssertEqual(step.kind, .action)
        XCTAssertEqual(step.source, "Ashnod's Altar")
        XCTAssertEqual(step.label, "sacrifice a creature: add {c}{c}.")
        let replay = try XCTUnwrap(ComboLoop.command(for: step, in: decision))
        XCTAssertEqual(replay.command.sourceInstanceId, "altar-1")
        XCTAssertEqual(replay.actionID, "act-77")

        // The target prompt: chosen by name, replayed against a different Squirrel.
        let asked = try snapshot(prompt: true)
        let pick = GameCommand(type: "choose_target", gameId: "game-1", playerId: "me", promptId: "p-2", messageId: 4, targetIds: ["sq-10"])
        let target = try XCTUnwrap(ComboLoop.step(command: pick, label: "Squirrel", actionID: "target-x", snapshot: asked))
        XCTAssertEqual(target.kind, .prompt)
        XCTAssertEqual(target.targets, ["Squirrel"])
        let again = try XCTUnwrap(ComboLoop.command(for: target, in: asked))
        XCTAssertEqual(again.command.type, "choose_target")
        XCTAssertEqual(again.command.targetIds, ["sq-10"])
        // No Squirrel offered: the step isn't available.
        let other = ComboStep(kind: .prompt, type: "choose_target", source: nil, label: "GAME_TARGET", targets: ["Goblin"])
        XCTAssertNil(ComboLoop.command(for: other, in: asked))
        XCTAssertNil(ComboLoop.command(for: step, in: try snapshot(altarAction: false)), "the altar's ability isn't offered")
    }

    func testDigestOpponentResponseAndSummary() throws {
        let before = try snapshot()
        XCTAssertFalse(ComboLoop.opponentResponded(before))
        XCTAssertTrue(ComboLoop.opponentResponded(try snapshot(opponentStack: true)))
        let after = try snapshot(opponentLife: 0)
        XCTAssertNotEqual(ComboLoop.digest(before), ComboLoop.digest(after))
        XCTAssertEqual(ComboLoop.digest(before), ComboLoop.digest(try snapshot()))
        XCTAssertEqual(ComboLoop.summary(rounds: 12, before: before, after: after), "Repeated 12 times · Tavern AI 12 → 0")
        XCTAssertEqual(ComboLoop.describe([ComboStep(kind: .action, type: "activate_ability", source: "Ashnod's Altar", label: "x")]), "Activate Ashnod's Altar")
    }
}
