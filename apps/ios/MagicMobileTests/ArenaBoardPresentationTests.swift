import XCTest
import UIKit
@testable import MagicMobile

final class ArenaBoardPresentationTests: XCTestCase {
    func testPlayerEnchantmentsRemainLiveAndNeverDuplicateInPermanentLanes() throws {
        let chain = try [attachmentCard("curse", parent: "player"), attachmentCard("nested-curse", parent: "curse"), attachmentCard("orphan", parent: "missing")]
        XCTAssertEqual(ZoneCard.enchanting(playerID: "player", cards: chain).map(\.id), ["curse", "nested-curse"])
        XCTAssertTrue(ZoneCard.enchanting(playerID: "other", cards: chain).isEmpty)
        XCTAssertTrue(ZoneCard.enchanting(playerID: "player", cards: Array(chain.dropFirst())).isEmpty)
        let snapshot = GameBoardPreviewFixtures.snapshot(.attachedPermanents)
        let all = snapshot.players.flatMap { $0.zones.battlefield }
        let reference = BoardZoneReference.playerEnchantments(playerID: "ai-1")
        XCTAssertEqual(reference.cards(in: snapshot).map(\.instanceId), ["player-curse"])
        XCTAssertTrue(reference.cards(in: GameBoardPreviewFixtures.snapshot(.normalBattlefield)).isEmpty)
        XCTAssertTrue(BoardZoneReference.playerEnchantments(playerID: "absent").cards(in: snapshot).isEmpty)
        for player in snapshot.players {
            let lane = BattlefieldAttachments.lane(ownedCards: player.zones.battlefield, allCards: all, lands: false, playerIDs: Set(snapshot.players.map(\.playerId)))
            XCTAssertFalse(lane.contains { $0.instanceId == "player-curse" })
        }
        XCTAssertEqual(BoardPlayerStatus.counters(try XCTUnwrap(snapshot.human)).map(\.name), ["Poison", "Energy"])
        let phased = try XCTUnwrap(all.first { $0.instanceId == "human-sol-ring" })
        XCTAssertTrue(phased.isPhasedOut)
        let updated = GameBoardPreviewFixtures.snapshot(.attachedPermanents, specialStateAdvanced: true)
        XCTAssertFalse(try XCTUnwrap(updated.human?.zones.battlefield.first { $0.instanceId == "human-sol-ring" }).isPhasedOut)
        XCTAssertEqual(BoardPlayerStatus.counters(try XCTUnwrap(updated.human)).first?.count, 5)
        XCTAssertTrue(reference.cards(in: updated).isEmpty, "Open player-enchantment inspector drops moved cards")
        XCTAssertEqual(BoardZoneReference.playerEnchantments(playerID: "human").cards(in: updated).map(\.id), ["player-curse"])
        XCTAssertFalse(try attachmentCard("regular").isPhasedOut, "Unknown phasing must not disable a normal card")
    }

    func testAttachmentsFollowExactHostIncludingCrossControllerAndLands() throws {
        let host = try attachmentCard("host", type: "Creature")
        let land = try attachmentCard("land", type: "Land")
        let aura = try attachmentCard("aura", parent: "host")
        let equipment = try attachmentCard("equipment", parent: "host")
        let landAura = try attachmentCard("land-aura", parent: "land")
        let all = [aura, landAura, host, equipment, land]
        let lane = BattlefieldAttachments.lane(ownedCards: [host, equipment, land], allCards: all, lands: false)
        XCTAssertEqual(Set(lane.map(\.instanceId)), ["host", "aura", "equipment"])
        let group = try XCTUnwrap(BattlefieldAttachments.groups(lane).first)
        XCTAssertEqual(group.representative.instanceId, "host")
        XCTAssertEqual(Set(group.cards.map(\.instanceId)), ["host", "aura", "equipment"])
        XCTAssertTrue(BattlefieldAttachments.lane(ownedCards: [aura, landAura], allCards: all, lands: false).isEmpty)
        XCTAssertEqual(Set(BattlefieldAttachments.lane(ownedCards: [land], allCards: all, lands: true).map(\.instanceId)), ["land", "land-aura"])
        XCTAssertEqual(CombatViewportAnchors.laneIndices(human: [aura, landAura], opponent: [host, equipment, land])["aura"], 0)
        XCTAssertEqual(CombatViewportAnchors.laneIndices(human: [aura, landAura], opponent: [host, equipment, land])["land-aura"], 1)
    }

