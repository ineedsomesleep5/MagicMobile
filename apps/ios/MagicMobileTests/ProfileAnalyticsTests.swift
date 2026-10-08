import XCTest
@testable import MagicMobile

/// profile-cases.json: the numbers behind a profile's pictures, a public profile as the server sends it, search results and
/// what the search field sends. ProfileAnalyticsTest.kt checks Android against the same file.
final class ProfileAnalyticsTests: XCTestCase {
    private var root: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../android/core/src/test/resources/parity/profile-cases.json").standardizedFileURL
        root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(PublicProfile.timestamp(text.hasSuffix("Z") ? String(text.dropLast()) + "+00:00" : text), text)
    }

    func testSummaries() throws {
        for item in try XCTUnwrap(root["summaries"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? ""
            let now = try date(try XCTUnwrap(item["now"] as? String))
            var points: [ProfileSummary.RankPoint] = []
            let games: [ProfileGame] = try XCTUnwrap(item["games"] as? [[String: Any]]).map { row in
                let at = try date(try XCTUnwrap(row["at"] as? String))
                if let after = row["rankAfter"] as? Int { points.insert(.init(date: at, points: after), at: 0) }
                return ProfileGame(id: try XCTUnwrap(row["id"] as? String), date: at,
                                   mode: try XCTUnwrap(PlayMode(rawValue: try XCTUnwrap(row["mode"] as? String))),
                                   outcome: try XCTUnwrap(RankOutcome(rawValue: try XCTUnwrap(row["result"] as? String))), deckName: "",
                                   commanders: row["commanders"] as? [String] ?? [], colors: row["colors"] as? [String] ?? [], opponents: [],
                                   turns: (row["turns"] as? Int).flatMap { $0 > 0 ? $0 : nil })
            }
            let expect = try XCTUnwrap(item["expect"] as? [String: Any])
            let summary = ProfileSummary(games: games, now: now, rankPoints: points)
            XCTAssertEqual(summary.games, expect["games"] as? Int, name)
            XCTAssertEqual(summary.wins, expect["wins"] as? Int, name)
            XCTAssertEqual(summary.losses, expect["losses"] as? Int, name)
            XCTAssertEqual(summary.draws, expect["draws"] as? Int, name)
            XCTAssertEqual(summary.currentStreak, expect["currentStreak"] as? Int, name)
            XCTAssertEqual(summary.bestStreak, expect["bestStreak"] as? Int, name)
            if let average = expect["averageTurns"] as? Double {
                XCTAssertEqual(try XCTUnwrap(summary.averageTurns), average, accuracy: 1e-9, name)
            } else {
                XCTAssertNil(summary.averageTurns, name)
            }
            let weeks = try XCTUnwrap(expect["weeks"] as? [[String: Any]])
            XCTAssertEqual(summary.weeks.count, ProfileSummary.weekCount, name)
            XCTAssertEqual(summary.weeks.map { PublicProfile.dayText($0.start) }, weeks.compactMap { $0["start"] as? String }, name)
            XCTAssertEqual(summary.weeks.map(\.games), weeks.compactMap { $0["games"] as? Int }, name)
            XCTAssertEqual(summary.weeks.map(\.wins), weeks.compactMap { $0["wins"] as? Int }, name)
            let shares: (String) -> [[String: Any]] = { (expect[$0] as? [[String: Any]]) ?? [] }
            XCTAssertEqual(summary.commanders.map(\.id), shares("commanders").compactMap { $0["id"] as? String }, name)
            XCTAssertEqual(summary.commanders.map(\.games), shares("commanders").compactMap { $0["games"] as? Int }, name)
            XCTAssertEqual(summary.commanders.map(\.wins), shares("commanders").compactMap { $0["wins"] as? Int }, name)
            XCTAssertEqual(summary.colors.map(\.id), shares("colors").compactMap { $0["id"] as? String }, name)
            XCTAssertEqual(summary.colors.map(\.games), shares("colors").compactMap { $0["games"] as? Int }, name)
            XCTAssertEqual(summary.colors.map(\.wins), shares("colors").compactMap { $0["wins"] as? Int }, name)
            XCTAssertEqual(summary.rankPoints.map(\.points), expect["rankPoints"] as? [Int], name)
        }
    }

    func testSummaryFromMatchRecordsFollowsTheRecordsRankChanges() throws {
        let now = try date("2026-10-07T12:00:00Z")
        func record(_ at: String, _ outcome: RankOutcome, after: Int?) throws -> MatchRecord {
            let change = after.map { RankChange(outcome: outcome, before: RankPosition(points: max(0, $0 - 1)), after: RankPosition(points: $0), bonuses: []) }
            return MatchRecord(date: try date(at), mode: after == nil ? .quick : .ranked, opponents: [], opponentBracket: nil, aiSkill: nil,
                               deckID: "d", deckName: "Deck", commander: "Krenko, Mob Boss", colors: ["R"], deckBracket: 2, outcome: outcome,
                               turns: 7, rankChange: change, season: nil)
        }
        let summary = ProfileSummary(matches: [try record("2026-10-06T10:00:00Z", .win, after: 30), try record("2026-10-05T10:00:00Z", .loss, after: 29),
                                               try record("2026-10-04T10:00:00Z", .win, after: nil)], now: now)
        XCTAssertEqual(summary.rankPoints.map(\.points), [29, 30])
        XCTAssertEqual(summary.commanders.map(\.id), ["Krenko, Mob Boss"])
        XCTAssertEqual(summary.currentStreak, 1)
        XCTAssertEqual(ProfileGame(try record("2026-10-06T10:00:00Z", .win, after: 30)).rankDelta, 1)
    }

    func testPublicProfiles() throws {
        for item in try XCTUnwrap(root["publicProfiles"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? ""
            let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(item["json"]))
            let profile = try PublicProfile.parse(data)
            let expect = try XCTUnwrap(item["expect"] as? [String: Any])
            XCTAssertEqual(profile.username, expect["username"] as? String, name)
            XCTAssertEqual(profile.restricted, expect["restricted"] as? Bool, name)
            XCTAssertEqual(profile.visibility.rawValue, expect["visibility"] as? String, name)
            XCTAssertEqual(profile.relation, expect["relation"] as? String, name)
            XCTAssertEqual(profile.online, expect["online"] as? Bool, name)
            XCTAssertEqual(profile.isFriend, expect["isFriend"] as? Bool, name)
            XCTAssertEqual(profile.rank?.step, expect["rankStep"] as? Int, name)
            XCTAssertEqual(profile.summary.games, expect["games"] as? Int, name)
            XCTAssertEqual(profile.summary.weeks.count, expect["weeks"] as? Int, name)
            XCTAssertEqual(profile.games.count, expect["gameCount"] as? Int, name)
            if profile.restricted { continue }
            XCTAssertEqual(profile.title, expect["title"] as? String, name)
            XCTAssertEqual(profile.favoriteCommander, expect["favoriteCommander"] as? String, name)
            XCTAssertEqual(profile.rank?.pips, expect["rankPips"] as? Int, name)
            XCTAssertEqual(profile.rank?.peakStep, expect["rankPeak"] as? Int, name)
            XCTAssertEqual(profile.summary.wins, expect["wins"] as? Int, name)
            XCTAssertEqual(profile.summary.losses, expect["losses"] as? Int, name)
            XCTAssertEqual(profile.summary.currentStreak, expect["currentStreak"] as? Int, name)
            XCTAssertEqual(profile.summary.bestStreak, expect["bestStreak"] as? Int, name)
            XCTAssertEqual(try XCTUnwrap(profile.summary.averageTurns), try XCTUnwrap(expect["averageTurns"] as? Double), accuracy: 1e-9, name)
            XCTAssertEqual(profile.summary.weeks.map(\.games), expect["weekGames"] as? [Int], name)
            XCTAssertEqual(profile.summary.rankPoints.map(\.points), expect["rankPoints"] as? [Int], name)
            XCTAssertEqual(profile.summary.colors.map(\.id), expect["colors"] as? [String], name)
            XCTAssertEqual(profile.summary.commanders.map(\.id), expect["commanders"] as? [String], name)
            let first = try XCTUnwrap(profile.games.first)
            XCTAssertEqual(first.opponents.map(\.name), expect["firstGameOpponents"] as? [String], name)
            XCTAssertEqual(first.opponents.map(\.hidden), expect["firstGameHidden"] as? [Bool], name)
            XCTAssertEqual(first.opponents.map { !$0.isAI }, expect["firstGameHuman"] as? [Bool], name)
            XCTAssertEqual(profile.games[1].deckName, expect["secondGameDeck"] as? String, name)
            XCTAssertNil(profile.games[1].turns, name)
            // The server's timestamps carry no time zone name: the date is the instant they say.
            XCTAssertEqual(first.date, try date("2026-10-06T10:00:00Z"), name)
        }
    }

    func testSearchResults() throws {
        let block = try XCTUnwrap(root["searchResults"] as? [String: Any])
        let results = try PlayerSearchResult.parse(try JSONSerialization.data(withJSONObject: try XCTUnwrap(block["json"])))
        let expect = try XCTUnwrap(block["expect"] as? [[String: Any]])
        XCTAssertEqual(results.count, expect.count)
        for (result, wanted) in zip(results, expect) {
            XCTAssertEqual(result.username, wanted["username"] as? String)
            XCTAssertEqual(result.visibility.rawValue, wanted["visibility"] as? String)
            XCTAssertEqual(result.relation, wanted["relation"] as? String)
            XCTAssertEqual(result.online, wanted["online"] as? Bool)
            XCTAssertEqual(result.rankStep, wanted["rankStep"] as? Int)
        }
    }

    func testSearchPrefixes() throws {
        for item in try XCTUnwrap(root["searchPrefixes"] as? [[String: Any]]) {
            let text = try XCTUnwrap(item["text"] as? String)
            XCTAssertEqual(PlayerSearchRules.normalized(text), item["normalized"] as? String, "'\(text)'")
        }
    }
}
