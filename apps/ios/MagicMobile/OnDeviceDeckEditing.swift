import Foundation

struct NativeDeckRow: Identifiable, Equatable, Codable {
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

struct NativeDeckDraft: Equatable, Codable {
    var name: String
    var rows: [NativeDeckRow]

    static let basicLandNames = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]

    private func isMainBasicLand(_ row: NativeDeckRow, name: String) -> Bool {
        row.cardName == name && !row.isPrimaryCommander &&
            ["deck", "main"].contains(row.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    func basicLandCount(_ name: String) -> Int {
        rows.filter { isMainBasicLand($0, name: name) }.reduce(0) { $0 + $1.quantity }
    }

    /// A deliberate main-deck edit, never an automatic mana-base recommendation.
    /// Preserve sideboards, commander roles and the original draft on failure.
    mutating func setBasicLandCount(_ name: String, quantity: Int) throws {
        guard Self.basicLandNames.contains(name), (0...2000).contains(quantity) else {
            throw OnDeviceDeckEditing.Error.invalidEntry
        }
        var updated = self
        let existing = rows.first { isMainBasicLand($0, name: name) }
        updated.rows.removeAll { isMainBasicLand($0, name: name) }
        if quantity > 0 {
            var row = existing ?? NativeDeckRow(cardName: name)
            row.quantity = quantity
            updated.rows.append(row)
        }
        // Check entries/count without making an unfinished name prevent editing.
        var validation = updated
        validation.name = "Draft"
        _ = try validation.deck()
        self = updated
    }

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

/// Recovery is separate from saved/playable decks and retains incomplete names and row IDs.
enum NativeDeckDraftRecovery {
    static func load(key: String, defaults: UserDefaults = .standard) throws -> NativeDeckDraft? {
        guard let data = defaults.data(forKey: "deckStudio.draft." + key) else { return nil }
        guard data.count <= OnDeviceDeckEditing.maximumJSONBytes else { throw OnDeviceDeckEditing.Error.oversizedJSON }
        let draft = try JSONDecoder().decode(NativeDeckDraft.self, from: data)
        var validation = draft
        validation.name = "Recovery"
        _ = try validation.deck()
        return draft
    }

    static func save(_ draft: NativeDeckDraft, key: String, defaults: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(draft)
        guard data.count <= OnDeviceDeckEditing.maximumJSONBytes else { throw OnDeviceDeckEditing.Error.oversizedJSON }
        defaults.set(data, forKey: "deckStudio.draft." + key)
    }

    static func clear(key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "deckStudio.draft." + key)
    }

    /// Remove every revision, including unreadable recovery payloads, only after
    /// the library deletion succeeds. Keep the new-deck slot and other records.
    static func clear(recordID: String, defaults: UserDefaults = .standard) {
        let prefix = "deckStudio.draft.\(recordID)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard Int(key.dropFirst(prefix.count)) != nil else { continue }
            defaults.removeObject(forKey: key)
        }
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

    struct TextImport {
        let deck: DeckList
        /// Source annotations are retained for review, never silently discarded.
        let annotations: [TextAnnotation]
    }

    struct TextAnnotation: Equatable {
        let line: Int
        let text: String
    }

    struct TextImportError: LocalizedError {
        let line: Int
        let reason: String
        var errorDescription: String? { "Line \(line): \(reason) No cards were imported." }
    }

    /// Explicit text-export grammar only, not CSV/JSON or arbitrary provider text.
    /// Unknown card names and custom sections survive as draft data, not play validation.
    /// Caller must present annotations and resolve names before enabling native play.
    static func importText(_ text: String, name: String) throws -> TextImport {
        guard text.utf8.count <= maximumJSONBytes else {
            throw TextImportError(line: 1, reason: "Deck text exceeds 2 MiB.")
        }
        try validateDraft(DeckList(name: name, commander: nil, entries: []))
        var rows: [NativeDeckRow] = []
        var annotations: [TextAnnotation] = []
        var section = "deck"
        var total = 0
        func sectionName(_ heading: String) -> String? {
            switch heading.lowercased() {
            case "deck", "main", "mainboard": return "deck"
            case "commander", "commanders": return "commanders"
            case "companion", "companions": return "companions"
            case "sideboard": return "sideboard"
            case "maybeboard", "considering": return "maybeboard"
            default: return nil
            }
        }
        // Normalize CRLF once so line numbers match the user's editor.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for (offset, raw) in lines.enumerated() {
            let number = offset + 1
            func invalid(_ reason: String) -> TextImportError { TextImportError(line: number, reason: reason) }
            var line = raw.trimmingCharacters(in: .whitespaces)
            if offset == 0, line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var heading = line
            let explicitHeading = heading.hasPrefix("//") || heading.hasPrefix("#") || heading.hasSuffix(":")
            if heading.hasPrefix("//") { heading = String(heading.dropFirst(2)) }
            else if heading.hasPrefix("#") { heading = String(heading.dropFirst()) }
            heading = heading.trimmingCharacters(in: .whitespaces)
            if heading.hasSuffix(":") { heading.removeLast() }
            heading = heading.trimmingCharacters(in: .whitespaces)
            if let known = sectionName(heading) { section = known; continue }
            if explicitHeading, line.first?.isNumber != true {
                guard !heading.isEmpty, heading.utf8.count <= 2000 else { throw invalid("Invalid section heading.") }
                annotations.append(TextAnnotation(line: number, text: "Grouping retained in \(section): \(heading)"))
                continue
            }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let token = parts.first.map(String.init) ?? ""
            let digits = token.lowercased().hasSuffix("x") ? String(token.dropLast()) : token
            guard parts.count == 2, !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let count = Int(digits), (1...2000).contains(count), count <= 2000 - total else {
                throw invalid("Use '1 Card Name' or '1x Card Name', with at most 2,000 cards total. Mark custom headings with // or a trailing colon.")
            }
            var cardName = String(parts[1]).trimmingCharacters(in: .whitespaces)
            var rowSection = section
            func takeSuffix(_ pattern: String) -> String? {
                guard let range = cardName.range(of: pattern, options: .regularExpression) else { return nil }
                let suffix = String(cardName[range]).trimmingCharacters(in: .whitespaces)
                cardName.removeSubrange(range)
                return suffix
            }
            // Moxfield bulk tags have their own delimiter; punctuation inside names is untouched.
            if let tags = takeSuffix(#"\s+#!.+$"#) {
                annotations.append(TextAnnotation(line: number, text: tags))
            }
            if let label = takeSuffix(#"\s+\^[^^\r\n]+,#[0-9A-Fa-f]{6}\^$"#) {
                annotations.append(TextAnnotation(line: number, text: label))
            }
            if let category = takeSuffix(#"\s+\[[^\[\]\r\n]+\]$"#) {
                var value = String(category.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if value.hasSuffix("{top}") {
                    value = String(value.dropLast(5)).trimmingCharacters(in: .whitespaces)
                    guard sectionName(value) == "commanders" else {
                        throw invalid("Only [Commander{top}] is supported as a premier category.")
                    }
                }
                guard !value.isEmpty else { throw invalid("Empty bracket category.") }
                guard !value.contains("{"), !value.contains("}") else {
                    throw invalid("Unsupported category flags; specify the intended deck section explicitly.")
                }
                let mapped = sectionName(value)
                // A category under an explicit non-main section must not silently move it.
                if section != "deck", let mapped, mapped != section {
                    throw invalid("Bracket category conflicts with the current section.")
                }
                if let mapped { rowSection = mapped }
                annotations.append(TextAnnotation(line: number, text: "Category retained: \(category)"))
            }
            if let foil = takeSuffix(#"\s+\*(?:F|E)\*$"#) {
                annotations.append(TextAnnotation(line: number, text: foil))
            }
            if let printing = takeSuffix(#"\s+\([A-Za-z0-9]+\)(?:\s+[A-Za-z0-9★†-]+)?$"#) {
                annotations.append(TextAnnotation(line: number, text: printing))
            }
            // Fail explicitly on malformed/unrecognized export decorations rather than
            // importing an altered name or dropping additional category information.
            guard !cardName.contains("["), !cardName.contains("]"), !cardName.contains("^"),
                  !cardName.contains("#!"), cardName.range(of: #"\s+\*[^*]*\*$"#, options: .regularExpression) == nil else {
                throw invalid("Unsupported or malformed export suffix; use one bracket category and the documented printing/foil/label syntax.")
            }
            cardName = cardName.trimmingCharacters(in: .whitespaces)
            let entry = DeckEntry(cardName: cardName, quantity: count, section: rowSection)
            do { try validate(entry) } catch { throw invalid("Card name or section is empty or too long.") }
            rows.append(NativeDeckRow(cardName: cardName, quantity: count, section: rowSection))
            total += count
        }
        guard !rows.isEmpty else { throw TextImportError(line: 1, reason: "The list has no card rows.") }
        return TextImport(deck: try NativeDeckDraft(name: name, rows: rows).deck(), annotations: annotations)
    }

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
