import Foundation

enum AiDifficulty: String, CaseIterable, Identifiable, Codable {
    case easy
    case normal
    case hard
    case expert

    var id: String { rawValue }
}

struct DeckEntry: Codable, Identifiable, Hashable {
    var id: String { "\(section)-\(cardName)-\(quantity)" }
    let cardName: String
    let quantity: Int
    let section: String
}

struct DeckList: Codable, Hashable {
    let name: String
    let commander: DeckEntry?
    let entries: [DeckEntry]

    var totalCards: Int {
        (commander?.quantity ?? 0) + entries.reduce(0) { $0 + $1.quantity }
    }
}

struct GeneratedDeckResponse: Decodable {
    let deck: DeckList
    let validationErrors: [String]
    let stats: DeckStats
}

struct DeckStats: Decodable {
    let lands: Int
    let ramp: Int
    let draw: Int
    let removal: Int
    let boardWipes: Int
    let averageManaValue: Double
}

struct EngineHealth: Decodable {
    let status: String
    let reason: String
    let checkedAt: String
    let recoveryAction: String?
}

struct CardCacheMetadata: Decodable {
    let provider: String
    let status: String
    let bulkVersion: String?
    let cardCount: Int
    let imageCount: Int
    let missingImageCount: Int
    let symbolCount: Int?
    let updatedAt: String?
}

struct CardImageManifestResponse: Decodable {
    let metadata: CardCacheMetadata
    let images: [CardImageManifestEntry]
}

struct CardImageManifestEntry: Decodable, Hashable {
    let name: String
    let url: String
    let inspectionUrl: String?
    let normalUrl: String?
}

struct SymbolManifestResponse: Decodable {
    let metadata: CardCacheMetadata
    let symbols: [SymbolManifestEntry]
}

struct SymbolManifestEntry: Decodable, Hashable {
    let symbol: String
    let looseVariant: String?
    let english: String?
    let svgUrl: String
    let pngUrl: String?
}

struct CommanderGameConfig: Encodable {
    let roomId: String
    let humanPlayerId: String
    let humanDisplayName: String?
    let humanDeck: DeckList
    let aiPlayers: [AiPlayerConfig]
    let startingLife: Int
    let commanderDamageEnabled: Bool
}

struct AiPlayerConfig: Encodable {
    let playerId: String
    let displayName: String
    let difficulty: AiDifficulty
    let deck: DeckList
}

enum GameStatus: String, Decodable, Equatable {
    case inProgress = "in_progress"
    case completed
}

struct GameSnapshot: Decodable {
    let id: String
    let source: String?
    let activePlayerId: String?
    let phase: String
    let step: String?
    let turn: Int
    let priorityPlayerId: String?
    let waitingOnPlayerId: String?
    let promptText: String?
    let players: [PlayerGameState]
    let log: [GameLogEntry]
    let legalActions: [LegalAction]?
    let choicePrompt: ChoicePrompt?
    let promptEnvelope: PromptEnvelope?
    let promptEnvelopeV2: PromptEnvelopeV2?
    let startupOpeningPrompts: [StartupOpeningPrompt]?
    let xmage: XmageMobileSnapshot?
    let engineHealth: EngineHealth?
    let bridgeRevision: Int?
    let xmageCycle: Int?
    let pendingStatus: String?
    let manaPayment: ManaPayment?
    let gameStatus: GameStatus?
    let winnerPlayerIds: [String]?
    let endReason: String?

    var human: PlayerGameState? {
        players.first { $0.playerId == "human" }
    }

    var opponent: PlayerGameState? {
        players.first { $0.playerId != "human" }
    }

    var isCompleted: Bool {
        gameStatus == .completed
    }

    var winnerDisplayNames: [String] {
        let winners = Set(winnerPlayerIds ?? [])
        return players.compactMap { player in
            guard winners.contains(player.playerId) else { return nil }
            return player.displayName ?? (player.playerId == "human" ? "You" : player.playerId)
        }
    }
}

enum MobilePromptKind: String, Codable, Equatable {
    case payment
    case target
    case confirmation
    case cardChoice
    case playerChoice
    case abilityChoice
    case order
    case amount
    case multiAmount
    case pile
    case search
    case combat
    case unsupported
}

struct MobilePromptPresentation: Equatable {
    let kind: MobilePromptKind
    let title: String
    let message: String
    let requiresDetail: Bool
    let isUnsupported: Bool

    static func make(snapshot: GameSnapshot, legalActions: [LegalAction]) -> MobilePromptPresentation? {
        if isCombatSelection(snapshot, legalActions: legalActions) {
            let isBlock = legalActions.contains { $0.type == "declare_blockers" } ||
                normalizedStep(snapshot).contains("declare-block")
            return MobilePromptPresentation(
                kind: .combat,
                title: isBlock ? "Select blockers" : "Select attackers",
                message: snapshot.promptText ?? (isBlock ? "Choose blockers" : "Choose attackers"),
                requiresDetail: false,
                isUnsupported: false
            )
        }

        guard let prompt = snapshot.promptEnvelopeV2 else { return nil }
        let kind = kind(for: prompt)
        let detailKinds: Set<MobilePromptKind> = [.cardChoice, .playerChoice, .abilityChoice, .order, .amount, .multiAmount, .pile, .search, .target, .unsupported]
        let title = title(for: kind, prompt: prompt)
        return MobilePromptPresentation(
            kind: kind,
            title: title,
            message: prompt.message,
            requiresDetail: detailKinds.contains(kind) || optionCount(prompt) > 3,
            isUnsupported: kind == .unsupported
        )
    }

