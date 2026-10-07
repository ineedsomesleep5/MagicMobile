import SwiftUI
import PhotosUI
import UIKit

struct CompactPromptPopup: View {
    let snapshot: GameSnapshot
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let openDetails: () -> Void
    @Environment(\.boardAnswerActions) private var answerActions
    /// "Don't ask again this game" for this question only.
    @State private var remember = false
    @State private var rememberPromptId: String?

    private var promptV2: PromptEnvelopeV2? { snapshot.promptEnvelopeV2 }
    private var legalActions: [LegalAction] { snapshot.legalActions ?? [] }
    private var sourceManaActions: [LegalAction] {
        legalActions.filter { $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil) }
    }
    private var compactPromptActions: [LegalAction] {
        Self.compactLegalPromptActions(in: snapshot)
    }
    private var presentation: MobilePromptPresentation? {
        MobilePromptPresentation.make(snapshot: snapshot, legalActions: legalActions)
    }
    private var paymentPrompt: PromptEnvelopeV2? {
        if let prompt = promptV2, Self.isManaPaymentPrompt(prompt) {
            return prompt
        }
        if Self.shouldShowStackPaymentTray(in: snapshot) {
            return Self.syntheticStackPaymentPrompt(in: snapshot)
        }
        return nil
    }

    @Environment(\.tavernBoard) private var tavern
    private var tavernKit: Bool { tavern && TavernUIKit.available }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: tavernKit ? .center : .firstTextBaseline, spacing: 8) {
                GameRulesText(source: PromptDisplayText.clean(messageText), symbolSize: 14)
                    .font(tavernKit ? .system(size: 15, weight: .semibold, design: .serif) : .system(size: 14, weight: .black))
                    .foregroundStyle(tavernKit ? TavernPalette.parchment : .white.opacity(0.94))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 4)
                if tavernKit {
                    TavernTag(text: priorityLabel, leather: true)
                } else {
                    Text(priorityLabel)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }

            if let prompt = paymentPrompt {
                ManaPaymentTray(
                    snapshot: snapshot,
                    prompt: prompt,
                    pendingActionId: pendingActionId,
                    runAction: runAction,
                    runCommand: runCommand
                )
            } else if pendingActionId != nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(MagicPalette.arcaneBlue)
                        .scaleEffect(0.66)
                    Text("Waiting for XMage")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.arcaneBlue)
                }
            } else if let prompt = promptV2 {
                compactPromptControls(prompt)
            } else if let prompt = snapshot.choicePrompt {
                compactChoicePrompt(prompt)
            } else if let prompt = snapshot.promptEnvelope {
                compactLegacyPrompt(prompt)
            }
        }
        .padding(.horizontal, tavernKit ? 12 : 10)
        .padding(.vertical, tavernKit ? 11 : 9)
        .modifier(PopupPanelBackground(tavern: tavernKit, borderColor: borderColor))
    }

    static func shouldShow(for snapshot: GameSnapshot, pendingActionId: String?) -> Bool {
        if InlinePaymentPromptState.isActive(in: snapshot) {
            return false
        }
        if pendingActionId != nil {
            return true
        }

        if let prompt = snapshot.promptEnvelopeV2 {
            let presentation = MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? [])
            if presentation?.kind == .payment || isManaPaymentPrompt(prompt) {
                return false
            }
            if isPassivePriorityPrompt(prompt, snapshot: snapshot) {
                return false
            }
            if !compactLegalPromptActions(in: snapshot).isEmpty {
                return true
            }
            if presentation?.requiresDetail == true || needsDetails(snapshot) {
                return true
            }
            if prompt.confirmation != nil || isCommanderReplacementPrompt(prompt) {
                return true
            }
            if prompt.choices?.isEmpty == false {
                return true
            }
            return prompt.required == true && !isPassivePriorityMessage(prompt.message)
        }

        if let choicePrompt = snapshot.choicePrompt {
            return !choicePrompt.choices.isEmpty || !compactLegalPromptActions(in: snapshot).isEmpty
        }

        if let prompt = snapshot.promptEnvelope {
            return prompt.choices?.isEmpty == false || !compactLegalPromptActions(in: snapshot).isEmpty
        }

        return false
    }

    static func shouldShowStackPaymentTray(in snapshot: GameSnapshot) -> Bool {
        // Authoritative: the bridge reports manaPayment.active only while the human
        // is actually paying for a spell/ability on the stack. This intentionally
        // does NOT fire for plain response windows (an ability on the stack you may
        // respond to but are not paying for).
        if snapshot.manaPayment?.active == true {
            return true
        }
        guard snapshot.isViewer(snapshot.waitingOnPlayerId) || snapshot.isViewer(snapshot.priorityPlayerId) else {
            return false
        }
        let actions = snapshot.legalActions ?? []
        let sourceManaActions = actions.filter { $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil) }
        guard !sourceManaActions.isEmpty else {
            return false
        }
        let allowedPaymentWindowTypes = Set(["make_mana", "undo_mana", "cancel_payment", "cancel_mana_payment", "concede"])
        guard actions.allSatisfy({ allowedPaymentWindowTypes.contains($0.type) }) else {
            return false
        }
        return snapshot.xmage?.stack.isEmpty == false || snapshot.human?.zones.stack.isEmpty == false
    }

    static func syntheticStackPaymentPrompt(in snapshot: GameSnapshot) -> PromptEnvelopeV2 {
        PromptEnvelopeV2(
            id: "xmage-stack-payment-\(snapshot.bridgeRevision ?? snapshot.turn)",
            method: "GAME_PLAY_MANA",
            messageId: -1,
            playerId: snapshot.viewerID,
            responseKind: "mana",
            message: stackPaymentMessage(in: snapshot),
            required: false,
            minChoices: nil,
            maxChoices: nil,
            totalMin: nil,
            totalMax: nil,
            targetIds: nil,
            choices: nil,
            responseCommand: nil,
            cards: nil,
            targets: nil,
            players: nil,
            piles: nil,
            abilities: nil,
            modes: nil,
            amounts: nil,
            multiAmounts: nil,
            manaChoices: nil,
            orderedItems: nil,
            confirmation: nil,
            options: nil
        )
    }

    private static func stackPaymentMessage(in snapshot: GameSnapshot) -> String {
        if let top = snapshot.xmage?.stack.first {
            return "Tap mana for \(top.displayName)"
        }
        if let top = snapshot.human?.zones.stack.first {
            return "Tap mana for \(top.card.name)"
        }
        return "Tap mana for the spell"
    }

    static func needsDetails(_ snapshot: GameSnapshot) -> Bool {
        if snapshot.source == "xmage-ondevice", let prompt = snapshot.promptEnvelopeV2 {
            if prompt.cards?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false { return true }
            if prompt.piles?.isEmpty == false || prompt.abilities?.isEmpty == false || prompt.modes?.isEmpty == false { return true }
            if prompt.amounts?.isEmpty == false || prompt.multiAmounts?.isEmpty == false || prompt.orderedItems?.isEmpty == false { return true }
            if (prompt.choices?.count ?? 0) > 3 || prompt.responseCommand?.type == "choose_amount" { return true }
        }
        if !compactLegalPromptActions(in: snapshot).isEmpty {
            return false
        }
        if let presentation = MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? []) {
            return presentation.requiresDetail
        }
        guard let prompt = snapshot.promptEnvelopeV2 else { return false }
        if prompt.cards?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false { return true }
        if prompt.piles?.isEmpty == false || prompt.abilities?.isEmpty == false || prompt.modes?.isEmpty == false { return true }
        if prompt.amounts?.isEmpty == false || prompt.multiAmounts?.isEmpty == false || prompt.orderedItems?.isEmpty == false { return true }
        return (prompt.choices?.count ?? 0) > 3
    }

    static func compactLegalPromptActions(in snapshot: GameSnapshot) -> [LegalAction] {
        let legalActions = snapshot.legalActions ?? []
        let promptId = snapshot.promptEnvelopeV2?.responseCommand?.promptId
            ?? snapshot.promptEnvelopeV2?.id
            ?? snapshot.promptEnvelope?.id
            ?? snapshot.choicePrompt?.id
        let responseType = snapshot.promptEnvelopeV2?.responseCommand?.type?.lowercased()
        let responseKind = snapshot.promptEnvelopeV2?.responseKind.lowercased()
            ?? snapshot.promptEnvelope?.responseKind.lowercased()
        let message = (
            snapshot.promptEnvelopeV2?.message
                ?? snapshot.promptEnvelope?.message
                ?? snapshot.choicePrompt?.message
                ?? snapshot.promptText
                ?? ""
        ).lowercased()

        var allowedTypes = Set(["resolve_choice", "answer_yes_no", "pay_cost", "commander_replacement"])
        if message.contains("mulligan") {
            allowedTypes.formUnion(["keep_hand", "mulligan"])
        }
        if message.contains("starting player") || message.contains("starts") || responseKind == "player" {
            allowedTypes.insert("choose_player")
        }
        if responseType == "resolve_choice" || responseKind == "choice" {
            allowedTypes.insert("resolve_choice")
        }

        return PortraitInteractionPolicy.dockActions(legalActions)
            .filter { action in
                if action.type == "concede" { return false }
                // The card-backed picker owns these choices. Keep separate
                // cancel/confirmation actions, but do not repeat abilities as
                // a second compact text chooser underneath it.
                if snapshot.source == "xmage-ondevice", snapshot.promptEnvelopeV2?.abilities?.isEmpty == false,
                   action.type == "choose_ability" { return false }
                if let promptId, action.promptId == promptId { return true }
                if let responseType, action.type == responseType { return true }
                return allowedTypes.contains(action.type)
            }
            .sorted { lhs, rhs in
                compactActionPriority(lhs) < compactActionPriority(rhs)
            }
    }

    private var isManaPayment: Bool {
        if presentation?.kind == .payment {
            return true
        }
        if let prompt = promptV2 {
            return Self.isManaPaymentPrompt(prompt)
        }
        return false
    }

    private var borderColor: Color {
        isManaPayment ? MagicPalette.arcaneBlue : MagicPalette.borderBronze
    }

    private var priorityLabel: String {
        if snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) {
            return "YOUR DECISION"
        }
        return "WAITING"
    }

    private var messageText: String {
        presentation?.message
            ?? promptV2?.message
            ?? snapshot.choicePrompt?.message
            ?? snapshot.promptEnvelope?.message
            ?? snapshot.promptText
            ?? "XMage is waiting"
    }

    @ViewBuilder
    private func compactPromptControls(_ prompt: PromptEnvelopeV2) -> some View {
        let options = (prompt.targets ?? []).filter { option in
            !snapshot.players.flatMap({ $0.zones.battlefield }).contains { $0.instanceId == option.id }
        }
        if !options.isEmpty && prompt.maxChoices == 1 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 8) {
                ForEach(options) { option in
                    compactCommandButton(option.label, systemImage: "person.crop.circle", pendingId: "\(prompt.id)-\(option.id)", command: command(type: prompt.responseCommand?.type ?? "choose_target", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [option.id]))
                }
            }
        } else if isCommanderReplacement(prompt) {
            HStack(spacing: 7) {
                compactCommandButton("Command zone", systemImage: "crown.fill", pendingId: "\(prompt.id)-command-zone", command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: true))
                compactCommandButton("Original", systemImage: "arrow.uturn.backward", pendingId: "\(prompt.id)-original-zone", command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: false))
            }
        } else if let confirmation = prompt.confirmation, isConfirmationPrompt(prompt) {
            let rememberable = prompt.canRememberAnswer && answerActions.supported.contains("rememberAnswer")
            HStack(spacing: 7) {
                compactCommandButton(confirmation.yesLabel ?? "Yes", systemImage: "checkmark.circle", pendingId: "\(prompt.id)-yes",
                                     command: remembering(explicitConfirmationCommand(confirmation.yesCommand, prompt: prompt), prompt: prompt, rememberable: rememberable))
                compactCommandButton(confirmation.noLabel ?? "No", systemImage: "xmark.circle", pendingId: "\(prompt.id)-no",
                                     command: remembering(explicitConfirmationCommand(confirmation.noCommand, prompt: prompt), prompt: prompt, rememberable: rememberable))
            }
            // A card's "you may" question (sixteen quest counters): answer once for the rest of the game.
            if rememberable {
                RememberChoiceToggle(title: "Don't ask again this game",
                                     isOn: Binding(get: { remember && rememberPromptId == prompt.id },
                                                   set: { remember = $0; rememberPromptId = prompt.id }))
            }
        } else if Self.shouldPreferCompactActionsBeforeRawChoices(for: snapshot) {
            compactActionButtons(compactPromptActions)
        } else if let choices = prompt.choices, !choices.isEmpty, choices.count <= 3 {
            HStack(spacing: 7) {
                ForEach(choices) { choice in
                    compactCommandButton(
                        choice.label,
                        systemImage: yesNoIcon(choice.label),
                        pendingId: "\(prompt.id)-\(choice.id)",
                        command: command(type: PromptCommandBuilder.idCommandType(preferred: prompt.responseCommand?.type, fallback: "resolve_choice"), promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [choice.id])
                    )
                }
            }
            let extraActions = Self.supplementalChoiceActions(in: snapshot)
            if !extraActions.isEmpty {
                compactActionButtons(extraActions)
            }
        } else if !compactPromptActions.isEmpty {
            compactActionButtons(compactPromptActions)
        } else if CompactPromptPopup.needsDetails(snapshot) {
            detailButton()
        } else {
            unsupportedFallback()
        }
    }

    @ViewBuilder
    private func compactChoicePrompt(_ prompt: ChoicePrompt) -> some View {
        HStack(spacing: 7) {
            ForEach(prompt.choices.prefix(3)) { choice in
                let action = action(for: choice, promptId: prompt.id)
                Button {
                    if let action {
                        runAction(action)
                    } else if let command = command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) {
                        runCommand(command, choice.label, "\(prompt.id)-\(choice.id)")
                    }
                } label: {
                    PromptButtonLabel(title: choice.label, systemImage: yesNoIcon(choice.label), isPending: pendingActionId == action?.id || pendingActionId == "\(prompt.id)-\(choice.id)")
                }
                .buttonStyle(PanelActionButtonStyle(isPrimary: action?.isPrimary == true))
                .disabled(pendingActionId != nil || (action == nil && command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) == nil))
            }
            if prompt.choices.count > 3 {
                detailButton()
            }
        }
    }

    static func shouldPreferCompactActionsBeforeRawChoices(for snapshot: GameSnapshot) -> Bool {
        let actions = compactLegalPromptActions(in: snapshot)
        guard actions.contains(where: { $0.type == "choose_player" }) else {
            return false
        }
        let responseType = snapshot.promptEnvelopeV2?.responseCommand?.type?.lowercased()
        let responseKind = snapshot.promptEnvelopeV2?.responseKind.lowercased()
            ?? snapshot.promptEnvelope?.responseKind.lowercased()
        let message = (
            snapshot.promptEnvelopeV2?.message
                ?? snapshot.promptEnvelope?.message
                ?? snapshot.choicePrompt?.message
                ?? snapshot.promptText
                ?? ""
        ).lowercased()
        return responseType == "choose_player" ||
            responseKind == "player" ||
            message.contains("starting player")
    }

    @ViewBuilder
    private func compactLegacyPrompt(_ prompt: PromptEnvelope) -> some View {
        if let choices = prompt.choices, !choices.isEmpty {
            HStack(spacing: 7) {
                ForEach(choices.prefix(3)) { choice in
                    compactCommandButton(choice.label, systemImage: yesNoIcon(choice.label), pendingId: "\(prompt.id)-\(choice.id)", command: command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]))
                }
            }
        } else if !compactPromptActions.isEmpty {
            compactActionButtons(compactPromptActions)
        } else {
            unsupportedFallback()
        }
    }

    static func supplementalChoiceActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard snapshot.source == "xmage-ondevice", let prompt = snapshot.promptEnvelopeV2,
              let choices = prompt.choices, !choices.isEmpty, choices.count <= 3 else { return [] }
        let choiceIDs = Set(choices.map(\.id))
        return compactLegalPromptActions(in: snapshot).filter { action in
            guard action.promptId == (prompt.responseCommand?.promptId ?? prompt.id),
                  action.messageId == (prompt.responseCommand?.messageId ?? prompt.messageId),
                  action.playerId == prompt.playerId else { return false }
            return !(action.type == "resolve_choice" && action.choiceIds?.count == 1 && choiceIDs.contains(action.choiceIds?.first ?? ""))
        }
    }

    private func compactActionButtons(_ actions: [LegalAction]) -> some View {
        HStack(spacing: 7) {
            ForEach(actions.prefix(3)) { action in
                let title = compactActionLabel(action)
                Button {
                    runAction(action)
                } label: {
                    PromptButtonLabel(
                        title: title,
                        systemImage: action.systemImage,
                        isPending: pendingActionId == action.id
                    )
                }
                .buttonStyle(PanelActionButtonStyle(isPrimary: action.isPrimary == true || action.type == "keep_hand", compact: true))
                .disabled(pendingActionId != nil)
            }
            if actions.count > 3 || (snapshot.source == "xmage-ondevice" && Self.needsDetails(snapshot)) {
                detailButton()
            }
        }
    }

    private func detailButton() -> some View {
        Button(action: openDetails) {
            PromptButtonLabel(title: "Open choices", subtitle: "XMage prompt controls", systemImage: "list.bullet.rectangle", isPending: false)
        }
        .buttonStyle(PanelActionButtonStyle())
        .disabled(pendingActionId != nil)
    }

    private func compactCommandButton(_ label: String, systemImage: String? = nil, pendingId: String, command: GameCommand?) -> some View {
        Button {
            if let command {
                runCommand(command, label, pendingId)
            }
        } label: {
            PromptButtonLabel(title: label, systemImage: systemImage, isPending: pendingActionId == pendingId)
        }
        .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
        .disabled(pendingActionId != nil || command == nil)
    }

    private func unsupportedFallback() -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.warningAmber)
            Text("Needs app support")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
            Spacer(minLength: 2)
            detailButton()
        }
    }

    private func action(for choice: ChoicePromptOption, promptId: String) -> LegalAction? {
        let choiceId = choice.id
        let composedId = "\(promptId)-\(choiceId)"
        return legalActions.first { action in
            action.id == choiceId ||
                action.id == composedId ||
                action.targetIds?.contains(choiceId) == true ||
                action.validTargetIds?.contains(choiceId) == true ||
                action.id.hasSuffix("-\(choiceId)")
        }
    }

    private func command(
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        useCommandZone: Bool? = nil,
        manaType: String? = nil,
        pay: Bool? = nil
    ) -> GameCommand? {
        UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: snapshot.promptEnvelopeV2,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            useCommandZone: useCommandZone,
            manaType: manaType,
            pay: pay
        )
    }

    private func remembering(_ command: GameCommand?, prompt: PromptEnvelopeV2, rememberable: Bool) -> GameCommand? {
        guard var command, rememberable, remember, rememberPromptId == prompt.id else { return command }
        command.answerActions = ["rememberAnswer"]
        return command
    }

    private func explicitConfirmationCommand(_ confirmationCommand: XmageResponseCommand?, prompt: PromptEnvelopeV2) -> GameCommand? {
        guard let confirmationCommand,
              let type = confirmationCommand.type,
              let promptId = confirmationCommand.promptId,
              let confirmed = confirmationCommand.confirmed ?? confirmationCommand.pay
        else {
            return nil
        }
        return command(
            type: type,
            promptId: promptId,
            playerId: prompt.playerId,
            ids: [confirmed ? "true" : "false"],
            pay: confirmationCommand.pay ?? confirmed
        )
    }

    static func isManaPaymentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        return type == "play_mana" || type == "choose_mana" || type == "pay_cost" || type == "play_x_mana" ||
            kind == "mana" || kind == "pay_cost" || kind == "cost" || kind == "x_mana" ||
            prompt.method == "GAME_PLAY_MANA" || prompt.method == "GAME_PLAY_XMANA"
    }

    private func isConfirmationPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        prompt.responseCommand?.type?.lowercased() == "answer_yes_no" || prompt.responseKind.lowercased() == "confirmation"
    }

    private func isCommanderReplacement(_ prompt: PromptEnvelopeV2) -> Bool {
        return Self.isCommanderReplacementPrompt(prompt)
    }

    private func sourceCardName(for action: LegalAction) -> String {
        action.cardName ?? action.label.replacingOccurrences(of: "Tap ", with: "")
    }

    private func compactActionLabel(_ action: LegalAction) -> String {
        switch action.type {
        case "keep_hand":
            return "Keep"
        case "mulligan":
            return "Mulligan"
        default:
            return action.compactPromptTitle
        }
    }

    private func yesNoIcon(_ label: String) -> String? {
        let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "ok", "accept", "keep"].contains(lower) { return "checkmark.circle" }
        if ["no", "cancel", "decline", "mulligan"].contains(lower) { return "xmark.circle" }
        return nil
    }

    private static func compactActionPriority(_ action: LegalAction) -> Int {
        if action.isPrimary == true { return 0 }
        switch action.type {
        case "keep_hand":
            return 1
        case "mulligan":
            return 2
        case "choose_player":
            return 3
        case "resolve_choice", "answer_yes_no":
            return 4
        case "pay_cost", "commander_replacement":
            return 5
        default:
            return 8
        }
    }

    private static func isCommanderReplacementPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        PromptCommandBuilder.isCommanderReplacement(prompt)
    }

    private static func isPassivePriorityPrompt(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> Bool {
        guard prompt.method == "GAME_SELECT" else { return false }
        if prompt.responseKind == "priority", prompt.responseCommand?.type == "pass_priority" {
            return true
        }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        guard type == "choose_card" || type == "card" else { return false }
        if prompt.cards?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false {
            return false
        }
        if prompt.choices?.isEmpty == false || prompt.modes?.isEmpty == false || prompt.abilities?.isEmpty == false {
            return false
        }
        return isPassivePriorityMessage(prompt.message) || isPassivePriorityMessage(snapshot.promptText ?? "")
    }

    private static func isPassivePriorityMessage(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "play spells and abilities" ||
            normalized == "play instants and activated abilities" ||
            normalized == "play spells or abilities" ||
            normalized == "select a card"
    }
}

