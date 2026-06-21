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

struct CommanderStartupResponse: Decodable {
    let startupId: String
    let status: String
    let snapshot: GameSnapshot?
    let message: String?
    let error: String?
}

struct GameLogEntry: Decodable, Identifiable {
    let id: String
    let message: String
    let createdAt: String?
}

struct PlayerGameState: Decodable, Identifiable {
    let playerId: String
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
    let counters: [String: Int]?
    let power: Int?
    let toughness: Int?
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
    let cardInstanceId: String?
    let sourceZone: String?
    let sourceInstanceId: String?
    let abilityId: String?
    let targetIds: [String]?
    let validTargetIds: [String]?
    let playerIds: [String]?
    let validPlayerIds: [String]?
    let choiceIds: [String]?
    let modeIds: [String]?
    let orderedIds: [String]?
    let amount: Int?
    let amounts: [Int]?
    let manaType: String?
    let pile: String?
    let confirmed: Bool?
    let isPrimary: Bool?
    let requiresTarget: Bool?
    let responseKind: String?
    let messageId: Int?
    let minChoices: Int?
    let maxChoices: Int?
    let zoneContext: String?
    let shortLabel: String?
    let commandTemplate: [String: String]?
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
    let targetIds: [String]?
    let choices: [ChoicePromptOption]?
    let responseCommand: XmageResponseCommand?
    let cards: [ZoneCard]?
    let targets: [ChoicePromptOption]?
    let piles: [XmagePromptPile]?
    let abilities: [XmagePromptAbility]?
    let modes: [ChoicePromptOption]?
    let amounts: [Int]?
    let options: [String: JSONValue]?
}

struct XmageResponseCommand: Decodable {
    let type: String?
    let promptId: String?
}

struct XmagePromptPile: Decodable, Identifiable {
    let id: String
    let label: String
    let cards: [ZoneCard]
}

struct XmagePromptAbility: Decodable, Identifiable {
    let id: String
    let label: String
    let rulesText: String?
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
    let sourceCard: ZoneCard?
    let paid: Bool?
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

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
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

    init(
        type: String,
        gameId: String,
        playerId: String,
        cardInstanceId: String? = nil,
        sourceInstanceId: String? = nil,
        abilityId: String? = nil,
        promptId: String? = nil,
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
        confirmed: Bool? = nil
    ) {
        self.type = type
        self.gameId = gameId
        self.playerId = playerId
        self.cardInstanceId = cardInstanceId
        self.sourceInstanceId = sourceInstanceId
        self.abilityId = abilityId
        self.promptId = promptId
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
    }
}
