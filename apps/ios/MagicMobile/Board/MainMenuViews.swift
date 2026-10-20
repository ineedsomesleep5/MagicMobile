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
        .safeAreaInset(edge: .bottom, spacing: 0) { SupportBanner() }
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
                        decks()   // the spell book opening is heard from its film (GrimoireStage)
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
                .font(TavernDisplayFont.font(21))
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
            .accessibilityValue(friendsBadge > 0 ? "\(friendsBadge) online, waiting or unread" : "")
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
    /// Walnut Tavern is the only board players can choose since 2026-10-11 (the picker is gone);
    /// `arena` (the classic layout) stays for UI tests that pin it with a launch argument.
    static let defaultValue = "tavern"
    static let options = BattlefieldBackdrop.allCases.map(\.rawValue)
    static func normalized(_ value: String) -> String { options.contains(value) ? value : defaultValue }
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
                    BoardModePicker()
                    CardFramesToggle()
                    PortraitModeToggle(isOn: $portraitModeEnabled)
                    FollowTurnsToggle()
                    AutoPassAfterCastToggle()
                    SmartAutoPassToggle()
                    BoardEffectsPicker()
                    GamePerformancePanel()
                    SupportSettingsPanel()
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background { TavernSheetBackground() }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

/// Recent games' memory and heat (GamePerformanceLog), always reachable here so the player can share it to compare app
/// versions. Numbers only: no cards or player names. Android's GamePerformancePanel matches it.
struct GamePerformancePanel: View {
    @State private var entries: [GamePerformanceEntry] = []
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TavernPanelTitle(text: "Game Performance")
            Text("Memory and heat from your recent games, to compare app versions. Numbers only, no cards or names. Nothing is sent unless you share it.")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(TavernPalette.parchment.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Text(entries.last.map { String(localized: "Last game: \($0.line)") } ?? String(localized: "Finish a game to record one."))
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(TavernPalette.parchment.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.performance.last")
            Button { showReport = true } label: {
                Label("View and Share", systemImage: "chart.bar.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
            .disabled(entries.isEmpty)
            .accessibilityIdentifier("settings.performance")
        }
        .modifier(TavernSettingsPanel())
        .onAppear {
            entries = GamePerformanceLog.shared.entries
            #if DEBUG
            // UI tests: two recorded games without playing them.
            if ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_PERFORMANCE"] != nil {
                let start = Date().addingTimeInterval(-7_200)
                entries = [GamePerformanceEntry(started: start, mode: "quick", aiSkill: 3, minutes: 18, turns: 11, peakFootprintMB: 612, hottest: 1),
                           GamePerformanceEntry(started: start.addingTimeInterval(3_600), mode: "ranked", aiSkill: 4, minutes: 34, turns: 19,
                                                peakFootprintMB: 845, lowestAvailableMB: 410, hottest: 2, hotMinutes: 6, memoryWarnings: 1)]
            }
            #endif
        }
        .sheet(isPresented: $showReport) { GamePerformanceSheet(report: GamePerformanceLog.section(entries) ?? "") }
    }
}

/// The full performance report on a tavern sheet, with Share.
struct GamePerformanceSheet: View {
    let report: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TavernPanelTitle(text: "Game Performance")
                Spacer()
                Button { dismiss() } label: { TavernSealLabel() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("performance.close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ShareLink(item: report) { Label("Share Report", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                        .accessibilityIdentifier("performance.share")
                    Text(report)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(TavernPalette.parchment)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("performance.report")
                }
                .padding(18)
            }
        }
        .background { TavernSheetBackground() }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
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
/// Tavern frames on battlefield cards, for the board mode chosen above (CardFramesPreference).
struct CardFramesToggle: View {
    @AppStorage(BoardMode.key) private var mode = BoardMode.defaultValue
    @AppStorage(CardFramesPreference.hearthKey) private var hearth = CardFramesPreference.hearthDefault
    @AppStorage(CardFramesPreference.arenaKey) private var arena = CardFramesPreference.arenaDefault

    var body: some View {
        let isArena = BoardMode.resolved(mode) == .arena
        TavernToggle(title: "Card Frames", isOn: isArena ? $arena : $hearth, identifier: "settings.cardFrames",
                     subtitle: isArena ? "Tavern frames on Arena's battlefield cards. Off, they look like the reference game's cards."
                                       : "Tavern frames on Hearth's battlefield cards. Off, they look like the reference game's cards.")
            .modifier(TavernSettingsPanel())
    }
}

struct FollowTurnsToggle: View {
    @AppStorage(BoardFocusTracker.followTurnsKey) private var isOn = true

    var body: some View {
        TavernToggle(title: "Follow Turns", isOn: $isOn, identifier: "settings.followTurns",
                     subtitle: "Show whose turn it is at the top. A tap on an opponent holds until the next turn.")
            .modifier(TavernSettingsPanel())
    }
}

/// After you cast a spell, priority passes so it resolves without another tap (opponents can still respond). On by default.
enum AutoPassAfterCast {
    static let key = "magicmobile.autoPassAfterCast"
}

struct AutoPassAfterCastToggle: View {
    @AppStorage(AutoPassAfterCast.key) private var isOn = true

