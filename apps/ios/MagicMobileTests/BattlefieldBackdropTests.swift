import XCTest
import UIKit
@testable import MagicMobile

final class BattlefieldBackdropTests: XCTestCase {
    func testStableChoicesPreserveExistingPreferences() {
        XCTAssertEqual(BattlefieldBackdrop.allCases.map(\.rawValue),
                       ["arena", "midnight", "wood", "moss", "ember", "tide", "tavern"])
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

    func testComposedTablesShipBothOrientationsWithoutGenericShading() throws {
        for theme in BattlefieldBackdrop.allCases {
            guard let composed = theme.composedAssetNames else {
                XCTAssertFalse(theme.hasBakedLighting)
                continue
            }
            XCTAssertNil(theme.assetName, "A composed table must not fall back to a square crop")
            XCTAssertTrue(theme.hasBakedLighting)
            let portrait = try XCTUnwrap(UIImage(named: composed.portrait), "Missing \(composed.portrait)")
            let landscape = try XCTUnwrap(UIImage(named: composed.landscape), "Missing \(composed.landscape)")
            XCTAssertGreaterThan(portrait.size.height, portrait.size.width)
            XCTAssertGreaterThan(landscape.size.width, landscape.size.height)
            XCTAssertGreaterThanOrEqual(portrait.size.height * portrait.scale, 2048)
        }
    }
}
