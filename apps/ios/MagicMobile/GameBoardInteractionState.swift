import Foundation

enum GameBoardInteractionMode: Equatable {
    case idle
    case selectedCard(cardId: String)
    case draggingCard(cardId: String, legalActionIds: [String])
    case awaitingCastSnapshot(actionId: String)
    case manaPayment(promptId: String)
    case targeting(promptId: String, sourceCardId: String?, validTargetIds: Set<String>)
    case searchSelecting(promptId: String, zoneName: String, selectedIds: Set<String>)
    case combatSelectingAttackers
    case combatSelectingBlockers
    case damageAllocating(promptId: String)
    case waitingForXmage
    case unsupportedPrompt(promptId: String, method: String, responseKind: String)
}

struct GameBoardInteractionState: Equatable {
    var mode: GameBoardInteractionMode = .idle
    var feedback: String?

    static let idle = GameBoardInteractionState()

    var isWaitingForAuthoritativeSnapshot: Bool {
        switch mode {
        case .awaitingCastSnapshot, .waitingForXmage:
            return true
        default:
            return false
        }
    }

    var targetableIds: Set<String> {
        if case .targeting(_, _, let validTargetIds) = mode {
            return validTargetIds
        }
        return []
    }

    func isTargetable(_ card: ZoneCard) -> Bool {
        targetableIds.contains(card.instanceId) || targetableIds.contains(card.id)
    }

    static func mode(
        for snapshot: GameSnapshot,
        pendingActionId: String?,
        selectedCard: ZoneCard?
    ) -> GameBoardInteractionMode {
        if pendingActionId != nil {
            return .waitingForXmage
        }

        if let prompt = snapshot.promptEnvelopeV2 {
            if isManaPaymentPrompt(prompt) {
                return .manaPayment(promptId: prompt.responseCommand?.promptId ?? prompt.id)
            }
            if let targetingMode = targetingMode(for: prompt, selectedCard: selectedCard) {
                return targetingMode
            }
            if isSearchPrompt(prompt) {
                return .searchSelecting(
                    promptId: prompt.responseCommand?.promptId ?? prompt.id,
                    zoneName: searchZoneName(for: prompt),
                    selectedIds: []
                )
            }
            if isDamageAssignmentPrompt(prompt, snapshot: snapshot) {
                return .damageAllocating(promptId: prompt.responseCommand?.promptId ?? prompt.id)
            }
            if !hasMobileSafeControl(prompt) {
                return .unsupportedPrompt(
                    promptId: prompt.responseCommand?.promptId ?? prompt.id,
                    method: prompt.method,
                    responseKind: prompt.responseKind
                )
            }
        }

        if let selectedCard {
            return .selectedCard(cardId: selectedCard.instanceId)
        }

        return .idle
    }

    static func legalPlayActions(for card: ZoneCard, actions: [LegalAction]) -> [LegalAction] {
        cardActions(for: card, actions: actions).filter { action in
            ["play_land", "cast_spell"].contains(action.type)
        }
    }

    static func cardActions(for card: ZoneCard, actions: [LegalAction]) -> [LegalAction] {
        let ids = Set([card.instanceId, card.id])
        return actions.filter { action in
            action.effectiveCardInstanceId.map(ids.contains) == true ||
                action.effectiveSourceInstanceId.map(ids.contains) == true
        }
    }

    static func validTargetIds(from prompt: PromptEnvelopeV2?, actions: [LegalAction]) -> Set<String> {
        var ids = Set<String>()

        if let prompt {
            ids.formUnion(prompt.targetIds ?? [])
            ids.formUnion(prompt.targets?.map(\.id) ?? [])
            ids.formUnion(prompt.cards?.map(\.instanceId) ?? [])
            ids.formUnion(prompt.players?.map(\.playerId) ?? [])
        }

        for action in actions {
            ids.formUnion(action.validTargetIds ?? [])
            ids.formUnion(action.targetIds ?? [])
            ids.formUnion(action.validCardInstanceIds ?? [])
            ids.formUnion(action.cardInstanceIds ?? [])
            ids.formUnion(action.validPlayerIds ?? [])
            ids.formUnion(action.playerIds ?? [])
        }

        return ids
    }

