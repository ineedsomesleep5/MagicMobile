import Foundation

/// The documented public Spellbook API uses names/quantities, not XMage class names.
/// No saved deck title, local IDs, notes, sideboard, or maybeboard is transmitted.
struct SpellbookDeck: Codable, Equatable, Sendable {
    struct Card: Codable, Equatable, Sendable {
        let card: String
        let quantity: Int
    }
    let main: [Card]
    let commanders: [Card]

    init(main: [Card], commanders: [Card]) throws {
        func normalize(_ cards: [Card], limit: Int) throws -> [Card] {
            guard cards.count <= limit else { throw SpellbookError.invalidDeck }
            var quantities: [String: Int] = [:]
            var names: [String: String] = [:]
            for row in cards {
                let name = row.card.trimmingCharacters(in: .whitespacesAndNewlines)
                // Spellbook also accepts numeric strings as its own card IDs. Never
                // allow an unresolved numeric name to accidentally become such an ID.
                guard !name.isEmpty, name.utf8.count <= 256,
                      !name.allSatisfy(\.isNumber),
                      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                      (1...2000).contains(row.quantity) else { throw SpellbookError.invalidDeck }
                let key = Self.key(name)
                guard quantities[key, default: 0] <= 2000 - row.quantity else { throw SpellbookError.invalidDeck }
                quantities[key, default: 0] += row.quantity
                // Stable when equivalent input rows arrive in a different order.
                names[key] = min(names[key] ?? name, name)
            }
            return quantities.keys.sorted().map { Card(card: names[$0]!, quantity: quantities[$0]!) }
        }
        self.main = try normalize(main, limit: 600)
        self.commanders = try normalize(commanders, limit: 12)
        guard !self.commanders.isEmpty,
              self.main.reduce(0, { $0 + $1.quantity }) + self.commanders.reduce(0, { $0 + $1.quantity }) <= 2000
        else { throw SpellbookError.invalidDeck }
    }
    static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    func quantities(commandZoneOnly: Bool = false) -> [String: Int] {
        (commandZoneOnly ? commanders : main + commanders).reduce(into: [:]) { result, row in
            result[Self.key(row.card), default: 0] += row.quantity
        }
    }
}

enum SpellbookError: Error, LocalizedError, Equatable {
    case invalidDeck, invalidResponse, responseTooLarge, unsafePagination, unavailable
    case rateLimited(seconds: Int), httpStatus(Int), tooManyResults
    var errorDescription: String? {
        switch self {
        case .invalidDeck: return "Combo lookup requires resolved card names, commander(s), and a bounded decklist. Your draft is unchanged."
        case .invalidResponse: return "Commander Spellbook returned an unsupported response. Your draft and previous results are unchanged."
        case .responseTooLarge: return "The combo response exceeded the safe size limit. Use the Spellbook website for this search."
        case .unsafePagination: return "The next combo page could not be verified. No deck data was sent to that address."
        case .unavailable: return "Commander Spellbook is unavailable or offline. Keep building, use saved results, or retry later."
        case .rateLimited(let seconds): return "Please wait \(seconds) seconds before another combo request. Your draft is unchanged."
        case .httpStatus(let status): return "Commander Spellbook returned HTTP \(status). No cards were added; retry later."
        case .tooManyResults: return "This lookup reached the local result limit. Open Commander Spellbook for more results."
        }
    }
}

enum SpellbookGroup: String, Codable, CaseIterable, Sendable {
    case included, includedByChangingCommanders, almostIncluded, almostIncludedByAddingColors
    case almostIncludedByChangingCommanders, almostIncludedByAddingColorsAndChangingCommanders
    var title: String {
        switch self {
        case .included: return "Pieces found by Spellbook"
        case .almostIncluded: return "Nearby combos"
        case .includedByChangingCommanders: return "Needs a commander change"
        case .almostIncludedByAddingColors: return "Needs additional colors"
        case .almostIncludedByChangingCommanders: return "Nearby, with a different commander"
        case .almostIncludedByAddingColorsAndChangingCommanders: return "Needs colors and commander changes"
        }
    }
    var isOther: Bool { self != .included && self != .almostIncluded }
}

