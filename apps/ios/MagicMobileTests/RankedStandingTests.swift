import XCTest
@testable import MagicMobile

/// The server keeps the ranked standing (mm_ranked_standing); the phone counts each result at once, sends ranked
/// AI results with their ticket, and adopts the server's standing when nothing is still on its way.
@MainActor
final class RankedStandingTests: XCTestCase {
    private let october = Date(timeIntervalSince1970: 1_791_000_000) // October 2026

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RankedStandingTests-\(UUID().uuidString)")
    }

    private func standing(season: String = "2026-10", points: Int, peak: Int? = nil, wins: Int = 0, losses: Int = 0,
                          unsettled: Int = 0, history: String = "[]") throws -> RankedStanding {
        let json = """
        {"seeded": true, "unsettled": \(unsettled), "season": "\(season)", "points": \(points), "peakPoints": \(peak ?? points),
         "wins": \(wins), "losses": \(losses), "draws": 0, "winStreak": 2, "history": \(history), "settlement": "counted",
         "change": {"outcome": "win"}}
        """
        return try RankedStanding.parse(Data(json.utf8))
    }

    private func play(_ store: PlayerRecordStore, _ outcome: RankOutcome, human: Bool = false) {
        _ = store.record(mode: .ranked, outcome: outcome, opponents: [.init(name: "Foe", commander: nil, isAI: !human)],
                         opponentBracket: 2, aiSkill: 1, deckID: "precon:x", deckName: "Goblins", commander: "Krenko, Mob Boss",
                         colors: ["R"], deckBracket: 2, turns: 9)
    }

    func testParsesTheServerStanding() throws {
        let value = try standing(points: 9, peak: 12, wins: 5, losses: 2,
                                 history: #"[{"season": "2026-09", "finalPoints": 30, "peakPoints": 33, "wins": 9, "losses": 4}]"#)
        XCTAssertEqual(value.points, 9)
        XCTAssertEqual(value.history?.first?.finalPoints, 30)
        XCTAssertEqual(value.settlement, "counted")
    }

    func testAdoptsTheServerStanding() throws {
        let store = PlayerRecordStore(directory: directory(), now: { self.october })
        play(store, .win)
        store.adopt(try standing(points: 9, peak: 12, wins: 5, losses: 2))
        XCTAssertEqual(store.rank.position, RankPosition(tier: .bronze, division: 2, pips: 1))
        XCTAssertEqual(store.rank.peak, RankPosition(tier: .bronze, division: 1, pips: 0))
        XCTAssertEqual(store.rank.wins, 5)
        XCTAssertEqual(store.rank.losses, 2)
        XCTAssertEqual(store.rank.winStreak, 2)
        // The match history the phone recorded stays.
        XCTAssertEqual(store.matches.count, 1)
    }

    func testKeepsItsOwnCountWhileAResultIsOnItsWay() throws {
        let store = PlayerRecordStore(directory: directory(), now: { self.october })
        play(store, .win)
        let shown = store.rank
        // A friend match the other side hasn't reported yet.
        store.adopt(try standing(points: 0, unsettled: 1))
        XCTAssertEqual(store.rank, shown)
        // An AI result not sent yet.
        store.beginRankedAIGame(ticket: UUID())
        play(store, .win)
        XCTAssertEqual(store.pendingRankedResults.count, 1)
        let afterSecond = store.rank
        store.adopt(try standing(points: 1))
        XCTAssertEqual(store.rank, afterSecond)
    }

    func testANewSeasonOnTheServerRollsOverAndKeepsItsHistory() throws {
        let store = PlayerRecordStore(directory: directory(), now: { self.october })
        for _ in 0..<3 { play(store, .win) }
        store.adopt(try standing(season: "2026-11", points: 4,
                                 history: #"[{"season": "2026-10", "finalPoints": 20, "peakPoints": 22, "wins": 9, "losses": 4}]"#))
        XCTAssertEqual(store.rank.season, "2026-11")
        XCTAssertEqual(store.rank.position, RankPosition(points: 4))
        XCTAssertEqual(store.rank.history.first?.season, "2026-10")
        XCTAssertEqual(store.rank.history.first?.final, RankPosition(points: 20))
        XCTAssertEqual(store.rank.history.first?.wins, 9)
        // An older season from the server never replaces a newer one on the phone.
        let current = store.rank
        store.adopt(try standing(season: "2026-09", points: 60))
        XCTAssertEqual(store.rank, current)
    }

    func testRankedAIResultsWaitWithTheirTicketAcrossARelaunch() {
        let folder = directory()
        let store = PlayerRecordStore(directory: folder, now: { self.october })
        let ticket = UUID()
        store.beginRankedAIGame(ticket: ticket)
        play(store, .win)
        XCTAssertNil(store.rankedTicket)
        XCTAssertEqual(store.pendingRankedResults.map(\.ticket), [ticket])
        XCTAssertEqual(store.pendingRankedResults.first?.outcome, .win)
        // A game against a person never uses an AI ticket.
        store.beginRankedAIGame(ticket: UUID())
        play(store, .loss, human: true)
        XCTAssertEqual(store.pendingRankedResults.count, 1)
        XCTAssertNotNil(store.rankedTicket)

        let again = PlayerRecordStore(directory: folder, now: { self.october })
        XCTAssertEqual(again.pendingRankedResults.map(\.ticket), [ticket])
        XCTAssertEqual(again.rankedTicket, store.rankedTicket)
        again.resolvePendingRankedResult(ticket)
        XCTAssertTrue(again.pendingRankedResults.isEmpty)
        XCTAssertTrue(PlayerRecordStore(directory: folder, now: { self.october }).pendingRankedResults.isEmpty)
    }

    /// Bronze ranked faces only the three softest precons (C3's round-robin); an empty match falls back to every precon.
    func testBronzePicksOnlyTheGentlestPrecons() {
        let precons = AIDeckPool.all.filter(\.isPrecon)
        XCTAssertEqual(precons.count, 5)
        for roll in 0..<10 {
            let pick = AIDeckPool.pick(bracket: 2, avoidingCommander: nil, recent: [], preconsOnly: true,
                                       onlyPrecons: AIDeckPool.gentlestPrecons, in: precons) { _ in roll }
            XCTAssertTrue(AIDeckPool.gentlestPrecons.contains(pick?.id ?? ""), "\(String(describing: pick?.id))")
        }
        let fallback = AIDeckPool.pick(bracket: 2, avoidingCommander: nil, recent: [], preconsOnly: true,
                                       onlyPrecons: ["no-such-precon"], in: precons) { _ in 4 }
        XCTAssertNotNil(fallback)
    }
}
