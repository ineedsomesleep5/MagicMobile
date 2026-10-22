import SwiftUI
import PhotosUI
import UIKit

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
        .sheet(isPresented: $showReport) { GamePerformanceSheet(report: GamePerformanceLog.section(entries) ?? "").environment(\.boardPanelClose, nil) }
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
    @AppStorage(OnDeviceSmartPass.stopForThreatsKey) private var stopForThreats = true
    @State private var showStops = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TavernToggle(title: "Smart Auto-Pass", isOn: $isOn, identifier: "settings.smartAutoPass",
                         subtitle: "Passes for you when you have nothing to play, and skips steps you don’t stop at.")
            TavernToggle(title: "Stop for My Own Spells", isOn: $stopForOwn, identifier: "settings.stopForOwnSpells",
                         subtitle: "Off: your own spells and triggers resolve without a stop, as on Arena.")
                .disabled(!isOn)
            TavernToggle(title: "Stop for Removal", isOn: $stopForThreats, identifier: "settings.stopForThreats",
                         subtitle: "An opponent's spell that destroys, exiles or takes your permanents waits for you, even when you can't answer it.")
            Button { showStops = true } label: {
                Label("Phase Stops", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
            .disabled(!isOn)
            .accessibilityIdentifier("settings.phaseStops")
        }
        .modifier(TavernSettingsPanel())
        .sheet(isPresented: $showStops) { PhaseStopsSheet().environment(\.boardPanelClose, nil) }
    }
}

/// The phase stops on a tavern sheet; also opened by tapping the phase plate in a game.
struct PhaseStopsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.boardPanelClose) private var panelClose
    /// Closes the sheet, or the Arena board's panel on the table.
    private func close() { if let panelClose { panelClose() } else { dismiss() } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TavernPanelTitle(text: "Phase Stops")
                Spacer()
                Button { close() } label: { TavernSealLabel() }
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
