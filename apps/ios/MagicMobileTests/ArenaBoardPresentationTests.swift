import XCTest
import UIKit
@testable import MagicMobile

final class ArenaBoardPresentationTests: XCTestCase {
    @MainActor
    func testCompactFooterRequiresVisibleStatsOrStatus() throws {
        for type in ["Land", "Artifact", "Enchantment", "Creature", "Planeswalker", "Battle"] {
            XCTAssertFalse(try compactCard(type: type).showsFooter, type)
        }
        XCTAssertTrue(try compactCard(type: "Land", fields: ["tapped": true]).showsFooter)
        XCTAssertTrue(try compactCard(type: "Creature", fields: ["summoningSickness": true]).showsFooter)
        XCTAssertFalse(try compactCard(type: "Artifact", fields: ["summoningSickness": true]).showsFooter)
        XCTAssertTrue(try compactCard(type: "Creature", fields: ["power": 0, "toughness": 0]).showsFooter)
        XCTAssertTrue(try compactCard(type: "Creature", fields: ["reportedPower": "*", "reportedToughness": "1+*"]).showsFooter)
        XCTAssertFalse(try compactCard(type: "Creature", fields: ["power": 2]).showsFooter)
        XCTAssertTrue(try compactCard(type: "Artifact", fields: ["isCreaturePermanent": true, "power": 2, "toughness": 2]).showsFooter)
    }

    @MainActor
    func testCompactCounterOverlaysRemainAvailableWithoutAnEmptyFooter() throws {
        for (type, counter) in [("Planeswalker", "loyalty"), ("Battle", "defense"), ("Artifact", "charge")] {
            let tile = try compactCard(type: type, fields: ["counters": [counter: 3]])
            XCTAssertFalse(tile.showsFooter)
            XCTAssertEqual(tile.card.counterBadges.map(\.count), [3])
            XCTAssertTrue(tile.card.accessibilityLabel(zoneName: "Battlefield", selected: false, legal: false)
                .contains("\(tile.card.counterBadges[0].label) counter 3"))
        }
    }

    @MainActor
    private func compactCard(type: String, fields: [String: Any] = [:]) throws -> ArenaBattlefieldCard {
        var payload = fields
        payload["instanceId"] = "footer-card"
        payload["card"] = ["name": "Footer fixture", "typeLine": type, "oracleText": ""]
        let card = try JSONDecoder().decode(ZoneCard.self, from: JSONSerialization.data(withJSONObject: payload))
        return ArenaBattlefieldCard(card: card, zoneName: "Battlefield", width: 64, height: 70)
    }

    func testHandScrubberPreservesThumbGrabAndClampsTrackTaps() {
        let width: CGFloat = 300
        let thumb = HandScrubberGeometry.thumbWidth(trackWidth: width)
        let travel = width - thumb
        XCTAssertEqual(HandScrubberGeometry.progress(location: travel * 0.4 + 9, trackWidth: width, grabOffset: 9), 0.4, accuracy: 0.0001)
        XCTAssertEqual(HandScrubberGeometry.progress(location: 0, trackWidth: width, grabOffset: thumb / 2), 0)
        XCTAssertEqual(HandScrubberGeometry.progress(location: width, trackWidth: width, grabOffset: thumb / 2), 1)
        XCTAssertEqual(HandScrubberGeometry.thumbWidth(trackWidth: 20), 20)
    }

