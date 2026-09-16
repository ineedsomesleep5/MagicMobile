import Foundation
import XCTest
@testable import MagicMobile

final class OnDeviceDeckEditingTests: XCTestCase {
    func testExactProviderHostedCopiedSyntax() throws {
        // Verbatim examples, not synthesized exporter output:
        // Archidekt moderator: https://archidekt.com/forum/thread/3137701?page=3
        // Moxfield user report on provider feedback site: https://moxfield.nolt.io/2407
        let samples: [(String, String, [String])] = [
            ("1x Sol Ring (clb) [Ramp]", "deck", ["Category retained: [Ramp]", "(clb)"]),
            ("1 Sol Ring (CMM) 396 #!Mana Ramp", "deck", ["#!Mana Ramp", "(CMM) 396"])
        ]
        for (source, section, annotations) in samples {
            let result = try OnDeviceDeckEditing.importText(source, name: "Copied example")
            XCTAssertEqual(result.deck.entries.count, 1)
            XCTAssertEqual(result.deck.entries.first?.cardName, "Sol Ring")
            XCTAssertEqual(result.deck.entries.first?.quantity, 1)
            XCTAssertEqual(result.deck.entries.first?.section, section)
            XCTAssertEqual(result.annotations, annotations.map { .init(line: 1, text: $0) })
        }
    }

    func testTextExportHeadersKeepCommanderPartnerCompanionAndBoards() throws {
        let result = try OnDeviceDeckEditing.importText("""
        Commander
        1 Tymna the Weaver
        1x Thrasios, Triton Hero
        Companion:
        1 Zirda, the Dawnwaker
        // Mainboard
        2x Forest
        # Sideboard
        1 Forest
        Maybeboard
        1 Unknown New Card
        """, name: "Pasted")
        XCTAssertEqual(result.deck.commander?.cardName, "Tymna the Weaver")
        XCTAssertEqual(result.deck.entries.map(\.section), ["commanders", "companions", "deck", "sideboard", "maybeboard"])
        XCTAssertEqual(result.deck.totalCards, 7)
        XCTAssertEqual(result.deck.entries.last?.cardName, "Unknown New Card")
    }

    func testMoxfieldPrintingFoilAndBulkTagsRetainNamesAndAnnotations() throws {
        let result = try OnDeviceDeckEditing.importText("""
        1 Sol Ring (CMM) 396 #!Mana Ramp
        1 Arcane Signet (CMM) 384 *F*
        2 Rampant Growth (9ED) 263
        """, name: "Moxfield")
        XCTAssertEqual(result.deck.entries.map(\.cardName), ["Sol Ring", "Arcane Signet", "Rampant Growth"])
        XCTAssertEqual(result.deck.totalCards, 4)
        XCTAssertTrue(result.annotations.contains(.init(line: 1, text: "#!Mana Ramp")))
        XCTAssertTrue(result.annotations.contains(.init(line: 2, text: "*F*")))
        XCTAssertTrue(result.annotations.contains(.init(line: 3, text: "(9ED) 263")))
    }

    func testArchidektCategoryPrintingLabelAndCommanderTop() throws {
        let result = try OnDeviceDeckEditing.importText("""
        1x Emmara, Soul of the Accord (grn) *F* [Commander{top}] ^Owned,#000000^
        1x Sol Ring (clb) [Ramp]
        2x Swamp (ltr) 267 [Land]
        1x Unknown Future Card [Maybeboard]
        1x Forest [Sideboard]
        """, name: "Archidekt")
        XCTAssertEqual(result.deck.commander?.cardName, "Emmara, Soul of the Accord")
        XCTAssertEqual(result.deck.entries.map(\.cardName), ["Sol Ring", "Swamp", "Unknown Future Card", "Forest"])
        // Grouping categories are metadata, never engine zones.
        XCTAssertEqual(result.deck.entries.map(\.section), ["deck", "deck", "maybeboard", "sideboard"])
        XCTAssertEqual(result.deck.totalCards, 6)
        XCTAssertTrue(result.annotations.contains(.init(line: 1, text: "^Owned,#000000^")))
    }

