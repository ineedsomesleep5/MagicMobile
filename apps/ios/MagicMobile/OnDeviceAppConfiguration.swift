import Foundation

/// Release selection is deliberately independent of launch arguments. An
/// unlinked Release can never fall back to the legacy desktop/server client.
enum OnDeviceAppConfiguration {
    enum EntryPoint: Equatable { case embedded, setupPreview, referencePreview, engineMissing }

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
    static let aiCountKey = "magicmobile.ondevice.aiOpponentCount"
    static let humanCountKey = "magicmobile.ondevice.humanPlayerCount"
    static let friendsKey = "magicmobile.ondevice.playWithFriends"
    static let defaultDeckID = "precon:token-triumph"
    static let defaultAIDeckID = "grave-danger"

    struct Selection: Equatable {
        var deckID: String
        var aiDeckID: String
        var aiOpponents: Int
        var humanPlayers: Int
        var friends: Bool
    }

    static func normalize(_ saved: Selection, deckIDs: Set<String>, aiDeckIDs: [String]) -> Selection {
        let fallbackAI = aiDeckIDs.contains(defaultAIDeckID) ? defaultAIDeckID : (aiDeckIDs.first ?? "")
        let fallbackDeck = deckIDs.contains(defaultDeckID) ? defaultDeckID : (deckIDs.sorted().first ?? "")
        return Selection(deckID: deckIDs.contains(saved.deckID) ? saved.deckID : fallbackDeck,
                         aiDeckID: aiDeckIDs.contains(saved.aiDeckID) ? saved.aiDeckID : fallbackAI,
                         aiOpponents: min(3, max(1, saved.aiOpponents)),
                         humanPlayers: min(4, max(2, saved.humanPlayers)), friends: saved.friends)
    }

    static func read(from defaults: UserDefaults, deckIDs: Set<String>, aiDeckIDs: [String]) -> Selection {
        normalize(Selection(deckID: defaults.string(forKey: deckKey) ?? defaultDeckID,
                            aiDeckID: defaults.string(forKey: aiDeckKey) ?? defaultAIDeckID,
                            aiOpponents: defaults.object(forKey: aiCountKey) == nil ? 1 : defaults.integer(forKey: aiCountKey),
                            humanPlayers: defaults.object(forKey: humanCountKey) == nil ? 2 : defaults.integer(forKey: humanCountKey),
                            friends: defaults.bool(forKey: friendsKey)), deckIDs: deckIDs, aiDeckIDs: aiDeckIDs)
    }

    static func save(_ selection: Selection, to defaults: UserDefaults) {
        defaults.set(selection.deckID, forKey: deckKey)
        defaults.set(selection.aiDeckID, forKey: aiDeckKey)
        defaults.set(selection.aiOpponents, forKey: aiCountKey)
        defaults.set(selection.humanPlayers, forKey: humanCountKey)
        defaults.set(selection.friends, forKey: friendsKey)
    }
}
