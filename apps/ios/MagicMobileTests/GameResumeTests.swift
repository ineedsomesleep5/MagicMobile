import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Save/resume rules against temporary directories and engine-boundary fakes. No XMage
/// checkpoint is written or restored here; native restore is pending a checkpoint engine build.
final class GameResumeTests: XCTestCase {
    private static let launch = Date(timeIntervalSince1970: 1_790_000_000)
    private static let build = "0.1.1 (21)"
    private static let engine = "xmage/native-aot/protocol-1/upstream/catalogue"
    private static let checkpointCapabilities = MagicMobileOnDevice.JSONValue.object(["engine": .string("xmage"), "saveResume": .bool(true)])
    private static let oldCapabilities = MagicMobileOnDevice.JSONValue.object(["engine": .string("xmage"), "saveResume": .bool(false)])

    private final class Clock { var now = GameResumeTests.launch }

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
        GameResumeCoordinator(store: store, now: { clock.now })
    }

    // MARK: Expiry and identity

    func testTenMinuteWindowFromLeavingTheApp() {
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 599)), .resumable(Self.record(checkpointAgo: 900, leftAgo: 599)))
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 600)), .resumable(Self.record(checkpointAgo: 900, leftAgo: 600)))
        XCTAssertEqual(decide(Self.record(checkpointAgo: 900, leftAgo: 601)), .expired)
    }

    func testForegroundDeathUsesTheLastCheckpoint() {
        XCTAssertEqual(decide(Self.record(checkpointAgo: 599, leftAgo: nil)), .resumable(Self.record(checkpointAgo: 599, leftAgo: nil)))
        XCTAssertEqual(decide(Self.record(checkpointAgo: 601, leftAgo: nil)), .expired)
    }

    func testBuildOrEngineMismatchCannotResume() {
        let fresh = Self.record(checkpointAgo: 10, leftAgo: nil)
        XCTAssertEqual(decide(fresh, appBuild: "0.1.1 (22)"), .updated)
        XCTAssertEqual(decide(fresh, engine: "xmage/native-aot/protocol-1/other/catalogue"), .updated)
        var future = fresh
        future.format = 2
        XCTAssertEqual(decide(future), .updated)
        XCTAssertEqual(decide(Self.record(checkpointAgo: 9000, leftAgo: 9000), appBuild: "0.1.1 (22)"), .updated,
                       "An update is the reason even when the game also expired")
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
                                 (.referencePreview, false), (.engineMissing, false)] {
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
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: nil), to: store)
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
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: nil), to: store)
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
        try writeGame(Self.record(checkpointAgo: 10, leftAgo: nil), to: store)
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

    // MARK: Background

    @MainActor
    func testBackgroundRecordsLeavingInsideBackgroundTimeAndPurges() async throws {
        let store = makeStore(), clock = Clock()
        let resume = coordinator(store, clock: clock)
        resume.evaluateLaunch(appBuild: Self.build, engineIdentity: Self.engine)
        var purges: [String] = []
        var taskNames: [String] = []
        resume.backgroundPurges = [{ purges.append("images") }, { purges.append("audio") }]
        resume.runBackgroundTask = { name, body in taskNames.append(name); return Task { @MainActor in await body() } }
        resume.checkpointWriteGrace = 0.3

        // No game: caches still drop, nothing is written.
        await resume.enteredBackground().value
        XCTAssertEqual(purges, ["images", "audio"])
        XCTAssertFalse(store.sidecarExists)

        try startCheckpointedGame(resume, store: store)
        clock.now = Self.launch.addingTimeInterval(42)
        try Data("in-flight".utf8).write(to: store.checkpointTemporaryURL)
        let started = ProcessInfo.processInfo.systemUptime
        let task = resume.enteredBackground()
        XCTAssertEqual(store.readRecord()?.leftAt, Self.millis(clock.now), "Flushed before the background task ends")
        await task.value
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - started, 0.25,
                                    "Background time is held for an in-flight checkpoint write")
        XCTAssertEqual(purges.count, 4)
        XCTAssertEqual(taskNames.count, 2)

        resume.enteredForeground()
        XCTAssertNil(try XCTUnwrap(store.readRecord()).leftAt, "A surviving process keeps its live game")
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
        try await session.close()
        XCTAssertNil(session.checkpoint)
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
