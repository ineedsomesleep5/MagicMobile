import Foundation
import CoreFoundation
import MagicMobileOnDevice

/// Release selection is deliberately independent of launch arguments. An
/// unlinked Release can never fall back to the legacy desktop/server client.
enum OnDeviceAppConfiguration {
    enum EntryPoint: Equatable { case embedded, setupPreview, referencePreview, engineMissing }

    static func aiGameSeats(name: String, humanDeck: MagicMobileOnDevice.JSONValue,
                            aiDecks: [MagicMobileOnDevice.JSONValue],
                            aiSkill: Int) throws -> [MagicMobileOnDevice.JSONValue] {
        guard (1...3).contains(aiDecks.count) else { throw EngineError.invalidMessage("Choose 1–3 AI opponents.") }
        guard (1...10).contains(aiSkill) else { throw EngineError.invalidMessage("Choose AI skill from 1–10.") }
        return [.object(["seatId": .string("player1"), "name": .string(name),
                         "controller": .string("human"), "deck": humanDeck])] + aiDecks.enumerated().map { offset, aiDeck in
            let index = offset + 1
            return .object(["seatId": .string("player\(index + 1)"), "name": .string("AI \(index)"),
                     "controller": .string("ai"), "deck": aiDeck, "aiSkill": .number(Double(aiSkill))])
        }
    }

    static func select(engineLinked: Bool, debug: Bool, arguments: [String]) -> EntryPoint {
        if engineLinked { return .embedded }
        guard debug else { return .engineMissing }
        return arguments.contains("--ondevice-setup-ui-test") ? .setupPreview : .referencePreview
    }

    static var entryPoint: EntryPoint {
        #if XMAGE_NATIVE_LINKED
        let linked = true
        #else
        let linked = false
        #endif
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return select(engineLinked: linked, debug: debug, arguments: ProcessInfo.processInfo.arguments)
    }
}

/// Only setup preferences are saved here. These keys never contain an engine
/// handle, peer credential, hidden game state, or a resumable-match claim.
enum OnDeviceSetupPreferences {
    static let deckKey = "magicmobile.ondevice.selectedDeckID"
    static let aiDeckKey = "magicmobile.ondevice.aiPreconID"
    static let aiDeck2Key = "magicmobile.ondevice.aiPreconID2"
    static let aiDeck3Key = "magicmobile.ondevice.aiPreconID3"
    static let aiCountKey = "magicmobile.ondevice.aiOpponentCount"
    static let aiSkillKey = "magicmobile.ondevice.aiSkill"
    static let humanCountKey = "magicmobile.ondevice.humanPlayerCount"
    static let friendsKey = "magicmobile.ondevice.playWithFriends"
    static let defaultDeckID = "precon:token-triumph"
    static let defaultAIDeckID = "grave-danger"

    static func normalizedAIDeckIDs(_ saved: [String], available: [String]) -> [String] {
        let fallback = available.contains(defaultAIDeckID) ? defaultAIDeckID : (available.first ?? "")
        let first = saved.first.flatMap { available.contains($0) ? $0 : nil } ?? fallback
        return (0..<3).map { index in
            index < saved.count && available.contains(saved[index]) ? saved[index] : first
        }
    }

    struct Selection: Equatable {
        var deckID: String
        var aiDeckID: String
        var aiOpponents: Int
        var humanPlayers: Int
        var friends: Bool
        var aiSkill: Int = 2
    }

    static func normalize(_ saved: Selection, deckIDs: Set<String>, aiDeckIDs: [String]) -> Selection {
        let fallbackAI = aiDeckIDs.contains(defaultAIDeckID) ? defaultAIDeckID : (aiDeckIDs.first ?? "")
        let fallbackDeck = deckIDs.contains(defaultDeckID) ? defaultDeckID : (deckIDs.sorted().first ?? "")
        return Selection(deckID: deckIDs.contains(saved.deckID) ? saved.deckID : fallbackDeck,
                         aiDeckID: aiDeckIDs.contains(saved.aiDeckID) ? saved.aiDeckID : fallbackAI,
                         aiOpponents: min(3, max(1, saved.aiOpponents)),
                         humanPlayers: min(4, max(2, saved.humanPlayers)), friends: saved.friends,
                         aiSkill: min(10, max(1, saved.aiSkill)))
    }

    static func read(from defaults: UserDefaults, deckIDs: Set<String>, aiDeckIDs: [String]) -> Selection {
        normalize(Selection(deckID: defaults.string(forKey: deckKey) ?? defaultDeckID,
                            aiDeckID: defaults.string(forKey: aiDeckKey) ?? defaultAIDeckID,
                            aiOpponents: defaults.object(forKey: aiCountKey) == nil ? 1 : defaults.integer(forKey: aiCountKey),
                            humanPlayers: defaults.object(forKey: humanCountKey) == nil ? 2 : defaults.integer(forKey: humanCountKey),
                            friends: defaults.bool(forKey: friendsKey), aiSkill: readAISkill(from: defaults)), deckIDs: deckIDs, aiDeckIDs: aiDeckIDs)
    }

    static func readAISkill(from defaults: UserDefaults) -> Int {
        guard let number = defaults.object(forKey: aiSkillKey) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else { return 2 }
        return Int(min(10, max(1, number.doubleValue)))
    }

    static func save(_ selection: Selection, to defaults: UserDefaults) {
        defaults.set(selection.deckID, forKey: deckKey)
        defaults.set(selection.aiDeckID, forKey: aiDeckKey)
        defaults.set(selection.aiOpponents, forKey: aiCountKey)
        defaults.set(min(10, max(1, selection.aiSkill)), forKey: aiSkillKey)
        defaults.set(selection.humanPlayers, forKey: humanCountKey)
        defaults.set(selection.friends, forKey: friendsKey)
    }
}
