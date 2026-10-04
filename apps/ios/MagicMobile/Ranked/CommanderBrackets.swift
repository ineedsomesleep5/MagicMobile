import Foundation

/// Wizards' Commander Brackets (beta). A decklist shows the lowest bracket a deck can be in; the
/// player's intent (1 vs 2, 4 vs 5) is their call. The card lists live in commander-brackets.json
/// (scripts/ranked/build_bracket_rules.py); Android reads the same file (CommanderBrackets.kt) and
/// parity/ranked-cases.json checks both.
enum CommanderBracket: Int, CaseIterable, Codable, Comparable, Identifiable, Sendable {
    case exhibition = 1, core, upgraded, optimized, cedh

    var id: Int { rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .exhibition: return String(localized: "Exhibition")
        case .core: return String(localized: "Core")
        case .upgraded: return String(localized: "Upgraded")
        case .optimized: return String(localized: "Optimized")
        case .cedh: return String(localized: "cEDH")
        }
    }

    /// "Bracket 3 · Upgraded"
    var title: String { String(localized: "Bracket \(rawValue) · \(name)") }

    var blurb: String {
        switch self {
        case .exhibition: return String(localized: "Theme first. Games are slow and win in style.")
        case .core: return String(localized: "Like a modern precon. No Game Changers, no fast combos.")
        case .upgraded: return String(localized: "Tuned decks with up to three Game Changers.")
        case .optimized: return String(localized: "Fast, lethal decks. Anything legal goes.")
        case .cedh: return String(localized: "Competitive Commander. Built to win as fast as possible.")
        }
    }

    init(clamping value: Int) { self = CommanderBracket(rawValue: min(5, max(1, value))) ?? .core }
}

/// The card lists the bracket check reads.
struct BracketRules: Equatable, Sendable {
    struct Combo: Equatable, Sendable, Decodable {
        let cards: [String]
        let manaValue: Int
        /// Cheap enough to win in the first few turns: only Bracket 4 and up.
        let early: Bool
    }

    let gameChangers: Set<String>
    let massLandDenial: Set<String>
    let extraTurns: Set<String>
    let combos: [Combo]
    /// This many extra-turn cards read as a deck built to chain them.
    let chainedExtraTurns: Int

    private struct File: Decodable {
        let gameChangers: [String]
        let massLandDenial: [String]
        let extraTurns: [String]
        let combos: [Combo]
        let chainedExtraTurns: Int
    }

    init(gameChangers: Set<String>, massLandDenial: Set<String>, extraTurns: Set<String>, combos: [Combo], chainedExtraTurns: Int = 3) {
        self.gameChangers = gameChangers; self.massLandDenial = massLandDenial; self.extraTurns = extraTurns
        self.combos = combos; self.chainedExtraTurns = chainedExtraTurns
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(gameChangers: Set(file.gameChangers), massLandDenial: Set(file.massLandDenial),
                  extraTurns: Set(file.extraTurns), combos: file.combos, chainedExtraTurns: file.chainedExtraTurns)
    }

    /// The bundled lists. A missing file (never in a shipped app) checks nothing rather than crashing.
    static let bundled: BracketRules = {
        guard let url = Bundle.main.url(forResource: "commander-brackets", withExtension: "json"),
              let data = try? Data(contentsOf: url), let rules = try? BracketRules(data: data) else {
            return BracketRules(gameChangers: [], massLandDenial: [], extraTurns: [], combos: [])
        }
        return rules
    }()

    /// A card as the lists name it: double-faced and split cards are matched by their front face too.
    private func names(_ cards: [String]) -> Set<String> {
        var set = Set<String>()
        for card in cards {
            set.insert(card)
            if let front = card.components(separatedBy: " // ").first, front != card { set.insert(front) }
        }
        return set
    }

    func evaluate(cardNames: [String]) -> BracketReport {
        let cards = names(cardNames)
        let changers = cards.intersection(gameChangers).sorted()
        let landDenial = cards.intersection(massLandDenial).sorted()
        let turns = cards.intersection(extraTurns).sorted()
        let present = combos.filter { Set($0.cards).isSubset(of: cards) }
        var minimum = CommanderBracket.core
        if !changers.isEmpty { minimum = max(minimum, changers.count <= 3 ? .upgraded : .optimized) }
        if !landDenial.isEmpty { minimum = .optimized }
        if turns.count >= chainedExtraTurns { minimum = .optimized }
        for combo in present { minimum = max(minimum, combo.early ? .optimized : .upgraded) }
        return BracketReport(minimum: minimum, gameChangers: changers, massLandDenial: landDenial, extraTurns: turns,
                             combos: present.filter { !$0.early }.map(\.cards), earlyCombos: present.filter(\.early).map(\.cards))
    }

    /// The deck as played: commander plus main deck (sideboard and maybeboard stay out).
    func evaluate(_ deck: DeckList) -> BracketReport {
        let played = deck.entries.filter { $0.section == "deck" || $0.section == "commander" || $0.section == "main" }
        return evaluate(cardNames: (deck.commander.map { [$0.cardName] } ?? []) + played.map(\.cardName))
    }
}

/// What a decklist shows about its bracket, with the cards behind it.
struct BracketReport: Equatable, Sendable {
    let minimum: CommanderBracket
    let gameChangers: [String]
    let massLandDenial: [String]
    let extraTurns: [String]
    /// Two-card combos late enough for Bracket 3.
    let combos: [[String]]
    let earlyCombos: [[String]]

    /// One line per reason the deck sits above Core, for the bracket sheet.
    var reasons: [String] {
        var lines: [String] = []
        if !gameChangers.isEmpty {
            lines.append(String(localized: "\(gameChangers.count) Game Changers: \(gameChangers.joined(separator: ", "))"))
        }
        if !massLandDenial.isEmpty {
            lines.append(String(localized: "Mass land denial: \(massLandDenial.joined(separator: ", "))"))
        }
        if minimum == .optimized, extraTurns.count >= 3 {
            lines.append(String(localized: "Chains extra turns: \(extraTurns.joined(separator: ", "))"))
        }
        for combo in earlyCombos { lines.append(String(localized: "Early two-card combo: \(combo.joined(separator: " + "))")) }
        for combo in combos { lines.append(String(localized: "Two-card combo: \(combo.joined(separator: " + "))")) }
        return lines
    }
}

/// The player's own label for a deck, kept per deck ID. It may raise the bracket (intent), or lower a
/// Core list to Exhibition; never below what the list shows.
enum DeckBracketPreference {
    static let key = "magicmobile.ranked.deckBrackets"

    static func declared(_ deckID: String, in defaults: UserDefaults) -> CommanderBracket? {
        (defaults.dictionary(forKey: key)?[deckID] as? Int).flatMap(CommanderBracket.init(rawValue:))
    }

    static func setDeclared(_ bracket: CommanderBracket?, for deckID: String, in defaults: UserDefaults) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[deckID] = bracket?.rawValue
        defaults.set(all, forKey: key)
    }

    static func effective(minimum: CommanderBracket, declared: CommanderBracket?) -> CommanderBracket {
        guard let declared else { return minimum }
        if declared == .exhibition, minimum == .core { return .exhibition }
        return max(declared, minimum)
    }

    /// The labels a player may choose for a deck whose list shows `minimum`.
    static func choices(minimum: CommanderBracket) -> [CommanderBracket] {
        CommanderBracket.allCases.filter { $0 >= minimum || ($0 == .exhibition && minimum == .core) }
    }
}