    static func kind(for prompt: PromptEnvelopeV2) -> MobilePromptKind {
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        let method = prompt.method.uppercased()
        if type == "play_mana" || type == "choose_mana" || type == "pay_cost" || type == "play_x_mana" ||
            kind == "mana" || kind == "pay_cost" || kind == "cost" || kind == "x_mana" ||
            method == "GAME_PLAY_MANA" || method == "GAME_PLAY_XMANA" {
            return .payment
        }
        if type == "choose_target" || kind == "target" || method.contains("TARGET") || prompt.targets?.isEmpty == false || prompt.targetIds?.isEmpty == false {
            return .target
        }
        if type == "answer_yes_no" || kind == "confirmation" || prompt.confirmation != nil {
            return .confirmation
        }
        if type == "choose_player" || kind == "player" || prompt.players?.isEmpty == false {
            return .playerChoice
        }
        if type == "choose_ability" || kind == "ability" || prompt.abilities?.isEmpty == false {
            return .abilityChoice
        }
        if type == "order_triggers" || type == "order_items" || kind == "order" || prompt.orderedItems?.isEmpty == false {
            return .order
        }
        if type == "choose_multi_amount" || kind == "multi_amount" || prompt.multiAmounts?.isEmpty == false {
            return .multiAmount
        }
        if type == "choose_amount" || kind == "amount" || prompt.amounts?.isEmpty == false {
            return .amount
        }
        if type == "choose_pile" || kind == "pile" || prompt.piles?.isEmpty == false {
            return .pile
        }
        if type == "search_select" || kind == "search" {
            return .search
        }
        if type == "choose_card" || kind == "card" || prompt.cards?.isEmpty == false || prompt.choices?.isEmpty == false || prompt.modes?.isEmpty == false {
            return .cardChoice
        }
        return .unsupported
    }

    private static func title(for kind: MobilePromptKind, prompt: PromptEnvelopeV2) -> String {
        switch kind {
        case .payment: return "Pay cost"
        case .target: return "Select target"
        case .confirmation: return "Confirm choice"
        case .cardChoice: return "Choose card"
        case .playerChoice: return "Choose player"
        case .abilityChoice: return "Choose ability"
        case .order: return "Order choices"
        case .amount: return "Choose amount"
        case .multiAmount: return "Assign amounts"
        case .pile: return "Choose pile"
        case .search: return "Search"
        case .combat: return "Combat"
        case .unsupported:
            return prompt.responseKind.isEmpty ? "XMage prompt" : prompt.responseKind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func optionCount(_ prompt: PromptEnvelopeV2) -> Int {
        (prompt.choices?.count ?? 0) + (prompt.cards?.count ?? 0) + (prompt.targets?.count ?? 0) +
            (prompt.players?.count ?? 0) + (prompt.abilities?.count ?? 0) + (prompt.piles?.count ?? 0) +
            (prompt.amounts?.count ?? 0) + (prompt.multiAmounts?.count ?? 0) + (prompt.orderedItems?.count ?? 0)
    }

    private static func isCombatSelection(_ snapshot: GameSnapshot, legalActions: [LegalAction]) -> Bool {
        legalActions.contains { $0.type == "declare_attackers" || $0.type == "declare_blockers" } ||
            ((snapshot.waitingOnPlayerId == "human" || snapshot.priorityPlayerId == "human") &&
             (normalizedStep(snapshot).contains("declare-attack") || normalizedStep(snapshot).contains("declare-block")))
    }

    private static func normalizedStep(_ snapshot: GameSnapshot) -> String {
        "\(snapshot.step ?? "") \(snapshot.promptText ?? "")".lowercased()
    }
}

enum MagicMobileActionRejectionCategory: String, Codable, Equatable {
    case staleSnapshot = "stale_snapshot"
    case noLongerLegal = "no_longer_legal"
    case invalidChoice = "invalid_choice"
    case bridgeDisconnected = "bridge_disconnected"
    case xmageWaiting = "xmage_waiting"
    case unknown
}

struct MagicMobileActionRejection: Decodable {
    let category: MagicMobileActionRejectionCategory
    let message: String
    let snapshot: GameSnapshot?

    var shortMessage: String {
        switch category {
        case .staleSnapshot:
            return "Snapshot stale. Refreshed choices."
        case .noLongerLegal:
            return "That action is no longer legal."
        case .invalidChoice:
            return "XMage rejected that choice."
        case .bridgeDisconnected:
            return "Bridge disconnected. Reconnect available."
        case .xmageWaiting:
            return "XMage is still resolving."
        case .unknown:
            return message
        }
    }

    enum CodingKeys: String, CodingKey {
        case category
        case rejectionCategory
        case message
        case error
        case snapshot
    }

    init(category: MagicMobileActionRejectionCategory, message: String, snapshot: GameSnapshot?) {
        self.category = category
        self.message = message
        self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCategory = try container.decodeIfPresent(String.self, forKey: .rejectionCategory) ??
            container.decodeIfPresent(String.self, forKey: .category) ??
            container.decodeIfPresent(String.self, forKey: .error)
        category = Self.category(from: rawCategory)
        message = try container.decodeIfPresent(String.self, forKey: .message) ??
            container.decodeIfPresent(String.self, forKey: .error) ??
            "XMage rejected the action."
        snapshot = try container.decodeIfPresent(GameSnapshot.self, forKey: .snapshot)
    }

    static func category(from raw: String?) -> MagicMobileActionRejectionCategory {
        let text = raw?.lowercased() ?? ""
        if text.contains("stale") || text.contains("revision") { return .staleSnapshot }
        if text.contains("no_longer") || text.contains("no longer") || text.contains("not legal") { return .noLongerLegal }
        if text.contains("invalid") || text.contains("duplicate") || text.contains("disabled") { return .invalidChoice }
        if text.contains("disconnect") || text.contains("unavailable") { return .bridgeDisconnected }
        if text.contains("waiting") || text.contains("pending") { return .xmageWaiting }
        return .unknown
    }
}

struct ActionRejectionNotice: Equatable {
    let category: MagicMobileActionRejectionCategory
    let message: String
    let bridgeRevision: Int?
    let xmageCycle: Int?

    init(rejection: MagicMobileActionRejection) {
        category = rejection.category
        message = rejection.shortMessage
        bridgeRevision = rejection.snapshot?.bridgeRevision
        xmageCycle = rejection.snapshot?.xmageCycle
    }

    var title: String {
        switch category {
        case .staleSnapshot: return "Game state changed"
        case .noLongerLegal: return "Action no longer legal"
        case .invalidChoice: return "Choice rejected"
        case .bridgeDisconnected: return "Connection lost"
        case .xmageWaiting: return "XMage is resolving"
        case .unknown: return "Action not completed"
        }
    }

    var recoveryTitle: String? {
        switch category {
        case .staleSnapshot, .noLongerLegal, .invalidChoice:
            return "Refresh"
        case .bridgeDisconnected:
            return "Reconnect"
        case .xmageWaiting, .unknown:
            return nil
        }
    }
}

enum XmageWaitKind: String, Equatable {
    case yourPriority
    case xmageThinking
    case waitingForBridge
    case bridgeDisconnected
    case actionStillResolving
    case snapshotStale
    case manualReconnectAvailable
}

struct XmageWaitPresentation: Equatable {
    let kind: XmageWaitKind
    let title: String
    let detail: String

    static func make(
        snapshot: GameSnapshot,
        pendingActionId: String?,
        liveUpdateStatus: String,
        elapsedSeconds: TimeInterval = 0,
        didRefresh: Bool = false,
        didReconnect: Bool = false,
        didDiagnose: Bool = false
    ) -> XmageWaitPresentation {
        let live = liveUpdateStatus.lowercased()
        if live.contains("unavailable") || live.contains("disconnect") {
            return XmageWaitPresentation(kind: .bridgeDisconnected, title: "Bridge disconnected", detail: "Reconnect live updates.")
        }
        if pendingActionId != nil {
            return XmageWaitPresentation(kind: .actionStillResolving, title: "Action still resolving", detail: "Waiting for XMage to advance.")
        }
        if snapshot.pendingStatus == "waiting_for_xmage" {
            return XmageWaitPresentation(kind: .waitingForBridge, title: "Waiting for bridge", detail: "XMage accepted the command.")
        }
        if elapsedSeconds >= AIWaitRecoveryPolicy.diagnoseThresholdSeconds, didRefresh, didReconnect, didDiagnose {
            return XmageWaitPresentation(kind: .manualReconnectAvailable, title: "Manual reconnect available", detail: "Automatic refresh, reconnect, and health check already ran.")
        }
        if snapshot.isStalled {
            return XmageWaitPresentation(kind: .snapshotStale, title: "Snapshot stale", detail: "Refresh or reconnect to recover.")
        }
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" {
            return XmageWaitPresentation(kind: .yourPriority, title: "Your priority", detail: "Choose an action.")
        }
        return XmageWaitPresentation(kind: .xmageThinking, title: "XMage thinking", detail: "Waiting for AI or rules resolution.")
    }
}

/// Authoritative mana-payment state from the bridge: present and `active` only
/// while the human is mid-paying for a spell/ability on the stack. Drives the
/// pip tray, gating, and auto-resolve. Absent/inactive = not paying.
struct ManaPayment: Decodable {
    let active: Bool
    let spellName: String?
    let manaCostText: String?
    let remainingText: String?
    let remaining: ManaPips?
}

struct ManaPips: Decodable {
    let generic: Int
    let W: Int
    let U: Int
    let B: Int
    let R: Int
    let G: Int
    let C: Int
    let total: Int

