import Foundation

@main struct RecordingCompletionChecks {
    static var checks = 0
    static func check(_ value: Bool, _ name: String) { checks += 1; if !value { fatalError("FAIL: \(name)") } }
    static func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: .sortedKeys) }
    static let match = "00000000-0000-0000-0000-000000000001"
    static let viewer = "00000000-0000-0000-0000-000000000002"
    static let other = "00000000-0000-0000-0000-000000000003"
    static let date = Date(timeIntervalSince1970: 1_789_596_000)
    static func start() throws -> DeckStudioPlaytestAccumulator {
        let deck: [String: Any] = ["name": "Test deck", "main": [["name": "Forest", "count": 99]], "commanders": [["name": "Commander", "count": 1]], "companions": []]
        let request: [String: Any] = ["protocol": 1, "op": "create", "configuration": ["seats": [["seatId": "human", "controller": "human", "deck": deck], ["seatId": "ai", "controller": "ai", "deck": deck]]]]
        let response: [String: Any] = ["protocol": 1, "ok": true, "result": ["matchId": match, "engine": ["engine": "xmage", "execution": "native-aot", "upstream": "pin", "catalogueHash": "hash"]]]
        var accumulator = DeckStudioPlaytestAccumulator()
        check(accumulator.observe(request: try data(request), response: try data(response), enabled: true, appBuild: "test", now: date), "valid create")
        return accumulator
    }
    @discardableResult static func poll(_ acc: inout DeckStudioPlaytestAccumulator, revision: Int, phase: String = "running", root: [String: Any]? = nil, time: Date = date, enabled: Bool = true) throws -> Bool {
        var result: [String: Any] = ["matchId": match, "viewerId": "human", "revision": revision, "phase": phase]
        if let root { result["snapshot"] = root }
        return acc.observe(request: try data(["protocol": 1, "op": "poll", "matchId": match, "viewerId": "human"]), response: try data(["protocol": 1, "ok": true, "result": result]), enabled: enabled, appBuild: "test", now: time)
    }
    static func root(_ id: String = viewer, turn: Int = 2) -> [String: Any] {
        ["schema": "xmage-gameview-v1", "enginePlayerId": id, "gameView": ["myPlayerId": id, "turn": turn]]
    }
    static func main() throws {
        var acc = try start()
        try poll(&acc, revision: 1, root: root())
        try poll(&acc, revision: 2, phase: "failed")
        check(acc.game?.end == .engineFailed, "actual lowercase engine failure is terminal")
        check(acc.game?.won == nil, "engine failure is not a loss")
        let terminal = acc.game
        check(try !poll(&acc, revision: 3, root: root(turn: 999)), "terminal history immutable")
        check(acc.game == terminal, "late poll cannot rewrite terminal game")
        acc = try start()
        try poll(&acc, revision: 1, phase: "closed")
        check(acc.game?.end == .interrupted, "closed without completed outcome is interruption")
        acc = try start()
        try poll(&acc, revision: 1, phase: "ended")
        check(acc.game?.end == .completed && acc.game?.won == nil, "engine-ended without winner stays unknown result")
        acc = try start()
        try poll(&acc, revision: 1, root: root())
        let first = acc.game
        check(try !poll(&acc, revision: 99, root: root(other)), "wrong nested viewer rejected atomically")
        check(acc.game == first, "bad nested view does not advance watermark")
        check(try poll(&acc, revision: 2, root: root(turn: 3)), "later correct snapshot still accepted")
        check(acc.game?.observedTurn == 3, "right viewer's turn updated")
        check(try !poll(&acc, revision: 3, phase: "mystery"), "unknown lifecycle not accepted")
        check(try !poll(&acc, revision: 3, enabled: false), "disabled observation does not collect")
        check(try !poll(&acc, revision: 3, time: Date(timeIntervalSince1970: .infinity)), "nonfinite clock rejected")
        check(try !poll(&acc, revision: -1), "negative revision rejected")
        var complete = root()
        complete["outcome"] = ["ended": true, "winnerPlayerIds": [viewer]]
        try poll(&acc, revision: 4, phase: "ended", root: complete, time: date.addingTimeInterval(90))
        check(acc.game?.won == true, "only explicit winner is a win")
        check(acc.game?.elapsedSeconds == 90, "recorded elapsed from accepted time")
        try acc.game!.validate()
        var corrupt = acc.game!
        corrupt.observedAt = Date(timeIntervalSince1970: .infinity)
        do { try corrupt.validate(); check(false, "infinite date must fail") } catch { check(true, "infinite date rejected") }
        corrupt = acc.game!; corrupt.finishedAt = date.addingTimeInterval(-1)
        do { try corrupt.validate(); check(false, "backward date must fail") } catch { check(true, "backward date rejected") }
        corrupt = acc.game!; corrupt.commandZoneCasts = ["Not this deck's commander": 3]
        do { try corrupt.validate(); check(false, "unrelated card cannot enter persisted summary") } catch { check(true, "commander identity validated") }
        acc = try start()
        try poll(&acc, revision: 1, root: root(), time: date.addingTimeInterval(100))
        let destroyed = acc.observe(request: try data(["protocol": 1, "op": "destroy", "matchId": match]), response: try data(["protocol": 1, "ok": true, "result": ["destroyed": true]]), enabled: true, appBuild: "test", now: date.addingTimeInterval(10))
        check(destroyed && acc.game?.end == .left, "acknowledged destruction is a deliberate leave")
        check(acc.game?.observedAt == date.addingTimeInterval(100), "clock rollback does not lose elapsed history")
        print("PASS: \(checks) additional recording-integrity assertions; synthetic protocol inputs, no gameplay simulation.")
    }
}
