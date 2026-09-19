import Foundation

@main struct ObservationChecks {
    static var checks = 0
    static func check(_ value: Bool, _ label: String) { checks += 1; if !value { fatalError(label) } }
    static func rejects(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch { checks += 1 } }
    static func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    static func input(_ op: String, _ fields: [String: Any] = [:]) -> Data { json(fields.merging(["protocol": 1, "op": op]) { _, n in n }) }
    static func output(_ result: [String: Any], ok: Bool = true) -> Data { json(["protocol": 1, "ok": ok, "result": result]) }
    static let match = "11111111-1111-1111-1111-111111111111"
    static let viewer = "22222222-2222-2222-2222-222222222222"
    static let other = "33333333-3333-3333-3333-333333333333"
    static let start = Date(timeIntervalSince1970: 1_789_584_000)
    static var deck: [String: Any] { ["name": "My deck", "main": [["name": "Forest", "count": 99]], "commanders": [["name": "Commander", "count": 1]], "companions": []] }
    static func create(_ humans: Int = 1, _ engine: String = "native-aot") -> (Data, Data) {
        let seats: [[String: Any]] = [ ["seatId": "local", "controller": "human", "name": "Local", "deck": deck], ["seatId": "ai", "controller": humans > 1 ? "human" : "ai", "name": "Other", "deck": deck] ]
        return (input("create", ["configuration": ["seats": seats]]), output(["matchId": match, "seats": ["local", "ai"], "engine": ["engine": "xmage", "execution": engine, "upstream": "pin", "catalogueHash": "catalogue"]]))
    }
    static func poll(_ revision: Int, turn: Int = 1, casts: Int = 0, ended: Bool = false, winner: String? = nil, seat: String = "local", player: String = viewer) -> (Data, Data) {
        let root: [String: Any] = ["schema": "xmage-gameview-v1", "enginePlayerId": player,
            "gameView": ["myPlayerId": player, "turn": turn, "myHand": ["SECRET": ["name": "This must never be retained"]]],
            "commanders": ["public-id": ["ownerPlayerId": player, "name": "Commander", "castsFromCommandZone": casts],
                           "opponent-id": ["ownerPlayerId": other, "name": "Opponent Commander", "castsFromCommandZone": 99]],
            "outcome": ["ended": ended, "winnerPlayerIds": winner.map { [$0] } ?? []]]
        return (input("poll", ["matchId": match, "viewerId": seat, "after": 0]), output(["matchId": match, "viewerId": seat, "revision": revision, "phase": "running", "snapshot": root]))
    }
    static func main() async throws {
        let d = try DeckStudioDeckSignature.native(deck)
        check(d.rows.count == 2, "signature sections")
        let split = try DeckStudioDeckSignature(rows: [.init(name: "Forest", count: 30, section: "main"), .init(name: "Commander", count: 1, section: "commanders"), .init(name: "Forest", count: 69, section: "main")])
        check(d == split, "row-order/printing independent, quantity preserving")
        check(d != (try DeckStudioDeckSignature(rows: [.init(name: "Forest", count: 99, section: "commanders"), .init(name: "Commander", count: 1, section: "main")])), "roles retained")
        for count in [-1, 0, 2001, Int.max] { rejects { _ = try DeckStudioDeckSignature(rows: [.init(name: "Forest", count: count, section: "main")]) } }
        rejects { _ = try DeckStudioDeckSignature(rows: [.init(name: "Forest", count: 1, section: "maybeboard")]) }
        rejects { _ = try DeckStudioDeckSignature.native(["main": [["name": "Forest", "count": true]], "commanders": [], "companions": []]) }
        check(DeckStudioJSON.integer(true) == nil && DeckStudioJSON.boolean(1) == nil, "bool is not an integer")
        var machine = DeckStudioPlaytestAccumulator()
        let (make, made) = create()
        check(!machine.observe(request: make, response: made, enabled: false, appBuild: "test", now: start), "opt-in required")
        let (multiplayer, multiplayerReply) = create(2)
        check(!machine.observe(request: multiplayer, response: multiplayerReply, enabled: true, appBuild: "test", now: start), "no multi-human recording")
        let (jvm, jvmReply) = create(1, "jvm")
        check(!machine.observe(request: jvm, response: jvmReply, enabled: true, appBuild: "test", now: start), "native-only production admission")
        check(!machine.observe(request: make, response: output([:], ok: false), enabled: true, appBuild: "test", now: start), "failed create does not count as a game")
        check(machine.observe(request: make, response: made, enabled: true, appBuild: "test", now: start), "successful native create captured")
        check(machine.game?.deck == d && machine.game?.aiOpponents == 1, "playing signature and actual AI count")
        let first = poll(1, turn: 4, casts: 1)
        check(machine.observe(request: first.0, response: first.1, enabled: true, appBuild: "test", now: start.addingTimeInterval(60)), "native snapshot observation")
        check(machine.game?.observedTurn == 4 && machine.game?.commandZoneCasts == ["Commander": 1], "public own watcher only")
        check(!machine.observe(request: first.0, response: first.1, enabled: true, appBuild: "test", now: start.addingTimeInterval(90)), "duplicate revision ignored")
        let badSeat = poll(9, seat: "ai")
        check(!machine.observe(request: badSeat.0, response: badSeat.1, enabled: true, appBuild: "test", now: start), "another seat ignored")
        let replacedViewer = poll(2, turn: 999, casts: 99, player: other)
        _ = machine.observe(request: replacedViewer.0, response: replacedViewer.1, enabled: true, appBuild: "test", now: start.addingTimeInterval(70))
        check(machine.game?.observedTurn == 4 && machine.game?.commandZoneCasts["Commander"] == 1, "bound native player cannot change")
        let last = poll(3, turn: 8, casts: 2, ended: true, winner: viewer)
        _ = machine.observe(request: last.0, response: last.1, enabled: true, appBuild: "test", now: start.addingTimeInterval(180))
        let complete = machine.game!
        check(complete.end == .completed && complete.won == true && complete.elapsedSeconds == 180, "explicit native outcome only")
        _ = machine.close(now: start.addingTimeInterval(200))
        check(machine.game == complete, "cleanup never overwrites completion")
        let encoded = try JSONEncoder().encode(complete)
        check(!String(decoding: encoded, as: UTF8.self).contains("SECRET") && !String(decoding: encoded, as: UTF8.self).contains("Opponent Commander"), "no hand or opponent identities persisted")
        try complete.validate()
        for end in ["destroy", "close"] {
            var m = DeckStudioPlaytestAccumulator()
            _ = m.observe(request: make, response: made, enabled: true, appBuild: "test", now: start)
            if end == "destroy" { _ = m.observe(request: input("destroy", ["matchId": match]), response: output(["destroyed": true]), enabled: true, appBuild: "test", now: start.addingTimeInterval(10)) }
            else { _ = m.close(now: start.addingTimeInterval(10)) }
            check(m.game?.end == (end == "destroy" ? .left : .interrupted) && m.game?.won == nil, "leaving is not a loss")
        }
        let request = json(deck)
        let success = json(["valid": true, "validator": "Commander", "issues": [], "upstream": "pin", "catalogueHash": "catalogue"])
        let receipt = try DeckStudioValidationReceipt.success(result: success, request: request, upstream: "pin", catalogue: "catalogue", appBuild: "42")
        check(receipt.valid && receipt.matches(request: request, upstream: "pin", catalogue: "catalogue", appBuild: "42"), "exact native receipt")
        check(!receipt.matches(request: json(["name": "Changed"]), upstream: "pin", catalogue: "catalogue", appBuild: "42"), "edited deck invalidates receipt")
        check(!receipt.matches(request: request, upstream: "pin2", catalogue: "catalogue", appBuild: "42"), "engine upgrade invalidates")
        check(!receipt.matches(request: request, upstream: "pin", catalogue: "catalogue", appBuild: "43"), "app upgrade invalidates")
        rejects { _ = try DeckStudioValidationReceipt.success(result: success, request: request, upstream: "wrong", catalogue: "catalogue", appBuild: "42") }
        rejects { _ = try DeckStudioValidationReceipt.success(result: json(["valid": 1]), request: request, upstream: "pin", catalogue: "catalogue", appBuild: "42") }
        let issues = json(["validator": "Commander", "issues": [["type": "ERROR", "group": NSNull(), "cardName": "Named card", "message": "Exact native error <unchanged>"]]])
        let rejected = try DeckStudioValidationReceipt.rejection(details: issues, message: "Native rejection", request: request, upstream: "pin", catalogue: "catalogue", appBuild: "42")
        check(!rejected.valid && rejected.issues[0].message == "Exact native error <unchanged>" && rejected.issues[0].group == nil, "native issue detail retained")
        rejects { _ = try DeckStudioValidationReceipt.rejection(details: json(["validator": "Commander", "issues": []]), message: "Error", request: request, upstream: "pin", catalogue: "cat", appBuild: "42") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deck-studio-test-" + UUID().uuidString)
        let suite = "deck-studio-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: dir); defaults.removePersistentDomain(forName: suite) }
        let store = DeckStudioPlaytestStore(directory: dir, defaults: defaults)
        check(!(await store.admission()).enabled, "recording defaults off")
        await store.setEnabled(true)
        let admission = await store.admission()
        check(await store.record(complete, admission: admission), "summary saved")
        check(try await store.summaries() == [complete], "recorded summary available")
        let reload = DeckStudioPlaytestStore(directory: dir, defaults: defaults)
        check(try await reload.summaries() == [complete], "durable reload")
        try await store.clear()
        check(!(await store.record(complete, admission: admission)), "late session cannot repopulate cleared history")
        check(try await store.summaries().isEmpty, "clear remains empty")
        let newAdmission = await store.admission()
        await store.setEnabled(false)
        check(!(await store.record(complete, admission: newAdmission)), "disabling stops persistence")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = Data("corrupt but valuable".utf8)
        let file = dir.appendingPathComponent("summaries-v1.json")
        try bad.write(to: file)
        let corrupted = DeckStudioPlaytestStore(directory: dir, defaults: defaults)
        do { _ = try await corrupted.summaries(); check(false, "corruption must report") } catch { check(true, "corruption reported") }
        await corrupted.setEnabled(true)
        check(!(await corrupted.record(complete, admission: await corrupted.admission())), "corrupt file not overwritten")
        check(try Data(contentsOf: file) == bad, "original remains intact")
        try await corrupted.clear()
        check(try await corrupted.summaries().isEmpty, "explicit deletion recovers corruption")
        print("PASS: \(checks) recording, privacy, storage and validation receipt checks. Synthetic native envelopes, not a phone gameplay result.")
    }
}
