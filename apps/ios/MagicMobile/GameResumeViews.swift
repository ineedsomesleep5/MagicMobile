import SwiftUI

/// "Resume your game?" over the main menu. An explicit choice: the backdrop does not dismiss it.
struct GameResumePrompt: View {
    let offer: GameResumeOffer
    let resume: () -> Void
    let abandon: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                BrandMark(size: 40)
                Text(GameResumeText.promptTitle).brandTitle(28)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(offer.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ondevice.resume.detail")
                VStack(spacing: 10) {
                    Button(action: resume) {
                        Label(GameResumeText.resume, systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle(kind: .primary))
                    .accessibilityIdentifier("ondevice.resume.resume")
                    Button(role: .destructive, action: abandon) {
                        Text(GameResumeText.abandon).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle(kind: .destructive))
                    .accessibilityIdentifier("ondevice.resume.abandon")
                }
                .padding(.top, 4)
            }
            .brandPanel(padding: 22)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("ondevice.resume.prompt")
        }
        .preferredColorScheme(.dark)
    }
}

/// A one-time line about a saved game: expired, resumed, or lost when the app closed.
struct GameResumeNoticeBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BrandTheme.ember)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(BrandTheme.inkSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.leading, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BrandTheme.surface.opacity(0.97))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BrandTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ondevice.resume.notice")
    }
}