struct DragActionChoice: Identifiable {
    let id = UUID()
    let message: String
    let actions: [LegalAction]
}

struct DragActionChoicePopup: View {
    let choice: DragActionChoice
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let cancel: () -> Void

    /// Ability text is sentence length; give each action its own full-width row.
    private var usesRows: Bool {
        choice.actions.count > 2 || choice.actions.contains { ($0.shortLabel ?? $0.label).count > 18 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(PromptDisplayText.clean(choice.message))
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(MagicPalette.parchment)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Cancel action choice")
            }

            let layout = usesRows ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(choice.actions.prefix(4)) { action in
                    Button {
                        runAction(action)
                    } label: {
                        PromptButtonLabel(
                            title: action.shortLabel ?? action.label,
                            systemImage: action.systemImage,
                            isPending: pendingActionId == action.id,
                            cardName: action.cardName ?? choice.message,
                            large: usesRows
                        )
                    }
                    .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: !usesRows))
                    .disabled(pendingActionId != nil)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.96), MagicPalette.leather.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MagicPalette.antiqueGold.opacity(0.7), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}

struct ManaPaymentTray: View {
    let snapshot: GameSnapshot
    let prompt: PromptEnvelopeV2
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    var compact = false
    @Environment(\.tavernBoard) private var tavern

