import SwiftUI

struct BattlefieldLayoutMetrics {
    static let magicCardHeightToWidth: CGFloat = 88.0 / 63.0

    let size: CGSize
    let safeArea: EdgeInsets
    var centerControlsVisible = true

    init(proxy: GeometryProxy, centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        size = proxy.size
        // The center column already lives inside SwiftUI's safe-area proposal.
        // Its local bounds must not lose the window insets a second time.
        safeArea = EdgeInsets()
    }

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets(), centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        self.size = size
        self.safeArea = safeArea
    }

    var safeFrame: CGRect {
        let margin: CGFloat = 10
        let x = safeArea.leading + margin
        let y = safeArea.top + 8
        let width = max(size.width - safeArea.leading - safeArea.trailing - margin * 2, 320)
        // The hand finishes at the safe bottom edge; retain only the top gutter.
        let height = max(size.height - safeArea.top - safeArea.bottom - 8, 300)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var topStatusRect: CGRect {
        CGRect(x: safeFrame.minX, y: safeFrame.minY, width: safeFrame.width, height: 40)
    }

    var rightDockRect: CGRect {
        let width = min(max(safeFrame.width * 0.20, 210), 268)
        let top = topStatusRect.maxY + 8
        return CGRect(x: safeFrame.maxX - width, y: top, width: width, height: max(safeFrame.maxY - top, 220))
    }

    var boardColumnRect: CGRect {
        let top = safeFrame.minY
        return CGRect(
            x: safeFrame.minX,
            y: top,
            width: max(safeFrame.maxX - safeFrame.minX, 320),
            height: max(safeFrame.maxY - top, 260)
        )
    }

    var handRect: CGRect {
        CGRect(
            x: boardColumnRect.minX,
            y: boardColumnRect.maxY - handFrameHeight,
            width: boardColumnRect.width,
            height: handFrameHeight
        )
    }

    var opponentBattlefieldRect: CGRect {
        laneRects[0]
    }

    var opponentLandsRect: CGRect {
        laneRects[1]
    }

    var centerStripRect: CGRect {
        laneRects[2]
    }

    var playerBattlefieldRect: CGRect {
        laneRects[3]
    }

    var playerLandsRect: CGRect {
        laneRects[4]
    }

    var bottomActionRect: CGRect {
        let width = min(max(boardColumnRect.width * 0.58, 320), 460)
        let height: CGFloat = 38
        return CGRect(
            x: boardColumnRect.midX - width / 2,
            y: handRect.minY - height - 8,
            width: width,
            height: height
        )
    }

    var compactPromptRect: CGRect {
        let width = min(max(boardColumnRect.width * 0.30, 260), 340)
        let height = min(max(size.height * 0.20, 98), 178)
        return CGRect(
            x: boardColumnRect.midX - width / 2,
            y: max(centerStripRect.maxY + 6, playerBattlefieldRect.minY + 3),
            width: width,
            height: height
        )
    }

    var rightActionPanelRect: CGRect {
        let top = phaseRailRect.maxY + 8
        return CGRect(
            x: rightDockRect.minX,
            y: top,
            width: rightDockRect.width,
            height: max(rightDockRect.maxY - top, 190)
        )
    }

    var detailSheetRect: CGRect {
        let width = min(safeFrame.width, 560)
        let height = safeFrame.height - 12
        return CGRect(x: safeFrame.midX - width / 2, y: safeFrame.midY - height / 2,
                      width: width, height: height)
    }

    var phaseRailRect: CGRect {
        let top = diagnosticsY + 28
        let height: CGFloat = 36
        return CGRect(
            x: rightDockRect.minX + 8,
            y: top,
            width: max(rightDockRect.width - 16, 190),
            height: height
        )
    }

    var playWidth: CGFloat {
        boardColumnRect.width
    }

    var playCenterX: CGFloat {
        boardColumnRect.midX
    }

    var leftInset: CGFloat {
        boardColumnRect.minX
    }

    var railWidth: CGFloat {
        min(max(rightDockRect.width * 0.34, 64), 82)
    }

    var hudWidth: CGFloat {
        min(boardColumnRect.width * 0.34, 230)
    }

    var opponentHUDWidth: CGFloat {
        min(boardColumnRect.width * 0.24, 168)
    }

    var turnBadgeWidth: CGFloat {
        min(max(boardColumnRect.width * 0.24, 180), 220)
    }

    var turnBadgeX: CGFloat {
        boardColumnRect.minX + turnBadgeWidth / 2
    }

    var liveStatusX: CGFloat {
        min(boardColumnRect.maxX - 92, rightDockRect.minX - 92)
    }

    var opponentHUDX: CGFloat {
        boardColumnRect.midX
    }

    var playerHUDX: CGFloat {
        boardColumnRect.minX + hudWidth / 2 + 8
    }

    var bottomHUDY: CGFloat {
        max(handRect.minY - 12, playerLandsRect.maxY + 22)
    }

    var manaHUDX: CGFloat {
        boardColumnRect.minX + 102
    }

    var manaHUDY: CGFloat {
        playerLandsRect.minY - 14
    }

    var topHUDY: CGFloat {
        topStatusRect.midY
    }

    var diagnosticsY: CGFloat {
        rightDockRect.minY + 28
    }

    var stackPeekWidth: CGFloat {
        min(max(centerStripRect.width * 0.32, 190), 330)
    }

    var promptY: CGFloat {
        centerStripRect.midY
    }

    var playerDropZone: CGRect {
        playerPlayAreaRect
    }

    var playerPlayAreaRect: CGRect {
        CGRect(
            x: boardColumnRect.minX,
            y: playerBattlefieldRect.minY - 6,
            width: boardColumnRect.width,
            height: playerLandsRect.maxY - playerBattlefieldRect.minY + 14
        )
    }

    var inspectorX: CGFloat {
        detailSheetRect.midX
    }

    var inspectorY: CGFloat {
        detailSheetRect.midY
    }

    var logX: CGFloat {
        detailSheetRect.maxX + 22
    }

    var logY: CGFloat {
        min(size.height * 0.44, 210)
    }

    var stackRect: CGRect {
        let w: CGFloat = 200
        let h: CGFloat = 86
        return CGRect(
            x: size.width - w - 8,
            y: size.height - h - 8,
            width: w,
            height: h
        )
    }

    var handCardWidth: CGFloat {
        let horizontalFit = boardColumnRect.width / 7.7
        let verticalScale = safeFrame.height < 360 ? 0.24 : 0.30
        let verticalFit = max((safeFrame.height * verticalScale) / Self.magicCardHeightToWidth, 58)
        let minimumWidth: CGFloat = boardColumnRect.width < 540 ? 60 : 68
        return min(max(horizontalFit, minimumWidth), min(verticalFit, 90))
    }

    var handCardHeight: CGFloat {
        handCardWidth * Self.magicCardHeightToWidth
    }

    var handFrameHeight: CGFloat {
        ArenaHandLayout.restingHeight(cardHeight: handCardHeight)
    }

    var handY: CGFloat {
        handRect.midY
    }

    var handVisualTopY: CGFloat {
        handRect.minY - 24
    }

    var permanentCardWidth: CGFloat {
        min(88, max(44, (opponentBattlefieldRect.height - 12) / 1.08))
    }

    var permanentCardHeight: CGFloat { permanentCardWidth * 1.08 }

    var landCardWidth: CGFloat { min(48, permanentCardWidth) }

    var landCardHeight: CGFloat { landCardWidth * 1.08 }

    var landRowHeight: CGFloat {
        landCardHeight + 8
    }

    var compactRowHeight: CGFloat {
        permanentCardHeight + 8
    }

    var rowHeight: CGFloat {
        compactRowHeight
    }

    var battlefieldRowsHeight: CGFloat {
        compactRowHeight * 2 + landRowHeight * 2 + centerStripHeight + laneGap * 4
    }

    private var battlefieldRect: CGRect {
        let top = boardColumnRect.minY + 2
        let bottom = handRect.minY - 4
        return CGRect(x: boardColumnRect.minX, y: top, width: boardColumnRect.width, height: max(bottom - top, 190))
    }

    private var laneRects: [CGRect] {
        // Lands share each player's row, leaving vertical space for readable cards and hand.
        let rowHeight = max((battlefieldRect.height - centerStripHeight - 12) / 2, 44)
        let landWidth = battlefieldRect.width * 0.32
        let creatureWidth = battlefieldRect.width - landWidth - 10
        let top = battlefieldRect.minY
        let centerY = top + rowHeight + 6
        let playerY = centerY + centerStripHeight + 6
        func creatures(_ y: CGFloat) -> CGRect {
            CGRect(x: battlefieldRect.minX, y: y, width: creatureWidth, height: rowHeight)
        }
        func lands(_ y: CGFloat) -> CGRect {
            CGRect(x: battlefieldRect.maxX - landWidth, y: y, width: landWidth, height: rowHeight)
        }
        return [creatures(top), lands(top),
                CGRect(x: battlefieldRect.minX, y: centerY, width: battlefieldRect.width, height: centerStripHeight),
                creatures(playerY), lands(playerY)]
    }

    private var laneGap: CGFloat {
        3
    }

    private var centerStripHeight: CGFloat {
        centerControlsVisible ? 56 : 0
    }

    private var battlefieldScale: CGFloat {
        min(1, max(0.88, (opponentBattlefieldRect.height - 8) / max(naturalPermanentCardHeight, 1)))
    }

    private var landScale: CGFloat {
        1
    }

    private var naturalPermanentCardHeight: CGFloat {
        min(max(boardColumnRect.width / 9.4, 52), 76) * 1.40
    }

    private var naturalLandCardHeight: CGFloat {
        max(44, min(max(boardColumnRect.width / 12.4, 46), 62) * 1.12)
    }
}

