import Foundation

/// The ranked ladder (1v1): Bronze to Diamond in four divisions each (IV lowest, I highest), then
/// Mythic. Four pips fill a division. Wins and losses both move you, so you can rank down too.
/// Rules shared with Android (RankLadder.kt); parity/ranked-cases.json checks both.
enum RankTier: Int, CaseIterable, Codable, Comparable, Sendable {
    case bronze, silver, gold, platinum, diamond, mythic

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .bronze: return String(localized: "Bronze")
        case .silver: return String(localized: "Silver")
        case .gold: return String(localized: "Gold")
        case .platinum: return String(localized: "Platinum")
        case .diamond: return String(localized: "Diamond")
        case .mythic: return String(localized: "Mythic")
        }
    }

    /// The badge art (Assets.xcassets; Android gets the same files as tavern_rank_*).
    var assetName: String { "tavern-rank-\(String(describing: self))" }

    /// Brackets your opponents' decks come from at this tier. Bracket 1 is never asked for: the
    /// Exhibition AI decks are tribal lists no weaker than Core, so Bronze plays precons instead.
    var opponentBrackets: ClosedRange<Int> {
        switch self {
        case .bronze: return 2...2
        case .silver: return 2...2
        case .gold: return 2...3
        case .platinum: return 3...3
        case .diamond: return 3...4
        case .mythic: return 4...4
        }
    }

    /// The strongest deck you may queue with here. A weaker deck is allowed and earns an extra pip per win.
    var maxDeckBracket: Int { opponentBrackets.upperBound }

    /// Pips a ranked win earns here (Arena's Bo1 steps; ladder option B, Caleb 2026-10-15): two up to Gold, one from Platinum.
    var winPips: Int { self <= .gold ? 2 : 1 }
    /// Pips a ranked loss costs here: none in Bronze.
    var lossPips: Int { self == .bronze ? 0 : 1 }

    /// Bronze AI opponents play only the official precons, the gentlest decks in the pool.
    var preconOpponentsOnly: Bool { self == .bronze }

    /// XMage AI skill for AI opponents at this tier (AIDifficulty.java): Bronze to Gold look fewer moves ahead
    /// and make deliberate mistakes, Platinum plays upstream's full strength, Diamond and Mythic play as experts
    /// (combat planner). It thinks skill × 3 s. Mythic stops at 6: skill 7 means 21 s turns on a phone.
    var aiSkill: Int {
        switch self {
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        case .platinum: return 4
        case .diamond: return 5
        case .mythic: return 6
        }
    }
}

/// A place on the ladder. `division` is 4 (lowest) to 1, 0 for Mythic; `pips` is 0–3 below Mythic and
/// counts up without limit in Mythic.
struct RankPosition: Codable, Equatable, Comparable, Hashable, Sendable {
    static let pipsPerDivision = 4
    static let divisions = 4
    /// Steps below Mythic: five tiers of four divisions.
    static let mythicStep = 20

    var tier: RankTier
    var division: Int
    var pips: Int

    static let start = RankPosition(tier: .bronze, division: 4, pips: 0)

    /// 0 (Bronze IV) to 20 (Mythic).
    var step: Int { tier == .mythic ? Self.mythicStep : tier.rawValue * Self.divisions + (Self.divisions - division) }

    /// Every pip ever earned, as one number: losing below 0 pips steps down a division.
    var points: Int { step * Self.pipsPerDivision + pips }

    init(tier: RankTier, division: Int, pips: Int) {
        self.tier = tier
        self.division = tier == .mythic ? 0 : min(4, max(1, division))
        self.pips = max(0, tier == .mythic ? pips : min(Self.pipsPerDivision - 1, pips))
    }

    init(points: Int) {
        let points = max(0, points)
        let step = points / Self.pipsPerDivision
        if step >= Self.mythicStep {
            self.init(tier: .mythic, division: 0, pips: points - Self.mythicStep * Self.pipsPerDivision)
        } else {
            self.init(tier: RankTier(rawValue: step / Self.divisions) ?? .bronze,
                      division: Self.divisions - step % Self.divisions, pips: points % Self.pipsPerDivision)
        }
    }

    static func atStep(_ step: Int) -> RankPosition { RankPosition(points: max(0, min(Self.mythicStep, step)) * Self.pipsPerDivision) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.points < rhs.points }

    var divisionNumeral: String { ["", "I", "II", "III", "IV"][min(4, max(0, division))] }

    /// "Gold II", "Mythic".
    var title: String { tier == .mythic ? tier.name : "\(tier.name) \(divisionNumeral)" }

    /// The AI's bracket here: the lower bracket of a tier's range in divisions IV–III, the upper in II–I.
    var opponentBracket: Int {
        let range = tier.opponentBrackets
        return division >= 3 ? range.lowerBound : range.upperBound
    }
}

enum RankOutcome: String, Codable, Sendable { case win, loss, draw }

/// How one ranked result moved you.
struct RankChange: Codable, Equatable, Sendable {
    enum Bonus: String, Codable, Sendable {
        /// A third straight win below Gold.
        case streak
        /// A win with a deck below the tier's opponent brackets.
        case underdog
    }

    enum Kind: String, Codable, Sendable { case none, pipUp, pipDown, divisionUp, divisionDown, tierUp, tierDown }

    let outcome: RankOutcome
    let before: RankPosition
    let after: RankPosition
    let bonuses: [Bonus]

    var pipDelta: Int { after.points - before.points }

