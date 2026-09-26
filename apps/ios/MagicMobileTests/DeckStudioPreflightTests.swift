import XCTest
@testable import MagicMobile

final class DeckStudioPreflightTests: XCTestCase {
    private typealias Facts = DeckStudioPreflight.CardFacts
    private let facts: [String: Facts] = [
        "Atraxa, Praetors' Voice": Facts(name: "Atraxa, Praetors' Voice", typeLine: "Legendary Creature — Phyrexian Angel Horror", oracleText: "Flying", colorIdentity: ["W", "U", "B", "G"]),
        "Kraum, Ludevic's Opus": Facts(name: "Kraum, Ludevic's Opus", typeLine: "Legendary Creature — Zombie Horror", oracleText: "Partner", colorIdentity: ["U", "R"]),
        "Tymna the Weaver": Facts(name: "Tymna the Weaver", typeLine: "Legendary Creature — Human Cleric", oracleText: "Partner", colorIdentity: ["W", "B"]),
        "Sol Ring": Facts(name: "Sol Ring", typeLine: "Artifact", oracleText: "{T}: Add {C}{C}.", colorIdentity: []),
        "Lightning Bolt": Facts(name: "Lightning Bolt", typeLine: "Instant", oracleText: "Lightning Bolt deals 3 damage to any target.", colorIdentity: ["R"]),
        "Forest": Facts(name: "Forest", typeLine: "Basic Land — Forest", oracleText: "{T}: Add {G}.", colorIdentity: ["G"]),
        "Snow-Covered Island": Facts(name: "Snow-Covered Island", typeLine: "Basic Snow Land — Island", oracleText: "{T}: Add {U}.", colorIdentity: ["U"]),
        "Relentless Rats": Facts(name: "Relentless Rats", typeLine: "Creature — Rat", oracleText: "A deck can have any number of cards named Relentless Rats.", colorIdentity: ["B"]),
        "Seven Dwarves": Facts(name: "Seven Dwarves", typeLine: "Creature — Dwarf", oracleText: "A deck can have up to seven cards named Seven Dwarves.", colorIdentity: ["R"]),
        "Nazgûl": Facts(name: "Nazgûl", typeLine: "Creature — Wraith Knight", oracleText: "Deathtouch\nA deck can have up to nine cards named Nazgûl.", colorIdentity: ["B"]),
        "Mystery Card": Facts(name: "Mystery Card", typeLine: "Artifact", oracleText: nil, colorIdentity: nil)
    ]
    private func check(_ rows: [NativeDeckRow], resolves: ((String) -> Bool)? = { _ in true }) -> DeckStudioPreflight {
        DeckStudioPreflight(draft: NativeDeckDraft(name: "Test", rows: rows), card: { self.facts[$0] }, resolves: resolves)
    }
    private func row(_ name: String, _ quantity: Int = 1, _ section: String = "deck", primary: Bool = false) -> NativeDeckRow {
        NativeDeckRow(cardName: name, quantity: quantity, section: section, isPrimaryCommander: primary)
    }

    func testCountsMainAndCommandersAgainstOneHundred() {
        let result = check([row("Atraxa, Praetors' Voice", 1, "commanders", primary: true), row("Forest", 96),
                            row("Sol Ring", 1, "sideboard"), row("Lightning Bolt", 1, "maybeboard"), row("Sol Ring", 1, "considering")])
        XCTAssertEqual(result.count, 97)
        XCTAssertFalse(result.missingCommander)
        XCTAssertEqual(result.issueCount, 0)
        XCTAssertEqual(result.summary, "3 cards to go · No issues found")
        XCTAssertEqual(check([row("Atraxa, Praetors' Voice", 1, "commanders"), row("Forest", 100)]).summary, "1 card over · No issues found")
        XCTAssertEqual(check([row("Atraxa, Praetors' Voice", 1, "commanders"), row("Forest", 99)]).summary, "No issues found")
    }

    func testMissingCommanderIsOneIssueAndSkipsIdentity() {
        let result = check([row("Lightning Bolt"), row("Forest", 2)])
        XCTAssertTrue(result.missingCommander)
        XCTAssertNil(result.commanderIdentity)
        XCTAssertTrue(result.rows(.offIdentity).isEmpty, "No commander means no identity to judge")
        XCTAssertEqual(result.activeIssues, [.missingCommander])
        XCTAssertEqual(result.chipTitle(.missingCommander), "Missing commander")
        XCTAssertEqual(result.summary, "97 cards to go · 1 issue")
    }

    func testOffIdentityRowsUseTheCommanderIdentityAndIgnoreOtherBoards() {
        let bolt = row("Lightning Bolt"), companionBolt = row("Lightning Bolt", 1, "companion"), maybe = row("Lightning Bolt", 1, "maybeboard")
        let result = check([row("Atraxa, Praetors' Voice", 1, "commanders", primary: true), bolt, companionBolt, maybe, row("Sol Ring"), row("Forest")])
        XCTAssertEqual(result.commanderIdentity, ["W", "U", "B", "G"])
        XCTAssertEqual(result.rows(.offIdentity), [bolt.id, companionBolt.id])
        XCTAssertEqual(result.issues(for: bolt.id), [.offIdentity, .duplicate])
        XCTAssertTrue(result.issues(for: maybe.id).isEmpty, "Maybeboard cards stay out of play")
        XCTAssertEqual(result.chipTitle(.offIdentity), "Off-color · 2")
    }

