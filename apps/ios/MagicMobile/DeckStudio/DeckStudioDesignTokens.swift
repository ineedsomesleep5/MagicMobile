import SwiftUI

/// Walnut & Ember's workbench: aged parchment pages in dark brown ink, so real card artwork
/// still supplies the colour.
enum DeckStudioPalette {
    static let background = Color(red: 0.87, green: 0.79, blue: 0.64)
    static let surface = Color(red: 0.95, green: 0.90, blue: 0.79)
    static let surfaceElevated = Color(red: 0.98, green: 0.95, blue: 0.87)
    static let ink = Color(red: 0.20, green: 0.11, blue: 0.05)
    static let secondaryInk = Color(red: 0.40, green: 0.29, blue: 0.18)
    // The menu's ember hue, darkened for readable text on parchment.
    static let accent = Color(red: 0.60, green: 0.23, blue: 0.10)
    static let success = Color(red: 0.17, green: 0.36, blue: 0.20)
    static let warning = Color(red: 0.50, green: 0.28, blue: 0.06)
    static let danger = Color(red: 0.62, green: 0.13, blue: 0.10)
    static let separator = Color(red: 0.74, green: 0.60, blue: 0.38)
}

/// Geometry and motion shared with the rest of the app, so a Deck Studio control has the
/// same shape and touch target as a battlefield one.
enum DeckStudioMetrics {
    private static let tokens = GameBoardDesignTokens.current
    static let controlRadius: CGFloat = 16
    static let panelRadius: CGFloat = 22
    static let cardRadius = tokens.radius.card              // 6
    static let controlHeight = tokens.control.standardHeight // 48
    static let touchTarget = tokens.control.minimumTouchTarget // 44
    static let panelPadding = tokens.spacing.large          // 16
}

struct DeckStudioButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if TavernUIKit.available {
            // Walnut & Ember plaques: ember glass for the main action, leather for the rest.
            TavernButtonStyle(kind: primary ? .primary : .secondary, fontSize: 15).makeBody(configuration: configuration)
        } else {
            plain(configuration)
        }
    }

    private func plain(_ configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: DeckStudioMetrics.controlHeight)
            .foregroundStyle(primary ? .white : DeckStudioPalette.ink)
            .background(primary ? DeckStudioPalette.ink : DeckStudioPalette.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).stroke(primary ? .clear : DeckStudioPalette.separator))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Artwork buttons lift only through their own press; list edits remain immediate.
struct DeckStudioArtworkButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct DeckStudioPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(DeckStudioMetrics.panelPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: DeckStudioMetrics.panelRadius))
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
    @ScaledMetric(relativeTo: .caption2) private var pipSize = 22.0
    private let order = ["W", "U", "B", "R", "G"]
    var body: some View {
        HStack(spacing: 4) {
            if let colors {
                if colors.isEmpty { ManaSymbolView(symbol: "C", size: min(pipSize, 26)) }
                ForEach(order.filter { colors.contains($0) }, id: \.self) { symbol in
                    ManaSymbolView(symbol: symbol, size: min(pipSize, 26))
                }
            } else { Text("Identity unknown").font(.caption2).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .frame(minHeight: pipSize)
        .foregroundStyle(DeckStudioPalette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(colors.map { "Color identity: " + ($0.isEmpty ? "colorless" : $0.map { ["W": "white", "U": "blue", "B": "black", "R": "red", "G": "green"][$0] ?? $0 }.joined(separator: ", ")) } ?? "Color identity unavailable")
    }
}
