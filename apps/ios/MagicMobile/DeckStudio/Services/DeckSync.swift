import Foundation

/// Deck sync (docs/DECK_SYNC.md): this phone's library and the profile's decks on the server, kept the same on every
/// phone and browser signed in to that profile. The rules are shared with Android and the web through
/// parity/deck-sync-cases.json. A conflict never loses an edit: the server's copy keeps the id and this device's edit
/// becomes a copy named "(this device)".

/// A deck as the server answers it (mm_deck_view); `deck` is nil when deleted.
struct ServerDeck {
    let id: String
    let name: String
    let revision: Int
    let changeSeq: Int
    let deleted: Bool
    let deck: [String: Any]?
}

enum DeckSaveStatus { case saved, conflict }
enum DeckDeleteStatus { case deleted, conflict }

/// mm_decks_since / mm_deck_save / mm_deck_delete. Tests use a fake.
protocol DeckSyncAPI: AnyObject {
    func since(_ cursor: Int) async throws -> (decks: [ServerDeck], cursor: Int, more: Bool)
    func save(id: String, name: String, document: [String: Any], base: Int?) async throws -> (status: DeckSaveStatus, deck: ServerDeck)
    func remove(id: String, base: Int) async throws -> (status: DeckDeleteStatus, deck: ServerDeck?)
}

/// The sync record beside the library: the profile it synced with, the pull cursor, per deck (lower-case id) the server
/// revision last seen and the local revision that matched it, and tombstones for decks deleted here.
struct DeckSyncRecord: Codable, Equatable {
    struct Entry: Codable, Equatable { var serverRevision: Int; var syncedLocalRevision: Int }
    struct Tombstone: Codable, Equatable { var id: String; var serverRevision: Int }
    var account: String?
    var cursor = 0
    var entries: [String: Entry] = [:]
    var tombstones: [Tombstone] = []

    /// Ids compare without case: the server answers lower case, iOS makes upper case.
    var folded: DeckSyncRecord {
        var copy = self
        copy.entries = Dictionary(entries.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
        copy.tombstones = tombstones.map { Tombstone(id: $0.id.lowercased(), serverRevision: $0.serverRevision) }
        return copy
    }
}

/// The sync record in deck-sync.json beside decks.json.
@MainActor
final class DeckSyncState {
    let url: URL
    var record: DeckSyncRecord

    init(url: URL) {
        self.url = url
        record = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DeckSyncRecord.self, from: $0) }?.folded ?? DeckSyncRecord()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
final class DeckSync {
    /// Passes over the dirty decks: forks made by a conflict are pushed in the next.
    static let maxPasses = 3

    let library: DeckLibraryStore
    let state: DeckSyncState
    private let api: DeckSyncAPI
    private var running: Task<Void, Error>?

    init(library: DeckLibraryStore, state: DeckSyncState? = nil, api: DeckSyncAPI) {
        self.library = library
        self.state = state ?? DeckSyncState(url: library.cacheURL.deletingLastPathComponent().appendingPathComponent("deck-sync.json"))
        self.api = api
        // The player's delete of a synced deck becomes a tombstone the next sync sends.
        library.onDeleted = { [weak self] record in self?.noteDeleted(record) }
    }

    var record: DeckSyncRecord { state.record }

    /// `<name> (this device)`, cut to the phones' 512 bytes without splitting a character.
    nonisolated static func forkName(_ name: String) -> String {
        let suffix = " (this device)"
        var base = Substring(name)
        while (base + suffix).utf8.count > 512 { base = base.dropLast() }
        return base + suffix
    }

    func isDirty(_ record: DeckLibraryRecord) -> Bool {
        guard let entry = state.record.entries[record.id.lowercased()] else { return true }
        return entry.syncedLocalRevision != record.revision
    }

    /// Something waits to go up: a dirty deck or a tombstone.
    var hasPendingChanges: Bool { !state.record.tombstones.isEmpty || library.decks.contains(where: isDirty) }

    func noteDeleted(_ record: DeckLibraryRecord) {
        let key = record.id.lowercased()
        guard let entry = state.record.entries.removeValue(forKey: key) else { return }
        state.record.tombstones.append(.init(id: key, serverRevision: entry.serverRevision))
        state.save()
    }

    /// One sync for `account` (the signed-in profile's id). Concurrent calls share the running one.
    func sync(account: String) async throws {
        if let running { return try await running.value }
        let run = Task { try await self.run(account: account) }
        running = run
        defer { if running == run { running = nil } }
        try await run.value
    }