    func testOrphansCyclesAndSameNameHostsNeverDisappearOrMerge() throws {
        let cards = try [attachmentCard("host", type: "Creature"), attachmentCard("twin", type: "Creature"),
                         attachmentCard("aura", parent: "host"), attachmentCard("nested", parent: "aura"),
                         attachmentCard("orphan", parent: "gone"), attachmentCard("cycle1", parent: "cycle2"),
                         attachmentCard("cycle2", parent: "cycle1"), attachmentCard("self", parent: "self")]
        let groups = BattlefieldAttachments.groups(cards)
        XCTAssertEqual(groups.flatMap(\.cards).count, cards.count)
        XCTAssertEqual(Set(groups.flatMap(\.cards).map(\.instanceId)), Set(cards.map(\.instanceId)))
        XCTAssertEqual(groups.first(where: { $0.representative.instanceId == "host" })?.cards.count, 3)
        XCTAssertEqual(groups.first(where: { $0.cards.contains(where: { $0.instanceId == "twin" }) })?.cards.count, 1)
        for id in ["orphan", "cycle1", "cycle2", "self"] {
            XCTAssertEqual(BattlefieldAttachments.roots(cards)[id], id)
        }
    }

    func testResponseCueRequiresCurrentLocalPriorityPrompt() throws {
        let response = GameBoardPreviewFixtures.snapshot(.stackResponsePrompt, step: "UPKEEP")
        let cue = try XCTUnwrap(BoardResponseCue.make(response))
        XCTAssertEqual(cue.title, "Respond to the stack")
        XCTAssertEqual(cue.detail, "Upkeep")
        XCTAssertNil(BoardResponseCue.make(GameBoardPreviewFixtures.snapshot(.manaPaymentPrompt)))
        XCTAssertNil(BoardResponseCue.make(GameBoardPreviewFixtures.snapshot(.cardTargetPrompt)))
        XCTAssertNil(BoardResponseCue.make(GameBoardPreviewFixtures.snapshot(.aiThinking)))
    }

    func testResponseCueDistinguishesOrdinaryOwnMainFromActualResponseWindows() throws {
        for step in ["PRECOMBAT_MAIN", "POSTCOMBAT_MAIN", "precombat-main", "postcombat-main", "Main1", "MAIN2", "Main 1", "Main 2"] {
            XCTAssertNil(BoardResponseCue.make(try responseSnapshot(step: step)), step)
            XCTAssertEqual(BoardResponseCue.make(try responseSnapshot(step: step, active: "opponent"))?.title, "Your response window", step)
        }
        XCTAssertNil(BoardResponseCue.make(try responseSnapshot(step: nil, phase: "PRECOMBAT_MAIN")))
        for step in ["UPKEEP", "END_TURN", "BEGIN_COMBAT", "DECLARE_ATTACKERS", "DECLARE_BLOCKERS", "COMBAT_DAMAGE"] {
            let cue = try XCTUnwrap(BoardResponseCue.make(try responseSnapshot(step: step)))
            XCTAssertEqual(cue.title, "Your response window")
            XCTAssertEqual(cue.detail, EngineDisplayText.phaseLabel(step))
        }
        XCTAssertEqual(BoardResponseCue.make(GameBoardPreviewFixtures.snapshot(.stackResponsePrompt))?.title, "Respond to the stack")
        XCTAssertNil(BoardResponseCue.make(try responseSnapshot(step: "UPKEEP", priority: "opponent")))
        XCTAssertNil(BoardResponseCue.make(try responseSnapshot(step: "UPKEEP", promptOwner: "opponent")))
        XCTAssertNil(BoardResponseCue.make(try responseSnapshot(step: "UPKEEP", completed: true)))
        XCTAssertNil(BoardResponseCue.make(try responseSnapshot(step: "UPKEEP", hasPrompt: false)), "Submitted native prompts are removed by the adapter")
    }

    private func responseSnapshot(step: String?, phase: String = "BEGINNING", active: String = "human", priority: String = "human", promptOwner: String = "human", completed: Bool = false, hasPrompt: Bool = true) throws -> GameSnapshot {
        var payload: [String: Any] = ["id": "response-test", "phase": phase, "turn": 2, "players": [], "log": [],
                                      "activePlayerId": active, "priorityPlayerId": priority,
                                      "gameStatus": completed ? "completed" : "in_progress"]
        if let step { payload["step"] = step }
        if hasPrompt {
            payload["promptEnvelopeV2"] = ["id": "priority", "method": "GAME_PRIORITY", "messageId": 1,
                "playerId": promptOwner, "responseKind": "priority", "message": "Your priority",
                "required": false, "minChoices": 0, "maxChoices": 0,
                "responseCommand": ["type": "pass_priority", "promptId": "priority", "messageId": 1]]
        }
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func attachmentCard(_ id: String, type: String = "Enchantment", parent: String? = nil) throws -> ZoneCard {
        var payload: [String: Any] = ["instanceId": id, "card": ["name": "Same printed name", "typeLine": type]]
        if let parent { payload["attachedToInstanceId"] = parent }
        return try JSONDecoder().decode(ZoneCard.self, from: JSONSerialization.data(withJSONObject: payload))
    }

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
