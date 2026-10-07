import SwiftUI
import PhotosUI
import UIKit

/// Shared home presentation used by the native game and the development preview.
struct TavernMainMenu: View {
    let deckName: String
    let playerName: String
    let play: () -> Void
    let decks: () -> Void
    let settings: () -> Void
    var news: (() -> Void)? = nil
    var commanderName: String? = nil
    var commanderNamespace: Namespace.ID? = nil
    var downloads: (() -> Void)? = nil
    var howToPlay: (() -> Void)? = nil
    var friends: (() -> Void)? = nil
    /// Friends online plus requests waiting, shown on the Friends button.
    var friendsBadge = 0
    var profile: (() -> Void)? = nil
    /// The ranked standing shown on the Profile button.
    var rank: RankPosition? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let horizontal = proxy.size.width > proxy.size.height && !dynamicTypeSize.isAccessibilitySize
            let cardWidth = horizontal ? min(150, proxy.size.height * 0.36) : min(160, proxy.size.width * 0.38, proxy.size.height * 0.19)
            // No scrolling in either orientation (Caleb, 2026-10-02 landscape, 2026-10-04 portrait): short
            // screens tighten the brand block; anything still too tall scales to fit.
            let density = horizontal ? (proxy.size.height < 400 ? 2 : proxy.size.height < 470 ? 1 : 0)
                                     : (proxy.size.height < 700 ? 1 : 0)
            FitsHeight(available: proxy.size.height) {
                menuLayout(horizontal: horizontal, cardWidth: cardWidth, density: density, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
        }
        .background(BrandBackdrop().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { appeared = true }
        }
    }

