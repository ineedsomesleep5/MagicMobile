import SwiftUI

/// A friend's challenge arriving on the menu: a leather card with the mode and Accept or Decline.
struct ChallengeInviteBanner: View {
    let challenge: FriendChallenge
    let accept: () -> Void
    let decline: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if challenge.isRanked, let step = challenge.challengerStep {
                    RankEmblem(tier: RankPosition.atStep(step).tier, size: 44)
                } else {
                    Image(systemName: "figure.fencing")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .frame(width: 44, height: 44)
                }
            }
            .scaleEffect(pulse ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "\(challenge.challenger ?? String(localized: "A friend")) challenges you"))
                    .font(ArenaMenuStyle.font(15, .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                Text(challenge.isRanked ? String(localized: "Ranked · counts for both") : String(localized: "Quick Match · friendly"))
                    .font(ArenaMenuStyle.font(12, .regular)).opacity(0.8)
            }
            Spacer(minLength: 4)
            Button(String(localized: "Decline"), action: decline)
                .buttonStyle(ArenaButtonStyle(kind: .secondary, compact: true))
                .accessibilityIdentifier("challenge.decline")
            Button(String(localized: "Accept"), action: accept)
                .buttonStyle(ArenaButtonStyle(kind: .primary, compact: true))
                .accessibilityIdentifier("challenge.accept")
        }
        .foregroundStyle(TavernPalette.parchment)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 14))
        .shadow(color: TavernPalette.ember.opacity(0.45), radius: 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: 560)
        .onAppear {
            GameAudio.shared.play(.uiOpen)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("challenge.invite")
    }
}
