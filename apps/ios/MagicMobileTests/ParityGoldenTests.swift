import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Android parity goldens. The Android port in apps/android/core (package
/// io.magicmobile.android.game) adapts the same engine polls and prompt cases and must
/// produce these exact summaries (ParityGoldenTest.kt). After an intended iOS change, rerun
/// with MAGICMOBILE_WRITE_PARITY_GOLDENS=1, commit the goldens, then port the change until
/// the Android tests pass again.
final class ParityGoldenTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private var parityDirectory: URL { Self.root.appendingPathComponent("apps/android/core/src/test/resources/parity") }
    private var fixtureDirectory: URL { Self.root.appendingPathComponent("apps/ios/MagicMobileTests/Fixtures/OnDevice") }

    func testEngineFixturesMatchAndroidGoldens() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
            .filter { $0.hasSuffix(".json") && $0 != "manifest.json" }.sorted()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let poll = try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: fixtureDirectory.appendingPathComponent(name))))
            var log = OnDeviceMessageLog()
            try log.ingest(poll)
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID, log: log.entries)
            var summary = ParitySummary.snapshot(snapshot)
            summary["answers"] = ParitySummary.answers(snapshot: snapshot, prompt: poll.prompt)
            try check(summary, name: "fixture-" + name)
        }
    }

    func testPromptCasesMatchAndroidGoldens() throws {
        let data = try Data(contentsOf: parityDirectory.appendingPathComponent("prompt-cases.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let viewer = try XCTUnwrap(root["viewer"] as? String)
        let players = try JSONDecoder().decode([PlayerGameState].self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(root["players"])))
        let cards = players.flatMap { $0.zones.hand + $0.zones.battlefield + $0.zones.graveyard + $0.zones.exile + $0.zones.command }
        var results: [[String: Any]] = []
        for item in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let prompt = try EnginePrompt(MagicMobileOnDevice.JSONValue.decode(JSONSerialization.data(withJSONObject: XCTUnwrap(item["prompt"]))))
            var result: [String: Any] = ["name": item["name"] ?? ""]
            do {
                let view = try OnDevicePromptAdapter.presentation(prompt, viewerPlayerID: viewer, cards: cards, players: players)
                result["envelope"] = ParitySummary.envelope(view.envelope)
                result["actions"] = view.legalActions.map(ParitySummary.action)
                result["manaPayment"] = ParitySummary.o(view.manaPayment.map { ["active": $0.active, "remainingText": ParitySummary.o($0.remainingText)] as [String: Any] })
            } catch { result["error"] = ParitySummary.message(error) }
            result["answers"] = (item["commands"] as? [[String: Any]] ?? []).map { fields -> Any in
                let command = ParitySummary.command(fields, gameId: "match", playerId: viewer, promptId: prompt.id, messageId: Int(prompt.revision))
                return ParitySummary.answer(command, prompt: prompt, viewer: viewer)
            }
            results.append(result)
        }
        try check(["cases": results], name: "prompt-cases.json")
    }

    func testTextFormattingMatchesAndroidGoldens() throws {
        let data = try Data(contentsOf: parityDirectory.appendingPathComponent("text-cases.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let logs = (root["log"] as? [String] ?? []).map { message -> [String: Any] in
            let presentation = GameLogPresentation(message)
            return ["plain": presentation.plainText, "spans": presentation.spans.map { span -> [String: Any] in
                ["text": span.text, "role": "\(span.role)", "bold": span.bold, "italic": span.italic,
                 "card": ParitySummary.o(span.cardReference?.name)]
            }]
        }
        let rules = (root["rules"] as? [[String: Any]] ?? []).map { item -> [String: Any] in
            let presentation = GameRulesPresentation(source: item["source"] as? String ?? "", cardName: item["cardName"] as? String,
                                                     isHidden: item["hidden"] as? Bool ?? false)
            let symbols = GameRulesSymbols(presentation)
            return ["plain": presentation.plainText, "spoken": symbols.accessibilityText,
                    "fragments": symbols.fragments.map { ["literal": $0.literal, "code": ParitySummary.o($0.code)] as [String: Any] }]
        }
        let prompts = (root["prompts"] as? [String] ?? []).map(PromptDisplayText.clean)
        try check(["log": logs, "rules": rules, "prompts": prompts], name: "text-cases.json")
    }

    /// Shared behavior cases: both apps must meet every expectation in the file (no goldens).
    func testOpponentFocusCasesOnBothPlatforms() throws { try runSeatCases("focus-cases.json") }

    func testSpectatorSeatCasesOnBothPlatforms() throws { try runSeatCases("spectator-cases.json") }

    /// game-summary-cases.json: combat credit and the top attacker (name, damage, art card).
    func testGameSummaryCasesOnBothPlatforms() throws {
        let root = try caseFile("game-summary-cases.json")
        let base = try XCTUnwrap(root["base"] as? [String: Any])
        let cards = try XCTUnwrap(root["cards"] as? [String: [String: Any]])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let at = "game-summary-cases.json · \(item["name"] ?? "")"
            var stats = GameStats()
            for step in item["steps"] as? [[String: Any]] ?? [] {
                let json = try GameSummaryCase.snapshot(base, step, cards: cards)
                stats.record(try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
            }
            let expect = try XCTUnwrap(item["expect"] as? [String: Any], at)
            XCTAssertEqual(stats.combatDamage, expect["combatDamage"] as? Int, at)
            XCTAssertEqual(stats.biggestHit, expect["biggestHit"] as? Int, at)
            if let top = expect["top"] as? [String: Any] {
                let actual = try XCTUnwrap(stats.topCard, at)
                XCTAssertEqual(actual.name, top["name"] as? String, at)
                XCTAssertEqual(actual.damage, top["damage"] as? Int, at)
                XCTAssertEqual(actual.card?.instanceId, top["instanceId"] as? String, at)
                XCTAssertEqual(actual.card?.card.tokenArtwork?.name, top["tokenArtwork"] as? String, at)
            } else {
                XCTAssertNil(stats.topCard, at)
            }
        }
    }

    func testPriorityStatusCasesOnBothPlatforms() throws {
        let root = try caseFile("focus-cases.json")
        let base = try XCTUnwrap(root["base"] as? [String: Any])
        let cases = try XCTUnwrap(root["status"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            var json = base
            json["turn"] = item["turn"]
            json["priorityPlayerId"] = item["priority"]
            json["waitingOnPlayerId"] = item["waitingOn"]
            let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(snapshot.priorityStatusText, item["text"] as? String, "status · \(item["name"] ?? "")")
        }
    }

    /// combat-cases.json: keyword extraction, combat badges, first-strike beats and log reasons.
    func testCombatClarityCasesOnBothPlatforms() throws {
        let root = try caseFile("combat-cases.json")
        func keywords(_ value: Any?) -> [CombatKeyword] { (value as? [String] ?? []).compactMap(CombatKeyword.init(rawValue:)) }
        for item in try XCTUnwrap(root["keywords"] as? [[String: Any]]) {
            let icons = (item["icons"] as? [String])?.map { XmageCardIcon(iconType: $0, resourceName: nil, category: nil, text: nil, hint: nil) }
            XCTAssertEqual(CombatKeyword.of(icons: icons, rules: item["rules"] as? String).map(\.rawValue),
                           item["expect"] as? [String], "keywords · \(item["name"] ?? "")")
        }
        for item in try XCTUnwrap(root["badges"] as? [[String: Any]]) {
            let at = "badges · \(item["name"] ?? "")"
            let plan = CombatKeywordBadgePlan(keywords: keywords(item["keywords"]), cardWidth: CGFloat(item["width"] as! Double),
                                              cardHeight: CGFloat(item["height"] as! Double))
            XCTAssertEqual(plan.visible.map(\.rawValue), item["visible"] as? [String], at)
            XCTAssertEqual(plan.hiddenCount, item["hidden"] as? Int, at)
            XCTAssertEqual(plan.visible.map(plan.label), item["labels"] as? [String], at)
        }
        func state(_ json: [String: Any]) -> BoardFXState {
            let cards = (json["cards"] as? [[String: Any]] ?? []).map { card in
                BoardFXState.Card(id: card["id"] as! String, playerID: card["player"] as! String,
                                  zone: BoardFXZone(rawValue: card["zone"] as? String ?? "battlefield")!, name: card["id"] as! String,
                                  tint: .red, damage: card["damage"] as? Int ?? 0, counters: 0,
                                  attacking: card["attacking"] as? Bool ?? false, blocking: card["blocking"] as? [String] ?? [],
                                  keywords: Set(keywords(card["keywords"])))
            }
            return BoardFXState(gameID: "combat", step: json["step"] as! String, lives: json["lives"] as? [String: Int] ?? [:],
                                cards: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) }),
                                defenders: json["defenders"] as? [String: String] ?? [:],
                                blockedAttackers: Set(json["blocked"] as? [String] ?? []))
        }
        func summary(_ event: BoardFXEvent) -> String {
            switch event {
            case .firstStrikeBeat: return "first-strike"
            case let .combatStrike(id, target, _, first):
                let aim: String
                switch target { case let .card(card): aim = "card:\(card)"; case let .player(player): aim = "player:\(player)" }
                return "strike \(id) -> \(aim) \(first ? "first" : "regular")"
            case let .damageMarked(id, amount): return "damage \(id) \(amount)"
            case let .leftBattlefield(id, _, zone, _): return "left \(id) \(zone?.rawValue ?? "nil")"
            case let .lifeChanged(id, delta): return "life \(id) \(delta)"
            default: return "other"
            }
        }
        for item in try XCTUnwrap(root["beats"] as? [[String: Any]]) {
            let at = "beats · \(item["name"] ?? "")"
            let events = BoardEventDiffer.events(from: state(item["old"] as! [String: Any]), to: state(item["new"] as! [String: Any]))
            XCTAssertEqual(events.map(summary), item["events"] as? [String], at)
            for (level, key) in [(BoardFXLevel.full, "full"), (.reduced, "reduced")] {
                let planned = BoardFXScheduler.schedule(events, level: level).map {
                    "\(summary($0.event)) @\(String(format: "%.3f", $0.delay)) +\(String(format: "%.3f", $0.duration))"
                }
                XCTAssertEqual(planned, item[key] as? [String], "\(at) · \(key)")
            }
        }
        let log = try XCTUnwrap(root["log"] as? [String: Any])
        let fighters = try XCTUnwrap(log["fighters"] as? [String: [String: Any]]).mapValues {
            CombatLogReasons.Fighter(name: $0["name"] as! String, keywords: Set(keywords($0["keywords"])))
        }
        for item in try XCTUnwrap(log["cases"] as? [[String: Any]]) {
            let step = CombatLogReasons.DamageStep(from: item["previous"] as? String, to: item["step"] as! String)
            XCTAssertEqual(CombatLogReasons.reason(for: item["message"] as! String, step: step, fighters: fighters),
                           item["reason"] as? String, "log · \(item["name"] ?? "")")
        }
    }

    /// resume-cases.json: the save/resume strings, files, launch outcomes, prompt detail and
    /// game-over rule. ParityGoldenTest.kt runs the same cases on Android.
    @MainActor
    func testResumeCasesOnBothPlatforms() throws {
        let root = try caseFile("resume-cases.json")
        let strings = try XCTUnwrap(root["strings"] as? [String: String])
        let expected: [String: String] = [
            "promptTitle": GameResumeText.promptTitle, "resume": GameResumeText.resume, "abandon": GameResumeText.abandon,
            "resumed": GameResumeText.resumed, "restoreFailed": GameResumeText.restoreFailed,
            "expired": GameResumeText.expired, "updated": GameResumeText.updated,
            "endedOnClose": GameResumeText.endedOnClose, "dismiss": GameResumeText.dismiss]
        XCTAssertEqual(strings, expected)
        XCTAssertEqual(root["windowSeconds"] as? Int, Int(GameResumeLaunchDecision.window / 1000))
        XCTAssertEqual(root["noticeSeconds"] as? Int, GameResumeText.noticeSeconds)
        let identity = try XCTUnwrap(root["engineIdentity"] as? [String: Any])
        XCTAssertEqual(GameResumeIdentity.engine(protocolVersion: Int64(try XCTUnwrap(identity["protocol"] as? Int)),
                                                 upstream: try XCTUnwrap(identity["upstream"] as? String),
                                                 catalogueHash: try XCTUnwrap(identity["catalogueHash"] as? String)),
                       identity["text"] as? String)

        let files = try XCTUnwrap(root["files"] as? [String: Any])
        let sidecarKeys = try XCTUnwrap(files["sidecarKeys"] as? [String])
        XCTAssertEqual(files["sidecarFormat"] as? Int, GameResumeRecord.currentFormat)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func millis(_ ago: Any?) -> Int64? { (ago as? Double).map { Int64(((now.timeIntervalSince1970 - $0) * 1000).rounded()) } }
        let setup = GameResumeSetup(configuration: .object(["seats": .array([])]), seatID: "player1", playerName: "P",
                                    deckID: "precon:x", aiDeckIDs: ["x"], aiSkill: 2, startingPlayerMode: "choose")
        let cases = try XCTUnwrap(root["launch"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let at = "launch · \(item["name"] ?? "")"
            let present = Set(try XCTUnwrap(item["files"] as? [String], at))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResumeCases-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = GameResumeStore(directory: directory, protectsFiles: false)
            XCTAssertEqual(store.checkpointURL.lastPathComponent, files["checkpoint"] as? String)
            XCTAssertEqual(store.sidecarURL.lastPathComponent, files["sidecar"] as? String)
            XCTAssertEqual(store.markerURL.lastPathComponent, files["marker"] as? String)
            XCTAssertEqual(store.consumedCheckpointURL.lastPathComponent, files["consumed"] as? String)
            if present.contains("sidecar") {
                if let text = item["sidecarText"] as? String {
                    try store.writeAtomically(Data(text.utf8), to: store.sidecarURL)
                } else {
                    var record = GameResumeRecord(appBuild: item["appBuild"] as? String ?? "same",
                                                  engineIdentity: item["engine"] as? String ?? "same",
                                                  createdAt: millis(7200.0)!,
                                                  lastCheckpointAt: try XCTUnwrap(millis(item["checkpointAgo"]), at),
                                                  leftAt: millis(item["leftAgo"]), turn: 12, playerDeckName: "Token Triumph",
                                                  opponents: ["AI 1"], setup: setup)
                    record.format = item["format"] as? Int ?? GameResumeRecord.currentFormat
                    try store.write(record)
                    let written = try JSONSerialization.jsonObject(with: Data(contentsOf: store.sidecarURL)) as? [String: Any]
                    XCTAssertEqual(written?.keys.sorted(), sidecarKeys.sorted(), at)
                }
            }
            if present.contains("checkpoint") {
                try store.prepareDirectory()
                try Data("checkpoint".utf8).write(to: store.checkpointURL)
            }
            if present.contains("consumed") {
                try store.prepareDirectory()
                try Data("used-up checkpoint".utf8).write(to: store.consumedCheckpointURL)
            }
            if present.contains("marker") { try store.writeMarker(startedAt: millis(60.0)!) }
            let resume = GameResumeCoordinator(store: store, now: { now })
            resume.evaluateLaunch(appBuild: "same", engineIdentity: "same")
            let outcome: String
            if resume.offer != nil {
                XCTAssertNil(resume.notice, at)
                outcome = "offer"
            } else if let notice = resume.notice {
                outcome = strings.first { $0.value == notice }?.key ?? "unknown notice: \(notice)"
            } else {
                outcome = "none"
            }
            XCTAssertEqual(outcome, item["expect"] as? String, at)
            let remains = outcome == "offer"
            XCTAssertEqual(store.sidecarExists, remains, "\(at) · sidecar")
            XCTAssertEqual(store.checkpointExists, remains, "\(at) · checkpoint")
            XCTAssertFalse(store.consumedCheckpointExists, "\(at) · consumed")
            XCTAssertFalse(store.hasMarker, "\(at) · marker")
        }

        for item in try XCTUnwrap(root["detail"] as? [[String: Any]]) {
            XCTAssertEqual(GameResumeText.detail(turn: Int64(try XCTUnwrap(item["turn"] as? Int)),
                                                 opponents: try XCTUnwrap(item["opponents"] as? [String]),
                                                 savedSecondsAgo: try XCTUnwrap(item["savedAgoSeconds"] as? Double)),
                           item["text"] as? String)
        }

        // A game over for this seat deletes what it saved, so it cannot be resumed.
        for item in try XCTUnwrap(root["over"] as? [[String: Any]]) {
            var poll: [String: Any] = ["matchId": "m", "viewerId": "player1", "revision": 1, "phase": item["phase"] ?? "",
                                       "resyncRequired": false, "prompt": NSNull(), "snapshot": NSNull()]
            if item["snapshot"] as? Bool != false {
                let players: [[String: Any]] = [["playerId": "me", "hasLeft": item["viewerLeft"] ?? false],
                                                ["playerId": "other", "hasLeft": true]]
                let snapshot: [String: Any] = ["enginePlayerId": "me", "outcome": ["ended": item["outcomeEnded"] ?? false] as [String: Any],
                                               "gameView": ["players": players] as [String: Any]]
                poll["snapshot"] = snapshot
            }
            let value = try MagicMobileOnDevice.JSONValue.decode(JSONSerialization.data(withJSONObject: poll))
            XCTAssertEqual(GameResumePolicy.isOver(try MatchPoll(value)), item["over"] as? Bool, "over · \(item["name"] ?? "")")
        }
    }

    private func caseFile(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: parityDirectory.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Runs focus-cases.json or spectator-cases.json the way NativeGameView applies them:
    /// every poll feeds BoardFocusTracker, then BoardOpponentFocus.snapshot picks the seats.
    private func runSeatCases(_ name: String) throws {
        let root = try caseFile(name)
        let base = try XCTUnwrap(root["base"] as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            var state: [String: Any] = ["followTurns": item["followTurns"] as? Bool ?? true]
            var tracker = BoardFocusTracker()
            for (index, step) in (item["steps"] as? [[String: Any]] ?? []).enumerated() {
                let at = "\(name) · \(item["name"] ?? "") · step \(index + 1)"
                for key in SeatCase.stateKeys where step.keys.contains(key) { state[key] = step[key] }
                let snapshot = try JSONDecoder().decode(GameSnapshot.self,
                                                        from: JSONSerialization.data(withJSONObject: SeatCase.snapshot(base, state)))
                if let tap = step["tap"] as? String { tracker.select(tap) }
                tracker.observe(snapshot, followTurns: state["followTurns"] as? Bool ?? true)
                let board = BoardOpponentFocus.snapshot(snapshot, selecting: tracker.focusedID)
                if step.keys.contains("top") { XCTAssertEqual(board.opponent?.playerId, step["top"] as? String, at) }
                if let ids = step["topChoices"] as? [String] { XCTAssertEqual(BoardOpponentFocus.opponents(in: board).map(\.playerId), ids, at) }
                if let id = step["seat"] as? String { XCTAssertEqual(board.seat?.playerId, id, at) }
                if let ids = step["seatHand"] as? [String] { XCTAssertEqual(BoardOpponentFocus.seatHand(in: board).map(\.instanceId), ids, at) }
                if let count = step["seatHandCount"] as? Int { XCTAssertEqual(board.seat?.zones.visibleHandCount, count, at) }
                if let id = step["viewer"] as? String {
                    XCTAssertEqual(board.viewerID, id, at)
                    XCTAssertEqual(board.human?.playerId, id, at)
                }
                if let label = step["viewerLabel"] as? String { XCTAssertEqual(board.playerLabel(board.viewerID), label, at) }
                if let label = step["seatLabel"] as? String { XCTAssertEqual(board.playerLabel(board.seatID), label, at) }
                if let spectating = step["spectating"] as? Bool { XCTAssertEqual(board.isSpectating, spectating, at) }
                if let title = step["title"] as? String { XCTAssertEqual(SpectatorSeatPresentation.title(board), title, at) }
                if let detail = step["detail"] as? String { XCTAssertEqual(SpectatorSeatPresentation.detail(board), detail, at) }
            }
        }
    }

    private func check(_ summary: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        let directory = parityDirectory.appendingPathComponent("golden")
        let url = directory.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["MAGICMOBILE_WRITE_PARITY_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }
        let golden = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), String(decoding: golden, as: UTF8.self),
                       "\(name) changed: rerun with MAGICMOBILE_WRITE_PARITY_GOLDENS=1 and port the change to Android")
    }
}

