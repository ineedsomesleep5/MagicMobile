import Foundation

/// A fast, offline quick check of the Commander basics while editing: deck size,
/// a commander, colour identity, singleton copies and cards this build can play.
/// It is advisory only. XMage checks the deck when it is played, and a quick check
/// never blocks Play. Anything it cannot judge (missing metadata, an unknown
/// commander identity, partner or background pairings) is left to XMage rather
/// than reported, so the check errs towards staying quiet.
struct DeckStudioPreflight: Equatable {
    static let targetCount = 100
    static let caption = "Quick check · XMage confirms when you play"

    enum Issue: String, CaseIterable, Identifiable, Sendable {
        case missingCommander, offIdentity, duplicate, unresolved
        var id: String { rawValue }
        /// Chip title. Row issues add " · N" with the number of affected rows.
        var title: String {
            switch self {
            case .missingCommander: return "Missing commander"
            case .offIdentity: return "Off-color"
            case .duplicate: return "Duplicates"
            case .unresolved: return "Unresolved"
            }
        }
        /// Inline badge on an affected row.
        var badge: String {
            switch self {
            case .missingCommander: return "Missing commander"
            case .offIdentity: return "Off-color"
            case .duplicate: return "Duplicate"
            case .unresolved: return "Unresolved"
            }
        }
    }

    /// What the check needs from the bundled card catalogue.
    struct CardFacts: Equatable, Sendable {
        let name: String
        let typeLine: String?
        let oracleText: String?
        /// nil means unknown, [] means colorless.
        let colorIdentity: [String]?
    }

    /// Main deck plus commanders; companions and other boards are outside the 100.
    let count: Int
    let missingCommander: Bool
    /// Union of the commanders' identities; nil when any commander's identity is unknown.
    let commanderIdentity: Set<String>?
    private let flagged: [Issue: Set<UUID>]

    func rows(_ issue: Issue) -> Set<UUID> { flagged[issue] ?? [] }
    func issues(for row: UUID) -> [Issue] { Issue.allCases.filter { flagged[$0]?.contains(row) == true } }
    var issueCount: Int { (missingCommander ? 1 : 0) + flagged.values.reduce(0) { $0 + $1.count } }
    /// Chips with something to show, in a fixed order.
    var activeIssues: [Issue] {
        Issue.allCases.filter { $0 == .missingCommander ? missingCommander : !rows($0).isEmpty }
    }
    func chipTitle(_ issue: Issue) -> String {
        issue == .missingCommander ? issue.title : "\(issue.title) · \(rows(issue).count)"
    }
    /// e.g. "3 cards to go · 2 issues", "1 card over · No issues found".
    var summary: String {
        var parts: [String] = []
        if count < Self.targetCount { parts.append("\(CardCountText.label(Self.targetCount - count)) to go") }
        if count > Self.targetCount { parts.append("\(CardCountText.label(count - Self.targetCount)) over") }
        parts.append(issueCount == 0 ? "No issues found" : Self.issueCountText(issueCount))
        return parts.joined(separator: " · ")
    }
    static func issueCountText(_ count: Int) -> String { "\(count) \(count == 1 ? "issue" : "issues")" }

    /// How many copies a Commander deck may hold; nil means any number.
    static func copyLimit(_ card: CardFacts) -> Int? {
        if card.typeLine?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("basic ") == true { return nil }
        let text = (card.oracleText ?? "").lowercased()
        if text.contains("a deck can have any number of cards named") { return nil }
        if let match = upTo.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let value = String(text[range])
            let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
            if let limit = numbers[value] ?? Int(value), limit > 0 { return limit }
        }
        return 1
    }
    // A compile-time constant pattern, never card or user input.
    private static let upTo = try! NSRegularExpression(pattern: #"a deck can have up to ([a-z0-9]+) cards named"#)

    /// - Parameters:
    ///   - card: catalogue facts for a row's card name, or nil when unknown.
    ///   - resolves: whether this build can play the name; nil while no catalogue is loaded.
    init(draft: NativeDeckDraft, card: (String) -> CardFacts?, resolves: ((String) -> Bool)?) {
        let playing = draft.rows.filter { DeckStudioBoard.playing.contains(DeckStudioBoard.of($0)) }
        let commanders = playing.filter { DeckStudioBoard.of($0) == "commanders" }
        count = draft.rows.filter { ["deck", "commanders"].contains(DeckStudioBoard.of($0)) }.reduce(0) { $0 + $1.quantity }
        missingCommander = commanders.isEmpty
        var identity: Set<String>? = commanders.isEmpty ? nil : []
        for row in commanders {
            guard let colors = card(row.cardName)?.colorIdentity else { identity = nil; break }
            identity?.formUnion(colors)
        }
        commanderIdentity = identity
        var flagged: [Issue: Set<UUID>] = [:]
        if let resolves {
            flagged[.unresolved] = Set(playing.filter { !resolves($0.cardName) }.map(\.id))
        }
        if let identity {
            flagged[.offIdentity] = Set(playing.filter { row in
                guard DeckStudioBoard.of(row) != "commanders", let colors = card(row.cardName)?.colorIdentity else { return false }
                return !Set(colors).isSubset(of: identity)
            }.map(\.id))
        }
        // Copies are counted across main, commanders and companions by canonical name.
        var groups: [String: (facts: CardFacts, total: Int, rows: [UUID])] = [:]
        for row in playing {
            guard let facts = card(row.cardName) else { continue }
            let prior = groups[facts.name]
            groups[facts.name] = (facts, (prior?.total ?? 0) + row.quantity, (prior?.rows ?? []) + [row.id])
        }
        flagged[.duplicate] = Set(groups.values.filter { group in
            guard let limit = Self.copyLimit(group.facts) else { return false }
            return group.total > limit
        }.flatMap { $0.rows })
        self.flagged = flagged.filter { !$0.value.isEmpty }
    }

    init(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?) {
        let resolves: ((String) -> Bool)?
        if let resolver { resolves = { resolver.canonicalCardName($0) != nil } }
        else if let metadata { resolves = { metadata.card(named: $0) != nil } }
        else { resolves = nil }
        self.init(draft: draft, card: { name in
            metadata?.card(named: name).map {
                CardFacts(name: $0.name, typeLine: $0.typeLine, oracleText: $0.oracleText, colorIdentity: $0.colorIdentity)
            }
        }, resolves: resolves)
    }
}

/// What the Cards list is narrowed to: one quick-check issue, or the cards XMage named
/// (Fix deck). Both read "Showing only: …" with Show all, and clear once nothing matches.
/// Android's DeckStudioListFilter follows the same rules.
enum DeckStudioListFilter: Equatable {
    case quickCheck(DeckStudioPreflight.Issue)
    case needsFixes([String])

    var label: String {
        switch self {
        case .quickCheck(let issue): return issue.badge
        case .needsFixes: return DeckStudioPlayText.needsFixes
        }
    }
    var title: String { DeckStudioPlayText.showingOnly(label) }
    var issue: DeckStudioPreflight.Issue? { if case .quickCheck(let issue) = self { return issue } else { return nil } }

    func rows(_ preflight: DeckStudioPreflight, draft: NativeDeckDraft, canonical: (String) -> String?) -> Set<UUID> {
        switch self {
        case .quickCheck(let issue): return preflight.rows(issue)
        case .needsFixes(let cards): return DeckStudioPlayRules.fixRows(draft.rows, cards: cards, canonical: canonical)
        }
    }
}