typealias BattlefieldBoardLayout = BattlefieldLayoutMetrics

struct PortraitBattlefieldLayoutMetrics {
    static let magicCardHeightToWidth = BattlefieldLayoutMetrics.magicCardHeightToWidth

    let size: CGSize
    let safeArea: EdgeInsets
    var largeText = false
    var paymentActive = false
    var centerControlsVisible = true
    var centerStripHeight: CGFloat { paymentActive ? 60 : centerControlsVisible ? 36 : 0 }

    init(proxy: GeometryProxy, paymentActive: Bool = false, largeText: Bool = false, centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        self.largeText = largeText
        self.paymentActive = paymentActive
        size = proxy.size
        // This reader is inside the safe-area-constrained game root. Only the
        // battlefield background ignores those insets; controls stay inside it.
        safeArea = EdgeInsets()
    }

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets(), paymentActive: Bool = false, centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        self.paymentActive = paymentActive
        self.size = size
        self.safeArea = safeArea
    }

    var safeFrame: CGRect {
        let margin: CGFloat = 8
        return CGRect(
            x: safeArea.leading + margin,
            y: safeArea.top + 8,
            width: max(size.width - safeArea.leading - safeArea.trailing - margin * 2, 300),
            height: max(size.height - safeArea.top - safeArea.bottom - 16, 0)
        )
    }

    var topHUDRect: CGRect {
        CGRect(x: safeFrame.minX, y: safeFrame.minY, width: safeFrame.width, height: largeText ? 84 : 54)
    }

    var opponentBattlefieldRect: CGRect {
        CGRect(x: safeFrame.minX + 10, y: topHUDRect.maxY + 10, width: creatureLaneWidth, height: permanentGroupHeight)
    }

    var opponentLandsRect: CGRect {
        if usesCompactLanes {
            return CGRect(x: opponentBattlefieldRect.maxX + 8, y: opponentBattlefieldRect.minY,
                          width: safeFrame.maxX - 10 - opponentBattlefieldRect.maxX - 8, height: permanentGroupHeight)
        }
        return CGRect(x: safeFrame.minX + 10, y: opponentBattlefieldRect.maxY + 5, width: safeFrame.width - 20, height: landCardHeight + 8)
    }

    var centerStripRect: CGRect {
        CGRect(x: safeFrame.minX + 8, y: opponentLandsRect.maxY + 10, width: safeFrame.width - 16, height: centerStripHeight)
    }

    var playerBattlefieldRect: CGRect {
        CGRect(x: safeFrame.minX + 10, y: centerStripRect.maxY + 10, width: creatureLaneWidth, height: permanentGroupHeight)
    }

    var playerLandsRect: CGRect {
        if usesCompactLanes {
            return CGRect(x: playerBattlefieldRect.maxX + 8, y: playerBattlefieldRect.minY,
                          width: safeFrame.maxX - 10 - playerBattlefieldRect.maxX - 8, height: permanentGroupHeight)
        }
        return CGRect(x: safeFrame.minX + 10, y: playerBattlefieldRect.maxY + 5, width: safeFrame.width - 20, height: landCardHeight + 8)
    }

    var bottomControlsRect: CGRect {
        let height: CGFloat = 110
        return CGRect(x: safeFrame.minX, y: safeFrame.maxY - height, width: safeFrame.width, height: height)
    }

    var handRect: CGRect {
        let top = playerLandsRect.maxY + 8
        let bottom = bottomControlsRect.minY - 8
        return CGRect(x: safeFrame.minX, y: top, width: safeFrame.width, height: max(bottom - top, 0))
    }

    var bottomHUDRect: CGRect {
        CGRect(x: bottomControlsRect.minX, y: bottomControlsRect.minY, width: min(max(bottomControlsRect.width * 0.34, 132), 146), height: bottomControlsRect.height)
    }

    var bottomActionPanelRect: CGRect {
        let x = bottomHUDRect.maxX + 10
        return CGRect(
            x: x,
            y: bottomControlsRect.minY + 8,
            width: max(stackPanelRect.minX - x - 10, 118),
            height: bottomControlsRect.height - 16
        )
    }

    var passButtonRect: CGRect {
        CGRect(
            x: bottomActionPanelRect.minX,
            y: bottomActionPanelRect.minY + 18,
            width: bottomActionPanelRect.width,
            height: 44
        )
    }

    var skipButtonRect: CGRect {
        CGRect(
            x: passButtonRect.minX,
            y: passButtonRect.maxY + 10,
            width: passButtonRect.width,
            height: 34
        )
    }

    var bottomNavRect: CGRect {
        CGRect(
            x: bottomActionPanelRect.minX,
            y: skipButtonRect.maxY + 6,
            width: bottomActionPanelRect.width,
            height: max(bottomActionPanelRect.maxY - skipButtonRect.maxY - 6, 34)
        )
    }

    var stackPanelRect: CGRect {
        let width = min(max(bottomControlsRect.width * 0.28, 108), 126)
        return CGRect(
            x: bottomControlsRect.maxX - width - 8,
            y: bottomControlsRect.minY + 8,
            width: width,
            height: bottomControlsRect.height - 16
        )
    }

    var settingsButtonRect: CGRect {
        let size: CGFloat = 34
        return CGRect(
            x: bottomNavRect.minX,
            y: bottomNavRect.midY - size / 2,
            width: size,
            height: size
        )
    }

    var handScrubberRect: CGRect {
        CGRect(
            x: handRect.minX + 24,
            y: handRect.maxY - 12,
            width: max(handRect.width - 48, 120),
            height: 8
        )
    }

    var compactPromptRect: CGRect {
        CGRect(x: safeFrame.minX + 16, y: safeFrame.midY - 95, width: safeFrame.width - 32, height: 190)
    }

    var detailSheetRect: CGRect {
        CGRect(
            x: safeFrame.minX + 18,
            y: safeFrame.midY - min(safeFrame.height * 0.38, 290),
            width: safeFrame.width - 36,
            height: min(safeFrame.height * 0.76, 580)
        )
    }

    var playerPlayAreaRect: CGRect {
        CGRect(x: safeFrame.minX, y: playerBattlefieldRect.minY - 8, width: safeFrame.width, height: playerLandsRect.maxY - playerBattlefieldRect.minY + 16)
    }

    var playerDropZone: CGRect {
        playerPlayAreaRect
    }

    var permanentCardWidth: CGFloat {
        min(92, max(50, (permanentGroupHeight - 12) / 1.08))
    }

    var permanentCardHeight: CGFloat {
        permanentCardWidth * 1.08
    }

    var permanentRowHeight: CGFloat {
        permanentCardHeight + 8
    }

    var permanentGroupHeight: CGFloat {
        max(80, (safeFrame.height - topHUDRect.height - bottomControlsRect.height - ArenaHandLayout.restingHeight(cardHeight: handCardHeight) - 6 - centerStripHeight - (usesCompactLanes ? 0 : 2 * (landCardHeight + 8)) - 56) / 2)
    }

    // Preserve readable hand height on short phones by putting lands beside
    // permanents, using the same independently scrolling lanes as landscape.
    var usesCompactLanes: Bool {
        safeFrame.height < topHUDRect.height + bottomControlsRect.height + handCardHeight + 36 + centerStripHeight + 2 * (landCardHeight + 8) + 56 + 160
    }

    private var creatureLaneWidth: CGFloat {
        (safeFrame.width - 20) * (usesCompactLanes ? 0.68 : 1)
    }

    var landCardWidth: CGFloat {
        45
    }

    var landCardHeight: CGFloat {
        landCardWidth * 1.08
    }

    var handCardWidth: CGFloat {
        min(max(safeFrame.width / 4.8, 78), 88)
    }

    var handCardHeight: CGFloat {
        handCardWidth * Self.magicCardHeightToWidth
    }
}

struct BattlefieldLane {
    let name: String
    let frame: CGRect
}