    /// Ordered (symbol, count) pairs for rendering, generic first then WUBRG/C.
    var orderedColors: [(symbol: String, count: Int)] {
        [("W", W), ("U", U), ("B", B), ("R", R), ("G", G), ("C", C)].filter { $0.count > 0 }
    }
}

struct StartupOpeningPrompt: Decodable, Equatable {
    let promptId: String?
    let method: String?
    let responseKind: String?
    let message: String?
    let playerId: String?
    let bridgeRevision: Int?
    let xmageCycle: Int?
}

enum CastSubmissionOutcome: Equatable {
    case accepted
    case payment
    case targeting
    case waiting
    case rejectedStillInHand
    case notCastOrPlay

    var statusMessage: String {
        switch self {
        case .accepted:
            return "XMage accepted the play"
        case .payment:
            return "Tap mana sources to pay"
        case .targeting:
            return "Choose a highlighted XMage target"
        case .waiting:
            return "Waiting for XMage update"
        case .rejectedStillInHand:
            return "Cast did not progress. Refresh and try again."
        case .notCastOrPlay:
            return "Action submitted"
        }
    }
}

enum CastSubmissionClassifier {
    static func classify(action: LegalAction, before: GameSnapshot, after: GameSnapshot) -> CastSubmissionOutcome {
        guard ["cast_spell", "play_land"].contains(action.type) else { return .notCastOrPlay }
        if isPaymentPrompt(after.promptEnvelopeV2) { return .payment }
        if isTargetPrompt(after.promptEnvelopeV2) { return .targeting }
        if isActionableFollowUpPrompt(after.promptEnvelopeV2) { return .waiting }
        if after.pendingStatus == "waiting_for_xmage" { return .waiting }

        guard let cardId = action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId else {
            return .accepted
        }

        let wasInHand = before.human?.zones.hand.contains { $0.instanceId == cardId } == true
        let stillInHand = after.human?.zones.hand.contains { $0.instanceId == cardId } == true
        if wasInHand && stillInHand {
            return .rejectedStillInHand
        }
        return .accepted
    }

    static func shouldPollForDelayedOutcome(action: LegalAction, before: GameSnapshot, after: GameSnapshot) -> Bool {
        shouldKeepPollingForCastOutcome(action: action, before: before, after: after)
    }

