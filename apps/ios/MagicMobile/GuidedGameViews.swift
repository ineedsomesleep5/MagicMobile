import SwiftUI

/// The guided game's note: a leather slip in brass trim at the top of the table, with the
/// moment's title, a sentence or two, Got it and Turn off tips. It never covers more than it
/// needs; the rest of the table stays live under it.
struct GuidedGameCoachCard: View {
    let tip: GuidedGameTip
    let dismiss: () -> Void
    let turnOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TavernTag(text: "GUIDE", accent: TavernPalette.ember)
                TavernPanelTitle(text: GuidedGameText.title(tip))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(GuidedGameText.body(tip))
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(TavernPalette.parchment)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guided.tip.body")
            HStack(spacing: 10) {
                Button(GuidedGameText.turnOff, action: turnOff)
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("guided.turnOff")
                Spacer(minLength: 0)
                Button(GuidedGameText.gotIt, action: dismiss)
                    .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                    .accessibilityIdentifier("guided.gotIt")
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 12))
        .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guided.tip.\(tip.rawValue)")
    }
}

/// The first launch's welcome: a guided game, the How to Play slideshow, or straight to the menu.
struct GuidedGameWelcomeView: View {
    let playGuided: () -> Void
    let readHowToPlay: () -> Void
    let skip: () -> Void

    var body: some View {
        ZStack {
            TavernSheetBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.black.opacity(0.55)).overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1)))
                        .accessibilityHidden(true)
                    TavernPanelTitle(text: GuidedGameText.welcomeTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(GuidedGameText.welcomeBody)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(TavernPalette.parchment)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 12) {
                        Button(GuidedGameText.start, action: playGuided)
                            .buttonStyle(TavernButtonStyle(kind: .primary, fullWidth: true))
                            .accessibilityIdentifier("guided.welcome.play")
                        Button(GuidedGameText.readHowToPlay, action: readHowToPlay)
                            .buttonStyle(TavernButtonStyle(kind: .secondary, fullWidth: true))
                            .accessibilityIdentifier("guided.welcome.howToPlay")
                        Button(GuidedGameText.skip, action: skip)
                            .buttonStyle(TavernButtonStyle(kind: .secondary, fullWidth: true))
                            .accessibilityIdentifier("guided.welcome.skip")
                    }
                    .padding(.top, 6)
                }
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}