    static func boardTargetableIds(for snapshot: GameSnapshot) -> Set<String> {
        guard let prompt = snapshot.promptEnvelopeV2 else { return [] }
        if isManaPaymentPrompt(prompt) || snapshot.manaPayment?.active == true {
            return []
        }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        let isTargetPrompt = type == "choose_target" ||
            prompt.responseKind.lowercased() == "target" ||
            prompt.method.localizedCaseInsensitiveContains("TARGET")
        guard isTargetPrompt else { return [] }
        return validTargetIds(from: prompt, actions: snapshot.legalActions ?? [])
    }

    private static func targetingMode(
        for prompt: PromptEnvelopeV2,
        selectedCard: ZoneCard?
    ) -> GameBoardInteractionMode? {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        let looksLikeTargetPrompt = type == "choose_target" ||
            prompt.responseKind.lowercased() == "target" ||
            prompt.method.localizedCaseInsensitiveContains("TARGET")

        guard looksLikeTargetPrompt else { return nil }

        let ids = validTargetIds(from: prompt, actions: [])
        guard !ids.isEmpty else { return nil }

        return .targeting(
            promptId: prompt.responseCommand?.promptId ?? prompt.id,
            sourceCardId: selectedCard?.instanceId,
            validTargetIds: ids
        )
    }

    private static func isSearchPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "search_select" || prompt.method.localizedCaseInsensitiveContains("search")
    }

    private static func isManaPaymentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        return type == "play_mana" ||
            type == "choose_mana" ||
            type == "pay_cost" ||
            type == "play_x_mana" ||
            kind == "mana" ||
            kind == "pay_cost" ||
            kind == "cost" ||
            kind == "x_mana" ||
            prompt.method == "GAME_PLAY_MANA" ||
            prompt.method == "GAME_PLAY_XMANA"
    }

    private static func searchZoneName(for prompt: PromptEnvelopeV2) -> String {
        if case .string(let zone)? = prompt.options?["zone"], !zone.isEmpty {
            return zone.capitalized
        }
        return "Library"
    }

    private static func isDamageAssignmentPrompt(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> Bool {
        PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, phase: snapshot.phase, step: snapshot.step)
    }

    private static func hasMobileSafeControl(_ prompt: PromptEnvelopeV2) -> Bool {
        if prompt.choices?.isEmpty == false { return true }
        if prompt.targets?.isEmpty == false || prompt.targetIds?.isEmpty == false { return true }
        if prompt.players?.isEmpty == false || prompt.cards?.isEmpty == false { return true }
        if prompt.piles?.isEmpty == false || prompt.abilities?.isEmpty == false { return true }
        if prompt.modes?.isEmpty == false || prompt.amounts?.isEmpty == false { return true }
        if prompt.multiAmounts?.isEmpty == false || prompt.manaChoices?.isEmpty == false { return true }
        if prompt.orderedItems?.isEmpty == false || prompt.confirmation != nil { return true }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return [
            "answer_yes_no",
            "commander_replacement",
            "pay_cost",
            "play_mana",
            "choose_mana",
            "order_triggers",
            "order_items"
        ].contains(type)
    }
}

enum DragCastDropResult: Equatable {
    case ignored
    case rejected(String)
    case requiresChoice([LegalAction], String)
    case submit(LegalAction)

    static func == (lhs: DragCastDropResult, rhs: DragCastDropResult) -> Bool {
        switch (lhs, rhs) {
        case (.ignored, .ignored):
            return true
        case let (.rejected(left), .rejected(right)):
            return left == right
        case let (.requiresChoice(leftActions, leftMessage), .requiresChoice(rightActions, rightMessage)):
            return leftMessage == rightMessage && leftActions.map(\.id) == rightActions.map(\.id)
        case let (.submit(left), .submit(right)):
            return left.id == right.id
        default:
            return false
        }
    }
}

enum DragCastDropResolver {
    static func resolve(card: ZoneCard, legalActions: [LegalAction], droppedInPlayArea: Bool) -> DragCastDropResult {
        guard droppedInPlayArea else { return .ignored }
        let playableActions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
        guard playableActions.count == 1, let action = playableActions.first else {
            if playableActions.isEmpty {
                return .rejected("\(card.card.name) is not currently playable")
            }
            return .requiresChoice(playableActions, "Choose how to play \(card.card.name)")
        }
        return .submit(action)
    }
}