    static func shouldKeepPollingForCastOutcome(action: LegalAction, before: GameSnapshot, after: GameSnapshot) -> Bool {
        guard ["cast_spell", "play_land"].contains(action.type) else { return false }
        return classify(action: action, before: before, after: after) == .rejectedStillInHand
    }

    static func isPaymentPrompt(_ prompt: PromptEnvelopeV2?) -> Bool {
        guard let prompt else { return false }
        let method = prompt.method.uppercased()
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return method == "GAME_PLAY_MANA"
            || method == "GAME_PLAY_XMANA"
            || ["play_mana", "choose_mana", "pay_cost", "play_x_mana", "mana", "x_mana"].contains(type)
    }

    static func isTargetPrompt(_ prompt: PromptEnvelopeV2?) -> Bool {
        guard let prompt else { return false }
        let method = prompt.method.uppercased()
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return method.contains("TARGET") || type == "choose_target" || type == "target"
    }

    static func isActionableFollowUpPrompt(_ prompt: PromptEnvelopeV2?) -> Bool {
        guard let prompt else { return false }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        let actionableTypes: Set<String> = [
            "answer_yes_no",
            "choose_ability",
            "choose_amount",
            "choose_card",
            "choose_mode",
            "choose_multi_amount",
            "choose_pile",
            "choose_player",
            "commander_replacement",
            "generic_replacement",
            "order_items",
            "order_triggers",
            "pay_cost",
            "play_x_mana",
            "resolve_choice",
            "search_select"
        ]
        guard actionableTypes.contains(type) else { return false }

        let hasChoices = prompt.choices?.isEmpty == false ||
            prompt.cards?.isEmpty == false ||
            prompt.targets?.isEmpty == false ||
            prompt.players?.isEmpty == false ||
            prompt.piles?.isEmpty == false ||
            prompt.abilities?.isEmpty == false ||
            prompt.modes?.isEmpty == false ||
            prompt.multiAmounts?.isEmpty == false ||
            prompt.targetIds?.isEmpty == false ||
            (prompt.minChoices ?? 0) > 0 ||
            prompt.required == true

        return hasChoices || prompt.responseCommand != nil
    }
}

extension GameSnapshot {
    var isStalled: Bool {
        pendingStatus == "stalled" || engineHealth?.status == "stalled"
    }

    var isWaitingOnAIOrStalled: Bool {
        isStalled || priorityPlayerId == "ai-1" || waitingOnPlayerId == "ai-1"
    }

    var aiWaitSignature: String {
        "\(id)|\(turn)|\(phase)|\(step ?? "")|\(priorityPlayerId ?? "")|\(waitingOnPlayerId ?? "")|\(pendingStatus ?? "")|\(engineHealth?.status ?? "")|\(bridgeRevision ?? -1)|\(xmageCycle ?? -1)"
    }
}

enum AIWaitRecoveryAction: Equatable {
    case none
    case refresh
    case reconnect
    case diagnose
}

enum AIWaitRecoveryPolicy {
    static let refreshThresholdSeconds: TimeInterval = 10
    static let reconnectThresholdSeconds: TimeInterval = 20
    static let diagnoseThresholdSeconds: TimeInterval = 30

    static func action(
        for snapshot: GameSnapshot,
        elapsedSeconds: TimeInterval,
        didRefresh: Bool,
        didReconnect: Bool,
        didDiagnose: Bool = false
    ) -> AIWaitRecoveryAction {
        guard snapshot.isWaitingOnAIOrStalled else {
            return .none
        }
        if elapsedSeconds >= diagnoseThresholdSeconds, didRefresh, didReconnect, !didDiagnose {
            return .diagnose
        }
        if elapsedSeconds >= reconnectThresholdSeconds, didRefresh, !didReconnect {
            return .reconnect
        }
        if elapsedSeconds >= refreshThresholdSeconds, !didRefresh {
            return .refresh
        }
        return .none
    }
}

struct CommanderStartupResponse: Decodable {
    let startupId: String
    let status: String
    let snapshot: GameSnapshot?
    let message: String?
    let error: String?
    var deckErrors: [CommanderDeckValidationError]? = nil
}

struct CleanupGameRequest: Encodable {
    let reason: String
}

struct CleanupGameResponse: Decodable {
    let status: String
    let gameId: String
    let reason: String?
    let removed: Bool
    let bridgeCleanupAttempted: Bool?
    let bridgeCleanupSucceeded: Bool?
}

struct CommanderFixtureResponse: Decodable {
    let error: String?
    let fixtureName: String?
    let productionDisabled: Bool
    let directStateSeeded: Bool
    let setupMethod: String?
    let blockedReason: String?
    let nextImplementationStep: String?
    let snapshot: GameSnapshot?
    let latestSnapshot: GameSnapshot?

    enum CodingKeys: String, CodingKey {
        case error
        case fixtureName
        case productionDisabled
        case directStateSeeded
        case setupMethod
        case blockedReason
        case nextImplementationStep
        case snapshot
        case latestSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        fixtureName = try container.decodeIfPresent(String.self, forKey: .fixtureName)
        productionDisabled = try container.decodeIfPresent(Bool.self, forKey: .productionDisabled) ?? false
        directStateSeeded = try container.decodeIfPresent(Bool.self, forKey: .directStateSeeded) ?? false
        setupMethod = try container.decodeIfPresent(String.self, forKey: .setupMethod)
        blockedReason = try container.decodeIfPresent(String.self, forKey: .blockedReason)
        nextImplementationStep = try container.decodeIfPresent(String.self, forKey: .nextImplementationStep)
        snapshot = try container.decodeIfPresent(GameSnapshot.self, forKey: .snapshot)
        latestSnapshot = try container.decodeIfPresent(GameSnapshot.self, forKey: .latestSnapshot)
    }

    var playableSnapshot: GameSnapshot? {
        guard directStateSeeded else { return nil }
        return snapshot ?? latestSnapshot
    }

