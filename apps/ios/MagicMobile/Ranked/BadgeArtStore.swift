import Foundation

/// How asking the server for a badge went.
enum BadgeFetch: Equatable, Sendable {
    case new(Data, etag: String?)
    case unchanged
    /// The server doesn't have that file.
    case missing
    /// Offline or a server error: try another time.
    case failed
}

/// Badge art kept on the phone, so a profile opens with its coins already there. Our art has a small copy beside it
/// (scripts/brand/award_small.sh); art from anywhere else is kept as it comes. The store asks the server again at most every six
/// hours, and a file it already has only comes down again if it changed, so new art still needs no build. Android's BadgeArtStore
/// matches it.
final class BadgeArtStore: Sendable {
    typealias Fetch = @Sendable (URL, String?) async -> BadgeFetch

    static let recheck: TimeInterval = 6 * 3600
    private static let awards = "/design/awards/"

    static let shared = BadgeArtStore(
        folder: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("BadgeArt", isDirectory: true),
        fetch: BadgeArtStore.download)

    private let folder: URL?
    private let fetch: Fetch

    init(folder: URL?, fetch: @escaping Fetch) {
        self.folder = folder
        self.fetch = fetch
    }

    static func smallURL(_ url: URL) -> URL {
        let text = url.absoluteString
        guard text.contains(awards), !text.contains(awards + "small/") else { return url }
        return URL(string: text.replacingOccurrences(of: awards, with: awards + "small/")) ?? url
    }

    private static func key(_ url: URL, small: Bool) -> String {
        String(stableHash((small ? "small:" : "") + url.absoluteString), radix: 16)
    }

    private func art(_ key: String) -> URL? { folder?.appendingPathComponent(key + ".png") }
    private func note(_ key: String) -> URL? { folder?.appendingPathComponent(key + ".note") }

    /// What the phone has, however old.
    func stored(_ url: URL, small: Bool = true) -> Data? {
        art(Self.key(url, small: small)).flatMap { try? Data(contentsOf: $0) }
    }

    /// Checks with the server unless it did lately, and tells whether the art changed.
    @discardableResult
    func refresh(_ url: URL, small: Bool = true, now: Date = Date()) async -> Bool {
        let key = Self.key(url, small: small)
        let lines = note(key).flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.components(separatedBy: "\n")
        let etag = lines.flatMap { $0.count > 1 && !$0[1].isEmpty ? $0[1] : nil }
        let have = art(key).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let checked = lines?.first.flatMap(Double.init) ?? 0
        if have, now.timeIntervalSince1970 - checked < Self.recheck { return false }
        let wanted = small ? Self.smallURL(url) : url
        var result = await fetch(wanted, have ? etag : nil)
        if result == .missing, wanted != url { result = await fetch(url, nil) }
        switch result {
        case let .new(data, fresh):
            save(data, etag: fresh, key: key, now: now)
            return true
        case .unchanged:
            write(etag: etag, key: key, now: now)
            return false
        case .missing, .failed:
            return false
        }
    }

    /// Refreshes these, a few at a time, and returns the ones whose art changed.
    func prefetch(_ urls: [URL], small: Bool = true) async -> [URL] {
        var changed: [URL] = []
        for start in stride(from: 0, to: urls.count, by: 4) {
            let batch = urls[start..<min(start + 4, urls.count)]
            await withTaskGroup(of: URL?.self) { group in
                for url in batch { group.addTask { await self.refresh(url, small: small) ? url : nil } }
                for await url in group { if let url { changed.append(url) } }
            }
        }
        return changed
    }

    private func save(_ data: Data, etag: String?, key: String, now: Date) {
        guard let folder, let target = art(key) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
        write(etag: etag, key: key, now: now)
    }

    private func write(etag: String?, key: String, now: Date) {
        guard let target = note(key) else { return }
        try? "\(now.timeIntervalSince1970)\n\(etag ?? "")".write(to: target, atomically: true, encoding: .utf8)
    }

    private static func download(_ url: URL, etag: String?) async -> BadgeFetch {
        if url.isFileURL { return (try? Data(contentsOf: url)).map { .new($0, etag: nil) } ?? .missing }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200: return data.count <= 4 * 1024 * 1024 ? .new(data, etag: http.value(forHTTPHeaderField: "ETag")) : .failed
        case 304: return .unchanged
        case 404: return .missing
        default: return .failed
        }
    }
}
