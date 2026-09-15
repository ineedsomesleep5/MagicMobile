import XCTest
import SwiftUI
@testable import MagicMobile

final class PortraitPolishTests: XCTestCase {
    func testCombatGroupsKeepIndividualCardsForMeasuredArrows() throws {
        func group(_ extra: String) throws -> BattlefieldCardGroup {
            let cards = try JSONDecoder().decode([ZoneCard].self, from: Data("""
            [{"instanceId":"one","card":{"name":"Soldier","typeLine":"Creature"}\(extra)},
             {"instanceId":"two","card":{"name":"Soldier","typeLine":"Creature"}\(extra)}]
            """.utf8))
            let groups = BattlefieldDensityPlanner.groups(cards: cards)
            XCTAssertEqual(groups.count, 1)
            return try XCTUnwrap(groups.first)
        }
        let ordinary = try group("")
        XCTAssertFalse(BattlefieldRow.requiresIndividualCombatCards(ordinary, highlightedIDs: []))
        XCTAssertTrue(BattlefieldRow.requiresIndividualCombatCards(ordinary, highlightedIDs: ["two"]))
        XCTAssertTrue(BattlefieldRow.requiresIndividualCombatCards(try group(",\"isAttacking\":true"), highlightedIDs: []))
        XCTAssertTrue(BattlefieldRow.requiresIndividualCombatCards(try group(",\"blocking\":[\"attacker\"]"), highlightedIDs: []))
    }