    private func run(account: String) async throws {
        // 1. Another profile: start over, so every deck here joins it. Nothing local is deleted.
        if state.record.account != account {
            state.record = DeckSyncRecord(account: account)
            state.save()
        }
        // 2. Pull.
        try await pull()
        // 3. Deletions made here.
        for tombstone in state.record.tombstones {
            let answer = try await api.remove(id: tombstone.id, base: tombstone.serverRevision)
            if let index = state.record.tombstones.firstIndex(of: tombstone) { state.record.tombstones.remove(at: index) }
            if answer.status == .conflict, let deck = answer.deck { try apply(deck) }
            state.save()
        }
        // 4. Changes made here; a conflict's fork goes up in the next pass.
        for _ in 0..<Self.maxPasses {
            let dirty = library.decks.filter(isDirty)
            if dirty.isEmpty { break }
            for record in dirty {
                guard let current = library.decks.first(where: { $0.id == record.id }), isDirty(current) else { continue }
                let key = current.id.lowercased()
                let entry = state.record.entries[key]
                // Revision 0 marks a deck the server refused: it was never there.
                let base = entry.flatMap { $0.serverRevision > 0 ? $0.serverRevision : nil }
                let answer: (status: DeckSaveStatus, deck: ServerDeck)
                do {
                    answer = try await api.save(id: current.id, name: current.name, document: DeckDocument.of(current), base: base)
                } catch where SupabaseLite.code(of: error) == "invalid_deck" {
                    // A deck the server refuses stays here, skipped until it changes.
                    state.record.entries[key] = .init(serverRevision: entry?.serverRevision ?? 0, syncedLocalRevision: current.revision)
                    continue
                }
                if answer.status == .saved {
                    mark(current, answer.deck)
                } else if !answer.deck.deleted, DeckDocument.same(current, name: answer.deck.name, document: answer.deck.deck) {
                    mark(current, answer.deck)
                } else {
                    try fork(current)
                    try apply(answer.deck, forked: true)
                }
                state.save()
            }
        }
        // 5. Pull again, past this device's own changes.
        try await pull()
    }

    private func pull() async throws {
        for _ in 0..<100 {
            let answer = try await api.since(state.record.cursor)
            for deck in answer.decks { try apply(deck) }
            state.record.cursor = answer.cursor
            state.save()
            if !answer.more { return }
        }
    }

    /// One server deck into the library, by the pull rules; `forked` when this device's edit is already kept as a copy.
    /// A library write that fails stops the sync before the cursor moves, so the next sync applies this deck again.
    private func apply(_ server: ServerDeck, forked: Bool = false) throws {
        let key = server.id.lowercased()
        if let index = state.record.tombstones.firstIndex(where: { $0.id == key }) {
            if server.deleted { state.record.tombstones.remove(at: index); return }
            if server.revision == state.record.tombstones[index].serverRevision { return }
            state.record.tombstones.remove(at: index)
        }
        guard let local = library.record(matching: server.id) else {
            if !server.deleted { take(server) }
            return
        }
        if !server.deleted, DeckDocument.same(local, name: server.name, document: server.deck) { mark(local, server); return }
        if isDirty(local), !forked {
            if let entry = state.record.entries[key], entry.serverRevision == server.revision { return }
            try fork(local)
        }
        if server.deleted {
            try library.removeSyncedDurably(id: local.id)
            state.record.entries.removeValue(forKey: key)
        } else {
            take(server)
        }
    }

    private func take(_ server: ServerDeck) {
        guard let content = DeckDocument.read(name: server.name, server.deck) else { return }
        // A deck this library can't hold stays on the server.
        if let saved = try? library.applySyncedDurably(content, id: server.id) { mark(saved, server) }
    }

    private func mark(_ local: DeckLibraryRecord, _ server: ServerDeck) {
        state.record.entries[local.id.lowercased()] = .init(serverRevision: server.revision, syncedLocalRevision: local.revision)
    }

    /// This device's edit as a new deck (new id, same format and source), so the server's copy can take the id.
    /// Deck colours follow the commanders, so the copy shows the same ones.
    private func fork(_ local: DeckLibraryRecord) throws {
        _ = try library.duplicateLocalDurably(local, name: Self.forkName(local.name))
    }
}

/// The server functions over the account's Supabase client.
final class SupabaseDeckSync: DeckSyncAPI {
    private let api: SupabaseLite

    init(api: SupabaseLite) { self.api = api }

    private static func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

    static func view(_ value: Any?) -> ServerDeck {
        let row = value as? [String: Any] ?? [:]
        return ServerDeck(id: row["id"] as? String ?? "", name: row["name"] as? String ?? "", revision: int(row["revision"]) ?? 0,
                          changeSeq: int(row["changeSeq"]) ?? 0, deleted: row["deleted"] as? Bool == true, deck: row["deck"] as? [String: Any])
    }

    func since(_ cursor: Int) async throws -> (decks: [ServerDeck], cursor: Int, more: Bool) {
        let answer = try Self.object(try await api.rpc("mm_decks_since", ["p_cursor": cursor]))
        return ((answer["decks"] as? [Any] ?? []).map(Self.view), Self.int(answer["cursor"]) ?? cursor, answer["more"] as? Bool == true)
    }

    func save(id: String, name: String, document: [String: Any], base: Int?) async throws -> (status: DeckSaveStatus, deck: ServerDeck) {
        let answer = try Self.object(try await api.rpc("mm_deck_save", ["p_id": id, "p_name": name, "p_deck": document,
                                                                         "p_base": base.map { NSNumber(value: $0) } ?? NSNull()]))
        return (answer["status"] as? String == "saved" ? .saved : .conflict, Self.view(answer["deck"]))
    }

    func remove(id: String, base: Int) async throws -> (status: DeckDeleteStatus, deck: ServerDeck?) {
        let answer = try Self.object(try await api.rpc("mm_deck_delete", ["p_id": id, "p_base": base]))
        return (answer["status"] as? String == "conflict" ? .conflict : .deleted, answer["deck"].flatMap { $0 is NSNull ? nil : Self.view($0) })
    }
}