    func testTextImportPreservesPunctuationAndUnknownCustomSections() throws {
        let names = ["Fire // Ice", "B.F.M. (Big Furry Monster)", "\"Ach! Hans, Run!\"", "Who/What/When/Where/Why", "Asmoranomardicadaistinaculdacar", "Éowyn, Shieldmaiden", "Urza's Saga"]
        let result = try OnDeviceDeckEditing.importText("// Unrecognized custom section\n" + names.map { "1 \($0)" }.joined(separator: "\n"), name: "Punctuation")
        XCTAssertEqual(result.deck.entries.map(\.cardName), names)
        XCTAssertTrue(result.deck.entries.allSatisfy { $0.section == "deck" })
        XCTAssertTrue(result.annotations.contains(.init(line: 1, text: "Grouping retained in deck: Unrecognized custom section")))
    }

    func testArchidektGroupingsPreserveMainDeckAndExplicitZones() throws {
        let result = try OnDeviceDeckEditing.importText("""
        1x Emmara, Soul of the Accord [Commander{top}]
        // Creatures
        2x Unknown Creature [Creature]
        // Ramp
        1x Sol Ring [Ramp]
        // Lands
        3x Forest [Land]
        Sideboard
        // Creatures
        1x Unknown Sideboard Creature [Creature]
        Maybeboard
        // Future ideas
        1x Unknown Future Card [Custom Group]
        """, name: "Grouped export")
        XCTAssertEqual(result.deck.commander?.cardName, "Emmara, Soul of the Accord")
        XCTAssertEqual(result.deck.entries.map(\.section), ["deck", "deck", "deck", "sideboard", "maybeboard"])
        XCTAssertEqual(result.deck.entries.map(\.quantity), [2, 1, 3, 1, 1])
        XCTAssertEqual(result.deck.totalCards, 9)
        XCTAssertTrue(result.annotations.contains(.init(line: 9, text: "Grouping retained in sideboard: Creatures")))
        XCTAssertThrowsError(try OnDeviceDeckEditing.importText("1x Forest [Land{noDeck}]", name: "Ambiguous")) { error in
            XCTAssertEqual((error as? OnDeviceDeckEditing.TextImportError)?.line, 1)
        }
    }

    func testTextImportBOMCRLFAndExactErrorLineNumbers() throws {
        let deck = try OnDeviceDeckEditing.importText("\u{FEFF}Commander\r\n1 Leader\r\n\r\nDeck\r\n2x Forest", name: "Windows").deck
        XCTAssertEqual(deck.commander?.cardName, "Leader")
        XCTAssertEqual(deck.totalCards, 3)
        let invalidRows = ["0 Forest", "-1 Forest", "1.5 Forest", "999999999999999999999 Forest", "1", "Some unknown heading", "1 Sol Ring [Ramp] [Draw]", "1 Sol Ring [", "1 Sol Ring ^Bad label^", "1 Sol Ring [Ramp{top}]"]
        for invalid in invalidRows {
            XCTAssertThrowsError(try OnDeviceDeckEditing.importText("Deck\r\n1 Forest\r\n\r\n\(invalid)", name: "Invalid")) { error in
                XCTAssertEqual((error as? OnDeviceDeckEditing.TextImportError)?.line, 4, invalid)
                XCTAssertTrue(error.localizedDescription.contains("No cards were imported."))
            }
        }
    }

    func testTextImportRejectsConflictingRolesAndLimitsWithoutDroppingRows() throws {
        for text in ["Sideboard\n1 Sol Ring [Commander]", "Commander\n1 Sol Ring [Maybeboard]", "2000 Forest\n1 Island"] {
            XCTAssertThrowsError(try OnDeviceDeckEditing.importText(text, name: "Invalid")) { error in
                XCTAssertEqual((error as? OnDeviceDeckEditing.TextImportError)?.line, 2)
            }
        }
        XCTAssertThrowsError(try OnDeviceDeckEditing.importText("Commander\n", name: "Empty"))
        XCTAssertThrowsError(try OnDeviceDeckEditing.importText(String(repeating: "x", count: OnDeviceDeckEditing.maximumJSONBytes + 1), name: "Large"))
        XCTAssertThrowsError(try OnDeviceDeckEditing.importText("1 Forest", name: " "))
        let result = try OnDeviceDeckEditing.importText("Sideboard\n1 Forest [Land]", name: "Excluded")
        XCTAssertEqual(result.deck.entries.first?.section, "sideboard")
        XCTAssertTrue(result.annotations.contains(.init(line: 2, text: "Category retained: [Land]")))
    }

