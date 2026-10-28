import CryptoKit
import Foundation

/// Your own card pictures (CustomCardArt) on every phone and browser signed in to this profile (docs/CARD_ART_SYNC.md).
/// The rules are shared with Android (CardArtSync.kt) and the web (cardArtSync.ts) through parity/card-art-sync-cases.json.
/// A picture changed here since the last sync wins over one changed elsewhere meanwhile; nothing is ever merged.

/// One card's picture as the server answers it: `picture` is the JPEG's SHA-256, nil when the card has none.
struct ServerCardArt: Equatable {
    var cardKey: String
    var picture: String?
    var changeSeq: Int
}

protocol CardArtSyncAPI: AnyObject {
    func since(_ cursor: Int) async throws -> (arts: [ServerCardArt], cursor: Int, more: Bool)
    @discardableResult func set(cardKey: String, picture: String?) async throws -> ServerCardArt
    func upload(picture: String, data: Data) async throws
    func download(picture: String) async throws -> Data
    /// Best effort: a file nothing points at any more.
    func removeFile(picture: String) async throws
}

/// The pictures on this device, by card key.
protocol CardArtLocal: AnyObject {
    func keys() -> [String]
    /// The stored JPEG's SHA-256 (lower-case hex).
    func hash(_ cardKey: String) -> String?
    func data(_ cardKey: String) -> Data?
    /// A picture from another device: stored without counting as a change made here.
    func store(_ data: Data, cardKey: String) throws
    func remove(_ cardKey: String)
}

struct CardArtSyncRecord: Codable, Equatable {
    struct Removal: Codable, Equatable { var cardKey: String; var picture: String }
    var account: String?
    var cursor = 0
    /// The picture the server had for each card when this device last matched it.
    var synced: [String: String] = [:]
    /// Cards whose picture was removed here while the server still has it.
    var removed: [Removal] = []
}

/// The sync record on disk, beside the pictures.
final class CardArtSyncStore {
    private let url: URL
    var record: CardArtSyncRecord { didSet { save() } }

    init(url: URL) {
        self.url = url
        record = (try? JSONDecoder().decode(CardArtSyncRecord.self, from: Data(contentsOf: url))) ?? CardArtSyncRecord()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(record).write(to: url, options: .atomic)
    }
}

final class CardArtSync: @unchecked Sendable {
    /// Codes the server answers for one card that will not change by asking again: that card stays on this device.
    static let refusals: Set<String> = ["invalid_card_art", "too_many_pictures", "Payload too large", "invalid_mime_type"]

    private let local: CardArtLocal
    private let store: CardArtSyncStore
    private let api: CardArtSyncAPI
    private var running: Task<Void, Error>?
    /// Cards the server refused this session (too many, too large): not offered again until their picture changes.
    private var refused: [String: String] = [:]
    private let lock = NSLock()

    init(local: CardArtLocal, store: CardArtSyncStore, api: CardArtSyncAPI) {
        self.local = local
        self.store = store
        self.api = api
    }

    var record: CardArtSyncRecord { lock.withLock { store.record } }

    /// The player removed a card's picture here: the server's copy goes next sync.
    func noteRemoved(_ cardKey: String) {
        lock.withLock {
            guard let picture = store.record.synced.removeValue(forKey: cardKey) else { return }
            store.record.removed = store.record.removed.filter { $0.cardKey != cardKey } + [.init(cardKey: cardKey, picture: picture)]
        }
    }

    /// Whether anything made here is waiting to go up.
    var hasPendingChanges: Bool {
        let (record, refused) = lock.withLock { (store.record, self.refused) }
        if !record.removed.isEmpty { return true }
        return local.keys().contains { key in
            guard let hash = local.hash(key) else { return false }
            return hash != record.synced[key] && refused[key] != hash
        }
    }

    /// One sync for `account` (the signed-in profile's id). Concurrent calls share the running one.
    func sync(account: String) async throws {
        let task: Task<Void, Error> = lock.withLock {
            if let running { return running }
            let made = Task { try await self.run(account: account) }
            running = made
            return made
        }
        defer { lock.withLock { if running == task { running = nil } } }
        try await task.value
    }

    private func mutate(_ change: (inout CardArtSyncRecord) -> Void) { lock.withLock { change(&store.record) } }

    private func run(account: String) async throws {
        // 1. Another profile: start over, so every picture here joins it. Nothing local is deleted.
        if record.account != account { mutate { $0 = CardArtSyncRecord(account: account) } }
        // 2. Pull.
        try await pull()
        // 3. Removals made here.
        for removal in record.removed {
            try await api.set(cardKey: removal.cardKey, picture: nil)
            mutate { $0.removed.removeAll { $0 == removal } }
            await forget(removal.picture)
        }
        // 4. Pictures set or changed here.
        for key in local.keys() {
            guard let hash = local.hash(key), hash != record.synced[key], lock.withLock({ refused[key] }) != hash,
                  let data = local.data(key) else { continue }
            do {
                try await api.upload(picture: hash, data: data)
                try await api.set(cardKey: key, picture: hash)
            } catch {
                if Self.refusals.contains(SupabaseLite.code(of: error)) {
                    lock.withLock { refused[key] = hash }
                    await forget(hash)
                    continue
                }
                throw error
            }
            let old = record.synced[key]
            mutate { $0.synced[key] = hash }
            if let old { await forget(old) }
        }
        // 5. Pull once more, past this device's own changes.
        try await pull()
    }

