import SwiftUI

/// Deck Studio is the app's light "workshop" mode: deckbuilding means long reading
/// sessions over dense lists, which a light surface serves better than the battlefield's
/// dark one. It stays light on purpose, but it is no longer a separate design system —
/// its geometry and type come from GameBoardDesignTokens and MagicTypography, and its
/// accent is the app's one gold darkened for contrast on parchment. Changing it here
/// never changes the battlefield palette.
enum DeckStudioPalette {
    static let background = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let surface = Color(red: 0.99, green: 0.985, blue: 0.965)
    static let surfaceElevated = Color.white
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.15)
    static let secondaryInk = Color(red: 0.34, green: 0.36, blue: 0.35)
    /// The shared antique gold, darkened so it still passes contrast on a light surface.
    static let gold = Color(red: 0.43, green: 0.33, blue: 0.16)
    static let success = Color(red: 0.17, green: 0.36, blue: 0.26)
    static let warning = Color(red: 0.48, green: 0.27, blue: 0.07)
    static let danger = Color(red: 0.64, green: 0.15, blue: 0.15)
    static let separator = Color(red: 0.83, green: 0.81, blue: 0.77)
}

/// Geometry and motion shared with the rest of the app, so a Deck Studio control has the
/// same shape and touch target as a battlefield one.
enum DeckStudioMetrics {
    private static let tokens = GameBoardDesignTokens.current
    static let controlRadius = tokens.radius.sheet - 4      // 14
    static let panelRadius = tokens.radius.heroPanel        // 20
    static let cardRadius = tokens.radius.card              // 6
    static let controlHeight = tokens.control.standardHeight // 48
    static let touchTarget = tokens.control.minimumTouchTarget // 44
    static let panelPadding = tokens.spacing.large          // 16
}

struct DeckStudioButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: DeckStudioMetrics.controlHeight)
            .foregroundStyle(primary ? .white : DeckStudioPalette.ink)
            .background(primary ? DeckStudioPalette.ink : DeckStudioPalette.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).stroke(primary ? .clear : DeckStudioPalette.separator))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
    }
}

struct DeckStudioPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(DeckStudioMetrics.panelPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: DeckStudioMetrics.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.panelRadius).stroke(DeckStudioPalette.separator.opacity(0.7)))
    }
}

struct DeckStudioNotice: View {
    let title: String
    let message: String
    var icon = "info.circle"
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
        } icon: { Image(systemName: icon) }
        .foregroundStyle(DeckStudioPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeckStudioColorIdentity: View {
    let colors: [String]?
    private let order = ["W", "U", "B", "R", "G"]
    var body: some View {
        HStack(spacing: 4) {
            if let colors {
                if colors.isEmpty { Text("C").font(.caption2.bold()) }
                ForEach(order.filter { colors.contains($0) }, id: \.self) { symbol in
                    Text(symbol).font(.caption2.bold()).frame(width: 22, height: 22)
                        .background(DeckStudioPalette.surfaceElevated, in: Circle())
                        .overlay(Circle().stroke(DeckStudioPalette.separator))
                }
            } else { Text("Identity unknown").font(.caption2) }
        }
        .foregroundStyle(DeckStudioPalette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(colors.map { "Color identity: " + ($0.isEmpty ? "colorless" : $0.joined(separator: ", ")) } ?? "Color identity unavailable")
    }
}
