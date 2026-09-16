import Foundation

/// Device-local, bounded summaries. No event stream, hand, opponent deck, or
/// network credential is persisted. Storage failure must never fail gameplay.
actor DeckStudioPlaytestStore {
    static let shared = DeckStudioPlaytestStore()
    static let enabledKey = "magicmobile.playtestSummaries.enabled"
    static let maximumBytes = 2 * 1024 * 1024
    static let maximumGames = 100
    struct Admission: Sendable { let enabled: Bool; let generation: UUID }
    private struct Payload: Codable { let schema: Int; let games: [DeckStudioRecordedGame] }
    private let url: URL?
    private let defaults: UserDefaults
    private var generation = UUID()
    private var loaded = false
    private var games: [DeckStudioRecordedGame] = []
    private var failure: String?
    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("MagicMobile-Playtests", isDirectory: true), defaults: UserDefaults = .standard) {
        self.url = directory?.appendingPathComponent("summaries-v1.json")
        self.defaults = defaults
    }
    func admission() -> Admission { Admission(enabled: defaults.bool(forKey: Self.enabledKey), generation: generation) }
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { generation = UUID() }
    }
    func status() -> String? { failure }
    func summaries() throws -> [DeckStudioRecordedGame] { try load(); return games }
    @discardableResult func record(_ value: DeckStudioRecordedGame, admission: Admission) -> Bool {
        guard admission.enabled, admission.generation == generation, defaults.bool(forKey: Self.enabledKey) else { return false }
        do {
            try load(); try value.validate()
            var next = games.filter { $0.id != value.id }
            next.append(value)
            next.sort { $0.startedAt > $1.startedAt }
            next = Array(next.prefix(Self.maximumGames))
            try write(next); games = next; failure = nil
            return true
        } catch {
            failure = "Playtest summary storage is unavailable. Existing data is preserved; gameplay is unaffected."
            return false
        }
    }
    func clear() throws {
        generation = UUID()
        if let url, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        games = []; loaded = true; failure = nil
    }
    private func load() throws {
        guard !loaded else { return }
        guard let url else { throw StorageFailure.unavailable }
        if !FileManager.default.fileExists(atPath: url.path) { loaded = true; return }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? NSNumber, size.intValue <= Self.maximumBytes else { throw StorageFailure.invalid }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw StorageFailure.invalid }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schema == 1, payload.games.count <= Self.maximumGames,
              Set(payload.games.map(\.id)).count == payload.games.count else { throw StorageFailure.invalid }
        for value in payload.games { try value.validate() }
        games = payload.games.map { original in
            var value = original
            if value.end == .inProgress { value.end = .interrupted; value.finishedAt = value.observedAt }
            return value
        }
        loaded = true
    }
    private func write(_ values: [DeckStudioRecordedGame]) throws {
        guard let url else { throw StorageFailure.unavailable }
        let data = try JSONEncoder().encode(Payload(schema: 1, games: values))
        guard data.count <= Self.maximumBytes else { throw StorageFailure.invalid }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    private enum StorageFailure: Error { case unavailable, invalid }
}
