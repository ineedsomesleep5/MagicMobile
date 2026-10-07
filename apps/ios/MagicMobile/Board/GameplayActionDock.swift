import SwiftUI
import PhotosUI
import UIKit

enum LandscapeActionDockLayout {
    static let horizontalPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 4
    static let controlSpacing: CGFloat = 4
    static let primaryLineLimit = 1
    static func sidebarWidth(hasStack: Bool) -> CGFloat { hasStack ? 176 : 160 }
}

struct GameplayActionDock: View {
    @Environment(\.nativeTurnControl) private var nativeTurnControl
    @Environment(\.startingRollVisible) private var startingRollVisible
    let snapshot: GameSnapshot
    let passAction: LegalAction?
    let yieldActions: [LegalAction]
    let pendingActionId: String?
    var compact = false
    var landscapeSidebar = false
    var horizontal = false
    /// Tavern table only: render just one part of the horizontal dock.
    var tavernPart: TavernDockPart? = nil
    let openPromptDetails: () -> Void
    let openLog: () -> Void
    let openSettings: () -> Void
    let runAction: (LegalAction) -> Void

    private var promptActions: [LegalAction] {
        CompactPromptPopup.compactLegalPromptActions(in: snapshot)
    }

    /// No "Open Choice" while the starting roll covers the board: the roll answers that prompt.
    private var hasPromptDecision: Bool {
        !startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil)
    }

    private var model: GameActionDockModel {
        GameActionDockModel.make(
            snapshot: snapshot,
            passAction: passAction,
            promptActions: promptActions,
            decisionRequired: hasPromptDecision,
            pendingActionId: pendingActionId
        )
    }

    enum TavernDockPart { case skip, menu, primary }

    var body: some View {
        if let tavernPart {
            switch tavernPart {
            case .skip: secondaryControl.frame(width: 44, height: 44)
            case .menu: controlsMenu
            case .primary:
                if TavernPassAssets.flips {
                    TavernPassStage(enabled: model.isPrimaryEnabled, turnsOnTap: model.primaryAction != nil) { primaryButton }
                } else {
                    primaryButton
                }
            }
        } else if horizontal {
            HStack(spacing: 6) {
                secondaryControl.frame(width: 44)
                controlsMenu
                primaryButton
            }
        } else {
            VStack(spacing: landscapeSidebar ? LandscapeActionDockLayout.controlSpacing : 8) {
                primaryButton
                HStack(spacing: 6) { secondaryControl; controlsMenu }
            }
        }
    }

    private var primaryButton: some View {
        VStack(spacing: 2) {
        Button {
                    if let primaryAction = model.primaryAction {
                        runAction(primaryAction)
                    } else if model.mode == .prompt {
                        openPromptDetails()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if tavernPart == nil {
                            Image(systemName: model.mode == .prompt ? "sparkles" : "forward.end.fill")
                                .font(.system(size: compact ? 10 : 11, weight: .black))
                        }
                        Text(model.primaryTitle)
                            // The tavern's ring plate engraves one small line.
                            .font(tavernPart != nil ? .system(size: 9, weight: .heavy, design: .serif)
                                                    : .system(size: compact ? 13 : 15, weight: .bold, design: .serif))
                            .lineLimit(tavernPart != nil ? 1 : (landscapeSidebar ? LandscapeActionDockLayout.primaryLineLimit : 2))
                            .minimumScaleFactor(0.62)
                    }
                    .frame(maxWidth: .infinity)
                }
                .modifier(PrimaryDockButtonStyle(tavern: tavernPart == .primary, showsTitle: !isPlainPass && model.isPrimaryEnabled))
                .disabled(!model.isPrimaryEnabled)
                .accessibilityLabel(Text(model.primaryTitle))
                .accessibilityIdentifier("board.action.primary")
                .accessibilityHint(showsPriorityHelp ? GameplayActionPresentation.priorityHint(hasStack: hasStackForPriority) : "")
                // A finger-down on Pass must not become a new prompt's action
                // if an engine update replaces this control before finger-up.
                .id("\(model.primaryAction?.id ?? "none"):\(snapshot.promptEnvelopeV2?.id ?? "none"):\(model.primaryAction?.messageId ?? snapshot.promptEnvelopeV2?.messageId ?? -1)")
            // The landscape sidebar keeps its height for the stack; the hint stays in VoiceOver.
            if showsPriorityHelp && !landscapeSidebar && tavernPart == nil {
                Text(GameplayActionPresentation.priorityDetail(hasStack: hasStackForPriority))
                    .font(.caption2)
                    .foregroundStyle(MagicPalette.parchment.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Passing priority is the hourglass alone on the tavern table (and waiting is its dim
    /// face), so neither shows a title.
    private var isPlainPass: Bool {
        model.mode == .priority && model.primaryAction?.type == "pass_priority"
    }

    private var showsPriorityHelp: Bool {
        model.mode == .priority && model.isPrimaryEnabled && model.primaryAction?.type == "pass_priority"
    }

    private var hasStackForPriority: Bool {
        !snapshot.stackTopFirst.isEmpty || snapshot.players.contains { !$0.zones.stack.isEmpty }
    }

    @ViewBuilder private var controlsMenu: some View {
        if tavernPart != nil && TavernUIKit.available {
            tavernControlsMenu
        } else {
            systemControlsMenu
        }
    }

    /// The tavern's controls ring opens a leather pop-over instead of the system menu.
    private var tavernControlsMenu: some View {
        TavernMenu(arrowEdge: .bottom) {
            if model.mode == .prompt {
                ForEach(model.promptActions.filter { $0.id != model.primaryAction?.id }) { action in
                    TavernMenuItem(title: action.label) { runAction(action) }
                        .disabled(pendingActionId != nil)
                }
                TavernMenuItem(title: "All Choices", systemImage: "list.bullet.rectangle.portrait", action: openPromptDetails)
                TavernMenuDivider()
            }
            TavernMenuItem(title: "Game Log", systemImage: "list.bullet.rectangle", action: openLog)
            if snapshot.source == "xmage-ondevice", model.mode != .prompt {
                TavernMenuItem(title: "More actions", systemImage: "ellipsis", action: openPromptDetails)
            }
            TavernMenuItem(title: "Game Settings", systemImage: "gearshape.fill", action: openSettings)
        } label: {
            Image(systemName: model.mode == .prompt && model.promptActions.count > 1 ? "ellipsis.circle.fill" : "slider.horizontal.3")
                .font(.system(size: 14, weight: .black))
        }
        .buttonStyle(GameplayDockMenuButtonStyle())
        .accessibilityLabel(model.mode == .prompt && model.promptActions.count > 1 ? "More choices and game controls" : "Game controls")
    }

    private var systemControlsMenu: some View {
        Menu {
                    if model.mode == .prompt {
                        ForEach(model.promptActions.filter { $0.id != model.primaryAction?.id }) { action in
                            Button(action.label) {
                                runAction(action)
                            }
                            .disabled(pendingActionId != nil)
                        }
                        Button("All Choices", action: openPromptDetails)
                        Divider()
                    }
                    Button(action: openLog) {
                        Label("Game Log", systemImage: "list.bullet.rectangle")
                    }
                    if snapshot.source == "xmage-ondevice", model.mode != .prompt {
                        Button("More actions", action: openPromptDetails)
                    }
                    Button(action: openSettings) {
                        Label("Game Settings", systemImage: "gearshape.fill")
                    }
                } label: {
                    Image(systemName: model.mode == .prompt && model.promptActions.count > 1 ? "ellipsis.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 14, weight: .black))
                }
                .buttonStyle(GameplayDockMenuButtonStyle())
                .accessibilityLabel(model.mode == .prompt && model.promptActions.count > 1 ? "More choices and game controls" : "Game controls")
    }

    @ViewBuilder private var secondaryControl: some View {
            if let control = nativeTurnControl {
                if control.isAutoPassing {
                    Button(action: control.stop) {
                        secondaryLabel("Stop skipping", icon: "stop.fill")
                    }
                    .modifier(DockSecondaryButtonStyle(circular: horizontal))
                    .accessibilityLabel("Stop skipping")
                    .accessibilityHint(control.status ?? "Stops future automatic passes")
                } else if tavernPart != nil && TavernUIKit.available {
                    TavernMenu(arrowEdge: .bottom) {
                        TavernMenuItem(title: "End turn — skip stack responses", action: control.skipResponses)
                            .disabled(!control.canSkipResponses)
                        TavernMenuItem(title: "Skip to my turn — skip stack responses", action: control.skipToMyTurn)
                            .disabled(!control.canSkipToMyTurn)
                        TavernMenuItem(title: "End turn — stop for responses", action: control.endTurn)
                            .disabled(!control.canEndTurn)
                    } label: {
                        secondaryLabel("Skip…", icon: "forward.end")
                    }
                    .modifier(DockSecondaryButtonStyle(circular: horizontal))
                    .disabled(!control.canEndTurn && !control.canSkipResponses && !control.canSkipToMyTurn)
                    .accessibilityLabel("Skip options")
                    .accessibilityHint("Choose how long to skip responses. Required choices always stop skipping.")
                } else {
                    Menu {
                        Button("End turn — skip stack responses", action: control.skipResponses)
                            .disabled(!control.canSkipResponses)
                        Button("Skip to my turn — skip stack responses", action: control.skipToMyTurn)
                            .disabled(!control.canSkipToMyTurn)
                        Button("End turn — stop for responses", action: control.endTurn)
                            .disabled(!control.canEndTurn)
                    } label: {
                        secondaryLabel("Skip…", icon: "forward.end")
                    }
                    .modifier(DockSecondaryButtonStyle(circular: horizontal))
                    .disabled(!control.canEndTurn && !control.canSkipResponses && !control.canSkipToMyTurn)
                    .accessibilityLabel("Skip options")
                    .accessibilityHint("Choose how long to skip responses. Required choices always stop skipping.")
                }
            } else if model.showsPromptDetails {
                Button(action: openPromptDetails) {
                    secondaryLabel("Choices", icon: "list.bullet.rectangle.portrait")
                }
                .modifier(DockSecondaryButtonStyle(circular: horizontal))
                .accessibilityLabel("View all choices")
            } else {
                YieldActionsControl(
                    snapshot: snapshot,
                    actions: yieldActions,
                    fontSize: compact ? 8 : 10,
                    iconOnly: horizontal,
                    runAction: runAction
                )
            }
    }

    private func secondaryLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if !horizontal { Text(title).lineLimit(2) }
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// The primary action: the orange capsule, or the brass hourglass on the tavern table.
struct PrimaryDockButtonStyle: ViewModifier {
    let tavern: Bool
    var showsTitle = true
    func body(content: Content) -> some View {
        if tavern { content.buttonStyle(TavernPrimaryButtonStyle(showsTitle: showsTitle)) }
        else { content.buttonStyle(GameplayDockButtonStyle(isPrimary: true)) }
    }
}

struct GameplayDockButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressSound(.uiTap, isPressed: configuration.isPressed)
            .foregroundStyle(isPrimary ? Color.white : MagicPalette.parchment)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                LinearGradient(
                    colors: backgroundColors(isPressed: configuration.isPressed),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isPrimary ? Color(red: 1, green: 0.79, blue: 0.39) : MagicPalette.parchment.opacity(0.25), lineWidth: isPrimary ? 1.5 : 1))
            .shadow(color: isPrimary && isEnabled ? Color.orange.opacity(0.35) : .clear, radius: 8, y: 2)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundColors(isPressed: Bool) -> [Color] {
        if isPrimary {
            return isPressed
                ? [Color(red: 0.66, green: 0.28, blue: 0.08), Color(red: 0.40, green: 0.12, blue: 0.03)]
                : [Color(red: 0.78, green: 0.31, blue: 0.065), Color(red: 0.64, green: 0.20, blue: 0.05)]
        }
        return [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.76)]
    }
}

/// The portrait dock shows its secondary control as an icon beside the settings button;
/// give it the same 44pt circle instead of a wide capsule spilling past its slot. Applied
/// as real button styles so each keeps its own environment (enabled state, Reduce Motion).
struct DockSecondaryButtonStyle: ViewModifier {
    let circular: Bool
    func body(content: Content) -> some View {
        if circular { content.buttonStyle(GameplayDockMenuButtonStyle()) }
        else { content.buttonStyle(GameplayDockButtonStyle(isPrimary: false)) }
    }
}

struct CompactOrCircleButtonStyle: ViewModifier {
    let circular: Bool
    func body(content: Content) -> some View {
        if circular { content.buttonStyle(GameplayDockMenuButtonStyle()) }
        else { content.buttonStyle(CompactActionButtonStyle(isPrimary: false)) }
    }
}

struct GameplayDockMenuButtonStyle: ButtonStyle {
    @Environment(\.tavernBoard) private var tavern
    func makeBody(configuration: Configuration) -> some View {
        if tavern {
            configuration.label.modifier(TavernRingLabel(pressed: configuration.isPressed))
        } else {
            classic(configuration)
        }
    }

    private func classic(_ configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MagicPalette.parchment)
            .frame(width: 44, height: 44)
            .background(configuration.isPressed ? MagicPalette.brass.opacity(0.62) : MagicPalette.iron.opacity(0.84), in: Circle())
            .overlay(Circle().stroke(MagicPalette.parchment.opacity(0.25), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct PortraitBottomCommandBar: View {
    let humanName: String
    let human: PlayerGameState
    let opponentId: String
    let manaPool: ManaPool?
    let passAction: LegalAction?
    let yieldActions: [LegalAction]
    let pendingActionId: String?
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let openLog: () -> Void
    let openSettings: () -> Void
    let openPromptDetails: () -> Void
    let viewZone: (String, [ZoneCard]) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    /// Opens the stack sheet from the tavern's stack tray.
    var openStack: (() -> Void)? = nil
    @State private var isStackOpen = false
    @State private var isEmotePickerOpen = false
    @Environment(\.emoteCenter) private var emoteCenter
    @Environment(\.tavernBoard) private var tavern
    @Environment(\.tavernCanvas) private var tavernCanvas
    @Environment(\.boardAnswerActions) private var answerActions

    /// "Resolve all": one tap passes until the stack you're looking at has resolved (XMage's F10). It stops by itself if an
    /// opponent adds something, and every choice still comes to you. Shown with two or more objects on the stack.
    private var resolveStackCommand: GameCommand? {
        let stackCount = snapshot.xmage?.stack.count ?? human.zones.stack.count
        guard stackCount >= 2, pendingActionId == nil, answerActions.supported.contains("passUntilStackResolved"),
              let passAction, passAction.type == "pass_priority" else { return nil }
        var command = GameCommand(type: "pass_priority", gameId: snapshot.id, playerId: passAction.playerId,
                                  promptId: passAction.promptId, messageId: passAction.messageId,
                                  expectedBridgeRevision: snapshot.bridgeRevision)
        command.answerActions = ["passUntilStackResolved"]
        return command
    }

    private func resolveStackButton(_ command: GameCommand) -> some View {
        ResolveStackButton { runCommand(command, "Resolve the stack", "resolve-stack-\(command.promptId ?? "")") }
    }

    var body: some View {
        GeometryReader { _ in
            Group {
                if tavern { tavernLayout } else { classicLayout }
            }
            .padding(.horizontal, 4)
            .onAppear {
                #if DEBUG
                isStackOpen = snapshot.id == "design-preview-stack-response-prompt"
                #endif
            }
            .sheet(isPresented: $isStackOpen) {
                BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
            }
            .onChange(of: isStackOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
        }
    }

    private var classicLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                PlayerZoneMenu(player: human, viewZone: viewZone, snapshot: snapshot, pendingActionID: pendingActionId)
                // The revealed top of your library, next to your zones.
                if let top = human.zones.library.first {
                    TopOfLibraryCard(card: top, playable: GameplayAffordances.castableZones(player: human, snapshot: snapshot, pendingActionID: pendingActionId).contains(.library),
                                     owner: "your", height: 40) { viewZone("Top of your library", [top]) }
                }
                BoardPlayerEffects(player: human, attachments: BattlefieldAttachments.enchanting(playerID: human.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: viewZone)
                ScrollView(.horizontal, showsIndicators: false) {
                    ManaPoolHUD(manaPool: manaPool, compact: true,
                        payableSymbols: GameplayAffordances.floatingManaSymbols(in: snapshot, pendingActionID: pendingActionId),
                        payMana: { symbol in
                            if pendingActionId == nil, let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                                runCommand(command, "Spend floating {\(symbol)}", "floating-\(snapshot.promptEnvelopeV2?.id ?? "")-\(symbol)")
                            }
                        })
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Floating mana; swipe to view all colors")
                BoardStackTray(objects: snapshot.stackTopFirst,
                               count: snapshot.xmage?.stack.count ?? human.zones.stack.count) { isStackOpen = true }
                if let resolveStackCommand { resolveStackButton(resolveStackCommand) }
                if let emoteCenter { TableChatButton(center: emoteCenter) }
            }
            HStack(spacing: 8) {
                lifeOrb
                dock(nil).frame(maxWidth: .infinity)
            }
        }
    }

    /// Walnut Tavern: every control sits on a socket of the table plate (TavernDesign):
    /// your commander medallion (it opens your zones), the mana gems in the rail, the
    /// hourglass with Skip and the controls menu as small rings.
    private var tavernLayout: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if let canvas = tavernCanvas {
                let sockets = TavernSockets.current(canvas)
                let pass = sockets.passButton
                ZStack {
                    tavernMedallion(canvas: canvas)
                        .tavernPosition(sockets.lifeMedallion, canvas: canvas, origin: origin)
                    ForEach(Array(tavernManaValues.enumerated()), id: \.offset) { index, value in
                        tavernManaGem(symbol: value.0, count: value.1, canvas: canvas)
                            .tavernPosition(CGPoint(x: sockets.manaSocketXs[index], y: sockets.manaSocketY),
                                            canvas: canvas, origin: origin)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Floating mana")
                    dock(.primary)
                        .tavernPosition(pass, canvas: canvas, origin: origin)
                    // Skip and the controls ring orbit the hourglass's lower-left on one arc
                    // (72 pt out): Skip at its left, controls further round below it.
                    dock(.skip)
                        .scaleEffect(canvas.tavernControlScale)
                        .tavernPosition(sockets.skip, canvas: canvas, origin: origin)
                    dock(.menu)
                        .scaleEffect(canvas.tavernControlScale)
                        .tavernPosition(sockets.menu, canvas: canvas, origin: origin)
                    let stackCount = snapshot.xmage?.stack.count ?? human.zones.stack.count
                    if stackCount > 0, let openStack {
                        TavernStackTray(count: stackCount, topName: snapshot.stackTopFirst.first?.name, open: openStack,
                                        width: sockets.canvas.width > sockets.canvas.height ? 106 : 124,
                                        topCard: snapshot.stackTopFirst.first?.displaySourceCard)
                            // "Resolve all" hangs above the tray's trailing edge, clear of the hourglass.
                            .overlay(alignment: .topTrailing) {
                                if let resolveStackCommand {
                                    resolveStackButton(resolveStackCommand).fixedSize().offset(x: 6, y: -40)
                                }
                            }
                            .scaleEffect(canvas.tavernControlScale)
                            .tavernPosition(sockets.stackTray, canvas: canvas, origin: origin)
                    }
                    // Counters and attached cards live in the medallion's pop-over; poison and
                    // commander damage also show here at a glance.
                    HStack(spacing: 6) {
                        TavernStatusGlance(summary: PlayerStatusSummary(player: human, snapshot: snapshot))
                        if let emoteCenter { TableChatButton(center: emoteCenter) }
                    }
                    .scaleEffect(canvas.tavernControlScale)
                    .tavernPosition(sockets.chat,
                                    canvas: canvas, origin: origin)
                }
            }
        }
    }

    private var tavernManaValues: [(String, Int)] {
        [("W", manaPool?.W ?? 0), ("U", manaPool?.U ?? 0), ("B", manaPool?.B ?? 0),
         ("R", manaPool?.R ?? 0), ("G", manaPool?.G ?? 0), ("C", manaPool?.C ?? 0)]
    }

    /// A mana gem centred on its rail socket; a payable gem is a button, exactly like the
    /// classic mana row. Gems are a little narrower than the socket pitch so they never touch.
    @ViewBuilder
    private func tavernManaGem(symbol: String, count: Int, canvas: CGSize) -> some View {
        let payable = GameplayAffordances.floatingManaSymbols(in: snapshot, pendingActionID: pendingActionId).contains(symbol)
        let gem = TavernManaGemFace(symbol: symbol, count: count, payable: payable, diameter: canvas.tavernLength(26) * canvas.tavernControlScale)
        if payable {
            Button {
                if pendingActionId == nil, let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                    runCommand(command, "Spend floating {\(symbol)}", "floating-\(snapshot.promptEnvelopeV2?.id ?? "")-\(symbol)")
                }
            } label: { gem.frame(minWidth: 44, minHeight: 44) }
            .buttonStyle(.plain)
            .accessibilityLabel("Spend floating \(symbol) mana, \(count) available")
            .accessibilityIdentifier("board.mana.spend.\(symbol)")
        } else {
            gem.accessibilityLabel("\(symbol) mana, \(count)")
        }
    }

    /// Your commander's portrait in the life socket; it opens your zones like the old grid button.
    private func tavernMedallion(canvas: CGSize) -> some View {
        let diameter = canvas.tavernLength(TavernSockets.current(canvas).lifeHoleRadius * 2)
        let castable = GameplayAffordances.castableZones(player: human, snapshot: snapshot, pendingActionID: pendingActionId)
        let commanderReady = !castable.isEmpty
        return PlayerZoneMenu(
            player: human, viewZone: viewZone, snapshot: snapshot, pendingActionID: pendingActionId,
            customLabel: AnyView(
                TavernMedallion(diameter: diameter, life: human.life,
                                active: snapshot.isViewer(snapshot.activePlayerId), commanderReady: commanderReady) {
                    PlayerPortrait(player: human, size: diameter)
                }
                .frame(width: diameter + 8, height: diameter + 8)
            ),
            accessibilityOverride: ("Your life: \(human.life)\(Self.castableDescription(castable))", "board.lifeOrb")
        )
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [TavernSeatAnchor.bottom: $0] }
        // The revealed top of your library (Conspicuous Snoop, Future Sight, Courser of Kruphix…) beside your portrait.
        .overlay(alignment: .topTrailing) {
            if let top = human.zones.library.first {
                TopOfLibraryCard(card: top, playable: castable.contains(.library), owner: "your", height: diameter * 0.72) {
                    viewZone("Top of your library", [top])
                }
                .offset(x: diameter * 0.62, y: -diameter * 0.05)
            }
        }
        .overlay(alignment: .top) {
            if let emoteCenter {
                EmoteBubbleSlot(center: emoteCenter, playerID: human.playerId)
                    .fixedSize()
                    .offset(y: -56)
            }
        }
    }

    /// "commander cast available" and the rest, for VoiceOver.
    static func castableDescription(_ zones: Set<BoardZoneReference.PlayerZone>) -> String {
        let names: [(BoardZoneReference.PlayerZone, String)] = [(.command, "commander"), (.graveyard, "graveyard"), (.exile, "exile"), (.library, "top of library")]
        let ready = names.filter { zones.contains($0.0) }.map(\.1)
        return ready.isEmpty ? "" : ", cast available from \(ready.joined(separator: ", "))"
    }

    private var lifeOrb: some View {
        Button {
            if emoteCenter != nil { isEmotePickerOpen = true }
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "heart.fill").font(.system(size: 9))
                    .foregroundStyle(MagicPalette.antiqueGold)
                BoardLifeTotal(life: human.life).id(human.playerId)
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .frame(width: 52, height: 52)
            .background(.black.opacity(0.85), in: Circle())
            .overlay(Circle().strokeBorder(MagicPalette.antiqueGold.opacity(snapshot.isViewer(snapshot.activePlayerId) ? 1 : 0.65),
                                           lineWidth: snapshot.isViewer(snapshot.activePlayerId) ? 3 : 2))
            .shadow(color: MagicPalette.antiqueGold.opacity(snapshot.isViewer(snapshot.activePlayerId) ? 0.7 : 0), radius: 10)
            .animation(.easeInOut(duration: 0.35), value: snapshot.activePlayerId)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if let emoteCenter {
                EmoteBubbleSlot(center: emoteCenter, playerID: human.playerId)
                    .fixedSize()
                    .offset(y: -62)
            }
        }
        .popover(isPresented: $isEmotePickerOpen) {
            if let emoteCenter {
                EmotePicker(center: emoteCenter, snapshot: snapshot) { isEmotePickerOpen = false }
                    .presentationCompactAdaptation(.popover)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your life: \(human.life)")
        .accessibilityHint(emoteCenter == nil ? "" : "Opens quick chat")
        .accessibilityAddTraits(emoteCenter == nil ? [] : .isButton)
        .accessibilityIdentifier("board.lifeOrb")
    }

    private func dock(_ part: GameplayActionDock.TavernDockPart?) -> some View {
                GameplayActionDock(
                        snapshot: snapshot,
                        passAction: passAction,
                        yieldActions: yieldActions,
                        pendingActionId: pendingActionId,
                        horizontal: true,
                    tavernPart: part,
                        openPromptDetails: openPromptDetails,
                        openLog: openLog,
                        openSettings: openSettings,
                        runAction: runAction
                    )
    }
}

struct BoardStackInspector: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeTurnControl) private var turnControl
    @Environment(\.tavernBoard) private var tavern
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            HStack {
                if tavern && TavernUIKit.available {
                    TavernPanelTitle(text: "Stack")
                } else {
                    Text("Stack").font(.headline)
                }
                Spacer()
                if let turnControl, turnControl.isAutoPassing {
                    Button("Stop skipping", action: turnControl.stop)
                        .frame(minHeight: 44)
                        .tavernPlaque(tavern, kind: .danger)
                }
                Button("Done") { inspectedCard = nil; dismiss() }
                    .frame(minHeight: 44)
                    .tavernPlaque(tavern, kind: .secondary)
                    .accessibilityIdentifier("board.stack.done")
            }
            PortraitStackLane(snapshot: snapshot, humanStack: snapshot.human?.zones.stack ?? [],
                              legalActions: snapshot.legalActions ?? [],
                              selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                              horizontal: geometry.size.width > geometry.size.height)
                .overlay {
                    if let inspectedCard {
                        CardInspector(card: inspectedCard)
                            .overlay(alignment: .topTrailing) {
                                Button("Close card") { self.inspectedCard = nil }
                                    .frame(minHeight: 44).padding(8)
                            }
                            .inspectionTouchPassthrough()
                    }
                }
        }
        .padding(12)
        }
        .presentationDetents([.height(460), .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }
}

