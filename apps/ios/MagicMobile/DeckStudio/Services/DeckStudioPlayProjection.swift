import Foundation
import MagicMobileOnDevice

/// Draft boards remain intact. Only explicit side/maybeboard sections are
/// excluded from a *separate* playing projection; unknown sections need review.
struct DeckStudioPlayProjection {
    let original: DeckList
    let playing: DeckList
    let excluded: [DeckEntry]
    init(_ deck: DeckList) throws {
        try OnDeviceDeckEditing.validateDraft(deck)
        var included: [DeckEntry] = [], excluded: [DeckEntry] = []
        for row in deck.entries {
            switch row.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "main", "deck", "commander", "commanders", "companion", "companions": included.append(row)
            case "sideboard", "maybeboard", "considering": excluded.append(row)
            default: throw OnDeviceDeckResolver.ResolutionError("Map section '\(row.section)' to Main, Commander, Companion, Sideboard or Maybeboard before validating. No cards have been discarded.")
            }
        }
        self.original = deck
        self.playing = DeckList(name: deck.name, commander: deck.commander, entries: included)
        self.excluded = excluded
    }
    func resolve(_ resolver: OnDeviceDeckResolver) throws -> MagicMobileOnDevice.JSONValue { try resolver.resolve(playing) }
    func signature(_ resolver: OnDeviceDeckResolver) throws -> DeckStudioDeckSignature {
        let data = try resolve(resolver).encoded()
        guard let value = DeckStudioJSON.object(data) else { throw DeckStudioDeckSignature.Failure.invalidDeck }
        return try DeckStudioDeckSignature.native(value)
    }
}
