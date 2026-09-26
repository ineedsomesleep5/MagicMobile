import Foundation

/// Presentation identity is separate from the mutable deck and from native seat IDs.
struct DeckStudioShelfItem: Equatable, Identifiable {
    enum Origin: String, Codable { case local, included }
    let id: String
    let name: String
    let commanders: [String]
    let tags: [String]
    let origin: Origin
    let updatedAt: Date?
}

struct DeckStudioLibraryQuery {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", favorites = "Favorites", local = "My decks", included = "Included"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case edited = "Recently edited", name = "Name", commander = "Commander"
        var id: String { rawValue }
    }
    var text = ""
    var filter: Filter = .all
    var sort: Sort = .edited

    func apply(to items: [DeckStudioShelfItem], favorites: Set<String>) -> [DeckStudioShelfItem] {
        let words = Self.key(text).split(whereSeparator: \.isWhitespace).map(String.init)
        let matching = items.filter { item in
            let haystack = Self.key(([item.name] + item.commanders + item.tags).joined(separator: " "))
            guard words.allSatisfy({ haystack.contains($0) }) else { return false }
            switch filter {
            case .all: return true
            case .favorites: return favorites.contains(item.id)
            case .local: return item.origin == .local
            case .included: return item.origin == .included
            }
        }
        return matching.sorted { lhs, rhs in
            switch sort {
            case .edited:
                let a = lhs.updatedAt ?? .distantPast, b = rhs.updatedAt ?? .distantPast
                if a != b { return a > b }
            case .commander:
                let a = Self.key(lhs.commanders.joined(separator: " / "))
                let b = Self.key(rhs.commanders.joined(separator: " / "))
                if a != b { return a < b }
            case .name: break
            }
            let a = Self.key(lhs.name), b = Self.key(rhs.name)
            return a == b ? lhs.id < rhs.id : a < b
        }
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Bounded whole-draft transactions. A failed edit never partially updates state.
/// Tokens advance on undo/redo too: an old async reply cannot validate a new revision.
struct DeckStudioEditHistory<Value: Equatable> {
    private(set) var value: Value
    private(set) var baseline: Value
    private(set) var generation: UUID = UUID()
    private var past: [Value] = []
    private var future: [Value] = []
    private let limit: Int

    init(_ value: Value, limit: Int = 64) {
        self.value = value; baseline = value; self.limit = max(1, min(limit, 256))
    }
    var isDirty: Bool { value != baseline }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func edit(_ operation: (inout Value) throws -> Void) rethrows {
        var next = value
        try operation(&next)
        guard next != value else { return }
        past.append(value)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll(); value = next; generation = UUID()
    }
    mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append(value); value = previous; generation = UUID()
    }
    mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(value); value = next; generation = UUID()
    }
    mutating func markSaved() { baseline = value }
    mutating func restore(_ recovered: Value) {
        // Restoration is one undoable edit and is still dirty relative to disk.
        edit { $0 = recovered }
    }
}

/// Exact sampling-without-replacement math, not AI playtesting or a mulligan model.
enum DeckStudioProbability {
    enum InputError: Error { case invalidPopulation }
    static func atLeast(_ threshold: Int, successes: Int, population: Int, draws: Int) throws -> Double {
        guard (0...2000).contains(population), (0...population).contains(successes),
              (0...population).contains(draws) else { throw InputError.invalidPopulation }
        let low = max(0, draws - (population - successes)), high = min(successes, draws)
        if threshold <= low { return 1 }
        if threshold > high { return 0 }
        func logChoose(_ n: Int, _ k: Int) -> Double {
            let count = min(k, n - k)
            guard count > 0 else { return 0 }
            var result = 0.0
            for index in 1...count {
                result += log(Double(n - count + index)) - log(Double(index))
            }
            return result
        }
        let denominator = logChoose(population, draws)
        let probability = (threshold...high).reduce(0.0) { total, hits in
            total + exp(logChoose(successes, hits) + logChoose(population - successes, draws - hits) - denominator)
        }
        return min(1, max(0, probability))
    }
}

/// "Group by Role" for the Cards list: automatic categories from the role
/// classifier. A card sits under every role it has, and your own role review
/// replaces the automatic hints for that card. Cards with no role are "Other".
enum DeckStudioRoleGroups {
    static let other = "Other"
    static var order: [String] { DeckStudioRole.allCases.map(\.title) + [other] }

    struct CardFacts {
        let text: String?
        let types: [String]?
        let curated: [DeckStudioRole]
    }