struct SpellbookVariant: Codable, Equatable, Identifiable, Sendable {
    struct Card: Codable, Equatable, Sendable {
        let id: Int
        let name: String
        let oracleId: String?
    }
    struct Ingredient: Codable, Equatable, Sendable {
        let card: Card
        let quantity: Int
        let mustBeCommander: Bool
        let zoneLocations: [String]
        let battlefieldCardState: String
        let exileCardState: String
        let libraryCardState: String
        let graveyardCardState: String
    }
    struct Template: Codable, Equatable, Sendable {
        struct Value: Codable, Equatable, Sendable { let id: Int; let name: String }
        let template: Value
        let quantity: Int
        let mustBeCommander: Bool
        let zoneLocations: [String]
        let battlefieldCardState: String
        let exileCardState: String
        let libraryCardState: String
        let graveyardCardState: String
    }
    struct Result: Codable, Equatable, Sendable {
        struct Feature: Codable, Equatable, Sendable { let name: String }
        let feature: Feature
        let quantity: Int
    }
    struct Legalities: Codable, Equatable, Sendable { let commander: Bool? }
    let id: String
    let uses: [Ingredient]
    let requires: [Template]
    let produces: [Result]
    let identity: String
    let status: String
    let spoiler: Bool
    let legalities: Legalities
    let description: String
    let easyPrerequisites: String
    let notablePrerequisites: String
    let manaNeeded: String
    let notes: String

    var websiteURL: URL? {
        guard Self.safeID(id) else { return nil }
        return URL(string: "https://commanderspellbook.com/combo/\(id)/")
    }
    static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 &&
        value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
    func validate() throws {
        func text(_ value: String, max: Int = 32768) -> Bool { value.utf8.count <= max && !value.contains("\0") }
        guard Self.safeID(id), uses.count <= 100, requires.count <= 100, produces.count <= 100,
              !uses.isEmpty || !requires.isEmpty,
              Set(identity).isSubset(of: Set("WUBRGC")), identity.count <= 6,
              text(description), text(easyPrerequisites), text(notablePrerequisites), text(manaNeeded), text(notes),
              text(status, max: 32),
              uses.allSatisfy({ $0.card.id > 0 && !$0.card.name.isEmpty && text($0.card.name, max: 1024) &&
                  (1...2000).contains($0.quantity) && $0.zoneLocations.count <= 20 &&
                  $0.zoneLocations.allSatisfy { text($0, max: 16) } &&
                  text($0.battlefieldCardState) && text($0.exileCardState) && text($0.libraryCardState) && text($0.graveyardCardState) }),
              requires.allSatisfy({ $0.template.id > 0 && text($0.template.name, max: 1024) &&
                  (1...2000).contains($0.quantity) && $0.zoneLocations.count <= 20 &&
                  $0.zoneLocations.allSatisfy { text($0, max: 16) } &&
                  text($0.battlefieldCardState) && text($0.exileCardState) && text($0.libraryCardState) && text($0.graveyardCardState) }),
              produces.allSatisfy({ text($0.feature.name, max: 4096) && (1...2000).contains($0.quantity) })
        else { throw SpellbookError.invalidResponse }
    }
}

struct SpellbookPage: Decodable, Sendable {
    struct Results: Decodable, Sendable {
        let identity: String
        let included: [SpellbookVariant]
        let includedByChangingCommanders: [SpellbookVariant]
        let almostIncluded: [SpellbookVariant]
        let almostIncludedByAddingColors: [SpellbookVariant]
        let almostIncludedByChangingCommanders: [SpellbookVariant]
        let almostIncludedByAddingColorsAndChangingCommanders: [SpellbookVariant]
        var groups: [SpellbookGroup: [SpellbookVariant]] {
            [.included: included, .includedByChangingCommanders: includedByChangingCommanders,
             .almostIncluded: almostIncluded, .almostIncludedByAddingColors: almostIncludedByAddingColors,
             .almostIncludedByChangingCommanders: almostIncludedByChangingCommanders,
             .almostIncludedByAddingColorsAndChangingCommanders: almostIncludedByAddingColorsAndChangingCommanders]
        }
    }
    let count: Int?
    let next: String?
    let results: Results

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= SpellbookAPI.maximumResponseBytes else { throw SpellbookError.responseTooLarge }
        do {
            let page = try JSONDecoder().decode(Self.self, from: data)
            guard page.count.map({ $0 >= 0 }) ?? true,
                  page.results.groups.values.reduce(0, { $0 + $1.count }) <= 1000,
                  page.next.map({ $0.utf8.count <= 2048 }) ?? true,
                  Set(page.results.identity).isSubset(of: Set("WUBRGC")) else { throw SpellbookError.invalidResponse }
            var seen = Set<String>()
            for group in SpellbookGroup.allCases {
                for variant in page.results.groups[group, default: []] {
                    try variant.validate()
                    guard seen.insert(variant.id).inserted else { throw SpellbookError.invalidResponse }
                }
            }
            return page
        } catch let error as SpellbookError { throw error }
        catch { throw SpellbookError.invalidResponse }
    }
}

