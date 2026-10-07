import Foundation

/// The editor history validates and commits a candidate atomically. One Undo
/// reverses a whole replacement, commander promotion, or basic-land operation.
enum DeckStudioEditorOperations {
    static func replaceCard(in draft: inout NativeDeckDraft, rowID: UUID, name: String) throws {
        guard let index = draft.rows.firstIndex(where: { $0.id == rowID }) else { throw OnDeviceDeckEditing.Error.missingEntry }
        draft.rows[index].cardName = name
        draft.rows[index].printing = nil
    }
    static func replacePrimaryCommander(in draft: inout NativeDeckDraft, name: String, keepOld: Bool) throws {
        let primary = draft.rows.firstIndex(where: { $0.isPrimaryCommander }) ?? draft.rows.firstIndex(where: {
            ["commander", "commanders"].contains($0.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        })
        if let primary, draft.rows[primary].cardName == name { return }
        if let primary {
            let old = draft.rows[primary]
            draft.rows[primary].cardName = name
            draft.rows[primary].quantity = 1
            draft.rows[primary].section = "commanders"
            draft.rows[primary].isPrimaryCommander = true
            draft.rows[primary].printing = nil
            if keepOld { draft.rows.append(.init(cardName: old.cardName, quantity: old.quantity, section: "maybeboard", printing: old.printing)) }
        } else { draft.rows.insert(.init(cardName: name, section: "commanders", isPrimaryCommander: true), at: 0) }
        // Explicit promotion moves one main-deck copy; partners and other boards stay intact.
        if let index = draft.rows.firstIndex(where: { !$0.isPrimaryCommander && $0.cardName == name && ["main", "deck"].contains($0.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
            // The commander keeps the art the promoted copy had.
            if let commander = draft.rows.firstIndex(where: { $0.isPrimaryCommander && $0.cardName == name }), draft.rows[commander].printing == nil {
                draft.rows[commander].printing = draft.rows[index].printing
            }
            if draft.rows[index].quantity == 1 { draft.rows.remove(at: index) }
            else { draft.rows[index].quantity -= 1 }
        }
    }
    static func setBasicLands(in draft: inout NativeDeckDraft, quantities: [String: Int]) throws {
        guard Set(quantities.keys) == Set(NativeDeckDraft.basicLandNames) else { throw OnDeviceDeckEditing.Error.invalidEntry }
        var candidate = draft
        for name in NativeDeckDraft.basicLandNames where quantities[name]! < candidate.basicLandCount(name) {
            try candidate.setBasicLandCount(name, quantity: quantities[name]!)
        }
        for name in NativeDeckDraft.basicLandNames { try candidate.setBasicLandCount(name, quantity: quantities[name]!) }
        draft = candidate
    }

    /// Adds `quantity` copies to an existing row on the same board, or appends one row.
    static func add(in draft: inout NativeDeckDraft, name: String, quantity: Int, section: String) throws {
        guard (1...2000).contains(quantity), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnDeviceDeckEditing.Error.invalidEntry
        }
        let board = DeckStudioBoard.normalized(section)
        if let index = draft.rows.firstIndex(where: { $0.cardName == name && DeckStudioBoard.of($0) == board }) {
            let (next, overflow) = draft.rows[index].quantity.addingReportingOverflow(quantity)
            guard !overflow else { throw OnDeviceDeckEditing.Error.invalidEntry }
            draft.rows[index].quantity = next
        } else { draft.rows.append(NativeDeckRow(cardName: name, quantity: quantity, section: section)) }
    }

    /// Commander-first new decks: the chosen card leads the deck, and an untouched
    /// default name becomes the commander's name.
    static func startWithCommander(in draft: inout NativeDeckDraft, name: String) throws {
        try replacePrimaryCommander(in: &draft, name: name, keepOld: false)
        let current = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == NativeDeckDraft().name { draft.name = String(name.prefix(96)) }
    }

    /// Bulk edits commit as one history step. Every selected row must still exist,
    /// so an edit made against a stale selection changes nothing.
    static func moveRows(in draft: inout NativeDeckDraft, ids: Set<UUID>, to section: String) throws {
        try requireRows(ids, in: draft)
        for index in draft.rows.indices where ids.contains(draft.rows[index].id) {
            draft.rows[index].section = section
            draft.rows[index].isPrimaryCommander = false
        }
    }
    static func setQuantity(in draft: inout NativeDeckDraft, ids: Set<UUID>, quantity: Int) throws {
        guard (1...2000).contains(quantity) else { throw OnDeviceDeckEditing.Error.invalidEntry }
        try requireRows(ids, in: draft)
        for index in draft.rows.indices where ids.contains(draft.rows[index].id) { draft.rows[index].quantity = quantity }
    }
    static func removeRows(in draft: inout NativeDeckDraft, ids: Set<UUID>) throws {
        try requireRows(ids, in: draft)
        draft.rows.removeAll { ids.contains($0.id) }
    }
    private static func requireRows(_ ids: Set<UUID>, in draft: NativeDeckDraft) throws {
        guard !ids.isEmpty, ids.isSubset(of: Set(draft.rows.map(\.id))) else { throw OnDeviceDeckEditing.Error.missingEntry }
    }
}

/// Board names shared by the quick check, text diff, sample hand and bulk edits.
/// "considering" is the maybeboard, as in the text export and the play projection.
enum DeckStudioBoard {
    static let playing: Set<String> = ["deck", "commanders", "companions"]
    static func normalized(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "deck", "main": return "deck"
        case "commander", "commanders": return "commanders"
        case "companion", "companions": return "companions"
        case "maybeboard", "considering": return "maybeboard"
        case let other: return other
        }
    }
    static func of(_ row: NativeDeckRow) -> String { row.isPrimaryCommander ? "commanders" : normalized(row.section) }
}

/// Quick Add grammar: an optional count ("2 " or "2x "), then the card name. A
/// trailing printing "(set)" / "(set) 123" and "[tag]" are ignored and reported.
struct DeckStudioQuickAdd: Equatable {
    let quantity: Int
    let name: String
    let ignored: [String]

    var note: String? { ignored.isEmpty ? nil : "Ignored \(ignored.joined(separator: " ")) · sets and tags aren't saved" }

    /// `isCardName` lets an exact card name that starts with a number win over the count.
    static func parse(_ raw: String, isCardName: (String) -> Bool = { _ in false }) -> DeckStudioQuickAdd? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 2000 else { return nil }
        var ignored: [String] = []
        while let range = text.range(of: #"\s*(?:\[[^\[\]]*\]|\([A-Za-z0-9]{2,6}\)(?:\s+[A-Za-z0-9★†-]+)?)$"#, options: .regularExpression) {
            ignored.insert(text[range].trimmingCharacters(in: .whitespaces), at: 0)
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        if isCardName(text) { return DeckStudioQuickAdd(quantity: 1, name: text, ignored: ignored) }
        // A count with no name yet ("2x") is still being typed.
        guard text.range(of: #"^[0-9]{1,4}[xX]?$"#, options: .regularExpression) == nil else { return nil }
        var quantity = 1
        if let match = text.range(of: #"^[0-9]{1,4}[xX]?\s+"#, options: .regularExpression) {
            var token = text[match].trimmingCharacters(in: .whitespaces)
            if token.last == "x" || token.last == "X" { token.removeLast() }
            guard let value = Int(token), (1...2000).contains(value) else { return nil }
            quantity = value
            text = String(text[match.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        return DeckStudioQuickAdd(quantity: quantity, name: text, ignored: ignored)
    }
}
