import Foundation

/// How a game was started, for the profile and for what a result does to your rank.
enum PlayMode: String, Codable, Sendable {
    /// One AI at your deck's bracket (or the bracket, deck and skill you chose). No rank change.
    case quick
    /// The ladder: a human from the queue, or an AI at your tier.
    case ranked
    /// The custom table: any AI line-up, Game Center or an online table.
    case casual

    /// Who goes first in this mode: Ranked always rolls, since picking yourself would be an edge on the ladder.
    /// The other modes use the player's own "Who goes first?" choice ("choose" or "roll").
    func startingPlayerMode(preference: String) -> String { self == .ranked ? "roll" : preference }
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
    /// How long the game ran, in seconds; nil for games from before 2026-10-26.
    var durationSeconds: Int? = nil
    /// The phone's count at once; the server's once it answers (PlayerRecordStore.settleRanked).
    var rankChange: RankChange?
    let season: String?
    /// The engine's id for the game: it finds the detailed record (Deck Studio's saved game history), when
    /// the player chose to keep one. Games from earlier builds have none.
    var engineMatchID: String? = nil
    /// A ranked AI game's server ticket, so the server's answer finds this game.
    var rankedTicket: UUID? = nil
    /// How the server counted it (counted, too_soon, capped, unverified) and, for an unverified win, why.
    var settlement: String? = nil
    var settlementCheck: String? = nil

    /// Why a ranked win left the ladder alone, as the player reads it; nil when it counted.
    var rankNote: String? { RankSettlement.note(settlement, check: settlementCheck, deckBracket: deckBracket) }

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

/// The player's profile on this phone: ranked standing, match history and chosen title. With a profile name the
/// server keeps the ranked standing (RankedStanding): the phone counts each result at once, then adopts the server's.
@MainActor
final class PlayerRecordStore: ObservableObject {
    static let maxMatches = 300
    /// Engine game records kept on this phone (docs/cloud/game-record.md): the last games, newest first.
    static let maxGameRecords = 50

    /// A ranked game against the AI whose result the server hasn't confirmed yet (mm_ranked_ai_result).
    struct PendingRankedResult: Codable, Equatable {
        let ticket: UUID
        let outcome: RankOutcome
        let date: Date
        /// The ticket carried a server seed (mm_ranked_ai_start2): the result goes with the game record.
        var seeded: Bool? = nil
        /// The game record's file in GameRecords, when the engine kept one.
        var recordFile: String? = nil
    }

    private struct File: Codable {
        var rank: RankState
        var matches: [MatchRecord]
        var title: Achievement?
        var favoriteCommander: String?
        var recentAIDecks: [String]?
        var rankedTicket: UUID?
        var rankedTicketSeeded: Bool?
        var pendingRankedResults: [PendingRankedResult]?
    }

    @Published private(set) var rank: RankState
    @Published private(set) var matches: [MatchRecord]
    @Published var title: Achievement? { didSet { if title != oldValue { save() } } }
    @Published var favoriteCommander: String? { didSet { if favoriteCommander != oldValue { save() } } }
    /// The last AI decks faced, so the next pick is a different one.
    private(set) var recentAIDecks: [String] = []
    /// The server's ticket for the ranked AI game being played (mm_ranked_ai_start); kept across a resume.
    private(set) var rankedTicket: UUID?
    /// That ticket carried a server seed.
    private(set) var rankedTicketSeeded = false
    /// Finished ranked AI games still to send, oldest first.
    private(set) var pendingRankedResults: [PendingRankedResult] = []
    /// Set by the app to share rank changes with friends; nil in tests.
    var publish: ((RankState, PlayerStats, Achievement?, String?) -> Void)?
    /// Set by the app to send each finished game to the profile server; nil in tests.
    var didRecord: ((MatchRecord) -> Void)?

    private let fileURL: URL?
    /// Game records, one JSON file per finished game (the engine's `record`), private to this phone.
    let gameRecordsURL: URL?
    private let now: () -> Date