/// Builds a case step's snapshot from the file's base. SeatCase in ParityGoldenTest.kt is its twin.
enum SeatCase {
    static let stateKeys = ["turn", "step", "active", "prompt", "out", "game", "viewer", "completed", "followTurns"]

    static func snapshot(_ base: [String: Any], _ state: [String: Any]) -> [String: Any] {
        var json = base
        if let game = state["game"] as? String { json["id"] = game }
        if let turn = state["turn"] as? Int { json["turn"] = turn }
        if let step = state["step"] as? String { json["step"] = step }
        if let viewer = state["viewer"] as? String { json["viewerPlayerId"] = viewer }
        json["activePlayerId"] = state["active"] as? String
        if state["completed"] as? Bool == true { json["gameStatus"] = "completed" }
        if let owner = state["prompt"] as? String {
            json["promptEnvelopeV2"] = ["id": "case-prompt", "method": "GAME_SELECT", "messageId": 1, "playerId": owner,
                                        "responseKind": "priority", "message": "Respond"] as [String: Any]
        }
        let out = Set(state["out"] as? [String] ?? [])
        json["players"] = (base["players"] as? [[String: Any]] ?? []).map { player -> [String: Any] in
            var player = player
            player["hasLeft"] = out.contains(player["playerId"] as? String ?? "")
            return player
        }
        return json
    }
}

