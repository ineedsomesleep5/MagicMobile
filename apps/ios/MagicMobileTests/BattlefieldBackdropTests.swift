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

    func testTableThemesFallBackToWalnutAndWalnutStaysAsItWas() {
        XCTAssertEqual(ArenaTableTheme.defaultValue, ArenaTableDraw.random)
        XCTAssertTrue(ArenaTableTheme.utopia.isBright)
        XCTAssertFalse(ArenaTableTheme.walnut.isBright)
        XCTAssertNil(ArenaTableTheme.walnut.cardShadow)
        XCTAssertTrue(ArenaTableTheme.walnut.hasTableLamp)
        XCTAssertEqual(ArenaTableTheme.walnut.plate(landscape: true), "tavern-arena-landscape")
        XCTAssertEqual(ArenaTableTheme.walnut.plate(landscape: false), "tavern-arena-portrait")
    }

    func testEachGameDrawsItsOwnTableAndKeepsIt() {
        let draw = { (match: String) in ArenaTableDraw.table(match: match, pinned: ArenaTableDraw.random, pinnedMatch: "") }
        XCTAssertEqual(draw("match-a"), draw("match-a"), "A resumed game keeps its table")
        var drawn: [ArenaTableTheme: Int] = [:]
        for index in 0..<5000 { drawn[draw("\(UUID())-\(index)"), default: 0] += 1 }
        XCTAssertEqual(drawn.count, ArenaTableTheme.allCases.count)
        for (table, count) in drawn { XCTAssertGreaterThan(count, 800, "\(table) came up too rarely") }
    }

    func testAPickedTableStaysWithItsOwnMatch() {
        let pinned = { (match: String?) in ArenaTableDraw.table(match: match, pinned: "volcano", pinnedMatch: "chosen") }
        XCTAssertEqual(pinned("chosen"), .volcano)
        let others = Set((0..<200).map { pinned("ranked-\($0)") })
        XCTAssertGreaterThan(others.count, 1, "The next game draws again")
        XCTAssertEqual(ArenaTableDraw.table(match: "any", pinned: "volcano", pinnedMatch: ""), .volcano, "Fixtures pin every game")
        XCTAssertEqual(ArenaTableDraw.table(match: nil, pinned: ArenaTableDraw.random, pinnedMatch: ""), .walnut)
    }

    func testEveryTableThemeShipsBothPlates() throws {
        for theme in ArenaTableTheme.allCases {
            let wide = try XCTUnwrap(UIImage(named: theme.plate(landscape: true)), "\(theme) has no landscape plate")
            let tall = try XCTUnwrap(UIImage(named: theme.plate(landscape: false)), "\(theme) has no portrait plate")
            XCTAssertGreaterThan(wide.size.width, wide.size.height)
            XCTAssertGreaterThan(tall.size.height, tall.size.width)
        }
    }

    /// Each world's motion is built from its plate (scripts/brand/arena_world_motion.py): the data and both maps must ship.
    func testEveryWorldShipsItsMotion() throws {
        for theme in ArenaTableTheme.allCases where theme != .walnut {
            let spec = try XCTUnwrap(ArenaWorldSpec.all[theme.rawValue], "\(theme) has no motion")
            for (variant, scene) in [("landscape", spec.landscape), ("portrait", spec.portrait)] {
                XCTAssertFalse(scene.lights.isEmpty && scene.flows.isEmpty, "\(theme) \(variant) doesn't move")
                XCTAssertNotNil(UIImage(named: "arena-world-\(theme.rawValue)-\(variant)-mask"))
                XCTAssertNotNil(UIImage(named: "arena-world-\(theme.rawValue)-\(variant)-glow"))
                for flow in scene.flows {
                    XCTAssertEqual(flow.rect.count, 4)
                    XCTAssertEqual(flow.dir.count, 2)
                }
            }
        }
        XCTAssertNil(ArenaWorldSpec.all[ArenaTableTheme.walnut.rawValue], "Walnut doesn't move")
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