/// Only the engine's authorized zone projection is ever presented.
struct PlayerZoneMenu: View {
    @Environment(\.boardZoneInspectionAction) private var inspectZone
    let player: PlayerGameState
    let viewZone: (String, [ZoneCard]) -> Void
    var snapshot: GameSnapshot? = nil
    var pendingActionID: String? = nil
    /// Tavern table: the player's medallion opens the zones instead of the grid button.
    var customLabel: AnyView? = nil
    var extraItems: AnyView? = nil
    var accessibilityOverride: (label: String, identifier: String)? = nil
    /// The tavern pop-over's arrow: opponents at the top of the table open downward.
    var menuArrowEdge: Edge = .bottom
    /// The game, for the pop-over's status (counters, commander damage, attached cards) when
    /// `snapshot` is left out to keep the shared zone rows off an opponent's menu.
    var statusSnapshot: GameSnapshot? = nil
    /// In a pod, the opponents the pop-over can swap between.
    var swapOpponents: [PlayerGameState] = []
    var swap: ((String) -> Void)? = nil

    private var commanderReady: Bool {
        snapshot.map { GameplayAffordances.commanderCastAvailable(player: player, snapshot: $0, pendingActionID: pendingActionID) } ?? false
    }
    /// Zones with a card you can play now (graveyard, exile, the revealed top card), shown on their rows.
    private var castable: Set<BoardZoneReference.PlayerZone> {
        snapshot.map { GameplayAffordances.castableZones(player: player, snapshot: $0, pendingActionID: pendingActionID) } ?? []
    }
    private func row(_ zone: BoardZoneReference.PlayerZone, _ name: String, _ count: Int) -> String {
        castable.contains(zone) ? "\(name) · Cast available" : "\(name) · \(count)"
    }
    private var libraryRow: String {
        if castable.contains(.library) { return "Library · Top card playable" }
        return player.zones.library.isEmpty ? "Library · \(player.zones.visibleLibraryCount)" : "Library · Top card revealed"
    }

