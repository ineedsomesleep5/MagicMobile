import Foundation
import XCTest
@testable import MagicMobile

/// Deck sync against a fake server, running every scenario in parity/deck-sync-cases.json (docs/DECK_SYNC.md), the
/// cases Android and the web run too.
final class DeckSyncTests: XCTestCase {
    private struct LocalRow: Equatable { let id: String; let name: String; let cards: [String] }
    private struct ServerRow: Equatable { let id: String; let name: String; let revision: Int; let deleted: Bool }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// A library holding exactly these decks at these revisions (decks.json), and the sync record beside it.
    @MainActor
    private func library(in directory: URL, _ decks: [(id: String, name: String, revision: Int, cards: [String])],
                         sync: Any? = nil) throws -> DeckLibraryStore {
        let records = decks.map { deck in
            DeckLibraryRecord(id: deck.id, name: deck.name, commander: nil, entries: deck.cards.map { DeckEntry(cardName: $0, quantity: 1, section: "deck") },
                              revision: deck.revision, updatedAt: Date(timeIntervalSince1970: 1_792_000_000), isCloudBacked: false)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.magicMobileDecks.encode(records).write(to: directory.appendingPathComponent("decks.json"))
        if let sync, !(sync is NSNull) {
            try JSONSerialization.data(withJSONObject: sync).write(to: directory.appendingPathComponent("deck-sync.json"))
        }
        return DeckLibraryStore(cacheURL: directory.appendingPathComponent("decks.json"))
    }

    private static func localDecks(_ value: Any?) -> [(id: String, name: String, revision: Int, cards: [String])] {
        (value as? [[String: Any]] ?? []).map { ($0["id"] as! String, $0["name"] as! String, $0["revision"] as! Int, $0["cards"] as! [String]) }
    }

    @MainActor
    func testSharedCases() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/core/src/test/resources/parity/deck-sync-cases.json").standardizedFileURL
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(json["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 12)
        for item in cases {
            let name = item["name"] as! String
            let local = Self.localDecks(item["local"])
            let serverRows = item["server"] as! [[String: Any]]
            let store = try library(in: temporaryDirectory(), local, sync: item["sync"])
            let server = FakeDeckServer(serverRows)
            let sync = DeckSync(library: store, api: server)
            try await sync.sync(account: item["account"] as! String)

            let original = Set(local.map { $0.id.lowercased() } + serverRows.map { ($0["id"] as! String).lowercased() })
            let expect = item["expect"] as! [String: Any]
            let byName: (LocalRow, LocalRow) -> Bool = { $0.name < $1.name }
            let actualLocal = store.decks.map { LocalRow(id: original.contains($0.id.lowercased()) ? $0.id.lowercased() : "fork", name: $0.name,
                                                         cards: $0.entries.map(\.cardName)) }.sorted(by: byName)
            let expectedLocal = (expect["local"] as! [[String: Any]]).map {
                LocalRow(id: $0["fork"] as? Bool == true ? "fork" : ($0["id"] as! String).lowercased(), name: $0["name"] as! String, cards: $0["cards"] as! [String])
            }.sorted(by: byName)
            XCTAssertEqual(actualLocal, expectedLocal, name)

            let byServerName: (ServerRow, ServerRow) -> Bool = { $0.name < $1.name }
            let actualServer = server.decks.values.map { ServerRow(id: original.contains($0.id) ? $0.id : "fork", name: $0.name, revision: $0.revision,
                                                                   deleted: $0.deleted) }.sorted(by: byServerName)
            let expectedServer = (expect["server"] as! [[String: Any]]).map {
                ServerRow(id: $0["fork"] as? Bool == true ? "fork" : ($0["id"] as! String).lowercased(), name: $0["name"] as! String,
                          revision: $0["revision"] as! Int, deleted: $0["deleted"] as! Bool)
            }.sorted(by: byServerName)
            XCTAssertEqual(actualServer, expectedServer, name)

            for deck in store.decks { XCTAssertFalse(sync.isDirty(deck), "\(name): \(deck.name) is dirty") }
            XCTAssertEqual(sync.record.tombstones, [], name)
            for deck in server.decks.values where !deck.deleted {
                if let mine = store.record(matching: deck.id) {
                    XCTAssertEqual(mine.entries.map(\.cardName), FakeDeckServer.cards(deck.deck), name)
                }
            }
            // The record on disk reads back the same.
            XCTAssertEqual(DeckSyncState(url: sync.state.url).record, sync.record, name)
        }
    }

    @MainActor
    func testDeckDeletedHereLeavesTombstoneOnlyWhenTheServerHasIt() throws {
        let synced = "AAAAAAAA-1111-4222-8333-444444444444"
        let store = try library(in: temporaryDirectory(), [(synced, "Synced", 1, ["Forest"]), ("B1", "Local only", 1, ["Island"])],
                                sync: ["account": "A", "cursor": 1, "entries": [synced.lowercased(): ["serverRevision": 4, "syncedLocalRevision": 1]],
                                       "tombstones": [Any]()])
        let sync = DeckSync(library: store, api: FakeDeckServer([]))
        try store.deleteLocalDurably(id: synced)
        try store.deleteLocalDurably(id: "B1")
        XCTAssertEqual(sync.record.tombstones, [.init(id: synced.lowercased(), serverRevision: 4)])
        XCTAssertEqual(sync.record.entries, [:])
    }

    @MainActor
    func testSecondSyncChangesNothingAndForkNameKeepsTo512Bytes() async throws {
        let store = try library(in: temporaryDirectory(), [("L1", "Atraxa", 1, ["Sol Ring"])])
        let server = FakeDeckServer([])
        let sync = DeckSync(library: store, api: server)
        try await sync.sync(account: "A")
        let before = server.snapshot
        let decks = store.decks
        try await sync.sync(account: "A")
        XCTAssertEqual(server.snapshot, before)
        XCTAssertEqual(store.decks, decks)
        XCTAssertLessThanOrEqual(DeckSync.forkName(String(repeating: "é", count: 300)).utf8.count, 512)
        XCTAssertTrue(DeckSync.forkName(String(repeating: "é", count: 300)).hasSuffix(" (this device)"))
        XCTAssertEqual(DeckSync.forkName("Mine"), "Mine (this device)")
    }

    @MainActor
    func testConcurrentSyncsShareOneRun() async throws {
        let store = try library(in: temporaryDirectory(), [("L1", "Atraxa", 1, ["Sol Ring"])])
        let server = FakeDeckServer([])
        let sync = DeckSync(library: store, api: server)
        async let first: Void = sync.sync(account: "A")
        async let second: Void = sync.sync(account: "A")
        _ = try await (first, second)
        XCTAssertEqual(server.pulls, 2)
        XCTAssertEqual(server.decks.count, 1)
    }

    @MainActor
    func testRefusedDeckStaysLocalUntilItChanges() async throws {
        let store = try library(in: temporaryDirectory(), [("L1", "Refused", 1, ["Sol Ring"])])
        let server = FakeDeckServer([])
        server.refused = ["Refused"]
        let sync = DeckSync(library: store, api: server)
        try await sync.sync(account: "A")
        XCTAssertTrue(server.decks.isEmpty)
        XCTAssertFalse(sync.isDirty(store.decks[0]))
        XCTAssertFalse(sync.hasPendingChanges)
        // Once it changes it goes up as new (revision 0 means it was never on the server).
        server.refused = []
        let edited = try store.updateLocalDurably(DeckList(name: "Accepted", commander: nil, entries: store.decks[0].entries), id: "L1", expectedRevision: 1)
        XCTAssertTrue(sync.isDirty(edited))
        try await sync.sync(account: "A")
        XCTAssertEqual(server.decks["l1"]?.name, "Accepted")
        XCTAssertEqual(server.decks["l1"]?.revision, 1)
    }

    @MainActor
    func testDocumentRoundTripsWithCommanderPrintingAndSource() throws {
        let record = DeckLibraryRecord(name: "Krenko", commander: DeckEntry(cardName: "Krenko, Mob Boss", quantity: 1, section: "commander"),
                                       entries: [DeckEntry(cardName: "Mountain", quantity: 30, section: "deck",
                                                           printing: CardPrinting(set: "dmu", number: "268"))],
                                       sourceURL: "https://archidekt.com/decks/1/")
        let document = DeckDocument.of(record)
        XCTAssertEqual(Set(document.keys), ["format", "commander", "entries", "source"])
        XCTAssertEqual((document["source"] as? [String: String]), ["kind": "archidekt", "url": "https://archidekt.com/decks/1/"])
        XCTAssertEqual(DeckDocument.of(DeckLibraryRecord(name: "Plain", commander: nil, entries: []))["source"] as? [String: String], ["kind": "manual"])
        // Key order doesn't matter; the name does.
        let reordered = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])) as? [String: Any])
        XCTAssertTrue(DeckDocument.same(record, name: "Krenko", document: reordered))
        XCTAssertFalse(DeckDocument.same(record, name: "Krenko v2", document: reordered))
        let read = try XCTUnwrap(DeckDocument.read(name: "Krenko", reordered))
        XCTAssertEqual(read.deckList, record.deckList)
        XCTAssertEqual(read.sourceURL, record.sourceURL)
        XCTAssertEqual(read.format, "commander")
    }

    @MainActor
    func testAppliedDeckKeepsLocalIdAndIsEditable() throws {
        let store = try library(in: temporaryDirectory(), [("AAAAAAAA-1111-4222-8333-444444444444", "Old", 3, ["Forest"])])
        let content = try XCTUnwrap(DeckDocument.read(name: "New", FakeDeckServer.document(["Island"])))
        let saved = try store.applySyncedDurably(content, id: "aaaaaaaa-1111-4222-8333-444444444444")
        XCTAssertEqual(saved.id, "AAAAAAAA-1111-4222-8333-444444444444")
        XCTAssertEqual(saved.revision, 4)
        XCTAssertFalse(saved.isCloudBacked)
        XCTAssertNoThrow(try store.updateLocalDurably(DeckList(name: "Edited", commander: nil, entries: saved.entries), id: saved.id, expectedRevision: 4))
        try store.removeSyncedDurably(id: "aaaaaaaa-1111-4222-8333-444444444444")
        XCTAssertTrue(store.decks.isEmpty)
    }

    func testUserIDIsTheTokenSubject() {
        let payload = Data(#"{"sub":"3f1c2d4e-0000-4000-8000-00000000abcd","role":"authenticated"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(SupabaseLite.subject(ofToken: "e30.\(payload).sig"), "3f1c2d4e-0000-4000-8000-00000000abcd")
        XCTAssertNil(SupabaseLite.subject(ofToken: "not-a-token"))
    }
}

