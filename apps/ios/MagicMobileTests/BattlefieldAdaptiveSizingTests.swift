import XCTest
@testable import MagicMobile

final class BattlefieldAdaptiveSizingTests: XCTestCase {
    private func width(_ available: CGFloat, count: Int, maximum: CGFloat = 76) -> CGFloat {
        BattlefieldAdaptiveSizing.cardWidth(availableRowWidth: available, maxCardWidth: maximum,
                                             heightRatio: 1.4, tappedSlots: Array(repeating: false, count: count))
    }

    func testSparseAndEmptyRowsKeepMaximum() {
        XCTAssertEqual(width(800, count: 3), 76)
        XCTAssertEqual(width(0, count: 0), 76)
    }

    func testTenCardsShrinkToExactlyFitIncludingGapsAndPadding() {
        let result = width(600, count: 10)
        XCTAssertEqual(result, 54.8, accuracy: 0.000001)
        XCTAssertEqual(result * 10 + 9 * 4 + 16, 600, accuracy: 0.000001)
    }

    func testFloorAllowsOverflowAndNeverExceedsSmallMaximum() {
        let result = width(300, count: 10)
        XCTAssertEqual(result, 44)
        XCTAssertGreaterThan(result * 10 + 9 * 4 + 16, 300)
        XCTAssertEqual(width(0, count: 10, maximum: 32), 32)
    }

    func testTappedSlotUsesRotatedHeightAsHorizontalFootprint() {
        let result = BattlefieldAdaptiveSizing.cardWidth(availableRowWidth: 204, maxCardWidth: 100,
                                                          heightRatio: 1.5, tappedSlots: [false, true, false])
        XCTAssertEqual(result, 180 / 3.5, accuracy: 0.000001)
        XCTAssertEqual(result * 3.5 + 8 + 16, 204, accuracy: 0.000001)
        XCTAssertLessThan(result, width(204, count: 3, maximum: 100))
    }

    func testCollapsedGroupCountsOnlyItsRenderedSlot() {
        let collapsed = width(300, count: 2)
        let expanded = width(300, count: 6)
        XCTAssertEqual(collapsed, 76)
        XCTAssertEqual(expanded, 44)
        XCTAssertLessThan(expanded, collapsed)
    }

    func testAddingCardsAndReducingSpaceNeverEnlargesCards() {
        var previous: CGFloat = 76
        for count in 1...30 {
            let current = width(600, count: count)
            XCTAssertLessThanOrEqual(current, previous)
            XCTAssertGreaterThanOrEqual(current, 44)
            previous = current
        }
        previous = 76
        for available in stride(from: 1000, through: 0, by: -10) {
            let current = width(CGFloat(available), count: 10)
            XCTAssertLessThanOrEqual(current, previous)
            previous = current
        }
    }

    func testInvalidDimensionsStayFiniteAndConservative() {
        for available in [CGFloat(-1), .nan, .infinity, -.infinity] {
            XCTAssertEqual(width(available, count: 2), 44)
        }
        for maximum in [CGFloat(0), -1, .nan, .infinity, -.infinity] {
            XCTAssertEqual(width(600, count: 2, maximum: maximum), 0)
        }
        for ratio in [CGFloat(0), -1, .nan, .infinity, -.infinity] {
            XCTAssertEqual(BattlefieldAdaptiveSizing.cardWidth(availableRowWidth: 120, maxCardWidth: 76,
                                                               heightRatio: ratio, tappedSlots: [true, false]), 50)
        }
    }

    func testAllTappedAndSubunitRatioUseActualExtent() {
        XCTAssertEqual(BattlefieldAdaptiveSizing.cardWidth(availableRowWidth: 220, maxCardWidth: 100,
                                                           heightRatio: 2, tappedSlots: [true, true]), 50)
        XCTAssertEqual(BattlefieldAdaptiveSizing.cardWidth(availableRowWidth: 120, maxCardWidth: 100,
                                                           heightRatio: 0.5, tappedSlots: [true, true]), 100)
    }
}
