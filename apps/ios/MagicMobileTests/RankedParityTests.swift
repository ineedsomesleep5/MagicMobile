import XCTest
@testable import MagicMobile

/// ranked-cases.json: the ladder, seasons, Commander brackets and AI deck pools.
/// RankedParityTest.kt checks Android against the same file.
final class RankedParityTests: XCTestCase {
    private var root: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../android/core/src/test/resources/parity/ranked-cases.json").standardizedFileURL
        root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func rows(_ key: String) throws -> [[String: Any]] { try XCTUnwrap(root[key] as? [[String: Any]]) }

    private func position(_ value: Any?) throws -> RankPosition {
        let row = try XCTUnwrap(value as? [String: Any])
        let tier = try XCTUnwrap(RankTier.allCases.first { String(describing: $0) == row["tier"] as? String })
        return RankPosition(tier: tier, division: try XCTUnwrap(row["division"] as? Int), pips: try XCTUnwrap(row["pips"] as? Int))
    }

    func testLadder() throws {
        XCTAssertEqual(root["pipsPerDivision"] as? Int, RankPosition.pipsPerDivision)
        for item in try rows("ladder") {
            let name = item["name"] as? String ?? ""
            var state = RankState.fresh(season: "2026-10")
            state.position = try position(item["before"])
            state.peak = state.position
            state.winStreak = try XCTUnwrap(item["streak"] as? Int)
            let outcome = try XCTUnwrap(RankOutcome(rawValue: try XCTUnwrap(item["outcome"] as? String)))
            let result = RankLadder.apply(outcome, to: state, deckBracket: try XCTUnwrap(item["deckBracket"] as? Int))
            XCTAssertEqual(result.state.position, try position(item["after"]), name)
            XCTAssertEqual(result.state.winStreak, item["streakAfter"] as? Int, name)
            XCTAssertEqual(result.change.pipDelta, item["delta"] as? Int, name)
            XCTAssertEqual(result.change.bonuses.map(\.rawValue), item["bonuses"] as? [String], name)
            XCTAssertEqual(result.change.kind.rawValue, item["kind"] as? String, name)
        }
    }

    func testPositionsAndTiers() throws {
        for item in try rows("positions") {
            let position = RankPosition(points: try XCTUnwrap(item["points"] as? Int))
            XCTAssertEqual(position.step, item["step"] as? Int, "\(item)")
            XCTAssertEqual(position.title, item["title"] as? String)
            XCTAssertEqual(position.pips, item["pips"] as? Int)
            XCTAssertEqual(position.opponentBracket, item["opponentBracket"] as? Int)
            XCTAssertEqual(position.points, item["points"] as? Int)
        }
        for item in try rows("tiers") {
            let tier = try XCTUnwrap(RankTier.allCases.first { String(describing: $0) == item["tier"] as? String })
            let range = try XCTUnwrap(item["opponentBrackets"] as? [Int])
            XCTAssertEqual([tier.opponentBrackets.lowerBound, tier.opponentBrackets.upperBound], range)
            XCTAssertEqual(tier.maxDeckBracket, item["maxDeckBracket"] as? Int)
            XCTAssertEqual(tier.aiSkill, item["aiSkill"] as? Int)
        }
    }

