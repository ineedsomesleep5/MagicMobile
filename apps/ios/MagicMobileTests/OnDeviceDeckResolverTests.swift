import Foundation
import XCTest
@testable import MagicMobile

final class OnDeviceDeckResolverTests: XCTestCase {
    private func aliasCatalogue(aliases: [String: String] = ["Front // Back": "Front", "Fire // Ice": "Fire"]) throws -> Data {
        let names = ["Front", "Fire", "Fire // Ice"]
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "upstreamCommit": "upstream", "catalogueHash": "registry",
            "sourceCatalogueSHA256": "source", "sourceRegistrySHA256": "report",
            "sourceMetadataSHA256": String(repeating: "a", count: 64), "nameAliases": aliases,
            "cards": names.enumerated().map { ["name": $0.element, "setCode": "SET", "collectorNumber": String($0.offset)] }
        ])
    }

    func testPinnedAliasCanonicalizesImportAndFinalResolutionButExactSplitWins() throws {
        let resolver = try OnDeviceDeckResolver(catalogueData: aliasCatalogue())
        XCTAssertEqual(resolver.canonicalCardName("Front // Back"), "Front")
        XCTAssertEqual(resolver.canonicalCardName("Fire // Ice"), "Fire // Ice")
        XCTAssertNil(resolver.canonicalCardName("Front // Wrong"))
        XCTAssertNil(resolver.canonicalCardName("front // Back"))
        XCTAssertEqual(resolver.searchCardNames(query: "Front"), ["Front"])
        let deck = try resolver.importDeck(text: "Commander\n1 Front // Back\nDeck\n2 Fire // Ice", name: "Aliases")
        XCTAssertEqual(deck.commander?.cardName, "Front")
        XCTAssertEqual(deck.entries.first?.cardName, "Fire // Ice")
        XCTAssertEqual(deck.totalCards, 3)
        let direct = DeckList(name: "Direct", commander: nil, entries: [DeckEntry(cardName: "Front // Back", quantity: 2, section: "Companion")])
        let config = try resolver.resolve(direct)
        XCTAssertEqual(config["companions"]?.array?.first?["name"]?.string, "Front")
        XCTAssertEqual(config["companions"]?.array?.first?["count"]?.integer, 2)
        let duplicate = DeckList(name: "Duplicate", commander: DeckEntry(cardName: "Front", quantity: 1, section: "commander"), entries: direct.entries)
        XCTAssertThrowsError(try resolver.resolve(duplicate))
        XCTAssertThrowsError(try resolver.importDeck(text: "1 Front // Wrong", name: "Invalid"))
    }

    func testInvalidAliasTargetsAndMissingMetadataIdentityReject() throws {
        for aliases in [["Front // Back": "Missing"], ["Front // Back": "Front // Other"], ["Wrong // Back": "Front"], ["Front // ": "Front"]] {
            XCTAssertThrowsError(try OnDeviceDeckResolver(catalogueData: aliasCatalogue(aliases: aliases)))
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: aliasCatalogue()) as? [String: Any])
        json.removeValue(forKey: "sourceMetadataSHA256")
        XCTAssertThrowsError(try OnDeviceDeckResolver(catalogueData: JSONSerialization.data(withJSONObject: json)))
    }

    func testBundledWestvaleAliasUsesExistingSelectedPrinting() throws {
        let resolver = try OnDeviceDeckResolver.bundled()
        XCTAssertEqual(resolver.canonicalCardName("Westvale Abbey // Ormendahl, Profane Prince"), "Westvale Abbey")
        XCTAssertNil(resolver.canonicalCardName("Westvale Abbey // Wrong Back"))
        let deck = try resolver.importDeck(text: "1 Westvale Abbey // Ormendahl, Profane Prince", name: "Metadata")
        let row = try XCTUnwrap(resolver.resolve(deck)["main"]?.array?.first)
        XCTAssertEqual(row["name"]?.string, "Westvale Abbey")
        XCTAssertEqual(row["setCode"]?.string, "INR")
        XCTAssertEqual(row["collectorNumber"]?.string, "287")
    }

    private func fixtureResolver() throws -> OnDeviceDeckResolver {
        try OnDeviceDeckResolver(catalogueData: Data(#"{"schemaVersion":1,"upstreamCommit":"upstream","catalogueHash":"registry","sourceCatalogueSHA256":"source","sourceRegistrySHA256":"report","cards":[{"name":"Forest","setCode":"ONE","collectorNumber":"1"},{"name":"Emmara, Soul of the Accord","setCode":"GRN","collectorNumber":"168"}]}"#.utf8))
    }

    func testResolvesExactNamesAndPreservesCounts() throws {
        let resolver = try OnDeviceDeckResolver(catalogueData: Data(#"{"schemaVersion":1,"upstreamCommit":"upstream","catalogueHash":"registry","sourceCatalogueSHA256":"source","sourceRegistrySHA256":"report","cards":[{"name":"Forest","setCode":"ONE","collectorNumber":"1"},{"name":"Emmara, Soul of the Accord","setCode":"GRN","collectorNumber":"168"}]}"#.utf8))
        let deck = DeckList(name: "My deck", commander: DeckEntry(cardName: "Emmara, Soul of the Accord", quantity: 1, section: "commander"), entries: [DeckEntry(cardName: "Forest", quantity: 37, section: "deck")])
        let config = try resolver.resolve(deck)
        XCTAssertEqual(Set(config.object!.keys), ["name", "main", "commanders", "companions"])
        XCTAssertEqual(config["name"]?.string, "My deck")
        XCTAssertEqual(config["main"]?.array?.first?["count"]?.integer, 37)
        XCTAssertEqual(config["main"]?.array?.first?["setCode"]?.string, "ONE")
        XCTAssertEqual(config["commanders"]?.array?.first?["name"]?.string, "Emmara, Soul of the Accord")
        XCTAssertEqual(config["companions"]?.array, [])
        XCTAssertEqual(resolver.upstreamCommit, "upstream")
        XCTAssertEqual(resolver.catalogueHash, "registry")
    }

    func testSavedDeckSurvivesCanonicalPrintingReplacementWithoutChangingCountsOrSections() throws {
        func resolver(set: String) throws -> OnDeviceDeckResolver {
            let names = ["Emmara, Soul of the Accord", "Forest", "Diregraf Colossus"]
            return try OnDeviceDeckResolver(catalogueData: JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "upstreamCommit": "upstream-\(set)", "catalogueHash": "registry-\(set)",
                "sourceCatalogueSHA256": "source", "sourceRegistrySHA256": "report",
                "cards": names.enumerated().map {
                    ["name": $0.element, "setCode": set, "collectorNumber": "\(set)-\($0.offset)"]
                }
            ]))
        }
        // Persist the same name-based format as the deck library, before the upgrade.
        // These printings are deterministic fixtures, not engine legality evidence.
        let original = DeckList(name: "Saved before upgrade",
            commander: DeckEntry(cardName: "Emmara, Soul of the Accord", quantity: 1, section: "commander"),
            entries: [DeckEntry(cardName: "Forest", quantity: 37, section: "deck"),
                      DeckEntry(cardName: "Diregraf Colossus", quantity: 1, section: "main")])
        let persisted = try JSONEncoder().encode(original)
        let previous = try resolver(set: "OLD").resolve(original)
        let restored = try JSONDecoder().decode(DeckList.self, from: persisted)
        let current = try resolver(set: "NEW").resolve(restored)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.totalCards, 39)
        XCTAssertEqual(current["name"], previous["name"])
        for section in ["commanders", "main", "companions"] {
            let oldRows = try XCTUnwrap(previous[section]?.array)
            let newRows = try XCTUnwrap(current[section]?.array)
            XCTAssertEqual(newRows.count, oldRows.count, section)
            for (old, new) in zip(oldRows, newRows) {
                XCTAssertEqual(new["name"], old["name"])
                XCTAssertEqual(new["count"], old["count"])
                XCTAssertEqual(old["setCode"]?.string, "OLD")
                XCTAssertEqual(new["setCode"]?.string, "NEW")
                XCTAssertEqual(new["collectorNumber"]?.string,
                               old["collectorNumber"]?.string?.replacingOccurrences(of: "OLD-", with: "NEW-"))
            }
        }
        XCTAssertEqual(try JSONDecoder().decode(DeckList.self, from: persisted), original)
    }

    func testInvalidCountsFailBeforeConversionWithoutOverflow() throws {
        let resolver = try fixtureResolver()
        for count in [-1, 0, 2001, Int.max] {
            let deck = DeckList(name: "Invalid", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: count, section: "deck")])
            XCTAssertThrowsError(try resolver.resolve(deck), "count=\(count)")
        }
        let oversized = DeckList(name: "Oversized", commander: DeckEntry(cardName: "Emmara, Soul of the Accord", quantity: 1, section: "commander"), entries: [DeckEntry(cardName: "Forest", quantity: 2000, section: "deck")])
        XCTAssertThrowsError(try resolver.resolve(oversized))
        let maximum = DeckList(name: "Maximum", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: 2000, section: "deck")])
        XCTAssertEqual(try resolver.resolve(maximum)["main"]?.array?.first?["count"]?.integer, 2000)
    }

    func testExplicitPartnerAndCompanionSectionsPreserveAllCounts() throws {
        let resolver = try fixtureResolver()
        let deck = DeckList(name: "Sections", commander: DeckEntry(cardName: "Emmara, Soul of the Accord", quantity: 1, section: "commander"), entries: [DeckEntry(cardName: "Forest", quantity: 2, section: "commanders")])
        let config = try resolver.resolve(deck)
        XCTAssertEqual(config["main"]?.array, [])
        XCTAssertEqual(config["commanders"]?.array?.count, 2)
        XCTAssertEqual(config["commanders"]?.array?.last?["count"]?.integer, 2)
        let companion = DeckList(name: "Companion", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: 2, section: "Companion")])
        XCTAssertEqual(try resolver.resolve(companion)["companions"]?.array?.first?["count"]?.integer, 2)
        // These fixtures test section transport only, not card eligibility or deck legality.
    }

    func testCrossSectionDuplicatesAreActionableAndSameSectionCountsSurvive() throws {
        let resolver = try fixtureResolver()
        let entry = DeckEntry(cardName: "Forest", quantity: 3, section: "deck")
        let duplicate = DeckList(name: "Duplicate", commander: DeckEntry(cardName: "Forest", quantity: 1, section: "commander"), entries: [entry])
        XCTAssertThrowsError(try resolver.resolve(duplicate)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Forest"))
            XCTAssertTrue(error.localizedDescription.contains("section"))
        }
        let repeated = DeckList(name: "Repeated basics", commander: nil, entries: [entry, entry])
        let rows = try XCTUnwrap(resolver.resolve(repeated)["main"]?.array)
        XCTAssertEqual(rows.compactMap { $0["count"]?.integer }.reduce(0, +), 6)
    }

    func testCatalogueRejectsAmbiguousPrinting() throws {
        let ambiguous = Data(#"{"schemaVersion":1,"upstreamCommit":"upstream","catalogueHash":"registry","sourceCatalogueSHA256":"source","sourceRegistrySHA256":"report","cards":[{"name":"Forest","setCode":"ONE","collectorNumber":"1"},{"name":"Island","setCode":"ONE","collectorNumber":"1"}]}"#.utf8)
        XCTAssertThrowsError(try OnDeviceDeckResolver(catalogueData: ambiguous))
    }

    func testEveryExistingPreconResolvesWithoutChangingSourceCounts() throws {
        let resolver = try OnDeviceDeckResolver.bundled()
        XCTAssertEqual(PreconCatalog.all.count, 5)
        for precon in PreconCatalog.all {
            let deck = precon.deckList
            let config = try resolver.resolve(deck)
            let rows = ["main", "commanders", "companions"].flatMap { config[$0]!.array! }
            let count = rows.compactMap { $0["count"]?.integer }.reduce(0, +)
            XCTAssertEqual(count, Int64(deck.totalCards), precon.name)
            XCTAssertEqual(count, 100, "Legacy source count changed: \(precon.name)")
            XCTAssertEqual(config["commanders"]?.array?.count, 1, precon.name)
            XCTAssertFalse(config["main"]!.array!.contains { $0["name"]?.string == precon.commander })
            for row in rows { XCTAssertEqual(Set(row.object!.keys), ["count", "setCode", "collectorNumber", "name"]) }
            print("PRECON \(precon.id): \(count) cards (native legality not evaluated)")
            #if SWIFT_PACKAGE
            if let directory = ProcessInfo.processInfo.environment["MAGICMOBILE_PRECON_EXPORT_DIR"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try config.encoded().write(to: folder.appendingPathComponent(precon.id + ".json"), options: .atomic)
            }
            #endif
        }
    }

    func testLocalTextImportHonorsExplicitSections() throws {
        let resolver = try fixtureResolver()
        let deck = try resolver.importDeck(text: """
        Commander:
        1 Emmara, Soul of the Accord

        Deck
        15x Forest
        22 Forest
        """, name: "Imported")
        XCTAssertEqual(deck.name, "Imported")
        XCTAssertEqual(deck.commander?.cardName, "Emmara, Soul of the Accord")
        XCTAssertEqual(deck.totalCards, 38)
        XCTAssertEqual(try resolver.resolve(deck)["main"]?.array?.count, 2)
        let companion = try resolver.importDeck(text: "Companion\n2 Forest", name: "Sections")
        XCTAssertEqual(try resolver.resolve(companion)["companions"]?.array?.first?["count"]?.integer, 2)
        let partners = try resolver.importDeck(text: "Commanders\n1 Forest\n1 Emmara, Soul of the Accord", name: "Partners")
        XCTAssertEqual(try resolver.resolve(partners)["commanders"]?.array?.count, 2)
        for text in ["Deck\nForest", "-1 Forest", "99999999999999999999999999 Forest", "1 forest", "Sideboard\n1 Forest"] {
            XCTAssertThrowsError(try resolver.importDeck(text: text, name: "Invalid"), text)
        }
    }

    func testMissingBundledCatalogueIsActionable() throws {
        XCTAssertThrowsError(try OnDeviceDeckResolver.bundled(bundle: Bundle(for: NSObject.self))) { error in
            XCTAssertTrue(error.localizedDescription.contains("ondevice-catalogue.json"))
        }
    }

    func testUnknownNamesNeverUseFuzzyOrCaseInsensitiveIdentity() throws {
        let resolver = try fixtureResolver()
        for name in ["forest", "Forrest", "Forest (ONE) 1", "Unknown Card"] {
            XCTAssertThrowsError(try resolver.resolve(DeckList(name: "Unknown", commander: nil, entries: [DeckEntry(cardName: name, quantity: 1, section: "deck")]))) { error in
                XCTAssertTrue(error.localizedDescription.contains(name))
                XCTAssertTrue(error.localizedDescription.contains("exact card name"))
            }
        }
    }

    func testMalformedOrDuplicateNameCatalogueFailsWithoutCrashing() throws {
        let source = #"{"schemaVersion":1,"upstreamCommit":"upstream","catalogueHash":"registry","sourceCatalogueSHA256":"source","sourceRegistrySHA256":"report","cards":[{"name":"Forest","setCode":"ONE","collectorNumber":"1"},{"name":"Forest","setCode":"TWO","collectorNumber":"1"}]}"#
        XCTAssertThrowsError(try OnDeviceDeckResolver(catalogueData: Data(source.utf8)))
        XCTAssertThrowsError(try OnDeviceDeckResolver(catalogueData: Data(source.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8)))
        XCTAssertThrowsError(try OnDeviceDeckResolver(catalogueData: Data("{}".utf8)))
    }
}

#if ONDEVICE_DECK_STANDALONE
@main
enum DeckResolverTestRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: OnDeviceDeckResolverTests.self)
        suite.run()
        exit(suite.testRun!.totalFailureCount == 0 ? 0 : 1)
    }
}
#endif
