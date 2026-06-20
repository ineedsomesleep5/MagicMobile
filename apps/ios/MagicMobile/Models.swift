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
    let engineHealth: EngineHealth?

    var human: PlayerGameState? {
        players.first { $0.playerId == "human" }
    }

    var opponent: PlayerGameState? {
        players.first { $0.playerId != "human" }
    }
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
    let zones: PlayerZones

    var id: String { playerId }
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
    let sourceInstanceId: String?
    let targetIds: [String]?
    let commandTemplate: [String: String]?
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
}
