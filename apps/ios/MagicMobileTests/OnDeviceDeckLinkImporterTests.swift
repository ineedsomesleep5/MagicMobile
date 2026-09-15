import XCTest
@testable import MagicMobile

final class OnDeviceDeckLinkImporterTests: XCTestCase {
    private func resolver() throws -> OnDeviceDeckResolver {
        let names = ["Forest", "Island", "Leader", "Partner", "Companion", "Fire // Ice", "Front"]
        let json: [String: Any] = ["schemaVersion": 1, "upstreamCommit": "test", "catalogueHash": "test", "sourceCatalogueSHA256": "test", "sourceRegistrySHA256": "test",
            "sourceMetadataSHA256": String(repeating: "a", count: 64), "nameAliases": ["Front // Back": "Front"],
            "cards": names.enumerated().map { ["name": $0.element, "setCode": "TEST", "collectorNumber": String($0.offset)] }]
        return try OnDeviceDeckResolver(catalogueData: JSONSerialization.data(withJSONObject: json))
    }

    private func data(_ json: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: json) }

    func testProviderImportsPersistOnlyLocallyAttestedCanonicalNames() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        let archSource = try OnDeviceDeckLinkImporter.source(for: "https://archidekt.com/decks/123")
        let deck = try importer.decode(data: data(arch([archRow("Front // Back", categories: ["Commander"], quantity: 2), archRow("Fire // Ice")])), source: archSource)
        XCTAssertEqual(deck.commander?.cardName, "Front")
        XCTAssertEqual(deck.commander?.quantity, 2)
        XCTAssertEqual(deck.commander?.section, "commanders")
        XCTAssertEqual(deck.entries.first?.cardName, "Fire // Ice")
        let moxSource = try OnDeviceDeckLinkImporter.source(for: "https://moxfield.com/decks/abcdefghijklmnopqrstuv")
        let moxDeck = try importer.decode(data: data(mox(["companions": board("Front // Back", quantity: 2), "mainboard": board("Forest")])), source: moxSource)
        XCTAssertEqual(moxDeck.entries.first { $0.section == "companions" }?.cardName, "Front")
        XCTAssertEqual(moxDeck.totalCards, 3)
        XCTAssertThrowsError(try importer.decode(data: data(arch([archRow("Front // Wrong")])), source: archSource))
        XCTAssertThrowsError(try importer.decode(data: data(mox(["mainboard": board("Front // Wrong")])), source: moxSource))
    }

    private func mox(_ boards: [String: Any]) -> [String: Any] {
        ["name": "Public list", "publicId": "abcdefghijklmnopqrstuv", "visibility": "public", "boards": boards]
    }

    private func board(_ name: String, quantity: Any = 1) -> [String: Any] {
        ["cards": [name: ["quantity": quantity, "card": ["name": name]]]]
    }

    private func archRow(_ name: String, categories: [String] = [], companion: Bool = false, quantity: Any = 1) -> [String: Any] {
        ["quantity": quantity, "categories": categories, "companion": companion, "card": ["oracleCard": ["name": name]]]
    }

    private func arch(_ rows: [[String: Any]]) -> [String: Any] {
        ["id": 123, "name": "Public list", "private": false, "unlisted": false,
         "categories": [["name": "Commander", "includedInDeck": true], ["name": "Companion", "includedInDeck": false], ["name": "Sideboard", "includedInDeck": false], ["name": "Maybeboard", "includedInDeck": false]], "cards": rows]
    }

    func testExportedTextPreservesPartnersCompanionPrintingNamesAndCounts() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        let deck = try importer.importDeck(text: "\u{FEFF}// Commander\r\n1 Leader\n1 Partner\n# Companion:\n1 Companion\nDeck\n12x Forest (SET) 123 *F*\n2 Island\n1 Fire // Ice", name: "Pasted")
        XCTAssertEqual(deck.commander?.cardName, "Leader")
        XCTAssertEqual(deck.entries.filter { $0.section == "commanders" }.map(\.cardName), ["Partner"])
        XCTAssertEqual(deck.entries.filter { $0.section == "companions" }.map(\.cardName), ["Companion"])
        XCTAssertEqual(deck.totalCards, 18)
        XCTAssertEqual(deck.entries.first { $0.cardName == "Forest" }?.quantity, 12)
    }

    func testPastedUnsupportedSectionsUnknownNamesAndMalformedCountsFailClosed() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        for text in ["Sideboard\n1 Forest", "// Sideboard\n1 Forest", "SB: 1 Forest", "# Maybeboard\n1 Forest", "1 forest", "1 Missing", "0 Forest", "-1 Forest", "2000 Forest\n1 Island", "1.5 Forest", "1 Forest #Commander", "# Custom section\n1 Forest", ""] {
            XCTAssertThrowsError(try importer.importDeck(text: text, name: "Invalid"), text)
        }
        XCTAssertThrowsError(try importer.importDeck(text: String(repeating: "x", count: OnDeviceDeckLinkImporter.maximumBytes + 1), name: "Huge"))
    }

    func testOfflineSearchReturnsExactCompiledNamesInStableOrder() throws {
        let resolver = try resolver()
        XCTAssertEqual(resolver.searchCardNames(query: "I"), ["Companion", "Fire // Ice", "Island"])
        XCTAssertEqual(resolver.searchCardNames(query: "i", limit: 1), ["Companion"])
        XCTAssertEqual(resolver.searchCardNames(query: " "), [])
        XCTAssertEqual(resolver.searchCardNames(query: "i", limit: -1), [])
        XCTAssertTrue(resolver.containsCard(name: "Forest"))
        XCTAssertFalse(resolver.containsCard(name: "forest"))
    }

    func testMoxfieldSectionsResolveLocallyWithoutDroppingSideboards() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        let source = try OnDeviceDeckLinkImporter.source(for: "https://moxfield.com/decks/abcdefghijklmnopqrstuv")
        let payload = mox(["mainboard": board("Forest", quantity: 37), "commanders": ["cards": ["one": ["quantity": 1, "card": ["name": "Leader"]], "two": ["quantity": 1, "card": ["name": "Partner"]]]], "companions": board("Companion"), "sideboard": ["cards": [:]]])
        let deck = try importer.decode(data: data(payload), source: source)
        XCTAssertEqual(deck.totalCards, 40)
        XCTAssertEqual(deck.commander?.cardName, "Leader")
        XCTAssertEqual(deck.entries.filter { $0.section == "commanders" }.map(\.cardName), ["Partner"])
        for section in ["sideboard", "maybeboard", "unknown"] {
            XCTAssertThrowsError(try importer.decode(data: data(mox([section: board("Forest")])), source: source))
        }
        for quantity in [0, -1, 2001, 1.5, "1", true] as [Any] {
            XCTAssertThrowsError(try importer.decode(data: data(mox(["mainboard": board("Forest", quantity: quantity)])), source: source))
        }
        XCTAssertThrowsError(try importer.decode(data: data(mox(["mainboard": board("forest")])), source: source))
        var privateDeck = payload
        privateDeck["visibility"] = "private"
        XCTAssertThrowsError(try importer.decode(data: data(privateDeck), source: source))
        privateDeck["visibility"] = "public"
        privateDeck["publicId"] = "wrong"
        XCTAssertThrowsError(try importer.decode(data: data(privateDeck), source: source))
    }

    func testArchidektRolesCategoriesAndPrivacy() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        let source = try OnDeviceDeckLinkImporter.source(for: "https://archidekt.com/decks/123")
        let payload = arch([archRow("Leader", categories: ["Commander"]), archRow("Partner", categories: ["Commander"]), archRow("Companion", categories: ["Companion"], companion: true), archRow("Forest", quantity: 37)])
        let deck = try importer.decode(data: data(payload), source: source)
        XCTAssertEqual(deck.totalCards, 40)
        XCTAssertEqual(deck.commander?.cardName, "Leader")
        XCTAssertEqual(deck.entries.filter { $0.section == "companions" }.map(\.cardName), ["Companion"])
        for row in [archRow("Forest", categories: ["Sideboard"]), archRow("Forest", categories: ["Maybeboard"]), archRow("Forest", categories: ["Unknown"]), archRow("Leader", categories: ["Commander"], companion: true), archRow("Unknown") ] {
            XCTAssertThrowsError(try importer.decode(data: data(arch([row])), source: source))
        }
        for key in ["private", "unlisted"] {
            var privateDeck = payload
            privateDeck[key] = true
            XCTAssertThrowsError(try importer.decode(data: data(privateDeck), source: source))
        }
        var mismatched = payload
        mismatched["id"] = 124
        XCTAssertThrowsError(try importer.decode(data: data(mismatched), source: source))
    }

    func testProviderBlocksRedirectsHTMLAndOversizedResponsesOfferPasteFallback() throws {
        let source = try OnDeviceDeckLinkImporter.source(for: "https://archidekt.com/decks/123")
        for status in [301, 302, 401, 403, 404, 429, 500] {
            let response = HTTPURLResponse(url: source.endpoint, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            XCTAssertThrowsError(try OnDeviceDeckLinkImporter.validate(response: response, source: source)) { error in
                XCTAssertTrue(error.localizedDescription.contains("paste"))
            }
        }
        for headers in [["Content-Type": "text/html"], ["Content-Type": "application/json", "Content-Length": "2097153"]] {
            XCTAssertThrowsError(try OnDeviceDeckLinkImporter.validate(response: HTTPURLResponse(url: source.endpoint, statusCode: 200, httpVersion: nil, headerFields: headers)!, source: source))
        }
        XCTAssertThrowsError(try OnDeviceDeckLinkImporter.validate(response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, source: source))
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        for malformed in [Data("{}".utf8), Data("<html>blocked</html>".utf8), Data(repeating: 0, count: OnDeviceDeckLinkImporter.maximumBytes + 1)] {
            XCTAssertThrowsError(try importer.decode(data: malformed, source: source))
        }
    }

    func testOnlyExactPublicDeckURLsBecomeFixedProviderEndpoints() throws {
        let mox = try OnDeviceDeckLinkImporter.source(for: "https://www.moxfield.com/decks/abcdefghijklmnopqrstuv")
        XCTAssertEqual(mox.endpoint.absoluteString, "https://api2.moxfield.com/v3/decks/all/abcdefghijklmnopqrstuv")
        let arch = try OnDeviceDeckLinkImporter.source(for: "https://archidekt.com/decks/123/my_deck#title")
        XCTAssertEqual(arch.endpoint.absoluteString, "https://archidekt.com/api/decks/123/")
        for url in ["http://archidekt.com/decks/123", "https://archidekt.com.evil.test/decks/123", "https://user@archidekt.com/decks/123", "https://archidekt.com:443/decks/123", "https://archidekt.com/decks/%31", "https://archidekt.com/decks/123?next=https://evil.test", "https://archidekt.com/api/decks/123", "https://moxfield.com/decks/public", "https://archidekt.com/decks/0", "https://archidekt.com/decks/123/a/b"] {
            XCTAssertThrowsError(try OnDeviceDeckLinkImporter.source(for: url), url)
        }
    }

    func testMoxfieldExclusionRequiresOptInAndNeverSkipsUnknownBoards() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        let source = try OnDeviceDeckLinkImporter.source(for: "https://moxfield.com/decks/abcdefghijklmnopqrstuv")
        let boards: [String: Any] = ["commanders": board("Leader"), "companions": board("Companion"),
                                     "mainboard": board("Forest", quantity: 98), "sideboard": board("Island"), "maybeboard": board("Partner")]
        XCTAssertThrowsError(try importer.decode(data: data(mox(boards)), source: source))
        let deck = try importer.decode(data: data(mox(boards)), source: source, excludeSideboards: true)
        XCTAssertEqual(deck.totalCards, 100)
        XCTAssertEqual(deck.commander?.cardName, "Leader")
        XCTAssertEqual(deck.entries.filter { $0.section == "companions" }.map(\.cardName), ["Companion"])
        XCTAssertFalse(deck.entries.contains { ["Island", "Partner"].contains($0.cardName) })
        var unknown = boards
        unknown["new-provider-section"] = board("Island")
        XCTAssertThrowsError(try importer.decode(data: data(mox(unknown)), source: source, excludeSideboards: true))
        for invalid in [board("Unknown"), board("Island", quantity: 0), board("Island", quantity: 2001)] {
            var malformed = boards
            malformed["sideboard"] = invalid
            XCTAssertThrowsError(try importer.decode(data: data(mox(malformed)), source: source, excludeSideboards: true))
        }
        var privateDeck = mox(boards)
        privateDeck["visibility"] = "private"
        XCTAssertThrowsError(try importer.decode(data: data(privateDeck), source: source, excludeSideboards: true))
    }

    func testArchidektExclusionPreservesRolesAndRejectsAmbiguity() throws {
        let importer = OnDeviceDeckLinkImporter(resolver: try resolver())
        let source = try OnDeviceDeckLinkImporter.source(for: "https://archidekt.com/decks/123")
        var payload = arch([archRow("Leader", categories: ["Commander"]), archRow("Partner", categories: ["Commander"]),
                            archRow("Companion", categories: ["Companion"], companion: true), archRow("Forest", quantity: 97),
                            archRow("Island", categories: ["Sideboard"]), archRow("Island", categories: ["Maybeboard"]),
                            archRow("Island", categories: ["Ideas"])])
        var categories = payload["categories"] as! [[String: Any]]
        categories.append(["name": "Ideas", "includedInDeck": false])
        payload["categories"] = categories
        XCTAssertThrowsError(try importer.decode(data: data(payload), source: source))
        let deck = try importer.decode(data: data(payload), source: source, excludeSideboards: true)
        XCTAssertEqual(deck.totalCards, 100)
        XCTAssertEqual(deck.commander?.cardName, "Leader")
        XCTAssertEqual(deck.entries.filter { $0.section == "commanders" }.map(\.cardName), ["Partner"])
        XCTAssertEqual(deck.entries.filter { $0.section == "companions" }.map(\.cardName), ["Companion"])
        XCTAssertFalse(deck.entries.contains { $0.cardName == "Island" })
        for row in [archRow("Leader", categories: ["Commander", "Sideboard"]),
                    archRow("Companion", categories: ["Sideboard"], companion: true),
                    archRow("Island", categories: ["Unknown"]),
                    archRow("Island", categories: ["Sideboard"], quantity: 0),
                    archRow("Unknown", categories: ["Maybeboard"])] {
            XCTAssertThrowsError(try importer.decode(data: data(arch([archRow("Forest"), row])), source: source, excludeSideboards: true))
        }
        var contradictory = arch([archRow("Leader", categories: ["Commander"]), archRow("Forest")])
        contradictory["categories"] = [["name": "Commander", "includedInDeck": false]]
        XCTAssertThrowsError(try importer.decode(data: data(contradictory), source: source, excludeSideboards: true))
        payload["private"] = true
        XCTAssertThrowsError(try importer.decode(data: data(payload), source: source, excludeSideboards: true))
    }

    /// Explicit external read opt-in only. Failures are real failures once enabled, not skips.
    /// MM_LIVE_ARCHIDEKT_URL=https://archidekt.com/decks/669560 swift test --package-path apps/ios --jobs 2 --filter OnDeviceDeckLinkImporterTests/testLiveArchidektURLSessionImport
    func testLiveArchidektURLSessionImport() async throws {
        guard let url = ProcessInfo.processInfo.environment["MM_LIVE_ARCHIDEKT_URL"], !url.isEmpty else {
            throw XCTSkip("Set MM_LIVE_ARCHIDEKT_URL to explicitly enable a public network import.")
        }
        let source = try OnDeviceDeckLinkImporter.source(for: url)
        guard case .archidekt = source.provider else { XCTFail("Live smoke requires an Archidekt deck URL"); return }
        let importer = OnDeviceDeckLinkImporter(resolver: try .bundled())
        let deck = try await importer.importDeck(url: url, excludeSideboards: true)
        XCTAssertFalse(deck.entries.isEmpty)
        XCTAssertFalse(try XCTUnwrap(deck.commander).cardName.isEmpty)
        if source.id == "669560" {
            XCTAssertEqual(deck.commander?.cardName, "Edgar Markov")
            XCTAssertEqual(deck.totalCards, 100, "Live public deck changed or section mapping is incorrect")
        }
    }
}
