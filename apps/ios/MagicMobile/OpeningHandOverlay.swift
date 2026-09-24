import SwiftUI

/// XMage's mulligan question ("Mulligan to 6 cards?"), answered from the opening-hand screen.
struct OpeningHandChoice {
    let message: String
    let keepLabel: String
    let mulliganLabel: String
    let keep: GameCommand
    let mulligan: GameCommand
    let promptID: String

    init?(_ snapshot: GameSnapshot) {
        guard let prompt = snapshot.promptEnvelopeV2, let confirmation = prompt.confirmation,
              prompt.message.localizedCaseInsensitiveContains("mulligan"),
              let yes = confirmation.yesCommand, let no = confirmation.noCommand else { return nil }
        func command(_ response: XmageResponseCommand) -> GameCommand? {
            guard let type = response.type, let promptId = response.promptId,
                  let confirmed = response.confirmed ?? response.pay else { return nil }
            return UniversalPromptResponseCommandBuilder.command(
                gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision, promptEnvelope: prompt,
                type: type, promptId: promptId, playerId: prompt.playerId,
                ids: [confirmed ? "true" : "false"], useCommandZone: nil, manaType: nil, pay: response.pay ?? confirmed)
        }
        // XMage's left button (yes) mulligans; the right one (no) keeps.
        guard let mulligan = command(yes), let keep = command(no) else { return nil }
        self.mulligan = mulligan
        self.keep = keep
        promptID = prompt.id
        message = prompt.message.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        mulliganLabel = confirmation.yesLabel ?? String(localized: "Mulligan")
        keepLabel = confirmation.noLabel ?? String(localized: "Keep")
    }
}

/// Arena-style opening hand: the seven cards fanned large over a dimmed table, with
/// Mulligan and Keep. Tap a card to read it full size.
struct OpeningHandOverlay: View {
    let choice: OpeningHandChoice
    let cards: [ZoneCard]
    let pending: Bool
    let answer: (GameCommand, String, String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dealt = false
    @State private var focused: ZoneCard?

    var body: some View {
        GeometryReader { proxy in
            let count = max(cards.count, 1)
            let width = min(116, (proxy.size.width - 56) / (CGFloat(count) * 0.5 + 0.62))
            let height = width * BattlefieldLayoutMetrics.magicCardHeightToWidth
            ZStack {
                Color.black.opacity(0.78).ignoresSafeArea()
                RadialGradient(colors: [MagicPalette.antiqueGold.opacity(0.16), .clear], center: .center,
                               startRadius: 10, endRadius: proxy.size.width * 0.7)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Text("OPENING HAND")
                            .font(.system(size: 13, weight: .black)).tracking(3)
                            .foregroundStyle(MagicPalette.antiqueGold)
                        Text(choice.message)
                            .font(.system(size: 20, weight: .black, design: .serif))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .accessibilityIdentifier("board.opening.message")
                    }
                    fan(width: width, height: height, available: proxy.size.width)
                        .frame(height: height * 1.2)
                        .padding(.bottom, 10)
                    HStack(spacing: 12) {
                        Button {
                            GameAudio.shared.play(.shuffle)
                            answer(choice.mulligan, choice.mulliganLabel, "opening-mulligan-\(choice.promptID)")
                        } label: {
                            Label(choice.mulliganLabel, systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OpeningHandButtonStyle(primary: false))
                        .accessibilityIdentifier("board.opening.mulligan")
                        Button {
                            answer(choice.keep, choice.keepLabel, "opening-keep-\(choice.promptID)")
                        } label: {
                            Label(choice.keepLabel, systemImage: "hand.thumbsup.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OpeningHandButtonStyle(primary: true))
                        .accessibilityIdentifier("board.opening.keep")
                    }
                    .disabled(pending)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }
                if let focused {
                    Color.black.opacity(0.6).ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { self.focused = nil } }
                    let big = min(proxy.size.width - 56, 320)
                    CardTile(card: focused, selected: false, zoneName: "Opening hand", width: big,
                             height: big * BattlefieldLayoutMetrics.magicCardHeightToWidth,
                             ignoreTappedRotation: true, imageVariant: .inspection)
                        .shadow(color: .black.opacity(0.7), radius: 20, y: 10)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { self.focused = nil } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Tap to return to your hand")
                }
            }
        }
        .onAppear {
            if reduceMotion { dealt = true } else { withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { dealt = true } }
            GameAudio.shared.play(.cardDraw)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.opening")
    }

    private func fan(width: CGFloat, height: CGFloat, available: CGFloat) -> some View {
        let count = cards.count
        let mid = CGFloat(count - 1) / 2
        // Leave room for the tilt of the outer cards.
        let step = min(width * 0.52, (available - 64 - width) / CGFloat(max(count - 1, 1)))
        return ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let offset = CGFloat(index) - mid
                CardTile(card: card, selected: false, zoneName: "Opening hand", width: width, height: height,
                         ignoreTappedRotation: true, imageVariant: .inspection)
                    .shadow(color: .black.opacity(0.55), radius: 8, y: 5)
                    .rotationEffect(.degrees(dealt ? Double(offset) * 5 : 0), anchor: .bottom)
                    .offset(x: dealt ? offset * step : 0, y: dealt ? abs(offset) * abs(offset) * 2.2 : height * 0.6)
                    .opacity(dealt ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: dealt)
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { focused = card } }
                    .accessibilityLabel(card.card.name)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows this card full size")
            }
        }
    }
}

/// Keep glows gold; Mulligan is a gold-edged outline, both easy to hit.
private struct OpeningHandButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(primary ? Color(red: 0.16, green: 0.11, blue: 0.05) : MagicPalette.parchment)
            .padding(.vertical, 14)
            .frame(minHeight: 50)
            .background(
                Capsule().fill(primary
                    ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), MagicPalette.antiqueGold],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.black.opacity(0.55)))
            )
            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(primary ? 0 : 0.8), lineWidth: 1.5))
            .shadow(color: primary ? MagicPalette.antiqueGold.opacity(0.5) : .clear, radius: 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .pressSound(primary ? .uiConfirm : nil, isPressed: configuration.isPressed)
    }
}
