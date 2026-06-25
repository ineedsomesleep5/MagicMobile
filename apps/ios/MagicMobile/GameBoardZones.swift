import Foundation

struct GameBoardZoneDescriptor: Identifiable, Hashable {
    let layer: GameBoardLayerName
    let purpose: String
    let swiftUIComponent: String
    let dataSource: String
    let functional: Bool

    var id: String { layer.rawValue }
}

enum GameBoardZoneCatalog {
    static let all: [GameBoardZoneDescriptor] = [
        GameBoardZoneDescriptor(layer: .boardRoot, purpose: "Root safe-area board container", swiftUIComponent: "NativeGameView", dataSource: "GameSnapshot", functional: true),
        GameBoardZoneDescriptor(layer: .background, purpose: "Decorative rustic battlefield surface", swiftUIComponent: "BattlefieldSurface", dataSource: "none", functional: false),
        GameBoardZoneDescriptor(layer: .opponentHUD, purpose: "AI life, commander, and zone counts", swiftUIComponent: "PlayerHeroHUD", dataSource: "snapshot.opponent", functional: true),
        GameBoardZoneDescriptor(layer: .opponentBattlefield, purpose: "Opponent permanents and lands", swiftUIComponent: "BattlefieldRow", dataSource: "snapshot.opponent.zones.battlefield", functional: true),
        GameBoardZoneDescriptor(layer: .centerStackStrip, purpose: "Stack and current prompt summary", swiftUIComponent: "XmageStackPeek, PromptPill", dataSource: "snapshot.xmage.stack and prompts", functional: true),
        GameBoardZoneDescriptor(layer: .phasePriorityBar, purpose: "Turn, phase, active player, priority", swiftUIComponent: "TurnStatusBadge", dataSource: "snapshot.turn, phase, priorityPlayerId", functional: true),
        GameBoardZoneDescriptor(layer: .promptPanel, purpose: "Prompt controls and legal action routing", swiftUIComponent: "UniversalPromptActionPanel", dataSource: "snapshot.legalActions and promptEnvelopeV2", functional: true),
        GameBoardZoneDescriptor(layer: .playerBattlefield, purpose: "Human permanents and lands", swiftUIComponent: "BattlefieldRow", dataSource: "snapshot.human.zones.battlefield", functional: true),
        GameBoardZoneDescriptor(layer: .handRail, purpose: "Human hand", swiftUIComponent: "HandFan", dataSource: "snapshot.human.zones.hand", functional: true),
        GameBoardZoneDescriptor(layer: .actionTray, purpose: "Selected card, pass, and priority actions", swiftUIComponent: "UniversalPromptActionPanel.actionSection", dataSource: "selectedCardActions", functional: true),
        GameBoardZoneDescriptor(layer: .manaPool, purpose: "Human mana pool", swiftUIComponent: "ManaPoolHUD", dataSource: "snapshot.human.manaPool", functional: true),
        GameBoardZoneDescriptor(layer: .commandZoneButton, purpose: "Command zone access and commander state", swiftUIComponent: "MobileSurfacesPanel", dataSource: "snapshot.human.zones.command", functional: true),
        GameBoardZoneDescriptor(layer: .graveyardButton, purpose: "Graveyard sheet access", swiftUIComponent: "MobileSurfacesPanel", dataSource: "snapshot.human.zones.graveyard", functional: true),
        GameBoardZoneDescriptor(layer: .exileButton, purpose: "Exile sheet access", swiftUIComponent: "MobileSurfacesPanel", dataSource: "snapshot.human.zones.exile", functional: true),
        GameBoardZoneDescriptor(layer: .stackButton, purpose: "Full stack sheet access", swiftUIComponent: "XmageStackPeek", dataSource: "snapshot.xmage.stack", functional: true),
        GameBoardZoneDescriptor(layer: .cardInspectorSheet, purpose: "Card details", swiftUIComponent: "CardInspector", dataSource: "inspectedCard", functional: true),
        GameBoardZoneDescriptor(layer: .zoneSheet, purpose: "Command/graveyard/exile/search sheets", swiftUIComponent: "ZoneInspectorSheet", dataSource: "zone-specific cards", functional: true),
        GameBoardZoneDescriptor(layer: .bridgeStatusPill, purpose: "Source, health, bridgeRevision, xmageCycle, WebSocket", swiftUIComponent: "GameDiagnosticsBadge", dataSource: "snapshot source and health", functional: true),
        GameBoardZoneDescriptor(layer: .aiThinkingPill, purpose: "AI thinking/waiting/stalled states", swiftUIComponent: "PromptPill", dataSource: "pendingStatus and priority fields", functional: true),
        GameBoardZoneDescriptor(layer: .unsupportedPromptFallback, purpose: "Safe fallback for unsupported prompts", swiftUIComponent: "UniversalPromptActionPanel unsupported prompt section", dataSource: "promptEnvelopeV2", functional: true)
    ]

    static var requiredLayerNames: Set<GameBoardLayerName> {
        Set(all.map(\.layer))
    }
}