    func testSeasons() throws {
        for item in try rows("seasons") {
            let date = Date(timeIntervalSince1970: Double(try XCTUnwrap(item["millis"] as? Int)) / 1000)
            XCTAssertEqual(RankLadder.season(for: date), item["season"] as? String)
        }
        for item in try rows("seasonEnds") {
            let end = try XCTUnwrap(RankLadder.seasonEnd(try XCTUnwrap(item["season"] as? String)))
            XCTAssertEqual(Int(end.timeIntervalSince1970 * 1000), item["millis"] as? Int)
        }
        for item in try rows("rollover") {
            let name = item["name"] as? String ?? ""
            var state = RankState.fresh(season: try XCTUnwrap(item["season"] as? String))
            state.position = try position(item["position"])
            state.peak = try position(item["peak"])
            state.wins = try XCTUnwrap(item["wins"] as? Int)
            state.losses = try XCTUnwrap(item["losses"] as? Int)
            let next = RankLadder.rollover(state, to: try XCTUnwrap(item["to"] as? String))
            XCTAssertEqual(next.position, try position(item["after"]), name)
            let history = try XCTUnwrap(item["history"] as? [[String: Any]])
            XCTAssertEqual(next.history.count, history.count, name)
            for (record, expected) in zip(next.history, history) {
                XCTAssertEqual(record.season, expected["season"] as? String, name)
                XCTAssertEqual(record.final, try position(expected["final"]), name)
                XCTAssertEqual(record.peak, try position(expected["peak"]), name)
                XCTAssertEqual(record.wins, expected["wins"] as? Int, name)
                XCTAssertEqual(record.losses, expected["losses"] as? Int, name)
            }
            if item["to"] as? String != item["season"] as? String {
                XCTAssertEqual(next.wins + next.losses, 0, name)
                XCTAssertEqual(next.peak, next.position, name)
            }
        }
    }

    func testBrackets() throws {
        let rules = BracketRules.bundled
        XCTAssertEqual(rules.gameChangers.count, 53, "the February 2026 list")
        for item in try rows("brackets") {
            let name = item["name"] as? String ?? ""
            let report = rules.evaluate(cardNames: try XCTUnwrap(item["cards"] as? [String]))
            XCTAssertEqual(report.minimum.rawValue, item["minimum"] as? Int, name)
            XCTAssertEqual(report.gameChangers, item["gameChangers"] as? [String], name)
            XCTAssertEqual(report.massLandDenial, item["massLandDenial"] as? [String], name)
            XCTAssertEqual(report.extraTurns, item["extraTurns"] as? [String], name)
            XCTAssertEqual(report.combos.count, item["combos"] as? Int, name)
            XCTAssertEqual(report.earlyCombos.count, item["earlyCombos"] as? Int, name)
        }
        for item in try rows("effective") {
            let minimum = try XCTUnwrap(CommanderBracket(rawValue: try XCTUnwrap(item["minimum"] as? Int)))
            let declared = (item["declared"] as? Int).flatMap(CommanderBracket.init(rawValue:))
            XCTAssertEqual(DeckBracketPreference.effective(minimum: minimum, declared: declared).rawValue, item["effective"] as? Int, "\(item)")
        }
        for item in try rows("choices") {
            let minimum = try XCTUnwrap(CommanderBracket(rawValue: try XCTUnwrap(item["minimum"] as? Int)))
            XCTAssertEqual(DeckBracketPreference.choices(minimum: minimum).map(\.rawValue), item["choices"] as? [Int])
        }
    }

    func testPoolsAndColors() throws {
        for item in try rows("pools") {
            let pool = AIDeckPool.pool(for: try XCTUnwrap(item["bracket"] as? Int))
            XCTAssertEqual(pool.count, item["count"] as? Int, "\(item)")
            XCTAssertEqual(Set(pool.map(\.bracket.rawValue)), [try XCTUnwrap(item["poolBracket"] as? Int)], "\(item)")
        }
        for item in try rows("colors") {
            XCTAssertEqual(PlayerStats.colors(manaCost: item["manaCost"] as? String), item["colors"] as? [String], "\(item)")
        }
    }
}

