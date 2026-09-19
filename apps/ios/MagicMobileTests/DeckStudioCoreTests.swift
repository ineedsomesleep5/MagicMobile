import XCTest
@testable import MagicMobile

final class DeckStudioCoreTests: XCTestCase {
    private func searchRankingCatalogue() throws -> NativeDeckMetadataCatalogue {
        var metadata: [String: Any] = [:]
        for index in 0..<2101 {
            metadata[String(format: "A%04d", index)] = ["types": ["CREATURE"], "typeLine": "Creature",
                "oracleText": "Search for a Forest.", "manaValue": 3, "colorIdentity": ["G"], "setCodes": ["TST"]]
        }
        for (name, type, identity, set, mana) in [
            ("Forest", "LAND", ["G"], "TST", 0),
            ("Forest Brook", "CREATURE", ["W"], "ALT", 3),
            ("Forest Glade", "CREATURE", ["G"], "TST", 3),
            ("Z Forest", "CREATURE", ["G"], "TST", 3)
        ] {
            metadata[name] = ["types": [type], "typeLine": type.capitalized, "manaValue": mana,
                              "colorIdentity": identity, "setCodes": [set]]
        }
        return try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": metadata.keys.sorted().reversed().map { ["name": $0] }, "cardMetadata": metadata]))
    }