    var statusMessage: String {
        if let blockedReason, !blockedReason.isEmpty {
            return "Fixture blocked: \(blockedReason)"
        }
        if let error, !error.isEmpty {
            return "Fixture blocked: \(error)"
        }
        return directStateSeeded ? "Fixture seeded in XMage" : "Fixture blocked"
    }
}

struct GameLogEntry: Decodable, Identifiable {
    let id: String
    let message: String
    let createdAt: String?
}

struct PlayerGameState: Decodable, Identifiable {
    let playerId: String
    let displayName: String?
    let life: Int
    let poison: Int
    let commanderTax: Int
    let manaPool: ManaPool?
    let zones: PlayerZones
    let commanderDamage: [String: Int]?

    var id: String { playerId }
}

struct ManaPool: Decodable, Hashable {
    let W: Int
    let U: Int
    let B: Int
    let R: Int
    let G: Int
    let C: Int
}

struct PlayerZones: Decodable {
    let library: [ZoneCard]
    let hand: [ZoneCard]
    let battlefield: [ZoneCard]
    let graveyard: [ZoneCard]
    let exile: [ZoneCard]
    let command: [ZoneCard]
    let stack: [ZoneCard]
}

struct ZoneCard: Decodable, Identifiable, Hashable {
    let instanceId: String
    let card: CardIdentity
    let tapped: Bool?
    let summoningSickness: Bool?
    let cardIcons: [XmageCardIcon]?
    let counters: [String: Int]?
    let power: Int?
    let toughness: Int?
    let isCreaturePermanent: Bool?
    let damage: Int?
    let isAttacking: Bool?
    let blocking: [String]?
    let attachedToInstanceId: String?
    let selectable: Bool?
    let disabledReason: String?

    var id: String { instanceId }

    init(
        instanceId: String,
        card: CardIdentity,
        tapped: Bool?,
        summoningSickness: Bool?,
        cardIcons: [XmageCardIcon]?,
        counters: [String: Int]?,
        power: Int?,
        toughness: Int?,
        isCreaturePermanent: Bool?,
        damage: Int?,
        isAttacking: Bool?,
        blocking: [String]?,
        attachedToInstanceId: String?,
        selectable: Bool? = nil,
        disabledReason: String? = nil
    ) {
        self.instanceId = instanceId
        self.card = card
        self.tapped = tapped
        self.summoningSickness = summoningSickness
        self.cardIcons = cardIcons
        self.counters = counters
        self.power = power
        self.toughness = toughness
        self.isCreaturePermanent = isCreaturePermanent
        self.damage = damage
        self.isAttacking = isAttacking
        self.blocking = blocking
        self.attachedToInstanceId = attachedToInstanceId
        self.selectable = selectable
        self.disabledReason = disabledReason
    }
}

struct CardIdentity: Decodable, Hashable {
    let name: String
    let typeLine: String
    let oracleText: String?
}

struct FlexibleInt: Decodable, Equatable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
            return
        }
        if let text = try? container.decode(String.self), let number = Int(text) {
            value = number
            return
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected an integer or numeric string.")
        )
    }
}

struct LegalAction: Decodable, Identifiable {
    let id: String
    let type: String
    let playerId: String
    let label: String
    let promptId: String?
    let cardInstanceId: String?
    let cardName: String?
    let manaCost: String?
    let sourceZone: String?
    let sourceInstanceId: String?
    let abilityId: String?
    let targetIds: [String]?
    let validTargetIds: [String]?
    let playerIds: [String]?
    let validPlayerIds: [String]?
    let choiceIds: [String]?
    let cardInstanceIds: [String]?
    let validCardInstanceIds: [String]?
    let modeIds: [String]?
    let orderedIds: [String]?
    let amount: Int?
    let amounts: [Int]?
    let multiAmounts: [XmagePromptMultiAmount]?
    let manaType: String?
    let manaTypes: [String]?
    let pile: FlexibleInt?
    let confirmed: Bool?
    let pay: Bool?
    let useCommandZone: Bool?
    let isPrimary: Bool?
    let requiresTarget: Bool?
    let requiresPayment: Bool?
    let producedMana: [String]?
    let responseKind: String?
    let messageId: Int?
    let minChoices: Int?
    let maxChoices: Int?
    let zoneContext: String?
    let shortLabel: String?
    let commandTemplate: [String: JSONValue]?
    let attackers: [AttackDeclaration]?
    let blockers: [BlockDeclaration]?
    let defenderId: String?
    let defenderKind: String?
    let defenderName: String?
}

extension LegalAction {
    var compactPromptTitle: String {
        switch type {
        case "pass_priority": return "Pass Priority"
        case "resolve_stack", "pass_until_stack_resolved": return "Resolve Stack"
        case "end_turn": return "End Turn"
        case "pass_until_end_of_turn": return "Yield Until End Step"
        case "yield_until_next_turn", "pass_until_next_turn": return "Yield Until Next Turn"
        default: break
        }

        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShortLabel = shortLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericAbilityLabels = Set(["ability", "activated ability", "triggered ability"])
        if ["choose_ability", "activate_ability"].contains(type),
           let trimmedShortLabel,
           genericAbilityLabels.contains(trimmedShortLabel.lowercased()),
           !trimmedLabel.isEmpty,
           !genericAbilityLabels.contains(trimmedLabel.lowercased()) {
            return trimmedLabel
        }
        if let trimmedShortLabel, !trimmedShortLabel.isEmpty {
            return trimmedShortLabel
        }
        return trimmedLabel.isEmpty ? type : trimmedLabel
    }

    var effectiveCardInstanceId: String? {
        commandTemplate?["cardInstanceId"]?.stringValue ?? cardInstanceId ?? effectiveSourceInstanceId
    }

    var effectiveSourceInstanceId: String? {
        commandTemplate?["sourceInstanceId"]?.stringValue ?? sourceInstanceId ?? cardInstanceId
    }