/// The AI decks themselves: playable lists at their brackets, through the same resolver games use.
final class AIDeckPoolTests: XCTestCase {
    func testEveryAIDeckIsALegalHundredAtItsBracket() throws {
        let resolver = try OnDeviceDeckResolver.bundled()
        XCTAssertEqual(AIDeckPool.bracketDecks.count, 21)
        for deck in AIDeckPool.all {
            XCTAssertEqual(deck.deckList.totalCards, 100, deck.id)
            XCTAssertEqual(deck.deckList.commander?.cardName, deck.commander, deck.id)
            // Singleton apart from basic lands.
            let basics: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]
            let repeated = deck.deckList.entries.filter { $0.quantity > 1 && !basics.contains($0.cardName) }
            XCTAssertTrue(repeated.isEmpty, "\(deck.id): \(repeated.map(\.cardName))")
            XCTAssertNoThrow(try resolver.resolve(deck.deckList), deck.id)
            let computed = BracketRules.bundled.evaluate(deck.deckList).minimum
            XCTAssertLessThanOrEqual(computed.rawValue, max(2, deck.bracket.rawValue), "\(deck.id) lists above its bracket")
        }
        XCTAssertEqual(Set(AIDeckPool.all.map(\.id)).count, AIDeckPool.all.count, "unique IDs")
    }

    func testPickAvoidsYourCommanderAndRecentDecks() throws {
        let pool = AIDeckPool.pool(for: 3)
        let krenko = try XCTUnwrap(pool.first { $0.commander == "Krenko, Mob Boss" })
        for roll in 0..<pool.count {
            let pick = try XCTUnwrap(AIDeckPool.pick(bracket: 3, avoidingCommander: "Krenko, Mob Boss", recent: [], roll: { _ in roll }))
            XCTAssertNotEqual(pick.commander, krenko.commander)
        }
        let recent = pool.dropFirst().map(\.id)
        let fresh = try XCTUnwrap(AIDeckPool.pick(bracket: 3, avoidingCommander: nil, recent: recent, roll: { _ in 0 }))
        XCTAssertEqual(fresh.id, pool[0].id, "the one deck not faced lately")
        // Everything faced lately: still a deck.
        XCTAssertNotNil(AIDeckPool.pick(bracket: 3, avoidingCommander: nil, recent: pool.map(\.id), roll: { _ in 0 }))
    }
}

@MainActor
final class PlayerRecordStoreTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PlayerRecordTests-\(UUID().uuidString)")
    }

    private func play(_ store: PlayerRecordStore, _ mode: PlayMode, _ outcome: RankOutcome, deckBracket: Int = 2,
                      colors: [String] = ["R"], commander: String = "Krenko, Mob Boss", human: Bool = false) -> RankChange? {
        store.record(mode: mode, outcome: outcome, opponents: [.init(name: "Foe", commander: "Edgar Markov", isAI: !human)],
                     opponentBracket: 2, aiSkill: 3, deckID: "precon:x", deckName: "Goblins", commander: commander,
                     colors: colors, deckBracket: deckBracket, turns: 9, aiDeckID: "ai-edgar-markov-core")
    }

    func testRankedMovesTheLadderAndQuickDoesNot() {
        var now = Date(timeIntervalSince1970: 1_791_000_000) // October 2026
        let store = PlayerRecordStore(directory: directory(), now: { now })
        XCTAssertNil(play(store, .quick, .win))
        XCTAssertEqual(store.rank.position, .start)
        let change = play(store, .ranked, .win)
        XCTAssertEqual(change?.after, RankPosition(tier: .bronze, division: 4, pips: 1))
        XCTAssertEqual(store.rank.wins, 1)
        XCTAssertEqual(store.matches.count, 2)
        XCTAssertEqual(store.recentAIDecks, ["ai-edgar-markov-core"])
        // A new month: the season rolls over before the next result counts.
        now = Date(timeIntervalSince1970: 1_797_292_800) // December 2026
        _ = play(store, .ranked, .loss)
        XCTAssertEqual(store.rank.season, "2026-12")
        XCTAssertEqual(store.rank.history.first?.season, "2026-10")
        XCTAssertEqual(store.rank.losses, 1)
        XCTAssertEqual(store.rank.wins, 0)
    }

    func testRecordSurvivesRelaunch() {
        let folder = directory()
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let store = PlayerRecordStore(directory: folder, now: { now })
        for _ in 0..<5 { _ = play(store, .ranked, .win) }
        store.title = .firstWin
        store.favoriteCommander = "Krenko, Mob Boss"
        let again = PlayerRecordStore(directory: folder, now: { now })
        XCTAssertEqual(again.rank, store.rank)
        XCTAssertEqual(again.matches.count, 5)
        XCTAssertEqual(again.title, .firstWin)
        XCTAssertEqual(again.favoriteCommander, "Krenko, Mob Boss")
    }

    func testStatsAndAchievements() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let store = PlayerRecordStore(directory: directory(), now: { now })
        for color in ["W", "U", "B", "R", "G"] { _ = play(store, .quick, .win, colors: [color], commander: "C-\(color)") }
        _ = play(store, .ranked, .loss)
        _ = play(store, .ranked, .win, deckBracket: 1, human: true) // Bronze opponents start at bracket 1: no underdog
        let stats = store.stats
        XCTAssertEqual(stats.games, 7)
        XCTAssertEqual(stats.wins, 6)
        XCTAssertEqual(stats.bestStreak, 5)
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.colors.map(\.id), ["W", "U", "B", "R", "G"])
        XCTAssertEqual(stats.averageTurns, 9)
        let unlocked = store.achievements
        XCTAssertTrue(unlocked.isSuperset(of: [.firstWin, .firstRankedWin, .streak5, .prismatic, .humanWin]))
        XCTAssertFalse(unlocked.contains(.giantSlayer))
        XCTAssertFalse(unlocked.contains(.silver))
    }
}

