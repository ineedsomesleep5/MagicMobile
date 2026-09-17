import Foundation
import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Production editor/projection/observer code with explicit synthetic inputs.
/// No native game, network provider, or physical-device acceptance is implied.
final class DeckStudioCompletionTests: XCTestCase {
    func testReplacementRetainsIdentityQuantityAndSectionAndUndo() throws {
        let row = NativeDeckRow(cardName: "Old card", quantity: 2, section: "maybeboard")
        let draft = NativeDeckDraft(name: "Draft", rows: [row])
        var history = DeckStudioEditHistory(draft)
        try history.edit { value in
            try DeckStudioEditorOperations.replaceCard(in: &value, rowID: row.id, name: "New card")
            _ = try value.deck()
        }
        XCTAssertEqual(history.value.rows[0].id, row.id)
        XCTAssertEqual(history.value.rows[0].quantity, 2)
        XCTAssertEqual(history.value.rows[0].section, "maybeboard")
        history.undo(); XCTAssertEqual(history.value, draft)
        XCTAssertThrowsError(try history.edit { value in
            try DeckStudioEditorOperations.replaceCard(in: &value, rowID: row.id, name: "")
            _ = try value.deck()
        })
        XCTAssertEqual(history.value, draft)
        XCTAssertThrowsError(try DeckStudioEditorOperations.replaceCard(in: &historyForMissingTest, rowID: UUID(), name: "Other"))
    }
    private var historyForMissingTest: NativeDeckDraft {
        get { NativeDeckDraft(name: "Empty") }
        set { }
    }
    func testCommanderReplacementKeepsPartnerAndPromotesOneMainCopy() throws {
        let primary = NativeDeckRow(cardName: "Old commander", section: "commanders", isPrimaryCommander: true)
        let partner = NativeDeckRow(cardName: "Partner", section: "commanders")
        var draft = NativeDeckDraft(name: "Draft", rows: [primary, partner, .init(cardName: "New commander", quantity: 2, section: " Main ")])
        try DeckStudioEditorOperations.replacePrimaryCommander(in: &draft, name: "New commander", keepOld: true)
        XCTAssertEqual(draft.rows.first?.id, primary.id)
        XCTAssertEqual(draft.rows.first?.cardName, "New commander")
        XCTAssertTrue(draft.rows.contains(partner))
        XCTAssertEqual(draft.rows.first(where: { $0.section == " Main " })?.quantity, 1)
        XCTAssertEqual(draft.rows.first(where: { $0.section == "maybeboard" })?.cardName, "Old commander")
        XCTAssertEqual(try draft.deck().commander?.cardName, "New commander")
        let after = draft
        try DeckStudioEditorOperations.replacePrimaryCommander(in: &draft, name: "New commander", keepOld: true)
        XCTAssertEqual(draft, after)
    }
    func testBasicLandSwapAtResourceLimitIsAtomic() throws {
        var draft = NativeDeckDraft(name: "Draft", rows: [.init(cardName: "Forest", quantity: 1000), .init(cardName: "Island", quantity: 1000)])
        var values = Dictionary(uniqueKeysWithValues: NativeDeckDraft.basicLandNames.map { ($0, 0) })
        values["Forest"] = 2000
        try DeckStudioEditorOperations.setBasicLands(in: &draft, quantities: values)
        XCTAssertEqual(draft.basicLandCount("Forest"), 2000)
        XCTAssertEqual(draft.basicLandCount("Island"), 0)
        let valid = draft
        values["Plains"] = 1
        XCTAssertThrowsError(try DeckStudioEditorOperations.setBasicLands(in: &draft, quantities: values))
        XCTAssertEqual(draft, valid)
        values["Forest"] = -1
        XCTAssertThrowsError(try DeckStudioEditorOperations.setBasicLands(in: &draft, quantities: values))
        XCTAssertEqual(draft, valid)
    }
    func testPlayingProjectionKeepsOriginalBoardsAndCompanions() throws {
        let deck = DeckList(name: "Original", commander: .init(cardName: "Commander", quantity: 1, section: "commanders"), entries: [
            .init(cardName: "Forest", quantity: 99, section: "deck"),
            .init(cardName: "Partner", quantity: 1, section: "commanders"),
            .init(cardName: "Companion", quantity: 1, section: "companions"),
            .init(cardName: "Maybe", quantity: 1, section: "maybeboard"),
            .init(cardName: "Side", quantity: 2, section: "sideboard")])
        let value = try DeckStudioPlayProjection(deck)
        XCTAssertEqual(value.original.entries.count, 5)
        XCTAssertEqual(value.playing.entries.map(\.cardName), ["Forest", "Partner", "Companion"])
        XCTAssertEqual(value.excluded.map(\.cardName), ["Maybe", "Side"])
        XCTAssertEqual(deck.entries.count, 5)
        XCTAssertThrowsError(try DeckStudioPlayProjection(.init(name: "Review me", commander: nil, entries: [.init(cardName: "Forest", quantity: 1, section: "mysterious imported section")])))
    }
    func testSearchManaSetAndIdentityApplyBeforeLimit() throws {
        let names = ["A off color", "B too cheap", "C wrong set", "D matching"]
        var cards: [[String: Any]] = []
        var metadata: [String: Any] = [:]
        for (index, name) in names.enumerated() {
            cards.append(["name": name])
            metadata[name] = ["typeLine": "Creature", "types": ["CREATURE"], "oracleText": "Fixture", "manaValue": index == 1 ? 1 : 3,
                              "manaCost": "{U}", "colors": [index == 0 ? "R" : "U"], "colorIdentity": [index == 0 ? "R" : "U"],
                              "setCodes": [index == 2 ? "OTHER" : "TEST"]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64), "cards": cards, "cardMetadata": metadata])
        let catalogue = try NativeDeckMetadataCatalogue(catalogueData: data)
        let result = DeckStudioCatalogueSearch.cards(in: catalogue, allowedIdentity: ["U"], setCode: "TEST", minimumManaValue: 2, maximumManaValue: 4, limit: 1)
        XCTAssertEqual(result.map(\.name), ["D matching"])
        XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, minimumManaValue: 5, maximumManaValue: 2).isEmpty)
        XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, minimumManaValue: .nan).isEmpty)
    }
    func testRecordingTransportIsByteTransparentAndKeepsEngineErrors() async throws {
        let suite = "deckstudio-observer-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeckStudioPlaytestStore(directory: directory, defaults: defaults)
        let rawReply = Data("{\"protocol\":1,\"ok\":true,\"result\":{\"example\":true}}".utf8)
        let base = ExactTransport(reply: rawReply)
        let observed = DeckStudioRecordingTransport(base: base, store: store, appBuild: "fixture")
        let request = Data("{\"protocol\":1,\"op\":\"capabilities\"}".utf8)
        let response = try await observed.request(request)
        XCTAssertEqual(response, rawReply)
        let recorded = await base.requests
        XCTAssertEqual(recorded, [request])
        await base.fail()
        do { _ = try await observed.request(request); XCTFail("Expected original transport error") }
        catch { XCTAssertEqual(error as? ExactTransport.Failure, .original) }
        await observed.runtimeClosed()
        let history = try await store.summaries()
        XCTAssertTrue(history.isEmpty)
    }
    private actor ExactTransport: EngineTransport {
        enum Failure: Error, Equatable { case original }
        let reply: Data
        var failed = false
        private(set) var requests: [Data] = []
        init(reply: Data) { self.reply = reply }
        func fail() { failed = true }
        func request(_ data: Data) async throws -> Data {
            requests.append(data)
            if failed { throw Failure.original }
            return reply
        }
    }
}
