import SwiftUI

/// Every game sound and music track, auditionable, with a switch per category and the
/// credits the music license asks for. An Arena page (Caleb, 2026-10-22: no sheets in the menus): inside Options it opens
/// from Audio with a back chevron; on its own it closes with its own button.
struct SoundLabView: View {
    var back: (() -> Void)? = nil
    @AppStorage(GameMusic.menu.choiceKey, store: MagicMobilePreferences.current) private var menuChoice = "shuffle"
    @AppStorage(GameMusic.game.choiceKey, store: MagicMobilePreferences.current) private var gameChoice = "shuffle"
    @State private var previewing: String?
    @Environment(\.arenaPanelClose) private var panelClose
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ArenaCaps(text: String(localized: "Music"))
                    musicPanel(.menu, choice: $menuChoice)
                    musicPanel(.game, choice: $gameChoice)
                    ArenaCaps(text: String(localized: "World sounds")).padding(.top, 6)
                    worldPanel
                    ArenaCaps(text: String(localized: "Sound effects")).padding(.top, 6)
                    ForEach(GameSoundCategory.allCases) { SoundLabCategory(category: $0) }
                    ArenaCaps(text: String(localized: "Credits")).padding(.top, 6)
                    credits
                }
                .padding(16)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .mask(ArenaScrollFade(depth: 48))
        }
        .foregroundStyle(ArenaMenuStyle.text)
        .preferredColorScheme(.dark)
        .onDisappear { GameAudio.shared.endPreview() }
    }

    /// The Options pages' head: the back chevron on the left, the title centred in serif, the close button on the right.
    private var header: some View {
        ZStack {
            Text(String(localized: "Sound Lab"))
                .font(ArenaMenuStyle.font(26, .bold)).foregroundStyle(ArenaMenuStyle.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                if let back {
                    Button {
                        GameAudio.shared.play(.uiBack)
                        back()
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy)).foregroundStyle(ArenaMenuStyle.text)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Back"))
                    .accessibilityIdentifier("panel.back")
                }
                Spacer(minLength: 0)
                ArenaCloseButton(identifier: "soundlab.done") { if let panelClose { panelClose() } else { dismiss() } }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.45) }
    }

    /// Each world's air, over the music as it plays at the table.
    private var worldPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ArenaTableTheme.allCases.filter { $0.ambience != nil }) { table in
                trackRow(title: table.title, selected: previewing == table.ambience, previewID: table.ambience) {
                    previewing = table.ambience
                    GameAudio.shared.previewWorld(table.ambience)
                }
                .accessibilityIdentifier("soundlab.world.\(table.rawValue)")
            }
        }
        .arenaCard(padding: 14)
    }

    private func musicPanel(_ scene: GameMusic, choice: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scene.title)
                .font(ArenaMenuStyle.font(17, .bold))
                .foregroundStyle(ArenaMenuStyle.text)
                .padding(.bottom, 4)
            trackRow(title: String(localized: "Shuffle all"),
                     selected: choice.wrappedValue == "shuffle", previewID: nil) {
                choice.wrappedValue = "shuffle"
                GameAudio.shared.settingsChanged(trackPickChanged: true)
            }
            .accessibilityIdentifier("soundlab.music.\(scene.rawValue).shuffle")
            ForEach(scene.tracks) { track in
                trackRow(title: track.title, selected: choice.wrappedValue == track.file,
                         previewID: track.file) {
                    choice.wrappedValue = track.file
                    previewing = track.file
                    GameAudio.shared.preview(track, in: scene)
                }
                .accessibilityIdentifier("soundlab.music.\(scene.rawValue).\(track.file)")
            }
        }
        .arenaCard(padding: 14)
    }

    /// A track by its title alone: the composer is in the credits below (the judge, 2026-10-22: no restating sublines).
    private func trackRow(title: String, selected: Bool, previewID: String?,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Arena's chosen diamond, lit gold.
                Rectangle()
                    .fill(selected ? AnyShapeStyle(ArenaMenuStyle.goldFill) : AnyShapeStyle(Color.clear))
                    .frame(width: 9, height: 9)
                    .overlay(Rectangle().strokeBorder(ArenaMenuStyle.gold.opacity(selected ? 1 : 0.6), lineWidth: 1.5))
                    .rotationEffect(.degrees(45))
                    .frame(width: 16)
                Text(title).font(ArenaMenuStyle.font(15, selected ? .bold : .medium)).foregroundStyle(ArenaMenuStyle.text)
                Spacer(minLength: 8)
                if let previewID {
                    Image(systemName: previewing == previewID ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ArenaMenuStyle.gold)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
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
            creditBlock(String(localized: "Table art"), lines: [
                String(localized: "3D props made with Meshy (meshy.ai). The medallion, corner ornament, candle and tankard are licensed under Creative Commons: By Attribution 4.0 License."),
                String(localized: "Wood and leather textures from Poly Haven (polyhaven.com, CC0).")
            ])
        }
        .arenaCard(padding: 14)
        .accessibilityIdentifier("soundlab.credits")
    }

    private func creditBlock(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ArenaCaps(text: title, size: 9.5)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(ArenaMenuStyle.font(12, .medium))
                    .foregroundStyle(ArenaMenuStyle.dim)
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
            TavernToggle(title: category.title, isOn: $enabled, identifier: "soundlab.category.\(category.rawValue)",
                         subtitle: category.detail)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(GameSound.sounds(in: category)) { sound in
                    Button {
                        GameAudio.shared.play(sound, audition: true)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ArenaMenuStyle.gold)
                            Text(sound.title).font(ArenaMenuStyle.font(13, .semibold))
                                .foregroundStyle(enabled ? ArenaMenuStyle.text : ArenaMenuStyle.dim)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .frame(minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.4)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BrandPressStyle())
                    .accessibilityLabel(String(localized: "Play \(sound.title)"))
                    .accessibilityIdentifier("soundlab.play.\(sound.rawValue)")
                }
            }
            .opacity(enabled ? 1 : 0.6)
        }
        .arenaCard(padding: 14)
    }
}