/// Builds a game-summary-cases.json step's snapshot. GameSummaryCase in ParityGoldenTest.kt is its twin.
enum GameSummaryCase {
    static func snapshot(_ base: [String: Any], _ step: [String: Any], cards: [String: [String: Any]]) throws -> [String: Any] {
        func card(_ key: String) throws -> [String: Any] { try XCTUnwrap(cards[key], "unknown card \(key)") }
        let life = step["life"] as? [String: Int] ?? [:]
        let battlefield = try (step["battlefield"] as? [String] ?? []).map(card)
        var json = base
        json["players"] = (base["players"] as? [[String: Any]] ?? []).map { player -> [String: Any] in
            var player = player
            let id = player["playerId"] as? String ?? ""
            if let value = life[id] { player["life"] = value }
            if id == base["viewerPlayerId"] as? String {
                var zones = player["zones"] as? [String: Any] ?? [:]
                zones["battlefield"] = battlefield
                player["zones"] = zones
            }
            return player
        }
        var xmage = base["xmage"] as? [String: Any] ?? [:]
        xmage["combat"] = try (step["attacks"] as? [[String: Any]] ?? []).map { attack -> [String: Any] in
            let attackers = try (attack["attackers"] as? [String] ?? []).map { key -> [String: Any] in
                // XMage's combat groups carry no token template.
                var attacker = try card(key)
                var identity = attacker["card"] as? [String: Any] ?? [:]
                identity["tokenArtwork"] = nil
                attacker["card"] = identity
                return attacker
            }
            return ["defenderId": attack["defender"] ?? "", "defenderName": attack["defender"] ?? "",
                    "blocked": attack["blocked"] as? Bool ?? false, "attackers": attackers, "blockers": []]
        }
        json["xmage"] = xmage
        return json
    }
}

