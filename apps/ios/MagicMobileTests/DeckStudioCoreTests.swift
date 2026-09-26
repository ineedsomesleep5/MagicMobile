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

    // MARK: Builder improvements

    private func builderCatalogue() throws -> NativeDeckMetadataCatalogue {
        let metadata: [String: [String: Any]] = [
            "Atraxa, Praetors' Voice": ["types": ["CREATURE"], "typeLine": "Legendary Creature — Phyrexian Angel Horror", "oracleText": "Flying, vigilance, deathtouch, lifelink", "manaValue": 4, "colorIdentity": ["W", "U", "B", "G"], "setCodes": ["C16"]],
            "Daretti, Scrap Savant": ["types": ["PLANESWALKER"], "typeLine": "Legendary Planeswalker — Daretti", "oracleText": "Daretti, Scrap Savant can be your commander.", "manaValue": 4, "colorIdentity": ["R"], "setCodes": ["C14"]],
            "Isamaru, Hound of Konda": ["types": ["CREATURE"], "typeLine": "Legendary Creature — Dog", "oracleText": "", "manaValue": 1, "colorIdentity": ["W"], "setCodes": ["CHK"]],
            "Sol Ring": ["types": ["ARTIFACT"], "typeLine": "Artifact", "oracleText": "{T}: Add {C}{C}.", "manaValue": 1, "colorIdentity": [], "setCodes": ["C21"], "roles": ["ramp"]],
            "Solemn Simulacrum": ["types": ["ARTIFACT", "CREATURE"], "typeLine": "Artifact Creature — Golem", "oracleText": "When this creature enters, you may search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.\nWhen this creature dies, you may draw a card.", "manaValue": 4, "colorIdentity": [], "setCodes": ["C21"], "roles": ["ramp", "cardFlow"]],
            "Counterspell": ["types": ["INSTANT"], "typeLine": "Instant", "oracleText": "Counter target spell.", "manaValue": 2, "colorIdentity": ["U"], "setCodes": ["C21"]],
            "Lightning Bolt": ["types": ["INSTANT"], "typeLine": "Instant", "oracleText": "Lightning Bolt deals 3 damage to any target.", "manaValue": 1, "colorIdentity": ["R"], "setCodes": ["M10"]],
            "Grizzly Bears": ["types": ["CREATURE"], "typeLine": "Creature — Bear", "oracleText": "", "manaValue": 2, "colorIdentity": ["G"], "setCodes": ["M10"]],
            "Forest": ["types": ["LAND"], "typeLine": "Basic Land — Forest", "oracleText": "{T}: Add {G}.", "manaValue": 0, "colorIdentity": ["G"], "setCodes": ["M10"]],
            "Soldevi Sage": ["types": ["CREATURE"], "typeLine": "Creature — Human Wizard", "oracleText": "{T}, Sacrifice two lands: Draw three cards, then discard one of them.", "manaValue": 3, "colorIdentity": ["U"], "setCodes": ["ALL"]]
        ]
        return try NativeDeckMetadataCatalogue(catalogueData: JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "sourceMetadataSHA256": String(repeating: "b", count: 64),
            "cards": metadata.keys.sorted().map { ["name": $0] }, "cardMetadata": metadata]))
    }

    func testQuickAddGrammarAcceptsCountsAndIgnoresSetsAndTags() {
        XCTAssertEqual(DeckStudioQuickAdd.parse("Sol Ring"), DeckStudioQuickAdd(quantity: 1, name: "Sol Ring", ignored: []))
        XCTAssertEqual(DeckStudioQuickAdd.parse("  2 Sol Ring "), DeckStudioQuickAdd(quantity: 2, name: "Sol Ring", ignored: []))
        XCTAssertEqual(DeckStudioQuickAdd.parse("2x Sol Ring"), DeckStudioQuickAdd(quantity: 2, name: "Sol Ring", ignored: []))
        XCTAssertEqual(DeckStudioQuickAdd.parse("12X Forest"), DeckStudioQuickAdd(quantity: 12, name: "Forest", ignored: []))
        let decorated = DeckStudioQuickAdd.parse("1x Sol Ring (clb) 123 [Ramp]")
        XCTAssertEqual(decorated, DeckStudioQuickAdd(quantity: 1, name: "Sol Ring", ignored: ["(clb) 123", "[Ramp]"]))
        XCTAssertEqual(decorated?.note, "Ignored (clb) 123 [Ramp] · sets and tags aren't saved")
        XCTAssertEqual(DeckStudioQuickAdd.parse("Sol Ring (C21)")?.ignored, ["(C21)"])
        XCTAssertNil(DeckStudioQuickAdd.parse("Sol Ring")?.note)
        // Names with ordinary parentheses or punctuation survive.
        XCTAssertEqual(DeckStudioQuickAdd.parse("B.F.M. (Big Furry Monster)")?.name, "B.F.M. (Big Furry Monster)")
        XCTAssertEqual(DeckStudioQuickAdd.parse("Circle of Protection: Red")?.name, "Circle of Protection: Red")
        // An exact card name that starts with a number beats the count.
        XCTAssertEqual(DeckStudioQuickAdd.parse("1996 World Champion") { $0 == "1996 World Champion" }?.name, "1996 World Champion")
        XCTAssertEqual(DeckStudioQuickAdd.parse("1996 World Champion")?.quantity, 1996)
        for invalid in ["", "   ", "2x", "0 Sol Ring", "2001 Forest", "[Ramp]"] {
            XCTAssertNil(DeckStudioQuickAdd.parse(invalid), invalid)
        }
    }

    func testQuickAddAndCommanderFirstEditsAreSingleDraftChanges() throws {
        var draft = NativeDeckDraft()
        try DeckStudioEditorOperations.startWithCommander(in: &draft, name: "Atraxa, Praetors' Voice")
        XCTAssertEqual(draft.name, "Atraxa, Praetors' Voice", "An untouched default name becomes the commander's name")
        XCTAssertEqual(draft.rows.map(\.cardName), ["Atraxa, Praetors' Voice"])
        XCTAssertTrue(draft.rows[0].isPrimaryCommander)
        var named = NativeDeckDraft(name: "My Superfriends")
        try DeckStudioEditorOperations.startWithCommander(in: &named, name: "Atraxa, Praetors' Voice")
        XCTAssertEqual(named.name, "My Superfriends", "A name the player chose is kept")

        try DeckStudioEditorOperations.add(in: &draft, name: "Sol Ring", quantity: 2, section: "deck")
        try DeckStudioEditorOperations.add(in: &draft, name: "Sol Ring", quantity: 1, section: "main")
        try DeckStudioEditorOperations.add(in: &draft, name: "Sol Ring", quantity: 1, section: "maybeboard")
        try DeckStudioEditorOperations.add(in: &draft, name: "Sol Ring", quantity: 1, section: "considering")
        XCTAssertEqual(draft.rows.filter { $0.cardName == "Sol Ring" }.map(\.quantity), [3, 2], "Main merges; considering is the maybeboard")
        XCTAssertThrowsError(try DeckStudioEditorOperations.add(in: &draft, name: "Sol Ring", quantity: 0, section: "deck"))
        XCTAssertThrowsError(try DeckStudioEditorOperations.add(in: &draft, name: " ", quantity: 1, section: "deck"))

        var history = DeckStudioEditHistory(NativeDeckDraft())
        try history.edit { try DeckStudioEditorOperations.add(in: &$0, name: "Forest", quantity: 30, section: "deck") }
        XCTAssertEqual(history.value.rows.map(\.quantity), [30])
        history.undo()
        XCTAssertTrue(history.value.rows.isEmpty, "One Undo removes the whole quick add")
    }

    func testBulkMoveQuantityAndRemoveAreAtomic() throws {
        let a = NativeDeckRow(cardName: "Sol Ring"), b = NativeDeckRow(cardName: "Counterspell", quantity: 2)
        let commander = NativeDeckRow(cardName: "Atraxa, Praetors' Voice", section: "commanders", isPrimaryCommander: true)
        var draft = NativeDeckDraft(name: "Bulk", rows: [commander, a, b])
        try DeckStudioEditorOperations.moveRows(in: &draft, ids: [a.id, commander.id], to: "maybeboard")
        XCTAssertEqual(draft.rows.map(\.section), ["maybeboard", "maybeboard", "deck"])
        XCTAssertFalse(draft.rows[0].isPrimaryCommander, "Moving the commander clears its primary flag")
        try DeckStudioEditorOperations.setQuantity(in: &draft, ids: [a.id, b.id], quantity: 4)
        XCTAssertEqual(draft.rows.map(\.quantity), [1, 4, 4])
        let before = draft
        XCTAssertThrowsError(try DeckStudioEditorOperations.setQuantity(in: &draft, ids: [a.id], quantity: 0))
        XCTAssertThrowsError(try DeckStudioEditorOperations.removeRows(in: &draft, ids: [a.id, UUID()]), "A stale selection changes nothing")
        XCTAssertThrowsError(try DeckStudioEditorOperations.moveRows(in: &draft, ids: [], to: "deck"))
        XCTAssertEqual(draft, before)
        try DeckStudioEditorOperations.removeRows(in: &draft, ids: [a.id, b.id])
        XCTAssertEqual(draft.rows.map(\.cardName), ["Atraxa, Praetors' Voice"])
    }

    func testTextDiffReviewsAddsRemovesAndKeepsRowsAndPrimaryCommander() throws {
        let tymna = NativeDeckRow(cardName: "Tymna the Weaver", section: "commanders")
        let kraum = NativeDeckRow(cardName: "Kraum, Ludevic's Opus", section: "commanders", isPrimaryCommander: true)
        let sol = NativeDeckRow(cardName: "Sol Ring", section: "main")
        let island = NativeDeckRow(cardName: "Island", quantity: 3)
        let maybe = NativeDeckRow(cardName: "Counterspell", section: "considering")
        let draft = NativeDeckDraft(name: "Partners", rows: [tymna, kraum, sol, island, maybe])
        let exported = try DeckStudioTextExport.text(draft.deck())
        // Round trip: exporting and applying unchanged text is not a change.
        let same = try DeckStudioTextDiff.draft(from: exported, replacing: draft)
        XCTAssertTrue(DeckStudioTextDiff(from: draft, to: same.draft).isEmpty)
        XCTAssertEqual(same.draft.rows.first(where: \.isPrimaryCommander)?.cardName, "Kraum, Ludevic's Opus", "The chosen primary commander stays primary")
        XCTAssertEqual(same.draft.rows.first { $0.cardName == "Sol Ring" }?.id, sol.id)
        XCTAssertEqual(same.draft.rows.first { $0.cardName == "Sol Ring" }?.section, "main", "Unchanged rows keep their section spelling")

        let edited = exported.replacingOccurrences(of: "3 Island", with: "1 Island\n2 Lightning Bolt (M10) 146")
            .replacingOccurrences(of: "1 Sol Ring\n", with: "")
        let result = try DeckStudioTextDiff.draft(from: edited, replacing: draft)
        let diff = DeckStudioTextDiff(from: draft, to: result.draft)
        XCTAssertEqual(diff.added.map(\.label), ["+2 Lightning Bolt · Deck"])
        XCTAssertEqual(diff.removed.map(\.label), ["−2 Island · Deck", "−1 Sol Ring · Deck"])
        XCTAssertEqual(result.draft.name, "Partners")
        XCTAssertEqual(result.draft.rows.first { $0.cardName == "Island" }?.id, island.id)
        XCTAssertEqual(result.notes, ["Line 7: (M10) 146"])
        XCTAssertEqual(result.draft.rows.filter { DeckStudioBoard.of($0) == "commanders" }.count, 2)

        // Clearing the text removes everything, as one reviewed change.
        let cleared = try DeckStudioTextDiff.draft(from: "  \n", replacing: draft)
        XCTAssertTrue(cleared.draft.rows.isEmpty)
        XCTAssertEqual(DeckStudioTextDiff(from: draft, to: cleared.draft).removed.count, 5)
        XCTAssertThrowsError(try DeckStudioTextDiff.draft(from: "Deck\nSol Ring", replacing: draft))
    }

    func testRoleGroupsAllowSeveralRolesAndHonourReviews() throws {
        let catalogue = try builderCatalogue()
        let sol = NativeDeckRow(cardName: "Sol Ring"), solemn = NativeDeckRow(cardName: "Solemn Simulacrum")
        let bears = NativeDeckRow(cardName: "Grizzly Bears", quantity: 2), counter = NativeDeckRow(cardName: "Counterspell")
        let extraSol = NativeDeckRow(cardName: "Sol Ring", section: "main")
        let rows = [sol, solemn, bears, counter, extraSol]
        let groups = DeckStudioRoleGroups.membership(rows: rows, metadata: catalogue, overrides: [:])
        XCTAssertEqual(groups[solemn.id], ["Ramp", "Draw / card flow"], "One card sits under every role it has")
        XCTAssertEqual(groups[sol.id], ["Ramp"])
        XCTAssertEqual(groups[extraSol.id], ["Ramp"])
        XCTAssertEqual(groups[counter.id], ["Targeted interaction"])
        XCTAssertEqual(groups[bears.id], ["Other"])
        XCTAssertEqual(DeckStudioRoleGroups.uniqueCards([sol, extraSol, solemn]), 2, "Headers count unique cards")
        let reviewed = DeckStudioRoleGroups.membership(rows: rows, metadata: catalogue,
                                                       overrides: ["Grizzly Bears": [.protection], "Solemn Simulacrum": []])
        XCTAssertEqual(reviewed[bears.id], ["Protection"], "Your own review replaces automatic hints")
        XCTAssertEqual(reviewed[solemn.id], ["Other"])
        XCTAssertEqual(DeckStudioRoleGroups.order.last, "Other")
        XCTAssertEqual(DeckStudioRoleGroups.order.first, "Ramp")
    }

    func testSampleHandDrawsSevenLondonMulligansAndKeepsCommandersOut() {
        let draft = NativeDeckDraft(name: "Hand", rows: [
            NativeDeckRow(cardName: "Atraxa, Praetors' Voice", section: "commanders", isPrimaryCommander: true),
            NativeDeckRow(cardName: "Forest", quantity: 10), NativeDeckRow(cardName: "Sol Ring", section: "main"),
            NativeDeckRow(cardName: "Counterspell", section: "maybeboard"), NativeDeckRow(cardName: "Grizzly Bears", section: "companion")
        ])
        let names = DeckStudioSampleHand.libraryNames(from: draft)
        XCTAssertEqual(names.count, 11)
        XCTAssertEqual(Set(names), ["Forest", "Sol Ring"], "Commanders, companions and other boards stay out of the library")
        var generator = SeededGenerator(seed: 7)
        var hand = DeckStudioSampleHand(names: names)
        hand.deal(using: &generator)
        XCTAssertEqual(hand.hand.count, 7); XCTAssertEqual(hand.library.count, 4)
        XCTAssertEqual(hand.turn, 1); XCTAssertTrue(hand.canMulligan)
        hand.mulligan(using: &generator)
        XCTAssertEqual(hand.hand.count, 7, "London: draw a fresh seven")
        XCTAssertEqual(hand.toBottom, 1)
        XCTAssertFalse(hand.canDraw, "Choose the bottom card first")
        hand.mulligan(using: &generator)
        XCTAssertEqual(hand.mulligans, 1, "No second mulligan before bottoming")
        let bottom = hand.hand[2]
        hand.putOnBottom(bottom.id)
        XCTAssertEqual(hand.hand.count, 6); XCTAssertEqual(hand.library.last, bottom); XCTAssertEqual(hand.toBottom, 0)
        hand.mulligan(using: &generator)
        XCTAssertEqual(hand.mulligans, 2); XCTAssertEqual(hand.toBottom, 2)
        hand.putOnBottom(hand.hand[0].id); hand.putOnBottom(hand.hand[0].id)
        hand.putOnBottom(hand.hand[0].id)
        XCTAssertEqual(hand.hand.count, 5, "Only as many as the mulligans taken go to the bottom")
        let top = hand.library.first
        hand.draw()
        XCTAssertEqual(hand.hand.last, top); XCTAssertEqual(hand.turn, 2)
        XCTAssertFalse(hand.canMulligan, "No mulligans after the first draw")
        XCTAssertEqual(hand.hand.count + hand.library.count, 11, "No card is lost or duplicated")
        while hand.canDraw { hand.draw() }
        XCTAssertTrue(hand.library.isEmpty); XCTAssertEqual(hand.hand.count, 11)
        hand.deal(using: &generator)
        XCTAssertEqual(hand.hand.count, 7); XCTAssertEqual(hand.mulligans, 0); XCTAssertEqual(hand.turn, 1)
        XCTAssertEqual(Set((hand.hand + hand.library).map(\.id)).count, 11)
        var small = DeckStudioSampleHand(names: ["Forest", "Forest", "Sol Ring"])
        small.deal(using: &generator)
        XCTAssertEqual(small.hand.count, 3); XCTAssertFalse(small.canDraw)
    }

    func testSearchSyntaxParsesTypesOracleManaValueAndIdentity() {
        let syntax = DeckStudioSearchSyntax(#"t:"legendary creature" o:draw mv<=3 mv>=1 id:wu angel"#)
        XCTAssertEqual(syntax.types, ["legendary creature"])
        XCTAssertEqual(syntax.oracle, ["draw"])
        XCTAssertEqual(syntax.maximumManaValue, 3); XCTAssertEqual(syntax.minimumManaValue, 1)
        XCTAssertEqual(syntax.identity, ["W", "U"])
        XCTAssertEqual(syntax.text, "angel")
        XCTAssertEqual(DeckStudioSearchSyntax("MV=2").minimumManaValue, 2)
        XCTAssertEqual(DeckStudioSearchSyntax("mv=2").maximumManaValue, 2)
        XCTAssertEqual(DeckStudioSearchSyntax("id:c").identity, [])
        XCTAssertEqual(DeckStudioSearchSyntax("T:Instant").types, ["Instant"])
        // Plain text and names with colons stay text; half-typed terms filter nothing yet.
        XCTAssertFalse(DeckStudioSearchSyntax("Circle of Protection: Red").hasFilters)
        XCTAssertEqual(DeckStudioSearchSyntax("Circle of Protection: Red").text, "Circle of Protection: Red")
        XCTAssertEqual(DeckStudioSearchSyntax("sol t:").text, "sol")
        XCTAssertFalse(DeckStudioSearchSyntax("sol t: mv<=").hasFilters)
        XCTAssertEqual(DeckStudioSearchSyntax("id:xyz").text, "id:xyz")
        XCTAssertEqual(DeckStudioSearchSyntax("mv<=abc").text, "mv<=abc")
    }

    func testSearchSyntaxFiltersLocalCatalogueAndCommanderPicker() throws {
        let catalogue = try builderCatalogue()
        func names(_ query: String, identity: [String]? = nil) -> [String] {
            DeckStudioCatalogueSearch.cards(in: catalogue, query: query, allowedIdentity: identity).map(\.name)
        }
        XCTAssertEqual(names("t:instant"), ["Counterspell", "Lightning Bolt"])
        XCTAssertEqual(names("o:draw"), ["Soldevi Sage", "Solemn Simulacrum"])
        XCTAssertEqual(names("t:artifact mv<=1"), ["Sol Ring"])
        XCTAssertEqual(names("mv>=4 t:creature"), ["Atraxa, Praetors' Voice", "Solemn Simulacrum"])
        XCTAssertEqual(names("id:u t:instant"), ["Counterspell"])
        XCTAssertEqual(names("id:c"), ["Sol Ring", "Solemn Simulacrum"])
        XCTAssertEqual(names("sol t:artifact"), ["Sol Ring", "Solemn Simulacrum"])
        XCTAssertEqual(names("sol t:"), ["Sol Ring", "Soldevi Sage", "Solemn Simulacrum"], "A half-typed term does not empty the results")
        XCTAssertEqual(names("t:instant", identity: ["R"]), ["Lightning Bolt"], "Commander identity and id: both apply")
        XCTAssertEqual(names("id:wu t:instant", identity: ["R"]), [])
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "t:creature", type: "Artifact").map(\.name), ["Solemn Simulacrum"])
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "t:instant", minimumManaValue: 2).map(\.name), ["Counterspell"])
        XCTAssertEqual(DeckStudioCatalogueSearch.cards(in: catalogue, query: "o:counter", limit: 0), [])
        // Quick Add suggestions match names only; exact and prefix matches lead.
        XCTAssertEqual(DeckStudioCatalogueSearch.nameSuggestions(in: catalogue, query: "sol", limit: 5).map(\.name),
                       ["Sol Ring", "Soldevi Sage", "Solemn Simulacrum"])
        XCTAssertEqual(DeckStudioCatalogueSearch.nameSuggestions(in: catalogue, query: "draw").map(\.name), [])
        XCTAssertEqual(DeckStudioCatalogueSearch.nameSuggestions(in: catalogue, query: "SOL RING", limit: 1).map(\.name), ["Sol Ring"])
        // Commander-first: legendary creatures and cards that say they can be your commander.
        XCTAssertEqual(DeckStudioCatalogueSearch.commanders(in: catalogue, query: "").map(\.name),
                       ["Atraxa, Praetors' Voice", "Daretti, Scrap Savant", "Isamaru, Hound of Konda"])
        XCTAssertEqual(DeckStudioCatalogueSearch.commanders(in: catalogue, query: "id:w").map(\.name), ["Isamaru, Hound of Konda"])
        XCTAssertEqual(DeckStudioCatalogueSearch.commanders(in: catalogue, query: "hound").map(\.name), ["Isamaru, Hound of Konda"])
    }
}

/// Deterministic SplitMix64 so sample-hand tests never depend on the system generator.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
