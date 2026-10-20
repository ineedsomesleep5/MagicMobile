import SwiftUI

/// The corner's buttons for the moment: the call to action and, above it, the secondary choice.
struct ArenaButtonPlan {
    struct Choice {
        let title: String
        var subtitle: String? = nil
        var kind: ArenaPlaqueButtonStyle.Kind = .primary
        var enabled = true
        let action: () -> Void
    }

    var primary: Choice?
    var secondary: Choice?
}

/// A queue of creatures All Attack still has to send, one per prompt revision.
struct ArenaAttackQueue: Equatable {
    var remaining: [String]
}

extension NativeGameView {
    func arenaCombatPhase(_ snapshot: GameSnapshot) -> ArenaCombatPhase? { ArenaCombatPhase.current(in: snapshot) }

    /// The prompt's own "Done" (XMage's combat completion), when it offers one.
    private func arenaCombatDone(_ snapshot: GameSnapshot) -> LegalAction? {
        (snapshot.legalActions ?? []).first { $0.type == "answer_yes_no" && $0.confirmed != false }
    }

    func arenaButtonPlan(snapshot: GameSnapshot) -> ArenaButtonPlan {
        if snapshot.isCompleted || snapshot.isSpectating { return ArenaButtonPlan() }
        if InlinePaymentPromptState.isActive(in: snapshot) { return arenaPaymentButtons(snapshot: snapshot) }
        if let phase = arenaCombatPhase(snapshot) { return arenaCombatButtons(phase, snapshot: snapshot) }
        let actions = snapshot.legalActions ?? []
        let model = GameActionDockModel.make(
            snapshot: snapshot, passAction: passAction(in: actions),
            promptActions: CompactPromptPopup.compactLegalPromptActions(in: snapshot),
            decisionRequired: !startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil),
            pendingActionId: pendingActionId)
        switch model.mode {
        case .gameOver:
            return ArenaButtonPlan()
        case .waiting:
            return ArenaButtonPlan(primary: .init(title: "Waiting…", kind: .waiting, enabled: false) {})
        case .prompt:
            let primary: ArenaButtonPlan.Choice
            if let action = model.primaryAction {
                primary = .init(title: action.label) { runAction(action) }
            } else {
                primary = .init(title: "Choices", kind: .secondary) { openPromptDetails() }
            }
            let other = model.promptActions.first { $0.id != model.primaryAction?.id }
            return ArenaButtonPlan(primary: primary, secondary: other.map { action in .init(title: action.label, kind: .secondary) { runAction(action) } })
        case .priority:
            guard let pass = model.primaryAction else {
                return ArenaButtonPlan(primary: .init(title: arenaWaitingTitle(snapshot), kind: .waiting, enabled: false) {})
            }
            let title = arenaPassTitle(pass, snapshot: snapshot)
            var plan = ArenaButtonPlan(primary: .init(title: title.title, subtitle: title.subtitle) { runAction(pass) })
            if let resolve = GameplayAffordances.resolveStackCommand(snapshot: snapshot, pendingActionID: pendingActionId, supported: answerActions.supported) {
                plan.secondary = .init(title: "Resolve All", kind: .secondary) {
                    runCommand(resolve, "Resolve the stack", "resolve-stack-\(resolve.promptId ?? "")")
                }
            }
            return plan
        }
    }

    /// The reference's short words: Next to move on, End Turn late in your turn, Resolve over a stack, Pass otherwise.
    private func arenaPassTitle(_ action: LegalAction, snapshot: GameSnapshot) -> (title: String, subtitle: String?) {
        guard action.type == "pass_priority" else { return (GameplayActionPresentation.title(for: action, snapshot: snapshot), nil) }
        if !snapshot.stackTopFirst.isEmpty { return ("Resolve", nil) }
        guard snapshot.isViewer(snapshot.activePlayerId) else { return ("Pass", nil) }
        switch TavernPhaseTrack.describe(snapshot.step ?? snapshot.phase).phase {
        case 0: return ("Next", "To Main")
        case 1: return ("Next", "To Combat")
        case 2: return ("Next", "To Main 2")
        default: return ("End Turn", nil)
        }
    }

    private func arenaWaitingTitle(_ snapshot: GameSnapshot) -> String {
        guard let active = snapshot.activePlayerId, !snapshot.isViewer(active) else { return "Waiting…" }
        return BoardOpponentFocus.opponents(in: snapshot).count > 1 ? "\(snapshot.playerLabel(active))’s Turn" : "Opponent’s Turn"
    }

    // MARK: Payment and Auto Pay

    private func arenaPaymentButtons(snapshot: GameSnapshot) -> ArenaButtonPlan {
        let cancel = ManaPaymentTray.manaUndoActions(in: snapshot).first { ["cancel_payment", "cancel_mana_payment"].contains($0.type) }
        let secondary = cancel.map { action in
            ArenaButtonPlan.Choice(title: "Cancel", kind: .secondary, enabled: pendingActionId == nil) { arenaAutoPay = nil; runAction(action) }
        }
        if arenaAutoPay != nil {
            return ArenaButtonPlan(primary: .init(title: "Paying…", enabled: false) {},
                                   secondary: .init(title: "Stop", kind: .secondary) { arenaAutoPay = nil })
        }
        switch arenaAutoPayNext(snapshot) {
        case .tap, .spend:
            return ArenaButtonPlan(primary: .init(title: "Auto Pay", enabled: pendingActionId == nil) { arenaStartAutoPay(snapshot: snapshot) },
                                   secondary: secondary)
        case .done, .blocked:
            // Nothing Auto Pay can do (special payment, X, a colour no source makes): the button stays, dimmed, and the
            // sources on the table still take taps.
            return ArenaButtonPlan(primary: .init(title: "Auto Pay", enabled: false) {}, secondary: secondary)
        }
    }

    private func arenaAutoPayNext(_ snapshot: GameSnapshot) -> ArenaAutoPay.Step {
        guard InlinePaymentPromptState.isActive(in: snapshot) else { return .done }
        if snapshot.manaPayment?.active == true || snapshot.promptEnvelopeV2?.responseKind.lowercased() == "mana" {
            return ArenaAutoPay.next(in: snapshot)
        }
        // The gateway's synthetic stack payment: no prompt text of its own, so read the cost from it.
        let prompt = CompactPromptPopup.syntheticStackPaymentPrompt(in: snapshot)
        return ArenaAutoPay.next(remainingText: snapshot.manaPayment?.remainingText ?? prompt.message, floating: [:],
                                 actions: snapshot.legalActions ?? [])
    }

    func arenaStartAutoPay(snapshot: GameSnapshot) {
        arenaAutoPay = ArenaAutoPayRun()
        GameHaptics.selection()
        arenaAutoPayStep(snapshot: snapshot)
    }

    /// One Auto Pay step per settled snapshot: it sends one tap and waits for XMage's answer before the next.
    func arenaAutoPayStep(snapshot: GameSnapshot) {
        guard var run = arenaAutoPay, pendingActionId == nil else { return }
        guard InlinePaymentPromptState.isActive(in: snapshot), let prompt = InlinePaymentPromptState.paymentPrompt(in: snapshot) else {
            arenaAutoPay = nil
            return
        }
        let remaining = snapshot.manaPayment?.remainingText ?? prompt.message
        let signature = remaining + "|" + (snapshot.legalActions ?? []).map(\.id).sorted().joined(separator: ",")
        guard !run.signatures.contains(signature), run.steps < 24 else {
            arenaAutoPay = nil
            arenaShowNotice("Auto Pay stopped: tap the rest yourself")
            return
        }
        run.signatures.insert(signature)
        run.steps += 1
        arenaAutoPay = run
        switch arenaAutoPayNext(snapshot) {
        case let .tap(actionID):
            if let action = snapshot.legalActions?.first(where: { $0.id == actionID }) {
                runAction(action)
            } else {
                arenaAutoPay = nil
            }
        case let .spend(symbol):
            if let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                runCommand(command, "Spend floating {\(symbol)}", "autopay-\(prompt.id)-\(symbol)-\(run.steps)")
            } else {
                arenaAutoPay = nil
            }
        case .done:
            arenaAutoPay = nil
        case let .blocked(reason):
            arenaAutoPay = nil
            arenaShowNotice(reason)
        }
    }

    func arenaShowNotice(_ text: String) {
        onInteractionFeedback(text)
        GameHaptics.warning()
        withAnimation(.easeOut(duration: 0.2)) { arenaNotice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if arenaNotice == text { withAnimation(.easeIn(duration: 0.3)) { arenaNotice = nil } }
        }
    }

    // MARK: Combat

    private func arenaCombatButtons(_ phase: ArenaCombatPhase, snapshot: GameSnapshot) -> ArenaButtonPlan {
        let mine = snapshot.human?.zones.battlefield ?? []
        let back = combatBackAction(in: snapshot).map { action in ArenaButtonPlan.Choice(title: "Take Back", kind: .secondary, action: action) }
        switch phase {
        case .attackers:
            let declared = mine.filter { $0.isAttacking == true }.count
            if CombatSelectionState.isDeclareAttackers(snapshot) && !combatSelection.selectedAttackerIds.isEmpty {
                // The gateway's two-tap declaration: an attacker is chosen and waits for its defender.
                return ArenaButtonPlan(primary: .init(title: "Cancel", kind: .secondary) { combatSelection.clearAttackers() })
            }
            let finish = ArenaButtonPlan.Choice(title: declared == 0 ? "No Attacks" : declared == 1 ? "1 Attacker" : "\(declared) Attackers",
                                                kind: declared == 0 ? .secondary : .primary, enabled: pendingActionId == nil) {
                arenaFinishCombat(phase, snapshot: snapshot)
            }
            if declared == 0, arenaAttackQueue == nil, let allAttack = arenaAllAttackTargets(snapshot), !allAttack.isEmpty {
                return ArenaButtonPlan(primary: .init(title: "All Attack", enabled: pendingActionId == nil) { arenaStartAllAttack(allAttack, snapshot: snapshot) },
                                       secondary: finish)
            }
            if arenaAttackQueue != nil {
                return ArenaButtonPlan(primary: .init(title: "Attacking…", enabled: false) {},
                                       secondary: .init(title: "Stop", kind: .secondary) { arenaAttackQueue = nil })
            }
            return ArenaButtonPlan(primary: finish, secondary: declared > 0 ? back : nil)
        case .blockers:
            let declared = mine.filter { !($0.blocking ?? []).isEmpty }.count
            if CombatSelectionState.isDeclareBlockers(snapshot) && combatSelection.selectedBlockerId != nil {
                return ArenaButtonPlan(primary: .init(title: "Cancel", kind: .secondary) { combatSelection.clearBlockers() })
            }
            let title = declared == 0 ? "No Blocks" : declared == 1 ? "1 Blocker" : "\(declared) Blockers"
            let finish = ArenaButtonPlan.Choice(title: title, kind: declared == 0 ? .secondary : .primary, enabled: pendingActionId == nil) {
                arenaFinishCombat(phase, snapshot: snapshot)
            }
            return ArenaButtonPlan(primary: finish, secondary: declared > 0 ? back : nil)
        }
    }

    private func arenaFinishCombat(_ phase: ArenaCombatPhase, snapshot: GameSnapshot) {
        if let done = arenaCombatDone(snapshot) {
            runAction(done)
        } else if phase == .attackers {
            finishAttackers(snapshot: snapshot)
        } else if combatSelection.hasPendingBlockers {
            submitBlockers(snapshot: snapshot)
        } else {
            finishBlockers(snapshot: snapshot)
        }
    }

    /// The creatures All Attack sends: every creature the prompt offers, when there is one opponent to attack (a pod or a
    /// planeswalker needs the player to pick each defender).
    private func arenaAllAttackTargets(_ snapshot: GameSnapshot) -> [String]? {
        guard BoardOpponentFocus.opponents(in: snapshot).count == 1 else { return nil }
        if CombatSelectionState.isDeclareAttackers(snapshot) {
            let actions = snapshot.legalActions ?? []
            return combatSelection.defenderHighlightIds(actions: actions).count == 1 ? Array(combatSelection.attackerHighlightIds(actions: actions)).sorted() : nil
        }
        let targetable = GameBoardInteractionState.boardTargetableIds(for: snapshot)
        let mine = snapshot.human?.zones.battlefield ?? []
        let ids = mine.filter { $0.isAttacking != true && (targetable.contains($0.instanceId) || targetable.contains($0.id)) }
            .map { targetable.contains($0.instanceId) ? $0.instanceId : $0.id }
        return ids
    }

    private func arenaStartAllAttack(_ ids: [String], snapshot: GameSnapshot) {
        if CombatSelectionState.isDeclareAttackers(snapshot) {
            // The gateway takes every attacker in one declaration.
            let actions = snapshot.legalActions ?? []
            guard let defender = combatSelection.defenderHighlightIds(actions: actions).first else { return }
            combatSelection.selectedAttackerIds = Set(ids)
            submitAttackers(defenderId: defender, snapshot: snapshot)
            return
        }
        arenaAttackQueue = ArenaAttackQueue(remaining: ids)
        GameHaptics.selection()
        arenaAttackStep(snapshot: snapshot)
    }

    /// The on-device engine takes one attacker per answer: send the next as soon as XMage has taken the last.
    func arenaAttackStep(snapshot: GameSnapshot) {
        guard var queue = arenaAttackQueue, pendingActionId == nil else { return }
        guard arenaCombatPhase(snapshot) == .attackers else { arenaAttackQueue = nil; return }
        let targetable = GameBoardInteractionState.boardTargetableIds(for: snapshot)
        let mine = snapshot.human?.zones.battlefield ?? []
        while let next = queue.remaining.first {
            queue.remaining.removeFirst()
            guard let card = mine.first(where: { $0.instanceId == next || $0.id == next }), card.isAttacking != true,
                  targetable.contains(next) else { continue }
            arenaAttackQueue = queue.remaining.isEmpty ? nil : queue
            submitTarget(card, snapshot: snapshot)
            return
        }
        arenaAttackQueue = nil
    }
}