/// The summary written for each case. ParitySummary.kt builds the identical structure.
enum ParitySummary {
    static func o<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }

    static func message(_ error: Error) -> String {
        (error as? MagicMobileOnDevice.EngineError)?.errorDescription ?? "decoding failed"
    }

    static func card(_ c: ZoneCard) -> [String: Any] {
        [
            "instanceId": c.instanceId, "name": c.card.name, "typeLine": c.card.typeLine, "oracleText": o(c.card.oracleText),
            "manaCost": o(c.card.manaCost), "isToken": o(c.card.isToken), "tokenColors": o(c.card.tokenColors),
            "copySourceArtworkName": o(c.card.copySourceArtworkName),
            "tokenArtwork": o(c.card.tokenArtwork.map { ["name": $0.name, "typeLine": $0.typeLine, "oracleText": $0.oracleText,
                                                            "power": o($0.power), "toughness": o($0.toughness), "colors": $0.colors] as [String: Any] }),
            "tapped": o(c.tapped), "summoningSickness": o(c.summoningSickness), "damage": o(c.damage), "phasedIn": o(c.phasedIn),
            "isAttacking": o(c.isAttacking), "blocking": o(c.blocking), "attachedToInstanceId": o(c.attachedToInstanceId),
            "reportedPower": o(c.reportedPower), "reportedToughness": o(c.reportedToughness), "counters": o(c.counters),
            "icons": (c.cardIcons ?? []).map { ["iconType": $0.iconType, "category": o($0.category), "text": o($0.text), "hint": o($0.hint)] as [String: Any] },
            "visibleIcons": c.visibleXmageIcons.map(\.iconType),
            "selectable": o(c.selectable), "disabledReason": o(c.disabledReason),
            "displayPower": o(c.displayPower), "displayToughness": o(c.displayToughness)
        ]
    }

    static func player(_ p: PlayerGameState) -> [String: Any] {
        let z = p.zones
        return [
            "playerId": p.playerId, "displayName": o(p.displayName), "life": p.life, "poison": p.poison,
            "commanderTax": p.commanderTax, "commanderTaxKnown": o(p.commanderTaxKnown), "hasLeft": o(p.hasLeft),
            "isHuman": o(p.isHuman), "monarch": o(p.monarch), "initiative": o(p.initiative), "counters": o(p.counters),
            "commanderDamage": o(p.commanderDamage),
            "commanders": (p.commanders ?? []).map { ["id": $0.id, "name": o($0.name), "ownerPlayerId": $0.ownerPlayerId,
                                                      "commanderTax": o($0.commanderTax), "castsFromCommandZone": o($0.castsFromCommandZone),
                                                      "damageToPlayers": o($0.damageToPlayers)] as [String: Any] },
            "manaPool": o(p.manaPool.map { ["W": $0.W, "U": $0.U, "B": $0.B, "R": $0.R, "G": $0.G, "C": $0.C] }),
            "handCount": o(z.handCount), "libraryCount": o(z.libraryCount),
            "hand": z.hand.map(card), "battlefield": z.battlefield.map(card), "graveyard": z.graveyard.map(card),
            "exile": z.exile.map(card), "command": z.command.map(card), "library": z.library.map(card), "stack": z.stack.map(card)
        ]
    }

    static func snapshot(_ s: GameSnapshot) -> [String: Any] {
        var result: [String: Any] = [
            "id": s.id, "source": o(s.source), "activePlayerId": o(s.activePlayerId), "phase": s.phase, "step": o(s.step),
            "turn": s.turn, "priorityPlayerId": o(s.priorityPlayerId), "waitingOnPlayerId": o(s.waitingOnPlayerId),
            "promptText": o(s.promptText), "bridgeRevision": o(s.bridgeRevision), "xmageCycle": o(s.xmageCycle),
            "pendingStatus": o(s.pendingStatus), "gameStatus": o(s.gameStatus.map { $0 == .completed ? "completed" : "in_progress" }),
            "winnerPlayerIds": o(s.winnerPlayerIds), "viewerPlayerId": o(s.viewerPlayerId), "isSpectating": s.isSpectating,
            "thinkingPlayerID": o(s.thinkingPlayerID), "log": s.log.map { ["id": $0.id, "message": $0.message] },
            "players": s.players.map(player), "legalActions": (s.legalActions ?? []).map(action),
            "promptEnvelopeV2": o(s.promptEnvelopeV2.map(envelope)),
            "manaPayment": o(s.manaPayment.map { ["active": $0.active, "remainingText": o($0.remainingText)] as [String: Any] })
        ]
        if let x = s.xmage {
            result["xmage"] = [
                "gameId": x.gameId, "bridgeRevision": x.bridgeRevision, "xmageCycle": o(x.xmageCycle),
                "stack": x.stack.map { ["id": $0.id, "objectType": o($0.objectType), "name": $0.name, "rulesText": o($0.rulesText),
                                         "sourceInstanceId": o($0.sourceInstanceId), "sourceName": o($0.sourceName),
                                         "sourceCard": o($0.sourceCard.map(card)), "targetIds": o($0.targetIds), "paid": o($0.paid)] as [String: Any] },
                "combat": x.combat.map { ["defenderId": $0.defenderId, "defenderName": $0.defenderName, "defenderKind": o($0.defenderKind),
                                          "blocked": $0.blocked, "attackers": $0.attackers.map(card), "blockers": $0.blockers.map(card)] as [String: Any] },
                "players": x.players.map { ["playerId": $0.playerId, "name": $0.name, "active": $0.active, "hasPriority": $0.hasPriority,
                                            "timerActive": $0.timerActive, "passedTurn": $0.skipState.passedTurn,
                                            "passedAllTurns": $0.skipState.passedAllTurns, "sideboard": $0.zones.sideboard.map(card)] as [String: Any] },
                "playableObjects": x.playableObjects.map { ["sourceInstanceId": $0.sourceInstanceId, "sourceZone": o($0.sourceZone), "cardName": $0.cardName,
                                                            "categories": $0.categories,
                                                            "abilities": $0.abilities.map { ["id": $0.id, "label": $0.label, "category": $0.category] }] as [String: Any] },
                "zones": (x.exileZones + x.revealed + x.lookedAt + x.companion).map { ["id": $0.id, "name": $0.name, "cards": $0.cards.map(card)] as [String: Any] },
                "panels": ["stack": x.panels.stack, "command": x.panels.command, "graveyard": x.panels.graveyard, "exile": x.panels.exile,
                           "revealed": x.panels.revealed, "lookedAt": x.panels.lookedAt, "search": x.panels.search]
            ] as [String: Any]
        } else { result["xmage"] = NSNull() }
        return result
    }

    static func action(_ a: LegalAction) -> [String: Any] {
        [
            "id": a.id, "type": a.type, "playerId": a.playerId, "label": a.label, "promptId": o(a.promptId), "messageId": o(a.messageId),
            "cardInstanceId": o(a.cardInstanceId), "sourceInstanceId": o(a.sourceInstanceId), "sourceZone": o(a.sourceZone),
            "cardName": o(a.cardName), "abilityId": o(a.abilityId), "confirmed": o(a.confirmed), "choiceIds": o(a.choiceIds),
            "compactPromptTitle": a.compactPromptTitle
        ]
    }

    static func envelope(_ e: PromptEnvelopeV2) -> [String: Any] {
        func options(_ values: [ChoicePromptOption]?) -> Any { o(values?.map { ["id": $0.id, "label": $0.label] }) }
        func command(_ c: XmageResponseCommand?) -> Any {
            o(c.map { ["type": o($0.type), "promptId": o($0.promptId), "messageId": o($0.messageId), "confirmed": o($0.confirmed), "pay": o($0.pay)] as [String: Any] })
        }
        var chosen: Any = NSNull()
        if case .array(let values)? = e.options?["chosenTargets"] { chosen = values.compactMap(\.stringValue) }
        return [
            "id": e.id, "method": e.method, "messageId": e.messageId, "playerId": e.playerId, "responseKind": e.responseKind,
            "message": e.message, "required": o(e.required), "minChoices": o(e.minChoices), "maxChoices": o(e.maxChoices),
            "totalMin": o(e.totalMin), "totalMax": o(e.totalMax), "targetIds": o(e.targetIds), "choices": options(e.choices),
            "responseCommand": command(e.responseCommand), "cards": o(e.cards?.map(card)), "targets": options(e.targets),
            "players": o(e.players?.map { ["id": $0.id, "label": $0.label, "playerId": $0.playerId] }),
            "piles": o(e.piles?.map { ["id": $0.id, "label": $0.label, "cards": $0.cards.map(card), "number": o($0.explicitPileNumber)] as [String: Any] }),
            "abilities": o(e.abilities?.map { ["id": $0.id, "label": $0.label, "sourceInstanceId": o($0.sourceInstanceId),
                                               "sourceName": o($0.sourceName), "sourceUnavailableReason": o($0.sourceUnavailableReason),
                                               "sourceCard": o($0.sourceCard.map(card))] as [String: Any] }),
            "modes": options(e.modes), "amounts": o(e.amounts),
            "multiAmounts": o(e.multiAmounts?.map { ["id": $0.id, "label": $0.label, "min": $0.min, "max": $0.max, "defaultValue": o($0.defaultValue)] as [String: Any] }),
            "manaChoices": o(e.manaChoices?.map { ["id": $0.id, "label": $0.label, "manaType": o($0.manaType), "amount": o($0.amount)] as [String: Any] }),
            "orderedItems": options(e.orderedItems),
            "confirmation": o(e.confirmation.map { ["yesLabel": o($0.yesLabel), "noLabel": o($0.noLabel),
                                                     "yesCommand": command($0.yesCommand), "noCommand": command($0.noCommand)] as [String: Any] }),
            "optionKeys": o(e.options.map { Array($0.keys).sorted() }), "chosenTargets": chosen,
            "kind": "\(MobilePromptPresentation.kind(for: e))"
        ]
    }

    static func command(_ f: [String: Any], gameId: String, playerId: String, promptId: String, messageId: Int) -> GameCommand {
        GameCommand(type: f["type"] as? String ?? "", gameId: gameId, playerId: playerId,
                    cardInstanceId: f["cardInstanceId"] as? String, sourceInstanceId: f["sourceInstanceId"] as? String,
                    abilityId: f["abilityId"] as? String, promptId: promptId, messageId: messageId,
                    choiceIds: f["choiceIds"] as? [String], targetIds: f["targetIds"] as? [String],
                    cardInstanceIds: f["cardInstanceIds"] as? [String], modeIds: f["modeIds"] as? [String],
                    pile: f["pile"] as? Int, amount: f["amount"] as? Int, amounts: f["amounts"] as? [Int],
                    orderedIds: f["orderedIds"] as? [String], manaType: f["manaType"] as? String,
                    playerIds: f["playerIds"] as? [String], confirmed: f["confirmed"] as? Bool)
    }

    static func answer(_ command: GameCommand, prompt: EnginePrompt, viewer: String) -> Any {
        do {
            let value = try OnDevicePromptAdapter.answer(for: command, prompt: prompt, viewerPlayerID: viewer)
            return try JSONSerialization.jsonObject(with: value.encoded(), options: [.fragmentsAllowed])
        } catch { return ["error": message(error)] }
    }

    /// Every offered action, sent the way OnDeviceSession.send(action:) builds it, plus each
    /// target and confirmation the prompt shows.
    static func answers(snapshot: GameSnapshot, prompt: EnginePrompt?) -> [Any] {
        guard let prompt, !prompt.submitted else { return [] }
        var commands: [GameCommand] = (snapshot.legalActions ?? []).map { a in
            GameCommand(type: a.type, gameId: snapshot.id, playerId: a.playerId, cardInstanceId: a.cardInstanceId,
                        sourceInstanceId: a.sourceInstanceId, abilityId: a.abilityId, promptId: a.promptId, messageId: a.messageId,
                        choiceIds: a.choiceIds, targetIds: a.targetIds, cardInstanceIds: a.cardInstanceIds, modeIds: a.modeIds,
                        pile: a.pile?.value, amount: a.amount, amounts: a.amounts, orderedIds: a.orderedIds,
                        useCommandZone: a.useCommandZone, manaType: a.manaType, manaTypes: a.manaTypes, playerIds: a.playerIds,
                        confirmed: a.confirmed, pay: a.pay, sourceZone: a.sourceZone, fromZone: a.sourceZone, cardName: a.cardName,
                        attackers: a.attackers, blockers: a.blockers, expectedBridgeRevision: snapshot.bridgeRevision)
        }
        if let envelope = snapshot.promptEnvelopeV2 {
            for target in envelope.targets ?? [] {
                commands.append(GameCommand(type: "choose_target", gameId: snapshot.id, playerId: snapshot.viewerID,
                                            promptId: envelope.id, messageId: envelope.messageId, targetIds: [target.id]))
            }
            for confirmed in envelope.confirmation == nil ? [] : [true, false] {
                commands.append(GameCommand(type: "answer_yes_no", gameId: snapshot.id, playerId: snapshot.viewerID,
                                            promptId: envelope.id, messageId: envelope.messageId, confirmed: confirmed))
            }
            for choice in envelope.manaChoices ?? [] {
                commands.append(GameCommand(type: "play_mana", gameId: snapshot.id, playerId: snapshot.viewerID,
                                            promptId: envelope.id, messageId: envelope.messageId, manaType: choice.manaType))
            }
        }
        return commands.map { ["type": $0.type, "answer": answer($0, prompt: prompt, viewer: snapshot.viewerID)] as [String: Any] }
    }
}