    var body: some View {
        if customLabel != nil && TavernUIKit.available {
            tavernMenu
        } else {
            systemMenu
        }
    }

    /// The tavern table's medallions open their zones in a leather pop-over.
    private var tavernMenu: some View {
        TavernMenu(arrowEdge: menuArrowEdge) {
            let game = statusSnapshot ?? snapshot
            TavernPlayerStatusPanel(name: game?.playerLabel(player.playerId) ?? player.displayName ?? "Player",
                                    summary: PlayerStatusSummary(player: player, snapshot: game), inspect: viewZone)
            TavernMenuItem(title: commanderReady ? "Command · Cast available" : "Command · \(player.zones.command.count)",
                           systemImage: "crown") { open(.command, player.zones.command) }
            TavernMenuItem(title: row(.graveyard, "Graveyard", player.zones.graveyard.count), systemImage: "leaf") { open(.graveyard, player.zones.graveyard) }
            TavernMenuItem(title: row(.exile, "Exile", player.zones.exile.count), systemImage: "sparkles") { open(.exile, player.zones.exile) }
            TavernMenuItem(title: "Hand · \(player.zones.visibleHandCount)", systemImage: "hand.raised") { open(.hand, player.zones.hand) }
            TavernMenuItem(title: libraryRow, systemImage: "books.vertical") { open(.library, player.zones.library) }
            TavernMenuItem(title: "Battlefield · \(player.zones.battlefield.count)", systemImage: "square.grid.2x2") { open(.battlefield, player.zones.battlefield) }
            if let snapshot {
                let references = BoardZoneReference.namedReferences(in: snapshot)
                if !references.isEmpty { TavernMenuDivider() }
                ForEach(references, id: \.self) { reference in
                    TavernMenuItem(title: "\(reference.title(in: snapshot)) · \(reference.cards(in: snapshot).count)") {
                        if let inspectZone { inspectZone(reference) }
                        else { viewZone(reference.title(in: snapshot), reference.cards(in: snapshot)) }
                    }
                }
            }
            if let extraItems {
                TavernMenuDivider()
                extraItems
            }
            if swapOpponents.count > 1, let swap {
                TavernOpponentSwap(opponents: swapOpponents, current: player.playerId,
                                   label: { game?.playerLabel($0) ?? "Opponent" }, select: swap)
            }
        } label: {
            if let customLabel { customLabel } else { defaultLabel }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityOverride?.label
            ?? "\(player.displayName ?? player.playerId) zones\(commanderReady ? ", commander cast available" : PortraitBottomCommandBar.castableDescription(castable))")
        .accessibilityIdentifier(accessibilityOverride?.identifier ?? "board.zones.\(player.playerId)")
    }

