import Foundation

/// How a game was started, for the profile and for what a result does to your rank.
enum PlayMode: String, Codable, Sendable {
    /// One AI at your deck's bracket (or the bracket, deck and skill you chose). No rank change.
    case quick
    /// The ladder: a human from the queue, or an AI at your tier.
    case ranked
    /// The custom table: any AI line-up, Game Center or an online table.
    case casual
}

/// One finished game on this phone. Only what the player saw: names, commanders, the result.
struct MatchRecord: Codable, Equatable, Identifiable, Sendable {
    struct Opponent: Codable, Equatable, Sendable {
        let name: String
        let commander: String?
        let isAI: Bool
    }

    var id = UUID()
    let date: Date
    let mode: PlayMode
    let opponents: [Opponent]
    /// The AI's bracket and skill, when the opponent was an AI.
    let opponentBracket: Int?
    let aiSkill: Int?
    let deckID: String
    let deckName: String
    let commander: String?
    /// Your commander's colors, W U B R G order.
    let colors: [String]
    let deckBracket: Int
    let outcome: RankOutcome
    let turns: Int
    let rankChange: RankChange?
    let season: String?
    /// The engine's id for the game: it finds the detailed record (Deck Studio's saved game history), when
    /// the player chose to keep one. Games from earlier builds have none.
    var engineMatchID: String? = nil

    var vsHuman: Bool { opponents.contains { !$0.isAI } }
}

/// Wins and losses as the profile shows them.
struct PlayerStats: Equatable, Sendable {
    struct Line: Equatable, Sendable, Identifiable {
        let id: String
        let label: String
        let detail: String?
        var games = 0
        var wins = 0
        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
    }

    var games = 0
    var wins = 0
    var losses = 0
    var draws = 0
    var averageTurns: Double?
    var currentStreak = 0
    var bestStreak = 0
    var decks: [Line] = []
    var commanders: [Line] = []
    /// W U B R G: games and wins with a commander of that color.
    var colors: [Line] = []

    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }

    init(_ matches: [MatchRecord]) {
        // The record keeps the newest game first; streaks read oldest first.
        let ordered = Array(matches.reversed())
        var decks: [String: Line] = [:], commanders: [String: Line] = [:], colors: [String: Line] = [:]
        var turnTotal = 0, turnGames = 0, streak = 0
        for match in ordered {
            games += 1
            let won = match.outcome == .win
            switch match.outcome {
            case .win: wins += 1; streak += 1; bestStreak = max(bestStreak, streak)
            case .loss: losses += 1; streak = 0
            case .draw: draws += 1; streak = 0
            }
            if match.turns > 0 { turnTotal += match.turns; turnGames += 1 }
            let deckKey = match.deckID
            decks[deckKey, default: Line(id: deckKey, label: match.deckName, detail: match.commander)].games += 1
            if won { decks[deckKey]?.wins += 1 }
            if let commander = match.commander {
                commanders[commander, default: Line(id: commander, label: commander, detail: nil)].games += 1
                if won { commanders[commander]?.wins += 1 }
            }
            for color in match.colors {
                colors[color, default: Line(id: color, label: PlayerStats.colorName(color), detail: nil)].games += 1
                if won { colors[color]?.wins += 1 }
            }
        }
        currentStreak = streak
        averageTurns = turnGames == 0 ? nil : Double(turnTotal) / Double(turnGames)
        let byPlay: (Line, Line) -> Bool = { $0.games != $1.games ? $0.games > $1.games : $0.label < $1.label }
        self.decks = decks.values.sorted(by: byPlay)
        self.commanders = commanders.values.sorted(by: byPlay)
        self.colors = ["W", "U", "B", "R", "G"].compactMap { colors[$0] }
    }

    static func colorName(_ symbol: String) -> String {
        switch symbol {
        case "W": return String(localized: "White")
        case "U": return String(localized: "Blue")
        case "B": return String(localized: "Black")
        case "R": return String(localized: "Red")
        case "G": return String(localized: "Green")
        default: return symbol
        }
    }

    /// A commander's colors from its mana cost ("{2}{R}{R}" -> ["R"]), hybrid symbols included.
    static func colors(manaCost: String?) -> [String] {
        guard let manaCost else { return [] }
        let found = Set(manaCost.uppercased().filter { "WUBRG".contains($0) }.map(String.init))
        return ["W", "U", "B", "R", "G"].filter(found.contains)
    }
}