// MARK: - Deck Studio

extension ParityGoldenTests {
    /// deck-studio-cases.json: Deck Studio's strings, Quick Add grammar, quick-check rules, search
    /// syntax, sample hand, role groups and stored check results. ParityGoldenTest.kt runs every
    /// case on Android; an id either platform does not know fails the test.
    @MainActor
    func testDeckStudioCasesOnBothPlatforms() throws {
        let root = try caseFile("deck-studio-cases.json")
        try deckStudioStrings(root)
        try deckStudioQuickAdd(try XCTUnwrap(root["quickAdd"] as? [String: Any]))
        try deckStudioPreflight(try XCTUnwrap(root["preflight"] as? [String: Any]))
        try deckStudioSearch(try XCTUnwrap(root["search"] as? [[String: Any]]))
        try deckStudioSampleHand(try XCTUnwrap(root["sampleHand"] as? [String: Any]))
        try deckStudioRoleGroups(try XCTUnwrap(root["roleGroups"] as? [String: Any]))
        try deckStudioCheckResults(try XCTUnwrap(root["checkResults"] as? [String: Any]))
    }

    private func deckStudioStatus(_ raw: Any?) throws -> DeckStudioPlayStatus {
        switch raw as? String {
        case "ready": return .ready
        case "needsFixes": return .needsFixes
        case "notChecked": return .notChecked
        default: return try XCTUnwrap(nil, "Unknown status \(String(describing: raw))")
        }
    }

