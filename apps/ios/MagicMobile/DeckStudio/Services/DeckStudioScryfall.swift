import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shared with native artwork. Monotonic request spacing and no automatic retry.
actor DeckStudioScryfallBudget {
    static let shared = DeckStudioScryfallBudget()
    private var next: TimeInterval = 0
    private var blocked: TimeInterval = 0
    func reserve() async throws {
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= blocked else { throw DeckStudioScryfallError.rateLimited }
            if now >= next { next = now + 0.55; return }
            try await Task.sleep(nanoseconds: UInt64(min(1, next - now) * 1_000_000_000))
        }
    }
    func backOff(_ seconds: TimeInterval) {
        let safe = seconds.isFinite ? max(30, min(3600, seconds)) : 30
        blocked = max(blocked, ProcessInfo.processInfo.systemUptime + safe)
    }
}

enum DeckStudioScryfallError: LocalizedError, Equatable {
    case invalidInput, invalidResponse, tooLarge, unavailable, rateLimited, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Enter a card name or search of at most 512 bytes."
        case .invalidResponse: return "Scryfall returned an unsupported response. The local catalogue and deck are unchanged."
        case .tooLarge: return "Scryfall's response exceeded the safe size limit. Refine the search."
        case .unavailable: return "Scryfall is unavailable or offline. Local search, editing and gameplay still work."
        case .rateLimited: return "Scryfall requests are paused after a rate limit. Retry later; no automatic retry was sent."
        case .http(let status): return status == 404 ? "No matching cards were found on Scryfall." : "Scryfall returned HTTP \(status). Local data is unchanged."
        }
    }
}

struct DeckStudioScryfallCard: Codable, Equatable, Identifiable, Sendable {
    struct Face: Codable, Equatable, Sendable {
        let name: String
        let manaCost: String?
        let typeLine: String?
        let oracleText: String?
        enum CodingKeys: String, CodingKey { case name, manaCost = "mana_cost", typeLine = "type_line", oracleText = "oracle_text" }
    }
    let id: UUID
    let oracleID: UUID?
    let name: String
    let manaCost: String?
    let manaValue: Double?
    let typeLine: String?
    let oracleText: String?
    let colorIdentity: [String]?
    let legalities: [String: String]?
    let faces: [Face]?
    let relatedURIs: [String: String]?
    let scryfallURI: String?
    let set: String?
    let collectorNumber: String?
    enum CodingKeys: String, CodingKey {
        case id, name, legalities, set
        case oracleID = "oracle_id", manaCost = "mana_cost", manaValue = "cmc", typeLine = "type_line", oracleText = "oracle_text"
        case colorIdentity = "color_identity", faces = "card_faces", relatedURIs = "related_uris", scryfallURI = "scryfall_uri", collectorNumber = "collector_number"
    }
    var edhrecURL: URL? { Self.safeWebURL(relatedURIs?["edhrec"], hosts: ["edhrec.com", "www.edhrec.com"]) }
    var websiteURL: URL? { Self.safeWebURL(scryfallURI, hosts: ["scryfall.com", "www.scryfall.com"]) }
    static func safeWebURL(_ string: String?, hosts: Set<String>) -> URL? {
        guard let string, string.utf8.count <= 2048, let parts = URLComponents(string: string),
              parts.scheme == "https", let host = parts.host?.lowercased(), hosts.contains(host),
              parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        return parts.url
    }
    func validated() throws -> Self {
        guard !name.isEmpty, name.utf8.count <= 1024, (oracleText?.utf8.count ?? 0) <= 32768,
              (typeLine?.utf8.count ?? 0) <= 2048, (manaCost?.utf8.count ?? 0) <= 2048,
              manaValue.map({ $0.isFinite && $0 >= 0 && $0 < 1000000 }) ?? true,
              colorIdentity.map({ Set($0).isSubset(of: ["W", "U", "B", "R", "G"]) && $0.count <= 5 }) ?? true,
              (faces?.count ?? 0) <= 8,
              faces?.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 1024 && ($0.oracleText?.utf8.count ?? 0) <= 32768 }) ?? true else { throw DeckStudioScryfallError.invalidResponse }
        return self
    }
}

struct DeckStudioScryfallPage: Sendable {
    let cards: [DeckStudioScryfallCard]
    let hasMore: Bool
    let page: Int
    let query: String
    let fetchedAt: Date
    let cached: Bool
}

protocol DeckStudioScryfallHTTP: Sendable { func send(_ request: URLRequest) async throws -> Data }

/// Reuses the tested bounded HTTP transport: exact URL, MIME, size, redirects and cancellation.
struct DeckStudioScryfallHTTPTransport: DeckStudioScryfallHTTP {
    let base = SpellbookURLSessionTransport()
    func send(_ request: URLRequest) async throws -> Data {
        do { return try await base.send(request) }
        catch SpellbookError.rateLimited(let seconds) {
            await DeckStudioScryfallBudget.shared.backOff(TimeInterval(seconds))
            throw DeckStudioScryfallError.rateLimited
        } catch SpellbookError.httpStatus(let code) { throw DeckStudioScryfallError.http(code) }
        catch SpellbookError.responseTooLarge { throw DeckStudioScryfallError.tooLarge }
        catch is CancellationError { throw CancellationError() }
        catch { throw DeckStudioScryfallError.unavailable }
    }
}

