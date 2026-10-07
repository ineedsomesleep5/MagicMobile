import XCTest
@testable import MagicMobile

/// Finished games reach the profile server without ever blocking play: sent once confirmed, retried when they could not be.
@MainActor
final class GameUploaderTests: XCTestCase {
    private func match(_ index: Int) -> MatchRecord {
        MatchRecord(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                    date: Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 3600), mode: .quick, opponents: [], opponentBracket: nil, aiSkill: nil,
                    deckID: "d", deckName: "Deck", commander: "Krenko, Mob Boss", colors: ["R"], deckBracket: 2, outcome: .win, turns: 7,
                    rankChange: nil, season: nil)
    }

    /// Newest first, like the record.
    private func record(_ count: Int) -> [MatchRecord] { (0..<count).map(match).reversed() }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GameUploaderTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testSendsOldestFirstAndRemembersWhatTheServerConfirmed() async {
        let uploader = GameUploader(directory: directory())
        let games = record(3)
        var order: [UUID] = []
        let confirmed = await uploader.flush(matches: games) { game in order.append(game.id); return .sent }
        XCTAssertEqual(confirmed, 3)
        XCTAssertEqual(order, games.reversed().map(\.id))
        XCTAssertTrue(uploader.pending(in: games).isEmpty)
        let again = await uploader.flush(matches: games) { _ in XCTFail("sent twice"); return .sent }
        XCTAssertEqual(again, 0)
    }

    func testStopsAtTheFirstGameThatCannotBeSentAndRetriesItLater() async {
        let uploader = GameUploader(directory: directory())
        let games = record(4)
        var calls = 0
        let first = await uploader.flush(matches: games) { _ in calls += 1; return calls == 3 ? .retryLater : .sent }
        XCTAssertEqual(first, 2, "the first two went, the third is offline, the fourth waits behind it")
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(uploader.pending(in: games).map(\.id), [games[1].id, games[0].id])
        var retried: [UUID] = []
        let second = await uploader.flush(matches: games) { game in retried.append(game.id); return .sent }
        XCTAssertEqual(second, 2)
        XCTAssertEqual(retried, [games[1].id, games[0].id])
    }

    func testAServerWithoutGameRecordingKeepsEverythingPending() async {
        let uploader = GameUploader(directory: directory())
        let games = record(3)
        var calls = 0
        let confirmed = await uploader.flush(matches: games) { _ in calls += 1; return .unavailable }
        XCTAssertEqual(confirmed, 0)
        XCTAssertEqual(calls, 1, "one try is enough to know")
        XCTAssertEqual(uploader.pending(in: games).count, 3)
    }

    func testAGameTheServerRefusesIsNotSentAgain() async {
        let uploader = GameUploader(directory: directory())
        let games = record(2)
        let confirmed = await uploader.flush(matches: games) { game in game.id == games[1].id ? .rejected : .sent }
        XCTAssertEqual(confirmed, 1)
        XCTAssertTrue(uploader.pending(in: games).isEmpty)
    }

    func testOnlyTheNewestGamesAreConsideredAndOnePassIsBounded() async {
        let uploader = GameUploader(directory: directory())
        let games = record(100)
        XCTAssertEqual(uploader.pending(in: games).count, GameUploader.window)
        XCTAssertEqual(uploader.pending(in: games).first?.id, games[GameUploader.window - 1].id)
        var calls = 0
        let confirmed = await uploader.flush(matches: games) { _ in calls += 1; return .sent }
        XCTAssertEqual(confirmed, GameUploader.perPass)
        XCTAssertEqual(calls, GameUploader.perPass)
        XCTAssertEqual(uploader.pending(in: games).count, GameUploader.window - GameUploader.perPass)
    }

    func testWhatWasSentSurvivesARestart() async {
        let folder = directory()
        let games = record(3)
        _ = await GameUploader(directory: folder).flush(matches: games) { _ in .sent }
        let restarted = GameUploader(directory: folder)
        XCTAssertTrue(restarted.pending(in: games).isEmpty)
        XCTAssertEqual(restarted.pending(in: record(4)).count, 1, "a new game after the restart is still pending")
    }

    func testAPassAlreadyRunningMakesAnotherOneANoOp() async {
        let uploader = GameUploader(directory: nil)
        let games = record(2)
        var nested = -1
        _ = await uploader.flush(matches: games) { _ in
            nested = await uploader.flush(matches: games) { _ in XCTFail("ran inside a running pass"); return .sent }
            return .sent
        }
        XCTAssertEqual(nested, 0)
    }
}
