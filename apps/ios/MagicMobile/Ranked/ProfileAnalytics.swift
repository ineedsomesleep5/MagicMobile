import Foundation

/// Who may open a player's profile. Public by default; the server enforces it (mm_public_profile).
/// Rules shared with Android (ProfileAnalytics.kt; parity/profile-cases.json checks both).
enum ProfileVisibility: String, CaseIterable, Codable, Sendable {
    case `public`, friends, `private`

    var title: String {
        switch self {
        case .public: return String(localized: "Public")
        case .friends: return String(localized: "Friends only")
        case .private: return String(localized: "Private")
        }
    }

    /// What the choice means, in a line.
    var detail: String {
        switch self {
        case .public: return String(localized: "Any player can open your profile, with your rank and recent games.")
        case .friends: return String(localized: "Only your friends can open your profile.")
        case .private: return String(localized: "Nobody but you can open your profile. Friends still see when you're online.")
        }
    }
}

/// One finished game as a profile shows it: this phone's own record, or a row from the profile server.
struct ProfileGame: Identifiable, Equatable, Sendable {
    struct Opponent: Equatable, Sendable {
        let name: String
        let commander: String?
        let isAI: Bool
        /// The server hides the name of a player who blocked, or was blocked by, the viewer.
        var hidden = false
    }

    let id: String
    let date: Date
    let mode: PlayMode
    let outcome: RankOutcome
    let deckName: String
    let commanders: [String]
    let colors: [String]
    let opponents: [Opponent]
    let turns: Int?
    /// Pips a ranked game moved (own games only).
    var rankDelta: Int? = nil
    /// The engine's id for the game, to find its detailed record (own games only).
    var engineMatchID: String? = nil

    var commander: String? { commanders.first }
    var vsHuman: Bool { opponents.contains { !$0.isAI } }

    init(id: String, date: Date, mode: PlayMode, outcome: RankOutcome, deckName: String, commanders: [String], colors: [String],
         opponents: [Opponent], turns: Int?, rankDelta: Int? = nil, engineMatchID: String? = nil) {
        self.id = id; self.date = date; self.mode = mode; self.outcome = outcome; self.deckName = deckName
        self.commanders = commanders; self.colors = colors; self.opponents = opponents; self.turns = turns
        self.rankDelta = rankDelta; self.engineMatchID = engineMatchID
    }

    init(_ match: MatchRecord) {
        self.init(id: match.id.uuidString, date: match.date, mode: match.mode, outcome: match.outcome, deckName: match.deckName,
                  commanders: match.commander.map { [$0] } ?? [], colors: match.colors,
                  opponents: match.opponents.map { Opponent(name: $0.name, commander: $0.commander, isAI: $0.isAI) },
                  turns: match.turns > 0 ? match.turns : nil, rankDelta: match.rankChange?.pipDelta, engineMatchID: match.engineMatchID)
    }
}

/// The numbers behind a profile's pictures: record, streaks, weeks, commanders, colors and rank over
/// time. Built from this phone's games, or from the totals the server sends for another player.
struct ProfileSummary: Equatable, Sendable {
    struct Share: Identifiable, Equatable, Sendable {
        let id: String
        let games: Int
        let wins: Int
        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
    }

    struct Week: Identifiable, Equatable, Sendable {
        /// Monday 00:00 UTC.
        let start: Date
        let games: Int
        let wins: Int
        var id: Date { start }
    }

    struct RankPoint: Equatable, Sendable {
        let date: Date
        /// The standing as one number: ladder step * 4 + pips.
        let points: Int
    }

    static let weekCount = 8
    static let maxCommanders = 6

