import Foundation
import MagicMobileOnDevice

/// Resolves trusted printings locally; the native XMage validator decides deck legality.
struct OnDeviceDeckResolver {
    private struct Printing: Decodable {
        let name: String
        let setCode: String
        let collectorNumber: String

        func json(count: Int) -> MagicMobileOnDevice.JSONValue {
            .object(["name": .string(name), "setCode": .string(setCode),
                     "collectorNumber": .string(collectorNumber), "count": .integer(Int64(count))])
        }
    }

    private struct Catalogue: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let catalogueHash: String
        let sourceCatalogueSHA256: String
        let sourceRegistrySHA256: String
        let cards: [Printing]
        let nameAliases: [String: String]?
        let sourceMetadataSHA256: String?
    }

    let upstreamCommit: String
    /// The native capability's registry hash, distinct from the JSONL content hash.
    let catalogueHash: String
    let sourceCatalogueSHA256: String
    let sourceRegistrySHA256: String
    private let cards: [String: Printing]
    private let nameAliases: [String: String]
    private let reverseFaces: [String: String]

    func canonicalCardName(_ name: String) -> String? {
        cards[name] != nil ? name : nameAliases[name] ?? reverseFaces[name]
    }

    func containsCard(name: String) -> Bool { canonicalCardName(name) != nil }

    func canonicalized(_ deck: DeckList) throws -> DeckList {
        func entry(_ value: DeckEntry) throws -> DeckEntry {
            guard let name = canonicalCardName(value.cardName) else {
                throw ResolutionError("No compiled printing for '\(value.cardName)'. Use the exact card name from this app's catalogue or update the app.")
            }
            return DeckEntry(cardName: name, quantity: value.quantity, section: value.section)
        }
        return try DeckList(name: deck.name, commander: deck.commander.map(entry), entries: deck.entries.map(entry))
    }

    func searchCardNames(query: String, limit: Int = 40) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }
        return Array(cards.keys.filter {
            $0.range(of: needle, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) != nil
        }.sorted().prefix(min(limit, 2000)))
    }

    static func bundled(bundle explicitBundle: Bundle? = nil) throws -> OnDeviceDeckResolver {
        #if SWIFT_PACKAGE
        let bundle = explicitBundle ?? .module
        #else
        let bundle = explicitBundle ?? .main
        #endif
        guard let url = bundle.url(forResource: "ondevice-catalogue", withExtension: "json")
                ?? bundle.url(forResource: "ondevice-catalogue", withExtension: "json", subdirectory: "Resources") else {
            throw ResolutionError("Missing ondevice-catalogue.json. Include the generated catalogue in the app's resources and rebuild.")
        }
        return try OnDeviceDeckResolver(catalogueData: Data(contentsOf: url))
    }

    init(catalogueData: Data) throws {
        let catalogue = try JSONDecoder().decode(Catalogue.self, from: catalogueData)
        guard catalogue.schemaVersion == 1, !catalogue.cards.isEmpty,
              !catalogue.upstreamCommit.isEmpty, !catalogue.catalogueHash.isEmpty,
              !catalogue.sourceCatalogueSHA256.isEmpty, !catalogue.sourceRegistrySHA256.isEmpty else {
            throw ResolutionError("The on-device catalogue is incomplete or incompatible. Update the app.")
        }
        var index: [String: Printing] = [:]
        var printings = Set<[String]>()
        for printing in catalogue.cards {
            guard !printing.name.isEmpty, !printing.setCode.isEmpty, !printing.collectorNumber.isEmpty,
                  index[printing.name] == nil,
                  printings.insert([printing.setCode, printing.collectorNumber]).inserted else {
                throw ResolutionError("The on-device catalogue contains an invalid or ambiguous printing. Regenerate the bundled catalogue.")
            }
            index[printing.name] = printing
        }
        let aliases = catalogue.nameAliases ?? [:]
        if !aliases.isEmpty {
            guard catalogue.sourceMetadataSHA256?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw ResolutionError("The local name aliases have no pinned metadata identity.")
            }
        }
        for (alias, canonical) in aliases {
            guard index[canonical] != nil, alias.hasPrefix(canonical + " // "), alias.count > canonical.count + 4 else {
                throw ResolutionError("The local catalogue has an invalid name alias. Regenerate it from pinned metadata.")
            }
        }
        upstreamCommit = catalogue.upstreamCommit
        catalogueHash = catalogue.catalogueHash
        sourceCatalogueSHA256 = catalogue.sourceCatalogueSHA256
        sourceRegistrySHA256 = catalogue.sourceRegistrySHA256
        cards = index
        nameAliases = aliases.filter { index[$0.key] == nil }
        reverseFaces = NativeDeckCanonicalNames.reverseFaces(nameAliases, exactNames: Set(index.keys))
    }

    func resolve(_ deck: DeckList) throws -> MagicMobileOnDevice.JSONValue {
        let deck = try canonicalized(deck)
        var total = 0
        func row(_ entry: DeckEntry) throws -> MagicMobileOnDevice.JSONValue {
            guard (1...2000).contains(entry.quantity), entry.quantity <= 2000 - total else {
                throw ResolutionError("Invalid count for '\(entry.cardName)'. Each count must be 1–2,000 and the entire deck must contain at most 2,000 cards.")
            }
            total += entry.quantity
            guard let printing = cards[entry.cardName] else {
                throw ResolutionError("No compiled printing for '\(entry.cardName)'. Use the exact card name from this app's catalogue or update the app.")
            }
            return printing.json(count: entry.quantity)
        }
        var sections: [String: [MagicMobileOnDevice.JSONValue]] = ["main": [], "commanders": [], "companions": []]
        var assignedSections: [String: String] = [:]
        func append(_ entry: DeckEntry, section: String) throws {
            if let previous = assignedSections[entry.cardName], previous != section {
                throw ResolutionError("'\(entry.cardName)' appears in both \(previous) and \(section). Keep it in one section and confirm its count; no copies were removed automatically.")
            }
            assignedSections[entry.cardName] = section
            sections[section]!.append(try row(entry))
        }
        if let commander = deck.commander { try append(commander, section: "commanders") }
        for entry in deck.entries {
            let section = try Self.section(entry.section)
            try append(entry, section: section)
        }
        var config = sections.mapValues { MagicMobileOnDevice.JSONValue.array($0) }
        config["name"] = .string(deck.name)
        return .object(config)
    }

    private static func section(_ name: String) throws -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "deck", "main": return "main"
        case "commander", "commanders": return "commanders"
        case "companion", "companions": return "companions"
        default: throw ResolutionError("Unsupported deck section '\(name)'. Native play supports Deck, Commander, or Companion, not a general sideboard. No cards were dropped.")
        }
    }

    /// Local plain text only: `1 Card Name` / `1x Card Name`, with explicit section headings.
    /// The first Commander entry uses DeckList.commander; additional partners stay in entries.
    func importDeck(text: String, name: String) throws -> DeckList {
        guard text.utf8.count <= 2 * 1024 * 1024, name.utf8.count <= 512 else {
            throw ResolutionError("Deck text or name is too large (2 MiB text, 512-byte name maximum).")
        }
        var section = "main"
        var commander: DeckEntry?
        var entries: [DeckEntry] = []
        var total = 0
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if index == 0 { line = line.replacingOccurrences(of: "\u{FEFF}", with: "") }
            if line.isEmpty { continue }
            // Exported headings can be plain, // Commander, or # Commander.
            var heading = line
            if heading.hasPrefix("//") { heading = String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            else if heading.hasPrefix("#") { heading = String(heading.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if heading.hasSuffix(":") { heading.removeLast() }
            if let nextSection = try? Self.section(heading) {
                section = nextSection
                continue
            }
            if ["sideboard", "maybeboard", "considering", "side", "sb"].contains(heading.lowercased()) || line.lowercased().hasPrefix("sb:") {
                throw ResolutionError("Unsupported sideboard or considering section on line \(index + 1). No cards were dropped; provide only the intended main deck, commanders, and companion.")
            }
            if line.hasPrefix("#") || line.hasPrefix("//") {
                throw ResolutionError("Unrecognized export heading/comment on line \(index + 1): '\(line)'. Remove it or use an explicit Deck, Commander, or Companion heading.")
            }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let countText = parts.first.map(String.init) ?? ""
            let digits = countText.lowercased().hasSuffix("x") ? String(countText.dropLast()) : countText
            guard parts.count == 2, let count = Int(digits), (1...2000).contains(count), count <= 2000 - total else {
                throw ResolutionError("Cannot import line \(index + 1): '\(line)'. Use '1 Exact Card Name' under Deck, Commander, or Companion.")
            }
            total += count
            var cardName = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Exact names win. Only recognized export printing/foil suffixes may be removed;
            // the remaining name must still exactly match the compiled catalogue.
            if canonicalCardName(cardName) == nil {
                cardName = cardName.replacingOccurrences(of: #"\s+\*F\*$"#, with: "", options: .regularExpression)
                cardName = cardName.replacingOccurrences(of: #"\s+\([A-Za-z0-9]+\)\s+[A-Za-z0-9★†-]+$"#, with: "", options: .regularExpression)
            }
            let entry = DeckEntry(cardName: canonicalCardName(cardName) ?? cardName, quantity: count, section: section)
            if section == "commanders", commander == nil { commander = entry }
            else { entries.append(entry) }
        }
        guard commander != nil || !entries.isEmpty else {
            throw ResolutionError("The imported list has no cards. Add lines such as '1 Exact Card Name'.")
        }
        let deck = DeckList(name: name, commander: commander, entries: entries)
        _ = try resolve(deck)
        return deck
    }

    struct ResolutionError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
