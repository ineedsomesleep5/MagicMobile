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
            if model.primaryAction == nil, arenaAbilityPrompt(snapshot) != nil || arenaTriggerPlanAnswers(snapshot) {
                // The ability browser holds the choice: only a prompt's own answer (a Cancel) stays in the corner.
                return ArenaButtonPlan(primary: model.promptActions.first.map { action in
                    .init(title: action.label, kind: .secondary) { runAction(action) }
                })
            }
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

    /// One Auto Pay step per settled snapshot: it sends one tap and waits for XMage's answer before the next. XMage
    /// asks which colour a mana of any colour should be: that is answered with the colour the plan wanted.
    func arenaAutoPayStep(snapshot: GameSnapshot) {
        guard var run = arenaAutoPay, pendingActionId == nil else { return }
        if run.awaitingColor, let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId),
           let choice = Self.arenaColorChoice(in: prompt, wanted: run.color) {
            run.color = nil
            run.awaitingColor = false
            run.answeredColor = "\(prompt.id):\(prompt.messageId)"
            run.quiet = 0
            arenaAutoPay = run
            if let command = PromptCommandBuilder.command(gameId: snapshot.id, promptEnvelope: prompt, type: "resolve_choice",
                                                          promptId: prompt.responseCommand?.promptId ?? prompt.id,
                                                          playerId: prompt.playerId, ids: [choice]) {
                runCommand(command, "Choose mana colour", "autopay-colour-\(prompt.id)-\(prompt.messageId)")
            } else {
                arenaAutoPay = nil
            }
            return
        }
        guard InlinePaymentPromptState.isActive(in: snapshot), let prompt = InlinePaymentPromptState.paymentPrompt(in: snapshot) else {
            // Another question means the payment is over; a quiet snapshot or two can come between XMage's answers.
            let asked = snapshot.promptEnvelopeV2.map { snapshot.isViewer($0.playerId) } ?? false
            run.quiet += 1
            // A tap's colour question comes at once; one that comes later is the spell's own (Painter's Servant).
            if run.quiet > 1 { run.awaitingColor = false }
            arenaAutoPay = asked || run.quiet > 3 ? nil : run
            return
        }
        // Back at the payment: the last tap asked nothing.
        run.awaitingColor = false
        run.color = nil
        run.quiet = 0
        let remaining = snapshot.manaPayment?.remainingText ?? prompt.message
        let signature = remaining + "|" + (snapshot.legalActions ?? []).map(\.id).sorted().joined(separator: ",")
        guard run.signatures[signature, default: 0] < 2, run.steps < 30 else {
            arenaAutoPay = nil
            arenaShowNotice("Auto Pay stopped: tap the rest yourself")
            return
        }
        run.signatures[signature, default: 0] += 1
        run.steps += 1
        arenaAutoPay = run
        switch arenaAutoPayNext(snapshot) {
        case let .tap(actionID, color):
            if let action = snapshot.legalActions?.first(where: { $0.id == actionID }) {
                arenaAutoPay?.color = color
                arenaAutoPay?.awaitingColor = true
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

    /// The choice that names `wanted` in XMage's mana-colour question, or its first colour when any will do; nil when
    /// the prompt isn't a colour question.
    static func arenaColorChoice(in prompt: PromptEnvelopeV2, wanted: String?) -> String? {
        let names = ["W": "white", "U": "blue", "B": "black", "R": "red", "G": "green"]
        guard prompt.responseKind.lowercased() == "choice", let choices = prompt.choices, !choices.isEmpty,
              choices.allSatisfy({ choice in names.values.contains { choice.label.lowercased().contains($0) } }) else { return nil }
        if let wanted, let name = names[wanted], let match = choices.first(where: { $0.label.lowercased().contains(name) }) {
            return match.id
        }
        return choices.first?.id
    }

    // MARK: Abilities

    /// XMage asking which ability: the order of triggers going on the stack (PICK_ABILITY), or which ability to use
    /// (CHOOSE_ABILITY). Shown in the Arena ability browser unless an order chosen there is answering it.
    func arenaAbilityPrompt(_ snapshot: GameSnapshot) -> (prompt: PromptEnvelopeV2, ordering: Bool)? {
        guard !arenaTriggerPlanAnswers(snapshot), let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId),
              let abilities = prompt.abilities, !abilities.isEmpty,
              (prompt.responseCommand?.type ?? "").lowercased() == "choose_ability" else { return nil }
        return (prompt, prompt.isTriggerOrder)
    }

    func arenaChooseAbility(_ ability: XmagePromptAbility, prompt: PromptEnvelopeV2, snapshot: GameSnapshot, remember: Bool) {
        guard pendingActionId == nil,
              var command = PromptCommandBuilder.command(gameId: snapshot.id, promptEnvelope: prompt, type: "choose_ability",
                                                         promptId: prompt.responseCommand?.promptId ?? prompt.id,
                                                         playerId: prompt.playerId, ids: [ability.id]) else { return }
        if remember { command.answerActions = ["rememberTriggerFirst"] }
        GameHaptics.selection()
        runCommand(command, prompt.isTriggerOrder ? "Put a trigger on the stack" : "Choose ability", "\(prompt.id)-\(ability.id)")
    }

    /// `resolveOrder` runs first to last. XMage asks which goes on the stack first, which resolves last: the plan is the
    /// picks in reverse, and each ordering prompt gets the first planned trigger it still offers (arenaTriggerStep).
    func arenaOrderTriggers(_ resolveOrder: [XmagePromptAbility], remember: Bool, prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        let picks = resolveOrder.reversed().map(\.id)
        guard let first = picks.first, let ability = resolveOrder.first(where: { $0.id == first }) else { return }
        arenaTriggerPlan = picks
        arenaTriggerSent = "\(prompt.id):\(prompt.messageId)"
        arenaChooseAbility(ability, prompt: prompt, snapshot: snapshot, remember: remember)
    }

    /// The plan answers this ordering prompt by itself: it offers a planned trigger and hasn't been answered yet. A
    /// prompt the plan already answered and still showing (a refused pick) goes back to the browser.
    func arenaTriggerPlanAnswers(_ snapshot: GameSnapshot) -> Bool {
        guard !arenaTriggerPlan.isEmpty, let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId),
              prompt.isTriggerOrder, let abilities = prompt.abilities else { return false }
        return "\(prompt.id):\(prompt.messageId)" != arenaTriggerSent && abilities.contains { arenaTriggerPlan.contains($0.id) }
    }

    /// The next pick of a chosen trigger order. Triggers XMage no longer offers are on the stack and leave the plan; a
    /// target question for one of them keeps it; your next priority, or an ordering prompt with none of its triggers
    /// (the last one XMage places itself), ends it.
    func arenaTriggerStep(snapshot: GameSnapshot) {
        guard !arenaTriggerPlan.isEmpty, pendingActionId == nil,
              let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId) else { return }
        guard prompt.isTriggerOrder, let abilities = prompt.abilities, !abilities.isEmpty else {
            if prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority" {
                arenaTriggerPlan = []; arenaTriggerSent = nil
            }
            return
        }
        arenaTriggerPlan = arenaTriggerPlan.filter { id in abilities.contains { $0.id == id } }
        guard let next = arenaTriggerPlan.first, let ability = abilities.first(where: { $0.id == next }) else {
            arenaTriggerSent = nil
            return
        }
        let key = "\(prompt.id):\(prompt.messageId)"
        guard key != arenaTriggerSent else { return }
        arenaTriggerSent = key
        arenaChooseAbility(ability, prompt: prompt, snapshot: snapshot, remember: false)
    }

    /// XMage asking for a modal spell's mode: the Arena's mode browser answers it.
    func arenaModePrompt(_ snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        guard let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId), prompt.modes?.isEmpty == false else { return nil }
        return prompt
    }

    /// The spell whose modes these are: named on the prompt's second line ("Black Market Connections [4cb]"), else the
    /// top of the stack.
    func arenaModeSource(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> ZoneCard? {
        let lines = prompt.message.components(separatedBy: "\n")
        if lines.count > 1 {
            let name = lines[1].replacingOccurrences(of: #"\s*\[[^\]]*\]\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if let card = PortraitInteractionPolicy.authorizedCards(snapshot).first(where: { $0.card.name == name }) { return card }
        }
        return snapshot.stackTopFirst.first?.displaySourceCard
    }

    func arenaChooseMode(_ mode: ChoicePromptOption, prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        guard pendingActionId == nil,
              let command = UniversalPromptResponseCommandBuilder.command(
                gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision, promptEnvelope: prompt,
                type: PromptCommandBuilder.idCommandType(preferred: prompt.responseCommand?.type, fallback: "choose_mode"),
                promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [mode.id]) else { return }
        runCommand(command, "Choose mode", "\(prompt.id)-\(mode.id)")
    }

    // MARK: Choices, players, numbers, splits and piles (docs/ARENA_STYLE.md)

    /// A question of yours the Arena's own screens take: not a payment, the opening hand or the starting roll.
    private func arenaOwnPrompt(_ snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        guard !startingRollVisible, OpeningHandChoice(snapshot) == nil, !InlinePaymentPromptState.isActive(in: snapshot),
              let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId), !CompactPromptPopup.isManaPaymentPrompt(prompt),
              prompt.responseKind != "priority", prompt.responseCommand?.type != "pass_priority" else { return nil }
        return prompt
    }

    /// The card a choice names: on the battlefield first, then anywhere you can see.
    func arenaCard(named name: String, in snapshot: GameSnapshot) -> ZoneCard? {
        snapshot.visibleBattlefield.first { $0.card.name == name }
            ?? PortraitInteractionPolicy.authorizedCards(snapshot).first { $0.card.name == name }
    }

    /// A list of named choices (replacement effects, creature types, colours): more than three, or ones naming a card,
    /// or with XMage's "Remember answer" twins. Auto Pay's own colour question is left to Auto Pay.
    func arenaChoicePrompt(_ snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        guard let prompt = arenaOwnPrompt(snapshot), let choices = prompt.choices, !choices.isEmpty,
              prompt.modes?.isEmpty != false, prompt.abilities?.isEmpty != false, prompt.cards?.isEmpty != false,
              prompt.confirmation == nil, !PromptCommandBuilder.isCommanderReplacement(prompt),
              arenaAutoPay?.awaitingColor != true,
              // The colour question Auto Pay just answered, until its answer lands.
              arenaAutoPay?.answeredColor != "\(prompt.id):\(prompt.messageId)" else { return nil }
        let options = ArenaChoiceList.options(choices.map { ($0.id, $0.label) })
        let namesCard = options.contains { option in option.name.map { arenaCard(named: $0, in: snapshot) != nil } ?? false }
        return choices.count > 3 || namesCard || options.count < choices.count ? prompt : nil
    }

    func arenaChoiceOptions(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> [ArenaChoiceBrowser.Option] {
        ArenaChoiceList.options((prompt.choices ?? []).map { ($0.id, $0.label) }).map { option in
            ArenaChoiceBrowser.Option(id: option.id, rememberID: option.rememberID, label: option.label, text: option.text,
                                      card: option.name.flatMap { arenaCard(named: $0, in: snapshot) },
                                      symbol: ArenaChoiceList.colorSymbol(option.label))
        }
    }

    func arenaAnswerChoice(_ option: ArenaChoiceBrowser.Option, remember: Bool, prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        let id = remember ? (option.rememberID ?? option.id) : option.id
        arenaAnswer(prompt, snapshot: snapshot, type: PromptCommandBuilder.idCommandType(preferred: prompt.responseCommand?.type, fallback: "resolve_choice"),
                    ids: [id], label: PromptDisplayText.clean(option.label), key: "\(prompt.id)-\(id)")
    }

    /// Choosing a player: XMage's player list, or a "starting player" question whose targets are the players.
    func arenaPlayerPrompt(_ snapshot: GameSnapshot) -> (prompt: PromptEnvelopeV2, seats: [ArenaPlayerChoice.Seat], type: String)? {
        guard let prompt = arenaOwnPrompt(snapshot) else { return nil }
        func seat(_ id: String, label: String) -> ArenaPlayerChoice.Seat {
            let player = snapshot.players.first { $0.playerId == id || CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot).contains(id) }
            return ArenaPlayerChoice.Seat(id: id, player: player, name: player.map { snapshot.isViewer($0.playerId) ? "You" : snapshot.playerLabel($0.playerId) } ?? label)
        }
        if let players = prompt.players, !players.isEmpty {
            return (prompt, players.filter { $0.selectable != false }.map { seat($0.playerId, label: $0.label) },
                    PromptCommandBuilder.idCommandType(preferred: prompt.responseCommand?.type, fallback: "choose_player"))
        }
        let ids = Set(snapshot.players.flatMap { CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot) })
        let message = prompt.message.lowercased()
        if message.contains("starting player") || message.contains("first turn") || message.contains("goes first"),
           let targets = prompt.targets, !targets.isEmpty,
           targets.allSatisfy({ ids.contains($0.id) }) {
            return (prompt, targets.map { seat($0.id, label: $0.label) },
                    PromptCommandBuilder.idCommandType(preferred: prompt.responseCommand?.type, fallback: "choose_target"))
        }
        return nil
    }

    func arenaAnswerPlayer(_ seat: ArenaPlayerChoice.Seat, type: String, prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        arenaAnswer(prompt, snapshot: snapshot, type: type, ids: [seat.id], label: "Choose \(seat.name)", key: "\(prompt.id)-\(seat.id)")
    }

    /// A number to choose (X, how many): XMage's amount question. Paying X mana stays with the payment.
    func arenaAmountPrompt(_ snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        guard let prompt = arenaOwnPrompt(snapshot), prompt.multiAmounts?.isEmpty != false else { return nil }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return prompt.amounts?.isEmpty == false || type == "choose_amount" ? prompt : nil
    }

    /// The amount pill's values, label and first value: X starts at the most your mana pays (the spell on the stack, your
    /// untapped mana sources and floating mana), anything else at its least.
    func arenaAmountSetup(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> (range: ArenaAmountRange, label: String, initial: Int) {
        let range = ArenaAmountRange(amounts: prompt.amounts, minimum: prompt.minChoices, maximum: prompt.maxChoices)
        let isX = prompt.message.contains("{X}") || prompt.message.lowercased().contains("value for x")
        guard isX, let cost = snapshot.stackTopFirst.first?.displaySourceCard?.card.manaCost, let human = snapshot.human else {
            return (range, isX ? "Pay X" : "Choose", range.minimum)
        }
        let sources = human.zones.battlefield.filter { card in
            card.tapped != true && (card.card.isLand || (card.card.oracleText ?? "").lowercased().contains("add {")
                                    || (card.card.oracleText ?? "").lowercased().contains("add one mana"))
        }.count
        let pool = human.manaPool.map { $0.W + $0.U + $0.B + $0.R + $0.G + $0.C } ?? 0
        let affordable = ArenaAmountRange.affordableX(cost: cost, sources: sources + pool) ?? range.minimum
        return (range, "Pay X", range.clamp(affordable))
    }

    func arenaAnswerAmount(_ value: Int, prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        arenaAnswer(prompt, snapshot: snapshot, type: PromptCommandBuilder.amountCommandType(preferred: prompt.responseCommand?.type),
                    amount: value, amounts: [value], label: "Choose \(value)", key: "\(prompt.id)-amount-\(value)")
    }

    /// A split of damage, counters or mana among rows.
    func arenaSplitPrompt(_ snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        guard let prompt = arenaOwnPrompt(snapshot), prompt.multiAmounts?.isEmpty == false else { return nil }
        return prompt
    }

    /// Each row as what it names: a blocker or target card, a player, a mana colour. Combat's source is the attacker the
    /// blockers block; a spell's is the top of the stack.
    func arenaSplitSetup(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot)
        -> (title: String, rows: [ArenaSplitBrowser.Row], source: XmageStackObject?, sourceCard: ZoneCard?) {
        // Combat's split comes in the combat damage step; "assign damage among targets" outside it is a spell's.
        let step = "\(snapshot.phase) \(snapshot.step ?? "")".lowercased()
        let combat = step.contains("combat") && step.contains("damage")
        let message = PromptDisplayText.clean(prompt.message.components(separatedBy: "\n").first ?? "")
        let damage = combat || message.lowercased().contains("damage")
        var attacker: ZoneCard?
        let rows = (prompt.multiAmounts ?? []).map { slot -> ArenaSplitBrowser.Row in
            let name = ArenaSplit.name(of: slot.label)
            let card = snapshot.visibleBattlefield.first { $0.card.name == name && (!combat || $0.blocking?.isEmpty == false) }
                ?? snapshot.visibleBattlefield.first { $0.card.name == name }
            if combat, attacker == nil, let blocked = card?.blocking {
                attacker = snapshot.human?.zones.battlefield.first { blocked.contains($0.instanceId) || blocked.contains($0.id) }
            }
            let player = card == nil ? snapshot.players.first { ($0.displayName ?? "") == name || snapshot.playerLabel($0.playerId) == name } : nil
            return ArenaSplitBrowser.Row(id: slot.id, label: slot.label, card: card, player: player,
                                         symbol: card == nil && player == nil ? ArenaChoiceList.colorSymbol(name) : nil,
                                         minimum: slot.min, maximum: slot.max, initial: min(max(slot.defaultValue ?? slot.min, slot.min), slot.max),
                                         lethal: nil)
        }
        let deathtouch = (attacker?.card.oracleText ?? snapshot.stackTopFirst.first?.rulesText ?? "").lowercased().contains("deathtouch")
        let withLethal = rows.map { row -> ArenaSplitBrowser.Row in
            guard damage, let card = row.card, card.isCreature, let toughness = card.displayToughness.flatMap({ Int($0) }) else { return row }
            return ArenaSplitBrowser.Row(id: row.id, label: row.label, card: row.card, player: row.player, symbol: row.symbol, minimum: row.minimum,
                                         maximum: row.maximum, initial: row.initial,
                                         lethal: ArenaSplit.lethal(toughness: toughness, damage: card.damage ?? 0, deathtouch: deathtouch))
        }
        let title = combat ? "Assign combat damage" : message.isEmpty ? "Divide" : message
        return (title, withLethal, combat ? nil : snapshot.stackTopFirst.first, attacker)
    }

    func arenaAnswerSplit(_ values: [Int], prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        arenaAnswer(prompt, snapshot: snapshot, type: "choose_multi_amount", amounts: values, label: "Assign amounts",
                    key: "\(prompt.id)-choose-multi-amount")
    }

    /// Choosing one of two piles.
    func arenaPilePrompt(_ snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        guard let prompt = arenaOwnPrompt(snapshot), prompt.piles?.isEmpty == false else { return nil }
        return prompt
    }

    func arenaAnswerPile(_ pile: XmagePromptPile, prompt: PromptEnvelopeV2, snapshot: GameSnapshot) {
        arenaAnswer(prompt, snapshot: snapshot, type: "choose_pile", pile: pile.explicitPileNumber, label: "Choose \(pile.label)",
                    key: "\(prompt.id)-pile-\(pile.id)")
    }

    /// One of these screens has this question; the pop-up, question screen and detail panel stay away.
    func arenaScreenPrompt(_ snapshot: GameSnapshot) -> Bool {
        arenaChoicePrompt(snapshot) != nil || arenaPlayerPrompt(snapshot) != nil || arenaAmountPrompt(snapshot) != nil
            || arenaSplitPrompt(snapshot) != nil || arenaPilePrompt(snapshot) != nil
    }

    /// XMage's own answers beside a screen's (Cancel, Done), leaving out the ones the screen makes itself.
    func arenaPromptAnswers(_ snapshot: GameSnapshot, excluding types: Set<String>) -> [(id: String, title: String, action: () -> Void)] {
        CompactPromptPopup.compactLegalPromptActions(in: snapshot).filter { !types.contains($0.type) }
            .map { action in (action.id, action.compactPromptTitle, { runAction(action) }) }
    }

    /// The same command the Hearth panel sends for this answer.
    private func arenaAnswer(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot, type: String, ids: [String] = [], amount: Int? = nil,
                             amounts: [Int]? = nil, pile: Int? = nil, label: String, key: String) {
        guard pendingActionId == nil,
              let command = UniversalPromptResponseCommandBuilder.command(
                gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision, promptEnvelope: prompt, type: type,
                promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: ids,
                amount: amount, amounts: amounts, pile: pile) else { return }
        GameHaptics.selection()
        runCommand(command, label, key)
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
        guard arenaCombatPhase(snapshot) == .attackers else {
            // A snapshot between XMage's answers can lack the attacker prompt: only leaving the step ends the queue.
            let step = (snapshot.step ?? snapshot.phase).lowercased().replacingOccurrences(of: "_", with: "-")
            if !step.contains("declare-attack") { arenaAttackQueue = nil }
            return
        }
        let targetable = GameBoardInteractionState.boardTargetableIds(for: snapshot)
        // Wait for the prompt's choices rather than dropping the rest of the queue.
        guard !targetable.isEmpty else { return }
        let mine = snapshot.human?.zones.battlefield ?? []
        func creature(_ id: String) -> ZoneCard? { mine.first { $0.instanceId == id || $0.id == id } }
        // XMage asking which defender (a planeswalker or battle in play) offers none of your creatures: wait for it.
        guard mine.contains(where: { targetable.contains($0.instanceId) || targetable.contains($0.id) }) else { return }
        // The rest: still yours, not yet attacking, and offered now.
        queue.remaining = queue.remaining.filter { id in targetable.contains(id) && creature(id).map { $0.isAttacking != true } == true }
        guard let next = queue.remaining.first, let card = creature(next) else {
            arenaAttackQueue = nil
            return
        }
        queue.remaining.removeFirst()
        arenaAttackQueue = queue.remaining.isEmpty ? nil : queue
        submitTarget(card, snapshot: snapshot)
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