/// Milestones; each unlocks a title the player can show on their profile.
enum Achievement: String, CaseIterable, Codable, Identifiable, Sendable {
    case firstWin, firstRankedWin, silver, gold, platinum, diamond, mythic
    case streak5, veteran, prismatic, giantSlayer, quickDraw, humanWin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstWin: return String(localized: "Rising Star")
        case .firstRankedWin: return String(localized: "Contender")
        case .silver: return String(localized: "Silver Blade")
        case .gold: return String(localized: "Gold Champion")
        case .platinum: return String(localized: "Platinum Warden")
        case .diamond: return String(localized: "Diamond Duelist")
        case .mythic: return String(localized: "Mythic Legend")
        case .streak5: return String(localized: "Unstoppable")
        case .veteran: return String(localized: "Tavern Veteran")
        case .prismatic: return String(localized: "Prismatic")
        case .giantSlayer: return String(localized: "Giant Slayer")
        case .quickDraw: return String(localized: "Quick Draw")
        case .humanWin: return String(localized: "Duelist")
        }
    }

    var detail: String {
        switch self {
        case .firstWin: return String(localized: "Win your first game.")
        case .firstRankedWin: return String(localized: "Win a ranked match.")
        case .silver: return String(localized: "Reach Silver.")
        case .gold: return String(localized: "Reach Gold.")
        case .platinum: return String(localized: "Reach Platinum.")
        case .diamond: return String(localized: "Reach Diamond.")
        case .mythic: return String(localized: "Reach Mythic.")
        case .streak5: return String(localized: "Win five games in a row.")
        case .veteran: return String(localized: "Play 50 games.")
        case .prismatic: return String(localized: "Win with a commander of each color.")
        case .giantSlayer: return String(localized: "Win a ranked match with a deck below the tier's bracket.")
        case .quickDraw: return String(localized: "Win 10 Quick Matches.")
        case .humanWin: return String(localized: "Beat another player online.")
        }
    }

    var systemImage: String {
        switch self {
        case .firstWin: return "star.fill"
        case .firstRankedWin: return "shield.lefthalf.filled"
        case .silver, .gold, .platinum, .diamond, .mythic: return "crown.fill"
        case .streak5: return "flame.fill"
        case .veteran: return "hourglass"
        case .prismatic: return "circle.hexagongrid.fill"
        case .giantSlayer: return "bolt.shield.fill"
        case .quickDraw: return "hare.fill"
        case .humanWin: return "person.2.fill"
        }
    }

    /// What the record has earned. Tiers count the best rank ever reached, in any season.
    static func unlocked(matches: [MatchRecord], rank: RankState) -> Set<Achievement> {
        var set = Set<Achievement>()
        let wins = matches.filter { $0.outcome == .win }
        if !wins.isEmpty { set.insert(.firstWin) }
        if wins.contains(where: { $0.mode == .ranked }) { set.insert(.firstRankedWin) }
        if wins.contains(where: { $0.mode != .quick && $0.vsHuman }) { set.insert(.humanWin) }
        let best = ([rank.peak] + rank.history.map(\.peak)).max() ?? .start
        let tiers: [(RankTier, Achievement)] = [(.silver, .silver), (.gold, .gold), (.platinum, .platinum), (.diamond, .diamond), (.mythic, .mythic)]
        for (tier, achievement) in tiers where best.tier >= tier { set.insert(achievement) }
        if PlayerStats(matches).bestStreak >= 5 { set.insert(.streak5) }
        if matches.count >= 50 { set.insert(.veteran) }
        if Set(wins.flatMap(\.colors)).isSuperset(of: ["W", "U", "B", "R", "G"]) { set.insert(.prismatic) }
        if wins.contains(where: { $0.rankChange?.bonuses.contains(.underdog) == true }) { set.insert(.giantSlayer) }
        if wins.filter({ $0.mode == .quick }).count >= 10 { set.insert(.quickDraw) }
        return set
    }
}

/// The player's profile on this phone: ranked standing, match history and chosen title. Ranked
/// standing is also published to the profile server (when signed in) so friends see it.
@MainActor
final class PlayerRecordStore: ObservableObject {
    static let maxMatches = 300

    private struct File: Codable {
        var rank: RankState
        var matches: [MatchRecord]
        var title: Achievement?
        var favoriteCommander: String?
        var recentAIDecks: [String]?
    }

    @Published private(set) var rank: RankState
    @Published private(set) var matches: [MatchRecord]
    @Published var title: Achievement? { didSet { if title != oldValue { save() } } }
    @Published var favoriteCommander: String? { didSet { if favoriteCommander != oldValue { save() } } }
    /// The last AI decks faced, so the next pick is a different one.
    private(set) var recentAIDecks: [String] = []
    /// Set by the app to share rank changes with friends; nil in tests.
    var publish: ((RankState, PlayerStats, Achievement?, String?) -> Void)?
    /// Set by the app to send each finished game to the profile server; nil in tests.
    var didRecord: ((MatchRecord) -> Void)?

    private let fileURL: URL?
    private let now: () -> Date

    init(directory: URL?, now: @escaping () -> Date = Date.init) {
        self.now = now
        fileURL = directory?.appendingPathComponent("player-record.json")
        let season = RankLadder.season(for: now())
        var loaded = File(rank: .fresh(season: season), matches: [])
        if let fileURL, let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder.record.decode(File.self, from: data) {
            loaded = file
        }
        rank = RankLadder.rollover(loaded.rank, to: season)
        matches = loaded.matches
        title = loaded.title
        favoriteCommander = loaded.favoriteCommander
        recentAIDecks = loaded.recentAIDecks ?? []
        if rank != loaded.rank { save() }
    }

