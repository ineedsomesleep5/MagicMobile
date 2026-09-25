import SwiftUI

/// A player's face at the table: their commander's art in a ring that turns gold on their
/// turn, spins while an AI decides, and greys out with a skull once they are out.
struct PlayerPortrait: View {
    let player: PlayerGameState
    var size: CGFloat = 44
    var active = false
    var thinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var commanderName: String? {
        player.commanders?.compactMap(\.name).first { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [MagicPalette.iron, MagicPalette.leather], startPoint: .top, endPoint: .bottom))
            if let name = commanderName {
                NativeCardArtworkView(name: name, variant: .board, contentMode: .fill, artOnly: true) { _, _ in initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .saturation(player.isOut ? 0 : 1)
        .opacity(player.isOut ? 0.5 : 1)
        .overlay(Circle().stroke(ring, lineWidth: active ? 2.5 : 1.3))
        .shadow(color: active ? MagicPalette.antiqueGold.opacity(0.55) : .clear, radius: 6)
        .overlay {
            if thinking && !player.isOut {
                ThinkingRing(color: BoardTurnColors.opponent, still: reduceMotion)
                    .padding(-3.5)
            }
        }
        .overlay(alignment: .bottom) {
            if player.isOut {
                Image(systemName: "skull.fill")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(MagicPalette.oxblood))
                    .offset(y: size * 0.14)
            }
        }
        .accessibilityHidden(true)
    }

    private var ring: Color {
        if player.isOut { return .gray.opacity(0.6) }
        return active ? MagicPalette.antiqueGold : MagicPalette.borderBronze.opacity(0.8)
    }

    private var initials: some View {
        Text(String((player.displayName ?? "?").prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .black, design: .rounded))
            .foregroundStyle(MagicPalette.parchment)
    }
}

/// A short arc orbiting a portrait while that player decides.
private struct ThinkingRing: View {
    let color: Color
    let still: Bool
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: still ? 1 : 0.3)
            .stroke(color.opacity(still ? 0.7 : 1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                guard !still else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { turning = true }
            }
    }
}

/// "Aurelia is thinking" with three pulsing dots.
struct ThinkingLabel: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            Text("\(name) is thinking")
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    Circle().frame(width: 3.5, height: 3.5)
                        .opacity(reduceMotion ? 0.8 : (phase == index ? 1 : 0.3))
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                phase = (phase + 1) % 3
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name) is thinking"))
    }
}
