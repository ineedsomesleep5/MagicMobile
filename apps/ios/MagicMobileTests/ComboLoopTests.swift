import XCTest
@testable import MagicMobile

/// The combo loop shortcut (ComboLoop.swift). Android's ComboLoopTest reads the same parity/combo-loop-cases.json.
final class ComboLoopTests: XCTestCase {
    private func target(_ code: String) -> ComboTarget {
        let parts = code.components(separatedBy: "@")
        guard parts.count == 2 else { return ComboTarget(name: code) }
        let detail = parts[1].components(separatedBy: "/")
        return ComboTarget(name: parts[0], controller: detail[0], kind: detail[1], token: detail[2] == "token")
    }

    private func step(_ code: String) -> ComboStep {
        let parts = code.components(separatedBy: "|")
        return ComboStep(kind: ComboStep.Kind(rawValue: parts[0])!, type: parts[1], source: parts[2].isEmpty ? nil : parts[2], label: parts[3],
                         targets: parts[4].isEmpty ? [] : parts[4].components(separatedBy: ";").map(target))
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

    // A small game: Chatterfang, a Treasure and two Squirrel tokens; the opponent has two creatures and 12 life.
    private func snapshot(prompt: Bool = false, callerAlive: Bool = true, chatterfangAction: Bool = true, ownTrigger: Bool = false,
                          opponentStack: Bool = false, opponentLife: Int = 12, callerToughness: Int = 3, passOffered: Bool = false) throws -> GameSnapshot {
        func card(_ id: String, _ name: String, _ type: String, token: Bool = false, toughness: Int? = nil) -> [String: Any] {
            var identity: [String: Any] = ["name": name, "typeLine": type, "oracleText": NSNull()]
            if token { identity["isToken"] = true }
            var card: [String: Any] = ["instanceId": id, "card": identity]
            if let toughness { card["toughness"] = toughness; card["power"] = 1 }
            return card
        }
        func zones(_ battlefield: [[String: Any]], stack: [[String: Any]] = []) -> [String: Any] {
            ["library": [], "hand": [], "battlefield": battlefield, "graveyard": [], "exile": [], "command": [], "stack": stack]
        }
        var theirs = [card("zac-1", "Zacama, Primal Calamity", "Legendary Creature — Elder Dinosaur", toughness: 4)]
        if callerAlive { theirs.insert(card("cal-1", "Kinjalli's Caller", "Creature — Human Cleric", toughness: callerToughness), at: 0) }
        var root: [String: Any] = [
            "id": "game-1", "phase": "main1", "turn": 15, "log": [], "viewerPlayerId": "me", "bridgeRevision": 7,
            "players": [
                ["playerId": "me", "displayName": "Caleb", "life": 20, "poison": 0, "commanderTax": 0,
                 "zones": zones([card("chat-1", "Chatterfang, Squirrel General", "Legendary Creature — Squirrel Warrior"),
                                 card("tr-1", "Treasure Token", "Token Artifact — Treasure", token: true),
                                 card("sq-9", "Squirrel Token", "Token Creature — Squirrel", token: true),
                                 card("sov-1", "Squirrel Sovereign", "Creature — Squirrel Noble")])],
                ["playerId": "ai", "displayName": "Tavern AI", "life": opponentLife, "poison": 0, "commanderTax": 0,
                 "zones": zones(theirs, stack: opponentStack ? [card("bolt-1", "Lightning Bolt", "Instant")] : [])],
            ],
        ]
        var actions: [[String: Any]] = []
        if chatterfangAction {
            actions.append(["id": "act-77", "type": "activate_ability", "playerId": "me",
                            "label": "{B}, Sacrifice X Squirrels: Target creature gets +X/-X until end of turn.",
                            "sourceInstanceId": "chat-1", "abilityId": "ab-1", "promptId": "p-1", "messageId": 3])
        }
        if passOffered { actions.append(["id": "p-1:pass_priority", "type": "pass_priority", "playerId": "me", "label": "Pass priority", "promptId": "p-1", "messageId": 3]) }
        root["legalActions"] = actions
        if ownTrigger {
            root["xmage"] = ["schemaVersion": 1, "gameId": "game-1", "bridgeRevision": 7, "callbackCoverage": [],
                             "stack": [["id": "st-1", "name": "Pitiless Plunderer trigger", "sourceInstanceId": "plu-1", "controllerId": "me"]],
                             "combat": [], "players": [], "exileZones": [], "revealed": [], "lookedAt": [], "companion": [],
                             "playableObjects": [],
                             "panels": ["stack": true, "command": false, "graveyard": false, "exile": false, "revealed": false, "lookedAt": false, "search": false]]
        }
        if prompt {
            var targets: [[String: Any]] = [["id": "zac-1", "label": "Zacama, Primal Calamity", "cardInstanceId": "zac-1"],
                                            ["id": "sq-9", "label": "Squirrel Token", "cardInstanceId": "sq-9"]]
            if callerAlive { targets.insert(["id": "cal-1", "label": "Kinjalli's Caller", "cardInstanceId": "cal-1"], at: 0) }
            root["promptEnvelopeV2"] = ["id": "p-2", "method": "GAME_TARGET", "messageId": 4, "playerId": "me", "responseKind": "target",
                                        "message": "Select a creature", "targets": targets,
                                        "responseCommand": ["type": "choose_target", "promptId": "p-2", "messageId": 4]]
        }
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
    }

    func testStepsKeepKindsAndReplayTheSameTargetUntilItsGone() throws {
        let decision = try snapshot()
        let activate = GameCommand(action: decision.legalActions![0], gameId: "game-1", bridgeRevision: 7)
        let step = try XCTUnwrap(ComboLoop.step(command: activate, label: "x", actionID: "act-77", snapshot: decision))
        XCTAssertEqual(step.source, "Chatterfang, Squirrel General")
        XCTAssertTrue(step.stackEmpty)
        XCTAssertEqual(ComboLoop.command(for: step, in: decision)?.actionID, "act-77")

        let asked = try snapshot(prompt: true)
        let pick = GameCommand(type: "choose_target", gameId: "game-1", playerId: "me", promptId: "p-2", messageId: 4, targetIds: ["cal-1"])
        let target = try XCTUnwrap(ComboLoop.step(command: pick, label: "Kinjalli's Caller", actionID: "t", snapshot: asked))
        XCTAssertEqual(target.targets, [ComboTarget(name: "Kinjalli's Caller", controller: "opponent", kind: "creature", token: false)])
        // While it lives, the same creature; once it's gone, another opponent's creature (never your own Squirrel).
        let same = try XCTUnwrap(ComboLoop.command(for: target, in: asked, prefer: ["Kinjalli's Caller"]))
        XCTAssertEqual(same.command.targetIds, ["cal-1"])
        XCTAssertNil(same.retargeted)
        let next = try XCTUnwrap(ComboLoop.command(for: target, in: try snapshot(prompt: true, callerAlive: false), prefer: ["Kinjalli's Caller"]))
        XCTAssertEqual(next.command.targetIds, ["zac-1"])
        XCTAssertEqual(next.retargeted?.from, "Kinjalli's Caller")
        XCTAssertEqual(next.retargeted?.to, "Zacama, Primal Calamity")
        // A Squirrel token choice never takes Squirrel Sovereign.
        let squirrel = ComboStep(kind: .prompt, type: "choose_target", source: nil, label: "GAME_TARGET",
                                 targets: [ComboTarget(name: "Squirrel Token", controller: "you", kind: "creature", token: true)])
        XCTAssertEqual(ComboLoop.command(for: squirrel, in: asked)?.command.targetIds, ["sq-9"])
        XCTAssertEqual(ComboLoop.missing(squirrel), "no Squirrel Token token left")
        XCTAssertEqual(ComboLoop.missing(target), "no opponent's creature left to choose")
    }

    func testPassesAreIgnoredAndOwnTriggersResolveFirst() throws {
        let decision = try snapshot(passOffered: true)
        let pass = GameCommand(type: "pass_priority", gameId: "game-1", playerId: "me", promptId: "p-1", messageId: 3)
        XCTAssertEqual(ComboLoop.note(command: pass, label: "Pass priority", actionID: "p-1:pass_priority", snapshot: decision), .ignore)
        let attack = GameCommand(type: "declare_attackers", gameId: "game-1", playerId: "me")
        XCTAssertEqual(ComboLoop.note(command: attack, label: "Attack", actionID: "x", snapshot: decision), .breaks)
        let step = try XCTUnwrap(ComboLoop.step(command: GameCommand(action: decision.legalActions![0], gameId: "game-1", bridgeRevision: 7),
                                                label: "x", actionID: "act-77", snapshot: decision))
        let resolving = try snapshot(ownTrigger: true, passOffered: true)
        XCTAssertTrue(ComboLoop.waitsForStack(step, in: resolving), "the round started with an empty stack")
        XCTAssertFalse(ComboLoop.opponentResponded(resolving), "the trigger is ours")
        XCTAssertEqual(ComboLoop.pass(in: resolving)?.command.type, "pass_priority")
        XCTAssertFalse(ComboLoop.waitsForStack(step, in: decision))
    }

    func testDigestSeesToughnessAndSummaries() throws {
        let before = try snapshot()
        XCTAssertNotEqual(ComboLoop.digest(before), ComboLoop.digest(try snapshot(callerToughness: 2)), "−1/−1 until end of turn is progress")
        XCTAssertEqual(ComboLoop.digest(before), ComboLoop.digest(try snapshot()))
        XCTAssertTrue(ComboLoop.opponentResponded(try snapshot(opponentStack: true)))
        XCTAssertEqual(ComboLoop.summary(rounds: 12, before: before, after: try snapshot(opponentLife: 0)), "Repeated 12 times · Tavern AI 12 → 0")
        let round = [ComboStep(kind: .action, type: "activate_ability", source: "Chatterfang", label: "x"),
                     ComboStep(kind: .prompt, type: "choose_target", source: nil, label: "GAME_TARGET",
                               targets: [ComboTarget(name: "Kinjalli's Caller", controller: "opponent", kind: "creature")])]
        XCTAssertEqual(ComboLoop.preview(round), ["Activate Chatterfang", "Choose an opponent's creature"])
        XCTAssertEqual(ComboLoop.roundLine(3, round, chosen: ["Kinjalli's Caller"]), "Round 3 · Activate Chatterfang → Kinjalli's Caller")
        XCTAssertTrue(ComboRepeat.times(10).watchable)
        XCTAssertFalse(ComboRepeat.times(20).watchable)
        XCTAssertFalse(ComboRepeat.untilWin.watchable)
    }
}