    private func pull() async throws {
        while true {
            let answer = try await api.since(record.cursor)
            for art in answer.arts { try await apply(art) }
            mutate { $0.cursor = answer.cursor }
            if !answer.more { break }
        }
    }

    private func apply(_ art: ServerCardArt) async throws {
        let key = art.cardKey
        if let removal = record.removed.first(where: { $0.cardKey == key }) {
            // This device's removal follows, unless someone set another picture meanwhile (it comes back).
            if art.picture == removal.picture { return }
            mutate { $0.removed.removeAll { $0 == removal } }
            if art.picture == nil { return }
        }
        let hash = local.hash(key)
        let synced = record.synced[key]
        let changedHere = hash != nil && hash != synced
        guard let picture = art.picture else {
            if hash != nil, !changedHere { local.remove(key) }
            mutate { $0.synced[key] = nil }
            return
        }
        if hash != picture, !changedHere {
            try local.store(try await api.download(picture: picture), cardKey: key)
        }
        // Changed here since the last sync: this device's picture goes up and wins.
        mutate { $0.synced[key] = picture }
    }

    /// A file no card points at any more.
    private func forget(_ picture: String) async {
        guard !record.synced.values.contains(picture) else { return }
        try? await api.removeFile(picture: picture)
    }

    /// SHA-256 of a picture's bytes, lower-case hex.
    static func pictureHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The server functions and the player's picture folder (custom-card-art/<user id>/) over the account's Supabase client.
final class SupabaseCardArtSync: CardArtSyncAPI {
    private let api: SupabaseLite

    init(api: SupabaseLite) { self.api = api }

    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

    static func art(_ value: Any?) -> ServerCardArt {
        let row = value as? [String: Any] ?? [:]
        return ServerCardArt(cardKey: row["cardKey"] as? String ?? "", picture: row["picture"] as? String, changeSeq: int(row["changeSeq"]) ?? 0)
    }

    private func file(_ picture: String) async throws -> String {
        guard let user = try await api.userID() else { throw SupabaseLite.Failure(code: "not_signed_in") }
        return "custom-card-art/\(user)/\(picture).jpg"
    }

    func since(_ cursor: Int) async throws -> (arts: [ServerCardArt], cursor: Int, more: Bool) {
        let answer = try JSONSerialization.jsonObject(with: try await api.rpc("mm_card_art_since", ["p_cursor": cursor])) as? [String: Any] ?? [:]
        return ((answer["arts"] as? [Any] ?? []).map(Self.art), Self.int(answer["cursor"]) ?? cursor, answer["more"] as? Bool == true)
    }

    func set(cardKey: String, picture: String?) async throws -> ServerCardArt {
        let data = try await api.rpc("mm_card_art_set", ["p_card_key": cardKey, "p_picture": picture ?? NSNull()])
        return Self.art(try JSONSerialization.jsonObject(with: data))
    }

    func upload(picture: String, data: Data) async throws { _ = try await api.storage("PUT", try await file(picture), body: data) }
    func download(picture: String) async throws -> Data { try await api.storage("GET", try await file(picture)) }
    func removeFile(picture: String) async throws { _ = try await api.storage("DELETE", try await file(picture)) }
}

/// Runs card picture sync for the signed-in profile: alongside deck sync, and a few seconds after a picture is set or
/// removed here.
@MainActor final class CardArtSyncCoordinator {
    static let shared = CardArtSyncCoordinator()
    private lazy var engine = CardArtSync(
        local: CustomCardArt.shared,
        store: CardArtSyncStore(url: CustomCardArt.shared.directory.deletingLastPathComponent().appendingPathComponent("MagicMobileCustomArtSync.json")),
        api: PlayerAccount.shared.cardArtSyncAPI)
    private var observers: [NSObjectProtocol] = []
    private var soon: Task<Void, Never>?

    /// Listens for pictures set or removed here (once).
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: CustomCardArt.didRemove, object: nil, queue: .main) { note in
            guard let key = note.userInfo?["cardKey"] as? String else { return }
            MainActor.assumeIsolated { self.engine.noteRemoved(key); self.syncSoon() }
        })
        observers.append(center.addObserver(forName: CustomCardArt.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.syncSoon() }
        })
    }

    /// One sync for the signed-in profile. Errors stay quiet: the next sync tries again.
    func sync() async {
        start()
        guard let profile = await PlayerAccount.shared.deckSyncProfile() else { return }
        try? await engine.sync(account: profile)
    }

    private func syncSoon() {
        soon?.cancel()
        soon = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, engine.hasPendingChanges else { return }
            await sync()
        }
    }
}