    var body: some View {
        TavernToggle(title: "Pass After Casting", isOn: $isOn, identifier: "settings.autoPassAfterCast",
                     subtitle: "Your spell resolves without another tap. Opponents can still respond.")
            .modifier(TavernSettingsPanel())
    }
}

/// Smart auto-pass (OnDeviceSmartPass, on by default) and the button to its phase stops.
struct SmartAutoPassToggle: View {
    @AppStorage(OnDeviceSmartPass.enabledKey) private var isOn = true
    @AppStorage(OnDeviceSmartPass.stopForOwnSpellsKey) private var stopForOwn = false
    @State private var showStops = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TavernToggle(title: "Smart Auto-Pass", isOn: $isOn, identifier: "settings.smartAutoPass",
                         subtitle: "Passes for you when you have nothing to play, and skips steps you don’t stop at.")
            TavernToggle(title: "Stop for My Own Spells", isOn: $stopForOwn, identifier: "settings.stopForOwnSpells",
                         subtitle: "Off: your own spells and triggers resolve without a stop, as on Arena.")
                .disabled(!isOn)
            Button { showStops = true } label: {
                Label("Phase Stops", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
            .disabled(!isOn)
            .accessibilityIdentifier("settings.phaseStops")
        }
        .modifier(TavernSettingsPanel())
        .sheet(isPresented: $showStops) { PhaseStopsSheet() }
    }
}

/// The phase stops on a tavern sheet; also opened by tapping the phase plate in a game.
struct PhaseStopsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TavernPanelTitle(text: "Phase Stops")
                Spacer()
                Button { dismiss() } label: { TavernSealLabel() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("phaseStops.close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            ScrollView { PhaseStopsGrid().padding(18) }
        }
        .background { TavernSheetBackground() }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// Where smart auto-pass stops when you have something to play: one row per step, a stop for
/// your turn and one for your opponents' turns.
struct PhaseStopsGrid: View {
    @AppStorage(OnDeviceSmartPass.enabledKey) private var enabled = true
    @AppStorage(OnDeviceSmartPass.stopsKey) private var raw = OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops)

    private var explanation: String {
        enabled ? "With something to play, the game stops at the steps you mark. With nothing to play it passes for you. It stops when you can answer an opponent's spell or attack, and lets your own spells resolve unless you turn on Stop for My Own Spells in Settings."
                : "Smart Auto-Pass is off, so every step waits for you. Turn it on in Settings to use these stops."
    }

    var body: some View {
        let stops: Set<String> = OnDeviceSmartPass.Settings.decode(raw)
        VStack(alignment: .leading, spacing: 0) {
            Text(explanation)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(TavernPalette.parchment.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            header
            ForEach(OnDeviceSmartPass.Step.allCases) { step in
                PhaseStopRow(step: step, stops: stops, toggle: toggle)
            }
            Button("Reset Stops") { raw = OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops) }
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .accessibilityIdentifier("phaseStops.reset")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            PhaseStopColumnTitle(text: "YOUR TURN")
            PhaseStopColumnTitle(text: "THEIRS")
        }
        .padding(.bottom, 4)
    }

    private func toggle(_ key: String) {
        var next: Set<String> = OnDeviceSmartPass.Settings.decode(raw)
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        raw = OnDeviceSmartPass.Settings.encode(next)
    }
}

private struct PhaseStopColumnTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .serif)).tracking(0.8)
            .foregroundStyle(BrandTheme.brassGradient)
            .frame(width: 76)
    }
}

/// One step: its name, then the stop for your turn and the stop for your opponents' turns.
private struct PhaseStopRow: View {
    let step: OnDeviceSmartPass.Step
    let stops: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(TavernPalette.parchment)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                PhaseStopButton(step: step, myTurn: true, isOn: stops.contains(OnDeviceSmartPass.stopKey(step, myTurn: true)), toggle: toggle)
                PhaseStopButton(step: step, myTurn: false, isOn: stops.contains(OnDeviceSmartPass.stopKey(step, myTurn: false)), toggle: toggle)
            }
            .frame(minHeight: 48)
            Rectangle().fill(TavernPalette.brass.opacity(0.35)).frame(height: 1)
        }
    }
}

/// A stop: ember glass with a raised hand when set, dark leather when the step passes.
private struct PhaseStopButton: View {
    let step: OnDeviceSmartPass.Step
    let myTurn: Bool
    let isOn: Bool
    let toggle: (String) -> Void

    private var key: String { OnDeviceSmartPass.stopKey(step, myTurn: myTurn) }
    private var tint: Color { isOn ? Color(red: 1, green: 0.91, blue: 0.66) : TavernPalette.brass.opacity(0.6) }
    private var material: TavernFill.Material { isOn ? .ember : .leather }
    private var label: String {
        let side: String = myTurn ? String(localized: "your turn") : String(localized: "opponents’ turns")
        return "\(step.title), \(side)"
    }

    var body: some View {
        Button { toggle(key) } label: {
            Image(systemName: isOn ? "hand.raised.fill" : "circle.dotted")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 76, height: 36)
                .background { TavernFill(material: material).clipShape(Capsule()).padding(1.5) }
                .overlay { TavernCapsuleRim(thin: true) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? String(localized: "Stop") : String(localized: "Pass"))
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier("phaseStops.\(key)")
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
