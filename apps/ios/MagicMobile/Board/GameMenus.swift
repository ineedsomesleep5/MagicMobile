import SwiftUI
import PhotosUI
import UIKit

struct MagicPathPhaseRail: View {
    let snapshot: GameSnapshot
    let passAction: LegalAction?
    let yieldActions: [LegalAction]
    let logAction: () -> Void
    let settingsAction: () -> Void
    let runAction: (LegalAction) -> Void
    var onlyPhases: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if onlyPhases {
                HStack(spacing: 7) {
                    PhaseChip(label: "Phase", phase: (snapshot.step ?? snapshot.phase).arenaPhaseTitle, active: true)
                    PhaseChip(label: "Priority", phase: snapshot.playerLabel(snapshot.priorityPlayerId), active: snapshot.isViewer(snapshot.priorityPlayerId))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    Button {
                        if let passAction {
                            runAction(passAction)
                        }
                    } label: {
                        Text(GameplayActionPresentation.title(for: passAction, snapshot: snapshot))
                            .font(.system(size: 12, weight: .black, design: .serif))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                    .disabled(passAction == nil)

                    YieldActionsControl(
                        snapshot: snapshot,
                        actions: yieldActions,
                        fontSize: 8,
                        runAction: runAction
                    )
                }

                HStack(spacing: 6) {
                    Button(action: logAction) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    .accessibilityLabel("Open game log")
                    Button(action: settingsAction) {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    .accessibilityLabel("Open game settings")
                }
            }
        }
        .padding(onlyPhases ? 0 : 8)
        .background(onlyPhases ? Color.clear : MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if !onlyPhases {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MagicPalette.antiqueGold.opacity(0.26), lineWidth: 1)
            }
        }
    }

    static func skipButtonLabel(snapshot: GameSnapshot, action: LegalAction?) -> String {
        GameplayActionPresentation.title(for: action, snapshot: snapshot)
    }
}

struct YieldActionsControl: View {
    let snapshot: GameSnapshot
    let actions: [LegalAction]
    let fontSize: CGFloat
    var iconOnly = false
    let runAction: (LegalAction) -> Void

    var body: some View {
        Group {
            if actions.count == 1, let action = actions.first {
                Button {
                    runAction(action)
                } label: {
                    actionLabel(GameplayActionPresentation.title(for: action, snapshot: snapshot), showsDisclosure: false)
                }
                .modifier(CompactOrCircleButtonStyle(circular: iconOnly))
                .accessibilityLabel(GameplayActionPresentation.title(for: action, snapshot: snapshot))
            } else {
                Menu {
                    ForEach(actions) { action in
                        Button(GameplayActionPresentation.title(for: action, snapshot: snapshot)) {
                            runAction(action)
                        }
                    }
                } label: {
                    actionLabel("Timing Options", showsDisclosure: true)
                }
                .modifier(CompactOrCircleButtonStyle(circular: iconOnly))
                .disabled(actions.isEmpty)
                .accessibilityLabel(actions.isEmpty ? "No timing options available" : "Open timing options")
                .accessibilityHint(actions.isEmpty ? "" : "Choose how far XMage should yield priority")
            }
        }
        .frame(minHeight: 44)
    }