    private var systemMenu: some View {
        Menu {
            Button(commanderReady ? "Command · Cast available" : "Command · \(player.zones.command.count)") { open(.command, player.zones.command) }
            Button(row(.graveyard, "Graveyard", player.zones.graveyard.count)) { open(.graveyard, player.zones.graveyard) }
            Button(row(.exile, "Exile", player.zones.exile.count)) { open(.exile, player.zones.exile) }
            Button("Hand · \(player.zones.visibleHandCount)") { open(.hand, player.zones.hand) }
            Button(libraryRow) { open(.library, player.zones.library) }
            Button("Battlefield · \(player.zones.battlefield.count)") { open(.battlefield, player.zones.battlefield) }
            if let snapshot {
                Divider()
                ForEach(BoardZoneReference.namedReferences(in: snapshot), id: \.self) { reference in
                    Button("\(reference.title(in: snapshot)) · \(reference.cards(in: snapshot).count)") {
                        if let inspectZone { inspectZone(reference) }
                        else { viewZone(reference.title(in: snapshot), reference.cards(in: snapshot)) }
                    }
                }
            }
            if let extraItems {
                Divider()
                extraItems
            }
        } label: {
            if let customLabel { customLabel } else { defaultLabel }
        }
        .accessibilityLabel(accessibilityOverride?.label
            ?? "\(player.displayName ?? player.playerId) zones\(commanderReady ? ", commander cast available" : PortraitBottomCommandBar.castableDescription(castable))")
        .accessibilityIdentifier(accessibilityOverride?.identifier ?? "board.zones.\(player.playerId)")
    }