    var effectiveSourceZone: String? {
        commandTemplate?["sourceZone"]?.stringValue ?? sourceZone
    }

    var effectiveFromZone: String? {
        commandTemplate?["fromZone"]?.stringValue ?? sourceZone
    }

    var effectiveAbilityId: String? {
        commandTemplate?["abilityId"]?.stringValue ?? abilityId
    }
}

struct ChoicePrompt: Decodable, Identifiable {
    let id: String
    let playerId: String
    let message: String
    let minChoices: Int
    let maxChoices: Int
    let choices: [ChoicePromptOption]
}

struct ChoicePromptOption: Decodable, Identifiable {
    let id: String
    let label: String
    let cardInstanceId: String?
}

struct PromptEnvelope: Decodable, Identifiable {
    let id: String
    let method: String
    let messageId: Int
    let playerId: String
    let responseKind: String
    let message: String
    let required: Bool?
    let minChoices: Int?
    let maxChoices: Int?
    let totalMin: Int?
    let totalMax: Int?
    let targetIds: [String]?
    let choices: [ChoicePromptOption]?
}

struct PromptEnvelopeV2: Decodable, Identifiable {
    let id: String
    let method: String
    let messageId: Int
    let playerId: String
    let responseKind: String
    let message: String
    let required: Bool?
    let minChoices: Int?
    let maxChoices: Int?
    let totalMin: Int?
    let totalMax: Int?
    let targetIds: [String]?
    let choices: [ChoicePromptOption]?
    let responseCommand: XmageResponseCommand?
    let cards: [ZoneCard]?
    let targets: [ChoicePromptOption]?
    let players: [XmagePromptPlayer]?
    let piles: [XmagePromptPile]?
    let abilities: [XmagePromptAbility]?
    let modes: [ChoicePromptOption]?
    let amounts: [Int]?
    let multiAmounts: [XmagePromptMultiAmount]?
    let manaChoices: [XmagePromptManaChoice]?
    let orderedItems: [ChoicePromptOption]?
    let confirmation: XmagePromptConfirmation?
    let options: [String: JSONValue]?
}

struct XmageResponseCommand: Decodable {
    let type: String?
    let promptId: String?
    let messageId: Int?
    let confirmed: Bool?
    let pay: Bool?
}

struct XmagePromptPile: Decodable, Identifiable {
    let id: String
    let label: String
    let cards: [ZoneCard]
}

extension XmagePromptPile {
    var explicitPileNumber: Int? {
        if id == "1" || id == "2" {
            return Int(id)
        }

        let normalizedId = id.lowercased()
        if normalizedId == "pile-1" || normalizedId == "pile_1" || normalizedId == "pile 1" {
            return 1
        }
        if normalizedId == "pile-2" || normalizedId == "pile_2" || normalizedId == "pile 2" {
            return 2
        }

        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedLabel == "pile 1" || normalizedLabel == "pile-1" || normalizedLabel == "pile_1" {
            return 1
        }
        if normalizedLabel == "pile 2" || normalizedLabel == "pile-2" || normalizedLabel == "pile_2" {
            return 2
        }

        return nil
    }
}

struct XmagePromptAbility: Decodable, Identifiable {
    let id: String
    let label: String
    let rulesText: String?
}

struct XmagePromptMultiAmount: Decodable, Identifiable {
    let id: String
    let label: String
    let min: Int
    let max: Int
    let defaultValue: Int?
}

struct XmagePromptPlayer: Decodable, Identifiable {
    let id: String
    let label: String
    let playerId: String
    let life: Int?
    let selectable: Bool?
}

struct XmagePromptManaChoice: Decodable, Identifiable {
    let id: String
    let label: String
    let manaType: String?
    let amount: Int?
}

struct XmagePromptConfirmation: Decodable {
    let yesLabel: String?
    let noLabel: String?
    let defaultValue: Bool?
    let yesCommand: XmageResponseCommand?
    let noCommand: XmageResponseCommand?
}

struct AttackDeclaration: Codable, Equatable {
    let attackerId: String
    let defenderId: String?
}

struct BlockDeclaration: Codable, Equatable {
    let blockerId: String
    let attackerId: String?
}

struct XmageMobileSnapshot: Decodable {
    let schemaVersion: Int
    let gameId: String
    let bridgeRevision: Int
    let xmageCycle: Int?
    let callbackCoverage: [String]
    let stack: [XmageStackObject]
    let combat: [XmageCombatGroup]
    let players: [XmageMobilePlayer]
    let exileZones: [XmageNamedZone]
    let revealed: [XmageNamedZone]
    let lookedAt: [XmageNamedZone]
    let companion: [XmageNamedZone]
    let playableObjects: [XmagePlayableObject]
    let panels: XmagePanels
}

struct XmageProtocolDebug: Decodable {
    let gameId: String?
    let source: String?
    let bridgeRevision: Int?
    let xmageCycle: Int?
    let pendingStatus: String?
    let priorityPlayerId: String?
    let waitingOnPlayerId: String?
    let legalActionCount: Int?
    let legalActionTypes: [String]?
    let promptSummary: XmageProtocolPromptSummary?
}

struct XmageProtocolPromptSummary: Decodable {
    let id: String?
    let method: String?
    let messageId: Int?
    let responseKind: String?
    let responseCommandType: String?
}

struct XmageMobilePlayer: Decodable, Identifiable {
    let playerId: String
    let xmagePlayerId: String?
    let name: String
    let active: Bool
    let hasPriority: Bool
    let timerActive: Bool
    let skipState: XmageSkipState
    let manaPool: ManaPool
    let command: [ZoneCard]
    let zones: XmagePlayerZones

    var id: String { playerId }
}

