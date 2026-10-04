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

    /// Brackets your opponents' decks come from at this tier.
    var opponentBrackets: ClosedRange<Int> {
        switch self {
        case .bronze: return 1...2
        case .silver: return 2...2
        case .gold: return 2...3
        case .platinum: return 3...3
        case .diamond: return 3...4
        case .mythic: return 4...4
        }
    }

    /// The strongest deck you may queue with here. A weaker deck is allowed and earns an extra pip per win.
    var maxDeckBracket: Int { opponentBrackets.upperBound }

    /// XMage AI skill for AI opponents at this tier.
    var aiSkill: Int {
        switch self {
        case .bronze: return 2
        case .silver: return 3
        case .gold: return 4
        case .platinum: return 5
        case .diamond: return 6
        case .mythic: return 7
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
            delta = 1
            if state.position.tier < .gold, next.winStreak >= 3 { delta += 1; bonuses.append(.streak) }
            if deckBracket < state.position.tier.opponentBrackets.lowerBound { delta += 1; bonuses.append(.underdog) }
        case .loss:
            next.losses += 1
            next.winStreak = 0
            delta = -1
        case .draw:
            next.draws += 1
            next.winStreak = 0
        }
        next.position = RankPosition(points: state.position.points + delta)
        next.peak = max(next.peak, next.position)
        return (next, RankChange(outcome: outcome, before: state.position, after: next.position, bonuses: bonuses))
    }
}

extension RankPosition {
    /// A standing as the profile server keeps it: the ladder step and pips.
    static func published(step: Int, pips: Int) -> RankPosition {
        let base = RankPosition.atStep(step)
        return RankPosition(tier: base.tier, division: base.division, pips: pips)
    }
}