    var kind: Kind {
        if after.tier != before.tier { return after.tier > before.tier ? .tierUp : .tierDown }
        if after.division != before.division { return after.division < before.division ? .divisionUp : .divisionDown }
        if after.pips != before.pips { return after.pips > before.pips ? .pipUp : .pipDown }
        return .none
    }
}

struct SeasonRecord: Codable, Equatable, Sendable {
    let season: String
    let final: RankPosition
    let peak: RankPosition
    let wins: Int
    let losses: Int
}

/// The player's ranked standing for the current season, plus past seasons.
struct RankState: Codable, Equatable, Sendable {
    var season: String
    var position: RankPosition
    var peak: RankPosition
    var wins = 0
    var losses = 0
    var draws = 0
    var winStreak = 0
    var history: [SeasonRecord] = []

    static func fresh(season: String) -> RankState { RankState(season: season, position: .start, peak: .start) }
}

enum RankLadder {
    /// Seasons are calendar months in UTC: "2026-10".
    static func season(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 2026, parts.month ?? 1)
    }

    /// When a season ends (the next month starts, UTC).
    static func seasonEnd(_ season: String) -> Date? {
        let parts = season.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
        return start.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
    }

    /// "October 2026"
    static func seasonName(_ season: String) -> String {
        guard let end = seasonEnd(season), let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: end) else { return season }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: start)
    }

    /// A new month: last season goes into history and everyone drops one tier (Mythic to Diamond IV),
    /// keeping their division, with empty pips.
    static func rollover(_ state: RankState, to season: String) -> RankState {
        guard state.season != season else { return state }
        var next = RankState.fresh(season: season)
        let played = state.wins + state.losses + state.draws > 0
        next.history = state.history
        if played {
            next.history.insert(SeasonRecord(season: state.season, final: state.position, peak: state.peak,
                                             wins: state.wins, losses: state.losses), at: 0)
        }
        next.history = Array(next.history.prefix(24))
        next.position = .atStep(state.position.step - RankPosition.divisions)
        next.peak = next.position
        return next
    }

    /// One ranked result. `deckBracket` is your deck's bracket, for the underdog pip.
    static func apply(_ outcome: RankOutcome, to state: RankState, deckBracket: Int) -> (state: RankState, change: RankChange) {
        var next = state
        var bonuses: [RankChange.Bonus] = []
        var delta = 0
        switch outcome {
        case .win:
            next.wins += 1
            next.winStreak += 1
            delta = state.position.tier.winPips
            if deckBracket < state.position.tier.opponentBrackets.lowerBound { delta += 1; bonuses.append(.underdog) }
        case .loss:
            next.losses += 1
            next.winStreak = 0
            delta = -state.position.tier.lossPips
        case .draw:
            next.draws += 1
            next.winStreak = 0
        }
        // A loss never takes you out of your tier (Mythic can fall back to Diamond, never below Diamond IV).
        let floor = RankPosition.atStep(min(state.position.tier, .diamond).rawValue * RankPosition.divisions).points
        next.position = RankPosition(points: max(state.position.points + delta, floor))
        next.peak = max(next.peak, next.position)
        return (next, RankChange(outcome: outcome, before: state.position, after: next.position, bonuses: bonuses))
    }
}

/// The ladder as the server keeps it (mm_ranked_standing, Caleb 2026-10-14). Once the player has a profile the
/// server decides rank: the phone shows its own result at once, then takes this.
struct RankedStanding: Decodable, Equatable, Sendable {
    struct Season: Decodable, Equatable, Sendable {
        let season: String
        let finalPoints: Int
        let peakPoints: Int
        let wins: Int
        let losses: Int
    }

    /// False only for a new server standing that has never counted a result: the phone may seed it once.
    let seeded: Bool
    /// Matches this player reported that the other side hasn't yet.
    let unsettled: Int
    let season: String
    let points: Int
    let peakPoints: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winStreak: Int
    let history: [Season]?
    /// How the result just sent counted (mm_ranked_ai_result): counted, too_soon, capped or abandoned.
    let settlement: String?

    static func parse(_ data: Data) throws -> RankedStanding { try JSONDecoder().decode(RankedStanding.self, from: data) }
}

extension RankPosition {
    /// A standing as the profile server keeps it: the ladder step and pips.
    static func published(step: Int, pips: Int) -> RankPosition {
        let base = RankPosition.atStep(step)
        return RankPosition(tier: base.tier, division: base.division, pips: pips)
    }
}

/// The season leaderboard from the server's standings (mm_ranked_leaderboard): everyone or friends, private profiles
/// and blocked players already left out by the server, plus the caller's own row.
struct RankedLeaderboard: Decodable, Equatable, Sendable {
    enum Scope: String, CaseIterable, Sendable { case everyone, friends }

    struct Entry: Decodable, Equatable, Identifiable, Sendable {
        let position: Int
        let username: String
        let title: String?
        let commander: String?
        let points: Int
        let wins: Int
        let losses: Int
        let online: Bool
        let you: Bool

        var id: String { username }
        var rank: RankPosition { RankPosition(points: points) }
    }

    let season: String
    let scope: String
    let total: Int
    let online: Int
    let entries: [Entry]
    let me: Entry?

    static func parse(_ data: Data) throws -> RankedLeaderboard { try JSONDecoder().decode(RankedLeaderboard.self, from: data) }

    /// The caller's row is pinned at the foot when it isn't among the shown entries.
    var pinnedMe: Entry? {
        guard let me, !entries.contains(where: { $0.username == me.username }) else { return nil }
        return me
    }
}
