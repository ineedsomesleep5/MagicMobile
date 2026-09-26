import Foundation

/// Apply type, mana, set and identity filters before limiting results. Exact
/// identity buckets are disjoint, so off-color entries cannot hide later matches.
enum DeckStudioCatalogueSearch {
    static func cards(in catalogue: NativeDeckMetadataCatalogue, query: String = "", type: String = "",
                      allowedIdentity: [String]? = nil, setCode: String = "", minimumManaValue: Double? = nil,
                      maximumManaValue: Double? = nil, limit: Int = 80) -> [NativeDeckMetadataCatalogue.Card] {
        guard limit > 0, minimumManaValue.map({ $0.isFinite && $0 >= 0 }) ?? true,
              maximumManaValue.map({ $0.isFinite && $0 >= 0 }) ?? true,
              minimumManaValue == nil || maximumManaValue == nil || minimumManaValue! <= maximumManaValue! else { return [] }
        let cap = min(limit, 2000)
        let syntax = DeckStudioSearchSyntax(query)
        if syntax.hasFilters {
            guard allowedIdentity.map({ Set($0).isSubset(of: ["W", "U", "B", "R", "G"]) }) ?? true else { return [] }
            var syntax = syntax
            if !type.isEmpty { syntax.types.append(type) }
            syntax.setCode = setCode
            syntax.minimumManaValue = [syntax.minimumManaValue, minimumManaValue].compactMap { $0 }.max()
            syntax.maximumManaValue = [syntax.maximumManaValue, maximumManaValue].compactMap { $0 }.min()
            if let allowedIdentity { syntax.identity = (syntax.identity ?? ["W", "U", "B", "R", "G"]).intersection(allowedIdentity) }
            return scan(catalogue, syntax: syntax, nameOnly: false, limit: cap)
        }
        // Without filter terms this is the plain name or rules-text search (minus any half-typed term).
        let query = syntax.text
        var filter = NativeDeckMetadataCatalogue.SearchFilter()
        filter.query = query; filter.type = type; filter.setCode = setCode
        filter.minimumManaValue = minimumManaValue; filter.maximumManaValue = maximumManaValue
        guard let allowedIdentity else { return catalogue.search(filter, limit: cap) }
        let identity = Array(Set(allowedIdentity)).sorted()
        guard identity.count <= 5, Set(identity).isSubset(of: ["W", "U", "B", "R", "G"]) else { return [] }
        var results: [NativeDeckMetadataCatalogue.Card] = []
        for mask in 0..<(1 << identity.count) {
            filter.colorIdentity = Set(identity.indices.filter { mask & (1 << $0) != 0 }.map { identity[$0] })
            results.append(contentsOf: catalogue.search(filter, limit: cap))
        }
        return Array(NativeDeckMetadataCatalogue.ranked(results, query: query).prefix(cap))
    }

    /// Quick Add autocomplete: names only, exact and prefix matches first.
    static func nameSuggestions(in catalogue: NativeDeckMetadataCatalogue, query: String, limit: Int = 5) -> [NativeDeckMetadataCatalogue.Card] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, limit > 0 else { return [] }
        return scan(catalogue, syntax: DeckStudioSearchSyntax(text: text), nameOnly: true, limit: min(limit, 2000))
    }

    /// Legendary creatures and cards whose text says they can be your commander.
    /// Partner and background pairings are left to XMage.
    static func isCommanderCandidate(_ card: NativeDeckMetadataCatalogue.Card) -> Bool {
        let legendaryCreature = card.types?.contains("CREATURE") == true
            && card.typeLine?.range(of: "Legendary", options: .caseInsensitive) != nil
        return legendaryCreature || card.oracleText?.range(of: "can be your commander", options: .caseInsensitive) != nil
    }

    /// Commander-first picker. Plain words match the name; the search syntax also applies.
    static func commanders(in catalogue: NativeDeckMetadataCatalogue, query: String, limit: Int = 80) -> [NativeDeckMetadataCatalogue.Card] {
        guard limit > 0 else { return [] }
        return scan(catalogue, syntax: DeckStudioSearchSyntax(query), nameOnly: true, limit: min(limit, 2000), where: isCommanderCandidate)
    }

    private static func scan(_ catalogue: NativeDeckMetadataCatalogue, syntax: DeckStudioSearchSyntax, nameOnly: Bool, limit: Int,
                             where extra: (NativeDeckMetadataCatalogue.Card) -> Bool = { _ in true }) -> [NativeDeckMetadataCatalogue.Card] {
        func contains(_ text: String?, _ query: String) -> Bool {
            text?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) != nil
        }
        let matches = catalogue.artworkCardNames.compactMap { catalogue.card(named: $0) }.filter { card in
            (syntax.text.isEmpty || contains(card.name, syntax.text) || (!nameOnly && contains(card.oracleText, syntax.text))) &&
            syntax.types.allSatisfy { contains(card.typeLine, $0) } &&
            syntax.oracle.allSatisfy { contains(card.oracleText, $0) } &&
            (syntax.setCode.isEmpty || card.setCodes.contains { $0.caseInsensitiveCompare(syntax.setCode) == .orderedSame }) &&
            (syntax.identity == nil || card.colorIdentity.map { Set($0).isSubset(of: syntax.identity!) } == true) &&
            (syntax.minimumManaValue == nil || card.manaValue.map { $0 >= syntax.minimumManaValue! } == true) &&
            (syntax.maximumManaValue == nil || card.manaValue.map { $0 <= syntax.maximumManaValue! } == true) &&
            extra(card)
        }
        return Array(NativeDeckMetadataCatalogue.ranked(matches, query: syntax.text).prefix(limit))
    }
}

