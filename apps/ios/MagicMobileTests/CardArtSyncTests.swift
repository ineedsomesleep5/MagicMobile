import XCTest
@testable import MagicMobile

/// Card picture sync against a fake server, running every scenario in parity/card-art-sync-cases.json
/// (docs/CARD_ART_SYNC.md), the same cases Android and the web run.
final class CardArtSyncTests: XCTestCase {
    /// The server's rows and the player's folder; a picture's bytes are its name.
    private final class FakeServer: CardArtSyncAPI {
        var rows: [String: ServerCardArt] = [:]
        var files = Set<String>()
        private var seq = 0
        private let refuse: String?

        init(_ rows: [[String: Any]], refuse: String?) {
            self.refuse = refuse
            for row in rows { write(row["cardKey"] as! String, row["picture"] as? String) }
            files = Set(self.rows.values.compactMap(\.picture))
        }

        @discardableResult private func write(_ key: String, _ picture: String?) -> ServerCardArt {
            seq += 1
            let row = ServerCardArt(cardKey: key, picture: picture, changeSeq: seq)
            rows[key] = row
            return row
        }

        func since(_ cursor: Int) async throws -> (arts: [ServerCardArt], cursor: Int, more: Bool) {
            let arts = rows.values.filter { $0.changeSeq > cursor }.sorted { $0.changeSeq < $1.changeSeq }
            return (arts, arts.last?.changeSeq ?? cursor, false)
        }

        func set(cardKey: String, picture: String?) async throws -> ServerCardArt {
            if cardKey == refuse { throw SupabaseLite.Failure(code: "too_many_pictures") }
            if let picture, !files.contains(picture) { throw SupabaseLite.Failure(code: "picture_missing") }
            return write(cardKey, picture)
        }

        func upload(picture: String, data: Data) async throws {
            XCTAssertEqual(String(decoding: data, as: UTF8.self), picture)
            files.insert(picture)
        }

        func download(picture: String) async throws -> Data {
            guard files.contains(picture) else { throw SupabaseLite.Failure(code: "not_found") }
            return Data(picture.utf8)
        }

        func removeFile(picture: String) async throws { files.remove(picture) }
    }

    private final class FakeLocal: CardArtLocal {
        var pictures: [String: String]
        init(_ pictures: [String: String]) { self.pictures = pictures }
        func keys() -> [String] { pictures.keys.sorted() }
        func hash(_ cardKey: String) -> String? { pictures[cardKey] }
        func data(_ cardKey: String) -> Data? { pictures[cardKey].map { Data($0.utf8) } }
        func store(_ data: Data, cardKey: String) throws { pictures[cardKey] = String(decoding: data, as: UTF8.self) }
        func remove(_ cardKey: String) { pictures[cardKey] = nil }
    }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("sync.json")
    }

    private static func record(_ value: [String: Any]) throws -> CardArtSyncRecord {
        var record = try JSONDecoder().decode(CardArtSyncRecord.self, from: JSONSerialization.data(withJSONObject: value))
        if record.account == nil { record.account = "me" }
        return record
    }

    func testSharedCases() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/core/src/test/resources/parity/card-art-sync-cases.json").standardizedFileURL
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(json["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 11)
        for item in cases {
            let name = item["name"] as! String
            let expect = item["expect"] as! [String: Any]
            let store = CardArtSyncStore(url: try temporaryFile())
            store.record = try Self.record(item["record"] as! [String: Any])
            let local = FakeLocal(item["local"] as! [String: String])
            let server = FakeServer(item["server"] as! [[String: Any]], refuse: item["refuse"] as? String)
            try await CardArtSync(local: local, store: store, api: server).sync(account: "me")
            XCTAssertEqual(local.pictures, expect["local"] as! [String: String], name)
            let serverRows = (expect["server"] as! [String: Any]).mapValues { $0 as? String }
            XCTAssertEqual(server.rows.mapValues(\.picture), serverRows, name)
            XCTAssertEqual(server.files.sorted(), (expect["files"] as! [String]).sorted(), name)
            XCTAssertEqual(store.record.synced, expect["synced"] as! [String: String], name)
            XCTAssertEqual(store.record.removed, [], name)
            XCTAssertEqual(store.record.account, "me", name)
        }
    }

    func testARemovalHereWaitsForTheNextSyncAndSurvivesARelaunch() throws {
        let file = try temporaryFile()
        let store = CardArtSyncStore(url: file)
        store.record = CardArtSyncRecord(account: "me", synced: ["gojo": "p1"])
        let sync = CardArtSync(local: FakeLocal([:]), store: store, api: FakeServer([], refuse: nil))
        sync.noteRemoved("gojo")
        XCTAssertTrue(sync.hasPendingChanges)
        XCTAssertEqual(CardArtSyncStore(url: file).record.removed, [.init(cardKey: "gojo", picture: "p1")])
    }

    /// The phone's pictures: one key per card on every platform (the front face, lower case), listed for the sync.
    func testPicturesOnThisPhoneAreListedByTheSharedCardKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let art = CustomCardArt(directory: directory)
        XCTAssertEqual(CustomCardArt.cardKey("  Delver of Secrets // Insectile Aberration "), "delver of secrets")
        try art.store(Data("p1".utf8), cardKey: "zur the enchanter")
        XCTAssertEqual(art.keys(), ["zur the enchanter"])
        XCTAssertEqual(art.hash("zur the enchanter"), CardArtSync.pictureHash(Data("p1".utf8)))
        XCTAssertNotNil(art.revision(forName: "Zur the Enchanter"))
        art.remove("zur the enchanter")
        XCTAssertEqual(art.keys(), [])
        XCTAssertNil(art.revision(forName: "Zur the Enchanter"))
    }
}