    init(directory: URL?, now: @escaping () -> Date = Date.init) {
        self.now = now
        fileURL = directory?.appendingPathComponent("player-record.json")
        gameRecordsURL = directory?.appendingPathComponent("GameRecords", isDirectory: true)
        let season = RankLadder.season(for: now())
        var loaded = File(rank: .newPlayer(season: season), matches: [])
        if let fileURL, let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder.record.decode(File.self, from: data) {
            loaded = file
        }
        rank = RankLadder.rollover(loaded.rank, to: season)
        matches = loaded.matches
        title = loaded.title
        favoriteCommander = loaded.favoriteCommander
        recentAIDecks = loaded.recentAIDecks ?? []
        rankedTicket = loaded.rankedTicket
        rankedTicketSeeded = loaded.rankedTicketSeeded ?? false
        pendingRankedResults = loaded.pendingRankedResults ?? []
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
                durationSeconds: Int? = nil, aiDeckID: String? = nil, engineMatchID: String? = nil, gameRecordFile: String? = nil) -> RankChange? {
        refreshSeason()
        var change: RankChange?
        if mode == .ranked {
            let result = RankLadder.apply(outcome, to: rank, deckBracket: deckBracket)
            rank = result.state
            change = result.change
        }
        var match = MatchRecord(date: now(), mode: mode, opponents: opponents, opponentBracket: opponentBracket, aiSkill: aiSkill,
                                deckID: deckID, deckName: deckName, commander: commander, colors: colors, deckBracket: deckBracket,
                                outcome: outcome, turns: turns, rankChange: change, season: mode == .ranked ? rank.season : nil,
                                engineMatchID: engineMatchID)
        match.durationSeconds = durationSeconds.map { min(86_400, max(0, $0)) }
        if mode == .ranked, opponents.allSatisfy(\.isAI) { match.rankedTicket = rankedTicket }
        matches.insert(match, at: 0)
        if matches.count > Self.maxMatches { matches.removeLast(matches.count - Self.maxMatches) }
        if let aiDeckID { recentAIDecks = Array(([aiDeckID] + recentAIDecks.filter { $0 != aiDeckID }).prefix(4)) }
        if mode == .ranked, opponents.allSatisfy(\.isAI), let ticket = rankedTicket {
            let pending = PendingRankedResult(ticket: ticket, outcome: outcome, date: now(), seeded: rankedTicketSeeded,
                                              recordFile: gameRecordFile)
            pendingRankedResults = Array((pendingRankedResults + [pending]).suffix(20))
            rankedTicket = nil
            rankedTicketSeeded = false
        }
        save()
        if mode == .ranked { publish?(rank, stats, title, shownCommander) }
        // The finished game goes to the profile server too (when there is a profile): never blocks play.
        didRecord?(match)
        return change
    }

    func publishNow() { publish?(rank, stats, title, shownCommander) }

    /// A ranked AI game began; `ticket` is the server's (nil offline: that game counts on this phone only).
    func beginRankedAIGame(ticket: UUID?, seeded: Bool = false) {
        guard rankedTicket != ticket || rankedTicketSeeded != seeded else { return }
        rankedTicket = ticket
        rankedTicketSeeded = ticket != nil && seeded
        save()
    }

    /// Keeps a finished game's record (the engine's JSON) and returns its file name; the oldest go past
    /// `maxGameRecords`. Excluded from backups: it holds every hand and library order of that game.
    func keepGameRecord(_ data: Data) -> String? {
        guard let gameRecordsURL else { return nil }
        let name = "game-\(Int(now().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
        do {
            try FileManager.default.createDirectory(at: gameRecordsURL, withIntermediateDirectories: true)
            var folder = gameRecordsURL
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            #if os(iOS)
            // Readable after the first unlock: a ranked result can sync with its record while the phone is locked.
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            #else
            let options: Data.WritingOptions = [.atomic] // file protection is iOS-only (the macOS test package)
            #endif
            try data.write(to: gameRecordsURL.appendingPathComponent(name), options: options)
        } catch { return nil }
        for old in gameRecordFiles().dropFirst(Self.maxGameRecords) { try? FileManager.default.removeItem(at: old) }
        return name
    }

