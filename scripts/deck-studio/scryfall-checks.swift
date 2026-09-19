import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor ScryfallFixture: DeckStudioScryfallHTTP {
    var replies: [Data]
    var requests: [URLRequest] = []
    var hold = false
    private var pending: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    init(_ replies: [Data], hold: Bool = false) { self.replies = replies; self.hold = hold }
    func send(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        if hold { await withCheckedContinuation { pending = $0; waiting?.resume(); waiting = nil } }
        guard !replies.isEmpty else { throw DeckStudioScryfallError.unavailable }
        return replies.removeFirst()
    }
    func started() async { if pending == nil { await withCheckedContinuation { waiting = $0 } } }
    func release() { hold = false; pending?.resume(); pending = nil }
    func count() -> Int { requests.count }
}
@main struct ScryfallChecks {
    static var count = 0
    static func check(_ condition: Bool, _ label: String) { count += 1; if !condition { fatalError(label) } }
    static func reject(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch { count += 1 } }
    static func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
    static var card: [String: Any] { ["object": "card", "id": "11111111-1111-1111-1111-111111111111", "oracle_id": "22222222-2222-2222-2222-222222222222", "name": "Fixture Card", "mana_cost": "{1}{U}", "cmc": 2, "type_line": "Instant", "oracle_text": "Fixture text only", "color_identity": ["U"], "legalities": ["commander": "legal"], "related_uris": ["edhrec": "https://edhrec.com/cards/fixture-card"], "scryfall_uri": "https://scryfall.com/card/set/1/fixture-card"] }
    static func main() async throws {
        let watchdog = Task.detached { do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }; fatalError("Scryfall fixture checks timed out") }
        defer { watchdog.cancel() }
        let req = try DeckStudioScryfallClient.request("A & B?exact=other")
        let parts = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        check(parts.host == "api.scryfall.com" && parts.path == "/cards/named", "fixed origin")
        check(parts.queryItems == [URLQueryItem(name: "exact", value: "A & B?exact=other")], "literal single name parameter")
        check(req.value(forHTTPHeaderField: "User-Agent") == "MagicMobile-DeckStudio/2.0" && req.value(forHTTPHeaderField: "Accept") == "application/json", "explicit headers")
        check(req.value(forHTTPHeaderField: "Authorization") == nil && !req.httpShouldHandleCookies, "no private credentials")
        for input in ["", "\n", "Bad\nName", String(repeating: "x", count: 513)] { reject { _ = try DeckStudioScryfallClient.request(input) } }
        for page in [0, -1, 11] { reject { _ = try DeckStudioScryfallClient.request("dragon", page: page) } }
        let search = try DeckStudioScryfallClient.request("t:dragon id<=UR", page: 2)
        check(URLComponents(url: search.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == "t:dragon id<=UR", "search expression remains query data")
        let decoded = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: json(card)).validated()
        check(decoded.manaValue == 2 && decoded.colorIdentity == ["U"] && decoded.oracleID != nil, "typed metadata")
        check(decoded.edhrecURL?.host == "edhrec.com", "provider page link validated")
        for url in ["http://edhrec.com/a", "https://edhrec.com.evil.test/a", "https://user:secret@edhrec.com/a", "file:///etc/passwd", "javascript:alert(1)", "https://edhrec.com:99/a"] {
            check(DeckStudioScryfallCard.safeWebURL(url, hosts: ["edhrec.com"]) == nil, "unsafe web link not exposed")
        }
        var faces = card; faces.removeValue(forKey: "oracle_text")
        faces["card_faces"] = [["name": "Front", "oracle_text": "Front text"], ["name": "Back", "oracle_text": "Back text"]]
        let mdfc = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: json(faces)).validated()
        check(mdfc.faces?.count == 2 && mdfc.oracleText == nil, "faces retained rather than inventing combined rules")
        var bad = card; bad["cmc"] = -1
        reject { _ = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: json(bad)).validated() }
        bad = card; bad["color_identity"] = ["Q"]
        reject { _ = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: json(bad)).validated() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scryfall-checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = ScryfallFixture([json(card), json(["object": "list", "data": [card], "has_more": true])])
        let client = DeckStudioScryfallClient(transport: fixture, directory: dir, pace: false)
        check(try await client.named("Fixture Card", allowNetwork: false) == nil, "offline miss is harmless")
        check(await fixture.count() == 0, "offline does not call transport")
        let fetched = try await client.named("Fixture Card", allowNetwork: true)
        check(fetched?.cached == false && fetched?.card.id == decoded.id, "explicit lookup works")
        check(try await client.named("Fixture Card", allowNetwork: false)?.cached == true, "offline cached result")
        check(await fixture.count() == 1, "no duplicate request for cached card")
        let page = try await client.search("t:dragon", allowNetwork: true)
        check(page?.hasMore == true && page?.cards.count == 1, "one page and has-more state")
        check(await fixture.count() == 2, "pagination never automatically fetched")
        let offline = DeckStudioScryfallClient(transport: ScryfallFixture([]), directory: dir, pace: false)
        check(try await offline.named("Fixture Card", allowNetwork: false)?.card == decoded, "disk cache reload")
        check(try await offline.named("Other Card", allowNetwork: false) == nil, "cache keyed to exact request")
        let held = ScryfallFixture([json(card)], hold: true)
        let cancelClient = DeckStudioScryfallClient(transport: held, directory: nil, pace: false)
        let task = Task { try await cancelClient.named("Fixture Card", allowNetwork: true) }
        await held.started(); task.cancel(); await held.release()
        do { _ = try await task.value; check(false, "cancel expected") } catch { check(error is CancellationError, "cancelled response rejected") }
        check(try await cancelClient.named("Fixture Card", allowNetwork: false) == nil, "cancelled response not cached")
        let clearing = ScryfallFixture([json(card)], hold: true)
        let clearClient = DeckStudioScryfallClient(transport: clearing, directory: dir, pace: false)
        let pending = Task { try await clearClient.named("Fresh Card", allowNetwork: true) }
        await clearing.started(); try await clearClient.clearCache(); await clearing.release()
        do { _ = try await pending.value; check(false, "clear expected") } catch { check(error is CancellationError, "clear invalidates suspended request") }
        check(try await clearClient.named("Fresh Card", allowNetwork: false) == nil, "cleared data not restored")
        let malformed = DeckStudioScryfallClient(transport: ScryfallFixture([json(["object": "card", "name": "missing UUID"])]), directory: nil, pace: false)
        do { _ = try await malformed.named("Broken", allowNetwork: true); check(false, "schema failure expected") } catch { check(true, "bad schema fails") }
        check(try await malformed.named("Broken", allowNetwork: false) == nil, "bad metadata not cached")
        let budget = DeckStudioScryfallBudget()
        try await budget.reserve()
        let began = ProcessInfo.processInfo.systemUptime
        try await budget.reserve()
        check(ProcessInfo.processInfo.systemUptime - began >= 0.50, "shared request spacing")
        await budget.backOff(30)
        do { try await budget.reserve(); check(false, "backoff expected") } catch { check((error as? DeckStudioScryfallError) == .rateLimited, "backoff stops requests") }
        print("PASS: \(count) optional Scryfall metadata/search/cache checks. Injected provider fixtures, not live service or phone execution.")
    }
}
