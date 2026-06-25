import CoreGraphics
import SwiftUI

enum GameBoardLayerName: String, CaseIterable, Identifiable {
    case boardRoot = "MM.BoardRoot"
    case background = "MM.Background"
    case opponentHUD = "MM.OpponentHUD"
    case opponentBattlefield = "MM.OpponentBattlefield"
    case centerStackStrip = "MM.CenterStackStrip"
    case phasePriorityBar = "MM.PhasePriorityBar"
    case promptPanel = "MM.PromptPanel"
    case playerBattlefield = "MM.PlayerBattlefield"
    case handRail = "MM.HandRail"
    case actionTray = "MM.ActionTray"
    case manaPool = "MM.ManaPool"
    case commandZoneButton = "MM.CommandZoneButton"
    case graveyardButton = "MM.GraveyardButton"
    case exileButton = "MM.ExileButton"
    case stackButton = "MM.StackButton"
    case cardInspectorSheet = "MM.CardInspectorSheet"
    case zoneSheet = "MM.ZoneSheet"
    case bridgeStatusPill = "MM.BridgeStatusPill"
    case aiThinkingPill = "MM.AIThinkingPill"
    case unsupportedPromptFallback = "MM.UnsupportedPromptFallback"

    var id: String { rawValue }
}

struct GameBoardDesignTokens {
    struct Canvas {
        let targetSize = CGSize(width: 956, height: 440)
        let safeMargin: CGFloat = 10
        let dynamicIslandReserve: CGFloat = 72
        let homeIndicatorReserve: CGFloat = 16
    }

    struct Spacing {
        let laneGap: CGFloat = 4
        let panelPadding: CGFloat = 8
        let handCardGap: CGFloat = 8
        let buttonGap: CGFloat = 6
        let sheetPadding: CGFloat = 12
    }

    struct Radius {
        let boardRoot: CGFloat = 28
        let largePanel: CGFloat = 12
        let panel: CGFloat = 8
        let chip: CGFloat = 999
        let button: CGFloat = 7
        let card: CGFloat = 6
    }

    struct Typography {
        let statusTiny: CGFloat = 7
        let chip: CGFloat = 8
        let label: CGFloat = 10
        let body: CGFloat = 11
        let button: CGFloat = 12
        let hudLife: CGFloat = 40
        let cardName: CGFloat = 8
    }

    static let current = GameBoardDesignTokens()

    let canvas = Canvas()
    let spacing = Spacing()
    let radius = Radius()
    let typography = Typography()
}
