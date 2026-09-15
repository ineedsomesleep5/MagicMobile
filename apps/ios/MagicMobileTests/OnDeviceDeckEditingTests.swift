import Foundation
import XCTest
@testable import MagicMobile

final class OnDeviceDeckEditingTests: XCTestCase {
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