    func testDeletingDeckRecoveryRemovesAllRevisionsIncludingCorruptPayloads() throws {
        let suite = "DeckStudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = NativeDeckDraft(rows: [NativeDeckRow(cardName: "Forest")])
        try NativeDeckDraftRecovery.save(draft, key: "deck.1", defaults: defaults)
        try NativeDeckDraftRecovery.save(draft, key: "deck.2", defaults: defaults)
        defaults.set(Data("broken".utf8), forKey: "deckStudio.draft.deck.3")

        NativeDeckDraftRecovery.clear(recordID: "deck", defaults: defaults)

        for revision in 1...3 {
            XCTAssertNil(defaults.data(forKey: "deckStudio.draft.deck.\(revision)"))
        }
        // A second deletion is harmless.
        NativeDeckDraftRecovery.clear(recordID: "deck", defaults: defaults)
    }

    func testDeletingDeckRecoveryPreservesOtherRecordsNewDraftAndPreferences() throws {
        let suite = "DeckStudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = NativeDeckDraft(name: "Keep me")
        for key in ["deck.1", "deck-other.1", "deck.child.1", "other.1", "new"] {
            try NativeDeckDraftRecovery.save(draft, key: key, defaults: defaults)
        }
        defaults.set(true, forKey: "magicmobile.deckArtworkNetworkEnabled")
        NativeDeckDraftRecovery.clear(recordID: "deck", defaults: defaults)
        XCTAssertNil(try NativeDeckDraftRecovery.load(key: "deck.1", defaults: defaults))
        for key in ["deck-other.1", "deck.child.1", "other.1", "new"] {
            XCTAssertEqual(try NativeDeckDraftRecovery.load(key: key, defaults: defaults), draft)
        }
        XCTAssertTrue(defaults.bool(forKey: "magicmobile.deckArtworkNetworkEnabled"))
    }

    func testRecoveryPreservesIncompleteNameRowIdentityAndSections() throws {
        let suite = "DeckStudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = NativeDeckDraft(name: "", rows: [NativeDeckRow(cardName: "Unknown", section: "sideboard")])
        try NativeDeckDraftRecovery.save(draft, key: "deck.revision1", defaults: defaults)
        XCTAssertEqual(try NativeDeckDraftRecovery.load(key: "deck.revision1", defaults: defaults), draft)
        XCTAssertNil(try NativeDeckDraftRecovery.load(key: "deck.revision2", defaults: defaults))
        NativeDeckDraftRecovery.clear(key: "deck.revision1", defaults: defaults)
        XCTAssertNil(try NativeDeckDraftRecovery.load(key: "deck.revision1", defaults: defaults))
    }

    func testCorruptRecoveryIsReportedAndRetained() throws {
        let suite = "DeckStudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("broken".utf8)
        defaults.set(data, forKey: "deckStudio.draft.new")
        XCTAssertThrowsError(try NativeDeckDraftRecovery.load(key: "new", defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: "deckStudio.draft.new"), data)
    }

    func testBasicLandToolsOnlyChangeMainDeckAndPreserveStableIdentity() throws {
        var draft = NativeDeckDraft(name: "", rows: [
            NativeDeckRow(cardName: "Forest", quantity: 4),
            NativeDeckRow(cardName: "Forest", quantity: 2, section: "main"),
            NativeDeckRow(cardName: "Forest", quantity: 3, section: "sideboard"),
            NativeDeckRow(cardName: "Forest", quantity: 1, section: "commanders", isPrimaryCommander: true)
        ])
        let firstID = draft.rows[0].id
        let protected = Array(draft.rows.suffix(2))
        XCTAssertEqual(draft.basicLandCount("Forest"), 6)
        try draft.setBasicLandCount("Forest", quantity: 10)
        XCTAssertEqual(draft.basicLandCount("Forest"), 10)
        XCTAssertEqual(draft.rows.last?.id, firstID)
        XCTAssertEqual(Array(draft.rows.prefix(2)), protected)
        try draft.setBasicLandCount("Forest", quantity: 0)
        XCTAssertEqual(draft.rows, protected)
        try draft.setBasicLandCount("Wastes", quantity: 2)
        XCTAssertEqual(draft.basicLandCount("Wastes"), 2)
    }

