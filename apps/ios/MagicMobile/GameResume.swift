import Foundation
import Combine
import MagicMobileOnDevice

/// Resume a solo game against the AI after the app closes. The engine writes the whole match
/// to `game.checkpoint`; this app keeps `resume.json` beside it and owns both files. A saved
/// game can be resumed for 10 minutes after the player left the app (or after the last
/// checkpoint, if the app died in the foreground). Game Center and online tables never
/// checkpoint; for those, and for engines without `saveResume`, a small marker lets the next
/// launch say that the game ended instead of silently showing the menu.
/// The same strings and rules apply on Android (parity/resume-cases.json).
enum GameResumeText {
    static let promptTitle = "Resume your game?"
    static let resume = "Resume"
    static let abandon = "Abandon"
    static let expired = "Your unfinished game expired after 10 minutes."
    static let updated = "Your unfinished game can't be resumed after an update."
    static let resumed = "Resumed at your last decision."
    static let restoreFailed = "Couldn't resume that game."
    static let endedOnClose = "Your last game ended when the app closed."
    /// The notice's close button, for VoiceOver.
    static let dismiss = "Dismiss notification"
    /// A notice dismisses itself after this long.
    static let noticeSeconds = 6

    /// "Turn 12 against Alice and Bob · saved 3 min ago". Whole minutes, rounded down:
    /// "saved just now" under a minute, whole hours from 60 minutes.
    static func detail(turn: Int64, opponents: [String], savedSecondsAgo: TimeInterval) -> String {
        let names = list(opponents)
        let game: String
        if turn > 0 { game = names.isEmpty ? "Turn \(turn)" : "Turn \(turn) against \(names)" }
        else { game = names.isEmpty ? "Your game" : "Against \(names)" }
        let minutes = Int(max(0, savedSecondsAgo) / 60)
        let saved = minutes < 1 ? "saved just now" : minutes < 60 ? "saved \(minutes) min ago" : "saved \(minutes / 60) hr ago"
        return "\(game) · \(saved)"
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }
}

/// Local game settings needed to rebuild the game screen, beside the create configuration.
struct GameResumeSetup: Codable, Equatable {
    /// The create configuration as sent, without the checkpoint path (recomputed each launch,
    /// because the app container path can change).
    var configuration: MagicMobileOnDevice.JSONValue
    var seatID: String
    var playerName: String
    var deckID: String
    var aiDeckIDs: [String]
    var aiSkill: Int
    var startingPlayerMode: String
}

/// `resume.json`. Times are Unix epoch milliseconds, like the engine's `savedAtMillis`.
struct GameResumeRecord: Codable, Equatable {
    static let currentFormat = 1
    var format = Self.currentFormat
    var appBuild: String
    var engineIdentity: String
    var createdAt: Int64
    var lastCheckpointAt: Int64
    var leftAt: Int64?
    var turn: Int64
    var playerDeckName: String
    var opponents: [String]
    var setup: GameResumeSetup

    private enum CodingKeys: String, CodingKey {
        case format, appBuild, engineIdentity, createdAt, lastCheckpointAt, leftAt, turn, playerDeckName, opponents, setup
    }

    init(appBuild: String, engineIdentity: String, createdAt: Int64, lastCheckpointAt: Int64, leftAt: Int64? = nil,
         turn: Int64 = 0, playerDeckName: String, opponents: [String], setup: GameResumeSetup) {
        self.appBuild = appBuild; self.engineIdentity = engineIdentity; self.createdAt = createdAt
        self.lastCheckpointAt = lastCheckpointAt; self.leftAt = leftAt; self.turn = turn
        self.playerDeckName = playerDeckName; self.opponents = opponents; self.setup = setup
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        appBuild = try c.decode(String.self, forKey: .appBuild)
        engineIdentity = try c.decode(String.self, forKey: .engineIdentity)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        lastCheckpointAt = try c.decode(Int64.self, forKey: .lastCheckpointAt)
        leftAt = try c.decodeIfPresent(Int64.self, forKey: .leftAt)
        turn = try c.decode(Int64.self, forKey: .turn)
        playerDeckName = try c.decode(String.self, forKey: .playerDeckName)
        opponents = try c.decode([String].self, forKey: .opponents)
        setup = try c.decode(GameResumeSetup.self, forKey: .setup)
    }

    /// `leftAt` is always written, as null while the player is in the app.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format); try c.encode(appBuild, forKey: .appBuild)
        try c.encode(engineIdentity, forKey: .engineIdentity); try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastCheckpointAt, forKey: .lastCheckpointAt); try c.encode(leftAt, forKey: .leftAt)
        try c.encode(turn, forKey: .turn); try c.encode(playerDeckName, forKey: .playerDeckName)
        try c.encode(opponents, forKey: .opponents); try c.encode(setup, forKey: .setup)
    }

    /// Names of the non-human seats, in seat order.
    static func opponents(in configuration: MagicMobileOnDevice.JSONValue) -> [String] {
        (configuration["seats"]?.array ?? []).filter { $0["controller"]?.string != "human" }.compactMap { $0["name"]?.string }
    }
}