    private func deckStudioRow(_ raw: [String: Any]) throws -> NativeDeckRow {
        NativeDeckRow(cardName: try XCTUnwrap(raw["name"] as? String), quantity: raw["quantity"] as? Int ?? 1,
                      section: raw["section"] as? String ?? "deck", isPrimaryCommander: raw["primary"] as? Bool ?? false)
    }

    @MainActor
    private func deckStudioStrings(_ root: [String: Any]) throws {
        let T = DeckStudioPlayText.self
        let known: [String: String] = [
            "play": T.play, "saveAndPlay": T.saveAndPlay, "playing": T.playing, "playingAccessibility": T.playingAccessibility,
            "ready": T.ready, "needsFixes": T.needsFixes, "notChecked": T.notChecked, "fixDeck": T.fixDeck, "notNow": T.notNow,
            "setUpGame": T.setUpGame, "cannotPlayTitle": T.cannotPlayTitle, "checkingTitle": T.checkingTitle,
            "checkingProgress": T.checkingProgress, "gameLive": T.gameLive, "catalogueLoading": T.catalogueLoading,
            "setupReady": T.setupReady, "setupNotChecked": T.setupNotChecked, "setupNeedsFixes": T.setupNeedsFixes,
            "panelCaption": T.panelCaption, "showAll": T.showAll, "startPassed": T.startPassed,
            "cardDetails": T.cardDetails, "addOne": T.addOne, "removeOne": T.removeOne, "replaceCard": T.replaceCard,
            "moveTo": T.moveTo, "removeRow": T.removeRow, "select": T.select, "selectCards": T.selectCards,
            "doneSelecting": T.doneSelecting, "selectAll": T.selectAll, "setQuantity": T.setQuantity, "remove": T.remove,
            "removeSelectedTitle": T.removeSelectedTitle, "removeSelectedMessage": T.removeSelectedMessage,
            "quantityMessage": T.quantityMessage, "quantityError": T.quantityError, "showAsGrid": T.showAsGrid, "showAsList": T.showAsList,
            "quickAdd": T.quickAdd, "quickAddMain": T.quickAddMain, "quickAddMaybe": T.quickAddMaybe,
            "quickAddMaybeboard": T.quickAddMaybeboard, "addCards": T.addCards, "quickAddHint": T.quickAddHint,
            "quickAddNeedsName": T.quickAddNeedsName, "quickAddFailed": T.quickAddFailed, "undo": T.undo,
            "editAsText": T.editAsText, "copyList": T.copyList, "listCopied": T.listCopied, "reviewChanges": T.reviewChanges,
            "applyChanges": T.applyChanges, "keepEditing": T.keepEditing, "diffAdded": T.diffAdded, "diffRemoved": T.diffRemoved,
            "noChanges": T.noChanges, "textEditorHint": T.textEditorHint, "chooseCommander": T.chooseCommander, "skip": T.skip,
            "commanderFirstTitle": T.commanderFirstTitle, "commanderFirstCaption": T.commanderFirstCaption,
            "searchCommanders": T.searchCommanders, "searchHint": T.searchHint, "withinIdentity": T.withinIdentity,
            "sampleHand": T.sampleHand, "sampleHandCaption": T.sampleHandCaption, "sampleHandEmpty": T.sampleHandEmpty,
            "draw7": T.draw7, "newHand": T.newHand, "mulligan": T.mulligan, "draw": T.draw,
            "quickCheckCaption": DeckStudioPreflight.caption]
        let strings = try XCTUnwrap(root["strings"] as? [String: String])
        XCTAssertEqual(Set(strings.keys), Set(known.keys), "Every Deck Studio string has one source on each platform")
        for (id, text) in strings { XCTAssertEqual(known[id], text, id) }
        XCTAssertEqual(T.destinations.map { [$0.section, $0.title] }, root["destinations"] as? [[String]])

        let formatted = try XCTUnwrap(root["formatted"] as? [[String: Any]])
        XCTAssertFalse(formatted.isEmpty)
        for item in formatted {
            let id = try XCTUnwrap(item["id"] as? String), args = try XCTUnwrap(item["args"] as? [Any])
            func text(_ index: Int) throws -> String { try XCTUnwrap(args[index] as? String, id) }
            func number(_ index: Int) throws -> Int { try XCTUnwrap(args[index] as? Int, id) }
            let actual: String
            switch id {
            case "checking": actual = T.checking(try text(0))
            case "nowPlaying": actual = T.nowPlaying(try text(0))
            case "nowPlayingStrip": actual = T.nowPlayingStrip(try text(0), try deckStudioStatus(args[1]))
            case "issues": actual = T.issueCount(try number(0))
            case "blocked": actual = T.blocked(try number(0))
            case "notShown": actual = T.notShown(try number(0))
            case "excluded": actual = T.excluded(try number(0))
            case "deletePlaying": actual = T.deletePlaying(try text(0))
            case "showingOnly": actual = T.showingOnly(try text(0))
            case "listFilter":
                let raw = try text(0)
                actual = raw == "needsFixes" ? DeckStudioListFilter.needsFixes([]).title
                    : DeckStudioListFilter.quickCheck(try XCTUnwrap(DeckStudioPreflight.Issue(rawValue: raw), raw)).title
            case "selected": actual = T.selected(try number(0))
            case "added": actual = T.added(try number(0), try text(1), maybeboard: try XCTUnwrap(args[2] as? Bool))
            case "noCardNamed": actual = T.noCardNamed(try text(0))
            case "handCounts": actual = T.handCounts(hand: try number(0), library: try number(1))
            case "status": actual = try deckStudioStatus(args[0]).label
            case "setupStatus": actual = try deckStudioStatus(args[0]).setupLine
            default: XCTFail("Unknown formatted id \(id)"); continue
            }
            XCTAssertEqual(actual, item["text"] as? String, "\(id) \(args)")
        }
    }