    var games = 0
    var wins = 0
    var losses = 0
    var draws = 0
    var currentStreak = 0
    var bestStreak = 0
    var averageTurns: Double?
    /// The last eight weeks, oldest first, empty weeks included.
    var weeks: [Week] = []
    /// Most played first.
    var commanders: [Share] = []
    /// W U B R G, each with the games played with a commander of that color.
    var colors: [Share] = []
    /// Ranked standings over time, oldest first.
    var rankPoints: [RankPoint] = []

    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }

    init() { weeks = Self.emptyWeeks(now: Date()) }

    init(games: Int, wins: Int, losses: Int, draws: Int, currentStreak: Int, bestStreak: Int, averageTurns: Double?, weeks: [Week],
         commanders: [Share], colors: [Share], rankPoints: [RankPoint]) {
        self.games = games; self.wins = wins; self.losses = losses; self.draws = draws
        self.currentStreak = currentStreak; self.bestStreak = bestStreak; self.averageTurns = averageTurns
        self.weeks = weeks; self.commanders = commanders; self.colors = colors; self.rankPoints = rankPoints
    }

    /// This phone's games, newest first (the record's order). `now` fixes the weeks for tests.
    init(matches: [MatchRecord], now: Date = Date()) {
        self.init(games: matches.map(ProfileGame.init), now: now,
                  rankPoints: matches.reversed().compactMap { match in match.rankChange.map { RankPoint(date: match.date, points: $0.after.points) } })
    }

    /// Games newest first. `rankPoints` is given separately: the rank history is the ranked games' standings,
    /// whatever deck the totals are narrowed to.
    init(games list: [ProfileGame], now: Date = Date(), rankPoints: [RankPoint] = []) {
        let ordered = Array(list.reversed())
        var turnTotal = 0, turnGames = 0, streak = 0
        var commanders: [String: (games: Int, wins: Int)] = [:], colors: [String: (games: Int, wins: Int)] = [:]
        for game in ordered {
            games += 1
            let won = game.outcome == .win
            switch game.outcome {
            case .win: wins += 1; streak += 1; bestStreak = max(bestStreak, streak)
            case .loss: losses += 1; streak = 0
            case .draw: draws += 1; streak = 0
            }
            if let turns = game.turns, turns > 0 { turnTotal += turns; turnGames += 1 }
            for commander in game.commanders {
                commanders[commander, default: (0, 0)].games += 1
                if won { commanders[commander]?.wins += 1 }
            }
            for color in Set(game.colors) where Self.colorOrder.contains(color) {
                colors[color, default: (0, 0)].games += 1
                if won { colors[color]?.wins += 1 }
            }
        }
        currentStreak = streak
        averageTurns = turnGames == 0 ? nil : Double(turnTotal) / Double(turnGames)
        self.commanders = commanders.map { Share(id: $0.key, games: $0.value.games, wins: $0.value.wins) }
            .sorted { $0.games != $1.games ? $0.games > $1.games : $0.id < $1.id }
            .prefix(Self.maxCommanders).map { $0 }
        self.colors = Self.colorOrder.compactMap { key in colors[key].map { Share(id: key, games: $0.games, wins: $0.wins) } }
        self.rankPoints = rankPoints
        var weekly = Self.emptyWeeks(now: now)
        let calendar = Self.calendar
        for game in list {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: game.date)?.start,
                  let index = weekly.firstIndex(where: { $0.start == start }) else { continue }
            weekly[index] = Week(start: start, games: weekly[index].games + 1, wins: weekly[index].wins + (game.outcome == .win ? 1 : 0))
        }
        weeks = weekly
    }

    static let colorOrder = ["W", "U", "B", "R", "G"]

    /// Weeks start on Monday, in UTC, like the server's date_trunc('week').
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func emptyWeeks(now: Date) -> [Week] {
        let calendar = Self.calendar
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weekCount).reversed().compactMap { back in
            calendar.date(byAdding: .weekOfYear, value: -back, to: current).map { Week(start: $0, games: 0, wins: 0) }
        }
    }
}

/// A standing for the rank-history line: the ladder's own position for a points value.
extension ProfileSummary.RankPoint {
    var position: RankPosition { RankPosition(points: points) }
}

/// Another player's profile, as mm_public_profile returns it.
struct PublicProfile: Equatable, Sendable {
    struct Rank: Equatable, Sendable {
        let season: String
        let step: Int
        let pips: Int
        let peakStep: Int
        let wins: Int
        let losses: Int

        /// This season's place, or nil when it is from an earlier season.
        var position: RankPosition? { season == RankLadder.season(for: Date()) ? .published(step: step, pips: pips) : nil }
    }

    var username: String
    /// Set when the viewer may not open it: private, or friends-only for a stranger.
    var restricted: Bool
    var visibility: ProfileVisibility
    /// self, friend, outgoing, incoming or none.
    var relation: String
    var online: Bool?
    var title: String?
    var favoriteCommander: String?
    var rank: Rank?
    var summary: ProfileSummary
    var games: [ProfileGame]

    var isSelf: Bool { relation == "self" }
    var isFriend: Bool { relation == "friend" }

    enum ParseError: Error { case malformed }