@MainActor
final class RankedMatchmakerTests: XCTestCase {
    private final class FakeQueue: RankedQueueService {
        var polls: [RankedTicket] = []
        var cancelResult = RankedTicket(ticket: UUID(), status: "cancelled", matchId: nil, role: nil, tableCode: nil, opponent: nil, opponentStep: nil)
        var enqueueResult: RankedTicket
        var fail = false
        var reports: [RankOutcome] = []
        init(enqueue: RankedTicket) { enqueueResult = enqueue }
        func enqueue(protocol: String, rankStep: Int, deckBracket: Int) async throws -> RankedTicket {
            if fail { throw SupabaseLite.Failure(code: "offline") }
            return enqueueResult
        }
        func poll(_ ticket: UUID) async throws -> RankedTicket { polls.isEmpty ? enqueueResult : polls.removeFirst() }
        func cancel(_ ticket: UUID) async throws -> RankedTicket { cancelResult }
        func setTable(match: UUID, code: String) async throws {}
        func report(match: UUID, outcome: RankOutcome) async throws { reports.append(outcome) }
    }

    private let ticket = UUID(), match = UUID()
    private func waiting() -> RankedTicket { RankedTicket(ticket: ticket, status: "waiting", matchId: nil, role: nil, tableCode: nil, opponent: nil, opponentStep: nil) }
    private func matched(_ role: String, code: String? = nil) -> RankedTicket {
        RankedTicket(ticket: ticket, status: "matched", matchId: match, role: role, tableCode: code, opponent: "RankTwo", opponentStep: 8)
    }

    func testNoProfileMeansAnAIGame() async {
        let maker = RankedMatchmaker(service: nil, sleep: { _ in })
        let outcome = await maker.search(protocol: "p", rankStep: 0, deckBracket: 2)
        XCTAssertEqual(outcome, .ai)
    }

    func testHostIsMatchedAtOnce() async {
        let queue = FakeQueue(enqueue: matched("host"))
        let maker = RankedMatchmaker(service: queue, sleep: { _ in })
        let outcome = await maker.search(protocol: "p", rankStep: 8, deckBracket: 2)
        XCTAssertEqual(outcome, .human(matched("host")))
        XCTAssertEqual(maker.phase, .matched(matched("host")))
    }

