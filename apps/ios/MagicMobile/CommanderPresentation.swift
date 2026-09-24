import SwiftUI

/// Shared presentation for the journey from choosing a deck to taking a seat.
enum CommanderPresentation {
    static let canvas = BrandTheme.canvas
    static let surface = BrandTheme.surface
    static let ink = BrandTheme.ink
    static let secondary = BrandTheme.inkSecondary
    static let accent = BrandTheme.ember
}

/// Menu and setup buttons share the brand look (ember primary, dark secondary).
struct CommanderActionStyle: ButtonStyle {
    var primary = true

    func makeBody(configuration: Configuration) -> some View {
        BrandButtonStyle(kind: primary ? .primary : .secondary).makeBody(configuration: configuration)
    }
}

struct CommanderPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(BrandPanel())
    }
}

extension View {
    func commanderPanel() -> some View { modifier(CommanderPanel()) }
}

struct CommanderDeckPortrait: View {
    let name: String?
    var namespace: Namespace.ID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let namespace, !reduceMotion {
                artwork.matchedGeometryEffect(id: "selected-commander", in: namespace)
            } else {
                artwork
            }
        }
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        Color.clear.overlay {
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NativeCardArtworkView(name: name, variant: .inspection, contentMode: .fit) { _, _ in
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(BrandTheme.border, lineWidth: 1.4))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
    }

    private var placeholder: some View {
        ZStack {
            CommanderPresentation.surface
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.largeTitle.weight(.light))
                    .foregroundStyle(CommanderPresentation.accent)
                Text(name ?? "Choose your commander")
                    .font(.headline).multilineTextAlignment(.center)
                    .foregroundStyle(CommanderPresentation.ink)
                    .padding(.horizontal, 18)
            }
        }
    }
}
