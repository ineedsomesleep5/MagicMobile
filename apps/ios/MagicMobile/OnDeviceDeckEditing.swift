import Foundation

struct NativeDeckRow: Identifiable, Equatable {
    var id: UUID = UUID()
    var cardName: String
    var quantity: Int
    var section: String
    /// Clear when the user explicitly changes this row's section.
    var isPrimaryCommander: Bool

    init(id: UUID = UUID(), cardName: String = "", quantity: Int = 1, section: String = "deck", isPrimaryCommander: Bool = false) {
        self.id = id; self.cardName = cardName; self.quantity = quantity; self.section = section
        self.isPrimaryCommander = isPrimaryCommander
    }
}

struct NativeDeckDraft {
    var name: String
    var rows: [NativeDeckRow]

    init(name: String = "New Commander Deck", rows: [NativeDeckRow] = []) {
        self.name = name; self.rows = rows
    }

    init(deck: DeckList) {
        name = deck.name
        rows = ((deck.commander.map { [$0] }) ?? []).map {
            NativeDeckRow(cardName: $0.cardName, quantity: $0.quantity, section: $0.section, isPrimaryCommander: true)
        } + deck.entries.map {
            NativeDeckRow(cardName: $0.cardName, quantity: $0.quantity, section: $0.section)
        }
    }

    func deck() throws -> DeckList {
        let marked = rows.indices.filter { rows[$0].isPrimaryCommander }
        guard marked.count <= 1 else { throw OnDeviceDeckEditing.Error.multiplePrimaryCommanders }
        let primaryIndex = marked.first ?? rows.firstIndex {
            ["commander", "commanders"].contains($0.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        var commander: DeckEntry?
        var entries: [DeckEntry] = []
        for (index, row) in rows.enumerated() {
            let entry = DeckEntry(cardName: row.cardName, quantity: row.quantity, section: row.section)
            if index == primaryIndex {
                commander = entry
            } else { entries.append(entry) }
        }
        let result = DeckList(name: name, commander: commander, entries: entries)
        try OnDeviceDeckEditing.validateDraft(result)
        return result
    }

    func exportJSON() throws -> Data { try OnDeviceDeckEditing(try deck()).exportJSON() }
    static func importJSON(_ data: Data) throws -> Self {
        Self(deck: try OnDeviceDeckEditing.importJSON(data).deckList)
    }
}

/// Lossless local draft editing, not rules validation. Resolve exact supported
/// names before play. Unknown sections stay intact until explicitly edited.
struct OnDeviceDeckEditing {
    static let maximumJSONBytes = 2 * 1024 * 1024
    enum Error: LocalizedError {
        case invalidName, invalidEntry, missingEntry, missingRecord, staleRevision, copyRequired, unreadableCache
        case multiplePrimaryCommanders, oversizedJSON
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Give this draft a nonempty name of at most 512 UTF-8 bytes."
            case .invalidEntry: return "Card names and sections must be nonempty and at most 2,000 UTF-8 bytes. Quantities must be 1–2,000, with at most 2,000 cards total."
            case .multiplePrimaryCommanders: return "Only one row may be marked as the primary commander. Keep partners in the commander section."
            case .oversizedJSON: return "Draft JSON must be at most 2 MiB."
            case .missingEntry: return "That card row changed. Reopen the draft."
            case .missingRecord: return "That saved deck no longer exists."
            case .staleRevision: return "The saved library changed. Reopen it before saving again."
            case .copyRequired: return "Make a local editing copy of this cloud deck first."
            case .unreadableCache: return "The saved library is unreadable. Preserve it before recovery."
            }
        }
    }

    var name: String
    var commander: DeckEntry?
    private(set) var entries: [DeckEntry]

    init(_ deck: DeckList = DeckList(name: "New Commander Deck", commander: nil, entries: [])) {
        name = deck.name; commander = deck.commander; entries = deck.entries
    }

    var deckList: DeckList { DeckList(name: name, commander: commander, entries: entries) }

    // Use "deck" for main, "commanders" for a partner, "companions" for a companion.
    // Do not merge rows by card name: one name can legitimately occur in several sections.
    mutating func add(_ entry: DeckEntry) throws {
        try Self.validate(entry); entries.append(entry)
    }

    mutating func replace(at index: Int, with entry: DeckEntry) throws {
        guard entries.indices.contains(index) else { throw Error.missingEntry }
        try Self.validate(entry); entries[index] = entry
    }

    mutating func setQuantity(_ quantity: Int, at index: Int) throws {
        guard entries.indices.contains(index) else { throw Error.missingEntry }
        let entry = entries[index]
        try replace(at: index, with: DeckEntry(cardName: entry.cardName, quantity: quantity, section: entry.section))
    }

    mutating func remove(at index: Int) throws {
        guard entries.indices.contains(index) else { throw Error.missingEntry }
        entries.remove(at: index)
    }

    static func validateDraft(_ deck: DeckList) throws {
        guard deck.name.utf8.count <= 512,
              !deck.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.invalidName }
        if let commander = deck.commander { try validate(commander) }
        var count = deck.commander?.quantity ?? 0
        for entry in deck.entries {
            try validate(entry)
            guard entry.quantity <= 2000 - count else { throw Error.invalidEntry }
            count += entry.quantity
        }
    }

    private static func validate(_ entry: DeckEntry) throws {
        guard (1...2000).contains(entry.quantity), entry.cardName.utf8.count <= 2000, entry.section.utf8.count <= 2000,
              !entry.cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entry.section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.invalidEntry }
    }

    /// JSON draft exchange preserves every section/name verbatim, unlike lossy text normalization.
    func exportJSON() throws -> Data {
        try Self.validateDraft(deckList)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(deckList)
        guard data.count <= Self.maximumJSONBytes else { throw Error.oversizedJSON }
        return data
    }

    static func importJSON(_ data: Data) throws -> Self {
        guard data.count <= maximumJSONBytes else { throw Error.oversizedJSON }
        let deck = try JSONDecoder().decode(DeckList.self, from: data)
        try validateDraft(deck)
        return Self(deck)
    }
}