    func testGuestWaitsForTheTableCode() async {
        let queue = FakeQueue(enqueue: waiting())
        queue.polls = [waiting(), matched("guest"), matched("guest", code: "ABCDEF")]
        let maker = RankedMatchmaker(service: queue, sleep: { _ in })
        let outcome = await maker.search(protocol: "p", rankStep: 8, deckBracket: 2)
        XCTAssertEqual(outcome, .human(matched("guest", code: "ABCDEF")))
    }

    func testPlayAINowAndServerTroubleBothGiveAnAIGame() async {
        let queue = FakeQueue(enqueue: waiting())
        let late = RankedMatchmaker(service: queue)
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(50)); late.skipToAI() }
        let outcome = await late.search(protocol: "p", rankStep: 8, deckBracket: 2)
        XCTAssertEqual(outcome, .ai)
        XCTAssertEqual(late.phase, .idle)
        queue.fail = true
        let failing = RankedMatchmaker(service: queue, sleep: { _ in })
        let failed = await failing.search(protocol: "p", rankStep: 8, deckBracket: 2)
        XCTAssertEqual(failed, .ai)
    }

    func testCancelReturnsToTheLobbyButALateMatchStillPlays() async {
        let queue = FakeQueue(enqueue: waiting())
        let cancelling = RankedMatchmaker(service: queue)
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(50)); cancelling.cancel() }
        let cancelled = await cancelling.search(protocol: "p", rankStep: 8, deckBracket: 2)
        XCTAssertEqual(cancelled, .cancelled)
        // Timed out into an AI game, but the server matched us meanwhile: the person wins.
        queue.cancelResult = matched("guest", code: "ABCDEF")
        let late = RankedMatchmaker(service: queue)
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(50)); late.skipToAI() }
        let outcome = await late.search(protocol: "p", rankStep: 8, deckBracket: 2)
        XCTAssertEqual(outcome, .human(matched("guest", code: "ABCDEF")))
    }
}

@MainActor
final class FriendChallengeTests: XCTestCase {
    private final class FakeChallenges: FriendChallengeService {
        var statuses: [FriendChallenge] = []
        var sent: FriendChallenge
        var cancelResult: FriendChallenge
        var incomingList: [FriendChallenge] = []
        var declined: [UUID] = []
        var fail: String?
        init(sent: FriendChallenge) { self.sent = sent; cancelResult = .closed(sent.id) }
        func send(to username: String, mode: PlayMode, protocol: String, rankStep: Int, tableCode: String) async throws -> FriendChallenge {
            if let fail { throw SupabaseLite.Failure(code: fail) }
            return sent
        }
        func incoming() async throws -> [FriendChallenge] { incomingList }
        func status(_ id: UUID) async throws -> FriendChallenge { statuses.isEmpty ? sent : statuses.removeFirst() }
        func accept(_ id: UUID, protocol: String, rankStep: Int) async throws -> FriendChallenge { FriendChallengeTests.challenge("accepted", code: "ABCDEF") }
        func decline(_ id: UUID) async throws { declined.append(id) }
        func cancel(_ id: UUID) async throws -> FriendChallenge { cancelResult }
    }

    private nonisolated static let id = UUID()
    private nonisolated static func challenge(_ status: String, mode: String = "ranked", code: String? = nil, match: UUID? = nil) -> FriendChallenge {
        FriendChallenge(id: id, mode: mode, status: status, role: "challenger", challenger: "DuelOne", challenged: "DuelTwo",
                        challengerStep: 9, protocol: "p", tableCode: code, matchId: match)
    }
    private func challenge(_ status: String, code: String? = nil, match: UUID? = nil) -> FriendChallenge {
        Self.challenge(status, code: code, match: match)
    }

