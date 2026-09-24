import SwiftUI

/// Every game sound and music track, auditionable, with a switch per category and the
/// credits the music license asks for.
struct SoundLabView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GameMusic.menu.choiceKey, store: MagicMobilePreferences.current) private var menuChoice = "shuffle"
    @AppStorage(GameMusic.game.choiceKey, store: MagicMobilePreferences.current) private var gameChoice = "shuffle"
    @State private var previewing: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tap any sound to hear it. Switch off a whole group if it gets in the way. Your picks are saved on this iPhone.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandTheme.inkSecondary)
                    BrandDivider(title: String(localized: "Music"))
                    musicPanel(.menu, choice: $menuChoice)
                    musicPanel(.game, choice: $gameChoice)
                    BrandDivider(title: String(localized: "Sound effects"))
                    ForEach(GameSoundCategory.allCases) { SoundLabCategory(category: $0) }
                    BrandDivider(title: String(localized: "Credits"))
                    credits
                }
                .padding(16)
            }
            .background(BrandTheme.canvas.ignoresSafeArea())
            .navigationTitle("Sound Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BrandTheme.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .heavy))
                        .tint(BrandTheme.ember)
                        .accessibilityIdentifier("soundlab.done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { GameAudio.shared.endPreview() }
    }

    private func musicPanel(_ scene: GameMusic, choice: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scene.title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(BrandTheme.ink)
            Text(scene == .menu ? "Plays in menus and while you build decks." : "Plays under the game, a little quieter.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandTheme.inkSecondary)
                .padding(.bottom, 6)
            trackRow(title: String(localized: "Shuffle all"), subtitle: String(localized: "A new track each time"),
                     selected: choice.wrappedValue == "shuffle", previewID: nil) {
                choice.wrappedValue = "shuffle"
                GameAudio.shared.settingsChanged(trackPickChanged: true)
            }
            .accessibilityIdentifier("soundlab.music.\(scene.rawValue).shuffle")
            ForEach(scene.tracks) { track in
                trackRow(title: track.title, subtitle: "Kevin MacLeod", selected: choice.wrappedValue == track.file,
                         previewID: track.file) {
                    choice.wrappedValue = track.file
                    previewing = track.file
                    GameAudio.shared.preview(track, in: scene)
                }
                .accessibilityIdentifier("soundlab.music.\(scene.rawValue).\(track.file)")
            }
        }
        .brandPanel(padding: 14)
    }

    private func trackRow(title: String, subtitle: String, selected: Bool, previewID: String?,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? BrandTheme.ember : BrandTheme.border)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(BrandTheme.ink)
                    Text(subtitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(BrandTheme.inkSecondary)
                }
                Spacer(minLength: 8)
                if let previewID {
                    Image(systemName: previewing == previewID ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BrandTheme.ember)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(BrandTheme.surfaceRaised))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(previewID == nil ? "" : String(localized: "Plays this track and picks it"))
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 10) {
            creditBlock(String(localized: "Music"), lines: (GameMusic.menu.tracks + GameMusic.game.tracks).map {
                "“\($0.title)” Kevin MacLeod (incompetech.com)"
            } + MusicCredits.stingers.map { "“\($0)” Kevin MacLeod (incompetech.com), excerpt" } + [
                String(localized: "Licensed under Creative Commons: By Attribution 4.0 License"),
                "http://creativecommons.org/licenses/by/4.0/"
            ])
            creditBlock(String(localized: "Sound effects"), lines: [
                String(localized: "Recordings from the Sonniss.com GDC Game Audio Bundles (royalty-free), by David Dumais Audio, Sound Spark LLC, Gamemaster Audio, Articulated Sounds, Airborne Sound, Double Trouble Audio, Bluezone, 3maze, Timothy McHugh, Sound Ex Machina and more."),
                String(localized: "Card recordings from Kenney.nl Casino Audio (CC0).")
            ])
        }
        .brandPanel(padding: 14)
        .accessibilityIdentifier("soundlab.credits")
    }

    private func creditBlock(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(1.8)
                .foregroundStyle(BrandTheme.ember)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Orchestral stingers cut from Kevin MacLeod pieces, credited with the tracks.
enum MusicCredits {
    static let stingers = ["Discovery Hit", "Greta Sting", "Danse Macabre - Big Hit 1"]
}

/// One group of effects: its switch and a chip per sound.
private struct SoundLabCategory: View {
    let category: GameSoundCategory
    @AppStorage private var enabled: Bool

    init(category: GameSoundCategory) {
        self.category = category
        _enabled = AppStorage(wrappedValue: true, category.key, store: MagicMobilePreferences.current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.system(size: 17, weight: .heavy)).foregroundStyle(BrandTheme.ink)
                    Text(category.detail).font(.system(size: 12, weight: .semibold)).foregroundStyle(BrandTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(BrandTheme.ember)
            .accessibilityIdentifier("soundlab.category.\(category.rawValue)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(GameSound.sounds(in: category)) { sound in
                    Button {
                        GameAudio.shared.play(sound, audition: true)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(BrandTheme.ember)
                            Text(sound.title).font(.system(size: 13, weight: .bold))
                                .foregroundStyle(enabled ? BrandTheme.ink : BrandTheme.inkSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .frame(minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BrandTheme.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BrandTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BrandPressStyle())
                    .accessibilityLabel(String(localized: "Play \(sound.title)"))
                    .accessibilityIdentifier("soundlab.play.\(sound.rawValue)")
                }
            }
            .opacity(enabled ? 1 : 0.6)
        }
        .brandPanel(padding: 14)
    }
}