    private func actionLabel(_ title: String, showsDisclosure: Bool) -> some View {
        HStack(spacing: 5) {
            if iconOnly {
                Image(systemName: "forward.end").font(.system(size: 16, weight: .semibold))
            } else {
            Text(title)
                .font(.system(size: fontSize, weight: .black, design: .serif))
                .multilineTextAlignment(.center)
            if showsDisclosure {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: max(fontSize - 2, 7), weight: .bold))
            }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

enum GameMenuConfirmation: Equatable {
    case startNew
    case quit

    var title: String {
        switch self {
        case .startNew: return "Start a new game?"
        case .quit: return "Quit this game?"
        }
    }

    var message: String {
        switch self {
        case .startNew: return "MagicMobile will ask XMage to clean up the current game, then open setup."
        case .quit: return "MagicMobile will ask XMage to clean up the current game, then return to the main menu."
        }
    }
}

struct PromptDebugInspector: View {
    let snapshot: GameSnapshot
    let liveUpdateStatus: String
    let lastActionRejection: ActionRejectionNotice?
    let protocolDebug: XmageProtocolDebug?
    let protocolDebugError: String?
    let isProtocolDebugLoading: Bool
    let refreshProtocolDebug: () -> Void

    private var prompt: PromptEnvelopeV2? { snapshot.promptEnvelopeV2 }
    private var presentation: MobilePromptPresentation? {
        MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt Debug")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("XMage prompt and bridge state")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))

                HStack {
                    Text(isProtocolDebugLoading ? "Loading gateway protocol..." : "Gateway protocol")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                    Spacer()
                    Button(action: refreshProtocolDebug) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .black))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                }

                if let protocolDebugError {
                    Text(protocolDebugError)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MagicPalette.warningAmber)
                }

                if let protocolDebug {
                    debugGrid([
                        ("Debug game", protocolDebug.gameId ?? "none"),
                        ("Debug source", protocolDebug.source ?? "none"),
                        ("Debug revision", protocolDebug.bridgeRevision.map(String.init) ?? "n/a"),
                        ("Debug cycle", protocolDebug.xmageCycle.map(String.init) ?? "n/a"),
                        ("Debug pending", protocolDebug.pendingStatus ?? "none"),
                        ("Debug priority", protocolDebug.priorityPlayerId ?? "none"),
                        ("Debug waiting", protocolDebug.waitingOnPlayerId ?? "none"),
                        ("Debug legal", protocolDebug.legalActionCount.map(String.init) ?? "n/a"),
                        ("Debug types", protocolDebug.legalActionTypes?.joined(separator: ", ") ?? "none"),
                        ("Debug prompt", protocolDebug.promptSummary?.id ?? "none"),
                        ("Debug method", protocolDebug.promptSummary?.method ?? "none"),
                        ("Debug response", protocolDebug.promptSummary?.responseKind ?? "none"),
                        ("Debug command", protocolDebug.promptSummary?.responseCommandType ?? "none")
                    ])
                }

                debugGrid([
                    ("Kind", presentation?.kind.rawValue ?? "none"),
                    ("Method", prompt?.method ?? "none"),
                    ("Response", prompt?.responseKind ?? "none"),
                    ("Command", prompt?.responseCommand?.type ?? "none"),
                    ("Prompt ID", prompt?.id ?? "none"),
                    ("Message", prompt?.messageId.description ?? "none"),
                    ("Revision", snapshot.bridgeRevision.map(String.init) ?? "n/a"),
                    ("Cycle", snapshot.xmageCycle.map(String.init) ?? "n/a"),
                    ("Pending", snapshot.pendingStatus ?? "none"),
                    ("Priority", snapshot.priorityPlayerId ?? "none"),
                    ("Waiting", snapshot.waitingOnPlayerId ?? "none"),
                    ("Legal", "\(snapshot.legalActions?.count ?? 0)"),
                    ("WS", liveUpdateStatus)
                ])

                if let lastActionRejection {
                    PromptPanelSection(title: "Last rejection", detail: lastActionRejection.category.rawValue, isHighlighted: true) {
                        Text(lastActionRejection.message)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MagicPalette.warningAmber)
                    }
                }

                if let actions = snapshot.legalActions, !actions.isEmpty {
                    PromptPanelSection(title: "Legal action types", detail: "\(actions.count)", isHighlighted: false) {
                        Text(Array(Set(actions.map(\.type))).sorted().joined(separator: ", "))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
            .padding(18)
        }
        .background(BattlefieldSurface().ignoresSafeArea())
    }

    private func debugGrid(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.0.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .frame(width: 76, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .background(MagicPalette.iron.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.35), lineWidth: 1))
    }
}

