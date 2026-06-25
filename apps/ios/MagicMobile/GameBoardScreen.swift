import SwiftUI

enum GameBoardDesignPreviewState: String, CaseIterable, Identifiable {
    case normalBattlefield = "normal-battlefield"
    case selectedCardActionTray = "selected-card-action-tray"
    case manaPaymentPrompt = "mana-payment-prompt"
    case searchSelectPrompt = "search-select-prompt"
    case stackResponsePrompt = "stack-response-prompt"
    case commanderReplacementPrompt = "commander-replacement-prompt"
    case damageAssignmentPrompt = "damage-assignment-prompt"
    case unsupportedPromptFallback = "unsupported-prompt-fallback"
    case aiThinking = "ai-thinking"
    case bridgeUnavailable = "bridge-unavailable"
    case missingCardArt = "missing-card-art"

    var id: String { rawValue }

    var title: String {
        rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

struct GameBoardDesignPreviewLabel: View {
    let state: GameBoardDesignPreviewState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintpalette.fill")
            Text("DESIGN PREVIEW")
            Text(state.title)
        }
        .font(.system(size: 9, weight: .black))
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GameBoardTheme.current.antiqueGold, in: Capsule())
        .accessibilityLabel("Design preview mode. Not gameplay proof. \(state.title)")
    }
}