/// Runs the Arena's step-by-step helpers (Auto Pay, All Attack) once each snapshot settles.
struct ArenaAutoPayDriver: ViewModifier {
    let key: String
    let active: Bool
    let step: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: key) { _, _ in
            guard active else { return }
            // Let the snapshot's own updates land before acting on it.
            DispatchQueue.main.async { step() }
        }
    }
}

/// Combat on the Arena table: red arcs from attackers to what they attack, gold from blockers to the attacker they hold.
struct ArenaCombatArrows: View {
    let snapshot: GameSnapshot
    let previewArrows: [CombatArrow]
    let bounds: [String: CGRect]
    let opponentID: String

    var body: some View {
        Canvas { context, _ in
            for arrow in CombatArrowModel.arrows(from: snapshot.xmage?.combat ?? [], previewArrows: previewArrows) {
                guard let from = bounds[arrow.fromId], let to = bounds[arrow.toId] ?? playerRect(arrow.toId, kind: arrow.toKind) else { continue }
                draw(arrow, from: CGPoint(x: from.midX, y: from.midY), to: CGPoint(x: to.midX, y: to.midY), in: &context)
            }
        }
    }

    private func playerRect(_ id: String, kind: String?) -> CGRect? {
        guard kind == nil || kind?.lowercased() == "player" else { return nil }
        if CombatPlayerIdentity.ids(for: snapshot.seatID, in: snapshot).contains(id) { return bounds[TavernSeatAnchor.bottom] }
        if CombatPlayerIdentity.ids(for: opponentID, in: snapshot).contains(id) { return bounds[TavernSeatAnchor.top] }
        return nil
    }

