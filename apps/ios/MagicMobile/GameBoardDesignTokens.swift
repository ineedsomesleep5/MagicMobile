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
        let menuMaxWidth: CGFloat = 620
        let setupMaxWidth: CGFloat = 760
        let landscapeSidebarWidth: CGFloat = 248
    }

    struct Spacing {
        let hairline: CGFloat = 2
        let laneGap: CGFloat = 4
        let extraSmall: CGFloat = 6
        let panelPadding: CGFloat = 8
        let small: CGFloat = 10
        let medium: CGFloat = 12
        let large: CGFloat = 16
        let extraLarge: CGFloat = 24
        let sectionGap: CGFloat = 32
        let handCardGap: CGFloat = 8
        let buttonGap: CGFloat = 6
        let sheetPadding: CGFloat = 12
    }

    struct Radius {
        let boardRoot: CGFloat = 28
        let heroPanel: CGFloat = 20
        let sheet: CGFloat = 18
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
        let readableMinimum: CGFloat = 11
        let largeControl: CGFloat = 17
    }

    struct Control {
        let minimumTouchTarget: CGFloat = 44
        let standardHeight: CGFloat = 48
        let prominentHeight: CGFloat = 54
        let compactGameHeight: CGFloat = 44
        let minimumIconSize: CGFloat = 20
    }

    struct Border {
        let hairline: CGFloat = 0.5
        let standard: CGFloat = 1
        let emphasized: CGFloat = 1.5
    }

    struct Motion {
        let immediate: Double = 0.12
        let fast: Double = 0.18
        let standard: Double = 0.26
        let springResponse: Double = 0.32
        let springDamping: Double = 0.84
    }

    struct Opacity {
        let disabled: Double = 0.42
        let secondary: Double = 0.72
        let quietBorder: Double = 0.18
        let standardBorder: Double = 0.42
        let scrim: Double = 0.66
    }

    static let current = GameBoardDesignTokens()

    let canvas = Canvas()
    let spacing = Spacing()
    let radius = Radius()
    let typography = Typography()
    let control = Control()
    let border = Border()
    let motion = Motion()
    let opacity = Opacity()
}