    /// Reads the server's JSON. Missing parts come out empty rather than failing the screen.
    static func parse(_ data: Data) throws -> PublicProfile {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let username = root["username"] as? String else {
            throw ParseError.malformed
        }
        let visibility = (root["visibility"] as? String).flatMap(ProfileVisibility.init(rawValue:)) ?? .public
        let relation = root["relation"] as? String ?? "none"
        if root["restricted"] as? Bool == true {
            return PublicProfile(username: username, restricted: true, visibility: visibility, relation: relation, online: nil, title: nil,
                                 favoriteCommander: nil, rank: nil, summary: ProfileSummary(), games: [])
        }
        func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        var rank: Rank?
        if let r = root["rank"] as? [String: Any], let season = r["season"] as? String, let step = int(r["step"]) {
            rank = Rank(season: season, step: step, pips: int(r["pips"]) ?? 0, peakStep: int(r["peakStep"]) ?? step,
                        wins: int(r["wins"]) ?? 0, losses: int(r["losses"]) ?? 0)
        }
        let stats = root["stats"] as? [String: Any] ?? [:]
        let shares: ([[String: Any]], String) -> [ProfileSummary.Share] = { rows, key in
            rows.compactMap { row in
                guard let id = row[key] as? String else { return nil }
                return ProfileSummary.Share(id: id, games: int(row["games"]) ?? 0, wins: int(row["wins"]) ?? 0)
            }
        }
        let weeks: [ProfileSummary.Week] = (root["weekly"] as? [[String: Any]] ?? []).compactMap { row in
            guard let text = row["week"] as? String, let start = PublicProfile.day(text) else { return nil }
            return ProfileSummary.Week(start: start, games: int(row["games"]) ?? 0, wins: int(row["wins"]) ?? 0)
        }
        let points: [ProfileSummary.RankPoint] = (root["rankHistory"] as? [[String: Any]] ?? []).compactMap { row in
            guard let text = row["at"] as? String, let date = PublicProfile.timestamp(text), let value = int(row["points"]) else { return nil }
            return ProfileSummary.RankPoint(date: date, points: value)
        }
        let summary = ProfileSummary(
            games: int(stats["games"]) ?? 0, wins: int(stats["wins"]) ?? 0, losses: int(stats["losses"]) ?? 0, draws: int(stats["draws"]) ?? 0,
            currentStreak: int(stats["currentStreak"]) ?? 0, bestStreak: int(stats["bestStreak"]) ?? 0,
            averageTurns: (stats["avgTurns"] as? NSNumber)?.doubleValue,
            weeks: weeks.isEmpty ? ProfileSummary.emptyWeeks(now: Date()) : weeks,
            commanders: shares(root["commanders"] as? [[String: Any]] ?? [], "name"),
            colors: shares(root["colors"] as? [[String: Any]] ?? [], "color"), rankPoints: points)
        let games: [ProfileGame] = (root["games"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String, let text = row["playedAt"] as? String, let date = PublicProfile.timestamp(text),
                  let mode = (row["mode"] as? String).flatMap(PlayMode.init(rawValue:)),
                  let outcome = (row["result"] as? String).flatMap(RankOutcome.init(rawValue:)) else { return nil }
            let opponents: [ProfileGame.Opponent] = (row["opponents"] as? [[String: Any]] ?? []).compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                return ProfileGame.Opponent(name: name, commander: item["commander"] as? String, isAI: item["ai"] as? Bool ?? true,
                                            hidden: item["hidden"] as? Bool ?? false)
            }
            return ProfileGame(id: id, date: date, mode: mode, outcome: outcome, deckName: row["deckName"] as? String ?? "",
                               commanders: row["commanders"] as? [String] ?? [], colors: row["colors"] as? [String] ?? [],
                               opponents: opponents, turns: int(row["turns"]))
        }
        return PublicProfile(username: username, restricted: false, visibility: visibility, relation: relation,
                             online: root["online"] as? Bool, title: root["title"] as? String,
                             favoriteCommander: root["favoriteCommander"] as? String, rank: rank, summary: summary, games: games)
    }

    /// "2026-10-05" as Monday 00:00 UTC.
    static func day(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return ProfileSummary.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// A week's Monday as the server writes it: "2026-10-05".
    static func dayText(_ date: Date) -> String {
        let parts = ProfileSummary.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// PostgREST timestamps: "2026-10-05T12:30:00+00:00", with or without fractions.
    static func timestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// A player found by typing the start of a name (mm_search_players).
struct PlayerSearchResult: Identifiable, Equatable, Sendable {
    let username: String
    let favoriteCommander: String?
    let season: String?
    let rankStep: Int?
    let pips: Int?
    let visibility: ProfileVisibility
    /// friend, outgoing, incoming or none.
    let relation: String
    let online: Bool?

    var id: String { username }

    var position: RankPosition? {
        guard let rankStep, season == RankLadder.season(for: Date()) else { return nil }
        return .published(step: rankStep, pips: pips ?? 0)
    }

    static func parse(_ data: Data) throws -> [PlayerSearchResult] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw PublicProfile.ParseError.malformed }
        return rows.compactMap { row in
            guard let username = row["username"] as? String else { return nil }
            return PlayerSearchResult(username: username, favoriteCommander: row["favorite_commander"] as? String,
                                      season: row["season"] as? String, rankStep: (row["rank_step"] as? NSNumber)?.intValue,
                                      pips: (row["pips"] as? NSNumber)?.intValue,
                                      visibility: (row["visibility"] as? String).flatMap(ProfileVisibility.init(rawValue:)) ?? .public,
                                      relation: row["relation"] as? String ?? "none", online: row["online"] as? Bool)
        }
    }
}

/// What the search field sends: at least two letters, digits or underscores (the server returns nothing otherwise).
enum PlayerSearchRules {
    static let minimumLength = 2
    static let maximumLength = 20

    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard (minimumLength...maximumLength).contains(trimmed.count),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return trimmed
    }
}
