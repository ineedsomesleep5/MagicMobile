import SwiftUI

/// Deck Studio's colours in the Arena menus (Caleb, 2026-10-22): light type on dark glass, gold for accents.
/// (It was parchment in dark brown ink.) The names stay: `ink` is the main type, `background` and the surfaces glass.
enum DeckStudioPalette {
    static let background = Color(red: 0.07, green: 0.075, blue: 0.09)
    static let surface = Color(red: 0.12, green: 0.125, blue: 0.15)
    static let surfaceElevated = Color(red: 0.17, green: 0.17, blue: 0.20)
    static let ink = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let secondaryInk = Color(red: 0.95, green: 0.92, blue: 0.86).opacity(0.66)
    static let accent = Color(red: 0.98, green: 0.84, blue: 0.52)
    static let success = Color(red: 0.60, green: 0.86, blue: 0.58)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.40)
    static let danger = Color(red: 1.0, green: 0.52, blue: 0.46)
    static let separator = Color(red: 0.62, green: 0.47, blue: 0.24)
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
            // The Arena board's plaques: ember glass for the main action, leather for the rest.
            ArenaButtonStyle(kind: primary ? .primary : .secondary, fontSize: 15).makeBody(configuration: configuration)
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
            // A lighter pane of glass in the gold hairline.
            .background {
                GrimoirePaper(tone: .plate)
                    .clipShape(RoundedRectangle(cornerRadius: DeckStudioMetrics.panelRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.panelRadius)
                        .strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.7))
            }
    }
}

/// Something to tell the player, written on the page in the binder's hand (BinderNote).
struct DeckStudioNotice: View {
    let title: String
    let message: String
    var icon = "info.circle"
    var body: some View { BinderNote(title: title, message: message, icon: icon) }
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