    private var defaultLabel: some View {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                // Glows whenever a card can be played from these zones: the commander, the graveyard, exile, the top card.
                .foregroundStyle(!castable.isEmpty ? .white : MagicPalette.parchment)
                .background(!castable.isEmpty ? MagicPalette.antiqueGold.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(!castable.isEmpty ? .white.opacity(0.9) : .clear, lineWidth: 1.5))
                .shadow(color: !castable.isEmpty ? MagicPalette.antiqueGold.opacity(0.75) : .clear, radius: 7)
    }

    private func open(_ zone: BoardZoneReference.PlayerZone, _ cards: [ZoneCard]) {
        if let inspectZone { inspectZone(.player(playerID: player.playerId, zone: zone)) }
        else { viewZone("\(player.displayName ?? player.playerId) · \(zone.rawValue.capitalized)", cards) }
    }
}

enum StackTargetPresentation {
    static func labels(for ids: [String], in snapshot: GameSnapshot) -> [String] {
        let cards = PortraitInteractionPolicy.authorizedCards(snapshot)
        return ids.map { id in
            if let player = snapshot.players.first(where: { CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot).contains(id) }) {
                return snapshot.playerLabel(player.playerId)
            }
            if let card = cards.first(where: { $0.id == id }) {
                return NativeCardArtworkPolicy.permitsLookup(card: card) ? card.card.name : "Hidden card"
            }
            if let object = snapshot.xmage?.stack.first(where: { $0.id == id || $0.objectId == id }) {
                return object.displayName
            }
            return "Unavailable target"
        }
    }
}

