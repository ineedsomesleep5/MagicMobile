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

    var human: PlayerGameState? {
        players.first { $0.playerId == "human" }
    }

    var opponent: PlayerGameState? {
        players.first { $0.playerId != "human" }
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
            return "XMage did not accept that play. Refresh and try again."
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
        if after.pendingStatus == "waiting_for_xmage" { return .waiting }

        guard let cardId = action.cardInstanceId ?? action.sourceInstanceId else {
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
        guard action.type == "cast_spell" else { return false }
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

struct CommanderStartupResponse: Decodable {
    let startupId: String
    let status: String
    let snapshot: GameSnapshot?
    let message: String?
    let error: String?
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

    var id: String { instanceId }
}

struct CardIdentity: Decodable, Hashable {
    let name: String
    let typeLine: String
    let oracleText: String?
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
    let pile: String?
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

struct AttackDeclaration: Codable {
    let attackerId: String
    let defenderId: String?
}

struct BlockDeclaration: Codable {
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
    let name: String
    let rulesText: String?
    let sourceInstanceId: String?
    let sourceName: String?
    let sourceZone: String?
    let sourceCard: ZoneCard?
    let controllerId: String?
    let controllerXmageId: String?
    let targetIds: [String]?
    let paid: Bool?

    var displayName: String {
        name.isEmpty ? "Stack object" : name
    }

    var displaySourceName: String {
        sourceCard?.card.name ?? sourceName ?? "Source unavailable"
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
