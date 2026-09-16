import XCTest
@testable import MagicMobile

final class NativeDeckBuilderLayoutTests: XCTestCase {
    func testPortraitUsesOneExpandedPaneRegardlessOfKeyboardHeight() {
        XCTAssertFalse(NativeDeckBuilderLayout.usesColumns(width: 390))
        XCTAssertFalse(NativeDeckBuilderLayout.usesColumns(width: 440))
    }

    func testLandscapeKeepsCollectionAndDeckSideBySide() {
        XCTAssertTrue(NativeDeckBuilderLayout.usesColumns(width: 650))
        XCTAssertTrue(NativeDeckBuilderLayout.usesColumns(width: 844))
        XCTAssertEqual(NativeDeckBuilderLayout.deckWidth(width: 844), 405.12, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(NativeDeckBuilderLayout.deckWidth(width: 650), 320)
        XCTAssertGreaterThanOrEqual(650 - NativeDeckBuilderLayout.deckWidth(width: 650), 320)
    }
}
