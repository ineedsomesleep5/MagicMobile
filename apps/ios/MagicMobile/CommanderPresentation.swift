import SwiftUI

/// Shared presentation for the journey from choosing a deck to taking a seat.
enum CommanderPresentation {
    static let canvas = Color(red: 20 / 255, green: 21 / 255, blue: 24 / 255)
    static let surface = Color(red: 31 / 255, green: 33 / 255, blue: 37 / 255)
    static let ink = Color(red: 243 / 255, green: 241 / 255, blue: 236 / 255)
    static let secondary = Color(red: 177 / 255, green: 178 / 255, blue: 182 / 255)
    static let accent = Color(red: 1, green: 128 / 255, blue: 88 / 255)
}

struct CommanderActionStyle: ButtonStyle {
    var primary = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .foregroundStyle(primary ? CommanderPresentation.canvas : CommanderPresentation.ink)
            .background(primary ? CommanderPresentation.accent : CommanderPresentation.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CommanderPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18)
            .background(CommanderPresentation.surface,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
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
