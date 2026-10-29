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
                Text(GameResumeText.promptTitle).font(ArenaMenuStyle.title(26, .bold)).foregroundStyle(ArenaMenuStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(offer.detail)
                    .font(ArenaMenuStyle.font(15, .semibold))
                    .foregroundStyle(ArenaMenuStyle.text.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ondevice.resume.detail")
                VStack(spacing: 10) {
                    Button(action: resume) {
                        Label(GameResumeText.resume, systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ArenaButtonStyle(kind: .primary, fullWidth: true))
                    .accessibilityIdentifier("ondevice.resume.resume")
                    Button(role: .destructive, action: abandon) {
                        Text(GameResumeText.abandon).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ArenaButtonStyle(kind: .danger, fullWidth: true))
                    .accessibilityIdentifier("ondevice.resume.abandon")
                }
                .padding(.top, 4)
            }
            .padding(22)
            .modifier(ArenaGlassPanel(cornerRadius: 18, opacity: 0.96))
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
    /// The table's notices ("Jed left. The game goes on.") use their own symbol.
    var symbol = "clock.arrow.circlepath"
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ArenaMenuStyle.gold)
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
            .accessibilityLabel(GameResumeText.dismiss)
        }
        .padding(.leading, 14)
        .modifier(ArenaGlassPanel(cornerRadius: 14, opacity: 0.97))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ondevice.resume.notice")
    }
}

/// The server's notice on the main menu (AppConfig, mm_app_config): it stays until the player closes it, then never comes back.
struct AppNoticeBanner: View {
    @State private var notice = AppConfigStore.shared.shownNotice

    var body: some View {
        Group {
            if let notice {
                GameResumeNoticeBanner(message: notice.text, symbol: "megaphone.fill") { AppConfigStore.shared.dismissNotice(notice) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("menu.notice")
            }
        }
        .animation(.easeOut(duration: 0.24), value: notice)
        .onReceive(NotificationCenter.default.publisher(for: AppConfigStore.didChange).receive(on: RunLoop.main)) { _ in
            notice = AppConfigStore.shared.shownNotice
        }
    }
}
