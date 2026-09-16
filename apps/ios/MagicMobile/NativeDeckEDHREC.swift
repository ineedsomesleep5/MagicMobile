import Foundation

/// Manual website handoff only: never embeds deck data in a URL or makes requests.
struct NativeDeckEDHREC {
    static let websiteURL = URL(string: "https://edhrec.com/recs")!
    let commanders: [String]
    let deckText: String

    init(deck: DeckList) {
        func section(_ entry: DeckEntry) -> String {
            entry.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var names = deck.commander.map { [$0.cardName] } ?? []
        for entry in deck.entries where ["commander", "commanders"].contains(section(entry)) {
            if !names.contains(entry.cardName) { names.append(entry.cardName) }
        }
        commanders = names
        // The website asks for commanders separately. Do not silently include sideboards,
        // companions or unrecognized draft sections in the main-deck paste.
        deckText = deck.entries.filter { ["main", "deck"].contains(section($0)) }
            .map { "\($0.quantity) \($0.cardName)" }.joined(separator: "\n")
    }
}