actor DeckStudioScryfallClient {
    static let shared = DeckStudioScryfallClient()
    struct CachedCard: Sendable { let card: DeckStudioScryfallCard; let fetchedAt: Date; let cached: Bool }
    private struct Entry: Codable { let schema: Int; let key: String; let date: Date; let data: Data }
    private struct List: Decodable {
        let object: String
        let data: [DeckStudioScryfallCard]
        let hasMore: Bool
        enum CodingKeys: String, CodingKey { case object, data, hasMore = "has_more" }
    }
    private let transport: any DeckStudioScryfallHTTP
    private let directory: URL?
    private let pace: Bool
    private var cache: [String: Entry] = [:]
    private var generation = UUID()
    private var busy = false
    init(transport: any DeckStudioScryfallHTTP = DeckStudioScryfallHTTPTransport(),
         directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("DeckStudio-Scryfall-v1"), pace: Bool = true) {
        self.transport = transport; self.directory = directory; self.pace = pace
    }
    static func request(_ value: String, page: Int? = nil) throws -> URLRequest {
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 512, !query.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              page.map({ (1...10).contains($0) }) ?? true else { throw DeckStudioScryfallError.invalidInput }
        var parts = URLComponents(string: "https://api.scryfall.com/cards/\(page == nil ? "named" : "search")")!
        if let page { parts.queryItems = [.init(name: "q", value: query), .init(name: "unique", value: "cards"), .init(name: "page", value: String(page))] }
        else { parts.queryItems = [.init(name: "exact", value: query)] }
        var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MagicMobile-DeckStudio/2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        return request
    }
    func named(_ name: String, allowNetwork: Bool, refresh: Bool = false) async throws -> CachedCard? {
        let request = try Self.request(name)
        guard let entry = try await data(request, allowNetwork: allowNetwork, refresh: refresh) else { return nil }
        do {
            let card = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: entry.0.data).validated()
            return CachedCard(card: card, fetchedAt: entry.0.date, cached: entry.1)
        } catch { throw DeckStudioScryfallError.invalidResponse }
    }
    func search(_ query: String, page: Int = 1, allowNetwork: Bool, refresh: Bool = false) async throws -> DeckStudioScryfallPage? {
        let request = try Self.request(query, page: page)
        guard let entry = try await data(request, allowNetwork: allowNetwork, refresh: refresh) else { return nil }
        do {
            let list = try JSONDecoder().decode(List.self, from: entry.0.data)
            guard list.object == "list", list.data.count <= 200, Set(list.data.map(\.id)).count == list.data.count else { throw DeckStudioScryfallError.invalidResponse }
            return DeckStudioScryfallPage(cards: try list.data.map { try $0.validated() }, hasMore: list.hasMore,
                page: page, query: query, fetchedAt: entry.0.date, cached: entry.1)
        } catch { throw DeckStudioScryfallError.invalidResponse }
    }
    func clearCache() throws {
        generation = UUID(); cache = [:]
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.lastPathComponent.hasPrefix("response-") && url.pathExtension == "json" {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    private func data(_ request: URLRequest, allowNetwork: Bool, refresh: Bool) async throws -> (Entry, Bool)? {
        try Task.checkCancellation()
        let key = request.url!.absoluteString
        if !refresh, let entry = read(key) { return (entry, true) }
        guard allowNetwork else { return nil }
        let token = generation
        while busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        if !refresh, let entry = read(key) { return (entry, true) }
        busy = true; defer { busy = false }
        if pace { try await DeckStudioScryfallBudget.shared.reserve() }
        let bytes = try await transport.send(request)
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        guard bytes.count <= 4 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              ["card", "list"].contains(object["object"] as? String ?? "") else { throw DeckStudioScryfallError.invalidResponse }
        if request.url?.path == "/cards/named" {
            guard object["object"] as? String == "card" else { throw DeckStudioScryfallError.invalidResponse }
            _ = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: bytes).validated()
        } else {
            let list = try JSONDecoder().decode(List.self, from: bytes)
            guard list.object == "list", list.data.count <= 200, Set(list.data.map(\.id)).count == list.data.count else { throw DeckStudioScryfallError.invalidResponse }
            for card in list.data { _ = try card.validated() }
        }
        let entry = Entry(schema: 1, key: key, date: Date(), data: bytes)
        cache[key] = entry
        if cache.count > 4, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache.removeValue(forKey: oldest) }
        store(entry)
        return (entry, false)
    }
    private func url(_ key: String) -> URL? {
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return directory?.appendingPathComponent("response-\(String(hash, radix: 16)).json")
    }
    private func read(_ key: String) -> Entry? {
        if let value = cache[key] { return value }
        guard let url = url(key), let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue <= 6 * 1024 * 1024,
              let data = try? Data(contentsOf: url), data.count <= 6 * 1024 * 1024,
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.schema == 1,
              entry.key == key, entry.date.timeIntervalSince1970.isFinite, entry.data.count <= 4 * 1024 * 1024 else { return nil }
        return entry
    }
    private func store(_ entry: Entry) {
        guard let directory, let url = url(entry.key) else { return }
        do {
            let data = try JSONEncoder().encode(entry)
            guard data.count <= 6 * 1024 * 1024 else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.lastPathComponent.hasPrefix("response-") && $0.pathExtension == "json" }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in files.dropFirst(12) { try FileManager.default.removeItem(at: old) }
        } catch { /* Optional cache failure never changes a deck or prevents using a response. */ }
    }
}
