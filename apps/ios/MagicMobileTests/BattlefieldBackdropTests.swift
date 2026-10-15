import XCTest
import UIKit
@testable import MagicMobile

final class BattlefieldBackdropTests: XCTestCase {
    func testOnlyTheTavernAndTheTestBoardRemain() {
        XCTAssertEqual(BattlefieldBackdrop.allCases.map(\.rawValue), ["arena", "tavern"])
        XCTAssertEqual(BattlefieldBackdrop.resolved("arena"), .arena)
        XCTAssertEqual(BattlefieldBackdrop.resolved("unknown"), .tavern, "Walnut Tavern is the default board")
        for retired in ["midnight", "wood", "moss", "ember", "tide"] {
            XCTAssertEqual(BattlefieldBackdrop.resolved(retired), .tavern, "\(retired) was retired on 2026-10-14")
        }
    }

    /// The retired textures (about 2.7 MB of Assets.car) must not come back with an asset-catalog merge.
    func testRetiredTexturesAreNotBundled() {
        for name in ["arena", "wood", "moss", "ember", "tide"] {
            XCTAssertNil(UIImage(named: "battlefield-\(name)"), "battlefield-\(name) was retired on 2026-10-14")
        }
    }

    func testComposedTablesShipBothOrientationsWithoutGenericShading() throws {
        for theme in BattlefieldBackdrop.allCases {
            guard let composed = theme.composedAssetNames else {
                XCTAssertFalse(theme.hasBakedLighting)
                continue
            }
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
