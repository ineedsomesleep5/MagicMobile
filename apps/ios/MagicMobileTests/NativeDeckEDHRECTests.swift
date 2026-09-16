import XCTest
@testable import MagicMobile

final class NativeDeckEDHRECTests: XCTestCase {
    func testWebsiteIsConstantWithoutDeckData() {
        XCTAssertEqual(NativeDeckEDHREC.websiteURL.absoluteString, "https://edhrec.com/recs")
        XCTAssertNil(NativeDeckEDHREC.websiteURL.query)
        XCTAssertNil(NativeDeckEDHREC.websiteURL.fragment)
    }

    func testPartnersAndMainDeckAreSeparatedWithoutMutatingDraft() {
        let first = DeckEntry(cardName: "First Partner", quantity: 1, section: "deck")
        let deck = DeckList(name: "Private deck title", commander: first, entries: [
            DeckEntry(cardName: "Second Partner", quantity: 1, section: " Commanders "),
            DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck"),
            DeckEntry(cardName: "Forest", quantity: 12, section: " Main "),
            DeckEntry(cardName: "Companion", quantity: 1, section: "companions"),
            DeckEntry(cardName: "Side card", quantity: 1, section: "sideboard"),
            DeckEntry(cardName: "Unknown", quantity: 1, section: "mainboard")
        ])
        let handoff = NativeDeckEDHREC(deck: deck)
        XCTAssertEqual(handoff.commanders, ["First Partner", "Second Partner"])
        XCTAssertEqual(handoff.deckText, "1 Sol Ring\n12 Forest")
        XCTAssertEqual(deck.entries.count, 6)
        XCTAssertEqual(deck.commander, first)
    }

    func testEmptyDraftAndCommanderSectionWithoutPrimary() {
        let empty = NativeDeckEDHREC(deck: DeckList(name: "", commander: nil, entries: []))
        XCTAssertTrue(empty.commanders.isEmpty)
        XCTAssertTrue(empty.deckText.isEmpty)
        let handoff = NativeDeckEDHREC(deck: DeckList(name: "Draft", commander: nil, entries: [
            DeckEntry(cardName: "Commander", quantity: 1, section: "commander")
        ]))
        XCTAssertEqual(handoff.commanders, ["Commander"])
        XCTAssertTrue(handoff.deckText.isEmpty)
    }
}