    private func deckStudioQuickAdd(_ root: [String: Any]) throws {
        let names = Set(try XCTUnwrap(root["cardNames"] as? [String]))
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let input = try XCTUnwrap(item["input"] as? String)
            let parsed = DeckStudioQuickAdd.parse(input) { names.contains($0) }
            guard let expected = item["result"] as? [String: Any] else { XCTAssertNil(parsed, "Quick Add \(input)"); continue }
            let value = try XCTUnwrap(parsed, "Quick Add \(input)")
            XCTAssertEqual(value.quantity, expected["quantity"] as? Int, input)
            XCTAssertEqual(value.name, expected["name"] as? String, input)
            XCTAssertEqual(value.ignored, expected["ignored"] as? [String], input)
            XCTAssertEqual(value.note, expected["note"] as? String, input)
        }
    }

    private func deckStudioPreflight(_ root: [String: Any]) throws {
        XCTAssertEqual(root["targetCount"] as? Int, DeckStudioPreflight.targetCount)
        XCTAssertEqual(root["caption"] as? String, DeckStudioPreflight.caption)
        let issues = try XCTUnwrap(root["issues"] as? [String: [String: String]])
        XCTAssertEqual(Set(issues.keys), Set(DeckStudioPreflight.Issue.allCases.map(\.rawValue)))
        for issue in DeckStudioPreflight.Issue.allCases {
            XCTAssertEqual(issues[issue.rawValue], ["title": issue.title, "badge": issue.badge], issue.rawValue)
        }
        var cards: [String: DeckStudioPreflight.CardFacts] = [:]
        for raw in try XCTUnwrap(root["cards"] as? [[String: Any]]) {
            let name = try XCTUnwrap(raw["name"] as? String)
            cards[name] = .init(name: name, typeLine: raw["typeLine"] as? String, oracleText: raw["oracleText"] as? String,
                                colorIdentity: raw["colorIdentity"] as? [String])
        }
        let aliases = root["aliases"] as? [String: String] ?? [:]
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let name = item["name"] as? String ?? ""
            let rows = try (try XCTUnwrap(item["rows"] as? [[String: Any]])).map(deckStudioRow)
            let catalogue = item["catalogue"] as? Bool ?? true
            let unresolvable = item["unresolvable"] as? [String]
            let check = DeckStudioPreflight(draft: NativeDeckDraft(name: "Case", rows: rows),
                                            card: { catalogue ? cards[aliases[$0] ?? $0] : nil },
                                            resolves: unresolvable.map { list in { !list.contains($0) } })
            let expect = try XCTUnwrap(item["expect"] as? [String: Any], name)
            XCTAssertEqual(check.count, expect["count"] as? Int, name)
            XCTAssertEqual(check.missingCommander, expect["missingCommander"] as? Bool, name)
            XCTAssertEqual(check.commanderIdentity.map { $0.sorted() }, expect["commanderIdentity"] as? [String], name)
            let flagged = try XCTUnwrap(expect["rows"] as? [String: [Int]], name)
            for issue in [DeckStudioPreflight.Issue.offIdentity, .duplicate, .unresolved] {
                XCTAssertEqual(check.rows(issue), Set((flagged[issue.rawValue] ?? []).map { rows[$0].id }), "\(name) · \(issue.rawValue)")
            }
            XCTAssertEqual(check.issueCount, expect["issueCount"] as? Int, name)
            XCTAssertEqual(check.summary, expect["summary"] as? String, name)
            XCTAssertEqual(check.activeIssues.map(check.chipTitle), expect["chips"] as? [String], name)
        }
    }

    private func deckStudioSearch(_ cases: [[String: Any]]) throws {
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let query = try XCTUnwrap(item["query"] as? String)
            let syntax = DeckStudioSearchSyntax(query)
            XCTAssertEqual(syntax.text, item["text"] as? String, query)
            XCTAssertEqual(syntax.types, item["types"] as? [String], query)
            XCTAssertEqual(syntax.oracle, item["oracle"] as? [String], query)
            XCTAssertEqual(syntax.minimumManaValue, item["minimumManaValue"] as? Double, query)
            XCTAssertEqual(syntax.maximumManaValue, item["maximumManaValue"] as? Double, query)
            XCTAssertEqual(syntax.identity.map { $0.sorted() }, item["identity"] as? [String], query)
            XCTAssertEqual(syntax.hasFilters, item["hasFilters"] as? Bool, query)
        }
    }

    private func deckStudioSampleHand(_ root: [String: Any]) throws {
        XCTAssertEqual(root["handSize"] as? Int, DeckStudioSampleHand.handSize)
        var generator = SystemRandomNumberGenerator()
        for item in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? ""
            let rows = try (try XCTUnwrap(item["rows"] as? [[String: Any]])).map(deckStudioRow)
            let names = DeckStudioSampleHand.libraryNames(from: NativeDeckDraft(name: "Case", rows: rows))
            XCTAssertEqual(names.count, item["library"] as? Int, name)
            var hand = DeckStudioSampleHand(names: names)
            for (index, step) in try XCTUnwrap(item["steps"] as? [[String: Any]]).enumerated() {
                let action = try XCTUnwrap(step["do"] as? String), at = "\(name) · step \(index + 1) \(action)"
                switch action {
                case "deal": hand.deal(using: &generator)
                case "mulligan": hand.mulligan(using: &generator)
                case "bottom": if let card = hand.hand.first { hand.putOnBottom(card.id) }
                case "draw": hand.draw()
                default: XCTFail("Unknown sample hand step \(action)"); continue
                }
                XCTAssertEqual(hand.hand.count, step["hand"] as? Int, at)
                XCTAssertEqual(hand.library.count, step["library"] as? Int, at)
                XCTAssertEqual(hand.mulligans, step["mulligans"] as? Int, at)
                XCTAssertEqual(hand.toBottom, step["toBottom"] as? Int, at)
                XCTAssertEqual(hand.turn, step["turn"] as? Int, at)
                XCTAssertEqual(hand.canMulligan, step["canMulligan"] as? Bool, at)
                XCTAssertEqual(hand.canDraw, step["canDraw"] as? Bool, at)
                XCTAssertEqual(hand.status, step["status"] as? String, at)
            }
        }
    }

    private func deckStudioRoleGroups(_ root: [String: Any]) throws {
        XCTAssertEqual(DeckStudioRoleGroups.order, root["order"] as? [String])
        var cards: [String: DeckStudioRoleGroups.CardFacts] = [:]
        for raw in try XCTUnwrap(root["cards"] as? [[String: Any]]) {
            cards[try XCTUnwrap(raw["name"] as? String)] = .init(text: nil, types: raw["types"] as? [String],
                curated: (raw["roles"] as? [String] ?? []).compactMap(DeckStudioRole.init(rawValue:)))
        }
        let rows = try XCTUnwrap(root["rows"] as? [String]).map { NativeDeckRow(cardName: $0) }
        for item in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? ""
            let overrides = try XCTUnwrap(item["overrides"] as? [String: [String]]).mapValues { Set($0.compactMap(DeckStudioRole.init(rawValue:))) }
            let membership = DeckStudioRoleGroups.membership(rows: rows, card: { cards[$0] }, overrides: overrides)
            XCTAssertEqual(rows.map { membership[$0.id] ?? [] }, item["groups"] as? [[String]], name)
            let counts = try XCTUnwrap(item["counts"] as? [String: Int], name)
            XCTAssertEqual(Set(membership.values.flatMap { $0 }), Set(counts.keys), name)
            for (title, count) in counts {
                XCTAssertEqual(DeckStudioRoleGroups.uniqueCards(rows.filter { membership[$0.id]?.contains(title) == true }), count, "\(name) · \(title)")
            }
        }
    }

    @MainActor
    private func deckStudioCheckResults(_ root: [String: Any]) throws {
        let limits = try XCTUnwrap(root["limits"] as? [String: Int])
        XCTAssertEqual(limits, ["maximumResults": DeckStudioReceiptStore.maximumResults, "maximumPerDeck": DeckStudioReceiptStore.maximumPerDeck,
                                "maximumBytes": DeckStudioReceiptStore.maximumBytes, "maximumIssues": DeckStudioStoredCheck.maximumIssues])
        for item in try XCTUnwrap(root["sha256"] as? [[String: Any]]) {
            let request = try XCTUnwrap(item["request"] as? String)
            XCTAssertEqual(DeckStudioCheckKey(deckID: "d", request: Data(request.utf8), upstream: "u", catalogue: "c", appBuild: "b").requestSHA256,
                           item["sha256"] as? String, request)
        }
        var requests: [String: String] = [:]
        func key(_ raw: [String: Any]) throws -> DeckStudioCheckKey {
            let request = try XCTUnwrap(raw["request"] as? String)
            let key = DeckStudioCheckKey(deckID: try XCTUnwrap(raw["deck"] as? String), request: Data(request.utf8),
                                         upstream: try XCTUnwrap(raw["upstream"] as? String), catalogue: try XCTUnwrap(raw["catalogue"] as? String),
                                         appBuild: try XCTUnwrap(raw["build"] as? String))
            requests[key.requestSHA256] = request
            return key
        }
        func label(_ key: DeckStudioCheckKey) -> String {
            [key.deckID, requests[key.requestSHA256] ?? key.requestSHA256, key.upstream, key.catalogue, key.appBuild].joined(separator: "|")
        }
        func stored(_ key: DeckStudioCheckKey, at: Double, valid: Bool, summary: String = "Checked") -> DeckStudioStoredCheck {
            DeckStudioStoredCheck(key: key, checkedAt: Date(timeIntervalSince1970: at / 1000), valid: valid, summary: summary,
                                  issues: valid ? [] : [.init(index: 0, type: "OTHER", group: "Sol Ring", message: "Too many copies", cardName: "Sol Ring")])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeckStudioCases-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (index, scenario) in try XCTUnwrap(root["store"] as? [[String: Any]]).enumerated() {
            let name = scenario["name"] as? String ?? ""
            let url = directory.appendingPathComponent("store-\(index).json")
            let store = DeckStudioReceiptStore(url: url)
            for record in try XCTUnwrap(scenario["records"] as? [[String: Any]]) {
                XCTAssertTrue(store.record(stored(try key(record), at: try XCTUnwrap(record["at"] as? Double), valid: try XCTUnwrap(record["valid"] as? Bool))), name)
            }
            let expected = try XCTUnwrap(scenario["expect"] as? [String])
            XCTAssertEqual(store.checks.map { label($0.key) }, expected, name)
            XCTAssertEqual(DeckStudioReceiptStore(url: url).checks.map { label($0.key) }, expected, "\(name) · reopened")
            for lookup in scenario["lookups"] as? [[String: Any]] ?? [] {
                XCTAssertEqual(store.status(for: try key(lookup)), try deckStudioStatus(lookup["status"]), "\(name) · \(lookup)")
            }
        }
        for (index, scenario) in try XCTUnwrap(root["generated"] as? [[String: Any]]).enumerated() {
            let name = scenario["name"] as? String ?? ""
            let url = directory.appendingPathComponent("generated-\(index).json")
            let store = DeckStudioReceiptStore(url: url)
            let summary = String(repeating: "x", count: scenario["summaryLength"] as? Int ?? 7)
            for deck in 0..<(try XCTUnwrap(scenario["decks"] as? Int)) {
                let raw: [String: Any] = ["deck": "local:\(deck)", "request": "r1", "upstream": "u1", "catalogue": "c1", "build": "10"]
                store.record(stored(try key(raw), at: Double(1000 + deck), valid: true, summary: summary))
            }
            let decks = store.checks.map(\.key.deckID)
            if let count = scenario["count"] as? Int { XCTAssertEqual(decks.count, count, name) }
            if let fewer = scenario["fewerThan"] as? Int { XCTAssertLessThan(decks.count, fewer, name); XCTAssertGreaterThan(decks.count, 0, name) }
            XCTAssertEqual(decks.first, scenario["first"] as? String, name)
            if let last = scenario["last"] as? String { XCTAssertEqual(decks.last, last, name) }
            for missing in scenario["missing"] as? [String] ?? [] { XCTAssertFalse(decks.contains(missing), "\(name) · \(missing)") }
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).intValue
            XCTAssertLessThanOrEqual(size, DeckStudioReceiptStore.maximumBytes, name)
            XCTAssertEqual(DeckStudioReceiptStore(url: url).checks.map(\.key.deckID), decks, "\(name) · reopened")
        }
        for (index, text) in try XCTUnwrap(root["corrupt"] as? [String]).enumerated() {
            let url = directory.appendingPathComponent("corrupt-\(index).json")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            XCTAssertEqual(DeckStudioReceiptStore(url: url).checks, [], "A corrupt file is a cache miss: \(text)")
        }
        for item in try XCTUnwrap(root["startResult"] as? [[String: Any]]) {
            XCTAssertEqual(DeckStudioPlayRules.storesStartResult(valid: try XCTUnwrap(item["valid"] as? Bool), issueCards: try XCTUnwrap(item["issueCards"] as? [String]),
                                                                 deckCards: try XCTUnwrap(item["deckCards"] as? [String]),
                                                                 alreadyPassed: try XCTUnwrap(item["alreadyPassed"] as? Bool)),
                           item["stores"] as? Bool, "\(item)")
        }
        for item in try XCTUnwrap(root["fixRows"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? ""
            let rows = try (try XCTUnwrap(item["rows"] as? [[String: Any]])).map(deckStudioRow)
            let canonical = item["canonical"] as? [String: String] ?? [:]
            let shown = DeckStudioPlayRules.fixRows(rows, cards: try XCTUnwrap(item["cards"] as? [String])) { canonical[$0] }
            XCTAssertEqual(shown, Set(try XCTUnwrap(item["rowsShown"] as? [Int]).map { rows[$0].id }), name)
        }
        func entry(_ raw: [String: Any]) throws -> DeckEntry {
            DeckEntry(cardName: try XCTUnwrap(raw["name"] as? String), quantity: raw["quantity"] as? Int ?? 1, section: raw["section"] as? String ?? "deck")
        }
        for item in try XCTUnwrap(root["unplayable"] as? [[String: Any]]) {
            let known = Set(try XCTUnwrap(item["known"] as? [String]))
            let deck = DeckList(name: "Case", commander: try (item["commander"] as? [String: Any]).map(entry),
                                entries: try (try XCTUnwrap(item["entries"] as? [[String: Any]])).map(entry))
            XCTAssertEqual(DeckStudioPlayRules.unplayableCards(deck) { known.contains($0) ? $0 : nil }, item["cards"] as? [String], item["name"] as? String ?? "")
        }
        for item in try XCTUnwrap(root["groups"] as? [[String: Any]]) {
            let issues = try (try XCTUnwrap(item["issues"] as? [[String: Any]])).enumerated().map { index, raw in
                DeckStudioStoredCheck.Issue(index: index, type: try XCTUnwrap(raw["type"] as? String), group: raw["group"] as? String,
                                            message: try XCTUnwrap(raw["message"] as? String), cardName: raw["cardName"] as? String)
            }
            let check = DeckStudioStoredCheck(key: DeckStudioCheckKey(deckID: "d", request: Data(), upstream: "u", catalogue: "c", appBuild: "b"),
                                              checkedAt: Date(), valid: false, summary: "Failed", issues: issues)
            XCTAssertEqual(check.groups.map { [$0.title, "\($0.issues.count)"] },
                           try XCTUnwrap(item["groups"] as? [[Any]]).map { ["\($0[0])", "\($0[1])"] })
            XCTAssertEqual(check.cardNames, item["cardNames"] as? [String])
        }
    }
}