    @MainActor
    func testHandScrubberMovesActualScrollOffsetIncludingInsetsAndShortHands() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        scroll.contentSize = CGSize(width: 1200, height: 120)
        scroll.contentInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        let controller = HandScrollController()
        controller.scrollView = scroll
        controller.scroll(to: 0)
        XCTAssertEqual(scroll.contentOffset.x, -4)
        XCTAssertEqual(controller.progress, 0)
        controller.scroll(to: 0.5)
        XCTAssertEqual(scroll.contentOffset.x, 450)
        XCTAssertEqual(controller.progress, 0.5)
        controller.scroll(to: 1)
        XCTAssertEqual(scroll.contentOffset.x, 904)
        XCTAssertEqual(controller.progress, 1)
        scroll.setContentOffset(CGPoint(x: 223, y: 0), animated: false)
        controller.refreshProgress()
        XCTAssertEqual(controller.progress, 0.25)
        scroll.contentSize.width = 100
        controller.scroll(to: 1)
        XCTAssertEqual(scroll.contentOffset.x, -4)
        XCTAssertEqual(controller.progress, 0)
    }

    func testCrowdedPermanentsUseTwoRowsOnlyWhenTouchTargetsFit() {
        let roomy = ArenaPermanentLayout(count: 10, width: 384, height: 116, maxCardWidth: 88, ratio: 1.08)
        XCTAssertEqual(roomy.rows, 2)
        XCTAssertEqual(roomy.columns, 5)
        XCTAssertGreaterThanOrEqual(roomy.cardWidth, 44)
        XCTAssertLessThanOrEqual(roomy.cardHeight * 2 + 20, 116)
        XCTAssertLessThanOrEqual(roomy.contentWidth, 384)
        let prompt = ArenaPermanentLayout(count: 10, width: 384, height: 88, maxCardWidth: 88, ratio: 1.08)
        XCTAssertEqual(prompt.rows, 1)
        XCTAssertGreaterThan(prompt.contentWidth, 384)
        XCTAssertEqual(ArenaPermanentLayout(count: 5, width: 384, height: 160, maxCardWidth: 88, ratio: 1.08).rows, 1)
    }

    func testNarrowTwoRowBoardScrollsWithoutShrinkingBelowTouchMinimum() {
        let layout = ArenaPermanentLayout(count: 10, width: 231, height: 145, maxCardWidth: 92, ratio: 1.08)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.cardWidth, 44)
        XCTAssertGreaterThan(layout.contentWidth, 231)
        for count in [6, 7, 10, 11, 40] {
            let plan = ArenaPermanentLayout(count: count, width: 354, height: 140, maxCardWidth: 92, ratio: 1.08)
            XCTAssertGreaterThanOrEqual(plan.columns * plan.rows, count)
            XCTAssertLessThan(plan.columns * (plan.rows - 1), count)
            XCTAssertGreaterThanOrEqual(plan.cardWidth, 44)
        }
    }

    func testOrdinaryPriorityDoesNotReserveADecisionBanner() {
        let normal = GameBoardPreviewFixtures.snapshot(.normalBattlefield)
        XCTAssertFalse(BoardDecisionPresentation.showsGuidance(normal))
        XCTAssertFalse(BoardDecisionPresentation.needsCenterSpace(normal))
        XCTAssertTrue(BoardDecisionPresentation.needsCenterSpace(normal, hasRejection: true))
        XCTAssertTrue(BoardDecisionPresentation.showsGuidance(GameBoardPreviewFixtures.snapshot(.manaPaymentPrompt)))
        XCTAssertTrue(BoardDecisionPresentation.showsGuidance(GameBoardPreviewFixtures.snapshot(.playerTargetPrompt)))
    }

    func testRemovingBannerReturnsHeightToBothBattlefields() {
        let size = CGSize(width: 600, height: 380)
        let ordinary = BattlefieldLayoutMetrics(size: size, centerControlsVisible: false)
        let decision = BattlefieldLayoutMetrics(size: size, centerControlsVisible: true)
        XCTAssertEqual(ordinary.centerStripRect.height, 0)
        XCTAssertGreaterThan(ordinary.opponentBattlefieldRect.height, decision.opponentBattlefieldRect.height)
        XCTAssertGreaterThan(ordinary.playerBattlefieldRect.height, decision.playerBattlefieldRect.height)
        let portrait = PortraitBattlefieldLayoutMetrics(size: CGSize(width: 390, height: 844), centerControlsVisible: false)
        let portraitDecision = PortraitBattlefieldLayoutMetrics(size: CGSize(width: 390, height: 844), centerControlsVisible: true)
        XCTAssertEqual(portrait.centerStripRect.height, 0)
        XCTAssertGreaterThan(portrait.permanentGroupHeight, portraitDecision.permanentGroupHeight)
        XCTAssertGreaterThanOrEqual(portrait.handRect.height, ArenaHandLayout.restingHeight(cardHeight: portrait.handCardHeight))
    }

    func testFiveCompactPermanentsFitAtNormalPhoneWidth() {
        for width: CGFloat in [300, 342, 382, 510] {
            let size = BattlefieldAdaptiveSizing.cardWidth(availableRowWidth: width, maxCardWidth: 92,
                heightRatio: 1, tappedSlots: Array(repeating: false, count: 5))
            XCTAssertGreaterThanOrEqual(size, 44)
            XCTAssertLessThanOrEqual(size * 5 + 16 + 16, width + 0.01)
        }
    }

    func testTuckedHandExposesTouchTargetsAndLargeHandsScroll() {
        for count in [2, 7, 15, 40] {
            let spacing = ArenaHandLayout.spacing(count: count, width: 360, cardWidth: 88, expanded: false)
            XCTAssertGreaterThanOrEqual(88 + spacing, 44)
        }
        XCTAssertEqual(ArenaHandLayout.spacing(count: 7, width: 360, cardWidth: 88, expanded: true), 8)
        XCTAssertLessThan(ArenaHandLayout.restingHeight(cardHeight: 124), 124 + 30)
    }

    func testManaPipsKeepHybridXAndPhyrexianMeaning() {
        XCTAssertEqual(HandManaCost.symbols("{X}{2}{W/U}{B/P}{C}{S}"), ["X", "2", "W/U", "B/P", "C", "S"])
        XCTAssertTrue(HandManaCost.symbols("").isEmpty)
        XCTAssertEqual(HandManaCost.symbols("{1}{R} // {1}{U}"), ["1", "R", "//", "1", "U"])
    }

    func testClippedCombatRemainsAnchoredToViewportEdge() throws {
        let lane = CGRect(x: 20, y: 30, width: 240, height: 110)
        let bounds = ["partial": CGRect(x: 0, y: 40, width: 60, height: 65),
                      "offscreen": CGRect(x: 350, y: 40, width: 60, height: 65),
                      "revoked": CGRect(x: 80, y: 40, width: 60, height: 65)]
        let result = CombatViewportAnchors.resolve(bounds: bounds, authorizedIDs: ["partial", "offscreen", "unmeasured"], viewports: [lane])
        XCTAssertEqual(result["partial"]?.isClipped, true)
        XCTAssertEqual(result["offscreen"]?.point.x, lane.maxX - 12)
        XCTAssertNil(result["revoked"])
        XCTAssertNil(result["unmeasured"])
        XCTAssertTrue(lane.contains(try XCTUnwrap(result["partial"]?.point)))
    }

    func testCombatAnchorReturnsToCardAfterScrollingBack() {
        let lane = CGRect(x: 0, y: 0, width: 360, height: 100)
        let card = CGRect(x: 80, y: 8, width: 64, height: 70)
        let result = CombatViewportAnchors.resolve(bounds: ["card": card], authorizedIDs: ["card"], viewports: [lane])
        XCTAssertEqual(result["card"], CombatViewportAnchor(point: CGPoint(x: card.midX, y: card.midY), isClipped: false))
    }

    func testSameHeightLanesKeepAnimatedLandOwnershipWhileScrolling() {
        let creatures = CGRect(x: 0, y: 0, width: 240, height: 100)
        let lands = CGRect(x: 248, y: 0, width: 100, height: 100)
        let result = CombatViewportAnchors.resolve(bounds: [
            "land": CGRect(x: 260, y: 20, width: 44, height: 48),
            "offscreenCreature": CGRect(x: 270, y: 20, width: 60, height: 60)],
            authorizedIDs: ["land", "offscreenCreature"], viewports: [creatures, lands],
            laneIndices: ["land": 1, "offscreenCreature": 0])
        XCTAssertEqual(result["land"]?.isClipped, false)
        XCTAssertEqual(result["land"]?.point.x, 282)
        XCTAssertEqual(result["offscreenCreature"]?.point.x, 228)
        XCTAssertEqual(result["offscreenCreature"]?.isClipped, true)
    }

    func testSameEdgeCombatCardsRemainIndividuallyAccessibleInCluster() {
        let point = CGPoint(x: 20, y: 55)
        let groups = CombatEdgeCluster.groups(anchors: [
            "second": CombatViewportAnchor(point: point, isClipped: true),
            "first": CombatViewportAnchor(point: point, isClipped: true),
            "visible": CombatViewportAnchor(point: point, isClipped: false)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.cardIDs, ["first", "second"])
    }
}
