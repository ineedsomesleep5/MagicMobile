import CoreGraphics
import XCTest
@testable import MagicMobile

/// Laws: properties that must hold for every input, checked against many seeded random ones (docs/LAWS.md). A failure names
/// its seed, so `forAll(seed: <that seed>)` replays it. The Kotlin twins live in apps/android/core/src/test/.../laws.
struct LawRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    /// SplitMix64: small, fast and the same on every machine.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func forAll(_ name: String, runs: Int = 500, seed: UInt64 = 0x4D61676963, file: StaticString = #filePath, line: UInt = #line,
            _ check: (inout LawRandom) throws -> Void) rethrows {
    for run in 0..<runs {
        var random = LawRandom(seed: seed &+ UInt64(run))
        do { try check(&random) } catch {
            XCTFail("Law '\(name)' broke on case \(run) (seed \(seed &+ UInt64(run))): \(error)", file: file, line: line)
            return
        }
    }
}

struct LawBroken: Error, CustomStringConvertible { let description: String }

func law(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw LawBroken(description: message()) }
}

final class RankedLawsTests: XCTestCase {
    private let mythicPoints = RankPosition.mythicStep * RankPosition.pipsPerDivision

    private func valid(_ position: RankPosition) throws {
        if position.tier == .mythic { try law(position.division == 0, "Mythic has no division: \(position)") }
        else { try law((1...4).contains(position.division) && (0...3).contains(position.pips), "invalid rank \(position)") }
    }

    func testPointsAndRanksConvertBothWays() throws {
        try forAll("RankPosition(points:).points == points") { random in
            let points = Int.random(in: 0..<(mythicPoints + 200), using: &random)
            let position = RankPosition(points: points)
            try valid(position)
            try law(position.points == points, "\(points) read back as \(position.points)")
        }
    }

    func testEveryGameMovesTheLadderTheRightWay() throws {
        try forAll("a season of ranked games") { random in
            var state = RankState.fresh(season: "2026-10")
            for _ in 0..<Int.random(in: 1...200, using: &random) {
                let outcome = [RankOutcome.win, .loss, .draw].randomElement(using: &random)!
                let (next, change) = RankLadder.apply(outcome, to: state, deckBracket: Int.random(in: 1...5, using: &random))
                switch outcome {
                case .win: try law(next.position.points > state.position.points, "a win gained nothing from \(state.position)")
                case .loss:
                    try law(next.position.points <= state.position.points, "a loss gained points from \(state.position)")
                    try law(next.position.tier >= min(state.position.tier, .diamond), "a loss left the tier: \(state.position) → \(next.position)")
                case .draw: try law(next.position == state.position, "a draw moved \(state.position) → \(next.position)")
                }
                try law(next.wins + next.losses + next.draws == state.wins + state.losses + state.draws + 1, "a game was miscounted")
                try law(next.peak >= state.peak && next.peak >= next.position, "peak fell or sits below the rank")
                try law(change.pipDelta == change.after.points - change.before.points, "pipDelta disagrees")
                try valid(next.position)
                state = next
            }
        }
    }

    func testANewSeasonNeverRaisesYourRank() throws {
        try forAll("season rollover") { random in
            let position = RankPosition(points: Int.random(in: 0..<(mythicPoints + 40), using: &random))
            var state = RankState.fresh(season: "2026-09")
            state.position = position
            state.peak = max(position, RankPosition(points: Int.random(in: 0..<(mythicPoints + 40), using: &random)))
            state.wins = Int.random(in: 0..<50, using: &random)
            state.losses = Int.random(in: 0..<50, using: &random)
            try law(RankLadder.rollover(state, to: "2026-09") == state, "the same month changed the state")
            let next = RankLadder.rollover(state, to: "2026-10")
            // Only a Mythic's two-division head start can sit above where a low finish left them.
            let headStart = RankPosition(points: RankLadder.placementWinPips)
            try law(next.position <= max(state.position, headStart), "a new season raised \(state.position) → \(next.position)")
            try law(next.placementLeft == RankLadder.placementMatches, "a new season didn't open placements")
            try law(next.peak == next.position && next.wins + next.losses + next.draws == 0, "the new season isn't fresh")
            try valid(next.position)
        }
    }
}

final class ArenaLayoutLawsTests: XCTestCase {
    /// Every Arena board control stays fully on screen on every phone, in both orientations (build 57's landscape gear sat
    /// 1 pt above the top edge of a 402 pt tall iPhone).
    func testEveryControlStaysOnScreenOnEveryPhone() throws {
        try forAll("Arena controls on screen") { random in
            let short = CGFloat(Int.random(in: 360...440, using: &random)), long = CGFloat(Int.random(in: 740...956, using: &random))
            let screen = Bool.random(using: &random) ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
            let canvas = ArenaCanvas(screen: screen), layout = canvas.layout
            let bounds = CGRect(origin: .zero, size: screen)
            let gear = canvas.point(layout.menu)
            let controls: [(String, CGRect)] = [
                ("gear", CGRect(x: gear.x - 22, y: gear.y - 22, width: 44, height: 44)),
                ("primary button", canvas.rect(layout.primary)), ("secondary button", canvas.rect(layout.secondary)),
                ("pass ahead", canvas.rect(layout.passAhead)), ("undo", canvas.rect(layout.undo)),
            ]
            for (label, rect) in controls {
                try law(bounds.contains(rect), "\(label) \(rect) leaves the \(screen.width)×\(screen.height) screen")
            }
        }
    }
}
