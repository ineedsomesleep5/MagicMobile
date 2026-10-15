import Foundation

/// An AI opponent's deck: the included precons (Core) plus ai-decks.json, built from EDHREC's
/// average decks per bracket (scripts/ranked/build_ai_decks.py). Players may play them too.
struct AIDeck: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let colors: String
    let commander: String
    let bracket: CommanderBracket
    let deckList: DeckList

    /// The setup screen's deck ID when a player picks one of these decks for themselves.
    var playerDeckID: String { "included:\(id)" }
    /// An official precon; ai-decks.json IDs all start with "ai-".
    var isPrecon: Bool { !id.hasPrefix("ai-") }
}

enum AIDeckPool {
    private struct File: Decodable {
        struct Deck: Decodable {
            struct Entry: Decodable { let name: String; let quantity: Int; let section: String }
            let id: String
            let name: String
            let subtitle: String
            let colors: String
            let commander: String
            let bracket: Int
            let entries: [Entry]
        }
        let decks: [Deck]
    }

    static func decode(_ data: Data) throws -> [AIDeck] {
        try JSONDecoder().decode(File.self, from: data).decks.map { deck in
            let commander = deck.entries.first { $0.section == "commander" }
            return AIDeck(id: deck.id, name: deck.name, subtitle: deck.subtitle, colors: deck.colors, commander: deck.commander,
                          bracket: CommanderBracket(clamping: deck.bracket),
                          deckList: DeckList(name: deck.name,
                                             commander: commander.map { DeckEntry(cardName: $0.name, quantity: 1, section: "commander") },
                                             entries: deck.entries.filter { $0.section != "commander" }
                                                 .map { DeckEntry(cardName: $0.name, quantity: $0.quantity, section: "deck") }))
        }
    }

    /// The bundled bracket decks (ai-decks.json), without the precons.
    static let bracketDecks: [AIDeck] = {
        guard let url = Bundle.main.url(forResource: "ai-decks", withExtension: "json"),
              let data = try? Data(contentsOf: url), let decks = try? decode(data) else { return [] }
        return decks
    }()

    /// Every AI deck: the precons first (Core; their IDs are the precon IDs saved games already use).
    static let all: [AIDeck] = PreconCatalog.all.map { precon in
        AIDeck(id: precon.id, name: precon.name, subtitle: precon.subtitle, colors: precon.colors,
               commander: precon.commander, bracket: .core, deckList: precon.deckList)
    } + bracketDecks

    static func deck(id: String) -> AIDeck? { all.first { $0.id == id } }

    /// Precons, by the ID a player's deck picker saves.
    static func playerDeck(id: String) -> AIDeck? {
        guard id.hasPrefix("included:") else { return nil }
        return bracketDecks.first { $0.playerDeckID == id }
    }

    static func decks(in bracket: CommanderBracket) -> [AIDeck] { all.filter { $0.bracket == bracket } }

    /// The pool for a bracket. cEDH borrows Optimized; an empty bracket borrows its nearest neighbour.
    static func pool(for bracket: Int, in decks: [AIDeck] = all) -> [AIDeck] {
        let wanted = min(4, max(1, bracket))
        for distance in 0...3 {
            for candidate in [wanted - distance, wanted + distance] where (1...4).contains(candidate) {
                let found = decks.filter { $0.bracket.rawValue == candidate }
                if !found.isEmpty { return found }
            }
        }
        return decks
    }

    /// The softest precons in the AI's hands, for Bronze ranked: an equal-skill round-robin of all five (C3, 2026-10-15,
    /// 200 games) put Chaos Incarnate at 36%, Grave Danger 45% and Token Triumph 50%, against First Flight 56% and
    /// Draconic Destruction 62% (docs/cloud/reports/c3.md).
    static let gentlestPrecons: Set<String> = ["chaos-incarnate", "grave-danger", "token-triumph"]

    /// An AI deck for this bracket: never your own commander, and not one of the last few you faced
    /// while others remain. `preconsOnly` keeps to the official precons, and `onlyPrecons` narrows them further
    /// when any of those are present. `roll` picks among what is left (injectable for tests).
    static func pick(bracket: Int, avoidingCommander commander: String?, recent: [String], preconsOnly: Bool = false,
                     onlyPrecons: Set<String>? = nil,
                     in decks: [AIDeck] = all, roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> AIDeck? {
        var precons = decks.filter(\.isPrecon)
        if let onlyPrecons, precons.contains(where: { onlyPrecons.contains($0.id) }) { precons.removeAll { !onlyPrecons.contains($0.id) } }
        var candidates = pool(for: bracket, in: preconsOnly && !precons.isEmpty ? precons : decks)
        if let commander, candidates.contains(where: { $0.commander != commander }) {
            candidates.removeAll { $0.commander == commander }
        }
        let fresh = candidates.filter { !recent.contains($0.id) }
        if !fresh.isEmpty { candidates = fresh }
        guard !candidates.isEmpty else { return nil }
        return candidates[min(candidates.count - 1, max(0, roll(candidates.count)))]
    }
}
