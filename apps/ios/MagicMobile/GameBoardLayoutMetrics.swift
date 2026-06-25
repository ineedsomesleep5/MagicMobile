import CoreGraphics

struct GameBoardLayerFrame: Identifiable, Hashable {
    let layer: GameBoardLayerName
    let rect: CGRect

    var id: String { layer.rawValue }
}

struct GameBoardLayoutSpec {
    let canvasSize: CGSize
    let layers: [GameBoardLayerFrame]

    static let magicPathLandscape = GameBoardLayoutSpec(
        canvasSize: CGSize(width: 956, height: 440),
        layers: [
            GameBoardLayerFrame(layer: .boardRoot, rect: CGRect(x: 0, y: 0, width: 956, height: 440)),
            GameBoardLayerFrame(layer: .background, rect: CGRect(x: 0, y: 0, width: 956, height: 440)),
            GameBoardLayerFrame(layer: .phasePriorityBar, rect: CGRect(x: 84, y: 12, width: 220, height: 42)),
            GameBoardLayerFrame(layer: .opponentHUD, rect: CGRect(x: 312, y: 10, width: 162, height: 48)),
            GameBoardLayerFrame(layer: .bridgeStatusPill, rect: CGRect(x: 496, y: 17, width: 92, height: 28)),
            GameBoardLayerFrame(layer: .opponentBattlefield, rect: CGRect(x: 78, y: 65, width: 540, height: 126)),
            GameBoardLayerFrame(layer: .centerStackStrip, rect: CGRect(x: 78, y: 197, width: 540, height: 44)),
            GameBoardLayerFrame(layer: .playerBattlefield, rect: CGRect(x: 78, y: 248, width: 540, height: 126)),
            GameBoardLayerFrame(layer: .manaPool, rect: CGRect(x: 82, y: 292, width: 200, height: 30)),
            GameBoardLayerFrame(layer: .handRail, rect: CGRect(x: 186, y: 374, width: 392, height: 52)),
            GameBoardLayerFrame(layer: .promptPanel, rect: CGRect(x: 634, y: 70, width: 216, height: 298)),
            GameBoardLayerFrame(layer: .actionTray, rect: CGRect(x: 596, y: 368, width: 226, height: 58)),
            GameBoardLayerFrame(layer: .commandZoneButton, rect: CGRect(x: 74, y: 382, width: 72, height: 34)),
            GameBoardLayerFrame(layer: .graveyardButton, rect: CGRect(x: 828, y: 376, width: 46, height: 34)),
            GameBoardLayerFrame(layer: .exileButton, rect: CGRect(x: 880, y: 376, width: 46, height: 34)),
            GameBoardLayerFrame(layer: .stackButton, rect: CGRect(x: 598, y: 204, width: 34, height: 28)),
            GameBoardLayerFrame(layer: .cardInspectorSheet, rect: CGRect(x: 30, y: 86, width: 132, height: 164)),
            GameBoardLayerFrame(layer: .zoneSheet, rect: CGRect(x: 166, y: 78, width: 178, height: 132)),
            GameBoardLayerFrame(layer: .aiThinkingPill, rect: CGRect(x: 370, y: 203, width: 120, height: 28)),
            GameBoardLayerFrame(layer: .unsupportedPromptFallback, rect: CGRect(x: 654, y: 248, width: 176, height: 72))
        ]
    )

    func frame(for layer: GameBoardLayerName) -> CGRect? {
        layers.first { $0.layer == layer }?.rect
    }
}