    /// The app's store: Application Support/Profile for the shipped app, a temporary folder for
    /// tests and previews.
    static let shared: PlayerRecordStore = {
        let testing = NSClassFromString("XCTestCase") != nil
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = OnDeviceAppConfiguration.entryPoint == .embedded && !testing
            ? support?.appendingPathComponent("Profile", isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent("Profile-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = PlayerRecordStore(directory: directory)
        #if DEBUG
        store.applyUITestSeed(ProcessInfo.processInfo.environment)
        #endif
        return store
    }()

    var stats: PlayerStats { PlayerStats(matches) }
    var achievements: Set<Achievement> { Achievement.unlocked(matches: matches, rank: rank) }

    /// The favorite commander chosen, or the one played most.
    var shownCommander: String? { favoriteCommander ?? stats.commanders.first?.label }

    /// A new month started while the app was open.
    func refreshSeason() {
        let season = RankLadder.season(for: now())
        guard season != rank.season else { return }
        rank = RankLadder.rollover(rank, to: season)
        save()
    }

    /// Records a finished game. A ranked game moves the ladder and returns how.
    @discardableResult
    func record(mode: PlayMode, outcome: RankOutcome, opponents: [MatchRecord.Opponent], opponentBracket: Int?, aiSkill: Int?,
                deckID: String, deckName: String, commander: String?, colors: [String], deckBracket: Int, turns: Int,
                aiDeckID: String? = nil, engineMatchID: String? = nil) -> RankChange? {
        refreshSeason()
        var change: RankChange?
        if mode == .ranked {
            let result = RankLadder.apply(outcome, to: rank, deckBracket: deckBracket)
            rank = result.state
            change = result.change
        }
        let match = MatchRecord(date: now(), mode: mode, opponents: opponents, opponentBracket: opponentBracket, aiSkill: aiSkill,
                                deckID: deckID, deckName: deckName, commander: commander, colors: colors, deckBracket: deckBracket,
                                outcome: outcome, turns: turns, rankChange: change, season: mode == .ranked ? rank.season : nil,
                                engineMatchID: engineMatchID)
        matches.insert(match, at: 0)
        if matches.count > Self.maxMatches { matches.removeLast(matches.count - Self.maxMatches) }
        if let aiDeckID { recentAIDecks = Array(([aiDeckID] + recentAIDecks.filter { $0 != aiDeckID }).prefix(4)) }
        save()
        if mode == .ranked { publish?(rank, stats, title, shownCommander) }
        // The finished game goes to the profile server too (when there is a profile): never blocks play.
        didRecord?(match)
        return change
    }

    func publishNow() { publish?(rank, stats, title, shownCommander) }

    private func save() {
        guard let fileURL else { return }
        let file = File(rank: rank, matches: matches, title: title, favoriteCommander: favoriteCommander, recentAIDecks: recentAIDecks)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.record.encode(file).write(to: fileURL, options: .atomic)
        } catch {
            // The profile is a convenience; a failed save never interrupts play.
        }
    }

    #if DEBUG
    /// UI tests: MAGICMOBILE_UI_TEST_RANK=<tier>-<division>-<pips>[-<streak>] sets the standing, and
    /// MAGICMOBILE_UI_TEST_MATCHES=<n> adds sample history.
    func applyUITestSeed(_ environment: [String: String]) {
        if SocialFixtures.isActive {
            let fixture = SocialFixtures.matches(now: now(), season: rank.season)
            matches = fixture.matches
            rank = fixture.rank
            favoriteCommander = nil
            return
        }
        if ProfileHistoryFixture.isActive {
            matches = ProfileHistoryFixture.matches()
            return
        }
        if let seed = environment["MAGICMOBILE_UI_TEST_RANK"] {
            let parts = seed.split(separator: "-").map(String.init)
            if parts.count >= 3, let tier = RankTier.allCases.first(where: { String(describing: $0) == parts[0] }),
               let division = Int(parts[1]), let pips = Int(parts[2]) {
                rank.position = RankPosition(tier: tier, division: division, pips: pips)
                rank.peak = max(rank.peak, rank.position)
                if parts.count >= 4, let streak = Int(parts[3]) { rank.winStreak = streak }
            }
        }
        if let count = environment["MAGICMOBILE_UI_TEST_MATCHES"].flatMap(Int.init), count > 0 {
            let decks = AIDeckPool.all
            for index in 0..<count {
                let deck = decks[index % decks.count], foe = decks[(index + 3) % decks.count]
                matches.append(MatchRecord(date: now().addingTimeInterval(Double(-index) * 3600), mode: index % 3 == 0 ? .ranked : .quick,
                                           opponents: [.init(name: foe.name, commander: foe.commander, isAI: true)],
                                           opponentBracket: foe.bracket.rawValue, aiSkill: 3, deckID: deck.playerDeckID,
                                           deckName: deck.name, commander: deck.commander, colors: deck.colors.map(String.init),
                                           deckBracket: deck.bracket.rawValue, outcome: index % 3 == 1 ? .loss : .win,
                                           turns: 7 + index % 5, rankChange: nil, season: rank.season))
            }
        }
    }
    #endif
}

private extension JSONEncoder {
    static var record: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var record: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