    private var remainingPips: ManaPips? { snapshot.manaPayment?.remaining }

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Pay cost")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                paymentPipRow
                Spacer(minLength: 0)
            }

            if let choices = prompt.manaChoices, !choices.isEmpty {
                HStack(spacing: 7) {
                    Text("Use floating mana")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.72))
                    ForEach(choices.prefix(6)) { choice in
                        let symbol = choice.manaType ?? choice.id
                        paymentManaButton(symbol: symbol, label: choice.label, pendingId: "\(prompt.id)-mana-choice-\(choice.id)", size: 24)
                    }
                }
            }

            let undoActions = Self.manaUndoActions(in: snapshot)
            if !undoActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(undoActions.prefix(2)) { action in
                        Button {
                            runAction(action)
                        } label: {
                            PromptButtonLabel(title: Self.paymentCancelTitle(for: action), systemImage: action.type == "resolve_choice" ? "sparkles" : "arrow.uturn.backward", isPending: pendingActionId == action.id)
                        }
                        .buttonStyle(PanelActionButtonStyle(compact: true))
                        .disabled(pendingActionId != nil)
                    }
                }
            } else if let undoText = Self.manaUndoUnavailableText(in: snapshot) {
                Text(undoText)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if !hasBattlefieldManaSources && prompt.manaChoices?.isEmpty != false {
                Text("Waiting for XMage mana options")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.arcaneBlue)
            }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
            paymentPipRow
            if let choices = prompt.manaChoices, !choices.isEmpty {
                if tavern {
                    Rectangle().fill(TavernPalette.brass.opacity(0.7)).frame(width: 1, height: 24)
                    Text("Use floating mana")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(TavernPalette.parchment)
                } else {
                    Divider().frame(height: 24)
                    Text("Use floating mana").font(.caption2.bold()).foregroundStyle(MagicPalette.parchment)
                }
                // Keep every supplied payment choice reachable while cancel stays fixed.
                ForEach(choices) { choice in
                    let symbol = choice.manaType ?? choice.id
                    paymentManaButton(symbol: symbol, label: choice.label, pendingId: "\(prompt.id)-mana-choice-\(choice.id)", size: 22)
                }
            } else {
                Text(hasBattlefieldManaSources ? "Tap sources" : "Waiting for mana options")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(hasBattlefieldManaSources ? MagicPalette.parchment.opacity(0.78) : MagicPalette.arcaneBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            }
            }
            .frame(minWidth: 48, minHeight: 44)
            .accessibilityLabel("Remaining cost and mana choices; swipe to view")

            ForEach(Self.compactPaymentActions(in: snapshot)) { action in
                Button {
                    runAction(action)
                } label: {
                    Image(systemName: action.type == "resolve_choice" ? "sparkles" : "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .black))
                }
                .buttonStyle(IconButtonStyle(small: true))
                .disabled(pendingActionId != nil)
                .accessibilityLabel(Self.paymentCancelTitle(for: action))
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var paymentPipRow: some View {
        if let pips = remainingPips, pips.total > 0 {
            HStack(spacing: 3) {
                if pips.generic > 0 {
                    if tavern {
                        TavernGenericGem(value: pips.generic, size: 30)
                    } else {
                        ZStack {
                            Circle().fill(Color.gray.opacity(0.55))
                            Text("\(pips.generic)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 18, height: 18)
                    }
                }
                ForEach(Array(pips.orderedColors.enumerated()), id: \.offset) { entry in
                    ForEach(0..<entry.element.count, id: \.self) { _ in
                        paymentManaButton(
                            symbol: entry.element.symbol,
                            label: "Pay {\(entry.element.symbol)}",
                            pendingId: "\(prompt.id)-pip-\(entry.element.symbol)-\(entry.offset)",
                            size: 18
                        )
                    }
                }
            }
        } else if !requiredManaSymbols.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(requiredManaSymbols.enumerated()), id: \.offset) { _, symbol in
                    if let amount = Int(symbol) {
                        Text("\(amount)").font(.caption.bold()).frame(width: 24, height: 24).background(.gray, in: Circle())
                    } else {
                        ManaSymbolView(symbol: symbol, size: 24)
                    }
                }
            }
            .accessibilityLabel(requiredManaText)
        } else {
            Text(requiredManaText)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var requiredManaSymbols: [String] {
        let text = snapshot.manaPayment?.remainingText ?? prompt.message
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9WUBRGC/XP]+)\\}") else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range(at: 1)) }
    }

    static func manaUndoActions(in snapshot: GameSnapshot) -> [LegalAction] {
        let undoTypes = Set(["undo_mana", "cancel_payment", "cancel_mana_payment"])
        return (snapshot.legalActions ?? [])
            .filter { action in
                if undoTypes.contains(action.type) { return true }
                guard snapshot.source == "xmage-ondevice", let prompt = snapshot.promptEnvelopeV2,
                      CompactPromptPopup.isManaPaymentPrompt(prompt) else { return false }
                return action.type == "resolve_choice" && action.choiceIds == ["special"]
                    && action.promptId == (prompt.responseCommand?.promptId ?? prompt.id)
                    && action.messageId == (prompt.responseCommand?.messageId ?? prompt.messageId)
                    && action.playerId == prompt.playerId
            }
    }

    static func compactPaymentActions(in snapshot: GameSnapshot) -> [LegalAction] {
        Array(manaUndoActions(in: snapshot).prefix(snapshot.source == "xmage-ondevice" ? 2 : 1))
    }

    static func paymentCancelTitle(for action: LegalAction) -> String {
        switch action.type {
        case "resolve_choice" where action.choiceIds == ["special"]:
            return action.label
        case "cancel_payment", "cancel_mana_payment":
            return "Cancel cast"
        case "undo_mana":
            return "Undo mana"
        default:
            return action.shortLabel ?? action.displayLabel
        }
    }

    static func payableManaChoiceSymbols(in snapshot: GameSnapshot, prompt: PromptEnvelopeV2) -> [String] {
        (prompt.manaChoices ?? [])
            .map { $0.manaType ?? $0.id }
            .filter { canPay(symbol: $0, in: snapshot) }
    }

    static func manaUndoUnavailableText(in snapshot: GameSnapshot) -> String? {
        guard hasFloatingMana(in: snapshot), manaUndoActions(in: snapshot).isEmpty else {
            return nil
        }
        return "XMage has not exposed mana undo"
    }

    private static func hasFloatingMana(in snapshot: GameSnapshot) -> Bool {
        guard let pool = snapshot.human?.manaPool else { return false }
        return pool.W + pool.U + pool.B + pool.R + pool.G + pool.C > 0
    }

    static func canPay(symbol: String, in snapshot: GameSnapshot) -> Bool {
        if manaPoolValue(symbol, in: snapshot) > 0 { return true }
        return symbol == "C" && ["W", "U", "B", "R", "G", "C"].contains { manaPoolValue($0, in: snapshot) > 0 }
    }

    private static func manaPoolValue(_ symbol: String, in snapshot: GameSnapshot) -> Int {
        let pool = snapshot.human?.manaPool
        switch symbol {
        case "W": return pool?.W ?? 0
        case "U": return pool?.U ?? 0
        case "B": return pool?.B ?? 0
        case "R": return pool?.R ?? 0
        case "G": return pool?.G ?? 0
        case "C": return pool?.C ?? 0
        default: return 0
        }
    }

    private var requiredManaText: String {
        let message = prompt.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Tap for mana"
        }
        return message.count > 28 ? "Pay mana" : message
    }

    private var hasBattlefieldManaSources: Bool {
        (snapshot.legalActions ?? []).contains {
            $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil)
        }
    }

    private func command(
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        manaType: String? = nil
    ) -> GameCommand? {
        UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: snapshot.promptEnvelopeV2,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            manaType: manaType
        )
    }

    private func paymentManaButton(symbol: String, label: String, pendingId: String, size: CGFloat) -> some View {
        let type = snapshot.source == "xmage-ondevice" ? "play_mana" : prompt.responseCommand?.type ?? "play_mana"
        let paymentCommand = command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol)
        return Button {
            if let command = paymentCommand {
                runCommand(command, label, pendingId)
            }
        } label: {
            // Tavern gems match the generic crystal's 30 pt.
            TavernAwareManaSymbol(symbol: symbol, size: tavern ? 25 : size)
                .opacity(canPay(symbol) && promptExposesManaChoice(symbol) ? 1 : 0.42)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(pendingActionId != nil || !canPay(symbol) || !promptExposesManaChoice(symbol) || paymentCommand == nil)
    }

    private func canPay(_ symbol: String) -> Bool {
        if snapshot.source == "xmage-ondevice" {
            // The prompt can belong to a controlled player's pool, not the viewer's.
            return (prompt.manaChoices?.first { ($0.manaType ?? $0.id) == symbol }?.amount ?? 0) > 0
        }
        return Self.canPay(symbol: symbol, in: snapshot)
    }

    private func promptExposesManaChoice(_ symbol: String) -> Bool {
        guard let choices = prompt.manaChoices, !choices.isEmpty else { return false }
        return choices.contains { ($0.manaType ?? $0.id) == symbol }
    }

}

/// The compact prompt's panel: dark iron and leather, or on the tavern board tooled leather in
/// brass trim.
private struct PopupPanelBackground: ViewModifier {
    let tavern: Bool
    let borderColor: Color

    func body(content: Content) -> some View {
        if tavern {
            content
                .background {
                    TavernFill(material: .leather)
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .overlay { TavernBrassFrame(scale: 0.5) }
                .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 5)
        } else {
            content
                .background(
                    LinearGradient(
                        colors: [MagicPalette.iron.opacity(0.92), MagicPalette.leather.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor.opacity(0.60), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 5)
        }
    }
}