    /// The kept game records, newest first.
    func gameRecordFiles() -> [URL] {
        guard let gameRecordsURL, let files = try? FileManager.default.contentsOfDirectory(at: gameRecordsURL, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// A kept record by file name, for the ranked upload.
    func gameRecord(named name: String) -> Data? {
        guard let gameRecordsURL, !name.contains("/") else { return nil }
        return try? Data(contentsOf: gameRecordsURL.appendingPathComponent(name))
    }

    /// Whether the named record is still on the phone (readable or not).
    func gameRecordIsKept(named name: String) -> Bool {
        guard let gameRecordsURL, !name.contains("/") else { return false }
        return FileManager.default.fileExists(atPath: gameRecordsURL.appendingPathComponent(name).path)
    }

    /// The server's answer for a ranked AI game: how it counted, and its own move on the ladder in place of the phone's.
    /// `points`: the server's standing now, so a win it held back shows where the player really stands.
    func settleRanked(ticket: UUID, settlement: String?, check: String?, change: RankedStanding.Change?, points: Int? = nil) {
        guard let index = matches.firstIndex(where: { $0.rankedTicket == ticket }) else { return }
        var match = matches[index]
        match.settlement = settlement
        match.settlementCheck = check
        if let before = change?.pointsBefore, let after = change?.pointsAfter {
            match.rankChange = RankChange(outcome: match.outcome, before: RankPosition(points: before), after: RankPosition(points: after),
                                          bonuses: (change?.bonuses ?? []).compactMap(RankChange.Bonus.init(rawValue:)),
                                          placementLeft: change?.placementLeft)
        } else if RankSettlement.held(settlement), let local = match.rankChange {
            let stands = points.map { RankPosition(points: $0) } ?? local.before
            // A held placement win gives its game back, so it can't reveal a rank or finish placements.
            match.rankChange = RankChange(outcome: local.outcome, before: stands, after: stands, bonuses: [],
                                          placementLeft: local.placementLeft.map { $0 + 1 })
        }
        guard match != matches[index] else { return }
        matches[index] = match
        save()
    }

    /// The server answered for this ticket (or never will).
    func resolvePendingRankedResult(_ ticket: UUID) {
        guard pendingRankedResults.contains(where: { $0.ticket == ticket }) else { return }
        pendingRankedResults.removeAll { $0.ticket == ticket }
        save()
    }

    /// Takes the server's standing. Kept back while a result is still on its way (a friend match the other side
    /// hasn't reported, or an AI result not sent yet), so a pip just earned never flickers away.
    func adopt(_ standing: RankedStanding) {
        guard standing.unsettled == 0, pendingRankedResults.isEmpty, standing.season >= rank.season else { return }
        var next = standing.season == rank.season ? rank : RankLadder.rollover(rank, to: standing.season)
        next.position = RankPosition(points: standing.points)
        next.peak = max(RankPosition(points: standing.peakPoints), next.position)
        next.wins = standing.wins
        next.losses = standing.losses
        next.draws = standing.draws
        next.winStreak = standing.winStreak
        if let left = standing.placementLeft { next.placementGames = left }
        // The server's past seasons replace the phone's for the same month.
        for record in standing.history ?? [] {
            let season = SeasonRecord(season: record.season, final: RankPosition(points: record.finalPoints),
                                      peak: RankPosition(points: record.peakPoints), wins: record.wins, losses: record.losses)
            if let index = next.history.firstIndex(where: { $0.season == record.season }) { next.history[index] = season }
            else { next.history.append(season) }
        }
        next.history = Array(next.history.sorted { $0.season > $1.season }.prefix(24))
        guard next != rank else { return }
        rank = next
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let file = File(rank: rank, matches: matches, title: title, favoriteCommander: favoriteCommander, recentAIDecks: recentAIDecks,
                        rankedTicket: rankedTicket, rankedTicketSeeded: rankedTicketSeeded, pendingRankedResults: pendingRankedResults)
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
            rank.placementGames = environment["MAGICMOBILE_UI_TEST_PLACEMENT"].flatMap(Int.init)
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
        if let left = environment["MAGICMOBILE_UI_TEST_PLACEMENT"].flatMap(Int.init) { rank.placementGames = left }
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