    func testInvalidBasicLandEditsAreAtomic() throws {
        var draft = NativeDeckDraft(name: "Limit", rows: [NativeDeckRow(cardName: "Island", quantity: 2000)])
        let original = draft.rows
        for (name, count) in [("Forest", 1), ("Island", -1), ("Island", 2001), ("Sol Ring", 1)] {
            XCTAssertThrowsError(try draft.setBasicLandCount(name, quantity: count))
            XCTAssertEqual(draft.rows, original)
        }
        try draft.setBasicLandCount("Island", quantity: 1999)
        try draft.setBasicLandCount("Forest", quantity: 1)
        XCTAssertEqual(try draft.deck().totalCards, 2000)
    }

    func testPrimaryCommanderRoleSurvivesDifferentSectionAndJSONRoundTrip() throws {
        for section in ["deck", "companions", " Unknown original section "] {
            let original = DeckList(name: "Role", commander: DeckEntry(cardName: "Tymna the Weaver", quantity: 1, section: section),
                                    entries: [DeckEntry(cardName: "Thrasios, Triton Hero", quantity: 1, section: "commanders")])
            var draft = NativeDeckDraft(deck: original)
            XCTAssertTrue(draft.rows[0].isPrimaryCommander)
            XCTAssertFalse(draft.rows[1].isPrimaryCommander)
            XCTAssertEqual(try draft.deck(), original)
            XCTAssertEqual(try NativeDeckDraft.importJSON(draft.exportJSON()).deck(), original)
            // Explicit role wins even if a partner row moves ahead of it.
            draft.rows.swapAt(0, 1)
            XCTAssertEqual(try draft.deck(), original)
        }
    }

    func testMultiplePrimaryMarkersRejectAndExplicitSectionEditClearsRole() throws {
        var draft = NativeDeckDraft(deck: input)
        draft.rows[1].isPrimaryCommander = true
        XCTAssertThrowsError(try draft.deck())
        XCTAssertThrowsError(try draft.exportJSON())
        draft.rows[1].isPrimaryCommander = false
        draft.rows[0].section = "deck"
        draft.rows[0].isPrimaryCommander = false // UI section-change contract.
        let result = try draft.deck()
        XCTAssertEqual(result.commander?.cardName, "Thrasios, Triton Hero")
        XCTAssertEqual(result.entries.first?.cardName, "Tymna the Weaver")
        XCTAssertEqual(result.entries.first?.section, "deck")
    }

    func testUnmarkedFirstCommanderFallbackPreservesSectionVerbatim() throws {
        let draft = NativeDeckDraft(name: "Fallback", rows: [
            NativeDeckRow(cardName: "Forest", section: "unknown"),
            NativeDeckRow(cardName: "Tymna the Weaver", section: " Commanders "),
            NativeDeckRow(cardName: "Thrasios, Triton Hero", section: "commanders")
        ])
        XCTAssertEqual(try draft.deck().commander?.section, " Commanders ")
        XCTAssertEqual(try draft.deck().entries.map(\.section), ["unknown", "commanders"])
    }

    func testDraftByteAndCountLimitsIncludingCommander() throws {
        XCTAssertNoThrow(try NativeDeckDraft(name: String(repeating: "é", count: 256)).deck())
        XCTAssertThrowsError(try NativeDeckDraft(name: String(repeating: "é", count: 257)).deck())
        let valid = NativeDeckRow(cardName: String(repeating: "é", count: 1000), quantity: 2000, section: "unknown")
        XCTAssertEqual(try NativeDeckDraft(name: "Bound", rows: [valid]).deck().totalCards, 2000)
        var tooLong = valid; tooLong.cardName += "x"
        XCTAssertThrowsError(try NativeDeckDraft(name: "Bound", rows: [tooLong]).deck())
        var tooMany = valid; tooMany.quantity = 2001
        XCTAssertThrowsError(try NativeDeckDraft(name: "Bound", rows: [tooMany]).deck())
        XCTAssertThrowsError(try NativeDeckDraft(name: "Bound", rows: [valid, NativeDeckRow(cardName: "Commander", section: "commanders")]).deck())
        var longSection = valid; longSection.section = String(repeating: "x", count: 2001)
        XCTAssertThrowsError(try NativeDeckDraft(name: "Bound", rows: [longSection]).deck())
    }