struct GameManagementMenu: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gameConcede) private var gameConcede
    @Environment(\.tavernBoard) private var tavern
    @State private var confirmingConcede = false
    @State private var showHowToPlay = false
    let snapshot: GameSnapshot
    let concedeAction: LegalAction?
    let runAction: (LegalAction) -> Void
    @Binding var portraitModeEnabled: Bool
    let openPromptInspector: () -> Void
    let confirmStartNew: () -> Void
    let confirmQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
            Text("Game Menu")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(MagicPalette.antiqueGold)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("board.menu.done")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            BoardAppearancePicker()
            PortraitModeToggle(isOn: $portraitModeEnabled)
            FollowTurnsToggle()
            BoardEffectsPicker()

            Button { showHowToPlay = true } label: {
                Label(HowToPlayText.title, systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactActionButtonStyle(isPrimary: false))
            .accessibilityIdentifier("board.menu.howToPlay")

            if snapshot.isSpectating {
                Label("You’re out of this game and watching the others play. Quit when you’re done.", systemImage: "eye.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.8))
                    .accessibilityIdentifier("board.menu.spectating")
            }
            HStack(spacing: 10) {
                Button {
                    confirmingConcede = true
                } label: {
                    Label("Concede", systemImage: "flag.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactActionButtonStyle(isDanger: true, isPrimary: false))
                .disabled(!canConcede)
                .accessibilityIdentifier("board.menu.concede")

                Button(action: confirmStartNew) {
                    Label("Start New", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactActionButtonStyle(isPrimary: true))

                Button(action: confirmQuit) {
                    Label("Quit", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                .accessibilityIdentifier("board.menu.quit")
            }

            Button(action: openPromptInspector) {
                Label("Prompt Debug", systemImage: "ladybug.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactActionButtonStyle(isPrimary: false))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("board.menu.scroll")
        }
        .background(BattlefieldSurface().ignoresSafeArea())
        .sheet(isPresented: $showHowToPlay) { HowToPlayView() }
        .tavernConfirmation(
            active: tavern,
            title: "Concede this game?",
            message: snapshot.remainingOpponents.count > 1
                ? "You leave the game and can keep watching the others play it out."
                : "Your opponent wins this game.",
            isPresented: $confirmingConcede,
            actions: [TavernDialogAction(title: "Concede", destructive: true) {
                dismiss()
                if let gameConcede { gameConcede.concede() } else if let concedeAction { runAction(concedeAction) }
            }],
            cancelTitle: "Keep Playing"
        )
    }

    /// Engine concede on device; XMage's own action on hosted games. Never after you're out.
    private var canConcede: Bool {
        !snapshot.isCompleted && snapshot.human?.isOut != true && (gameConcede != nil || concedeAction != nil)
    }
}

struct PhaseChip: View {
    let label: String
    let phase: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(active ? .black.opacity(0.7) : .white.opacity(0.55))
            Text(phase.compactPhaseTitle)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(active ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? MagicPalette.antiqueGold : MagicPalette.iron.opacity(0.50), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? MagicPalette.brass.opacity(0.55) : MagicPalette.borderBronze.opacity(0.20)))
    }
}

/// Holographic sheen on the held card image only (never its rules text): a slow
/// glint sweep with a slight tilt. Full board effects without Reduce Motion only;
/// the timeline exists only while the inspector is on screen.
struct InspectionFoil: ViewModifier {
    let size: CGSize
    @AppStorage(BoardFXLevel.key) private var level = BoardFXLevel.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        if BoardFXLevel(rawValue: level) == .full && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                content
                    .colorEffect(ShaderLibrary.mmFoil(.float2(size), .float(t * 0.3), .float(0.55)))
                    .rotation3DEffect(.degrees(sin(t * 0.9) * 3), axis: (x: 0.3, y: 1, z: 0), perspective: 0.5)
            }
        } else {
            content
        }
    }
}
