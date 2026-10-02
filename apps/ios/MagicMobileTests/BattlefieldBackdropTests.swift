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
        XCTAssertEqual(BattlefieldBackdrop.resolved("unknown"), .tavern, "Walnut Tavern is the default board")
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

    func testTavernFramesFollowTheCardsCurrentType() {
        func frame(_ typeLine: String, token: Bool? = nil, creatureNow: Bool? = nil) -> TavernFrameKind {
            TavernFrameKind(ZoneCard(instanceId: "f", card: CardIdentity(name: "Card", typeLine: typeLine, oracleText: nil, isToken: token),
                                     tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil, power: nil, toughness: nil,
                                     isCreaturePermanent: creatureNow, damage: nil, isAttacking: nil, blocking: nil,
                                     attachedToInstanceId: nil))
        }
        XCTAssertEqual(frame("Creature — Elf Druid"), .creature)
        XCTAssertEqual(frame("Token Creature — Spirit"), .token)
        XCTAssertEqual(frame("Creature — Soldier", token: true), .token)
        XCTAssertEqual(frame("Artifact Creature — Golem"), .creature, "An artifact creature is framed as a creature")
        XCTAssertEqual(frame("Artifact"), .artifact)
        XCTAssertEqual(frame("Token Artifact — Treasure", token: true), .artifact)
        XCTAssertEqual(frame("Enchantment — Aura"), .enchantment)
        XCTAssertEqual(frame("Basic Land — Forest"), .land)
        XCTAssertEqual(frame("Land", creatureNow: true), .creature, "An animated land is a creature now")
        XCTAssertEqual(frame("Artifact — Vehicle", creatureNow: false), .artifact)
        XCTAssertEqual(frame("Legendary Planeswalker — Jace"), .creature)
    }
}