    func testJSONLimitIsCheckedBeforeDecodeAndMalformedInputRejects() throws {
        let oversized = Data(repeating: 0, count: OnDeviceDeckEditing.maximumJSONBytes + 1)
        XCTAssertThrowsError(try NativeDeckDraft.importJSON(oversized)) { error in
            guard case OnDeviceDeckEditing.Error.oversizedJSON = error else { return XCTFail("Must reject size before decoding") }
        }
        XCTAssertThrowsError(try NativeDeckDraft.importJSON(Data("not json".utf8)))
        let invalid = DeckList(name: "Invalid", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: Int.max, section: "deck")])
        XCTAssertThrowsError(try NativeDeckDraft.importJSON(JSONEncoder().encode(invalid)))
        let empty = NativeDeckDraft(name: "Empty draft")
        XCTAssertEqual(try NativeDeckDraft.importJSON(empty.exportJSON()).deck(), try empty.deck())
    }

    private var input: DeckList {
        DeckList(name: "Editing copy", commander: DeckEntry(cardName: "Tymna the Weaver", quantity: 1, section: "commander"), entries: [
            DeckEntry(cardName: "Thrasios, Triton Hero", quantity: 1, section: "commanders"),
            DeckEntry(cardName: "Zirda, the Dawnwaker", quantity: 1, section: "Companion"),
            DeckEntry(cardName: "Forest", quantity: 12, section: "deck"),
            DeckEntry(cardName: "Island", quantity: 3, section: "unsupported-custom-section")
        ])
    }

    func testDraftRoundTripPreservesCommanderPartnerCompanionAndUnknownSections() throws {
        let draft = NativeDeckDraft(deck: input)
        XCTAssertEqual(try draft.deck(), input)
        XCTAssertEqual(Set(draft.rows.map(\.id)).count, draft.rows.count)
        let decoded = try NativeDeckDraft.importJSON(draft.exportJSON())
        XCTAssertEqual(try decoded.deck(), input)
    }

    func testRenameQuantityAddRemoveAndCommanderReplacementDoNotMutateOriginal() throws {
        let original = input
        var draft = NativeDeckDraft(deck: original)
        let rowID = draft.rows[3].id
        draft.name = "My local draft"
        draft.rows[3].quantity = 4
        XCTAssertEqual(draft.rows[3].id, rowID)
        draft.rows[0].cardName = "Akiri, Line-Slinger"
        draft.rows.append(NativeDeckRow(cardName: "Plains", quantity: 2, section: "deck"))
        draft.rows.remove(at: 2)
        let result = try draft.deck()
        XCTAssertEqual(result.name, "My local draft")
        XCTAssertEqual(result.commander?.cardName, "Akiri, Line-Slinger")
        XCTAssertEqual(result.entries.first?.cardName, "Thrasios, Triton Hero")
        XCTAssertEqual(result.entries.first(where: { $0.cardName == "Forest" })?.quantity, 4)
        XCTAssertTrue(result.entries.contains(where: { $0.section == "unsupported-custom-section" }))
        XCTAssertEqual(original, input)
    }

    func testDraftAllowsIncompleteCountsButRejectsBlankFieldsAndBadQuantities() throws {
        XCTAssertEqual(try NativeDeckDraft(name: "Draft").deck().totalCards, 0)
        XCTAssertThrowsError(try NativeDeckDraft(name: "  \n").deck())
        for row in [NativeDeckRow(cardName: ""), NativeDeckRow(cardName: "Forest", quantity: 0),
                    NativeDeckRow(cardName: "Forest", quantity: -1), NativeDeckRow(cardName: "Forest", section: "")] {
            XCTAssertThrowsError(try NativeDeckDraft(name: "Draft", rows: [row]).deck())
        }
        XCTAssertThrowsError(try NativeDeckDraft(name: "Overflow", rows: [
            NativeDeckRow(cardName: "Forest", quantity: Int.max), NativeDeckRow(cardName: "Island")
        ]).deck())
        // Draft validation is intentionally not a card resolver or engine legality claim.
        XCTAssertNoThrow(try NativeDeckDraft(name: "Unresolved", rows: [NativeDeckRow(cardName: "Unresolved exact input")]).deck())
    }

    func testDuplicateNamesInDifferentSectionsRemainSeparateRows() throws {
        let draft = NativeDeckDraft(name: "Sections", rows: [
            NativeDeckRow(cardName: "Forest", quantity: 3, section: "deck"),
            NativeDeckRow(cardName: "Forest", quantity: 2, section: "sideboard")
        ])
        XCTAssertEqual(try draft.deck().entries.count, 2)
        XCTAssertEqual(try NativeDeckDraft.importJSON(draft.exportJSON()).deck(), try draft.deck())
    }
}
