import XCTest
@testable import MagicMobile

final class HoldCardInspectionTests: XCTestCase {
    func testReleaseClearsOnlyOnceEvenWhenCancellationAlsoArrives() {
        let inspection = HoldCardInspection()
        var dismissals = 0
        inspection.begin { dismissals += 1 }
        XCTAssertTrue(inspection.isActive)
        inspection.end()
        inspection.end()
        XCTAssertFalse(inspection.isActive)
        XCTAssertEqual(dismissals, 1)
    }

    func testReplacingHoldDismissesPreviousBeforeOpeningNext() {
        let inspection = HoldCardInspection()
        var dismissed: [String] = []
        inspection.begin { dismissed.append("first") }
        inspection.begin { dismissed.append("second") }
        XCTAssertEqual(dismissed, ["first"])
        XCTAssertTrue(inspection.isActive)
        inspection.end()
        XCTAssertEqual(dismissed, ["first", "second"])
    }

    func testReleaseWithoutHoldPreservesExplicitInspection() {
        let inspection = HoldCardInspection()
        var selected = "explicit"
        inspection.end()
        XCTAssertEqual(selected, "explicit")
        inspection.begin { selected = "closed" }
        inspection.end()
        selected = "explicit-again"
        inspection.end()
        XCTAssertEqual(selected, "explicit-again")
    }
}