    func testPartnerCommandersAreTreatedConservatively() {
        // Two commanders: identity is their union, and the pairing itself is XMage's call.
        let bolt = row("Lightning Bolt")
        let result = check([row("Kraum, Ludevic's Opus", 1, "commanders", primary: true), row("Tymna the Weaver", 1, "commanders"), bolt])
        XCTAssertEqual(result.commanderIdentity, ["U", "R", "W", "B"])
        XCTAssertTrue(result.rows(.offIdentity).isEmpty)
        XCTAssertEqual(result.issueCount, 0)
        // A commander with unknown identity switches the identity check off instead of guessing.
        let unknown = check([row("Atraxa, Praetors' Voice", 1, "commanders", primary: true), row("Mystery Card", 1, "commanders"), bolt])
        XCTAssertNil(unknown.commanderIdentity)
        XCTAssertTrue(unknown.rows(.offIdentity).isEmpty)
    }

    func testDuplicatesHonourBasicsAndAnyNumberAndUpToLimits() {
        let solA = row("Sol Ring"), solB = row("Sol Ring", 1, "maybeboard"), solC = row("Sol Ring", 1, "commanders")
        let dwarves = row("Seven Dwarves", 7), moreDwarves = row("Seven Dwarves", 8)
        let base = [row("Atraxa, Praetors' Voice", 1, "commanders", primary: true)]
        let ok = check(base + [solA, solB, row("Forest", 30), row("Snow-Covered Island", 5), row("Relentless Rats", 40), dwarves, row("Nazgûl", 9)])
        XCTAssertTrue(ok.rows(.duplicate).isEmpty, "Basics, 'any number' and 'up to seven/nine' cards stay within their limits; maybeboard copies do not count")
        XCTAssertEqual(check(base + [moreDwarves]).rows(.duplicate), [moreDwarves.id])
        XCTAssertEqual(check(base + [row("Nazgûl", 10)]).issueCount, 1)
        // A card in the command zone and the main deck is a duplicate across both rows.
        XCTAssertEqual(check(base + [solA, solC]).rows(.duplicate), [solA.id, solC.id])
        XCTAssertEqual(check(base + [row("Sol Ring", 2)]).chipTitle(.duplicate), "Duplicates · 1")
        XCTAssertEqual(DeckStudioPreflight.copyLimit(facts["Relentless Rats"]!), nil)
        XCTAssertEqual(DeckStudioPreflight.copyLimit(facts["Seven Dwarves"]!), 7)
        XCTAssertEqual(DeckStudioPreflight.copyLimit(facts["Nazgûl"]!), 9)
        XCTAssertEqual(DeckStudioPreflight.copyLimit(facts["Snow-Covered Island"]!), nil)
        XCTAssertEqual(DeckStudioPreflight.copyLimit(facts["Sol Ring"]!), 1)
    }

    func testUnresolvedPlayingRowsOnlyWhenACatalogueIsLoaded() {
        let unknown = row("Not A Real Card"), maybeUnknown = row("Also Fake", 1, "maybeboard")
        let base = [row("Atraxa, Praetors' Voice", 1, "commanders", primary: true)]
        let resolved = check(base + [unknown, maybeUnknown], resolves: { self.facts[$0] != nil })
        XCTAssertEqual(resolved.rows(.unresolved), [unknown.id])
        XCTAssertEqual(resolved.issues(for: unknown.id), [.unresolved])
        XCTAssertEqual(resolved.chipTitle(.unresolved), "Unresolved · 1")
        XCTAssertTrue(check(base + [unknown], resolves: nil).rows(.unresolved).isEmpty, "No catalogue yet: nothing is judged unresolved")
    }

    func testIssueCountTextIsSingularOrPlural() {
        XCTAssertEqual(DeckStudioPreflight.issueCountText(1), "1 issue")
        XCTAssertEqual(DeckStudioPreflight.issueCountText(2), "2 issues")
        XCTAssertEqual(DeckStudioPreflight.issueCountText(0), "0 issues")
        XCTAssertEqual(DeckStudioPreflight.caption, "Quick check · XMage confirms when you play")
        let summary = check([row("Lightning Bolt"), row("Sol Ring", 2)]).summary
        XCTAssertEqual(summary, "97 cards to go · 2 issues")
    }

    func testCatalogueBackedInitUsesMetadataAndAliases() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "a", count: 64),
            "cards": [["name": "Esika, God of the Tree"], ["name": "Sol Ring"], ["name": "Lightning Bolt"]],
            "nameAliases": ["Esika, God of the Tree // The Prismatic Bridge": "Esika, God of the Tree"],
            "cardMetadata": [
                "Esika, God of the Tree": ["types": ["CREATURE"], "typeLine": "Legendary Creature — God", "colorIdentity": ["G", "W", "U", "B", "R"], "setCodes": ["KHM"]],
                "Sol Ring": ["types": ["ARTIFACT"], "typeLine": "Artifact", "colorIdentity": [], "setCodes": ["C21"]],
                "Lightning Bolt": ["types": ["INSTANT"], "typeLine": "Instant", "colorIdentity": ["R"], "setCodes": ["M10"]]
            ]])
        let catalogue = try NativeDeckMetadataCatalogue(catalogueData: data)
        let alias = NativeDeckRow(cardName: "Esika, God of the Tree // The Prismatic Bridge", section: "commanders", isPrimaryCommander: true)
        let draft = NativeDeckDraft(name: "Esika", rows: [alias, row("Sol Ring"), row("Lightning Bolt"), row("Unknown Thing")])
        let result = DeckStudioPreflight(draft: draft, metadata: catalogue, resolver: nil)
        XCTAssertEqual(result.commanderIdentity, ["W", "U", "B", "R", "G"])
        XCTAssertTrue(result.rows(.offIdentity).isEmpty)
        XCTAssertEqual(result.rows(.unresolved).count, 1)
        XCTAssertEqual(DeckStudioPreflight(draft: draft, metadata: nil, resolver: nil).issueCount, 0)
    }
}