    func testRankedNeedsTheSameTier() {
        XCTAssertTrue(FriendChallengeRules.mayRank(myStep: 8, friendStep: 11))     // Gold IV with Gold I
        XCTAssertFalse(FriendChallengeRules.mayRank(myStep: 11, friendStep: 12))   // Gold I with Platinum IV
        XCTAssertTrue(FriendChallengeRules.mayRank(myStep: 2, friendStep: nil))    // no standing reads as Bronze
        XCTAssertFalse(FriendChallengeRules.mayRank(myStep: 4, friendStep: nil))
        XCTAssertTrue(FriendChallengeRules.mayRank(myStep: 20, friendStep: 20))    // Mythic with Mythic
        XCTAssertFalse(FriendChallengeRules.mayRank(myStep: 19, friendStep: 20))
    }

    func testAcceptedChallengeHandsBackTheMatch() async {
        let match = UUID()
        let fake = FakeChallenges(sent: challenge("pending"))
        fake.statuses = [challenge("pending"), challenge("accepted", code: "ABCDEF", match: match)]
        let coordinator = FriendChallengeCoordinator(service: fake, sleep: { _ in })
        let answer = await coordinator.challenge("DuelTwo", mode: .ranked, protocol: "p", rankStep: 9, tableCode: "ABCDEF")
        XCTAssertEqual(answer, .accepted(challenge("accepted", code: "ABCDEF", match: match)))
        XCTAssertFalse(coordinator.isWaiting)
    }

    func testDeclinedAndFailedChallenges() async {
        let fake = FakeChallenges(sent: challenge("pending"))
        fake.statuses = [challenge("declined")]
        let coordinator = FriendChallengeCoordinator(service: fake, sleep: { _ in })
        let declined = await coordinator.challenge("DuelTwo", mode: .quick, protocol: "p", rankStep: 9, tableCode: "ABCDEF")
        XCTAssertEqual(declined, .declined)
        fake.fail = "rank_mismatch"
        let failed = await coordinator.challenge("DuelTwo", mode: .ranked, protocol: "p", rankStep: 4, tableCode: "ABCDEF")
        XCTAssertEqual(failed, .failed("rank_mismatch"))
        XCTAssertEqual(FriendChallengeRules.message(for: "rank_mismatch"), "Ranked challenges need the same tier.")
    }

    func testWithdrawingKeepsAnAcceptThatArrivedFirst() async {
        final class Box { weak var coordinator: FriendChallengeCoordinator? }
        let fake = FakeChallenges(sent: challenge("pending"))
        let box = Box()
        // The first wait withdraws the challenge.
        let coordinator = FriendChallengeCoordinator(service: fake, sleep: { _ in await MainActor.run { box.coordinator?.cancelOutgoing() } })
        box.coordinator = coordinator
        let cancelled = await coordinator.challenge("DuelTwo", mode: .quick, protocol: "p", rankStep: 9, tableCode: "ABCDEF")
        XCTAssertEqual(cancelled, .cancelled)
        fake.cancelResult = challenge("accepted", code: "ABCDEF")
        let accepted = await coordinator.challenge("DuelTwo", mode: .quick, protocol: "p", rankStep: 9, tableCode: "ABCDEF")
        XCTAssertEqual(accepted, .accepted(challenge("accepted", code: "ABCDEF")))
    }

    func testIncomingSkipsAnsweredChallenges() async {
        let fake = FakeChallenges(sent: challenge("pending"))
        fake.incomingList = [Self.challenge("pending", mode: "quick")]
        let coordinator = FriendChallengeCoordinator(service: fake, sleep: { _ in })
        await coordinator.refreshIncoming()
        XCTAssertEqual(coordinator.incoming.count, 1)
        await coordinator.decline(coordinator.incoming[0])
        XCTAssertEqual(fake.declined, [Self.id])
        await coordinator.refreshIncoming()
        XCTAssertTrue(coordinator.incoming.isEmpty, "A declined challenge never comes back while the server catches up")
    }
}