/// mm_decks_since / mm_deck_save / mm_deck_delete over a dictionary, as the migration does them.
private final class FakeDeckServer: DeckSyncAPI {
    var decks: [String: ServerDeck] = [:]
    var seq = 0
    var pulls = 0
    /// Names refused as `invalid_deck`.
    var refused: Set<String> = []

    static func document(_ cards: [String]) -> [String: Any] {
        ["format": "commander", "entries": cards.map { ["cardName": $0, "quantity": 1, "section": "deck"] }, "source": ["kind": "manual"]]
    }

    static func cards(_ document: [String: Any]?) -> [String] {
        (document?["entries"] as? [[String: Any]] ?? []).compactMap { $0["cardName"] as? String }
    }

    init(_ initial: [[String: Any]]) {
        for row in initial {
            let id = (row["id"] as! String).lowercased(), deleted = row["deleted"] as! Bool, changeSeq = row["seq"] as! Int
            decks[id] = ServerDeck(id: id, name: row["name"] as! String, revision: row["revision"] as! Int, changeSeq: changeSeq, deleted: deleted,
                                   deck: deleted ? nil : Self.document(row["cards"] as! [String]))
            seq = max(seq, changeSeq)
        }
    }

    var snapshot: [String] {
        decks.values.sorted { $0.changeSeq < $1.changeSeq }.map { "\($0.id)|\($0.name)|\($0.revision)|\($0.changeSeq)|\($0.deleted)|\(Self.cards($0.deck))" }
    }

