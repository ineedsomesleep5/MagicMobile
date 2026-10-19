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

    /// Phase 5: a seeded ticket's result goes with the game record kept on the phone, and survives a relaunch.
    func testSeededTicketKeepsTheGameRecordWithTheResult() throws {
        let folder = directory()
        let store = PlayerRecordStore(directory: folder, now: { self.october })
        let ticket = UUID()
        store.beginRankedAIGame(ticket: ticket, seeded: true)
        let file = try XCTUnwrap(store.keepGameRecord(Data(#"{"format":"magicmobile-game-record"}"#.utf8)))
        _ = store.record(mode: .ranked, outcome: .win, opponents: [.init(name: "Foe", commander: nil, isAI: true)],
                         opponentBracket: 2, aiSkill: 1, deckID: "precon:x", deckName: "Goblins", commander: nil,
                         colors: ["R"], deckBracket: 2, turns: 9, gameRecordFile: file)
        let reloaded = PlayerRecordStore(directory: folder, now: { self.october })
        let pending = try XCTUnwrap(reloaded.pendingRankedResults.first)
        XCTAssertEqual(pending.ticket, ticket)
        XCTAssertEqual(pending.seeded, true)
        XCTAssertEqual(pending.recordFile, file)
        XCTAssertEqual(reloaded.gameRecord(named: file), Data(#"{"format":"magicmobile-game-record"}"#.utf8))
        XCTAssertNil(reloaded.gameRecord(named: "../player-record.json"))
        // The next ticket starts unseeded until the server says otherwise.
        XCTAssertNil(reloaded.rankedTicket)
        reloaded.beginRankedAIGame(ticket: UUID())
        play(reloaded, .loss)
        XCTAssertEqual(reloaded.pendingRankedResults.last?.seeded, false)
    }

    func testKeepsTheLastFiftyGameRecordsNewestFirst() throws {
        var clock = october
        let store = PlayerRecordStore(directory: directory(), now: { clock })
        var names: [String] = []
        for game in 0..<(PlayerRecordStore.maxGameRecords + 3) {
            clock = october.addingTimeInterval(Double(game))
            names.append(try XCTUnwrap(store.keepGameRecord(Data("{\"game\":\(game)}".utf8))))
        }
        let kept = store.gameRecordFiles().map(\.lastPathComponent)
        XCTAssertEqual(kept.count, PlayerRecordStore.maxGameRecords)
        XCTAssertEqual(kept.first, names.last)
        XCTAssertFalse(kept.contains(names[0]))
    }

    func testParsesTheSeededTicket() {
        let id = UUID()
        XCTAssertEqual(PlayerAccount.rankedAITicket(Data(#"{"id":"\#(id.uuidString)","seed":"-4123456789012345678","aiSkill":1}"#.utf8)),
                       PlayerAccount.RankedAITicket(id: id, seed: -4_123_456_789_012_345_678))
        XCTAssertNil(PlayerAccount.rankedAITicket(Data(#"{"id":"\#(id.uuidString)","seed":4.5}"#.utf8)))
        XCTAssertNil(PlayerAccount.rankedAITicket(Data(#""\#(id.uuidString)""#.utf8)))
    }

    /// mm_ranked_leaderboard's reply (supabase/migrations/20261016180000_ranked_leaderboard.sql).
    func testLeaderboardParsesAndPinsYourRowOffTheList() throws {
        let json = #"{"season":"2026-10","scope":"everyone","total":3,"online":1,"entries":[{"position":1,"username":"Dahlia_Rose","title":"Mythic Legend","commander":"Ayula, Queen Among Bears","points":87,"step":20,"pips":7,"peakStep":20,"wins":28,"losses":11,"online":true,"you":false},{"position":2,"username":"ManaFiend","title":null,"commander":null,"points":71,"step":17,"pips":3,"peakStep":17,"wins":25,"losses":10,"online":false,"you":false}],"me":{"position":3,"username":"CalebM","title":"Contender","commander":"Edgar Markov","points":42,"step":10,"pips":2,"peakStep":11,"wins":14,"losses":9,"online":true,"you":true}}"#
        let board = try RankedLeaderboard.parse(Data(json.utf8))
        XCTAssertEqual(board.entries.map(\.username), ["Dahlia_Rose", "ManaFiend"])
        XCTAssertEqual(board.entries[0].rank.tier, .mythic)
        XCTAssertNil(board.entries[1].title)
        XCTAssertEqual(board.pinnedMe?.username, "CalebM", "your row is pinned when it's not among the shown entries")
        let empty = try RankedLeaderboard.parse(Data(#"{"season":"2026-10","scope":"friends","total":0,"online":0,"entries":[],"me":null}"#.utf8))
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertNil(empty.pinnedMe)
    }

    /// The fixture leaderboard follows the server's visibility rules.
    func testFixtureLeaderboardHidesPrivateAndNonFriendRows() {
        let everyone = SocialFixtures.leaderboard(.everyone, own: "CalebM")
        let names = everyone.entries.map(\.username)
        XCTAssertFalse(names.contains("DaPrivate"))
        XCTAssertFalse(names.contains("Dagger99"), "friends-only and not a friend")
        XCTAssertEqual(names.first, "Dahlia_Rose")
        XCTAssertEqual(everyone.entries.map(\.position), Array(1...everyone.entries.count))
        XCTAssertEqual(everyone.me?.username, "CalebM")
        let top = SocialFixtures.leaderboard(.everyone, own: "CalebM", limit: 3)
        XCTAssertEqual(top.entries.count, 3, "the limit caps the rows, like the server")
        XCTAssertEqual(top.pinnedMe?.username, "CalebM")
        let friends = SocialFixtures.leaderboard(.friends, own: "CalebM")
        XCTAssertEqual(Set(friends.entries.map(\.username)), ["Aria_Blade", "ManaFiend", "DarkMoonDan", "CalebM"])
    }

    /// Ranked always rolls for the first turn; the other modes keep the player's "Who goes first?" choice.
    /// RankedParityTest.kt checks Android the same way.
    func testRankedAlwaysRollsForFirstTurn() {
        for preference in ["choose", "roll"] {
            XCTAssertEqual(PlayMode.ranked.startingPlayerMode(preference: preference), "roll")
            XCTAssertEqual(PlayMode.quick.startingPlayerMode(preference: preference), preference)
            XCTAssertEqual(PlayMode.casual.startingPlayerMode(preference: preference), preference)
        }
    }
}