/// Never follows a provider-supplied arbitrary URL carrying the deck POST body.
/// Pagination is sparse: one bounded request per explicit user action.
enum SpellbookAPI {
    static let endpoint = URL(string: "https://backend.commanderspellbook.com/find-my-combos")!
    static let maximumResponseBytes = 4 * 1024 * 1024
    static let pageSize = 100
    static let maximumResults = 2000
    static func pageURL(offset: Int = 0) throws -> URL {
        guard (0...maximumResults).contains(offset) else { throw SpellbookError.unsafePagination }
        var value = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        value.queryItems = [URLQueryItem(name: "limit", value: String(pageSize)), URLQueryItem(name: "offset", value: String(offset))]
        return value.url!
    }
    static func nextOffset(_ next: String?, after previous: Int) throws -> Int? {
        guard let next else { return nil }
        guard let value = URLComponents(string: next), value.scheme == "https",
              value.host == endpoint.host, value.port == nil, value.user == nil, value.password == nil,
              value.fragment == nil, value.percentEncodedPath == endpoint.path,
              let items = value.queryItems, items.count == 2,
              items.filter({ $0.name == "limit" }).count == 1,
              items.filter({ $0.name == "offset" }).count == 1,
              items.first(where: { $0.name == "limit" })?.value == String(pageSize),
              let raw = items.first(where: { $0.name == "offset" })?.value,
              let offset = Int(raw), String(offset) == raw, offset > previous,
              offset <= maximumResults else { throw SpellbookError.unsafePagination }
        return offset
    }
}

/// Local, conservative named-card check. A provider's "included" bucket may
/// contain flexible templates; it is NOT proof that a combo is executable.
struct SpellbookAssessment: Equatable {
    enum Readiness: Equatable { case namedPiecesPresent, oneCardAway(String), reviewRequirements }
    let readiness: Readiness
    let explanation: String
    static func make(variant: SpellbookVariant, group: SpellbookGroup, deck: SpellbookDeck,
                     commanderColors: [String]?, canonicalName: (String) -> String?) -> Self {
        guard !group.isOther else { return Self(readiness: .reviewRequirements, explanation: group.title) }
        guard variant.status == "OK", !variant.spoiler, variant.legalities.commander == true else {
            return Self(readiness: .reviewRequirements, explanation: "Check spoiler, format legality and provider status before considering this combo.")
        }
        guard let commanderColors, Set(commanderColors).isSubset(of: Set(["W", "U", "B", "R", "G"])),
              Set(variant.identity).subtracting(["C"]).isSubset(of: Set(commanderColors.joined())) else {
            return Self(readiness: .reviewRequirements, explanation: "Commander color identity is unknown or this combo uses additional colors.")
        }
        guard variant.requires.isEmpty else {
            return Self(readiness: .reviewRequirements, explanation: "Contains flexible requirements. Review the named cards, templates and prerequisites; availability is not proven.")
        }
        let available = deck.quantities(), commanders = deck.quantities(commandZoneOnly: true)
        var needed: [String: Int] = [:], commanderNeeded: [String: Int] = [:], names: [String: String] = [:]
        for use in variant.uses {
            guard let name = canonicalName(use.card.name) else {
                return Self(readiness: .reviewRequirements, explanation: "A required card is not resolved in the installed XMage catalogue.")
            }
            let key = SpellbookDeck.key(name)
            guard needed[key, default: 0] <= 2000 - use.quantity else {
                return Self(readiness: .reviewRequirements, explanation: "The required quantities need review.")
            }
            needed[key, default: 0] += use.quantity; names[key] = name
            if use.mustBeCommander { commanderNeeded[key, default: 0] += use.quantity }
        }
        guard commanderNeeded.allSatisfy({ commanders[$0.key, default: 0] >= $0.value }) else {
            return Self(readiness: .reviewRequirements, explanation: "A specific card must be a commander, not merely in the deck.")
        }
        let missing = needed.compactMap { key, count -> (String, Int)? in
            let value = max(0, count - available[key, default: 0]); return value > 0 ? (key, value) : nil
        }
        if missing.isEmpty {
            return Self(readiness: .namedPiecesPresent, explanation: "All named pieces are present. Mana, zones, timing and other prerequisites still apply; this is not an XMage simulation.")
        }
        if missing.count == 1, let (key, quantity) = missing.first, quantity == 1,
           available[key, default: 0] == 0, let name = names[key] {
            return Self(readiness: .oneCardAway(name), explanation: "One named piece is absent. Adding it does not certify deck legality or prove the required game state.")
        }
        return Self(readiness: .reviewRequirements, explanation: "Missing multiple cards or additional copies. No automatic Commander-legal addition is implied.")
    }
}
