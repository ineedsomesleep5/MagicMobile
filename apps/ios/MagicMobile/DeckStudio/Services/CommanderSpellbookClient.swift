import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol SpellbookHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Data
}

/// Bounded streaming transport. No cookies, credential storage, redirects, or retries.
struct SpellbookURLSessionTransport: SpellbookHTTPTransport {
    private let configuration: @Sendable () -> URLSessionConfiguration
    init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) { self.configuration = configuration }
    func send(_ request: URLRequest) async throws -> Data {
        let job = SpellbookHTTPJob(request: request, configuration: configuration())
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { job.start($0) }
        } onCancel: { job.cancel() }
    }
}

private final class SpellbookHTTPJob: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var bytes = Data()
    private var finished = false
    private var cancelled = false

    init(request: URLRequest, configuration: URLSessionConfiguration) { self.request = request; self.configuration = configuration }
    func start(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let config = configuration
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        self.session = session; self.task = task
        lock.unlock()
        task.resume()
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, session = self.session
        self.continuation = nil; self.session = nil; self.task = nil
        bytes = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(SpellbookError.unsafePagination))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            try SpellbookHTTPResponsePolicy.validate(response, expected: request.url)
            completionHandler(.allow)
        } catch { finish(.failure(error)); completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= SpellbookAPI.maximumResponseBytes - bytes.count else {
            lock.unlock(); finish(.failure(SpellbookError.responseTooLarge)); return
        }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { finish(.failure(SpellbookError.unavailable)); return }
        lock.lock(); let data = bytes; lock.unlock()
        finish(.success(data))
    }
}

enum SpellbookHTTPResponsePolicy {
    static func validate(_ response: URLResponse, expected: URL?) throws {
        guard let http = response as? HTTPURLResponse, http.url == expected else { throw SpellbookError.invalidResponse }
        if http.statusCode == 429 {
            let value = http.value(forHTTPHeaderField: "Retry-After")
            var seconds = value.flatMap(Int.init) ?? 60
            if let value, Int(value) == nil {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date = formatter.date(from: value) { seconds = Int(min(3600, max(1, date.timeIntervalSinceNow))) }
            }
            throw SpellbookError.rateLimited(seconds: max(1, min(seconds, 3600)))
        }
        guard http.statusCode == 200 else { throw SpellbookError.httpStatus(http.statusCode) }
        guard http.mimeType?.lowercased() == "application/json" else { throw SpellbookError.invalidResponse }
        guard http.expectedContentLength <= Int64(SpellbookAPI.maximumResponseBytes) else { throw SpellbookError.responseTooLarge }
    }
}

struct SpellbookSnapshot: Codable, Equatable, Sendable {
    let schema: Int
    let deck: SpellbookDeck
    let fetchedAt: Date
    let total: Int?
    let groups: [SpellbookGroup: [SpellbookVariant]]
    let offsets: [Int]
    let nextOffset: Int?
    var loadedCount: Int { groups.values.reduce(0) { $0 + $1.count } }

    func validate(for expected: SpellbookDeck) throws {
        guard schema == 1, deck == expected, Set(groups.keys) == Set(SpellbookGroup.allCases),
              deck == (try SpellbookDeck(main: deck.main, commanders: deck.commanders)),
              fetchedAt.timeIntervalSince1970.isFinite, total.map({ $0 >= 0 }) ?? true,
              offsets.first == 0, offsets == Array(Set(offsets)).sorted(), offsets.count <= 21,
              offsets.allSatisfy({ (0...SpellbookAPI.maximumResults).contains($0) }),
              nextOffset.map({ $0 > (offsets.last ?? -1) && $0 <= SpellbookAPI.maximumResults }) ?? true,
              loadedCount <= SpellbookAPI.maximumResults else { throw SpellbookError.invalidResponse }
        var seen = Set<String>()
        for group in SpellbookGroup.allCases {
            for variant in groups[group, default: []] {
                try variant.validate()
                guard seen.insert(variant.id).inserted else { throw SpellbookError.invalidResponse }
            }
        }
    }
}