    func testSearchRankingBeforeCapsAndIdentitySubsetMerge() throws {
        let catalogue = try searchRankingCatalogue()
        for identity: [String]? in [nil, ["W", "G"]] {
            let results = DeckStudioCatalogueSearch.cards(in: catalogue, query: "  fOrEsT\n", allowedIdentity: identity)
            XCTAssertEqual(results.count, 80)
            XCTAssertEqual(Array(results.prefix(6)).map(\.name), ["Forest", "Forest Brook", "Forest Glade", "Z Forest", "A0000", "A0001"])
            XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: identity, limit: 1).map(\.name), ["Forest"])
            XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: identity, limit: 3000).count, 2000)
            XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: " \n", allowedIdentity: identity, limit: 2).map(\.name), ["A0000", "A0001"])
        }
        var filter = NativeDeckMetadataCatalogue.SearchFilter(); filter.query = " FOREST "
        XCTAssertEqual(catalogue.search(filter, limit: 1).map(\.name), ["Forest"])
        XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", limit: 0).isEmpty)
    }

    func testSearchRankingNeverRestoresFilteredExactMatch() throws {
        let catalogue = try searchRankingCatalogue()
        for identity: [String]? in [nil, ["G", "W"]] {
            XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", type: "Creature", allowedIdentity: identity, limit: 1).map(\.name), ["Forest Brook"])
            XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: identity, setCode: "ALT", limit: 1).map(\.name), ["Forest Brook"])
            XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: identity, minimumManaValue: 2, maximumManaValue: 4, limit: 1).map(\.name), ["Forest Brook"])
            XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: identity, minimumManaValue: 4).isEmpty)
        }
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: ["W"], limit: 1).map(\.name), ["Forest Brook"])
        XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, query: "forest", allowedIdentity: []).isEmpty)
        var filter = NativeDeckMetadataCatalogue.SearchFilter(); filter.query = "forest"; filter.colorIdentity = ["W"]
        XCTAssertEqual(catalogue.search(filter, limit: 1).map(\.name), ["Forest Brook"])
    }

    func testSearchIncludesPartnerAndDiacriticsAndStableTies() {
        let first = DeckStudioShelfItem(id: "local:a", name: "Élan", commanders: ["One", "Partner"], tags: ["Tokens"], origin: .local, updatedAt: nil)
        let second = DeckStudioShelfItem(id: "precon:a", name: "Élan", commanders: ["Two"], tags: [], origin: .included, updatedAt: nil)
        var query = DeckStudioLibraryQuery()
        query.text = "  ELAN PARTNER "
        XCTAssertEqual(query.apply(to: [second, first], favorites: []).map(\.id), ["local:a"])
        query.text = ""; query.filter = .favorites
        XCTAssertEqual(query.apply(to: [second, first], favorites: ["precon:a"]).map(\.id), ["precon:a"])
        query.filter = .all; query.sort = .name
        XCTAssertEqual(query.apply(to: [second, first], favorites: []).map(\.id), ["local:a", "precon:a"])
    }
    func testAtomicFailurePreservesHistoryAndDraft() {
        enum Failure: Error { case expected }
        var history = DeckStudioEditHistory([1, 2])
        let token = history.generation
        XCTAssertThrowsError(try history.edit { $0.append(3); throw Failure.expected })
        XCTAssertEqual(history.value, [1, 2]); XCTAssertEqual(history.generation, token)
        XCTAssertFalse(history.canUndo); XCTAssertFalse(history.isDirty)
    }
    func testUndoRedoHaveNewGenerationEvenWhenContentsReturnToBaseline() {
        var history = DeckStudioEditHistory("a")
        let initial = history.generation
        history.edit { $0 = "b" }; let changed = history.generation
        history.undo()
        XCTAssertEqual(history.value, "a"); XCTAssertFalse(history.isDirty)
        XCTAssertNotEqual(history.generation, initial); XCTAssertNotEqual(history.generation, changed)
        history.redo(); history.markSaved(); XCTAssertFalse(history.isDirty)
        history.undo(); XCTAssertTrue(history.isDirty)
        history.edit { $0 = "c" }; XCTAssertFalse(history.canRedo)
    }
    func testBoundedRecoveryAndNoOp() {
        var history = DeckStudioEditHistory(0, limit: 2)
        let token = history.generation
        history.edit { _ in }; XCTAssertEqual(history.generation, token)
        history.edit { $0 = 1 }; history.edit { $0 = 2 }; history.edit { $0 = 3 }
        history.undo(); history.undo(); history.undo(); XCTAssertEqual(history.value, 1)
        history.restore(8); XCTAssertTrue(history.isDirty)
        history.undo(); XCTAssertEqual(history.value, 1)
    }
    func testProbabilityMatchesIndependentExactEnumeration() throws {
        // Enumerate every subset for a six-card library. This does not share the
        // production log-combinations algorithm and covers empty/full samples.
        for successes in 0...6 {
            for draws in 0...6 {
                let samples = (0..<64).filter { $0.nonzeroBitCount == draws }
                for threshold in -1...7 {
                    let passing = samples.filter { mask in
                        (mask & ((1 << successes) - 1)).nonzeroBitCount >= threshold
                    }.count
                    let expected = Double(passing) / Double(samples.count)
                    XCTAssertEqual(try DeckStudioProbability.atLeast(threshold, successes: successes, population: 6, draws: draws), expected, accuracy: 1e-12)
                }
            }
        }
        XCTAssertThrowsError(try DeckStudioProbability.atLeast(1, successes: 8, population: 7, draws: 7))
        XCTAssertThrowsError(try DeckStudioProbability.atLeast(1, successes: 1, population: 2001, draws: 7))
    }
    func testEDHRECBrowsingPolicyDoesNotConfuseLookalikeHosts() {
        XCTAssertTrue(DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(URL(string: "https://edhrec.com/commanders")!))
        for value in ["https://edhrec.com.evil.example", "https://user@edhrec.com", "http://edhrec.com", "https://edhrec.com:8443", "file:///tmp/private", "javascript:alert(1)"] {
            XCTAssertFalse(DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(URL(string: value)!))
        }
    }
    func testIdentityFilteringOccursBeforeResultCap() throws {
        var names: [String] = []
        var metadata: [String: Any] = [:]
        for index in 0..<2100 {
            let name = String(format: "A%04d Red card", index)
            names.append(name)
            metadata[name] = ["types": ["CREATURE"], "typeLine": "Creature", "colorIdentity": ["R"], "setCodes": ["TST"]]
        }
        for (name, identity) in [("Z Colorless", [String]()), ("Z Green", ["G"]), ("Z Green White", ["G", "W"]), ("Z White", ["W"])] {
            names.append(name)
            metadata[name] = ["types": ["CREATURE"], "typeLine": "Creature", "colorIdentity": identity, "setCodes": ["TST"]]
        }
        names.append("Z Unknown")
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": names.map { ["name": $0] }, "cardMetadata": metadata])
        let catalogue = try NativeDeckMetadataCatalogue(catalogueData: data)
        let results = DeckStudioCatalogueSearch.cards(in: catalogue, allowedIdentity: ["G", "W"], limit: 80)
        XCTAssertEqual(results.map(\.name), ["Z Colorless", "Z Green", "Z Green White", "Z White"])
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, allowedIdentity: []).map(\.name), ["Z Colorless"])
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, allowedIdentity: ["G"], limit: 1).map(\.name), ["Z Colorless"])
        XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, allowedIdentity: ["X"]).isEmpty)
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "Green", allowedIdentity: ["G", "W"]).count, 2)
        XCTAssertTrue(DeckStudioCatalogueSearch.cards(in: catalogue, type: "Land", allowedIdentity: ["G", "W"]).isEmpty)
    }
}