    func since(_ cursor: Int) async throws -> (decks: [ServerDeck], cursor: Int, more: Bool) {
        pulls += 1
        let changed = decks.values.filter { $0.changeSeq > cursor }.sorted { $0.changeSeq < $1.changeSeq }
        return (changed, changed.last?.changeSeq ?? cursor, false)
    }

    func save(id: String, name: String, document: [String: Any], base: Int?) async throws -> (status: DeckSaveStatus, deck: ServerDeck) {
        if refused.contains(name) { throw SupabaseLite.Failure(code: "invalid_deck") }
        let key = id.lowercased()
        guard let row = decks[key] else {
            if base != nil { throw SupabaseLite.Failure(code: "not_found") }
            seq += 1
            let created = ServerDeck(id: key, name: name, revision: 1, changeSeq: seq, deleted: false, deck: document)
            decks[key] = created
            return (.saved, created)
        }
        if row.deleted || base == nil || row.revision != base { return (.conflict, row) }
        seq += 1
        let updated = ServerDeck(id: key, name: name, revision: row.revision + 1, changeSeq: seq, deleted: false, deck: document)
        decks[key] = updated
        return (.saved, updated)
    }

    func remove(id: String, base: Int) async throws -> (status: DeckDeleteStatus, deck: ServerDeck?) {
        let key = id.lowercased()
        guard let row = decks[key], !row.deleted else { return (.deleted, decks[key]) }
        if row.revision != base { return (.conflict, row) }
        seq += 1
        let gone = ServerDeck(id: key, name: row.name, revision: row.revision + 1, changeSeq: seq, deleted: true, deck: nil)
        decks[key] = gone
        return (.deleted, gone)
    }
}
