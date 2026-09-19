import XCTest
import UIKit
@testable import MagicMobile

final class BattlefieldBackdropTests: XCTestCase {
    func testStableChoicesPreserveExistingPreferences() {
        XCTAssertEqual(BattlefieldBackdrop.allCases.map(\.rawValue), ["arena", "midnight", "wood", "moss", "ember", "tide"])
        XCTAssertEqual(BattlefieldBackdrop.resolved("arena"), .arena)
        XCTAssertEqual(BattlefieldBackdrop.resolved("midnight"), .midnight)
        XCTAssertEqual(BattlefieldBackdrop.resolved("wood"), .wood)
        XCTAssertEqual(BattlefieldBackdrop.resolved("unknown"), .arena)
    }

    func testGeneratedMaterialsAreBundledAndSquareForBothCrops() throws {
        for theme in BattlefieldBackdrop.allCases {
            guard let asset = theme.assetName else { continue }
            let image = try XCTUnwrap(UIImage(named: asset), "Missing battlefield material: \(asset)")
            XCTAssertEqual(image.size.width, image.size.height, "Material must support either orientation from a center crop")
            XCTAssertGreaterThanOrEqual(image.size.width * image.scale, 1024)
        }
    }
}
