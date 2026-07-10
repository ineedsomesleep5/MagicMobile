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
    case gameOver
    case unsupportedPrompt(promptId: String, method: String, responseKind: String)
}

enum GameplayActionPresentation {
    private static let yieldActionGroups = [
        ["resolve_stack", "pass_until_stack_resolved"],
        ["pass_until_response"],
        ["end_turn", "pass_until_end_of_turn"],
        ["yield_until_next_turn", "pass_until_next_turn"]
    ]

    static func yieldActions(in actions: [LegalAction]) -> [LegalAction] {
        yieldActionGroups.compactMap { preferredTypes in
            preferredTypes.compactMap { type in
                actions.first { $0.type == type }
            }.first
        }
    }

    static func title(for action: LegalAction?, snapshot: GameSnapshot) -> String {
        guard let action else { return "Wait" }

        switch action.type {
        case "pass_priority":
            return "Pass Priority"
        case "pass_until_response":
            return "Pass Until Response"
        case "resolve_stack", "pass_until_stack_resolved":
            return "Resolve Stack"
        case "end_turn":
            return "End Turn"
        case "pass_until_end_of_turn":
            return "Yield Until End Step"
        case "yield_until_next_turn", "pass_until_next_turn":
            return "Yield Until Next Turn"
        case "advance_phase":
            return "Yield Until Next Main"
        case "declare_attackers":
            return "Done Attacking"
        case "declare_blockers":
            return "Done Blocking"
        default:
            if let shortLabel = action.shortLabel, !shortLabel.isEmpty {
                return shortLabel
            }
            return action.label
        }
    }

}

struct GameActionDockModel {
    enum Mode: Equatable {
        case prompt
        case priority
        case waiting
        case gameOver
    }

    let mode: Mode
    let primaryAction: LegalAction?
    let promptActions: [LegalAction]
    let primaryTitle: String
    let showsPromptDetails: Bool
    let isPrimaryEnabled: Bool

    static func make(
        snapshot: GameSnapshot,
        passAction: LegalAction?,
        promptActions: [LegalAction],
        decisionRequired: Bool,
        pendingActionId: String?
    ) -> GameActionDockModel {
        if snapshot.isCompleted {
            return GameActionDockModel(
                mode: .gameOver,
                primaryAction: nil,
                promptActions: [],
                primaryTitle: "Game Complete",
                showsPromptDetails: false,
                isPrimaryEnabled: false
            )
        }

        if pendingActionId != nil {
            return GameActionDockModel(
                mode: .waiting,
                primaryAction: nil,
                promptActions: promptActions,
                primaryTitle: "Waiting for XMage",
                showsPromptDetails: false,
                isPrimaryEnabled: false
            )
        }

        if decisionRequired {
            let primaryAction = promptActions.first
            return GameActionDockModel(
                mode: .prompt,
                primaryAction: primaryAction,
                promptActions: promptActions,
                primaryTitle: primaryAction?.label ?? "Open Choice",
                showsPromptDetails: true,
                isPrimaryEnabled: true
            )
        }

        return GameActionDockModel(
            mode: .priority,
            primaryAction: passAction,
            promptActions: [],
            primaryTitle: GameplayActionPresentation.title(for: passAction, snapshot: snapshot),
            showsPromptDetails: false,
            isPrimaryEnabled: passAction != nil
        )
    }
}

struct BattlefieldCardGroup: Identifiable, Equatable {
    let id: String
    let cards: [ZoneCard]

    var representative: ZoneCard { cards[0] }
    var count: Int { cards.count }
}

enum BattlefieldDensityPlanner {
    static func groups(cards: [ZoneCard]) -> [BattlefieldCardGroup] {
        var order: [String] = []
        var grouped: [String: [ZoneCard]] = [:]

        for card in cards {
            let key = groupKey(for: card)
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(card)
        }

        return order.compactMap { key in
            guard let cards = grouped[key] else { return nil }
            return BattlefieldCardGroup(id: key, cards: cards)
        }
    }

    private static func groupKey(for card: ZoneCard) -> String {
        let counters = (card.counters ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        let icons = (card.cardIcons ?? [])
            .map { "\($0.iconType):\($0.resourceName ?? "")" }
            .sorted()
            .joined(separator: ",")
        let blockers = (card.blocking ?? []).sorted().joined(separator: ",")
        return [
            card.card.name,
            card.card.typeLine,
            card.card.oracleText ?? "",
            String(card.tapped ?? false),
            String(card.summoningSickness ?? false),
            counters,
            String(card.power ?? Int.min),
            String(card.toughness ?? Int.min),
            String(card.damage ?? Int.min),
            String(card.isAttacking ?? false),
            blockers,
            card.attachedToInstanceId ?? "",
            String(card.selectable ?? true),
            card.disabledReason ?? "",
            icons
        ].joined(separator: "|")
    }
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
        if snapshot.isCompleted {
            return .gameOver
        }

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

        let actions = snapshot.legalActions ?? []
        if actions.contains(where: { $0.type == "declare_attackers" }) {
            return .combatSelectingAttackers
        }
        if actions.contains(where: { $0.type == "declare_blockers" }) {
            return .combatSelectingBlockers
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