/// Local search syntax, a small Scryfall-style subset:
/// `t:creature`, `o:draw`, `mv<=3`, `mv>=2`, `mv=3`, `id:wu` (identity within W and U;
/// `id:c` is colorless). Values may be quoted: `t:"legendary creature"`. Every term
/// must match. Anything else, including an incomplete term, stays as name or rules text.
struct DeckStudioSearchSyntax: Equatable {
    var text = ""
    var types: [String] = []
    var oracle: [String] = []
    var minimumManaValue: Double?
    var maximumManaValue: Double?
    var identity: Set<String>?
    var setCode = ""
    var hasFilters: Bool {
        !types.isEmpty || !oracle.isEmpty || minimumManaValue != nil || maximumManaValue != nil || identity != nil
    }

    init(text: String = "") { self.text = text }

    init(_ query: String) {
        var text: [String] = []
        for token in Self.tokens(query) {
            let lower = token.lowercased()
            func value(after prefix: String) -> String? {
                guard lower.hasPrefix(prefix) else { return nil }
                let rest = String(token.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))
                return rest.isEmpty ? nil : rest
            }
            // A term still being typed filters nothing yet.
            if ["t:", "o:", "id:", "mv<=", "mv>=", "mv="].contains(where: { lower.hasPrefix($0) && value(after: $0) == nil }) { continue }
            if let value = value(after: "t:") { types.append(value); continue }
            if let value = value(after: "o:") { oracle.append(value); continue }
            if let value = value(after: "id:") {
                let letters = Set(value.uppercased())
                if letters.isSubset(of: ["W", "U", "B", "R", "G", "C"]), !(letters.contains("C") && letters.count > 1) {
                    identity = (identity ?? ["W", "U", "B", "R", "G"]).intersection(letters.subtracting(["C"]).map(String.init))
                    continue
                }
            }
            if let bound = value(after: "mv<=").flatMap(Double.init), bound.isFinite, bound >= 0 {
                maximumManaValue = min(maximumManaValue ?? bound, bound); continue
            }
            if let bound = value(after: "mv>=").flatMap(Double.init), bound.isFinite, bound >= 0 {
                minimumManaValue = max(minimumManaValue ?? bound, bound); continue
            }
            if let bound = value(after: "mv=").flatMap(Double.init), bound.isFinite, bound >= 0 {
                minimumManaValue = max(minimumManaValue ?? bound, bound)
                maximumManaValue = min(maximumManaValue ?? bound, bound); continue
            }
            text.append(token)
        }
        self.text = text.joined(separator: " ")
    }

    /// Whitespace-separated tokens; double quotes keep spaces inside a token.
    private static func tokens(_ query: String) -> [String] {
        var tokens: [String] = [], current = "", quoted = false
        for character in query {
            if character == "\"" { quoted.toggle(); current.append(character) }
            else if character.isWhitespace && !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
