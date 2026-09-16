import Foundation

/// Explainable, deliberately incomplete role hints. This is neither EDHREC data
/// nor a rules engine. User-reviewed tags override all automatic hints for a card.
enum DeckStudioRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case ramp, cardFlow, interaction, boardWipe, protection, graveyardHate, recursion, tutor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ramp: return "Ramp"
        case .cardFlow: return "Draw / card flow"
        case .interaction: return "Targeted interaction"
        case .boardWipe: return "Board wipes"
        case .protection: return "Protection"
        case .graveyardHate: return "Graveyard interaction"
        case .recursion: return "Recursion"
        case .tutor: return "Tutors"
        }
    }
}

struct DeckStudioRoleEvidence: Equatable, Sendable {
    enum Source: String, Codable, Sendable { case reviewed, textPattern }
    let role: DeckStudioRole
    let source: Source
    let explanation: String
}

enum DeckStudioRoleClassifier {
    private struct Rule {
        let role: DeckStudioRole
        let expression: NSRegularExpression
        let explanation: String
        init(_ role: DeckStudioRole, _ expression: String, _ explanation: String) {
            self.role = role
            // All patterns are compile-time constants, not imported card/user input.
            self.expression = try! NSRegularExpression(pattern: expression)
            self.explanation = explanation
        }
    }
    private static let rules: [Rule] = [
        Rule(.ramp, #"^\{t\}: add (?:\{[wubrgc]\})+\."#, "A nonland permanent has a direct tap-for-mana ability."),
        Rule(.ramp, #"^\{t\}: add one mana of any color(?: in your commander's color identity)?\."#, "A nonland permanent has a direct tap-for-mana ability."),
        Rule(.ramp, #"^search your library for (?:a|up to two) basic land cards?, (?:reveal (?:it|them), )?put (?:it|one of them) onto the battlefield"#, "A library-search instruction puts a basic land onto the battlefield. Conditions still need review."),
        Rule(.cardFlow, #"^draw (?:a|two|three|four|five|six|seven|[1-9][0-9]?) cards?\."#, "A direct draw instruction is present. Cantrips and draw-then-discard effects are card flow, not necessarily net advantage."),
        Rule(.interaction, #"^(?:destroy|exile) target (?:creature|artifact|enchantment|permanent)(?: or (?:creature|artifact|enchantment))?\."#, "A direct targeted removal instruction is present; restrictions and other modes still matter."),
        Rule(.interaction, #"^counter target (?:noncreature )?spell\."#, "A direct counterspell instruction is present."),
        Rule(.boardWipe, #"^(?:destroy|exile) all creatures\."#, "A direct instruction affects all creatures. Symmetry and deck context still matter."),
        Rule(.protection, #"^permanents you control gain hexproof and indestructible until end of turn\."#, "A direct protective instruction grants hexproof and indestructible."),
        Rule(.graveyardHate, #"^exile (?:all cards from all graveyards|target card from a graveyard|target player's graveyard)\."#, "A direct instruction exiles cards from a graveyard."),
        Rule(.recursion, #"^return target (?:(?:creature|artifact|enchantment|permanent) )?card from your graveyard to (?:your hand|the battlefield)\."#, "A direct instruction returns a card from your graveyard."),
        Rule(.tutor, #"^search your library for a card, put that card into your hand, then shuffle\."#, "A direct unrestricted library-search instruction is present.")
    ]
    static func classify(text: String?, types: [String]?, reviewed: Set<DeckStudioRole>? = nil) -> [DeckStudioRoleEvidence] {
        if let reviewed {
            return DeckStudioRole.allCases.filter { reviewed.contains($0) }.map {
                DeckStudioRoleEvidence(role: $0, source: .reviewed, explanation: "You assigned this role. It overrides automatic hints for this card.")
            }
        }
        guard let text, text.utf8.count <= 32768 else { return [] }
        // Match only the beginning of the actual rules text. Do not mine quotations,
        // reminder text, triggers, opposing-player effects or conditional sentences.
        let normalized = text.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var matches: [DeckStudioRole: DeckStudioRoleEvidence] = [:]
        for rule in rules {
            if rule.role == .ramp {
                guard let types, !types.contains("LAND") else { continue }
            }
            if rule.expression.firstMatch(in: normalized, range: range) != nil {
                matches[rule.role] = DeckStudioRoleEvidence(role: rule.role, source: .textPattern, explanation: rule.explanation)
            }
        }
        return DeckStudioRole.allCases.compactMap { matches[$0] }
    }
}

struct DeckStudioRoleAnalysis {
    struct Entry: Equatable {
        let name: String
        let quantity: Int
        let text: String?
        let types: [String]?
    }
    struct Card: Identifiable {
        var id: String { name }
        let name: String
        let quantity: Int
        let evidence: [DeckStudioRoleEvidence]
        let userReviewed: Bool
    }
    let cards: [Card]
    let mainCount: Int
    let unclassifiedCount: Int
    let missingMetadataCount: Int
    func count(_ role: DeckStudioRole) -> Int {
        cards.filter { $0.evidence.contains(where: { $0.role == role }) }.reduce(0) { $0 + $1.quantity }
    }
    init(entries: [Entry], overrides: [String: Set<DeckStudioRole>]) throws {
        guard entries.count <= 2000 else { throw AnalysisError.invalidEntries }
        var total = 0, missing = 0
        var grouped: [String: (Entry, Int)] = [:]
        for entry in entries {
            guard !entry.name.isEmpty, entry.name.utf8.count <= 2000,
                  (1...2000).contains(entry.quantity), entry.quantity <= 2000 - total else { throw AnalysisError.invalidEntries }
            total += entry.quantity
            if entry.text == nil || entry.types == nil { missing += entry.quantity }
            if let prior = grouped[entry.name] {
                guard prior.0.text == entry.text, prior.0.types == entry.types else { throw AnalysisError.inconsistentMetadata }
                grouped[entry.name] = (entry, prior.1 + entry.quantity)
            } else { grouped[entry.name] = (entry, entry.quantity) }
        }
        cards = grouped.keys.sorted().map { name in
            let (entry, count) = grouped[name]!
            return Card(name: name, quantity: count,
                evidence: DeckStudioRoleClassifier.classify(text: entry.text, types: entry.types, reviewed: overrides[name]),
                userReviewed: overrides[name] != nil)
        }
        mainCount = total; missingMetadataCount = missing
        unclassifiedCount = cards.filter { $0.evidence.isEmpty }.reduce(0) { $0 + $1.quantity }
    }
    enum AnalysisError: Error { case invalidEntries, inconsistentMetadata }
}

/// Local auxiliary editor preferences, not part of the engine deck payload.
struct DeckStudioRolePreferences: Codable, Equatable {
    struct Target: Codable, Equatable {
        var enabled = false
        var lower = 0
        var upper = 0
        var isValid: Bool { (0...2000).contains(lower) && (lower...2000).contains(upper) }
        func comparison(_ count: Int) -> String? {
            guard enabled, isValid else { return nil }
            if count < lower { return "Below your target" }
            if count > upper { return "Above your target" }
            return "Within your target"
        }
    }
    var schema = 1
    var overrides: [String: Set<DeckStudioRole>] = [:]
    var targets: [DeckStudioRole: Target] = [:]
    func validated() throws -> Self {
        guard schema == 1, overrides.count <= 2000,
              overrides.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 2000 }),
              targets.values.allSatisfy(\.isValid) else { throw PreferenceError.invalid }
        return self
    }
    static func load(key: String, defaults: UserDefaults = .standard) throws -> Self {
        guard let data = defaults.data(forKey: key) else { return Self() }
        guard data.count <= 512 * 1024 else { throw PreferenceError.invalid }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    func save(key: String, defaults: UserDefaults = .standard) throws {
        let checked = try validated()
        let data = try JSONEncoder().encode(checked)
        guard data.count <= 512 * 1024 else { throw PreferenceError.invalid }
        defaults.set(data, forKey: key)
    }
    enum PreferenceError: LocalizedError {
        case invalid
        var errorDescription: String? { "Saved analysis preferences could not be read safely. They have been preserved; no deck data was changed." }
    }
}
