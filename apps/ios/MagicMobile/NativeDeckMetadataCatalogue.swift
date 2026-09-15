import Foundation

/// Selected-printing metadata, not live Oracle updates, Commander legality or mana production.
struct NativeDeckMetadataCatalogue {
    struct Card: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let typeLine: String?
        let types: [String]?
        let oracleText: String?
        let manaValue: Double?
        let manaCost: String?
        let colors: [String]?
        /// nil means unavailable; [] would mean explicitly known colorless identity.
        let colorIdentity: [String]?
        /// Sets present in the pinned registry, not a promise that each printing is selectable.
        let setCodes: [String]
    }

    struct SearchFilter {
        var query = "" // case-insensitive name or rules substring
        var type = ""
        var setCode = ""
        var colors: Set<String>? = nil // exact color set; [] selects known colorless cards
        var colorIdentity: Set<String>? = nil // unavailable metadata does not match
        var minimumManaValue: Double? = nil
        var maximumManaValue: Double? = nil
    }

    struct Statistics {
        var cardCount = 0
        var excludedCardCount = 0
        var landCount = 0
        var unknownTypeCount = 0
        var unknownManaValueCount = 0
        var unknownManaCostCount = 0
        var unknownNames: [String] = []
        /// Quantity-weighted nonland printed mana values; unknown types/values are excluded.
        var manaCurve: [Double: Int] = [:]
        /// Printed symbols, hybrids counted once as their own symbol; no color-source estimates.
        var manaSymbolCounts: [String: Int] = [:]
        var averageManaValue: Double? {
            let count = manaCurve.values.reduce(0, +)
            return count == 0 ? nil : manaCurve.reduce(0) { $0 + $1.key * Double($1.value) } / Double(count)
        }
    }

    private struct Metadata: Decodable {
        let typeLine: String?
        let types: [String]?
        let oracleText: String?
        let manaValue: Double?
        let manaCost: String?
        let colors: [String]?
        let colorIdentity: [String]?
        let setCodes: [String]
    }
    private struct Payload: Decodable {
        struct Printing: Decodable { let name: String }
        let schemaVersion: Int
        let sourceMetadataSHA256: String?
        let cards: [Printing]
        let nameAliases: [String: String]?
        let cardMetadata: [String: Metadata]?
    }
    private let cards: [Card]
    private let index: [String: Card]
    private let aliases: [String: String]

    static func bundled(bundle explicitBundle: Bundle? = nil) throws -> Self {
        #if SWIFT_PACKAGE
        let bundle = explicitBundle ?? .module
        #else
        let bundle = explicitBundle ?? .main
        #endif
        guard let url = bundle.url(forResource: "ondevice-catalogue", withExtension: "json")
            ?? bundle.url(forResource: "ondevice-catalogue", withExtension: "json", subdirectory: "Resources") else {
            throw CatalogueError("Missing bundled card metadata.")
        }
        return try Self(catalogueData: Data(contentsOf: url))
    }

    init(catalogueData: Data) throws {
        guard catalogueData.count <= 64 * 1024 * 1024 else { throw CatalogueError("Metadata catalogue is too large.") }
        let payload = try JSONDecoder().decode(Payload.self, from: catalogueData)
        let names = Set(payload.cards.map(\.name))
        func validName(_ name: String) -> Bool {
            !name.isEmpty && name.utf8.count <= 1024 && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
                && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
        guard payload.schemaVersion == 1, !payload.cards.isEmpty, payload.cards.count <= 100_000,
              payload.cards.allSatisfy({ validName($0.name) }),
              Set(payload.cards.map(\.name)).count == payload.cards.count else {
            throw CatalogueError("Invalid local metadata catalogue.")
        }
        let suppliedAliases = payload.nameAliases ?? [:]
        guard suppliedAliases.count <= 100_000, Set((payload.cardMetadata ?? [:]).keys).isSubset(of: names) else {
            throw CatalogueError("Metadata contains unknown card identities.")
        }
        if payload.cardMetadata != nil || !suppliedAliases.isEmpty {
            guard payload.sourceMetadataSHA256?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw CatalogueError("Metadata has no pinned source identity.")
            }
        }
        for (alias, target) in suppliedAliases {
            guard validName(alias), names.contains(target), alias.hasPrefix(target + " // "),
                  validName(String(alias.dropFirst(target.count + 4))) else {
                throw CatalogueError("Invalid local metadata alias; exact canonical targets are required.")
            }
        }
        let knownTypes: Set<String> = ["ARTIFACT", "BATTLE", "CONSPIRACY", "CREATURE", "DUNGEON", "ENCHANTMENT", "INSTANT", "LAND", "PHENOMENON", "PLANE", "PLANESWALKER", "SCHEME", "SORCERY", "KINDRED", "VANGUARD"]
        func validateColors(_ colors: [String]?) throws {
            guard let colors else { return }
            guard colors.count <= 5, Set(colors).count == colors.count, Set(colors).isSubset(of: ["W", "U", "B", "R", "G"]) else {
                throw CatalogueError("Invalid metadata colors; expected unique WUBRG symbols.")
            }
        }
        var result: [Card] = []
        for printing in payload.cards {
            let value = payload.cardMetadata?[printing.name]
            try validateColors(value?.colors)
            try validateColors(value?.colorIdentity)
            var types = value?.types
            if let supplied = types {
                guard !supplied.isEmpty, supplied.count <= 32, Set(supplied).count == supplied.count,
                      supplied.allSatisfy({ $0.range(of: "^[A-Z][A-Z_]{0,63}$", options: .regularExpression) != nil }) else {
                    throw CatalogueError("Invalid metadata card types.")
                }
                // Unknown future types must not silently become nonlands in statistics/search.
                if !Set(supplied).isSubset(of: knownTypes) { types = nil }
            }
            if let line = value?.typeLine, !validName(line) { throw CatalogueError("Invalid metadata type line.") }
            if let manaValue = value?.manaValue, !manaValue.isFinite || manaValue < 0 {
                throw CatalogueError("Invalid printed mana value.")
            }
            result.append(Card(name: printing.name, typeLine: types == nil ? nil : value?.typeLine,
                               types: types, oracleText: value?.oracleText.map { EngineDisplayText.text($0) },
                               manaValue: value?.manaValue, manaCost: value?.manaCost,
                               colors: value?.colors, colorIdentity: value?.colorIdentity,
                               setCodes: value?.setCodes ?? []))
        }
        cards = result.sorted { $0.name < $1.name }
        index = Dictionary(uniqueKeysWithValues: cards.map { ($0.name, $0) })
        aliases = suppliedAliases.filter { !names.contains($0.key) }
    }

    func card(named name: String) -> Card? {
        index[name] ?? aliases[name].flatMap { index[$0] }
    }

    func search(_ filter: SearchFilter = SearchFilter(), limit: Int = 40) -> [Card] {
        guard limit > 0 else { return [] }
        func contains(_ text: String?, _ query: String) -> Bool {
            text?.range(of: query, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) != nil
        }
        return Array(cards.lazy.filter { card in
            (filter.query.isEmpty || contains(card.name, filter.query) || contains(card.oracleText, filter.query)) &&
            (filter.type.isEmpty || contains(card.typeLine, filter.type)) &&
            (filter.setCode.isEmpty || card.setCodes.contains { $0.caseInsensitiveCompare(filter.setCode) == .orderedSame }) &&
            (filter.colors == nil || card.colors.map(Set.init) == filter.colors) &&
            (filter.colorIdentity == nil || card.colorIdentity.map(Set.init) == filter.colorIdentity) &&
            (filter.minimumManaValue == nil || card.manaValue.map { $0 >= filter.minimumManaValue! } == true) &&
            (filter.maximumManaValue == nil || card.manaValue.map { $0 <= filter.maximumManaValue! } == true)
        }.prefix(min(limit, 2000)))
    }

    func statistics(for deck: DeckList, sections: Set<String> = ["main", "deck"]) throws -> Statistics {
        var stats = Statistics()
        var total = 0
        var unknown = Set<String>()
        let selected = Set(sections.map { $0.lowercased() })
        let rows = (deck.commander.map { [DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "commanders")] } ?? []) + deck.entries
        for row in rows {
            guard (1...2000).contains(row.quantity), row.quantity <= 2000 - total else { throw CatalogueError("Statistics require at most 2,000 cards with positive quantities.") }
            total += row.quantity
            guard selected.contains(row.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                stats.excludedCardCount += row.quantity
                continue
            }
            stats.cardCount += row.quantity
            guard let card = card(named: row.cardName) else {
                unknown.insert(row.cardName)
                stats.unknownTypeCount += row.quantity
                stats.unknownManaValueCount += row.quantity
                stats.unknownManaCostCount += row.quantity
                continue
            }
            if let types = card.types {
                if types.contains("LAND") { stats.landCount += row.quantity }
                else if let value = card.manaValue { stats.manaCurve[value, default: 0] += row.quantity }
                else { stats.unknownManaValueCount += row.quantity }
            } else {
                stats.unknownTypeCount += row.quantity
                if card.manaValue == nil { stats.unknownManaValueCount += row.quantity }
            }
            if let cost = card.manaCost {
                for fragment in cost.components(separatedBy: "{").dropFirst() {
                    guard let end = fragment.firstIndex(of: "}") else { continue }
                    let symbol = String(fragment[..<end])
                    if symbol != "*", !symbol.isEmpty { stats.manaSymbolCounts[symbol, default: 0] += row.quantity }
                }
            } else { stats.unknownManaCostCount += row.quantity }
        }
        stats.unknownNames = unknown.sorted()
        return stats
    }

    struct CatalogueError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