    /// Role group titles for each row, in `order`.
    static func membership(rows: [NativeDeckRow], card: (String) -> CardFacts?,
                           overrides: [String: Set<DeckStudioRole>]) -> [UUID: [String]] {
        var byName: [String: [String]] = [:]
        var result: [UUID: [String]] = [:]
        for row in rows {
            if byName[row.cardName] == nil {
                let facts = card(row.cardName)
                let roles = DeckStudioRoleClassifier.classify(text: facts?.text, types: facts?.types,
                                                              curated: facts?.curated ?? [], reviewed: overrides[row.cardName]).map(\.role)
                byName[row.cardName] = roles.isEmpty ? [other] : DeckStudioRole.allCases.filter { roles.contains($0) }.map(\.title)
            }
            result[row.id] = byName[row.cardName]
        }
        return result
    }

    static func membership(rows: [NativeDeckRow], metadata: NativeDeckMetadataCatalogue?,
                           overrides: [String: Set<DeckStudioRole>]) -> [UUID: [String]] {
        membership(rows: rows, card: { name in
            metadata?.card(named: name).map {
                CardFacts(text: $0.oracleText, types: $0.types, curated: $0.roles.compactMap(DeckStudioRole.init(rawValue:)))
            }
        }, overrides: overrides)
    }

    /// Group headers count unique cards, since one card can appear in several groups.
    static func uniqueCards(_ rows: [NativeDeckRow]) -> Int { Set(rows.map(\.cardName)).count }
}

/// Goldfish sample hand: draw seven from the main deck, London mulligan (shuffle,
/// draw seven, put one card on the bottom per mulligan taken), then draw a card
/// each turn. Commanders and other boards stay out of the library.
struct DeckStudioSampleHand: Equatable {
    struct Card: Identifiable, Equatable {
        let id: Int
        let name: String
    }
    static let handSize = 7

    private(set) var library: [Card]
    private(set) var hand: [Card] = []
    private(set) var mulligans = 0
    /// Cards still to put on the bottom after the latest mulligan.
    private(set) var toBottom = 0
    private(set) var draws = 0
    var turn: Int { draws + 1 }
    var canMulligan: Bool { draws == 0 && toBottom == 0 && mulligans < Self.handSize && !hand.isEmpty }
    var canDraw: Bool { toBottom == 0 && !library.isEmpty }

    /// Main-deck cards, one entry per copy.
    static func libraryNames(from draft: NativeDeckDraft) -> [String] {
        draft.rows.filter { DeckStudioBoard.of($0) == "deck" }.flatMap { Array(repeating: $0.cardName, count: max(0, min($0.quantity, 2000))) }
    }

    init(names: [String]) {
        library = names.enumerated().map { Card(id: $0.offset, name: $0.element) }
    }

    /// A fresh opening hand from the whole deck.
    mutating func deal<G: RandomNumberGenerator>(using generator: inout G) {
        library = (library + hand).sorted { $0.id < $1.id }
        hand = []; mulligans = 0; toBottom = 0; draws = 0
        drawSeven(using: &generator)
    }
    mutating func mulligan<G: RandomNumberGenerator>(using generator: inout G) {
        guard canMulligan else { return }
        library += hand; hand = []
        mulligans += 1
        drawSeven(using: &generator)
        toBottom = min(mulligans, hand.count)
    }
    mutating func putOnBottom(_ id: Int) {
        guard toBottom > 0, let index = hand.firstIndex(where: { $0.id == id }) else { return }
        library.append(hand.remove(at: index))
        toBottom -= 1
    }
    mutating func draw() {
        guard canDraw else { return }
        hand.append(library.removeFirst())
        draws += 1
    }
    private mutating func drawSeven<G: RandomNumberGenerator>(using generator: inout G) {
        library.shuffle(using: &generator)
        let count = min(Self.handSize, library.count)
        hand = Array(library.prefix(count))
        library.removeFirst(count)
    }
}

/// Ordinary user browsing only. This type never loads a page, extracts content,
/// invents a commander slug or embeds a private deck in a URL.
enum DeckStudioEDHRECPolicy {
    static let browseURL = URL(string: "https://edhrec.com/commanders")!
    static let recsURL = URL(string: "https://edhrec.com/recs")!
    static func allowsEmbeddedNavigation(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased() else { return false }
        return host == "edhrec.com" || host == "www.edhrec.com"
    }
    static func allowsExternalBrowser(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              let host = parts.host, !host.isEmpty else { return false }
        return true
    }
}