    private func draw(_ arrow: CombatArrow, from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        let color: Color
        switch arrow.kind {
        case .attack: color = Color(red: 1, green: 0.32, blue: 0.2)
        case .blockedAttack: color = .gray
        case .block: color = Color(red: 1, green: 0.82, blue: 0.45)
        case .previewAttack: color = MagicPalette.warningAmber
        case .previewBlock: color = Color(red: 1, green: 0.82, blue: 0.45)
        }
        let preview = arrow.kind == .previewAttack || arrow.kind == .previewBlock
        let lift = min(60, hypot(end.x - start.x, end.y - start.y) * 0.25)
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - lift)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        context.stroke(path, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: preview ? 6 : 9, lineCap: .round))
        context.stroke(path, with: .color(color.opacity(preview ? 0.6 : 0.95)),
                       style: StrokeStyle(lineWidth: preview ? 2 : 3, lineCap: .round, dash: preview ? [6, 5] : []))
        let angle = atan2(end.y - control.y, end.x - control.x)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 12 * cos(angle - .pi / 6), y: end.y - 12 * sin(angle - .pi / 6)))
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 12 * cos(angle + .pi / 6), y: end.y - 12 * sin(angle + .pi / 6)))
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

/// Portrait only: the plate's own front rail drawn again over a resting hand, so the hand tucks behind the table's edge.
struct ArenaFrontRail: View {
    let top: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Image("tavern-arena-portrait")
                .resizable()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: max(0, proxy.size.height - top))
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                        .offset(y: top)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
