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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let horizontal = proxy.size.width > proxy.size.height && !dynamicTypeSize.isAccessibilitySize
            let cardWidth = horizontal ? min(150, proxy.size.height * 0.36) : min(168, proxy.size.width * 0.41, proxy.size.height * 0.2)
            let layout = horizontal ? AnyLayout(HStackLayout(alignment: .center, spacing: 44)) : AnyLayout(VStackLayout(spacing: 14))
            ScrollView(.vertical, showsIndicators: false) {
                layout {
                    VStack(spacing: 6) {
                        if !horizontal { identity(compact: false) }
                        HeroCommanderCard(name: commanderName, namespace: commanderNamespace, width: cardWidth)
                        deckTile
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        if horizontal { identity(compact: true).padding(.bottom, 8) }
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
                        if let friends {
                            Button {
                                GameAudio.shared.play(.uiOpen)
                                friends()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.2.fill")
                                    Text("Friends")
                                    Spacer(minLength: 0)
                                    if friendsBadge > 0 {
                                        Text("\(friendsBadge)")
                                            .font(.system(size: 13, weight: .black)).monospacedDigit()
                                            .padding(.horizontal, 8).padding(.vertical, 2)
                                            .background(BrandTheme.ember, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(BrandButtonStyle(kind: .secondary))
                            .accessibilityValue(friendsBadge > 0 ? "\(friendsBadge) online or waiting" : "")
                            .accessibilityIdentifier("menu.friends")
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
                .padding(.vertical, horizontal ? 16 : 12)
                .frame(maxWidth: 960, minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 14)
            }
        }
        .background(BrandBackdrop().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { appeared = true }
        }
    }

    private func identity(compact: Bool) -> some View {
        VStack(alignment: compact ? .leading : .center, spacing: 8) {
            BrandMark(size: compact ? 52 : 64)
            Text("MAGICMOBILE")
                .font(.caption.weight(.heavy)).tracking(3)
                .foregroundStyle(BrandTheme.inkSecondary)
            Text("Your next\ngreat game.")
                .brandTitle(compact ? 32 : 36)
                .multilineTextAlignment(compact ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Welcome back, \(playerName)")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.inkSecondary)
                    .multilineTextAlignment(compact ? .leading : .center)
            }
        }
    }

    private var deckTile: some View {
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

/// One spelling for each stored appearance, with a deliberate fallback. An unrecognised
/// stored value previously fell through to "midnight" by accident rather than returning
/// to the real default.
enum BoardAppearancePreference {
    static let key = "magicmobile.boardAppearance"
    static let defaultValue = "arena"
    static let options = BattlefieldBackdrop.allCases.map(\.rawValue)
    static func normalized(_ value: String) -> String { options.contains(value) ? value : defaultValue }
}

struct BoardAppearancePicker: View {
    @AppStorage(BoardAppearancePreference.key) private var appearance = BoardAppearancePreference.defaultValue
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battlefield").font(.headline).foregroundStyle(MagicPalette.parchment)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(BattlefieldBackdrop.allCases) { theme in
                    choice(theme.title, value: theme.rawValue)
                }
            }
            Text("Works in portrait and landscape.")
                .font(.caption).foregroundStyle(MagicPalette.parchment.opacity(0.65))
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
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? MagicPalette.antiqueGold : .white.opacity(0.15), lineWidth: 2))
        .foregroundStyle(MagicPalette.parchment)
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
            .background(Color(red: 0.08, green: 0.07, blue: 0.065))
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct PortraitModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Rotate")
                    .font(.callout.weight(.black))
                    .foregroundStyle(.white)
                Text("Portrait and landscape")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
        }
        .toggleStyle(.switch)
        .tint(GameBoardTheme.current.emeraldPriority)
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 10)
    }
}

/// The top of the board switches to whoever's turn starts (BoardFocusTracker). On by default.
struct FollowTurnsToggle: View {
    @AppStorage(BoardFocusTracker.followTurnsKey) private var isOn = true

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow Turns")
                    .font(.callout.weight(.black))
                    .foregroundStyle(.white)
                Text("Show whose turn it is at the top. A tap on an opponent holds until the next turn.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
        }
        .toggleStyle(.switch)
        .tint(GameBoardTheme.current.emeraldPriority)
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 10)
        .accessibilityIdentifier("settings.followTurns")
    }
}
