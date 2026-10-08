import Foundation

/// Interchange for the standard boards supported by plain-text deck importers.
/// JSON remains the lossless choice for custom sections or decorated names.
enum DeckStudioTextExport {
    enum ExportError: LocalizedError {
        case requiresJSON
        var errorDescription: String? { "Use JSON export for empty drafts, custom sections or unusual card names." }
    }
    /// One line per row, "2 Sol Ring" or, with chosen art, "2 Sol Ring (CMM) 400" as Moxfield and
    /// Archidekt write it, so the printing survives a round trip through this importer or theirs.
    static func line(_ entry: DeckEntry) -> String {
        "\(entry.quantity) \(entry.cardName)" + (entry.printing.map { " " + $0.exportSuffix } ?? "")
    }
    static func text(_ deck: DeckList) throws -> String {
        let entries = (deck.commander.map { [DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "commanders", printing: $0.printing)] } ?? []) + deck.entries
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
            return section + "\n" + rows.map(line).joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
        // Verify the actual importer preserves every name/quantity/board and chosen printing before sharing.
        let decoded = try OnDeviceDeckEditing.importText(text, name: deck.name).deck
        func counts(_ values: [DeckEntry]) -> [String: Int] {
            var result: [String: Int] = [:]
            for value in values { result["\(value.section)\u{0}\(value.cardName)\u{0}\(value.printing?.key ?? "")", default: 0] += value.quantity }
            return result
        }
        let expected = groups.flatMap { key, values in values.map { DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: key == "Commander" ? "commanders" : key == "Companion" ? "companions" : key.lowercased(), printing: $0.printing) } }
        let actual = (decoded.commander.map { [DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "commanders", printing: $0.printing)] } ?? []) + decoded.entries
        guard counts(expected) == counts(actual) else { throw ExportError.requiresJSON }
        return text
    }
}

/// "Edit as text": the whole deck in the export format, reviewed as cards added
/// and removed per board before it is applied as one undo step.
struct DeckStudioTextDiff: Equatable {
    struct Change: Equatable, Identifiable {
        let board: String
        let name: String
        let before: Int
        let after: Int
        var delta: Int { after - before }
        var id: String { board + "\u{0}" + name }
        /// e.g. "+2 Sol Ring · Deck", "−1 Island · Maybeboard".
        var label: String { "\(delta > 0 ? "+" : "−")\(abs(delta)) \(name) · \(DeckStudioTextDiff.title(board))" }
    }
    /// A card whose chosen printing changed, written "(SET) number" in the text.
    struct ArtChange: Equatable, Identifiable {
        let board: String
        let name: String
        let before: [String]
        let after: [String]
        var id: String { board + "\u{0}" + name }
        /// e.g. "Sol Ring · default art → CMM 400".
        var label: String { "\(name) · \(before.joined(separator: ", ")) → \(after.joined(separator: ", "))" }
    }
    let added: [Change]
    let removed: [Change]
    let art: [ArtChange]
    var isEmpty: Bool { added.isEmpty && removed.isEmpty && art.isEmpty }

    static func title(_ board: String) -> String {
        ["commanders": "Commander", "deck": "Deck", "companions": "Companion", "sideboard": "Sideboard", "maybeboard": "Maybeboard"][board]
            ?? board.capitalized
    }

    init(from old: NativeDeckDraft, to new: NativeDeckDraft) {
        func totals(_ draft: NativeDeckDraft) -> [String: (board: String, name: String, count: Int)] {
            var result: [String: (board: String, name: String, count: Int)] = [:]
            for row in draft.rows {
                let board = DeckStudioBoard.of(row)
                let key = board + "\u{0}" + row.cardName
                result[key] = (board, row.cardName, (result[key]?.count ?? 0) + row.quantity)
            }
            return result
        }
        let before = totals(old), after = totals(new)
        let order = ["commanders", "deck", "companions", "sideboard", "maybeboard"]
        let changes = Set(before.keys).union(after.keys).compactMap { key -> Change? in
            let value = before[key] ?? after[key]!
            let change = Change(board: value.board, name: value.name, before: before[key]?.count ?? 0, after: after[key]?.count ?? 0)
            return change.delta == 0 ? nil : change
        }.sorted { a, b in
            let left = order.firstIndex(of: a.board) ?? order.count, right = order.firstIndex(of: b.board) ?? order.count
            return left == right ? (a.board == b.board ? a.name < b.name : a.board < b.board) : left < right
        }
        added = changes.filter { $0.delta > 0 }
        removed = changes.filter { $0.delta < 0 }
        // The chosen printings per card and board, one entry per row: default art reads "default art".
        func artwork(_ draft: NativeDeckDraft) -> [String: (board: String, name: String, labels: [String])] {
            var result: [String: (board: String, name: String, labels: [String])] = [:]
            for row in draft.rows {
                let board = DeckStudioBoard.of(row)
                let key = board + "\u{0}" + row.cardName
                var value = result[key] ?? (board, row.cardName, [])
                value.labels.append(row.printing?.label ?? "default art")
                result[key] = value
            }
            return result.mapValues { ($0.board, $0.name, $0.labels.sorted()) }
        }
        let beforeArt = artwork(old), afterArt = artwork(new)
        art = Set(beforeArt.keys).intersection(afterArt.keys).compactMap { key -> ArtChange? in
            guard let was = beforeArt[key], let now = afterArt[key], was.labels != now.labels else { return nil }
            return ArtChange(board: was.board, name: was.name, before: was.labels, after: now.labels)
        }.sorted { ($0.board, $0.name) < ($1.board, $1.name) }
    }

    /// Parses edited text with the plain-text importer and returns the new draft.
    /// Rows that stay on the same board keep their identity and section spelling,
    /// and the current primary commander stays primary while it remains a commander.
    static func draft(from text: String, replacing draft: NativeDeckDraft) throws -> (draft: NativeDeckDraft, notes: [String]) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Draft" : draft.name
        let imported: DeckList
        var notes: [String] = []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imported = DeckList(name: name, commander: nil, entries: [])
        } else {
            let result = try OnDeviceDeckEditing.importText(text, name: name)
            imported = result.deck
            notes = result.annotations.map { "Line \($0.line): \($0.text)" }
        }
        var unused = draft.rows
        var rows: [NativeDeckRow] = NativeDeckDraft(deck: imported).rows.map { fresh in
            var row = fresh
            let board = DeckStudioBoard.of(fresh)
            if let index = unused.firstIndex(where: { DeckStudioBoard.of($0) == board && $0.cardName == fresh.cardName }) {
                let old = unused.remove(at: index)
                row.id = old.id
                if DeckStudioBoard.normalized(old.section) == board { row.section = old.section }
            }
            return row
        }
        let previousPrimary = draft.rows.first(where: \.isPrimaryCommander)?.cardName
        if let previousPrimary, let keep = rows.firstIndex(where: { DeckStudioBoard.of($0) == "commanders" && $0.cardName == previousPrimary }) {
            // Every row on the commander board has a commander section, so moving the flag keeps both commanders.
            for index in rows.indices { rows[index].isPrimaryCommander = index == keep }
        }
        var result = draft
        result.rows = rows
        return (result, notes)
    }
}
