import XCTest
@testable import MagicMobile

final class NativeDeckPresentationTests: XCTestCase {
    func testCardCountLabels() {
        XCTAssertEqual(NativeDeckDisplay.cardCount(0), "0 cards")
        XCTAssertEqual(NativeDeckDisplay.cardCount(1), "1 card")
        XCTAssertEqual(NativeDeckDisplay.cardCount(100), "100 cards")
    }
    func testGroupingPreservesExplicitRolesAndUnknownSections() {
        XCTAssertEqual(NativeDeckDisplay.group(section: "deck", primary: true, card: nil), "Commander")
        XCTAssertEqual(NativeDeckDisplay.group(section: " Commanders ", primary: false, card: nil), "Commander")
        XCTAssertEqual(NativeDeckDisplay.group(section: "companion", primary: false, card: nil), "Companion")
        XCTAssertEqual(NativeDeckDisplay.group(section: "sideboard", primary: false, card: nil), "Sideboard")
        XCTAssertEqual(NativeDeckDisplay.group(section: "deck", primary: false, card: nil), "Main · other / unknown type")
        XCTAssertTrue(NativeDeckDisplay.groupOrder("Commander", "Land"))
    }

    func testUnknownMetadataNeverMatchesColorlessOrTypeFilters() {
        XCTAssertTrue(NativeDeckDisplay.matches(name: "Forest", query: "forest", type: "", color: "", metadata: nil))
        XCTAssertFalse(NativeDeckDisplay.matches(name: "Forest", query: "", type: "Land", color: "", metadata: nil))
        XCTAssertFalse(NativeDeckDisplay.matches(name: "Forest", query: "", type: "", color: "C", metadata: nil))
    }

    func testPrintedColorFilterDoesNotPretendToBeCommanderIdentity() throws {
        let metadata = try NativeDeckMetadataCatalogue.bundled()
        XCTAssertTrue(NativeDeckDisplay.matches(name: "Forest", query: "", type: "Land", color: "C", metadata: metadata))
        XCTAssertFalse(NativeDeckDisplay.matches(name: "Forest", query: "", type: "", color: "G", metadata: metadata))
        XCTAssertNil(metadata.card(named: "Forest")?.colorIdentity)
    }
}
