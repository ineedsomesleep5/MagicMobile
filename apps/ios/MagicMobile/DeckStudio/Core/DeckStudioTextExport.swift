import Foundation

/// Interchange for the standard boards supported by plain-text deck importers.
/// JSON remains the lossless choice for custom sections or decorated names.
enum DeckStudioTextExport {
    enum ExportError: LocalizedError {
        case requiresJSON
        var errorDescription: String? { "Use JSON export for empty drafts, custom sections or unusual card names." }
    }
    static func text(_ deck: DeckList) throws -> String {
        let entries = (deck.commander.map { [DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "commanders")] } ?? []) + deck.entries
        guard !entries.isEmpty else { throw ExportError.requiresJSON }
        var groups: [String: [DeckEntry]] = [:]
        for entry in entries {
            let section: String
            switch entry.section.lowercased() {
            case "deck", "main", "mainboard": section = "Deck"
            case "commander", "commanders": section = "Commander"
            case "companion", "companions": section = "Companion"
            case "sideboard": section = "Sideboard"
            case "maybeboard", "considering": section = "Maybeboard"
            default: throw ExportError.requiresJSON
            }
            groups[section, default: []].append(entry)
        }
        let text = ["Commander", "Deck", "Companion", "Sideboard", "Maybeboard"].compactMap { section -> String? in
            guard let rows = groups[section], !rows.isEmpty else { return nil }
            return section + "\n" + rows.map { "\($0.quantity) \($0.cardName)" }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
        // Verify the actual importer preserves every name/quantity/board before sharing.
        let decoded = try OnDeviceDeckEditing.importText(text, name: deck.name).deck
        func counts(_ values: [DeckEntry]) -> [String: Int] {
            var result: [String: Int] = [:]
            for value in values { result["\(value.section)\u{0}\(value.cardName)", default: 0] += value.quantity }
            return result
        }
        let expected = groups.flatMap { key, values in values.map { DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: key == "Commander" ? "commanders" : key == "Companion" ? "companions" : key.lowercased()) } }
        let actual = (decoded.commander.map { [DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "commanders")] } ?? []) + decoded.entries
        guard counts(expected) == counts(actual) else { throw ExportError.requiresJSON }
        return text
    }
}