enum GameResumeIdentity {
    /// "0.1.1 (21)": any app update changes it.
    static func appBuild(version: String, build: String) -> String { "\(version) (\(build))" }

    /// The engine the app validates at startup (capabilities must match the bundled
    /// catalogue, upstream and protocol). Known before the engine opens, so the launch
    /// prompt needs no engine. The engine still rejects a foreign build itself
    /// (`checkpoint_incompatible`). The same text as Android.
    static func engine(_ identity: BuildIdentity) -> String {
        engine(protocolVersion: Int64(identity.protocolVersion), upstream: identity.upstreamCommit,
               catalogueHash: identity.catalogueHash)
    }

    static func engine(protocolVersion: Int64, upstream: String, catalogueHash: String) -> String {
        "xmage/protocol-\(protocolVersion)/\(upstream)/\(catalogueHash)"
    }
}

enum GameResumePolicy {
    /// The game is over for this seat: it ended, or the player left it (conceded or lost in a
    /// pod, and now spectates). What was saved before must not come back.
    static func isOver(_ poll: MatchPoll) -> Bool {
        if poll.phase == "ended" || poll.snapshot?["outcome"]?["ended"]?.bool == true { return true }
        guard let viewer = poll.snapshot?["enginePlayerId"]?.string else { return false }
        return poll.snapshot?["gameView"]?["players"]?.array?.contains {
            $0["playerId"]?.string == viewer && $0["hasLeft"]?.bool == true
        } == true
    }
}

/// What the next launch does with the files it finds.
enum GameResumeLaunchDecision: Equatable {
    case nothing
    /// A checkpoint without its sidecar: the app already abandoned that game. Delete quietly.
    case orphanCheckpoint
    /// The game died before its first checkpoint, or the sidecar is unreadable.
    case endedOnClose
    case updated
    case expired
    case resumable(GameResumeRecord)

    static let window: Int64 = 600_000

    /// Expiry comes first: a game older than the window has expired whatever the build. Only a
    /// fresh game saved by another app build, engine or sidecar format is "updated".
    static func decide(record: GameResumeRecord?, sidecarExists: Bool, checkpointExists: Bool,
                       nowMillis: Int64, appBuild: String, engineIdentity: String) -> Self {
        guard sidecarExists else { return checkpointExists ? .orphanCheckpoint : .nothing }
        guard let record, checkpointExists else { return .endedOnClose }
        guard nowMillis - (record.leftAt ?? record.lastCheckpointAt) <= window else { return .expired }
        guard record.format == GameResumeRecord.currentFormat, record.appBuild == appBuild,
              record.engineIdentity == engineIdentity else { return .updated }
        return .resumable(record)
    }
}

/// The files, in Application Support/Resume on the phone (excluded from backup, readable
/// after first unlock) or a temporary directory for tests and previews.
final class GameResumeStore {
    let directory: URL
    private let protectsFiles: Bool
    private let fileManager = FileManager.default

    var checkpointURL: URL { directory.appendingPathComponent("game.checkpoint") }
    var sidecarURL: URL { directory.appendingPathComponent("resume.json") }
    var markerURL: URL { directory.appendingPathComponent("game-in-progress.json") }
    /// The engine writes `path.tmp`, fsyncs and renames it over the checkpoint.
    var checkpointTemporaryURL: URL { URL(fileURLWithPath: checkpointURL.path + ".tmp") }

    init(directory: URL, protectsFiles: Bool) {
        self.directory = directory
        self.protectsFiles = protectsFiles
    }

    /// Only the embedded phone app outside XCTest uses the real directory.
    static func directory(entryPoint: OnDeviceAppConfiguration.EntryPoint, testing: Bool,
                          applicationSupport: URL?, temporary: URL = FileManager.default.temporaryDirectory) -> URL {
        if entryPoint == .embedded, !testing, let applicationSupport {
            return applicationSupport.appendingPathComponent("Resume", isDirectory: true)
        }
        return temporary.appendingPathComponent("Resume-Preview-\(UUID().uuidString)", isDirectory: true)
    }

