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

/// Mirrored by BattlefieldRowOverflowTest.kt; keep the cases and numbers identical.
final class BattlefieldRowOverflowTests: XCTestCase {
    /// Ten 50-point slots in a 300-point lane: content is 16 + 500 + 36 = 552 wide, so it scrolls up to 252.
    private func tenSlots(offset: CGFloat, cardsPerSlot: [Int] = []) -> BattlefieldRowOverflow {
        BattlefieldRowOverflow.measure(contentOffset: offset, viewportWidth: 300, slotWidths: Array(repeating: 50, count: 10),
                                       spacing: 4, leadingInset: 8, cardsPerSlot: cardsPerSlot)
    }

    private func twoSlots(offset: CGFloat) -> BattlefieldRowOverflow {
        BattlefieldRowOverflow.measure(contentOffset: offset, viewportWidth: 100, slotWidths: [50, 50], spacing: 4)
    }

    func testRowThatFitsHidesNothing() {
        let result = BattlefieldRowOverflow.measure(contentOffset: 0, viewportWidth: 300, slotWidths: [50, 50, 50],
                                                    spacing: 4, leadingInset: 8)
        XCTAssertEqual(result, .none)
    }

    func testRestingOverflowCountsOnlyFullyHiddenTrailingCards() {
        // Slot 5 spans 278...328: clipped but partly visible. Slots 6-9 start past 300.
        XCTAssertEqual(tenSlots(offset: 0), BattlefieldRowOverflow(hiddenLeading: 0, hiddenTrailing: 4, clipsLeading: false, clipsTrailing: true))
    }

    func testMidScrollHidesCardsOnBothSides() {
        // Offset 120: slots 0-1 end left of 0, slots 8-9 start past 300.
        XCTAssertEqual(tenSlots(offset: 120), BattlefieldRowOverflow(hiddenLeading: 2, hiddenTrailing: 2, clipsLeading: true, clipsTrailing: true))
        // Offset 200: slots 0-2 end left of 0, slot 3 spans -30...20, slot 9 spans 294...344.
        XCTAssertEqual(tenSlots(offset: 200), BattlefieldRowOverflow(hiddenLeading: 3, hiddenTrailing: 0, clipsLeading: true, clipsTrailing: true))
    }

    func testFullyScrolledRowClearsTheTrailingEdge() {
        XCTAssertEqual(tenSlots(offset: 252), BattlefieldRowOverflow(hiddenLeading: 4, hiddenTrailing: 0, clipsLeading: true, clipsTrailing: false))
    }

    func testSubPointSliversUseTheTolerance() {
        XCTAssertEqual(twoSlots(offset: 49.6), BattlefieldRowOverflow(hiddenLeading: 1, hiddenTrailing: 0, clipsLeading: true, clipsTrailing: false))
        XCTAssertEqual(twoSlots(offset: 49), BattlefieldRowOverflow(hiddenLeading: 0, hiddenTrailing: 0, clipsLeading: true, clipsTrailing: false))
        XCTAssertEqual(twoSlots(offset: 0.4), BattlefieldRowOverflow(hiddenLeading: 0, hiddenTrailing: 0, clipsLeading: false, clipsTrailing: true))
    }

    func testGroupedSlotsCountEveryCardTheyShow() {
        // An attachment stack of 3 in slot 8 and a collapsed ×4 group in slot 9; missing entries count one.
        XCTAssertEqual(tenSlots(offset: 0, cardsPerSlot: [1, 1, 1, 1, 1, 1, 1, 1, 3, 4]).hiddenTrailing, 1 + 1 + 3 + 4)
        XCTAssertEqual(tenSlots(offset: 0, cardsPerSlot: [2]).hiddenTrailing, 4)
        XCTAssertEqual(tenSlots(offset: 252, cardsPerSlot: [2, 0, -1]).hiddenLeading, 2 + 0 + 0 + 1)
    }

    func testLaneAddsRowsThatShareOneOffset() {
        let rows = [Array(repeating: 1, count: 10), [1, 1, 1]]
        XCTAssertEqual(BattlefieldRowOverflow.lane(contentOffset: 0, viewportWidth: 300, cardWidth: 50, cardsPerSlotByRow: rows),
                       BattlefieldRowOverflow(hiddenLeading: 0, hiddenTrailing: 4, clipsLeading: false, clipsTrailing: true))
        // The short row starts at the same padding, so scrolling to the end hides all three of its cards.
        XCTAssertEqual(BattlefieldRowOverflow.lane(contentOffset: 252, viewportWidth: 300, cardWidth: 50, cardsPerSlotByRow: rows),
                       BattlefieldRowOverflow(hiddenLeading: 7, hiddenTrailing: 0, clipsLeading: true, clipsTrailing: false))
        XCTAssertEqual(BattlefieldRowOverflow.lane(contentOffset: 0, viewportWidth: 300, cardWidth: 50, cardsPerSlotByRow: []), .none)
        XCTAssertEqual(BattlefieldRowOverflow.rowPadding, 8)
        XCTAssertEqual(BattlefieldRowOverflow.slotSpacing, 4)
    }

    func testScrollingRightNeverUncoversLeadingCardsOrHidesTrailingOnes() {
        var previous = tenSlots(offset: 0)
        for step in 0...84 {
            let offset = CGFloat(step * 3)
            let current = tenSlots(offset: offset)
            XCTAssertGreaterThanOrEqual(current.hiddenLeading, previous.hiddenLeading)
            XCTAssertLessThanOrEqual(current.hiddenTrailing, previous.hiddenTrailing)
            XCTAssertLessThanOrEqual(current.hiddenLeading + current.hiddenTrailing, 5, "A 300-point lane always shows five 50-point slots")
            XCTAssertEqual(current.clipsLeading, offset > 8.5)
            previous = current
        }
    }

    func testInvalidGeometryHidesNothing() {
        for offset in [CGFloat.nan, .infinity, -.infinity] { XCTAssertEqual(tenSlots(offset: offset), .none) }
        for viewport in [CGFloat(0), -1, .nan, .infinity] {
            XCTAssertEqual(BattlefieldRowOverflow.measure(contentOffset: 0, viewportWidth: viewport, slotWidths: [50], spacing: 4), .none)
        }
        XCTAssertEqual(BattlefieldRowOverflow.measure(contentOffset: 0, viewportWidth: 300, slotWidths: [], spacing: 4), .none)
        // Negative or non-finite widths, spacing and inset collapse to zero; an empty slot at an edge is not hidden.
        XCTAssertEqual(BattlefieldRowOverflow.measure(contentOffset: 0, viewportWidth: 100, slotWidths: [-20, .nan, 150],
                                                      spacing: .nan, leadingInset: .nan),
                       BattlefieldRowOverflow(hiddenLeading: 0, hiddenTrailing: 0, clipsLeading: false, clipsTrailing: true))
    }
}