    func testCompactPortraitPreservesFullHandAndSeparateLanes() {
        for large in [false, true] {
            for payment in [false, true] {
                var metrics = PortraitBattlefieldLayoutMetrics(size: CGSize(width: 375, height: 667),
                    safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0), paymentActive: payment)
                metrics.largeText = large
                XCTAssertTrue(metrics.usesCompactLanes)
                XCTAssertGreaterThanOrEqual(metrics.handRect.height, ArenaHandLayout.restingHeight(cardHeight: metrics.handCardHeight))
                XCTAssertTrue(metrics.safeFrame.contains(metrics.handRect))
                XCTAssertFalse(metrics.playerBattlefieldRect.intersects(metrics.playerLandsRect))
                XCTAssertLessThan(metrics.playerLandsRect.maxY, metrics.handRect.minY)
            }
        }
    }

    func testStackTargetsUseOnlyAuthorizedNames() {
        let snapshot = GameBoardPreviewFixtures.snapshot(.stackResponsePrompt)
        XCTAssertEqual(StackTargetPresentation.labels(for: ["human", "ai-creature-1", "missing", "library-ai-1"], in: snapshot),
                       ["You", "Serra Angel", "Unavailable target", "Hidden card"])
    }

    func testNativeArtworkNeverLooksUpRedactedCardNames() {
        for name in ["", "Hidden card", "Face-down card", "Face down card", "Face-down", "Face down",
                     "Card details unavailable", "  HIDDEN CARD\n", " FACE-DOWN CARD "] {
            XCTAssertFalse(NativeCardArtworkPolicy.permitsLookup(name: name), name)
        }
    }

    func testNativeArtworkAllowsOnlyLiteralVisibleNamesPastRedactionGate() {
        for name in ["Sol Ring", "Fire // Ice", "Éowyn, Shieldmaiden", "file:///not-a-local-artwork-input"] {
            XCTAssertTrue(NativeCardArtworkPolicy.permitsLookup(name: name), name)
        }
        // Passing the redaction gate is not consent: NativeDeckArtwork's offline tests
        // separately require a cache miss to return nil without a request.
    }

    func testFaceDownIconBlocksArtworkEvenWithAuthorizedNonSentinelName() throws {
        let json = """
        {"instanceId":"authorized-card","card":{"name":"Sol Ring","typeLine":"Artifact"},
         "cardIcons":[{"iconType":"OTHER_FACEDOWN"}]}
        """
        let card = try JSONDecoder().decode(ZoneCard.self, from: Data(json.utf8))
        XCTAssertTrue(NativeCardArtworkPolicy.permitsLookup(name: card.card.name))
        XCTAssertFalse(NativeCardArtworkPolicy.permitsLookup(card: card))
    }

    func testMeasuredCombatAnchorsFollowTappedWidthsAndScrolling() {
        let viewport = CGRect(x: 20, y: 30, width: 240, height: 110)
        let tapped = CGRect(x: 30, y: 40, width: 88, height: 88)
        let untapped = CGRect(x: 122, y: 40, width: 63, height: 88)
        let ids: Set<String> = ["tapped", "untapped"]
        let before = VisibleCombatAnchors.resolve(bounds: ["tapped": tapped, "untapped": untapped],
                                                  authorizedIDs: ids, viewports: [viewport])
        XCTAssertEqual(before["tapped"], CGPoint(x: tapped.midX, y: tapped.midY))
        XCTAssertEqual(before["untapped"], CGPoint(x: untapped.midX, y: untapped.midY))
        let after = VisibleCombatAnchors.resolve(
            bounds: ["tapped": tapped.offsetBy(dx: -40, dy: 0), "untapped": untapped.offsetBy(dx: -40, dy: 0)],
            authorizedIDs: ids, viewports: [viewport])
        XCTAssertNil(after["tapped"], "Partially clipped cards must not receive a guessed endpoint")
        XCTAssertEqual(after["untapped"], CGPoint(x: untapped.midX - 40, y: untapped.midY))
    }

    func testMeasuredCombatAnchorsExcludeRevokedAndUnmeasuredCards() {
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 100)
        let bounds = ["revoked": CGRect(x: 10, y: 5, width: 63, height: 88),
                      "offscreen": CGRect(x: 310, y: 5, width: 63, height: 88),
                      "empty": CGRect.zero]
        let result = VisibleCombatAnchors.resolve(bounds: bounds,
            authorizedIDs: ["offscreen", "empty", "unmeasured"], viewports: [viewport])
        XCTAssertTrue(result.isEmpty)
    }

    func testLandscapeRenderedCardsFitSeparateLanesAndHand() {
        // Center-column sizes after the HUD and action sidebar take their space.
        for size in [CGSize(width: 454, height: 360), CGSize(width: 486, height: 381), CGSize(width: 544, height: 409)] {
            let metrics = BattlefieldLayoutMetrics(size: size)
            XCTAssertFalse(metrics.opponentBattlefieldRect.intersects(metrics.opponentLandsRect))
            XCTAssertFalse(metrics.playerBattlefieldRect.intersects(metrics.playerLandsRect))
            XCTAssertLessThan(metrics.opponentBattlefieldRect.maxY, metrics.centerStripRect.minY)
            XCTAssertLessThan(metrics.centerStripRect.maxY, metrics.playerBattlefieldRect.minY)
            XCTAssertLessThan(metrics.playerBattlefieldRect.maxY, metrics.handRect.minY)
            XCTAssertLessThanOrEqual(metrics.permanentCardHeight + 12, metrics.playerBattlefieldRect.height)
            XCTAssertLessThanOrEqual(metrics.landCardHeight + 12, metrics.playerLandsRect.height)
            XCTAssertGreaterThanOrEqual(metrics.handRect.height, ArenaHandLayout.restingHeight(cardHeight: metrics.handCardHeight))
            XCTAssertTrue(metrics.safeFrame.contains(metrics.handRect))
        }
    }

    private var layouts: [PortraitBattlefieldLayoutMetrics] {
        [CGSize(width: 390, height: 844), CGSize(width: 402, height: 874), CGSize(width: 430, height: 932)].flatMap { size in
            [EdgeInsets(), EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)].map {
                PortraitBattlefieldLayoutMetrics(size: size, safeArea: $0)
            }
        }
    }

    func testEveryDevelopmentFixtureDecodesAndRetainsExplicitIdentity() {
        for state in GameBoardDesignPreviewState.allCases {
            let snapshot = GameBoardPreviewFixtures.snapshot(state)
            XCTAssertEqual(snapshot.id, "design-preview-\(state.rawValue)")
            XCTAssertEqual(snapshot.source, "design-preview", state.rawValue)
            XCTAssertEqual(snapshot.viewerID, "human", state.rawValue)
        }
    }

    func testHandAndBottomControlsDoNotOverlapOnSupportedPortraitSizes() {
        for metrics in layouts {
            let context = "\(metrics.size), top inset \(metrics.safeArea.top)"
            XCTAssertGreaterThan(metrics.handRect.height, 0, context)
            XCTAssertLessThanOrEqual(metrics.handRect.maxY, metrics.bottomControlsRect.minY, context)
            XCTAssertGreaterThanOrEqual(metrics.handRect.minY, metrics.playerLandsRect.maxY, context)
            XCTAssertLessThanOrEqual(metrics.bottomControlsRect.maxY, metrics.size.height - metrics.safeArea.bottom, context)
        }
    }

    func testHandBudgetFitsActualCardLiftAndScrollScrubber() {
        for metrics in layouts {
            // Resting hand is tucked; expansion grows upward without moving controls.
            XCTAssertGreaterThanOrEqual(metrics.handRect.height, ArenaHandLayout.restingHeight(cardHeight: metrics.handCardHeight),
                                        "\(metrics.size), top inset \(metrics.safeArea.top)")
        }
    }

    func testPaymentControlsHaveTheirOwnHeightWithoutCoveringCards() {
        let metrics = PortraitBattlefieldLayoutMetrics(size: CGSize(width: 390, height: 844), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), paymentActive: true)
        XCTAssertGreaterThanOrEqual(metrics.centerStripRect.height, 56)
        XCTAssertLessThan(metrics.centerStripRect.maxY, metrics.playerBattlefieldRect.minY)
        XCTAssertGreaterThanOrEqual(metrics.handRect.height, ArenaHandLayout.restingHeight(cardHeight: metrics.handCardHeight))
    }

    func testPrintedHandAndCompactBattlefieldHaveDistinctAspectRatios() {
        for metrics in layouts {
            XCTAssertEqual(metrics.handCardHeight / metrics.handCardWidth, 88.0 / 63.0, accuracy: 0.0001)
            for (width, height) in [(metrics.permanentCardWidth, metrics.permanentCardHeight),
                                    (metrics.landCardWidth, metrics.landCardHeight)] {
                XCTAssertGreaterThan(width, 0)
                XCTAssertEqual(height / width, 1.08, accuracy: 0.0001)
            }
        }
    }

    func testFourPlayerFixtureKeepsDistinctSeatsAndCardsWhenFocusChanges() throws {
        let snapshot = GameBoardPreviewFixtures.snapshot(.fourPlayerFocus)
        XCTAssertEqual(snapshot.players.count, 4)
        XCTAssertEqual(Set(snapshot.players.map(\.playerId)).count, 4)
        let ids = snapshot.players.flatMap { player in
            let zones = player.zones
            return [zones.library, zones.hand, zones.battlefield, zones.graveyard, zones.exile, zones.command, zones.stack]
                .flatMap { $0.map(\.instanceId) }
        }
        XCTAssertEqual(ids.count, Set(ids).count)
        for opponent in snapshot.players where !snapshot.isViewer(opponent.playerId) {
            let focused = BoardOpponentFocus.snapshot(snapshot, selecting: opponent.playerId)
            XCTAssertEqual(focused.viewerID, snapshot.viewerID)
            XCTAssertEqual(focused.opponent?.playerId, opponent.playerId)
            XCTAssertEqual(focused.players.map(\.playerId), snapshot.players.map(\.playerId))
        }
    }

    func testStackAbilityKeepsActionAndSourceIdentityDistinct() throws {
        let snapshot = GameBoardPreviewFixtures.snapshot(.stackResponsePrompt)
        let ability = try XCTUnwrap(snapshot.xmage?.stack.first { $0.objectType == "ACTIVATED_ABILITY" })
        let source = try XCTUnwrap(ability.sourceCard)
        XCTAssertNotEqual(ability.id, source.instanceId)
        XCTAssertEqual(ability.sourceInstanceId, source.instanceId)
        XCTAssertTrue(snapshot.players.flatMap { $0.zones.battlefield }.contains { $0.instanceId == source.instanceId })
        XCTAssertGreaterThanOrEqual(snapshot.xmage?.stack.count ?? 0, 2)
    }

    func testRemainingPaymentDoesNotTreatGeneratedManaAsPaid() throws {
        let snapshot = GameBoardPreviewFixtures.snapshot(.manaPaymentPrompt)
        let remaining = try XCTUnwrap(snapshot.manaPayment?.remaining)
        XCTAssertEqual(remaining.total, 3)
        XCTAssertEqual(remaining.generic, 2)
        XCTAssertEqual(remaining.W, 1)
        let solRing = try XCTUnwrap(snapshot.legalActions?.first { $0.sourceInstanceId == "human-sol-ring" })
        XCTAssertEqual(solRing.type, "make_mana")
        XCTAssertEqual(solRing.producedMana, ["C", "C"])
        XCTAssertTrue(snapshot.human?.zones.battlefield.contains { $0.instanceId == solRing.sourceInstanceId } == true)
    }
}