    func prepareDirectory() throws {
        var attributes: [FileAttributeKey: Any] = [:]
        if protectsFiles { attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }

    var sidecarExists: Bool { fileManager.fileExists(atPath: sidecarURL.path) }
    var checkpointExists: Bool { fileManager.fileExists(atPath: checkpointURL.path) }
    var checkpointWriteInProgress: Bool { fileManager.fileExists(atPath: checkpointTemporaryURL.path) }
    var hasMarker: Bool { fileManager.fileExists(atPath: markerURL.path) }

    func readRecord() -> GameResumeRecord? {
        guard let data = try? Data(contentsOf: sidecarURL) else { return nil }
        return try? JSONDecoder().decode(GameResumeRecord.self, from: data)
    }

    func write(_ record: GameResumeRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try writeAtomically(encoder.encode(record), to: sidecarURL)
    }

    func writeMarker(startedAt: Int64) throws {
        try writeAtomically(Data("{\"format\":1,\"startedAt\":\(startedAt)}".utf8), to: markerURL)
    }

    /// Both game files, and any interrupted temporary writes.
    func deleteGame() {
        for url in [sidecarURL, checkpointURL, URL(fileURLWithPath: sidecarURL.path + ".tmp"), checkpointTemporaryURL] {
            try? fileManager.removeItem(at: url)
        }
    }

    func deleteMarker() {
        for url in [markerURL, URL(fileURLWithPath: markerURL.path + ".tmp")] { try? fileManager.removeItem(at: url) }
    }

    /// Write `path.tmp`, fsync, rename: a reader sees the old file or the new one, never a torn one.
    func writeAtomically(_ data: Data, to url: URL) throws {
        try prepareDirectory()
        let temporary = URL(fileURLWithPath: url.path + ".tmp")
        try? fileManager.removeItem(at: temporary)
        let attributes: [FileAttributeKey: Any]? = protectsFiles
            ? [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication] : nil
        guard fileManager.createFile(atPath: temporary.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            try? fileManager.removeItem(at: temporary)
            throw POSIXError(code)
        }
    }
}

/// The prompt shown over the main menu when a saved game can be resumed.
struct GameResumeOffer: Equatable {
    let record: GameResumeRecord
    let detail: String
}

/// Everything the app does for save/resume. Views and the setup model call these hooks;
/// the rules live here so they are tested without an engine or a simulator.
@MainActor
final class GameResumeCoordinator: ObservableObject {
    /// Starts platform background time, runs `body`, then ends it.
    typealias BackgroundTaskRunner = @MainActor (_ name: String, _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never>

    @Published private(set) var offer: GameResumeOffer?
    @Published var notice: String?

    let store: GameResumeStore
    private let now: () -> Date
    /// Called on every move to the background: drop in-memory image caches, audio buffers.
    var backgroundPurges: [@MainActor () -> Void] = []
    var runBackgroundTask: BackgroundTaskRunner = { _, body in Task { @MainActor in await body() } }
    /// How long the background task waits for an in-flight engine checkpoint write.
    var checkpointWriteGrace: TimeInterval = 4

    private(set) var appBuild: String?
    private(set) var engineIdentity: String?
    /// The checkpointing game this process is playing, if any.
    private(set) var active: GameResumeRecord?
    private var lastSequence: Int64 = -1
    private var launchEvaluated = false

    init(store: GameResumeStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    private var nowMillis: Int64 { Int64((now().timeIntervalSince1970 * 1000).rounded()) }

    // MARK: Launch

    /// Once per process, when the build identity is known. Offers a resumable game or
    /// deletes the files and shows a one-time notice.
    func evaluateLaunch(appBuild: String, engineIdentity: String) {
        self.appBuild = appBuild
        self.engineIdentity = engineIdentity
        guard !launchEvaluated else { return }
        launchEvaluated = true
        let hadMarker = store.hasMarker
        store.deleteMarker()
        let decision = GameResumeLaunchDecision.decide(
            record: store.readRecord(), sidecarExists: store.sidecarExists, checkpointExists: store.checkpointExists,
            nowMillis: nowMillis, appBuild: appBuild, engineIdentity: engineIdentity)
        switch decision {
        case .nothing:
            if hadMarker { notice = GameResumeText.endedOnClose }
        case .orphanCheckpoint:
            store.deleteGame()
            if hadMarker { notice = GameResumeText.endedOnClose }
        case .endedOnClose:
            store.deleteGame(); notice = GameResumeText.endedOnClose
        case .updated:
            store.deleteGame(); notice = GameResumeText.updated
        case .expired:
            store.deleteGame(); notice = GameResumeText.expired
        case .resumable(let record):
            let ago = Double(nowMillis - record.lastCheckpointAt) / 1000
            offer = GameResumeOffer(record: record, detail: GameResumeText.detail(
                turn: record.turn, opponents: record.opponents, savedSecondsAgo: ago))
        }
    }

    /// The player chose Resume. The deadline was checked when the prompt appeared.
    func acceptOffer() -> GameResumeRecord? {
        defer { offer = nil }
        return offer?.record
    }

    /// The player chose Abandon.
    func abandon() {
        offer = nil
        store.deleteGame()
    }

    // MARK: Solo games

    struct SoloPlan {
        let configuration: MagicMobileOnDevice.JSONValue
        let baseConfiguration: MagicMobileOnDevice.JSONValue
        let checkpointing: Bool
    }

    /// Before creating a solo game: forget any earlier game and add the checkpoint path when
    /// the engine supports it. An engine without `saveResume` is sent the configuration unchanged.
    func planSoloGame(configuration: MagicMobileOnDevice.JSONValue, capabilities: MagicMobileOnDevice.JSONValue?) -> SoloPlan {
        discardAll()
        guard appBuild != nil, engineIdentity != nil, (try? store.prepareDirectory()) != nil,
              let checkpointed = try? EngineSaveResume.configuration(configuration, checkpointPath: store.checkpointURL.path,
                                                                      capabilities: capabilities) else {
            return SoloPlan(configuration: configuration, baseConfiguration: configuration, checkpointing: false)
        }
        return SoloPlan(configuration: checkpointed, baseConfiguration: configuration, checkpointing: true)
    }

    /// The engine created the planned game: write the sidecar, or the marker when it cannot checkpoint.
    func soloGameStarted(_ plan: SoloPlan, setup: GameResumeSetup, playerDeckName: String) {
        let created = nowMillis
        guard plan.checkpointing, let appBuild, let engineIdentity else { return markInProgress(at: created) }
        let record = GameResumeRecord(appBuild: appBuild, engineIdentity: engineIdentity, createdAt: created,
                                      lastCheckpointAt: created, playerDeckName: playerDeckName,
                                      opponents: GameResumeRecord.opponents(in: plan.baseConfiguration), setup: setup)
        do { try store.write(record); active = record; lastSequence = -1 }
        catch { store.deleteGame(); markInProgress(at: created) }
    }

    /// A poll reported a newer engine checkpoint.
    func checkpointSaved(_ checkpoint: EngineCheckpoint) {
        guard var record = active, checkpoint.sequence > lastSequence else { return }
        lastSequence = checkpoint.sequence
        record.lastCheckpointAt = checkpoint.savedAtMillis
        record.turn = checkpoint.turn
        active = record
        try? store.write(record)
    }

    /// Restores `record`. Never calls `restore` for an engine without `saveResume`. On any
    /// failure both files are deleted and the player is told; the caller stays on the menu.
    func restore(_ record: GameResumeRecord, capabilities: MagicMobileOnDevice.JSONValue?,
                 using perform: (_ checkpointPath: String) async throws -> EngineRestoredMatch) async throws -> EngineRestoredMatch {
        guard EngineSaveResume.isSupported(capabilities) else {
            restoreFailed()
            throw EngineError.invalidMessage(GameResumeText.restoreFailed)
        }
        do {
            let restored = try await perform(store.checkpointURL.path)
            var resumed = record
            resumed.leftAt = nil
            resumed.lastCheckpointAt = restored.savedAtMillis
            resumed.turn = restored.turn
            try? store.write(resumed)
            active = resumed; lastSequence = -1
            store.deleteMarker()
            notice = GameResumeText.resumed
            return restored
        } catch {
            restoreFailed()
            throw error
        }
    }

    func restoreFailed() {
        active = nil
        store.deleteGame()
        notice = GameResumeText.restoreFailed
    }

    // MARK: Tables and endings

    /// A Game Center, relay or online game started: it never checkpoints.
    func tableGameStarted() {
        discardAll()
        markInProgress(at: nowMillis)
    }

    /// The game ended (win, loss or draw), the player conceded or left, or another game replaces it.
    func gameFinished() { discardAll() }

    private func discardAll() {
        active = nil
        store.deleteGame()
        store.deleteMarker()
    }

    private func markInProgress(at time: Int64) {
        try? store.writeMarker(startedAt: time)
    }

    // MARK: Background

    /// The app moved to the background: record when the player left, inside platform
    /// background time so an in-flight engine checkpoint write can finish.
    @discardableResult
    func enteredBackground() -> Task<Void, Never> {
        for purge in backgroundPurges { purge() }
        let checkpointing = active != nil
        let task = runBackgroundTask("MagicMobile save game") { [weak self] in
            guard checkpointing, let self else { return }
            await self.waitForCheckpointWrite()
        }
        if var record = active {
            record.leftAt = nowMillis
            active = record
            try? store.write(record)
        }
        return task
    }

    /// Back in the app: the live game continues, however long the player was away.
    func enteredForeground() {
        guard var record = active, record.leftAt != nil else { return }
        record.leftAt = nil
        active = record
        try? store.write(record)
    }

    private func waitForCheckpointWrite() async {
        let deadline = ProcessInfo.processInfo.systemUptime + checkpointWriteGrace
        while store.checkpointWriteInProgress, ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
