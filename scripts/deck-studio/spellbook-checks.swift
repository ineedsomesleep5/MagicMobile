import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Synthetic public-API fixtures and injected HTTP, not live provider or MTG gameplay evidence.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_789_584_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval = 3) { lock.lock(); value.addTimeInterval(interval); lock.unlock() }
}
private actor FixtureTransport: SpellbookHTTPTransport {
    enum Response: Sendable { case data(Data), failure(SpellbookError), held(Data) }
    var responses: [Response]
    var requests: [URLRequest] = []
    private var held: CheckedContinuation<Void, Never>?
    private var starters: [CheckedContinuation<Void, Never>] = []
    init(_ responses: [Response]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        guard !responses.isEmpty else { throw SpellbookError.unavailable }
        switch responses.removeFirst() {
        case .data(let data): return data
        case .failure(let error): throw error
        case .held(let data):
            await withCheckedContinuation { held = $0; starters.forEach { $0.resume() }; starters.removeAll() }
            return data // Deliberately ignores cancellation; production must reject late data.
        }
    }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { starters.append($0) }
    }
    func release() { let pending = held; held = nil; pending?.resume() }
    func count() -> Int { requests.count }
    func all() -> [URLRequest] { requests }
}

private final class FixtureURLProtocol: URLProtocol {
    enum Mode { case valid(Data), oversizedHeader, oversizedBody, wait }
    private static let lock = NSLock()
    private static var mode: Mode = .wait
    static func configure(_ mode: Mode) { lock.lock(); self.mode = mode; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let mode = Self.mode; Self.lock.unlock()
        if case .wait = mode { return }
        var headers = ["Content-Type": "application/json"]
        if case .oversizedHeader = mode { headers["Content-Length"] = "5000000" }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        switch mode {
        case .valid(let data): client?.urlProtocol(self, didLoad: data)
        case .oversizedBody: client?.urlProtocol(self, didLoad: Data(repeating: 32, count: SpellbookAPI.maximumResponseBytes + 1))
        default: break
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
struct SpellbookChecks {
    static var assertions = 0
    static func check(_ condition: Bool, _ label: String) {
        assertions += 1
        if !condition { fatalError("FAIL: \(label)") }
    }
    static func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); check(false, label) } catch { check(true, label) }
    }
    static func use(_ name: String, quantity: Int = 1, commander: Bool = false) -> [String: Any] {
        ["card": ["id": name == "Alpha" ? 1 : 2, "name": name, "oracleId": NSNull()],
         "quantity": quantity, "mustBeCommander": commander, "zoneLocations": ["B"],
         "battlefieldCardState": "Untapped", "exileCardState": "", "libraryCardState": "", "graveyardCardState": ""]
    }
    static func variant(_ id: String = "1-2", uses: [[String: Any]]? = nil, templates: [[String: Any]] = [],
                        identity: String = "G", legal: Bool = true, spoiler: Bool = false) -> [String: Any] {
        ["id": id, "uses": uses ?? [use("Alpha"), use("Beta")], "requires": templates,
         "produces": [["feature": ["name": "Example result"], "quantity": 1]],
         "identity": identity, "status": "OK", "spoiler": spoiler, "legalities": ["commander": legal],
         "description": "Example steps", "easyPrerequisites": "Example prerequisite",
         "notablePrerequisites": "Needs a game state", "manaNeeded": "{1}", "notes": "Not actual card advice"]
    }
    static func page(_ items: [String: [[String: Any]]] = [:], next: String? = nil) throws -> Data {
        var results: [String: Any] = ["identity": "G"]
        for group in SpellbookGroup.allCases { results[group.rawValue] = items[group.rawValue] ?? [] }
        return try JSONSerialization.data(withJSONObject: ["count": NSNull(), "next": next as Any? ?? NSNull(), "results": results])
    }
    static func decodeVariant(_ object: [String: Any]) throws -> SpellbookVariant {
        try JSONDecoder().decode(SpellbookVariant.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static func deck(_ names: [String] = ["Alpha"]) throws -> SpellbookDeck {
        try SpellbookDeck(main: names.map { .init(card: $0, quantity: 1) }, commanders: [.init(card: "Commander", quantity: 1)])
    }
    static func assess(_ object: [String: Any], deck: SpellbookDeck, colors: [String]? = ["G"], group: SpellbookGroup = .almostIncluded,
                       resolve: (String) -> String? = { $0 }) throws -> SpellbookAssessment {
        SpellbookAssessment.make(variant: try decodeVariant(object), group: group, deck: deck,
                                commanderColors: colors, canonicalName: resolve)
    }
    static func main() async throws {
        // Only a failure watchdog uses wall time. Successful race tests use gates,
        // not assumptions about macOS task/timer scheduling.
        let watchdog = Task.detached {
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            fatalError("Spellbook checks deadlocked or exceeded 30 seconds")
        }
        defer { watchdog.cancel() }
        let first = try deck(), complete = try deck(["Alpha", "Beta"])
        let duplicate = try SpellbookDeck(main: [.init(card: " Alpha ", quantity: 1), .init(card: "Alpha", quantity: 2)], commanders: [.init(card: "Commander", quantity: 1)])
        check(duplicate.main == [.init(card: "Alpha", quantity: 3)], "quantity-aware normalization")
        check(try deck(["Beta", "Alpha"]).encoded() == complete.encoded(), "stable request identity across row order")
        check(try complete.encoded() != first.encoded(), "different card input has different identity")
        check(try SpellbookDeck(main: [.init(card: "Commander", quantity: 1)], commanders: [.init(card: "Alpha", quantity: 1)]).encoded() != first.encoded(), "commander and main roles never conflated")
        for name in ["", "123", "Bad\nName", String(repeating: "x", count: 257)] {
            rejects("invalid name \(name.prefix(5))") { _ = try SpellbookDeck(main: [.init(card: name, quantity: 1)], commanders: first.commanders) }
        }
        for count in [0, -1, 2001] { rejects("invalid quantity") { _ = try SpellbookDeck(main: [.init(card: "Alpha", quantity: count)], commanders: first.commanders) } }
        rejects("total bounded") { _ = try SpellbookDeck(main: [.init(card: "Alpha", quantity: 2000)], commanders: first.commanders) }
        rejects("commander required") { _ = try SpellbookDeck(main: first.main, commanders: []) }
        rejects("600 row limit") { _ = try SpellbookDeck(main: Array(repeating: .init(card: "Alpha", quantity: 1), count: 601), commanders: first.commanders) }
        let decoded = try SpellbookPage.decode(page(["included": [variant()]]))
        check(decoded.count == nil && decoded.results.included.count == 1, "nullable count and camelCase payload")
        check(decoded.results.included[0].uses[0].battlefieldCardState == "Untapped", "zone prerequisites retained")
        check(decoded.results.included[0].notablePrerequisites == "Needs a game state", "notable prerequisites retained")
        check(decoded.results.included[0].websiteURL?.absoluteString == "https://commanderspellbook.com/combo/1-2/", "safe attributed URL")
        rejects("malformed JSON") { _ = try SpellbookPage.decode(Data("bad".utf8)) }
        rejects("oversized response") { _ = try SpellbookPage.decode(Data(repeating: 32, count: SpellbookAPI.maximumResponseBytes + 1)) }
        var malformed = try JSONSerialization.jsonObject(with: page()) as! [String: Any]
        var results = malformed["results"] as! [String: Any]; results.removeValue(forKey: "includedByChangingCommanders"); malformed["results"] = results
        rejects("missing category is not zero results") { _ = try SpellbookPage.decode(JSONSerialization.data(withJSONObject: malformed)) }
        rejects("duplicate variants") { _ = try SpellbookPage.decode(page(["included": [variant()], "almostIncluded": [variant()]])) }
        rejects("invalid combo path") { _ = try SpellbookPage.decode(page(["included": [variant("../evil")]])) }
        rejects("invalid ingredient count") { _ = try SpellbookPage.decode(page(["included": [variant(uses: [use("Alpha", quantity: 0)])]])) }
        let validNext = "https://backend.commanderspellbook.com/find-my-combos?limit=100&offset=100"
        check(try SpellbookAPI.nextOffset(validNext, after: 0) == 100, "verified pagination")
        check(try SpellbookAPI.nextOffset(nil, after: 0) == nil, "last page")
        for url in [validNext.replacingOccurrences(of: "https:", with: "http:"),
                    validNext.replacingOccurrences(of: "backend.commanderspellbook.com", with: "evil.example"),
                    validNext.replacingOccurrences(of: "?", with: "/?"), validNext + "&q=secret", validNext + "#fragment",
                    validNext.replacingOccurrences(of: "offset=100", with: "offset=0"),
                    validNext.replacingOccurrences(of: "offset=100", with: "offset=-1"),
                    validNext.replacingOccurrences(of: "offset=100", with: "offset=0100"),
                    validNext.replacingOccurrences(of: "offset=100", with: "offset=999999"),
                    validNext.replacingOccurrences(of: "limit=100", with: "limit=1000"), validNext + "&limit=100",
                    validNext.replacingOccurrences(of: "https://", with: "https://user:pass@"),
                    validNext.replacingOccurrences(of: ".com/", with: ".com:443/")] {
            rejects("unsafe pagination") { _ = try SpellbookAPI.nextOffset(url, after: 0) }
        }
        check(try assess(variant(), deck: first).readiness == .oneCardAway("Beta"), "exactly one missing named card")
        check(try assess(variant(), deck: complete).readiness == .namedPiecesPresent, "all named pieces present")
        check(try assess(variant(), deck: first, colors: nil).readiness == .reviewRequirements, "unknown identity cannot certify upgrade")
        check(try assess(variant(identity: "UR"), deck: first).readiness == .reviewRequirements, "local commander identity enforced")
        check(try assess(variant(legal: false), deck: first).readiness == .reviewRequirements, "banned combo not one-click upgrade")
        check(try assess(variant(spoiler: true), deck: first).readiness == .reviewRequirements, "spoilers distinguished")
        check(try assess(variant(), deck: first, group: .almostIncludedByAddingColors).readiness == .reviewRequirements, "provider other groups remain separate")
        check(try assess(variant(), deck: first, resolve: { $0 == "Beta" ? nil : $0 }).readiness == .reviewRequirements, "unsupported engine card not addable")
        check(try assess(variant(uses: [use("Alpha", commander: true), use("Beta")]), deck: complete).readiness == .reviewRequirements, "required commander role not just membership")
        check(try assess(variant(uses: [use("Alpha", quantity: 2), use("Beta")]), deck: complete).readiness == .reviewRequirements, "extra copy not a legal one-card upgrade")
        check(try assess(variant(uses: [use("Alpha"), use("Alpha"), use("Beta")]), deck: complete).readiness == .reviewRequirements, "repeated ingredients counted, not set deduped")
        var template = use("Alpha"); template.removeValue(forKey: "card"); template["template"] = ["id": 1, "name": "Untap effect"]
        check(try assess(variant(templates: [template]), deck: complete).readiness == .reviewRequirements, "flexible templates cannot imply combo ready")
        let expected = try SpellbookAPI.pageURL()
        try SpellbookHTTPResponsePolicy.validate(HTTPURLResponse(url: expected, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, expected: expected)
        check(true, "valid HTTP envelope")
        for headers in [["Content-Type": "text/html"], ["Content-Type": "application/json", "Content-Length": "5000000"]] {
            rejects("bad HTTP envelope") { try SpellbookHTTPResponsePolicy.validate(HTTPURLResponse(url: expected, statusCode: 200, httpVersion: nil, headerFields: headers)!, expected: expected) }
        }
        for code in [301, 401, 403, 500] { rejects("non-success status") { try SpellbookHTTPResponsePolicy.validate(HTTPURLResponse(url: expected, statusCode: code, httpVersion: nil, headerFields: [:])!, expected: expected) } }
        do {
            try SpellbookHTTPResponsePolicy.validate(HTTPURLResponse(url: expected, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"])!, expected: expected)
            check(false, "429 expected")
        } catch { check((error as? SpellbookError) == .rateLimited(seconds: 120), "Retry-After retained") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spellbook-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock()
        let transport = FixtureTransport([.data(try page(["almostIncluded": [variant()]], next: validNext)),
                                           .data(try page(["included": [variant("3-4", uses: [use("Alpha")])]]))])
        let client = CommanderSpellbookClient(transport: transport, cacheDirectory: directory, now: { clock.now() })
        let empty = await client.cached(for: first)
        check(empty == nil, "cold cache empty")
        check(await transport.count() == 0, "cache read never transmits")
        let lookup = try await client.lookup(deck: first)
        check(lookup.savedToDisk && lookup.snapshot.loadedCount == 1, "bounded cache persisted")
        check(lookup.snapshot.nextOffset == 100, "pagination kept explicit")
        check(await transport.count() == 1, "only one request per interaction")
        let requests = await transport.all()
        check(requests[0].httpMethod == "POST", "POST body, not URL deck exposure")
        check(requests[0].httpBody == (try first.encoded()), "exact normalized payload")
        check(requests[0].value(forHTTPHeaderField: "User-Agent") == "MagicMobile-DeckStudio/2.0", "identifying header")
        check(requests[0].value(forHTTPHeaderField: "Authorization") == nil, "no credentials")
        do { _ = try await client.lookup(deck: first); check(false, "spacing expected") }
        catch { check((error as? SpellbookError) == .rateLimited(seconds: 2), "request spacing enforced") }
        clock.advance()
        let more = try await client.lookup(deck: first, continuing: lookup.snapshot)
        check(more.snapshot.loadedCount == 2 && more.snapshot.nextOffset == nil, "merge another explicit page")
        let all = await transport.all()
        check(all[0].httpBody == all[1].httpBody && all[1].url?.query?.contains("offset=100") == true, "pagination reuses exact deck body")
        let offline = CommanderSpellbookClient(transport: FixtureTransport([]), cacheDirectory: directory)
        check(await offline.cached(for: first) == more.snapshot, "offline cache reload")
        check(await offline.cached(for: complete) == nil, "cache never crosses deck identities")
        try await offline.clearCache()
        check(await offline.cached(for: first) == nil, "explicit cache clearing")
        let evil = FixtureTransport([.data(try page(["included": [variant()]], next: "https://evil.example/collect"))])
        let evilClient = CommanderSpellbookClient(transport: evil, cacheDirectory: nil)
        do { _ = try await evilClient.lookup(deck: first); check(false, "evil next expected") }
        catch { check((error as? SpellbookError) == .unsafePagination, "untrusted next rejected") }
        check(await evil.count() == 1, "never follows untrusted next")
        let throttled = FixtureTransport([.failure(.rateLimited(seconds: 120))])
        let throttleClock = TestClock()
        let throttledClient = CommanderSpellbookClient(transport: throttled, cacheDirectory: nil, now: { throttleClock.now() })
        do { _ = try await throttledClient.lookup(deck: first) } catch { check((error as? SpellbookError) == .rateLimited(seconds: 120), "429 surfaces") }
        throttleClock.advance(60)
        do { _ = try await throttledClient.lookup(deck: first); check(false, "cooldown expected") }
        catch { check((error as? SpellbookError) == .rateLimited(seconds: 60), "429 cooldown honored") }
        check(await throttled.count() == 1, "no hidden retry")
        let slow = FixtureTransport([.held(try page(["included": [variant()]]))])
        let slowClient = CommanderSpellbookClient(transport: slow, cacheDirectory: directory)
        let pending = Task { try await slowClient.lookup(deck: first) }
        await slow.waitUntilHeld()
        try await slowClient.clearCache()
        await slow.release()
        do { _ = try await pending.value; check(false, "clear invalidates in-flight cache") }
        catch { check(error is CancellationError, "late result after clear rejected") }
        check(await slowClient.cached(for: first) == nil, "cleared data not resurrected")
        let cancellingTransport = FixtureTransport([.held(try page())])
        let cancelledClient = CommanderSpellbookClient(transport: cancellingTransport, cacheDirectory: directory)
        let cancelled = Task { try await cancelledClient.lookup(deck: first) }
        await cancellingTransport.waitUntilHeld(); cancelled.cancel(); await cancellingTransport.release()
        do { _ = try await cancelled.value; check(false, "cancel expected") }
        catch { check(error is CancellationError, "cancelled request cannot publish") }
        check(await cancelledClient.cached(for: first) == nil, "cancelled response not cached")
        // Exercise the production bounded URLSession delegate with an intercepting
        // URLProtocol. These calls do not leave the process or contact the provider.
        let streaming = SpellbookURLSessionTransport(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [FixtureURLProtocol.self]
            return config
        })
        let streamData = try page()
        var streamRequest = URLRequest(url: expected)
        streamRequest.httpMethod = "POST"; streamRequest.httpBody = try first.encoded()
        FixtureURLProtocol.configure(.valid(streamData))
        check(try await streaming.send(streamRequest) == streamData, "real streaming delegate receives bounded JSON")
        for mode in [FixtureURLProtocol.Mode.oversizedHeader, .oversizedBody] {
            FixtureURLProtocol.configure(mode)
            do { _ = try await streaming.send(streamRequest); check(false, "stream size limit expected") }
            catch { check((error as? SpellbookError) == .responseTooLarge, "stream size limit enforced") }
        }
        FixtureURLProtocol.configure(.wait)
        let streamCancel = Task { try await streaming.send(streamRequest) }
        try await Task.sleep(nanoseconds: 10_000_000); streamCancel.cancel()
        do { _ = try await streamCancel.value; check(false, "stream cancellation expected") }
        catch { check(error is CancellationError, "stream continuation cancelled without a server completion") }
        #if canImport(Combine)
        try await modelChecks(first, other: complete)
        #else
        print("SKIP: ObservableObject lifecycle tests require Combine; hosted macOS runs them.")
        #endif
        print("PASS: \(assertions) Spellbook contract/cache/privacy assertions. Injected fixtures, not live API, native game, or phone acceptance.")
    }

    #if canImport(Combine)
    @MainActor static func modelChecks(_ first: SpellbookDeck, other: SpellbookDeck) async throws {
        let clock = TestClock()
        let transport = FixtureTransport([.held(try page(["included": [variant()]])), .data(try page(["included": [variant()]]))])
        let model = DeckStudioComboModel(client: CommanderSpellbookClient(transport: transport, cacheDirectory: nil, now: { clock.now() }))
        await model.setInput(first)
        check(await transport.count() == 0, "model initialization/input observation is offline")
        let firstWork = model.analyze(approvedDeck: first)
        await transport.waitUntilHeld()
        await model.setInput(other)
        await transport.release()
        await firstWork?.value
        check(model.snapshot == nil && model.input == other && !model.loading, "stale async response discarded after edit")
        model.analyze(approvedDeck: first)
        check(await transport.count() == 1, "approval for old deck cannot share new deck")
        clock.advance()
        let nextWork = model.analyze(approvedDeck: other)
        await nextWork?.value
        check(model.snapshot?.deck == other && !model.loading, "explicit approval publishes current result")
        model.cancel()
        await model.setInput(other)
        check(await transport.count() == 2, "tab return does not requery")
        await model.clear()
        check(model.snapshot == nil, "model cache clear resets visible results")
    }
    #endif
}
