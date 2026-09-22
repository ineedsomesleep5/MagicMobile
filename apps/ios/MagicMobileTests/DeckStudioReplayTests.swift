import Foundation
import XCTest
@testable import MagicMobile

/// Synthetic seat-scoped polls verify the public observation boundary. They do
/// not prove native gameplay or reconstruct an XMage replay.
final class DeckStudioReplayTests: XCTestCase {
    private let match = UUID().uuidString
    private let viewer = UUID().uuidString
    private let rival = UUID().uuidString
    private let visible = UUID().uuidString
    private let hidden = UUID().uuidString
    private let spell = UUID().uuidString

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
    private func created() -> ([String: Any], [String: Any]) {
        let request: [String: Any] = ["protocol": 1, "op": "create", "configuration": ["seats": [
            ["seatId": "human", "controller": "human", "deck": ["name": "Public history fixture",
                "main": [["name": "Plains", "count": 99]],
                "commanders": [["name": "Isamaru", "count": 1]], "companions": []]],
            ["seatId": "ai", "controller": "ai"]]]]
        let reply: [String: Any] = ["protocol": 1, "ok": true, "result": ["matchId": match,
            "engine": ["engine": "xmage", "execution": "native-aot", "upstream": "fixture", "catalogueHash": "fixture"]]]
        return (request, reply)
    }
    private func poll(revision: Int, turn: Int, life: Int = 40, board: Bool = false,
                      ended: Bool = false, malformedSeat: Bool = false,
                      message: String = "RAW LOG SECRET") -> ([String: Any], [String: Any]) {
        let publicCard: [String: Any] = ["id": visible, "name": "Sol Ring", "displayName": "Sol Ring",
                                         "cardTypes": ["ARTIFACT"], "hideInfo": false]
        let privateCard: [String: Any] = ["id": hidden, "name": "SECRET CARD", "displayName": "SECRET CARD",
                                          "hideInfo": true, "faceDown": true]
        let playerView: [[String: Any]] = [
            ["playerId": viewer, "name": "You", "life": life, "battlefield": [:]],
            ["playerId": rival, "name": "Rival", "life": 40, "battlefield": board
                ? [visible: publicCard, hidden: privateCard] : [:]]]
        let source: [String: Any] = ["id": spell, "name": "Lightning Bolt", "displayName": "Lightning Bolt", "hideInfo": false]
        let stack: [String: Any] = board ? [spell: ["id": spell, "mageObjectType": "SPELL",
                                                       "displayName": "Lightning Bolt", "sourceCard": source]] : [:]
        let root: [String: Any] = ["schema": "xmage-gameview-v1", "enginePlayerId": viewer,
            "gameView": ["myPlayerId": viewer, "turn": turn, "step": "UPKEEP", "players": playerView,
                         "stack": stack, "myHand": [["name": "HAND SECRET"]]],
            "outcome": ["ended": ended, "winnerPlayerIds": ended ? [viewer] : []],
            "authorizedOpponentHands": ["secret": "OPPONENT HAND SECRET"]]
        let request: [String: Any] = ["protocol": 1, "op": "poll", "matchId": match, "viewerId": "human"]
        let reply: [String: Any] = ["protocol": 1, "ok": true, "result": [
            "matchId": match, "viewerId": malformedSeat ? "ai" : "human", "revision": revision,
            "phase": ended ? "ended" : "running", "snapshot": root,
            "events": [["revision": revision, "kind": "message", "body": ["message": message]]]]]
        return (request, reply)
    }
    private func observe(_ request: [String: Any], _ reply: [String: Any],
                         using accumulator: inout DeckStudioPlaytestAccumulator,
                         time: Double, detail: Bool = true) throws -> Bool {
        accumulator.observe(request: try data(request), response: try data(reply), enabled: true,
                            appBuild: "fixture", now: Date(timeIntervalSince1970: time),
                            detailedEnabled: detail, sanitizeLog: { EngineDisplayText.label($0) })
    }

