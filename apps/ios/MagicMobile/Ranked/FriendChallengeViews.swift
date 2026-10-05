import SwiftUI

/// The challenger's wait while their friend answers: who, which mode, and a way to withdraw.
struct ChallengeWaitingOverlay: View {
    let friend: String
    let mode: PlayMode
    let rank: RankPosition
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                if mode == .ranked {
                    RankSpinEmblem(tier: rank.tier, size: 104, duration: 2.4, forever: true)
                } else {
                    Image(systemName: "figure.fencing")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .frame(height: 104)
                }
                Text(mode == .ranked ? String(localized: "Ranked challenge sent") : String(localized: "Quick Match challenge sent"))
                    .font(.system(size: 22, weight: .black, design: .serif))
                Text(String(localized: "Waiting for \(friend)…"))
                    .font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(TavernPalette.brass)
                Text(mode == .ranked ? String(localized: "This game counts for both of you.")
                                     : String(localized: "A friendly game: no rank change."))
                    .font(.system(size: 13, design: .serif)).opacity(0.8)
                Button(String(localized: "Withdraw challenge"), action: cancel)
                    .buttonStyle(TavernButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("challenge.cancel")
            }
            .foregroundStyle(TavernPalette.parchment)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: 420)
            .modifier(TavernPanelChrome(tavern: true, cornerRadius: 16))
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("challenge.waiting")
    }
}

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
                    .font(.system(size: 15, weight: .heavy, design: .serif)).lineLimit(1).minimumScaleFactor(0.75)
                Text(challenge.isRanked ? String(localized: "Ranked · counts for both") : String(localized: "Quick Match · friendly"))
                    .font(.system(size: 12, design: .serif)).opacity(0.8)
            }
            Spacer(minLength: 4)
            Button(String(localized: "Decline"), action: decline)
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                .accessibilityIdentifier("challenge.decline")
            Button(String(localized: "Accept"), action: accept)
                .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
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
