import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Save/resume rules against temporary directories and engine-boundary fakes. No XMage
/// checkpoint is written or restored here; native restore is pending a checkpoint engine build.
final class GameResumeTests: XCTestCase {
    private static let launch = Date(timeIntervalSince1970: 1_790_000_000)
    private static let build = "0.1.1 (21)"
    private static let engine = "xmage/protocol-1/upstream/catalogue"
    /// Today's shipped engines: they save at every decision.
    private static let checkpointCapabilities = MagicMobileOnDevice.JSONValue.object(["engine": .string("xmage"), "saveResume": .bool(true)])
    /// Engines that save only when asked.
    private static let onDemandCapabilities = MagicMobileOnDevice.JSONValue.object([
        "engine": .string("xmage"), "saveResume": .bool(true), "checkpointOnDemand": .bool(true)])
    private static let oldCapabilities = MagicMobileOnDevice.JSONValue.object(["engine": .string("xmage"), "saveResume": .bool(false)])

    private final class Clock {
        var now = GameResumeTests.launch
        var uptime: TimeInterval = 100
    }

    private func makeStore() -> GameResumeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GameResumeTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return GameResumeStore(directory: directory, protectsFiles: false)
    }

    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    private static func seat(_ id: String, _ name: String, _ controller: String) -> MagicMobileOnDevice.JSONValue {
        .object(["seatId": .string(id), "name": .string(name), "controller": .string(controller), "deck": .object(["name": .string(name)])])
    }

    private static let configuration = MagicMobileOnDevice.JSONValue.object(["seats": .array([
        seat("player1", "Caleb", "human"), seat("player2", "AI 1", "ai"), seat("player3", "AI 2", "ai")
    ])])

    private static let setup = GameResumeSetup(configuration: configuration, seatID: "player1", playerName: "Caleb",
                                               deckID: "precon:token-triumph", aiDeckIDs: ["grave-danger", "first-flight"],
                                               aiSkill: 4, startingPlayerMode: "roll")

    private static func record(checkpointAgo: TimeInterval, leftAgo: TimeInterval?, turn: Int64 = 12,
                               appBuild: String = build, engineIdentity: String = engine) -> GameResumeRecord {
        GameResumeRecord(appBuild: appBuild, engineIdentity: engineIdentity,
                         createdAt: millis(launch.addingTimeInterval(-1800)),
                         lastCheckpointAt: millis(launch.addingTimeInterval(-checkpointAgo)),
                         leftAt: leftAgo.map { millis(launch.addingTimeInterval(-$0)) }, turn: turn,
                         playerDeckName: "Token Triumph", opponents: ["AI 1", "AI 2"], setup: setup)
    }

    private func writeGame(_ record: GameResumeRecord, to store: GameResumeStore) throws {
        try store.write(record)
        try Data("engine checkpoint".utf8).write(to: store.checkpointURL)
    }

    private func decide(_ record: GameResumeRecord, appBuild: String = build, engine: String = engine) -> GameResumeLaunchDecision {
        .decide(record: record, sidecarExists: true, checkpointExists: true, nowMillis: Self.millis(Self.launch),
                appBuild: appBuild, engineIdentity: engine)
    }

    @MainActor
    private func coordinator(_ store: GameResumeStore, clock: Clock = Clock()) -> GameResumeCoordinator {
        GameResumeCoordinator(store: store, now: { clock.now }, uptime: { clock.uptime })
    }

    // MARK: Expiry and identity

    func testTenMinuteWindowFromLeavingTheApp() {
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 599)), .resumable(Self.record(checkpointAgo: 900, leftAgo: 599)))
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 600)), .resumable(Self.record(checkpointAgo: 900, leftAgo: 600)))
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 601)), .expired)
    }

    func testAGameOpenWhenTheAppDiedHasEndedEvenWithACheckpoint() {
        // Only a save made when the player left is offered; an older one never is.
        XCTAssertEqual(decide(Self.record(checkpointAgo: 5, leftAgo: nil)), .endedOnClose)
        XCTAssertEqual(decide(Self.record(checkpointAgo: 601, leftAgo: nil)), .endedOnClose)
        XCTAssertEqual(decide(Self.record(checkpointAgo: 5, leftAgo: nil), appBuild: "0.1.1 (22)"), .endedOnClose)
    }

    func testBuildOrEngineMismatchCannotResume() {
        let fresh = Self.record(checkpointAgo: 10, leftAgo: 5)
        XCTAssertEqual(decide(fresh, appBuild: "0.1.1 (22)"), .updated)
        XCTAssertEqual(decide(fresh, engine: "xmage/protocol-1/other/catalogue"), .updated)
        var future = fresh
        future.format = 2
        XCTAssertEqual(decide(future), .updated)
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 600), appBuild: "0.1.1 (22)"), .updated,
                       "Still inside the window: the update is the reason")
        XCTAssertEqual(decide(Self.record(checkpointAgo: 9000, leftAgo: 9000), appBuild: "0.1.1 (22)"), .expired,
                       "Expiry is the reason even when the app was also updated")
        future.leftAt = Self.millis(Self.launch.addingTimeInterval(-601))
        XCTAssertEqual(decide(future), .expired)
    }

    func testEngineIdentityMatchesAndroid() {
        XCTAssertEqual(GameResumeIdentity.engine(BuildIdentity(upstreamCommit: "abc123", catalogueHash: "hash9")),
                       "xmage/protocol-1/abc123/hash9")
    }

    func testGameIsOverWhenItEndsOrThisSeatLeftIt() throws {
        func poll(phase: String, ended: Bool, viewerLeft: Bool) throws -> MatchPoll {
            try MatchPoll(.object([
                "matchId": .string("m"), "viewerId": .string("player1"), "revision": .integer(3), "phase": .string(phase),
                "resyncRequired": .bool(false), "prompt": .null,
                "snapshot": .object(["enginePlayerId": .string("u1"), "outcome": .object(["ended": .bool(ended)]),
                                     "gameView": .object(["players": .array([
                                        .object(["playerId": .string("u1"), "hasLeft": .bool(viewerLeft)]),
                                        .object(["playerId": .string("u2"), "hasLeft": .bool(true)])])])])
            ]))
        }
        XCTAssertTrue(GameResumePolicy.isOver(try poll(phase: "ended", ended: true, viewerLeft: false)))
        XCTAssertTrue(GameResumePolicy.isOver(try poll(phase: "running", ended: true, viewerLeft: false)))
        XCTAssertTrue(GameResumePolicy.isOver(try poll(phase: "running", ended: false, viewerLeft: true)),
                      "Conceded or lost in a pod, now spectating")
        XCTAssertFalse(GameResumePolicy.isOver(try poll(phase: "running", ended: false, viewerLeft: false)),
                       "Another seat leaving is not this seat's end")
    }

    func testMissingFilesDecisions() {
        let now = Self.millis(Self.launch)
        func decide(record: GameResumeRecord?, sidecar: Bool, checkpoint: Bool) -> GameResumeLaunchDecision {
            .decide(record: record, sidecarExists: sidecar, checkpointExists: checkpoint, nowMillis: now,
                    appBuild: Self.build, engineIdentity: Self.engine)
        }
        XCTAssertEqual(decide(record: nil, sidecar: false, checkpoint: false), .nothing)
        XCTAssertEqual(decide(record: nil, sidecar: false, checkpoint: true), .orphanCheckpoint)
        XCTAssertEqual(decide(record: Self.record(checkpointAgo: 5, leftAgo: nil), sidecar: true, checkpoint: false), .endedOnClose)
        XCTAssertEqual(decide(record: nil, sidecar: true, checkpoint: true), .endedOnClose, "Unreadable sidecar")
    }

    // MARK: Sidecar

    func testSidecarRoundTripAndAtomicWrite() throws {
        let store = makeStore()
        let record = Self.record(checkpointAgo: 30, leftAgo: nil)
        try store.write(record)
        XCTAssertEqual(store.readRecord(), record)
        let json = try XCTUnwrap(String(data: Data(contentsOf: store.sidecarURL), encoding: .utf8))
        XCTAssertTrue(json.contains("\"leftAt\":null"), "leftAt is written explicitly as null")
        for key in ["format", "appBuild", "engineIdentity", "createdAt", "lastCheckpointAt", "turn", "playerDeckName", "opponents", "setup"] {
            XCTAssertTrue(json.contains("\"\(key)\":"), key)
        }
        XCTAssertFalse(json.contains("checkpoint\":{"), "The absolute checkpoint path is recomputed, never stored")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sidecarURL.path + ".tmp"))
        XCTAssertEqual(try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        // A write interrupted before its rename leaves the committed file readable.
        try Data("{\"format\":1,\"torn".utf8).write(to: URL(fileURLWithPath: store.sidecarURL.path + ".tmp"))
        XCTAssertEqual(store.readRecord(), record)
        var left = record
        left.leftAt = Self.millis(Self.launch)
        try store.write(left)
        XCTAssertEqual(store.readRecord(), left)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sidecarURL.path + ".tmp"))
    }

    func testTestsAndPreviewsNeverUseTheRealDirectory() {
        let support = URL(fileURLWithPath: "/private/var/mobile/Library/Application Support")
        XCTAssertEqual(GameResumeStore.directory(entryPoint: .embedded, testing: false, applicationSupport: support),
                       support.appendingPathComponent("Resume", isDirectory: true))
        for (entry, testing) in [(OnDeviceAppConfiguration.EntryPoint.embedded, true), (.setupPreview, false),
                                 (.engineMissing, false)] {
            let directory = GameResumeStore.directory(entryPoint: entry, testing: testing, applicationSupport: support)
            XCTAssertFalse(directory.path.hasPrefix(support.path), "\(entry) testing=\(testing)")
            XCTAssertTrue(directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        }
    }

    func testPromptDetailText() {
        XCTAssertEqual(GameResumeText.detail(turn: 12, opponents: ["Alice", "Bob"], savedSecondsAgo: 180),
                       "Turn 12 against Alice and Bob · saved 3 min ago")
        XCTAssertEqual(GameResumeText.detail(turn: 3, opponents: ["AI 1"], savedSecondsAgo: 20), "Turn 3 against AI 1 · saved just now")
        XCTAssertEqual(GameResumeText.detail(turn: 7, opponents: ["AI 1", "AI 2", "AI 3"], savedSecondsAgo: 60),
                       "Turn 7 against AI 1, AI 2 and AI 3 · saved 1 min ago")
        XCTAssertEqual(GameResumeText.detail(turn: 0, opponents: ["AI 1"], savedSecondsAgo: 119), "Against AI 1 · saved 1 min ago")
        XCTAssertEqual(GameResumeText.detail(turn: 5, opponents: ["AI 1"], savedSecondsAgo: 3700), "Turn 5 against AI 1 · saved 1 hr ago")
        XCTAssertEqual(GameResumeRecord.opponents(in: Self.configuration), ["AI 1", "AI 2"])
    }

    // MARK: Launch

    @MainActor
    func testLaunchOffersAResumableGame() throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 180, leftAgo: 120), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertEqual(resume.offer?.detail, "Turn 12 against AI 1 and AI 2 · saved 3 min ago")
        XCTAssertNil(resume.notice)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNotNil(resume.offer, "Evaluated once per launch")
        XCTAssertEqual(resume.acceptOffer(), Self.record(checkpointAgo: 180, leftAgo: 120))
        XCTAssertNil(resume.offer)
        XCTAssertTrue(store.sidecarExists && store.checkpointExists, "Files stay until the restore succeeds or fails")
    }

    @MainActor
    func testExpiredGameIsDeletedWithANotice() throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 900, leftAgo: 601), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNil(resume.offer)
        XCTAssertEqual(resume.notice, "Your unfinished game expired after 10 minutes.")
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
    }

    @MainActor
    func testUpdatedAppDeletesTheGameWithANotice() throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: 5), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: "0.1.1 (22)", engineIdentity: Self.engine)
        XCTAssertNil(resume.offer)
        XCTAssertEqual(resume.notice, "Your unfinished game can't be resumed after an update.")
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
    }

    @MainActor
    func testAbandonDeletesBothFiles() throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: 5), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNotNil(resume.offer)
        resume.abandon()
        XCTAssertNil(resume.offer)
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
        XCTAssertNil(resume.notice)
    }

    // MARK: Game lifecycle

    @MainActor
    private func startCheckpointedGame(_ resume: GameResumeCoordinator, store: GameResumeStore) throws {
        let plan = resume.planSoloGame(configuration: Self.configuration, capabilities: Self.checkpointCapabilities)
        XCTAssertTrue(plan.checkpointing)
        resume.soloGameStarted(plan, setup: Self.setup, playerDeckName: "Token Triumph")
        try Data("engine checkpoint".utf8).write(to: store.checkpointURL)
    }

    @MainActor
    func testSidecarWrittenAtStartAndUpdatedFromPolls() throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let plan = resume.planSoloGame(configuration: Self.configuration, capabilities: Self.checkpointCapabilities)
        XCTAssertEqual(plan.configuration["checkpoint"], .object(["path": .string(store.checkpointURL.path)]))
        XCTAssertNil(plan.baseConfiguration["checkpoint"])
        resume.soloGameStarted(plan, setup: Self.setup, playerDeckName: "Token Triumph")
        var saved = try XCTUnwrap(store.readRecord())
        XCTAssertEqual(saved.createdAt, Self.millis(Self.launch))
        XCTAssertEqual(saved.lastCheckpointAt, Self.millis(Self.launch))
        XCTAssertEqual(saved.opponents, ["AI 1", "AI 2"])
        XCTAssertEqual(saved.playerDeckName, "Token Triumph")
        XCTAssertEqual(saved.setup, Self.setup)
        XCTAssertEqual(saved.appBuild, Self.build)
        XCTAssertEqual(saved.engineIdentity, Self.engine)
        XCTAssertNil(saved.leftAt)
        XCTAssertFalse(store.hasMarker)

        resume.checkpointSaved(EngineCheckpoint(sequence: 1, savedAtMillis: Self.millis(Self.launch) + 5000, turn: 3, bytes: 600_000))
        saved = try XCTUnwrap(store.readRecord())
        XCTAssertEqual(saved.turn, 3)
        XCTAssertEqual(saved.lastCheckpointAt, Self.millis(Self.launch) + 5000)
        resume.checkpointSaved(EngineCheckpoint(sequence: 1, savedAtMillis: Self.millis(Self.launch) + 9000, turn: 9, bytes: 1))
        XCTAssertEqual(store.readRecord()?.turn, 3, "A repeated sequence is not a new save")
        resume.checkpointSaved(EngineCheckpoint(sequence: 2, savedAtMillis: Self.millis(Self.launch) + 9000, turn: 4, bytes: 1))
        XCTAssertEqual(store.readRecord()?.turn, 4)
    }

    @MainActor
    func testEndConcedeLeaveAndNewGameDeleteTheSave() throws {
        let store = makeStore()
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)

        // Game over (win, loss or draw), concede and leave all call gameFinished.
        try startCheckpointedGame(resume, store: store)
        resume.gameFinished()
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
        resume.checkpointSaved(EngineCheckpoint(sequence: 9, savedAtMillis: Self.millis(Self.launch), turn: 9, bytes: 1))
        XCTAssertFalse(store.sidecarExists, "A late poll cannot bring a finished game back")

        // Another solo game replaces the old save before it is created.
        try startCheckpointedGame(resume, store: store)
        _ = resume.planSoloGame(configuration: Self.configuration, capabilities: Self.checkpointCapabilities)
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)

        // So does a table game, which leaves only its marker.
        try startCheckpointedGame(resume, store: store)
        resume.tableGameStarted()
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
        XCTAssertTrue(store.hasMarker)
        resume.gameFinished()
        XCTAssertFalse(store.hasMarker)
    }

    // MARK: Capability gating

    @MainActor
    func testEngineWithoutSaveResumeGetsNoCheckpointFieldAndLeavesAMarker() async throws {
        let store = makeStore()
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        for capabilities in [Self.oldCapabilities, MagicMobileOnDevice.JSONValue.object(["engine": .string("xmage")])] {
            let plan = resume.planSoloGame(configuration: Self.configuration, capabilities: capabilities)
            XCTAssertFalse(plan.checkpointing)
            XCTAssertEqual(plan.configuration, Self.configuration, "Sent unchanged")
            // On the wire: create carries exactly the old configuration.
            let transport = GameResumeRecordingTransport()
            _ = try await EngineClient(transport: transport).create(configuration: plan.configuration)
            let calls = await transport.calls()
            XCTAssertEqual(calls.count, 1)
            XCTAssertNil(calls.first?["configuration"]?["checkpoint"])
            resume.soloGameStarted(plan, setup: Self.setup, playerDeckName: "Token Triumph")
            XCTAssertFalse(store.sidecarExists)
            XCTAssertTrue(store.hasMarker)
        }
    }

    @MainActor
    func testRestoreIsNeverCalledWithoutSaveResume() async throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: 5), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let record = try XCTUnwrap(resume.acceptOffer())
        let transport = GameResumeRecordingTransport()
        let client = EngineClient(transport: transport)
        var restoreCalls = 0
        do {
            _ = try await resume.restore(record, capabilities: Self.oldCapabilities) { path in
                restoreCalls += 1
                return try await client.restore(checkpointPath: path, capabilities: Self.oldCapabilities)
            }
            XCTFail("An engine without saveResume cannot restore")
        } catch {}
        XCTAssertEqual(restoreCalls, 0)
        let calls = await transport.calls()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
        XCTAssertEqual(resume.notice, "Couldn't resume that game.")
    }

    // MARK: Restore

    @MainActor
    func testRestoreFailureDeletesTheSaveAndSaysSo() async throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: 5), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let record = try XCTUnwrap(resume.acceptOffer())
        for code in [EngineSaveResume.incompatibleCode, EngineSaveResume.corruptCode, EngineSaveResume.unavailableCode] {
            try writeGame(record, to: store)
            do {
                _ = try await resume.restore(record, capabilities: Self.checkpointCapabilities) { _ in
                    throw EngineError.rejected(code: code, message: "Engine refused")
                }
                XCTFail("Expected \(code)")
            } catch EngineError.rejected(let thrown, _) {
                XCTAssertEqual(thrown, code)
            }
            XCTAssertFalse(store.sidecarExists || store.checkpointExists, code)
            XCTAssertEqual(resume.notice, "Couldn't resume that game.")
            XCTAssertNil(resume.active)
        }
        resume.checkpointSaved(EngineCheckpoint(sequence: 1, savedAtMillis: Self.millis(Self.launch), turn: 1, bytes: 1))
        XCTAssertFalse(store.sidecarExists)
    }

    @MainActor
    func testRestoreSuccessKeepsCheckpointingTheSamePath() async throws {
        let store = makeStore()
        try writeGame(Self.record(checkpointAgo: 200, leftAgo: 100), to: store)
        let resume = coordinator(store)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let record = try XCTUnwrap(resume.acceptOffer())
        let transport = GameResumeRecordingTransport(result: .object([
            "matchId": .string("restored"),
            "restored": .object(["turn": .integer(12), "savedAtMillis": .integer(Self.millis(Self.launch) - 200_000)])
        ]))
        let client = EngineClient(transport: transport)
        let restored = try await resume.restore(record, capabilities: Self.checkpointCapabilities) { path in
            try await client.restore(checkpointPath: path, capabilities: Self.checkpointCapabilities)
        }
        XCTAssertEqual(restored.matchID, "restored")
        let calls = await transport.calls()
        XCTAssertEqual(calls.first?["op"], .string("restore"))
        XCTAssertEqual(calls.first?["checkpoint"], .object(["path": .string(store.checkpointURL.path)]))
        let saved = try XCTUnwrap(store.readRecord())
        XCTAssertNil(saved.leftAt)
        XCTAssertEqual(saved.turn, 12)
        XCTAssertEqual(saved.setup, Self.setup)
        XCTAssertEqual(resume.notice, "Resumed at your last decision.")
        resume.checkpointSaved(EngineCheckpoint(sequence: 1, savedAtMillis: Self.millis(Self.launch) + 1000, turn: 13, bytes: 1))
        XCTAssertEqual(store.readRecord()?.turn, 13, "The restored game keeps saving")
        XCTAssertTrue(store.checkpointExists, "An engine that saves at every decision keeps its file")
    }

    @MainActor
    func testRestoreWithAnOnDemandEngineUsesUpTheSaveAndSavesAgainOnLeaving() async throws {
        let store = makeStore(), clock = Clock()
        try writeGame(Self.record(checkpointAgo: 200, leftAgo: 100), to: store)
        let resume = coordinator(store, clock: clock)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let record = try XCTUnwrap(resume.acceptOffer())
        _ = try await resume.restore(record, capabilities: Self.onDemandCapabilities) { _ in
            try EngineRestoredMatch(.object(["matchId": .string("restored"),
                                             "restored": .object(["turn": .integer(12), "savedAtMillis": .integer(Self.millis(Self.launch) - 200_000)])]))
        }
        XCTAssertTrue(resume.savesOnDemand)
        XCTAssertFalse(store.checkpointExists, "Playing again uses up the save: a crash now ends the game")
        XCTAssertTrue(store.consumedCheckpointExists)

        // Leaving again before any decision: the engine reports the save it restored from.
        let engine = FakeSave(clock: clock, store: store, results: [Self.saved(4, turn: 12, at: Self.launch.addingTimeInterval(-200))])
        engine.writesFile = false
        engine.install(on: resume)
        await resume.enteredBackground().value
        XCTAssertTrue(store.checkpointExists)
        XCTAssertFalse(store.consumedCheckpointExists)
        let next = coordinator(store, clock: clock)
        next.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNotNil(next.offer)
    }

    // MARK: Games that cannot checkpoint

    @MainActor
    func testMarkerSaysTheLastGameEndedWhenTheAppClosed() throws {
        let store = makeStore()
        let first = coordinator(store)
        first.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        first.tableGameStarted()
        // The process dies mid-game. Next launch:
        let second = coordinator(store)
        second.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertEqual(second.notice, "Your last game ended when the app closed.")
        XCTAssertNil(second.offer)
        XCTAssertFalse(store.hasMarker, "One-time notice")
        let third = coordinator(store)
        third.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNil(third.notice)

        // A game that ended normally or was left clears its marker.
        third.tableGameStarted()
        third.gameFinished()
        let fourth = coordinator(store)
        fourth.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNil(fourth.notice)
    }

    @MainActor
    func testGameThatDiedBeforeItsFirstCheckpoint() throws {
        let store = makeStore()
        let first = coordinator(store)
        first.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let plan = first.planSoloGame(configuration: Self.configuration, capabilities: Self.checkpointCapabilities)
        first.soloGameStarted(plan, setup: Self.setup, playerDeckName: "Token Triumph")
        let second = coordinator(store)
        second.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        XCTAssertNil(second.offer)
        XCTAssertEqual(second.notice, "Your last game ended when the app closed.")
        XCTAssertFalse(store.sidecarExists)
    }

    // MARK: Saving when the player leaves

    /// TEST-ONLY engine side of saving on leaving. Each request takes the next scripted result
    /// (the last one repeats) and advances the clock by its wait, as the engine waits. A saved
    /// result writes the checkpoint unless `writesFile` is false (a decision saved earlier).
    @MainActor
    private final class FakeSave {
        let clock: Clock, store: GameResumeStore
        var results: [EngineCheckpointResult]
        var writesFile = true
        var throwsError = false
        var waits: [Int] = []
        var cancels = 0
        var onRequest: (() -> Void)?

        init(clock: Clock, store: GameResumeStore, results: [EngineCheckpointResult]) {
            self.clock = clock; self.store = store; self.results = results
        }

        func install(on resume: GameResumeCoordinator) {
            resume.requestSave = { [self] wait in
                waits.append(wait)
                clock.uptime += Double(wait) / 1000
                onRequest?()
                if throwsError { throw EngineError.runtimeFailure(3) }
                let result = results.count > 1 ? results.removeFirst() : results[0]
                if case .saved = result, writesFile { try Data("engine checkpoint \(waits.count)".utf8).write(to: store.checkpointURL) }
                return result
            }
            resume.cancelSave = { [self] in cancels += 1 }
        }
    }

    private static func saved(_ sequence: Int64, turn: Int64, at date: Date) -> EngineCheckpointResult {
        .saved(EngineCheckpoint(sequence: sequence, savedAtMillis: millis(date), turn: turn, bytes: 600_000, writeMillis: 40))
    }

    @MainActor
    private func startOnDemandGame(_ resume: GameResumeCoordinator) {
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        let plan = resume.planSoloGame(configuration: Self.configuration, capabilities: Self.onDemandCapabilities)
        XCTAssertTrue(plan.checkpointing && plan.savesOnDemand)
        resume.soloGameStarted(plan, setup: Self.setup, playerDeckName: "Token Triumph")
    }

    @MainActor
    private func relaunch(_ store: GameResumeStore, clock: Clock) -> GameResumeCoordinator {
        let next = coordinator(store, clock: clock)
        next.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        return next
    }

    @MainActor
    func testLeavingSavesInsideBackgroundTimeAndTheNextLaunchOffersIt() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        var purges: [String] = []
        var taskNames: [String] = []
        resume.backgroundPurges = [{ purges.append("images") }, { purges.append("audio") }]
        resume.runBackgroundTask = { name, body in taskNames.append(name); return Task { @MainActor in await body() } }

        // No game: caches still drop, nothing is written or asked.
        await resume.enteredBackground().value
        XCTAssertEqual(purges, ["images", "audio"])
        XCTAssertFalse(store.sidecarExists)
        XCTAssertTrue(taskNames.isEmpty)

        startOnDemandGame(resume)
        XCTAssertFalse(store.checkpointExists, "Nothing is saved while the player plays")
        clock.now = Self.launch.addingTimeInterval(42)
        let engine = FakeSave(clock: clock, store: store,
                              results: [.waitingForEngine, .waitingForEngine, Self.saved(3, turn: 5, at: clock.now)])
        engine.install(on: resume)
        let task = resume.enteredBackground()
        XCTAssertEqual(store.readRecord()?.leftAt, Self.millis(clock.now), "leftAt is written before the engine is asked")
        await task.value
        XCTAssertEqual(engine.waits, [1000, 1000, 1000], "Asks again while the AI is thinking")
        XCTAssertEqual(taskNames, ["MagicMobile save game"])
        XCTAssertEqual(purges.count, 4)
        let saved = try XCTUnwrap(store.readRecord())
        XCTAssertEqual(saved.turn, 5)
        XCTAssertEqual(saved.lastCheckpointAt, Self.millis(clock.now))
        XCTAssertEqual(saved.leftAt, Self.millis(clock.now))
        XCTAssertTrue(store.checkpointExists)

        // iOS ends the app while it is away.
        clock.now = clock.now.addingTimeInterval(60)
        XCTAssertEqual(relaunch(store, clock: clock).offer?.detail, "Turn 5 against AI 1 and AI 2 · saved 1 min ago")
    }

    @MainActor
    func testBackgroundSaveStopsAtItsDeadline() async throws {
        // 15 s at most, and never within 3 s of the end of iOS background time.
        for (remaining, waits) in [(30.0, Array(repeating: 1000, count: 15)), (8.0, Array(repeating: 1000, count: 5)),
                                   (3.5, [500]), (1.0, [0])] {
            let store = makeStore(), clock = Clock()
            let resume = coordinator(store, clock: clock)
            startOnDemandGame(resume)
            resume.backgroundTimeRemaining = { remaining }
            let engine = FakeSave(clock: clock, store: store, results: [.waitingForEngine])
            engine.install(on: resume)
            await resume.enteredBackground().value
            XCTAssertEqual(engine.waits, waits, "\(remaining) s of background time")
            XCTAssertFalse(store.checkpointExists)
            // Never saved: the next launch says the game ended.
            XCTAssertEqual(relaunch(store, clock: clock).notice, "Your last game ended when the app closed.")
            XCTAssertFalse(store.sidecarExists)
        }
    }

    @MainActor
    func testBackgroundSaveStopsWhenTheGameCannotBeSaved() async throws {
        let cases: [(String, EngineCheckpointResult?)] = [
            ("mid-action", .waitingForPlayer), ("write failed", .failed(.object(["message": .string("disk full")]))),
            ("unavailable", .unavailable(code: EngineSaveResume.unavailableCode)), ("transport error", nil)]
        for (name, result) in cases {
            let store = makeStore(), clock = Clock()
            let resume = coordinator(store, clock: clock)
            startOnDemandGame(resume)
            let engine = FakeSave(clock: clock, store: store, results: [result ?? .waitingForEngine])
            engine.throwsError = result == nil
            engine.install(on: resume)
            await resume.enteredBackground().value
            XCTAssertEqual(engine.waits.count, 1, name)
            XCTAssertNotNil(store.readRecord()?.leftAt, name)
            XCTAssertEqual(relaunch(store, clock: clock).notice, "Your last game ended when the app closed.", name)
        }

        // The match is over: nothing is left to resume.
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        startOnDemandGame(resume)
        FakeSave(clock: clock, store: store, results: [.over]).install(on: resume)
        await resume.enteredBackground().value
        XCTAssertFalse(store.sidecarExists || store.checkpointExists)
        XCTAssertNil(resume.active)
        XCTAssertNil(relaunch(store, clock: clock).notice)
    }

    @MainActor
    func testComingBackUsesUpTheSaveSoACrashEndsTheGame() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        startOnDemandGame(resume)
        let engine = FakeSave(clock: clock, store: store, results: [Self.saved(1, turn: 3, at: clock.now)])
        engine.install(on: resume)
        await resume.enteredBackground().value
        XCTAssertTrue(store.checkpointExists)

        await resume.enteredForeground().value
        XCTAssertNil(try XCTUnwrap(store.readRecord()).leftAt, "A surviving process keeps its live game")
        XCTAssertEqual(engine.cancels, 1, "The engine forgets any armed request")
        XCTAssertFalse(store.checkpointExists, "The save made on leaving is used up")
        XCTAssertTrue(store.sidecarExists)
        await resume.enteredForeground().value
        XCTAssertEqual(engine.cancels, 1, "Only a return from leaving cancels")

        // The app dies while the player is in it: never an older save.
        let next = relaunch(store, clock: clock)
        XCTAssertNil(next.offer)
        XCTAssertEqual(next.notice, "Your last game ended when the app closed.")
        XCTAssertFalse(store.sidecarExists || store.checkpointExists || store.consumedCheckpointExists)
    }

    @MainActor
    func testLeavingAgainAtTheSameDecisionKeepsThatSave() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        startOnDemandGame(resume)
        let engine = FakeSave(clock: clock, store: store, results: [Self.saved(1, turn: 3, at: clock.now)])
        engine.install(on: resume)
        await resume.enteredBackground().value
        await resume.enteredForeground().value
        XCTAssertFalse(store.checkpointExists)

        // Back out without a decision: the engine reports the save it already made.
        engine.writesFile = false
        await resume.enteredBackground().value
        XCTAssertTrue(store.checkpointExists, "The used-up save is the current one again")
        XCTAssertFalse(store.consumedCheckpointExists)

        // After a decision the engine writes a new save, and the old one goes.
        await resume.enteredForeground().value
        engine.writesFile = true
        engine.results = [Self.saved(2, turn: 4, at: clock.now.addingTimeInterval(30))]
        await resume.enteredBackground().value
        XCTAssertTrue(store.checkpointExists)
        XCTAssertFalse(store.consumedCheckpointExists)
        XCTAssertEqual(store.readRecord()?.turn, 4)
        XCTAssertNotNil(relaunch(store, clock: clock).offer)
        XCTAssertFalse(store.consumedCheckpointExists)
    }

    @MainActor
    func testTheAppSwitcherArmsASaveWithoutWaiting() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        startOnDemandGame(resume)
        let engine = FakeSave(clock: clock, store: store, results: [.waitingForEngine])
        engine.install(on: resume)
        clock.now = Self.launch.addingTimeInterval(10)
        await resume.willLeave().value
        XCTAssertEqual(engine.waits, [0])
        XCTAssertEqual(store.readRecord()?.leftAt, Self.millis(clock.now))
        // Back without leaving the app: the request is cancelled.
        await resume.enteredForeground().value
        XCTAssertEqual(engine.cancels, 1)
        XCTAssertNil(store.readRecord()?.leftAt)

        // Closed from the app switcher after the engine saved: the next launch offers it.
        engine.results = [Self.saved(1, turn: 2, at: clock.now)]
        await resume.willLeave().value
        XCTAssertTrue(store.checkpointExists)
        XCTAssertEqual(store.readRecord()?.turn, 2)
        XCTAssertNotNil(relaunch(store, clock: clock).offer)
    }

    @MainActor
    func testComingBackStopsTheBackgroundSave() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        startOnDemandGame(resume)
        let engine = FakeSave(clock: clock, store: store, results: [Self.saved(1, turn: 3, at: clock.now)])
        engine.install(on: resume)
        // The player returns while the request is waiting; its answer comes after.
        engine.onRequest = { [weak resume] in resume?.enteredForeground() }
        await resume.enteredBackground().value
        XCTAssertEqual(engine.waits.count, 1)
        let record = try XCTUnwrap(store.readRecord())
        XCTAssertNil(record.leftAt)
        XCTAssertEqual(record.turn, 0, "A save answered after the return is not recorded as the save on leaving")
        XCTAssertNil(relaunch(store, clock: clock).offer)
    }

    @MainActor
    func testOlderEnginesSaveAtEveryDecisionAndAreNeverAsked() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        try startCheckpointedGame(resume, store: store)
        XCTAssertFalse(resume.savesOnDemand)
        var taskNames: [String] = []
        resume.runBackgroundTask = { name, body in taskNames.append(name); return Task { @MainActor in await body() } }
        let engine = FakeSave(clock: clock, store: store, results: [.waitingForEngine])
        engine.install(on: resume)
        await resume.willLeave().value
        await resume.enteredBackground().value
        XCTAssertTrue(engine.waits.isEmpty, "checkpoint is never sent to an engine without checkpointOnDemand")
        XCTAssertNotNil(store.readRecord()?.leftAt)
        XCTAssertTrue(taskNames.isEmpty)
        XCTAssertNotNil(relaunch(store, clock: clock).offer, "Its last per-decision save is offered after leaving")

        await resume.enteredForeground().value
        XCTAssertEqual(engine.cancels, 0)
        XCTAssertNil(store.readRecord()?.leftAt)
        XCTAssertTrue(store.checkpointExists, "The engine keeps writing its file")
        XCTAssertEqual(relaunch(store, clock: clock).notice, "Your last game ended when the app closed.")
    }

    // MARK: Session

    @MainActor
    func testSessionPublishesThePollCheckpoint() async throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "2p-initial-player-1", withExtension: "json", subdirectory: "OnDevice"))
        var fields = try XCTUnwrap(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)).object)
        fields["checkpoint"] = .object(["sequence": .integer(3), "savedAtMillis": .integer(1_790_000_000_000),
                                        "turn": .integer(2), "bytes": .integer(584_000)])
        let poll = try MatchPoll(.object(fields))
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: GameResumeRecordingTransport(result: poll.raw)),
                                 matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        XCTAssertEqual(session.checkpoint, EngineCheckpoint(sequence: 3, savedAtMillis: 1_790_000_000_000, turn: 2, bytes: 584_000))
        XCTAssertFalse(session.isOverForSeat)
        try await session.close()
        XCTAssertNil(session.checkpoint)

        // The poll that ends the game tells save/resume to delete the saved game.
        fields["phase"] = .string("ended")
        let ended = try MatchPoll(.object(fields))
        try await session.attach(client: EngineClient(transport: GameResumeRecordingTransport(result: ended.raw)),
                                 matchID: ended.matchID, seatID: ended.seatID, autoPoll: false, close: {})
        XCTAssertTrue(session.isOverForSeat)
        try await session.close()
        XCTAssertFalse(session.isOverForSeat)
    }
}

/// TEST-ONLY engine boundary: records each request and answers with `result`.
actor GameResumeRecordingTransport: EngineTransport {
    private var recorded: [MagicMobileOnDevice.JSONValue] = []
    private let result: MagicMobileOnDevice.JSONValue
    init(result: MagicMobileOnDevice.JSONValue = .object(["matchId": .string("match")])) { self.result = result }
    func request(_ data: Data) async throws -> Data {
        recorded.append(try MagicMobileOnDevice.JSONValue.decode(data))
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func calls() -> [MagicMobileOnDevice.JSONValue] { recorded }
}