struct XmageSkipState: Decodable {
    let passedTurn: Bool
    let passedUntilEndOfTurn: Bool
    let passedUntilNextMain: Bool
    let passedUntilStackResolved: Bool
    let passedAllTurns: Bool
    let passedUntilEndStepBeforeMyTurn: Bool
}

struct XmagePlayerZones: Decodable {
    let battlefield: [ZoneCard]
    let graveyard: [ZoneCard]
    let exile: [ZoneCard]
    let sideboard: [ZoneCard]
}

struct XmageStackObject: Decodable, Identifiable {
    let id: String
    let objectId: String?
    let objectType: String?
    let name: String
    let rulesText: String?
    let sourceInstanceId: String?
    let sourceName: String?
    let sourceZone: String?
    let sourceCard: ZoneCard?
    let sourceCardUnavailableReason: String?
    let controllerId: String?
    let controllerXmageId: String?
    let targetIds: [String]?
    let paid: Bool?

    var displayName: String {
        name.isEmpty ? "Stack object" : name
    }

    var displaySourceName: String {
        displaySourceCard?.card.name ?? sourceName ?? "Source unavailable"
    }

    var syntheticTileTitle: String {
        if displayName.localizedCaseInsensitiveContains("ability") {
            return displayName
        }
        if objectType?.localizedCaseInsensitiveContains("ability") == true {
            return "Activated ability"
        }
        return displayName
    }

    var syntheticTileSubtitle: String {
        let source = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let source, !source.isEmpty {
            return source
        }
        return "Stack"
    }

    var syntheticTileDetail: String {
        if let rulesText, !rulesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rulesText
        }
        if let detail = compactFallbackDetail {
            return detail
        }
        return sourceCardUnavailableReason ?? "Source card image unavailable"
    }

    var displaySourceCard: ZoneCard? {
        guard let sourceCard, !sourceCard.isSyntheticStackAbilityPlaceholder else {
            return nil
        }
        return sourceCard
    }

    var compactFallbackDetail: String? {
        if let sourceCardUnavailableReason, !sourceCardUnavailableReason.isEmpty {
            return sourceCardUnavailableReason
        }
        if displaySourceCard == nil, displaySourceName != "Source unavailable" {
            return "Source: \(displaySourceName)"
        }
        return nil
    }

    var displayMetadata: String? {
        var parts: [String] = []
        if let controllerId, !controllerId.isEmpty {
            parts.append("Controller: \(controllerId)")
        }
        if let sourceZone, !sourceZone.isEmpty {
            parts.append("From: \(sourceZone)")
        }
        if let targetIds, !targetIds.isEmpty {
            parts.append("Targets: \(targetIds.count)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
}

struct XmageCombatGroup: Decodable, Identifiable {
    let defenderId: String
    let defenderName: String
    let defenderKind: String?
    let blocked: Bool
    let attackers: [ZoneCard]
    let blockers: [ZoneCard]

    var id: String { defenderId }
}

struct XmageNamedZone: Decodable, Identifiable {
    let id: String
    let name: String
    let cards: [ZoneCard]
}

struct XmagePlayableObject: Decodable, Identifiable {
    let sourceInstanceId: String
    let sourceZone: String?
    let cardName: String
    let categories: [String]
    let abilities: [XmagePlayableAbility]

    var id: String { sourceInstanceId }
}

struct XmagePlayableAbility: Decodable, Identifiable {
    let id: String
    let label: String
    let category: String
}

struct XmagePanels: Decodable {
    let stack: Bool
    let command: Bool
    let graveyard: Bool
    let exile: Bool
    let revealed: Bool
    let lookedAt: Bool
    let search: Bool
}

indirect enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            let intValue = Int(value)
            return value == Double(intValue) ? String(intValue) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array, .object, .null:
            return nil
        }
    }

    var stringArrayValue: [String]? {
        switch self {
        case .array(let values):
            let strings = values.compactMap(\.stringValue)
            return strings.count == values.count ? strings : nil
        case .string(let value):
            return [value]
        case .number, .bool, .object, .null:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            if ["true", "yes"].contains(value.lowercased()) { return true }
            if ["false", "no"].contains(value.lowercased()) { return false }
            return nil
        case .number(let value):
            return value != 0
        case .array, .object, .null:
            return nil
        }
    }
}

struct GameCommand: Encodable {
    let type: String
    let gameId: String
    let playerId: String
    let cardInstanceId: String?
    let sourceInstanceId: String?
    let abilityId: String?
    let promptId: String?
    let messageId: Int?
    let choiceIds: [String]?
    let targetIds: [String]?
    let cardInstanceIds: [String]?
    let modeIds: [String]?
    let sourceInstanceIds: [String]?
    let paymentId: String?
    let abilityIdChoice: String?
    let pile: Int?
    let amount: Int?
    let amounts: [Int]?
    let orderedIds: [String]?
    let useCommandZone: Bool?
    let manaType: String?
    let manaTypes: [String]?
    let playerIds: [String]?
    let confirmed: Bool?
    let pay: Bool?
    let sourceZone: String?
    let fromZone: String?
    let cardName: String?
    let attackers: [AttackDeclaration]?
    let blockers: [BlockDeclaration]?
    let combatComplete: Bool?
    let expectedBridgeRevision: Int?

