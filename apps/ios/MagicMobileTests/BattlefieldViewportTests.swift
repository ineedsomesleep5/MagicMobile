import XCTest
import SwiftUI
import UIKit
@testable import MagicMobile

@MainActor
final class BattlefieldViewportTests: XCTestCase {
    func testGeometryReadersUseTheAlreadySafeViewportInBothOrientations() async throws {
        for size in [CGSize(width: 430, height: 932), CGSize(width: 932, height: 430)] {
            let measured = expectation(description: "Safe viewport measured: \(size)")
            var result: (CGSize, EdgeInsets, CGRect, CGRect)?
            let probe = GeometryReader { proxy in
                Color.clear.onAppear {
                    result = (proxy.size, proxy.safeAreaInsets,
                              PortraitBattlefieldLayoutMetrics(proxy: proxy).safeFrame,
                              BattlefieldLayoutMetrics(proxy: proxy).safeFrame)
                    measured.fulfill()
                }
            }
            let host = UIHostingController(rootView: probe)
            // Deliberately nonzero insets expose double subtraction even on a
            // test runner without a notch. Controls never ignore safe areas.
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 30, left: 12, bottom: 20, right: 12)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.layoutIfNeeded()
            await fulfillment(of: [measured], timeout: 5)
            let (viewport, insets, portrait, landscape) = try XCTUnwrap(result)
            XCTAssertGreaterThan(insets.top, 0)
            XCTAssertGreaterThan(insets.bottom, 0)
            XCTAssertEqual(viewport.height,
                           host.view.bounds.height - host.view.safeAreaInsets.top - host.view.safeAreaInsets.bottom,
                           accuracy: 1)
            for frame in [portrait, landscape] {
                XCTAssertEqual(frame.minY, 8, accuracy: 0.01)
            }
            XCTAssertEqual(portrait.maxY, viewport.height - 8, accuracy: 0.01)
            XCTAssertEqual(landscape.maxY, viewport.height, accuracy: 0.01)
            XCTAssertEqual(portrait.minX, 8, accuracy: 0.01)
            XCTAssertEqual(portrait.maxX, viewport.width - 8, accuracy: 0.01)
            XCTAssertEqual(landscape.minX, 10, accuracy: 0.01)
            XCTAssertEqual(landscape.maxX, viewport.width - 10, accuracy: 0.01)
        }
    }

    func testFullWindowMetricsStillRespectExplicitSafeInsets() {
        let size = CGSize(width: 430, height: 932)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let portrait = PortraitBattlefieldLayoutMetrics(size: size, safeArea: insets)
        let landscape = BattlefieldLayoutMetrics(size: size, safeArea: insets)
        for frame in [portrait.safeFrame, landscape.safeFrame] {
            XCTAssertEqual(frame.minY, 67, accuracy: 0.01)
        }
        XCTAssertEqual(portrait.safeFrame.maxY, 890, accuracy: 0.01)
        XCTAssertEqual(landscape.safeFrame.maxY, 898, accuracy: 0.01)
        XCTAssertEqual(portrait.topHUDRect.minY, 67, accuracy: 0.01)
        XCTAssertEqual(portrait.bottomControlsRect.maxY, 890, accuracy: 0.01)
        XCTAssertLessThan(portrait.handRect.maxY, portrait.bottomControlsRect.minY)
    }

    func testLandscapeHandEndsAtSafeBottomWithoutLosingCardOrLaneSpace() {
        for size in [CGSize(width: 454, height: 360), CGSize(width: 544, height: 409), CGSize(width: 804, height: 744)] {
            for bottom in [CGFloat(0), 21] {
                let metrics = BattlefieldLayoutMetrics(size: size, safeArea: EdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: 0))
                XCTAssertEqual(metrics.handRect.maxY, size.height - bottom, accuracy: 0.01)
                XCTAssertTrue(metrics.safeFrame.contains(metrics.handRect))
                XCTAssertGreaterThanOrEqual(metrics.handRect.height, ArenaHandLayout.restingHeight(cardHeight: metrics.handCardHeight))
                XCTAssertLessThan(metrics.playerLandsRect.maxY, metrics.handRect.minY)
            }
        }
    }

    func testLandscapeDockGivesSingleLinePrimaryMoreWidthAndStackMoreHeight() throws {
        XCTAssertEqual(LandscapeActionDockLayout.primaryLineLimit, 1)
        for hasStack in [false, true] {
            let width = LandscapeActionDockLayout.sidebarWidth(hasStack: hasStack)
            let contentWidth = width - 2 * LandscapeActionDockLayout.horizontalPadding
            XCTAssertGreaterThanOrEqual(contentWidth, 148)
            for state in [GameBoardDesignPreviewState.normalBattlefield, .manaPaymentPrompt] {
                let snapshot = GameBoardPreviewFixtures.snapshot(state)
                let dock = GameplayActionDock(snapshot: snapshot,
                    passAction: snapshot.legalActions?.first { $0.type == "pass_priority" },
                    yieldActions: GameplayActionPresentation.yieldActions(in: snapshot.legalActions ?? []),
                    pendingActionId: nil, compact: true, landscapeSidebar: true,
                    openPromptDetails: {}, openLog: {}, openSettings: {}, runAction: { _ in })
                    .frame(width: contentWidth)
                let renderer = ImageRenderer(content: dock)
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, contentWidth, accuracy: 0.01)
                // Two accessible 44pt rows plus 4pt spacing; the old dock used
                // 96pt plus 12pt bottom padding, taking another 12pt from stack.
                XCTAssertLessThanOrEqual(image.size.height, 92.5)
                XCTAssertLessThanOrEqual(image.size.height + LandscapeActionDockLayout.bottomPadding, 96.5)
            }
        }
    }
}
