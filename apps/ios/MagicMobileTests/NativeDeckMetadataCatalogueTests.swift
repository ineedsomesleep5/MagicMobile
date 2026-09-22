import XCTest
@testable import MagicMobile

final class NativeDeckMetadataCatalogueTests: XCTestCase {
    func testLandPreviewUsesQuantitiesAndPreservesDeck() throws {
        let payload: [String: Any] = [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": ["Forest", "Island", "Green", "Blue"].map { ["name": $0] },
            "cardMetadata": [
                "Forest": ["types": ["LAND"], "manaCost": "", "setCodes": []],
                "Island": ["types": ["LAND"], "manaCost": "", "setCodes": []],
                "Green": ["types": ["CREATURE"], "manaCost": "{G}", "setCodes": []],
                "Blue": ["types": ["INSTANT"], "manaCost": "{U}", "setCodes": []]
            ]
        ]
        let catalogue = try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: payload))
        let deck = DeckList(name: "Preview", commander: nil, entries: [
            DeckEntry(cardName: "Forest", quantity: 32, section: "deck"),
            DeckEntry(cardName: "Green", quantity: 3, section: "deck"),
            DeckEntry(cardName: "Blue", quantity: 2, section: "deck"),
            DeckEntry(cardName: "Island", quantity: 10, section: "sideboard")
        ])
        let suggestion = try catalogue.basicLandSuggestion(for: deck)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: suggestion.map { ($0.name, $0.quantity) }), ["Forest": 3, "Island": 2])
        XCTAssertEqual(deck.entries.first?.quantity, 32)
        XCTAssertTrue(try catalogue.basicLandSuggestion(for: deck, target: 30).isEmpty)
        let unknown = DeckList(name: "Unknown", commander: nil, entries: [DeckEntry(cardName: "Missing", quantity: 1, section: "deck")])
        XCTAssertTrue(try catalogue.basicLandSuggestion(for: unknown).isEmpty)
    }

    private func validationPayload(_ metadata: [String: Any] = [:], aliases: [String: String] = [:]) throws -> Data {
        var row: [String: Any] = ["setCodes": []]
        row.merge(metadata) { _, new in new }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": ["Front", "Front // Back"].map { ["name": $0] },
            "nameAliases": aliases, "cardMetadata": ["Front": row]
        ])
    }

    func testMalformedAliasesRejectAndExactNamesCannotBeOverridden() throws {
        for aliases in [["Other": "Front"], ["Front // Back": "Missing"], ["Front // ": "Front"],
                        ["Front // Back // More": "Alias", "Alias": "Front"], ["Front // Back\n": "Front"]] {
            XCTAssertThrowsError(try NativeDeckMetadataCatalogue(catalogueData: validationPayload(aliases: aliases)))
        }
        let exact = try NativeDeckMetadataCatalogue(catalogueData: validationPayload(aliases: ["Front // Back": "Front"]))
        XCTAssertEqual(exact.card(named: "Front // Back")?.name, "Front // Back")
        let alias = try NativeDeckMetadataCatalogue(catalogueData: validationPayload(aliases: ["Front // Other Back": "Front"]))
        XCTAssertEqual(alias.card(named: "Front // Other Back")?.name, "Front")
    }

    func testMalformedColorsTypesAndNamesReject() throws {
        for field in ["colors", "colorIdentity"] {
            for invalid in [["G", "G"], ["C"], ["g"], [""], "W"] as [Any] {
                XCTAssertThrowsError(try NativeDeckMetadataCatalogue(catalogueData: validationPayload([field: invalid])))
            }
        }
        for invalid in [[], [""], ["LAND", "LAND"], ["Land"], ["LAND CREATURE"], "LAND"] as [Any] {
            XCTAssertThrowsError(try NativeDeckMetadataCatalogue(catalogueData: validationPayload(["types": invalid])))
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: validationPayload()) as? [String: Any])
        for name in ["", " Front", "Front\n"] {
            json["cards"] = [["name": name]]
            XCTAssertThrowsError(try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: json)))
        }
    }

    func testFutureTypesStayUnknownRatherThanBecomingNonlandCurveEntries() throws {
        let catalogue = try NativeDeckMetadataCatalogue(catalogueData: validationPayload(["types": ["FUTURE_TYPE"], "typeLine": "Future type", "manaValue": 3]))
        XCTAssertNil(catalogue.card(named: "Front")?.types)
        XCTAssertNil(catalogue.card(named: "Front")?.typeLine)
        let deck = DeckList(name: "Future", commander: nil, entries: [DeckEntry(cardName: "Front", quantity: 2, section: "deck")])
        let stats = try catalogue.statistics(for: deck)
        XCTAssertEqual(stats.unknownTypeCount, 2)
        XCTAssertTrue(stats.manaCurve.isEmpty)
        var filter = NativeDeckMetadataCatalogue.SearchFilter(); filter.type = "Future"
        XCTAssertTrue(catalogue.search(filter).isEmpty)
    }

    private func catalogue() throws -> NativeDeckMetadataCatalogue {
        let payload: [String: Any] = [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": ["Forest", "Hybrid", "Unknown"].map { ["name": $0] },
            "nameAliases": ["Hybrid // Back": "Hybrid"],
            "cardMetadata": [
                "Forest": ["typeLine": "Basic Land — Forest", "types": ["LAND"], "oracleText": "{T}: Add {G}.", "manaValue": 0, "manaCost": "", "colors": [], "setCodes": ["SET"]],
                "Hybrid": ["typeLine": "Creature — Elf", "types": ["CREATURE"], "oracleText": "<b>Draw</b> a card.", "manaValue": 3, "manaCost": "{2}{G/W}{X}", "colors": ["W", "G"], "setCodes": ["AAA", "SET"]]
            ]
        ]
        return try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: payload))
    }

    func testExactAliasLookupAndUnavailableIdentity() throws {
        let catalogue = try catalogue()
        XCTAssertEqual(catalogue.card(named: "Hybrid // Back")?.name, "Hybrid")
        XCTAssertNil(catalogue.card(named: "hybrid"))
        XCTAssertNil(catalogue.card(named: "Hybrid // Wrong"))
        XCTAssertEqual(catalogue.card(named: "Hybrid")?.oracleText, "Draw a card.")
        XCTAssertEqual(catalogue.card(named: "Forest")?.colors, [])
        XCTAssertNil(catalogue.card(named: "Forest")?.colorIdentity)
        XCTAssertNil(catalogue.card(named: "Unknown")?.manaValue)
    }

    func testSearchFiltersAreDeterministicAndDoNotTreatUnknownAsColorless() throws {
        let catalogue = try catalogue()
        XCTAssertEqual(catalogue.search().map(\.name), ["Forest", "Hybrid", "Unknown"])
        var filter = NativeDeckMetadataCatalogue.SearchFilter()
        filter.query = "draw"; filter.type = "creature"; filter.setCode = "aaa"
        filter.minimumManaValue = 2; filter.maximumManaValue = 3; filter.colors = ["G", "W"]
        XCTAssertEqual(catalogue.search(filter).map(\.name), ["Hybrid"])
        filter.maximumManaValue = 2
        XCTAssertTrue(catalogue.search(filter).isEmpty)
        filter = .init(); filter.colors = []
        XCTAssertEqual(catalogue.search(filter).map(\.name), ["Forest"])
        filter = .init(); filter.colorIdentity = []
        XCTAssertTrue(catalogue.search(filter).isEmpty)
        XCTAssertTrue(catalogue.search(limit: 0).isEmpty)
    }

    func testStatisticsRespectSectionsQuantitiesUnknownsAndHybridSymbols() throws {
        let catalogue = try catalogue()
        let deck = DeckList(name: "Draft", commander: DeckEntry(cardName: "Hybrid", quantity: 1, section: "deck"), entries: [
            DeckEntry(cardName: "Forest", quantity: 4, section: "deck"),
            DeckEntry(cardName: "Hybrid // Back", quantity: 2, section: "main"),
            DeckEntry(cardName: "Unknown", quantity: 1, section: "deck"),
            DeckEntry(cardName: "Missing", quantity: 1, section: "deck"),
            DeckEntry(cardName: "Hybrid", quantity: 3, section: "sideboard")])
        let stats = try catalogue.statistics(for: deck)
        XCTAssertEqual(stats.cardCount, 8)
        XCTAssertEqual(stats.excludedCardCount, 4)
        XCTAssertEqual(stats.landCount, 4)
        XCTAssertEqual(stats.manaCurve, [3: 2])
        XCTAssertEqual(stats.averageManaValue, 3)
        XCTAssertEqual(stats.manaSymbolCounts, ["2": 2, "G/W": 2, "X": 2])
        XCTAssertNil(stats.manaSymbolCounts["G"])
        XCTAssertEqual(stats.unknownTypeCount, 2)
        XCTAssertEqual(stats.unknownManaCostCount, 2)
        XCTAssertEqual(stats.unknownNames, ["Missing"])
        XCTAssertEqual(try catalogue.statistics(for: deck, sections: ["commanders"]).cardCount, 1)
        XCTAssertThrowsError(try catalogue.statistics(for: DeckList(name: "Invalid", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: Int.max, section: "deck")])))
    }

    func testBundledMetadataIsTruthfulAndCarriesColorIdentity() throws {
        let catalogue = try NativeDeckMetadataCatalogue.bundled()
        let forest = try XCTUnwrap(catalogue.card(named: "Forest"))
        XCTAssertEqual(forest.manaValue, 0)
        XCTAssertEqual(forest.colors, [])
        // Color identity is not color. A basic land type carries its intrinsic mana
        // ability (CR 903.4), so a colorless Forest still has a green identity.
        XCTAssertEqual(forest.colorIdentity, ["G"])
        XCTAssertEqual(catalogue.card(named: "Sol Ring")?.colorIdentity, [])
        // Identity from a rules-text mana symbol on an otherwise colorless land.
        XCTAssertEqual(catalogue.card(named: "Bojuka Bog")?.colorIdentity, ["B"])
        XCTAssertEqual(catalogue.card(named: "The Scarab God")?.colorIdentity, ["U", "B"])
        // The reverse face contributes even when its color is absent from front text/cost.
        XCTAssertEqual(catalogue.card(named: "Archangel Avacyn")?.colorIdentity, ["W", "R"])
        XCTAssertEqual(catalogue.card(named: "Westvale Abbey")?.colorIdentity, ["B"])
        XCTAssertEqual(catalogue.card(named: "Elbrus, the Binding Blade")?.colorIdentity, ["B"])
        XCTAssertEqual(catalogue.card(named: "Brutal Cathar")?.colorIdentity, ["W", "R"])
        XCTAssertEqual(catalogue.card(named: "Blex, Vexing Pest")?.colorIdentity, ["B", "G"])
        XCTAssertEqual(catalogue.card(named: "Transguild Courier")?.colorIdentity, ["W", "U", "B", "R", "G"])
        XCTAssertEqual(catalogue.card(named: "Sacred Foundry")?.colorIdentity, ["W", "R"])
        XCTAssertTrue(forest.types?.contains("LAND") == true)
        XCTAssertFalse(forest.setCodes.isEmpty)
        let split = try XCTUnwrap(catalogue.card(named: "Fire // Ice"))
        XCTAssertEqual(split.manaValue, 4)
        XCTAssertEqual(split.manaCost, "{1}{R}{*}{1}{U}")
        XCTAssertEqual(catalogue.card(named: "Westvale Abbey // Ormendahl, Profane Prince")?.name, "Westvale Abbey")
        XCTAssertEqual(catalogue.card(named: "Revitalizing Repast // Old-Growth Grove")?.name, "Revitalizing Repast")
        XCTAssertEqual(catalogue.card(named: "Old-Growth Grove")?.name, "Revitalizing Repast")
        XCTAssertNil(catalogue.card(named: "Revitalizing Repast // Wrong Grove"))
    }

    func testReverseFaceOnlyResolvesWhenUniqueAndExactNamesWin() throws {
        let payload: [String: Any] = [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": ["Front", "Other", "Back", "Fire // Ice"].map { ["name": $0] },
            "nameAliases": ["Front // Back": "Front", "Other // Shared": "Other", "Front // Shared": "Front"],
        ]
        let catalogue = try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(catalogue.card(named: "Back")?.name, "Back")
        XCTAssertNil(catalogue.card(named: "Shared"))
        XCTAssertEqual(catalogue.card(named: "Fire // Ice")?.name, "Fire // Ice")
    }

    func testEveryPrintedCostSymbolIncludesTheFirstSymbol() throws {
        for (cost, expected) in [("{2}{G}{G}", ["2": 1, "G": 2]), ("{W/U}", ["W/U": 1]), ("{X}", ["X": 1]), ("", [:])] {
            let payload: [String: Any] = ["schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
                "cards": [["name": "Test"]], "cardMetadata": ["Test": ["manaCost": cost, "setCodes": []]]]
            let catalogue = try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: payload))
            let deck = DeckList(name: "Cost", commander: nil, entries: [DeckEntry(cardName: "Test", quantity: 1, section: "deck")])
            XCTAssertEqual(try catalogue.statistics(for: deck).manaSymbolCounts, expected, cost)
        }
    }
}