struct PortraitStackLane: View {
    let snapshot: GameSnapshot
    let humanStack: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var horizontal = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text("STACK")
                    .font(.headline)
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("\(stackCount)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))
                Spacer(minLength: 0)
                Text(responseLabel)
                    .font(.caption.bold())
                    .foregroundStyle(responseColor)
            }
            .padding(.horizontal, 2)

            Divider()
                .background(MagicPalette.antiqueGold.opacity(0.22))

            if stackCount == 0 {
                VStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold.opacity(0.76))
                    Text("No stack")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                    Text("Spells and abilities appear here")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(Array(xmageObjects.enumerated()), id: \.element.id) { _, object in
                            stackObjectView(object)
                        }
                        if xmageObjects.isEmpty {
                            ForEach(Array(humanStack.reversed().enumerated()), id: \.element.id) { _, card in
                                stackCardView(card)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("board.stack.items")
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MagicPalette.iron.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30), lineWidth: 1))
    }

    @ViewBuilder
    private func stackObjectView(_ object: XmageStackObject) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            if horizontal { stackArtwork(object) }
            VStack(alignment: .leading, spacing: 8) {
            Text(object.displayName).font(.headline).foregroundStyle(MagicPalette.parchment)
            Text("Source: \(object.displaySourceName)").font(.caption).foregroundStyle(.secondary)
            if let targets = object.targetIds, !targets.isEmpty {
                Text("Targets: \(StackTargetPresentation.labels(for: targets, in: snapshot).joined(separator: ", "))")
                    .font(.subheadline).foregroundStyle(MagicPalette.parchment)
            }
            if !horizontal { stackArtwork(object) }
            if let rules = object.rulesText {
                GameRulesText(source: rules,
                              cardName: object.displaySourceCard?.card.name ?? object.sourceName,
                              isHidden: object.displaySourceCard.map { !NativeCardArtworkPolicy.permitsLookup(card: $0) } ?? false)
                    .font(.body).foregroundStyle(MagicPalette.parchment)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stackArtwork(_ object: XmageStackObject) -> some View {
        if let card = object.displaySourceCard {
            stackCardView(card)
        } else {
            SyntheticStackObjectTile(object: object, width: horizontal ? 150 : 180, height: horizontal ? 210 : 252)
        }
    }

    private func stackCardView(_ card: ZoneCard) -> some View {
        CardTile(card: card, selected: false, legal: false, zoneName: "Stack", width: horizontal ? 150 : 180, height: horizontal ? 210 : 252, ignoreTappedRotation: true, imageVariant: .inspection)
            .onTapGesture { inspectedCard = card }
            .accessibilityHint("Tap to inspect source card")
    }

    private var xmageObjects: [XmageStackObject] {
        snapshot.stackTopFirst
    }

    private var stackCount: Int {
        if let count = snapshot.xmage?.stack.count, count > 0 {
            return count
        }
        return humanStack.count
    }

    private var responseLabel: String {
        legalActions.contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) } ? "RESPOND" : "WAIT"
    }

    private var responseColor: Color {
        responseLabel == "RESPOND" ? MagicPalette.legalEmerald : .white.opacity(0.55)
    }

}