    init(
        type: String,
        gameId: String,
        playerId: String,
        cardInstanceId: String? = nil,
        sourceInstanceId: String? = nil,
        abilityId: String? = nil,
        promptId: String? = nil,
        messageId: Int? = nil,
        choiceIds: [String]? = nil,
        targetIds: [String]? = nil,
        cardInstanceIds: [String]? = nil,
        modeIds: [String]? = nil,
        sourceInstanceIds: [String]? = nil,
        paymentId: String? = nil,
        abilityIdChoice: String? = nil,
        pile: Int? = nil,
        amount: Int? = nil,
        amounts: [Int]? = nil,
        orderedIds: [String]? = nil,
        useCommandZone: Bool? = nil,
        manaType: String? = nil,
        manaTypes: [String]? = nil,
        playerIds: [String]? = nil,
        confirmed: Bool? = nil,
        pay: Bool? = nil,
        sourceZone: String? = nil,
        fromZone: String? = nil,
        cardName: String? = nil,
        attackers: [AttackDeclaration]? = nil,
        blockers: [BlockDeclaration]? = nil,
        combatComplete: Bool? = nil,
        expectedBridgeRevision: Int? = nil
    ) {
        self.type = type
        self.gameId = gameId
        self.playerId = playerId
        self.cardInstanceId = cardInstanceId
        self.sourceInstanceId = sourceInstanceId
        self.abilityId = abilityId
        self.promptId = promptId
        self.messageId = messageId
        self.choiceIds = choiceIds
        self.targetIds = targetIds
        self.cardInstanceIds = cardInstanceIds
        self.modeIds = modeIds
        self.sourceInstanceIds = sourceInstanceIds
        self.paymentId = paymentId
        self.abilityIdChoice = abilityIdChoice
        self.pile = pile
        self.amount = amount
        self.amounts = amounts
        self.orderedIds = orderedIds
        self.useCommandZone = useCommandZone
        self.manaType = manaType
        self.manaTypes = manaTypes
        self.playerIds = playerIds
        self.confirmed = confirmed
        self.pay = pay
        self.sourceZone = sourceZone
        self.fromZone = fromZone
        self.cardName = cardName
        self.attackers = attackers
        self.blockers = blockers
        self.combatComplete = combatComplete
        self.expectedBridgeRevision = expectedBridgeRevision
    }
}

extension CardIdentity {
    public var isLand: Bool {
        typeLine.localizedCaseInsensitiveContains("land")
    }

    public var isCreature: Bool {
        typeLine.localizedCaseInsensitiveContains("creature")
    }

    public var isPlaneswalker: Bool {
        typeLine.localizedCaseInsensitiveContains("planeswalker")
    }

    public var isArtifact: Bool {
        typeLine.localizedCaseInsensitiveContains("artifact")
    }

    public var isEnchantment: Bool {
        typeLine.localizedCaseInsensitiveContains("enchantment")
    }
}

extension ZoneCard {
    public var isCreature: Bool {
        isCreaturePermanent ?? card.isCreature
    }

    public var showsPowerToughness: Bool {
        power != nil && toughness != nil && isCreature
    }

    public var isPromptSelectable: Bool {
        selectable ?? true
    }

    var isSyntheticStackAbilityPlaceholder: Bool {
        let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let type = card.typeLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name == "ability" || name == "activated ability" || name == "triggered ability" || type == "card"
    }

    func accessibilityLabel(zoneName: String? = nil, selected: Bool = false, legal: Bool = false, pending: Bool = false) -> String {
        var parts = ["\(zoneName?.isEmpty == false ? zoneName! : "Game") card", card.name]
        if !card.typeLine.isEmpty {
            parts.append(card.typeLine)
        }
        if tapped == true {
            parts.append("tapped")
        }
        if summoningSickness == true {
            parts.append("summoning sick")
        }
        let iconHints = visibleXmageIcons.compactMap(\.displayText)
        if !iconHints.isEmpty {
            parts.append(contentsOf: iconHints)
        }
        if isAttacking == true {
            parts.append("attacking")
        }
        if showsPowerToughness, let power, let toughness {
            parts.append("\(power)/\(toughness)")
        }
        let counterHints = counterBadges.map { "\($0.label) counter \($0.count)" }
        if !counterHints.isEmpty {
            parts.append(contentsOf: counterHints)
        }
        if legal {
            parts.append("playable")
        }
        if pending {
            parts.append("pending")
        }
        if selected {
            parts.append("selected")
        }
        return parts.joined(separator: ", ")
    }

    func accessibilityIdentifier(zoneName: String? = nil) -> String {
        let zone = Self.accessibilitySlug(zoneName?.isEmpty == false ? zoneName! : "game")
        let name = Self.accessibilitySlug(card.name)
        let shortId = Self.accessibilitySlug(String(instanceId.prefix(8)))
        return "card-\(zone)-\(name)-\(shortId)"
    }

    private static func accessibilitySlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
    }
}

struct XmageCardIcon: Decodable, Hashable {
    let iconType: String
    let resourceName: String?
    let category: String?
    let text: String?
    let hint: String?

    var displayText: String? {
        for value in [text, hint] {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

extension ZoneCard {
    var visibleXmageIcons: [XmageCardIcon] {
        (cardIcons ?? []).filter { icon in
            guard icon.category?.caseInsensitiveCompare("ABILITY") == .orderedSame || icon.category?.caseInsensitiveCompare("COMMANDER") == .orderedSame else {
                return false
            }
            return CardImageURL.xmageIconAssetName(for: icon.iconType) != nil
        }
    }

    var counterBadges: [CardCounterBadge] {
        (counters ?? [:])
            .filter { $0.value > 0 }
            .map { CardCounterBadge(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                return lhs.label < rhs.label
            }
    }
}

struct CardCounterBadge: Hashable {
    let name: String
    let count: Int

    var label: String {
        let lower = name.lowercased()
        if lower.contains("+1") || lower.contains("p1p1") {
            return "+1/+1"
        }
        if lower.contains("-1") || lower.contains("m1m1") {
            return "-1/-1"
        }
        if lower.contains("loyalty") {
            return "LOY"
        }
        if lower.contains("shield") {
            return "SHD"
        }
        return name
            .replacingOccurrences(of: " counter", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "counter", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    var priority: Int {
        let lower = name.lowercased()
        if lower.contains("+1") || lower.contains("p1p1") { return 0 }
        if lower.contains("-1") || lower.contains("m1m1") { return 1 }
        if lower.contains("loyalty") { return 2 }
        if lower.contains("shield") { return 3 }
        return 4
    }
}