/// Shared only inside this app. All network operations require an explicit UI action.
/// Cache reads never request data or transmit a deck. Cached responses remain dated.
actor CommanderSpellbookClient {
    static let shared = CommanderSpellbookClient()
    struct Lookup: Sendable { let snapshot: SpellbookSnapshot; let savedToDisk: Bool }
    private let transport: any SpellbookHTTPTransport
    private let directory: URL?
    private let now: @Sendable () -> Date
    private var memory: [Data: SpellbookSnapshot] = [:]
    private var nextAllowed = Date.distantPast
    private var requesting = false
    private var cacheGeneration: UInt64 = 0
    static let maximumCacheBytes = 8 * 1024 * 1024

    init(transport: any SpellbookHTTPTransport = SpellbookURLSessionTransport(),
         cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MagicMobile-Spellbook-v1", isDirectory: true),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport; directory = cacheDirectory; self.now = now
    }
    func cached(for deck: SpellbookDeck) -> SpellbookSnapshot? {
        guard let key = try? deck.encoded() else { return nil }
        if let found = memory[key] { return found }
        guard let url = cacheURL(key),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumCacheBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maximumCacheBytes,
              let snapshot = try? JSONDecoder().decode(SpellbookSnapshot.self, from: data),
              (try? snapshot.validate(for: deck)) != nil else { return nil }
        remember(snapshot, key: key)
        return snapshot
    }
    func clearCache() throws {
        cacheGeneration &+= 1
        memory.removeAll()
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("lookup-") && url.pathExtension == "json" {
            try FileManager.default.removeItem(at: url)
        }
    }
    func lookup(deck: SpellbookDeck, continuing previous: SpellbookSnapshot? = nil) async throws -> Lookup {
        try Task.checkCancellation()
        guard !requesting else { throw SpellbookError.rateLimited(seconds: 2) }
        let wait = nextAllowed.timeIntervalSince(now())
        guard wait <= 0 else { throw SpellbookError.rateLimited(seconds: max(1, Int(ceil(wait)))) }
        let validated = try SpellbookDeck(main: deck.main, commanders: deck.commanders)
        guard validated == deck else { throw SpellbookError.invalidDeck }
        let offset: Int
        if let previous {
            try previous.validate(for: deck)
            guard previous.loadedCount < SpellbookAPI.maximumResults, let next = previous.nextOffset,
                  !previous.offsets.contains(next) else { throw SpellbookError.tooManyResults }
            offset = next
        } else { offset = 0 }
        var request = URLRequest(url: try SpellbookAPI.pageURL(offset: offset), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MagicMobile-DeckStudio/2.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try deck.encoded()
        let generation = cacheGeneration
        requesting = true; nextAllowed = now().addingTimeInterval(2)
        defer { requesting = false }
        let data: Data
        do { data = try await transport.send(request) }
        catch let error as SpellbookError {
            if case .rateLimited(let seconds) = error { nextAllowed = now().addingTimeInterval(TimeInterval(seconds)) }
            throw error
        } catch is CancellationError { throw CancellationError() }
        catch { throw SpellbookError.unavailable }
        try Task.checkCancellation()
        let page = try SpellbookPage.decode(data)
        let next = try SpellbookAPI.nextOffset(page.next, after: offset)
        var groups = previous?.groups ?? [:]
        var seen: [String: (SpellbookGroup, SpellbookVariant)] = [:]
        for (group, variants) in groups { for variant in variants { seen[variant.id] = (group, variant) } }
        for group in SpellbookGroup.allCases {
            if groups[group] == nil { groups[group] = [] }
            for variant in page.results.groups[group, default: []] {
                if let old = seen[variant.id] {
                    guard old.0 == group, old.1 == variant else { throw SpellbookError.invalidResponse }
                    continue
                }
                groups[group, default: []].append(variant)
                seen[variant.id] = (group, variant)
            }
        }
        guard seen.count <= SpellbookAPI.maximumResults else { throw SpellbookError.tooManyResults }
        let snapshot = SpellbookSnapshot(schema: 1, deck: deck, fetchedAt: previous?.fetchedAt ?? now(),
            total: page.count, groups: groups, offsets: (previous?.offsets ?? []) + [offset], nextOffset: next)
        try snapshot.validate(for: deck)
        // A clear operation or cancellation during HTTP must not repopulate disk.
        guard generation == cacheGeneration else { throw CancellationError() }
        let key = try deck.encoded()
        remember(snapshot, key: key)
        return Lookup(snapshot: snapshot, savedToDisk: store(snapshot, key: key))
    }
    private func remember(_ snapshot: SpellbookSnapshot, key: Data) {
        memory[key] = snapshot
        while memory.count > 8, let oldest = memory.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            memory.removeValue(forKey: oldest)
        }
    }
    private func cacheURL(_ key: Data) -> URL? {
        // Non-security filename hash. An exact stored deck comparison rejects collisions.
        var hash: UInt64 = 14695981039346656037
        for byte in key { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return directory?.appendingPathComponent("lookup-\(String(hash, radix: 16)).json")
    }
    private func store(_ snapshot: SpellbookSnapshot, key: Data) -> Bool {
        guard let directory, let url = cacheURL(key) else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= Self.maximumCacheBytes else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.lastPathComponent.hasPrefix("lookup-") && $0.pathExtension == "json" }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                          ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in files.dropFirst(8) { try FileManager.default.removeItem(at: old) }
            return true
        } catch { return false } // Optional cache failure never hides a successful lookup.
    }
}