    func testDetailedTimelineIsSeparateChoiceAndLegacyDecodeWorks() throws {
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000, detail: false))
        let (request, reply) = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(request, reply, using: &recorder, time: 1_010, detail: false))
        XCTAssertNil(recorder.game?.timeline)
        let old = try JSONDecoder().decode(DeckStudioRecordedGame.self,
                                          from: JSONEncoder().encode(try XCTUnwrap(recorder.game)))
        XCTAssertNil(old.timeline)
        XCTAssertTrue(try observe(request, poll(revision: 2, turn: 2).1,
                                  using: &recorder, time: 1_020, detail: true))
        XCTAssertNil(recorder.game?.timeline, "Enabling detail mid-match does not start a partial recording")
    }

    func testOnlyPublicStructuredObservationsPersistAndRepeatsDeduplicate() throws {
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000))
        let first = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(first.0, first.1, using: &recorder, time: 1_010))
        let second = poll(revision: 2, turn: 2, life: 37, board: true)
        XCTAssertTrue(try observe(second.0, second.1, using: &recorder, time: 1_020))
        XCTAssertFalse(try observe(second.0, second.1, using: &recorder, time: 1_021))
        let third = poll(revision: 3, turn: 2, life: 37, board: true, ended: true)
        XCTAssertTrue(try observe(third.0, third.1, using: &recorder, time: 1_030))
        let game = try XCTUnwrap(recorder.game)
        try game.validate()
        let timeline = try XCTUnwrap(game.timeline)
        XCTAssertEqual(timeline.samples.map(\.turn), [1, 2])
        XCTAssertEqual(timeline.samples[1].players.first?.life, 37)
        XCTAssertEqual(timeline.samples[1].players.last?.battlefieldCount, 2)
        XCTAssertEqual(timeline.events.filter { $0.kind == .battlefieldAppearance }.compactMap(\.cardName), ["Sol Ring"])
        XCTAssertEqual(timeline.events.filter { $0.kind == .spellOnStack }.compactMap(\.cardName), ["Lightning Bolt"])
        XCTAssertEqual(timeline.events.filter { $0.kind == .outcome }.compactMap(\.outcome), ["won"])
        let persisted = try XCTUnwrap(String(data: JSONEncoder().encode(game), encoding: .utf8))
        for secret in ["SECRET CARD", "HAND SECRET", "OPPONENT HAND SECRET", "RAW LOG SECRET", visible, hidden, spell] {
            XCTAssertFalse(persisted.contains(secret), "Private or transient source leaked: \(secret)")
        }
    }

    func testWrongSeatAndMalformedHistoryCannotAdvanceTimeline() throws {
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000))
        let invalid = poll(revision: 1, turn: 1, malformedSeat: true)
        XCTAssertFalse(try observe(invalid.0, invalid.1, using: &recorder, time: 1_010))
        XCTAssertEqual(recorder.game?.lastRevision, -1)
        XCTAssertTrue(recorder.game?.timeline?.samples.isEmpty == true)
        let good = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(good.0, good.1, using: &recorder, time: 1_011))
        var corrupted = try XCTUnwrap(recorder.game)
        let duplicatePlayers = try XCTUnwrap(corrupted.timeline?.samples.first?.players)
        corrupted.timeline?.samples.append(.init(revision: 1, turn: 1, observedAt: corrupted.observedAt,
                                                  players: duplicatePlayers))
        XCTAssertThrowsError(try corrupted.validate())
    }

    func testOnlyAllowlistedPublicLogTemplatesBecomeStructuredEvents() throws {
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000))
        let baseline = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(baseline.0, baseline.1, using: &recorder, time: 1_010))
        let cast = poll(revision: 2, turn: 2, board: true, message: "<b>Rival casts Sol Ring.</b>")
        XCTAssertTrue(try observe(cast.0, cast.1, using: &recorder, time: 1_020))
        var damage = poll(revision: 3, turn: 2, life: 35, board: true,
                          message: "Sol Ring deals 5 damage to You")
        var damageResult = try XCTUnwrap(damage.1["result"] as? [String: Any])
        damageResult["events"] = [
            ["revision": 2, "kind": "message", "body": ["message": "Rival casts Sol Ring"]],
            ["revision": 3, "kind": "message", "body": ["message": "Sol Ring deals 5 damage to You"]]
        ]
        damage.1["result"] = damageResult
        XCTAssertTrue(try observe(damage.0, damage.1, using: &recorder, time: 1_030))
        let life = poll(revision: 4, turn: 2, life: 35, board: true, message: "Rival gains 3 life")
        XCTAssertTrue(try observe(life.0, life.1, using: &recorder, time: 1_040))
        let phase = poll(revision: 5, turn: 2, life: 35, board: true, message: "PHASE: UPKEEP")
        XCTAssertTrue(try observe(phase.0, phase.1, using: &recorder, time: 1_050))
        let privateDraw = poll(revision: 6, turn: 2, life: 35, board: true,
                               message: "Rival draws SECRET CARD")
        XCTAssertTrue(try observe(privateDraw.0, privateDraw.1, using: &recorder, time: 1_060))
        let game = try XCTUnwrap(recorder.game)
        try game.validate()
        let timeline = try XCTUnwrap(game.timeline)
        XCTAssertEqual(timeline.events.filter { $0.kind == .cast }.compactMap(\.cardName), ["Sol Ring"])
        XCTAssertEqual(timeline.events.filter { $0.kind == .damage }.compactMap(\.amount), [5])
        XCTAssertEqual(timeline.events.filter { $0.kind == .lifeChange }.compactMap(\.amount), [3])
        XCTAssertEqual(timeline.events.filter { $0.kind == .phase }.compactMap(\.phaseName), ["UPKEEP"])
        XCTAssertEqual(timeline.samples.last?.players.first?.life, 35)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(game), encoding: .utf8))
        XCTAssertFalse(json.contains("SECRET CARD"))
        XCTAssertFalse(json.contains("<b>"))
        XCTAssertFalse(json.contains("Rival casts"), "Only typed fields, not raw log text, are retained")
    }

    func testTerminalPollWithoutPlayersStillRecordsExplicitOutcome() throws {
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000))
        let baseline = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(baseline.0, baseline.1, using: &recorder, time: 1_010))
        var terminal = poll(revision: 2, turn: 2, ended: true).1
        var result = try XCTUnwrap(terminal["result"] as? [String: Any])
        var snapshot = try XCTUnwrap(result["snapshot"] as? [String: Any])
        var view = try XCTUnwrap(snapshot["gameView"] as? [String: Any])
        view["players"] = []
        snapshot["gameView"] = view
        result["snapshot"] = snapshot
        terminal["result"] = result
        XCTAssertTrue(try observe(poll(revision: 2, turn: 2).0, terminal,
                                  using: &recorder, time: 1_020))
        let game = try XCTUnwrap(recorder.game)
        XCTAssertEqual(game.end, .completed)
        XCTAssertEqual(game.won, true)
        XCTAssertEqual(game.timeline?.events.last?.kind, .outcome)
        XCTAssertEqual(game.timeline?.events.last?.outcome, "won")
        try game.validate()
    }

    func testDisablingDetailPreservesSavedTimelineWithoutAddingMore() async throws {
        let suite = "deckstudio-replay-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeckStudioPlaytestStore(directory: directory, defaults: defaults)
        await store.setEnabled(true)
        await store.setDetailedEnabled(true)
        let admission = await store.admission()
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000))
        let first = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(first.0, first.1, using: &recorder, time: 1_010))
        let firstSave = await store.record(try XCTUnwrap(recorder.game), admission: admission)
        XCTAssertTrue(firstSave)
        let before = try await store.summaries()
        XCTAssertNotNil(before.first?.timeline)
        await store.setDetailedEnabled(false)
        let secondSave = await store.record(try XCTUnwrap(recorder.game), admission: admission)
        XCTAssertTrue(secondSave)
        let after = try await store.summaries()
        XCTAssertEqual(after.first?.timeline, before.first?.timeline)
        var revoked = try XCTUnwrap(recorder.game)
        revoked.timeline = nil
        await store.setDetailedEnabled(true)
        let reenabledSave = await store.record(revoked, admission: admission)
        XCTAssertTrue(reenabledSave)
        let reenabled = try await store.summaries()
        XCTAssertEqual(reenabled.first?.timeline, before.first?.timeline,
                       "Re-enabling applies to future matches and must not erase retained detail")
    }

    func testMalformedSavedTimelineIsRejectedAndFileIsPreserved() async throws {
        let suite = "deckstudio-replay-corrupt-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var recorder = DeckStudioPlaytestAccumulator()
        let (start, accepted) = created()
        XCTAssertTrue(try observe(start, accepted, using: &recorder, time: 1_000))
        let first = poll(revision: 1, turn: 1)
        XCTAssertTrue(try observe(first.0, first.1, using: &recorder, time: 1_010))
        let game = try XCTUnwrap(recorder.game)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        var timeline = try XCTUnwrap(object["timeline"] as? [String: Any])
        var samples = try XCTUnwrap(timeline["samples"] as? [[String: Any]])
        samples[0]["revision"] = 10_000
        timeline["samples"] = samples
        object["timeline"] = timeline
        let corrupt = try JSONSerialization.data(withJSONObject: ["schema": 1, "games": [object]])
        let url = directory.appendingPathComponent("summaries-v1.json")
        try corrupt.write(to: url)
        let store = DeckStudioPlaytestStore(directory: directory, defaults: defaults)
        await store.setEnabled(true)
        await store.setDetailedEnabled(true)
        let admission = await store.admission()
        do { _ = try await store.summaries(); XCTFail("Expected validation failure") }
        catch { }
        let saved = await store.record(game, admission: admission)
        XCTAssertFalse(saved)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}
