import Foundation
import Combine
import MagicMobileOnDevice

/// Resume a solo game against the AI after the app closes. When the player leaves the app, the
/// engine writes the whole match to `game.checkpoint` (engines with `checkpointOnDemand` save
/// only when asked; older `saveResume` engines save at every decision); this app keeps
/// `resume.json` beside it and owns both files. A game saved when the player left can be resumed
/// for 10 minutes after they left. Coming back consumes that save, so a game that was open when
/// the app died is reported as ended, never resumed from an older save. Game Center and relay
/// tables never checkpoint; for those, and for engines without `saveResume`, a small marker lets
/// the next launch say that the game ended instead of silently showing the menu.
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
    /// The game was not saved when the player left: it was still open when the app died, it
    /// could not be saved in time, or the sidecar is unreadable.
    case endedOnClose
    case updated
    case expired
    case resumable(GameResumeRecord)

    static let window: Int64 = 600_000

    /// Only a game saved when the player left the app (`leftAt`) is resumable; one that was open
    /// when the app died has ended, even with a checkpoint. Expiry comes next: a game left longer
    /// ago than the window has expired whatever the build. Only a fresh game saved by another app
    /// build, engine or sidecar format is "updated".
    static func decide(record: GameResumeRecord?, sidecarExists: Bool, checkpointExists: Bool,
                       nowMillis: Int64, appBuild: String, engineIdentity: String) -> Self {
        guard sidecarExists else { return checkpointExists ? .orphanCheckpoint : .nothing }
        guard let record, checkpointExists, let leftAt = record.leftAt else { return .endedOnClose }
        guard nowMillis - leftAt <= window else { return .expired }
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
    /// The save made when the player last left, set aside when they came back. Never offered;
    /// the next launch deletes it.
    var consumedCheckpointURL: URL { directory.appendingPathComponent("game.checkpoint.consumed") }

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
    var consumedCheckpointExists: Bool { fileManager.fileExists(atPath: consumedCheckpointURL.path) }
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

    /// Both game files, a consumed save, and any interrupted temporary writes.
    func deleteGame() {
        for url in [sidecarURL, checkpointURL, URL(fileURLWithPath: sidecarURL.path + ".tmp"), checkpointTemporaryURL,
                    consumedCheckpointURL] {
            try? fileManager.removeItem(at: url)
        }
    }

    func deleteConsumedCheckpoint() { try? fileManager.removeItem(at: consumedCheckpointURL) }

    /// The player came back: the save made when they left is used up. From now on the game has
    /// no checkpoint, so a crash ends it. The file is set aside rather than deleted, because an
    /// engine asked to save again at the same decision reports that save instead of rewriting it.
    func consumeCheckpoint() {
        guard checkpointExists else { return }
        if rename(checkpointURL.path, consumedCheckpointURL.path) != 0 { try? fileManager.removeItem(at: checkpointURL) }
    }

    /// The engine reported a save. If it wrote nothing since the player came back, that save is
    /// the consumed one: put it back. Otherwise the consumed one is older and goes.
    func restoreConsumedCheckpointIfLatest() {
        if checkpointExists || rename(consumedCheckpointURL.path, checkpointURL.path) != 0 { deleteConsumedCheckpoint() }
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
    /// Asks the live game's engine to save now, waiting up to `waitMillis` (0...1000).
    typealias SaveRequest = @MainActor (_ waitMillis: Int) async throws -> EngineCheckpointResult
    /// Clears the engine's armed save request.
    typealias SaveCancel = @MainActor () async throws -> Void

    /// The background save stops after this long, or earlier if iOS allows less time.
    static let backgroundSaveLimit: TimeInterval = 15
    /// Background time left unused after the save, so iOS never has to end the app for it.
    static let backgroundTimeReserve: TimeInterval = 3

    @Published private(set) var offer: GameResumeOffer?
    @Published var notice: String?

    let store: GameResumeStore
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    /// Called on every move to the background: drop in-memory image caches, audio buffers.
    var backgroundPurges: [@MainActor () -> Void] = []
    var runBackgroundTask: BackgroundTaskRunner = { _, body in Task { @MainActor in await body() } }
    /// Background time iOS still allows, read inside the background task.
    var backgroundTimeRemaining: @MainActor () -> TimeInterval = { .infinity }
    /// The live solo game's engine, supplied by the setup model (engines with `checkpointOnDemand`).
    var requestSave: SaveRequest?
    var cancelSave: SaveCancel?

    private(set) var appBuild: String?
    private(set) var engineIdentity: String?
    /// The checkpointing game this process is playing, if any.
    private(set) var active: GameResumeRecord?
    /// The live game's engine saves only when asked. Older engines save at every decision.
    private(set) var savesOnDemand = false
    private var lastSequence: Int64 = -1
    private var launchEvaluated = false
    private var backgroundSave: Task<Void, Never>?
    /// The last cancel sent on coming back; a new save request waits for it.
    private var cancelling: Task<Void, Never>?

    init(store: GameResumeStore, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.now = now
        self.uptime = uptime
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
        // A save the player already came back from is never offered.
        store.deleteConsumedCheckpoint()
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
        /// The engine saves only when asked (`checkpointOnDemand`).
        let savesOnDemand: Bool
    }

    /// Before creating a solo game: forget any earlier game and add the checkpoint path when
    /// the engine supports it. An engine without `saveResume` is sent the configuration unchanged.
    func planSoloGame(configuration: MagicMobileOnDevice.JSONValue, capabilities: MagicMobileOnDevice.JSONValue?) -> SoloPlan {
        discardAll()
        guard appBuild != nil, engineIdentity != nil, (try? store.prepareDirectory()) != nil,
              let checkpointed = try? EngineSaveResume.configuration(configuration, checkpointPath: store.checkpointURL.path,
                                                                      capabilities: capabilities) else {
            return SoloPlan(configuration: configuration, baseConfiguration: configuration, checkpointing: false, savesOnDemand: false)
        }
        return SoloPlan(configuration: checkpointed, baseConfiguration: configuration, checkpointing: true,
                        savesOnDemand: EngineSaveResume.supportsOnDemand(capabilities))
    }

    /// The engine created the planned game: write the sidecar, or the marker when it cannot checkpoint.
    func soloGameStarted(_ plan: SoloPlan, setup: GameResumeSetup, playerDeckName: String) {
        let created = nowMillis
        guard plan.checkpointing, let appBuild, let engineIdentity else { return markInProgress(at: created) }
        let record = GameResumeRecord(appBuild: appBuild, engineIdentity: engineIdentity, createdAt: created,
                                      lastCheckpointAt: created, playerDeckName: playerDeckName,
                                      opponents: GameResumeRecord.opponents(in: plan.baseConfiguration), setup: setup)
        do { try store.write(record); active = record; lastSequence = -1; savesOnDemand = plan.savesOnDemand }
        catch { store.deleteGame(); markInProgress(at: created) }
    }

    /// A poll or a save request reported a newer engine checkpoint.
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
            savesOnDemand = EngineSaveResume.supportsOnDemand(capabilities)
            // Playing again uses up the save, as coming back to the app does.
            if savesOnDemand { store.consumeCheckpoint() }
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

    /// A Game Center or relay game started: it never checkpoints.
    func tableGameStarted() {
        discardAll()
        markInProgress(at: nowMillis)
    }

    /// The game ended (win, loss or draw), the player conceded or left, or another game replaces it.
    func gameFinished() { discardAll() }

    private func discardAll() {
        active = nil
        savesOnDemand = false
        backgroundSave?.cancel(); backgroundSave = nil
        store.deleteGame()
        store.deleteMarker()
    }

    private func markInProgress(at time: Int64) {
        try? store.writeMarker(startedAt: time)
    }

    // MARK: Leaving and coming back

    /// `.inactive` from `.active`: the player may be leaving, perhaps to close the app from the
    /// app switcher, which never reaches `.background`. Records when, and asks the engine to save
    /// at its next safe point without waiting.
    @discardableResult
    func willLeave() -> Task<Void, Never> {
        guard recordLeaving(), savesOnDemand, let requestSave else { return Task {} }
        let cancelling = self.cancelling
        return Task { [weak self] in
            await cancelling?.value
            guard let result = try? await requestSave(0) else { return }
            self?.saveFinished(result)
        }
    }

    /// The app moved to the background: record when the player left, then, inside platform
    /// background time, ask the engine to save until it saves, cannot, or time runs out.
    @discardableResult
    func enteredBackground() -> Task<Void, Never> {
        for purge in backgroundPurges { purge() }
        guard recordLeaving(), savesOnDemand, let requestSave else { return Task {} }
        backgroundSave?.cancel()
        let cancelling = self.cancelling
        let task = runBackgroundTask("MagicMobile save game") { [weak self] in
            await cancelling?.value
            await self?.saveWhileAway(requestSave)
        }
        backgroundSave = task
        return task
    }

    /// Back in the app: the live game continues, however long the player was away. The save
    /// made on leaving is used up, so if the app now dies, the next launch says the game ended.
    @discardableResult
    func enteredForeground() -> Task<Void, Never> {
        backgroundSave?.cancel(); backgroundSave = nil
        guard var record = active, record.leftAt != nil else { return Task {} }
        record.leftAt = nil
        active = record
        try? store.write(record)
        guard savesOnDemand else { return Task {} }
        store.consumeCheckpoint()
        guard let cancelSave else { return Task {} }
        let previous = cancelling
        let task = Task { await previous?.value; try? await cancelSave() }
        cancelling = task
        return task
    }

    /// Writes `leftAt` once per absence. False when no saved game is being played.
    private func recordLeaving() -> Bool {
        guard var record = active else { return false }
        if record.leftAt == nil {
            record.leftAt = nowMillis
            active = record
            try? store.write(record)
        }
        return true
    }

    /// Requests of up to one second each until the engine saves, cannot save, or the deadline:
    /// 15 seconds, or less when iOS allows less background time.
    private func saveWhileAway(_ requestSave: SaveRequest) async {
        let deadline = uptime() + min(Self.backgroundSaveLimit, backgroundTimeRemaining() - Self.backgroundTimeReserve)
        while active?.leftAt != nil, !Task.isCancelled {
            let wait = max(0, min(EngineSaveResume.maxWaitMillis, Int(((deadline - uptime()) * 1000).rounded(.down))))
            guard let result = try? await requestSave(wait), !Task.isCancelled else { return }
            guard result == .waitingForEngine, uptime() < deadline else { return saveFinished(result) }
        }
    }

    /// What the engine said about a save made while the player is away.
    private func saveFinished(_ result: EngineCheckpointResult) {
        guard active?.leftAt != nil else { return }
        switch result {
        case .saved(let checkpoint):
            store.restoreConsumedCheckpointIfLatest()
            checkpointSaved(checkpoint)
        case .over:
            gameFinished()
        case .waitingForEngine, .waitingForPlayer, .failed, .unavailable:
            break
        }
    }
}