    /// The deck and commander beside (landscape) or above (portrait) the actions. `density`
    /// 0 is the full layout; 1 and 2 tighten the brand block and spacing to fit a short screen.
    private func menuLayout(horizontal: Bool, cardWidth: CGFloat, density: Int, height: CGFloat) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .center, spacing: 44))
                                : AnyLayout(VStackLayout(spacing: density == 0 ? 14 : 10))
        return layout {
                VStack(spacing: 6) {
                    if !horizontal { identity(compact: false, density: density) }
                    HeroCommanderCard(name: commanderName, namespace: commanderNamespace, width: cardWidth)
                    deckTile
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: density == 0 ? 14 : density == 1 ? 10 : 8) {
                    if horizontal { identity(compact: true, density: density).padding(.bottom, density == 0 ? 8 : 2) }
                    Button {
                        GameAudio.shared.play(.menuPlay)
                        play()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                            Text("Play Commander")
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BrandButtonStyle(kind: .primary))
                    .accessibilityIdentifier("menu.play")
                    Button {
                        GameAudio.shared.play(.uiOpen)
                        decks()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.fill")
                            Text("Decks")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("menu.decks")
                    if friends != nil || profile != nil {
                        // Friends and Profile share a row (Caleb, 2026-10-04) so the menu fits without scrolling.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { socialActions }
                            VStack(spacing: density == 0 ? 14 : 10) { socialActions }
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { utilityActions }
                        HStack(spacing: 8) { utilityActions }
                        HStack(spacing: 0) { utilityActions }
                        VStack(alignment: .leading, spacing: 0) { utilityActions }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .frame(maxWidth: 400)
        }
        .padding(.horizontal, horizontal ? 36 : 26)
        .padding(.vertical, density == 0 ? 16 : 8)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
    }

    private func identity(compact: Bool, density: Int) -> some View {
        VStack(alignment: compact ? .leading : .center, spacing: density == 0 ? 8 : 5) {
            // Portrait leaves the mark out so the deck and actions sit higher (the app icon carries it).
            if compact { BrandMark(size: density == 0 ? 52 : density == 1 ? 42 : 34) }
            if density < 2 {
                Text("MAGICMOBILE")
                    .font(.caption.weight(.heavy)).tracking(3)
                    .foregroundStyle(BrandTheme.inkSecondary)
            }
            // Portrait and tighter landscape layouts set the title on one line.
            Text(density == 0 && compact ? "Your next\ngreat game." : "Your next great game.")
                .brandTitle(compact ? (density == 0 ? 32 : density == 1 ? 27 : 24) : (density == 0 ? 30 : 26))
                .lineLimit(compact ? nil : 1).minimumScaleFactor(0.75)
                .multilineTextAlignment(compact ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if density < 2, !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // In the tavern's hand, like the title above it (no system type on the menu).
                Text("Welcome back, \(playerName)")
                    .font(.system(size: 16, weight: .regular, design: .serif).italic())
                    .foregroundStyle(TavernPalette.parchment.opacity(0.8))
                    .shadow(color: .black.opacity(0.6), radius: 0.5, y: 1)
                    .multilineTextAlignment(compact ? .leading : .center)
            }
        }
    }

    @ViewBuilder private var deckTile: some View {
        if TavernUIKit.available { parchmentDeckTile } else { plainDeckTile }
    }

    /// Walnut & Ember: the deck's name on a parchment label in brass trim.
    private var parchmentDeckTile: some View {
        VStack(spacing: 2) {
            Text("YOUR DECK")
                .font(.system(size: 10, weight: .heavy, design: .serif)).tracking(2.2)
                .foregroundStyle(DeckStudioPalette.accent)
            Text(deckName)
                .font(.system(size: 21, weight: .heavy, design: .serif))
                .foregroundStyle(TavernPalette.ink)
            if let commanderName, !commanderName.isEmpty {
                Text(commanderName)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DeckStudioPalette.secondaryInk)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background { TavernFill(material: .parchment).clipShape(RoundedRectangle(cornerRadius: 9)) }
        .overlay { TavernBrassFrame(scale: 0.6) }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(commanderName.map { "Your deck: \(deckName), commander \($0)" } ?? "Your deck: \(deckName)")
    }

    private var plainDeckTile: some View {
        VStack(spacing: 4) {
            Text("YOUR DECK")
                .font(.caption2.weight(.heavy)).tracking(2.4)
                .foregroundStyle(BrandTheme.ember)
            Text(deckName)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(BrandTheme.ink)
                .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            if let commanderName, !commanderName.isEmpty {
                Text(commanderName)
                    .font(.footnote)
                    .foregroundStyle(BrandTheme.inkSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(commanderName.map { "Your deck: \(deckName), commander \($0)" } ?? "Your deck: \(deckName)")
    }

    @ViewBuilder private var socialActions: some View {
        if let friends {
            Button {
                GameAudio.shared.play(.uiOpen)
                friends()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                    Text("Friends").lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if friendsBadge > 0 {
                        Text("\(friendsBadge)")
                            .font(.system(size: 13, weight: .black)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(BrandTheme.ember, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(BrandButtonStyle(kind: .secondary))
            .accessibilityValue(friendsBadge > 0 ? "\(friendsBadge) online or waiting" : "")
            .accessibilityIdentifier("menu.friends")
        }
        if let profile {
            Button {
                GameAudio.shared.play(.uiOpen)
                profile()
            } label: {
                HStack(spacing: 8) {
                    if let rank {
                        RankEmblem(tier: rank.tier, size: 26)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                    }
                    Text("Profile").lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(BrandButtonStyle(kind: .secondary))
            .accessibilityValue(rank?.title ?? "")
            .accessibilityIdentifier("menu.profile")
        }
    }

    @ViewBuilder private var utilityActions: some View {
        BrandIconButton(title: "Settings", systemImage: "gearshape.fill") {
            GameAudio.shared.play(.uiOpen)
            settings()
        }
        .accessibilityIdentifier("menu.settings")
        if let news {
            BrandIconButton(title: "Updates", systemImage: "scroll.fill") {
                GameAudio.shared.play(.pageFlip)
                news()
            }
            .accessibilityIdentifier("menu.updates")
        }
        if let downloads {
            BrandIconButton(title: "Downloads", systemImage: "arrow.down.to.line.circle.fill") {
                GameAudio.shared.play(.uiOpen)
                downloads()
            }
            .accessibilityIdentifier("menu.downloads")
        }
        if let howToPlay {
            BrandIconButton(title: HowToPlayText.title, systemImage: "questionmark.circle") {
                GameAudio.shared.play(.pageFlip)
                howToPlay()
            }
            .accessibilityIdentifier("menu.howToPlay")
        }
    }
}

/// Lays its content out at its natural height and scales it down only if that is taller than
/// `available`, keeping it centred: a fixed screen that never scrolls.
private struct FitsHeight<Content: View>: View {
    let available: CGFloat
    @ViewBuilder let content: Content
    @State private var natural: CGFloat = 0

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: FitsHeightKey.self, value: geometry.size.height)
            })
            .onPreferenceChange(FitsHeightKey.self) { natural = $0 }
            .scaleEffect(natural > available ? available / natural : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FitsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// One spelling for each stored appearance, with a deliberate fallback. An unrecognised
/// stored value previously fell through to "midnight" by accident rather than returning
/// to the real default.
enum BoardAppearancePreference {
    static let key = "magicmobile.boardAppearance"
    /// Walnut Tavern is the default board (2026-10-02); a saved choice is kept.
    static let defaultValue = "tavern"
    static let options = BattlefieldBackdrop.allCases.map(\.rawValue)
    static func normalized(_ value: String) -> String { options.contains(value) ? value : defaultValue }
}

struct BoardAppearancePicker: View {
    @AppStorage(BoardAppearancePreference.key) private var appearance = BoardAppearancePreference.defaultValue
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TavernPanelTitle(text: "Battlefield")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(BattlefieldBackdrop.allCases) { theme in
                    choice(theme.title, value: theme.rawValue)
                }
            }
            Text("Works in portrait and landscape.")
                .font(.system(size: 12, design: .serif)).foregroundStyle(TavernPalette.parchment.opacity(0.65))
        }
    }
    private func choice(_ title: String, value: String) -> some View {
        Button { appearance = value } label: {
            AppearanceSwatch(title: title, selected: appearance == value) {
                BoardAppearanceArt(value: value)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " battlefield")
        .accessibilityAddTraits(appearance == value ? .isSelected : [])
    }
}

struct AppearanceSwatch<Art: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder let art: Art
    var body: some View {
        // Each swatch takes an equal share of the row. Aspect-filled artwork otherwise
        // claimed width from its neighbours, squeezing the gradient option to a sliver
        // and truncating the labels beside it.
        VStack(spacing: 8) {
            // A resizable image still reports a large ideal width, which wins the HStack's
            // space. Letting an empty container own the size and drawing the art inside it
            // keeps every swatch identical regardless of what it shows.
            Color.clear
                .frame(maxWidth: .infinity).frame(height: 68)
                .overlay { art }
                .clipped().clipShape(RoundedRectangle(cornerRadius: GameBoardDesignTokens.current.radius.panel))
            HStack(spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.seal.fill" : "circle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? AnyShapeStyle(BrandTheme.brassGradient) : AnyShapeStyle(TavernPalette.parchment.opacity(0.5)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background {
            TavernFill(material: .leather)
                .overlay(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? AnyShapeStyle(BrandTheme.brassGradient)
                                                                         : AnyShapeStyle(TavernPalette.brass.opacity(0.3)),
                                                                  lineWidth: selected ? 2 : 1))
        .shadow(color: selected ? TavernPalette.ember.opacity(0.5) : .clear, radius: 6)
        .foregroundStyle(TavernPalette.parchment)
        .contentShape(RoundedRectangle(cornerRadius: 10))  // the whole swatch takes the tap
    }
}

/// Swatches render the same art the surfaces do, so a preview cannot drift from reality.
struct BoardAppearanceArt: View {
    let value: String
    var body: some View {
        BattlefieldBackdropArt(theme: .resolved(value))
    }
}

struct AppearanceSettingsView: View {
    @Binding var portraitModeEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeTurnControl) private var nativeTurnControl
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if nativeTurnControl != nil { NativeArtworkPreferenceView() }
                    BoardAppearancePicker()
                    PortraitModeToggle(isOn: $portraitModeEnabled)
                    FollowTurnsToggle()
                    BoardEffectsPicker()
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background { TavernSheetBackground() }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct PortraitModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        TavernToggle(title: "Auto-Rotate", isOn: $isOn, subtitle: "Portrait and landscape")
            .modifier(TavernSettingsPanel())
    }
}

/// The top of the board switches to whoever's turn starts (BoardFocusTracker). On by default.
struct FollowTurnsToggle: View {
    @AppStorage(BoardFocusTracker.followTurnsKey) private var isOn = true

    var body: some View {
        TavernToggle(title: "Follow Turns", isOn: $isOn, identifier: "settings.followTurns",
                     subtitle: "Show whose turn it is at the top. A tap on an opponent holds until the next turn.")
            .modifier(TavernSettingsPanel())
    }
}

/// One group of settings: a leather panel in brass trim with parchment text.
struct TavernSettingsPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(TavernPalette.parchment)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .modifier(TavernPanelChrome(tavern: true, cornerRadius: 10))
    }
}
