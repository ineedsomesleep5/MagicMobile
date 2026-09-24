import XCTest
@testable import MagicMobile

final class OnDeviceModelTests: XCTestCase {
    // A presentation-schema test, not evidence that the native engine executed.
    func testLocalViewerIsNotRequiredToHaveTheLegacyHumanID() throws {
        let snapshot = try decodeSnapshot(viewer: "seat-b")
        XCTAssertEqual(snapshot.human?.playerId, "seat-b")
        XCTAssertEqual(snapshot.opponent?.playerId, "seat-a")
    }

    func testFocusingAnotherOpponentDoesNotChangeTheLocalViewer() throws {
        let snapshot = try decodeSnapshot(viewer: "seat-b", opponent: "seat-d")
        XCTAssertEqual(snapshot.human?.playerId, "seat-b")
        XCTAssertEqual(snapshot.opponent?.playerId, "seat-d")
    }

    func testPrivateZoneCountsDoNotRequireFabricatedCards() throws {
        let data = Data(#"{"library":[],"hand":[],"battlefield":[],"graveyard":[],"exile":[],"command":[],"stack":[],"handCount":7,"libraryCount":92}"#.utf8)
        let zones = try JSONDecoder().decode(PlayerZones.self, from: data)
        XCTAssertEqual(zones.visibleHandCount, 7)
        XCTAssertEqual(zones.visibleLibraryCount, 92)
        XCTAssertTrue(zones.hand.isEmpty)
        XCTAssertTrue(zones.library.isEmpty)
    }

    func testPlayerLabelsUseViewerAndActualOpponentName() throws {
        let snapshot = try decodeSnapshot(viewer: "seat-b")
        XCTAssertTrue(snapshot.isViewer("seat-b"))
        XCTAssertFalse(snapshot.isViewer(nil))
        XCTAssertEqual(snapshot.playerLabel("seat-b"), "You")
        XCTAssertEqual(snapshot.playerLabel("seat-c"), "seat-c")
        XCTAssertEqual(snapshot.playerLabel(nil), "Waiting")
    }

    func testUnreportedCommanderTaxAndTextStatsArePreserved() throws {
        let snapshot = try decodeSnapshot(viewer: "seat-b")
        XCTAssertEqual(snapshot.human?.hasKnownCommanderTax, false)
        let card = try JSONDecoder().decode(ZoneCard.self, from: Data(#"{"instanceId":"card","card":{"name":"Variable","typeLine":"Creature"},"reportedPower":"*","reportedToughness":"1+*"}"#.utf8))
        XCTAssertEqual(card.displayPower, "*")
        XCTAssertEqual(card.displayToughness, "1+*")
        XCTAssertTrue(card.showsPowerToughness)
        XCTAssertTrue(card.accessibilityLabel().contains("*/1+*"))
    }

    func testSignedAmountBoundsClampWithoutOverflow() {
        let bounds = PromptAmountBounds(minimum: -3, maximum: 2)
        XCTAssertEqual(bounds.clamp(-100), -3)
        XCTAssertEqual(bounds.clamp(100), 2)
        XCTAssertEqual(bounds.stepping(-3, by: -1), -3)
        XCTAssertEqual(bounds.stepping(2, by: 1), 2)
        XCTAssertEqual(bounds.stepping(-1, by: -1), -2)
    }

    private func decodeSnapshot(viewer: String, opponent: String? = nil) throws -> GameSnapshot {
        let zones: [String: Any] = ["library": [], "hand": [], "battlefield": [],
                                   "graveyard": [], "exile": [], "command": [], "stack": []]
        let players: [[String: Any]] = ["seat-a", "seat-b", "seat-c", "seat-d"].map {
            ["playerId": $0, "displayName": $0, "life": 40, "poison": 0,
             "commanderTax": 0, "commanderTaxKnown": false, "zones": zones]
        }
        var json: [String: Any] = ["id": "match", "phase": "PRECOMBAT_MAIN", "turn": 1,
                                  "viewerPlayerId": viewer, "players": players, "log": []]
        if let opponent { json["selectedOpponentId"] = opponent }
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

extension OnDeviceModelTests {
    func testKeywordIconsFillInFromCurrentRulesLinesOnly() {
        let icons = XmageCardIcon.keywordIcons(rules: "Flying\nAt the beginning of your upkeep, draw a card unless target opponent sacrifices a creature or pays 3 life.")
        XCTAssertEqual(icons.map(\.iconType), ["ABILITY_FLYING"])
        XCTAssertEqual(XmageCardIcon.keywordIcons(rules: "Vigilance, trample (This creature can deal excess combat damage.)\nReach").map(\.iconType),
                       ["ABILITY_VIGILANCE", "ABILITY_TRAMPLE", "ABILITY_REACH"])
        XCTAssertEqual(XmageCardIcon.keywordIcons(rules: "Creatures you control have flying.\nForestwalk\nMenace"), [],
                       "mentions, unmapped keywords and engine-only menace are ignored")
        XCTAssertEqual(XmageCardIcon.keywordIcons(rules: nil), [])

        var identity = CardIdentity(name: "Indulgent Tormentor", typeLine: "Creature — Demon", oracleText: "Flying")
        identity.manaCost = "{3}{B}{B}"
        let engineFlying = XmageCardIcon(iconType: "ABILITY_FLYING", resourceName: nil, category: "ABILITY", text: nil, hint: "Flying")
        for engine in [[], [engineFlying]] {
            let card = ZoneCard(instanceId: "t", card: identity, tapped: false, summoningSickness: true, cardIcons: engine,
                                counters: nil, power: 5, toughness: 3, isCreaturePermanent: true, damage: nil,
                                isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
            XCTAssertEqual(card.visibleXmageIcons.map(\.iconType), ["ABILITY_FLYING"], "exactly one flying icon either way")
        }
    }
}
