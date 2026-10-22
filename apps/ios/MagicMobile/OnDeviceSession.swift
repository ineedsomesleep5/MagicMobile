import Foundation
import Combine
import MagicMobileOnDevice

/// A seat's side of a phone-hosted table (Game Center or the cross-play relay). The host's session
/// announces each new game revision; a guest's session polls when an announcement arrives, promptly
/// while its own answer is outstanding, and otherwise only on a slow heartbeat, so a quiet table
/// sends almost nothing through the relay.
@MainActor
final class OnDeviceTableLink {
    enum Role: Equatable { case host, guest }
    let role: Role
    /// The host's table name, for "Waiting for <host>…".
    let hostName: String
    /// Host: shares a revision notice with every guest. Set by the multiplayer connection.
    var announce: ((Int64) -> Void)?
    private var announcedRevision: Int64 = -1
    /// Guest: the newest revision the host announced. Until the first notice arrives the guest
    /// cannot tell whether its host announces at all, so it keeps polling on the short timer.
    private(set) var noticedRevision: Int64 = -1
    private(set) var hostAnnounces = false
    private var waiters: [UUID: (continuation: CheckedContinuation<Void, Never>, timer: Task<Void, Never>)] = [:]

    init(role: Role, hostName: String) {
        self.role = role
        let name = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostName = name.isEmpty ? "the host" : name
    }

    var waitingStatus: String { "Waiting for \(hostName)…" }

    /// Host: the session applied a poll at `revision`. Each revision is announced once.
    func applied(revision: Int64) {
        guard role == .host, revision > announcedRevision else { return }
        announcedRevision = revision
        announce?(revision)
    }

    /// Guest: the host announced `revision`. Repeated, late or out-of-order notices are harmless.
    func noticed(revision: Int64) {
        guard role == .guest else { return }
        hostAnnounces = true
        noticedRevision = max(noticedRevision, revision)
        wake()
    }

    /// Returns after a notice, `wake()`, cancellation or `timeout` seconds, whichever comes first.
    func waitForNotice(timeout: TimeInterval) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let timer = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, min(timeout, 3600)) * 1_000_000_000))
                    self.resume(id)
                }
                waiters[id] = (continuation, timer)
            }
        } onCancel: {
            Task { @MainActor in self.resume(id) }
        }
    }

    /// Releases every waiting poll loop so it re-evaluates its schedule now.
    func wake() {
        for id in Array(waiters.keys) { resume(id) }
    }

    private func resume(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timer.cancel()
        waiter.continuation.resume()
    }
}

/// When a guest at a phone-hosted table polls its host next. Pure, so it is tested directly.
enum OnDeviceGuestPollSchedule {
    /// Safety net for a dropped notice. Notices are never queued or acknowledged.
    static let heartbeat: TimeInterval = 15
    /// After sending an answer, the guest polls promptly this long, or until the answer lands.
    static let answerWindow: TimeInterval = 10

    enum Step: Equatable {
        case poll(after: TimeInterval)
        case awaitNotice(timeout: TimeInterval)
    }

    static func next(hostAnnounces: Bool, noticedRevision: Int64, appliedRevision: Int64?,
                     awaitingAnswer: Bool, sinceAction: TimeInterval?, sinceLastPoll: TimeInterval,
                     spacing: TimeInterval) -> Step {
        let gap = max(0, spacing - sinceLastPoll)
        // A host that never announced (an older build) is polled on the short timer, as before.
        guard hostAnnounces, let applied = appliedRevision, noticedRevision <= applied else { return .poll(after: gap) }
        if awaitingAnswer, let sinceAction, sinceAction < answerWindow { return .poll(after: gap) }
        let remaining = heartbeat - sinceLastPoll
        return remaining > gap ? .awaitNotice(timeout: remaining) : .poll(after: gap)
    }
}

/// How often a local game asks its engine for the match. Every poll returns the whole snapshot, so
/// polling fast is only worth it while something can change.
enum OnDeviceLocalPollSchedule {
    /// The board just changed, or an answer is on its way.
    static let active: TimeInterval = 0.3
    /// A stack resolving right after this player's answer (a run of triggers, "Resolve all", a remembered answer): each
    /// resolution shows as soon as the engine has it. Only while things keep changing, and only for a few seconds.
    static let chain: TimeInterval = 0.12
    static let chainWindow: TimeInterval = 6
    /// Nothing changed for a few polls (the AI is thinking).
    static let idle: TimeInterval = 0.6
    /// The engine is waiting on this player: nothing can change until they answer, and an answer
    /// wakes the loop at once. This is only a safety net (a failure notice, a late save notice).
    static let awaitingPlayer: TimeInterval = 2
    /// Unchanged polls before the idle spacing, and before the awaiting-player spacing.
    static let idleAfter = 3, awaitingAfter = 8

    static func interval(idlePolls: Int, awaitingPlayer waiting: Bool, stackChain: Bool = false) -> TimeInterval {
        if waiting, idlePolls >= awaitingAfter { return awaitingPlayer }
        if idlePolls >= idleAfter { return idle }
        return stackChain ? chain : active
    }
}

/// Polls a local engine, and hands back the previous poll undecoded when the engine answered the same request with
/// exactly the same bytes. While the AI thinks most polls repeat the board, and decoding the whole game view was about
/// half of the polling thread's work (Instruments on Caleb's iPhone, 2026-10-18). The engine package's EngineClient
/// still decodes every reply that changed. Android: EngineClient.poll keeps the same memo.
struct OnDevicePollReader: Sendable {
    /// One poll as sent and answered, and its decoded result.
    struct Exchange: Sendable {
        let request: Data
        let reply: Data
        let poll: MatchPoll
    }

    let transport: any EngineTransport

    /// `previous` is the exchange whose poll the session last applied; `repeated` means it came back unchanged.
    func poll(matchID: String, seatID: String, after: Int64, previous: Exchange?) async throws -> (exchange: Exchange, repeated: Bool) {
        let tap = Tap(base: transport, previous: previous)
        do {
            let poll = try await EngineClient(transport: tap).poll(matchID: matchID, seatID: seatID, after: after)
            guard let sent = tap.sent else { throw EngineError.invalidMessage("The engine was not asked for this poll") }
            return (Exchange(request: sent.request, reply: sent.reply, poll: poll), false)
        } catch is Tap.Repeated {
            guard let previous else { throw EngineError.invalidMessage("A repeated poll has no previous poll") }
            return (previous, true)
        }
    }

    /// Passes the poll through, keeps the bytes, and stops before decoding a reply that repeats `previous`.
    private final class Tap: EngineTransport, @unchecked Sendable {
        struct Repeated: Error {}
        private let base: any EngineTransport
        private let previous: Exchange?
        private let lock = NSLock()
        private var exchanged: (request: Data, reply: Data)?
        var sent: (request: Data, reply: Data)? { lock.withLock { exchanged } }

        init(base: any EngineTransport, previous: Exchange?) {
            self.base = base
            self.previous = previous
        }

        func request(_ data: Data) async throws -> Data {
            let reply = try await base.request(data)
            lock.withLock { exchanged = (data, reply) }
            if let previous, previous.reply == reply, previous.request == data { throw Repeated() }
            return reply
        }
    }
}

/// A guest retries a poll a few times when its host stops answering, then gives up with the
/// usual message. Only polls and hello are retried: an answer keeps its exact request ID for
/// the player's explicit retry, and a host that left ends the table through the roster.
struct OnDeviceHostRetryPolicy {
    static let defaultDelays: [TimeInterval] = [1, 2, 4]
    let delays: [TimeInterval]
    private(set) var attempts = 0

    init(delays: [TimeInterval] = Self.defaultDelays) { self.delays = delays }

    mutating func delay(after error: Error) -> TimeInterval? {
        guard error is OnDeviceHostUnavailable, attempts < delays.count else { return nil }
        attempts += 1
        return delays[attempts - 1]
    }

    mutating func reset() { attempts = 0 }
}

/// One authenticated seat. UI changes are applied only from a current engine poll.
@MainActor
final class OnDeviceSession: ObservableObject {
    @Published private(set) var snapshot: GameSnapshot?
    @Published private(set) var matchID: String?
    @Published private(set) var seatID: String?
    @Published private(set) var pendingActionID: String?
    @Published private(set) var pendingCardID: String?
    @Published private(set) var isWorking = false
    @Published private(set) var isClosing = false
    @Published private(set) var status = "Ready"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAutoPassing = false
    @Published private(set) var autoPassStatus = ""
    /// The engine's latest save of this game (solo games on engines with `saveResume`).
    @Published private(set) var checkpoint: EngineCheckpoint?
    /// The game is over for this seat: it ended, or the player lost or left and now spectates.
    @Published private(set) var isOverForSeat = false
    /// Answer actions this game's engine accepts (its `answerActions` capability); empty on older engines.
    @Published private(set) var supportedAnswerActions: Set<String> = []
    /// Questions and trigger orders this seat asked XMage to remember this game, for the "forget" controls.
    @Published private(set) var rememberedAnswers = 0
    @Published private(set) var rememberedTriggerOrders = 0
    /// Standing instructions waiting for this seat's next answer of any kind (a preference, a reset), by type.
    private var standingActions: [String: MagicMobileOnDevice.JSONValue] = [:]
    /// Not published: it changes twice on every poll, and nothing on screen reads it.
    private var activeRefreshes = 0
    private var allowsSeatScopedAutoYield = false
    private var responding = false
    private var waitingForPolls = false
    /// Consecutive polls that returned exactly the previous poll.
    private var idlePolls = 0
    private var yieldPolicy = OnDeviceYieldPolicy()
    private var yieldTask: Task<Void, Never>?
    private var yieldGeneration = UUID()
    private var client: EngineClient?
    private var poll: MatchPoll?
    /// Local games: polls whose reply repeats `pollExchange` (the exchange behind `poll`) are not decoded again.
    private var pollReader: OnDevicePollReader?
    private var pollExchange: OnDevicePollReader.Exchange?
    private var messageLog = OnDeviceMessageLog()
    /// Presentation only: the round the board's turn labels show (the engine's turn counts every player's turn).
    private var tableRounds = TableRounds()
    private var pollingTask: Task<Void, Never>?
    private var closeEndpoint: (@MainActor () async throws -> Void)?
    private var epoch = UUID()
    private var visibilityEpoch = UUID()
    private var refreshSequence: UInt64 = 0
    private var appliedRefreshSequence: UInt64 = 0
    private var isForeground = true
    private var automaticPolling = true
    /// Set for a seat at a phone-hosted table; nil for local games.
    private var table: OnDeviceTableLink?
    /// Uptime of this seat's latest answer or concede, for prompt polling until it lands.
    private var lastActionAt: TimeInterval?
    /// Backoff between a guest's poll retries after its host stops answering (shortened by tests).
    var hostRetryDelays = OnDeviceHostRetryPolicy.defaultDelays
    private struct Submission {
        let prompt: EnginePrompt
        let answer: MagicMobileOnDevice.JSONValue
        let requestID: UUID
        let label: String
    }
    private var pending: Submission?
    /// The exact ability the player picked when activating a source with several.
    /// XMage then asks "which ability"; that follow-up is answered with this ID.
    private struct ChosenAbility: Equatable {
        let sourceID: String
        let abilityID: String
        let activationPromptID: String
    }
    private var chosenAbility: ChosenAbility?
    /// A follow-up ability prompt being answered automatically: its snapshot stays
    /// unpublished so the question never flashes on screen. Published if answering fails.
    private var heldAbilitySnapshot: (promptID: String, snapshot: GameSnapshot)?
    private var abilityAutoAnswer: Task<Void, Never>?
    /// Smart auto-pass (OnDeviceSmartPass); nil leaves every priority to the player.
    private var smartPass: OnDeviceSmartPass.Settings?
    private var smartPassTask: Task<Void, Never>?
    private var smartPassGeneration = UUID()
    /// The last prompt smart pass answered: each prompt is passed at most once, never retried.
    private var smartPassedPromptID: String?
    /// What the board is still showing; smart pass lets it finish before passing.
    lazy var presentationHold: BoardPresentationHold = .shared
    /// Full control (long-press Pass, or the controls menu): smart pass stops at every priority until this turn ends.
    @Published private(set) var fullControlTurn: Int64?
    /// A local log line was added since the last snapshot: the next poll republishes even if the game didn't change.
    private var logChanged = false

    /// `pollReader` reads polls through the same transport as `client` (local games).
    func attach(client: EngineClient, matchID: String, seatID: String, autoPoll: Bool = true,
                pollReader: OnDevicePollReader? = nil,
                allowsSeatScopedAutoYield: Bool = false, table: OnDeviceTableLink? = nil,
                answerActions: Set<String> = [], autoPassAfterCast: Bool? = nil,
                smartPass: OnDeviceSmartPass.Settings? = nil,
                close: @escaping @MainActor () async throws -> Void) async throws {
        guard self.client == nil, !isWorking else { throw EngineError.invalidMessage("Close the active game first") }
        self.client = client; self.matchID = matchID; self.seatID = seatID
        self.pollReader = pollReader; pollExchange = nil
        supportedAnswerActions = answerActions; rememberedAnswers = 0; rememberedTriggerOrders = 0; standingActions = [:]
        comboHistory = []; comboOffer = nil; comboWinForecast = nil; comboDeclined = nil; comboResult = nil
        if let autoPassAfterCast { setAutoPassAfterCast(autoPassAfterCast) }
        if devicePaceHot { queueDevicePace() }
        self.smartPass = smartPass; smartPassTask?.cancel(); smartPassTask = nil; smartPassedPromptID = nil; fullControlTurn = nil
        // Only trusted routes opt in. Every pass still uses this seat's authenticated prompt.
        self.allowsSeatScopedAutoYield = allowsSeatScopedAutoYield
        self.table = table; lastActionAt = nil
        autoPassStatus = ""; checkpoint = nil; isOverForSeat = false
        closeEndpoint = close; automaticPolling = autoPoll; epoch = UUID()
        refreshSequence = 0; appliedRefreshSequence = 0; isClosing = false
        messageLog = OnDeviceMessageLog()
        tableRounds = TableRounds()
        status = "Starting game"
        do { try await refresh() }
        catch {
            // A guest's poll loop retries the host a few times before giving up.
            guard let table, table.role == .guest, error is OnDeviceHostUnavailable else { throw error }
            status = table.waitingStatus
        }
        beginPolling()
    }

    func refresh() async throws {
        do { try await performRefresh() }
        catch { stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message); throw error }
    }

    private func performRefresh() async throws {
        guard let client, let matchID, let seatID, isForeground, !isClosing, !responding, !waitingForPolls,
              !isAutoPassing || activeRefreshes == 0 else { return }
        activeRefreshes += 1
        defer { activeRefreshes -= 1 }
        let token = epoch
        let visibility = visibilityEpoch
        refreshSequence += 1
        let sequence = refreshSequence
        let next: MatchPoll
        var exchange: OnDevicePollReader.Exchange?
        do {
            if let pollReader {
                let read = try await pollReader.poll(matchID: matchID, seatID: seatID, after: poll?.revision ?? 0,
                                                     previous: pollExchange)
                next = read.exchange.poll
                exchange = read.exchange
            } else {
                next = try await client.poll(matchID: matchID, seatID: seatID, after: poll?.revision ?? 0)
            }
        } catch {
            // Obsolete reads must not interrupt a replacement or resumed session.
            guard epoch == token, visibilityEpoch == visibility, isForeground,
                  !isClosing, !Task.isCancelled else { return }
            throw error
        }
        guard epoch == token, self.matchID == matchID, visibilityEpoch == visibility,
              isForeground, !isClosing, !Task.isCancelled else { return }
        guard next.matchID == matchID, next.seatID == seatID else { throw EngineError.unboundPeer }
        // Submission can change at the same mailbox revision. Do not let an older
        // in-flight poll restore a choice after a newer response hid it.
        if let poll, next.revision < poll.revision ||
            (next.revision == poll.revision && sequence <= appliedRefreshSequence) { return }
        // While the AI thinks, polls repeat the same board. Re-adapting and republishing
        // it every 300 ms only competes with the engine's search for the CPU.
        let unchanged = poll?.raw == next.raw && heldAbilitySnapshot == nil && snapshot != nil && !logChanged
        logChanged = false
        idlePolls = unchanged ? idlePolls + 1 : 0
        // A real change redraws whatever reads this session, including values derived from private
        // state. An unchanged poll publishes nothing (it used to redraw the whole game screen).
        if !unchanged { objectWillChange.send() }
        var nextLog = messageLog
        if !unchanged { try nextLog.ingest(next) }
        let autoAbility = chosenAbilityAnswer(for: next.prompt)
        if unchanged && autoAbility == nil {
            // Same board and prompt: keep the published snapshot.
        } else if next.phase == "closed" {
            snapshot = nil
            nextLog = OnDeviceMessageLog()
            pending = nil; pendingActionID = nil; pendingCardID = nil
        } else if next.snapshot != nil {
            var adapted = try OnDeviceSnapshotAdapter.snapshot(next, expectedSeatID: seatID, log: nextLog.entries)
            adapted.round = tableRounds.observe(adapted)
            if let autoAbility, let prompt = next.prompt {
                heldAbilitySnapshot = (prompt.id, adapted)
                pendingActionID = "auto-ability-\(autoAbility.abilityID)"; pendingCardID = autoAbility.sourceID
            } else {
                heldAbilitySnapshot = nil
                snapshot = adapted
            }
        }
        messageLog = nextLog
        poll = next
        pollExchange = exchange
        if let saved = next.checkpoint, saved != checkpoint { checkpoint = saved }
        let over = GameResumePolicy.isOver(next)
        if over != isOverForSeat { isOverForSeat = over }
        appliedRefreshSequence = max(appliedRefreshSequence, sequence)
        // A host tells its guests about each new revision, so they need not poll it constantly.
        table?.applied(revision: next.revision)
        if let pending, next.prompt?.id != pending.prompt.id || next.prompt?.revision != pending.prompt.revision {
            self.pending = nil
            if autoAbility == nil { pendingActionID = nil; pendingCardID = nil }
        }
        if let autoAbility, let prompt = next.prompt, abilityAutoAnswer == nil {
            abilityAutoAnswer = Task { [weak self] in await self?.answerChosenAbility(autoAbility, promptID: prompt.id) }
        }
        let nextStatus: String
        switch next.phase {
        case "ended": nextStatus = "Game complete"
        case "failed": nextStatus = "Game stopped"
        case "closed": nextStatus = "Game closed"
        case "starting": nextStatus = "Starting game"
        default: nextStatus = "Live"
        }
        // Assigned only on a change: a published property announces every assignment, even an equal one.
        if status != nextStatus { status = nextStatus }
        let nextError = next.raw["failure"]?["message"]?.string
        if errorMessage != nextError { errorMessage = nextError }
        if errorMessage != nil { stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message) }
        if isAutoPassing {
            if let context = yieldContext {
                if case .stop(let reason) = yieldPolicy.evaluate(context, now: ProcessInfo.processInfo.systemUptime) {
                    stopAutoPass(reason: reason.message)
                }
            } else { stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message) }
        }
        scheduleSmartPass()
        beginPolling()
    }

    /// Smart auto-pass settings changed (Settings or the phase stops sheet); applies from the next prompt.
    func setSmartPass(_ settings: OnDeviceSmartPass.Settings) {
        guard smartPass != nil else { return }
        smartPass = settings
        scheduleSmartPass()
    }

    private var currentTurn: Int64? { poll?.snapshot?["gameView"]?["turn"]?.integer }

    /// Full control is on for the turn being played.
    var isFullControl: Bool { fullControlTurn != nil && fullControlTurn == currentTurn }

    /// Turns full control for this turn on or off. Turning it on stops a smart pass that hasn't been sent yet.
    func toggleFullControl() {
        if isFullControl {
            fullControlTurn = nil
            scheduleSmartPass()
        } else {
            fullControlTurn = currentTurn
            smartPassTask?.cancel(); smartPassTask = nil; smartPassGeneration = UUID()
        }
    }

    private var smartPassSituation: OnDeviceSmartPass.Situation? {
        guard let context = yieldContext, let root = poll?.snapshot, let view = root["gameView"],
              let owner = view["players"]?.array?.first(where: { $0["playerId"]?.string == context.viewerID }) else { return nil }
        let floating = (owner["manaPool"]?.object ?? [:]).values.contains { ($0.integer ?? 0) > 0 }
        return .init(context: context, step: view["step"]?.string, hasPlay: OnDeviceSmartPass.hasPlay(view), manaFloating: floating,
                     topStackIsMine: OnDeviceSmartPass.topStackIsMine(root, viewer: context.viewerID),
                     hasResponse: OnDeviceSmartPass.hasResponse(view),
                     threatensMe: !context.emptyStack && (snapshot.map(OnDeviceSmartPass.threatensViewer) ?? false))
    }

    /// Passes this seat's ordinary priority when it has nothing to play, or nothing it stops for.
    /// The same pass a tap sends, once per prompt; a failure is left to the player, never retried.
    private func scheduleSmartPass() {
        guard let settings = smartPass, smartPassTask == nil, !isAutoPassing, !isFullControl, pending == nil, pendingActionID == nil,
              errorMessage == nil, heldAbilitySnapshot == nil, abilityAutoAnswer == nil, !isClosing,
              let situation = smartPassSituation,
              let prompt = OnDeviceSmartPass.passPrompt(situation, settings: settings),
              prompt.id != smartPassedPromptID else { return }
        let token = epoch, generation = UUID()
        smartPassGeneration = generation
        smartPassTask = Task { [weak self] in
            guard let self else { return }
            // The response lane frees right after the answer that led here.
            for _ in 0..<150 where self.isWorking || self.activeRefreshes > 0 { try? await Task.sleep(for: .milliseconds(20)) }
            await self.waitForBoardPresentation()
            // Re-check against the poll applied meanwhile: the same prompt, still a pass.
            guard !Task.isCancelled, self.epoch == token, !self.isWorking, let settings = self.smartPass,
                  self.pending == nil, self.pendingActionID == nil, !self.isAutoPassing, !self.isFullControl,
                  let situation = self.smartPassSituation,
                  let current = OnDeviceSmartPass.passPrompt(situation, settings: settings),
                  current.id == prompt.id, current.revision == prompt.revision,
                  current.id != self.smartPassedPromptID, let snapshot = self.snapshot else {
                if self.smartPassGeneration == generation { self.smartPassTask = nil }
                return
            }
            self.smartPassedPromptID = current.id
            self.messageLog.noteAutoPass(self.autoPassLabel(situation, snapshot: snapshot), id: current.id)
            self.logChanged = true
            let command = GameCommand(type: "pass_priority", gameId: situation.context.matchID,
                                      playerId: situation.context.viewerID, promptId: current.id,
                                      messageId: Int(current.revision), expectedBridgeRevision: snapshot.bridgeRevision)
            let sent = (try? await self.submit(command, label: String(localized: "Pass priority"), actionID: OnDeviceYieldPolicy.smartPassActionPrefix + current.id)) != nil
            guard self.smartPassGeneration == generation else { return }
            self.smartPassTask = nil
            // The answer's own refresh may already show the next routine priority.
            if sent { self.scheduleSmartPass() }
        }
    }

    /// What a smart pass let go by, for the game log: the top of the stack, else the step.
    private func autoPassLabel(_ situation: OnDeviceSmartPass.Situation, snapshot: GameSnapshot) -> String {
        if let top = snapshot.stackTopFirst.first { return top.displayName }
        return OnDeviceSmartPass.Step(engine: situation.step)?.title ?? String(localized: "Priority")
    }

    /// Lets the board finish what it is showing (an opponent's removal spell read at the centre, the
    /// creature it exiles) before smart pass moves the game on: first the board takes in the published
    /// snapshot, then its held effects play out, never longer than BoardPresentationHold.maximumWait.
    private func waitForBoardPresentation() async {
        // A long combo loop shows the board once a round, so there's nothing to wait for between its steps.
        guard !comboFastMode, let snapshot else { return }
        let key = BoardFXRevisionKey(snapshot: snapshot)
        let start = ProcessInfo.processInfo.systemUptime
        func elapsed() -> TimeInterval { ProcessInfo.processInfo.systemUptime - start }
        while presentationHold.ingested != key, elapsed() < BoardPresentationHold.ingestWait, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        while let until = presentationHold.until, until.timeIntervalSinceNow > 0,
              elapsed() < BoardPresentationHold.maximumWait, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(min(until.timeIntervalSinceNow, 0.1)))
        }
        // Holding a card to read it holds the pass too, as tapping the reference game's spell does.
        while presentationHold.reading, elapsed() < BoardPresentationHold.readingWait, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    var canEndTurn: Bool {
        canStartYield(.safeEndTurn)
    }

    var canEndTurnSkippingResponses: Bool { canStartYield(.endTurnSkippingResponses) }
    var canSkipToMyTurn: Bool { canStartYield(.untilMyTurn) }

    /// Availability follows the game, not the poll loop: an in-flight refresh or send
    /// must not flicker the Skip control or swallow a tap. The yield task itself waits
    /// for the session to be idle before every pass.
    private func canStartYield(_ mode: OnDeviceYieldPolicy.Mode) -> Bool {
        guard !isAutoPassing, !isClosing, pending == nil, errorMessage == nil,
              let context = yieldContext else { return false }
        return OnDeviceYieldPolicy.canStart(context, mode: mode)
    }

    /// Cancellable local scheduling of ordinary passes, not an engine skip-turn command.
    func endTurn() {
        startYield(.safeEndTurn)
    }

    func endTurnSkippingResponses() { startYield(.endTurnSkippingResponses) }
    func skipToMyTurn() { startYield(.untilMyTurn) }

    private func startYield(_ mode: OnDeviceYieldPolicy.Mode) {
        guard canStartYield(mode), let context = yieldContext,
              yieldPolicy.start(context, now: ProcessInfo.processInfo.systemUptime, mode: mode) else { return }
        isAutoPassing = true
        autoPassStatus = mode.status
        yieldGeneration = UUID()
        let generation = yieldGeneration
        let token = epoch
        yieldTask = Task { [weak self] in
            var lastPoll = ProcessInfo.processInfo.systemUptime
            do {
                while !Task.isCancelled {
                    try await self?.waitForNextPoll(since: lastPoll, interval: 0.3)
                    lastPoll = ProcessInfo.processInfo.systemUptime
                    guard let self, self.epoch == token, self.yieldGeneration == generation, self.isAutoPassing else { return }
                    guard !self.isWorking, self.activeRefreshes == 0 else { continue }
                    // A new authenticated poll, never just the rendered snapshot, authorizes each pass.
                    try await self.refresh()
                    lastPoll = ProcessInfo.processInfo.systemUptime
                    guard !Task.isCancelled, self.epoch == token, self.yieldGeneration == generation,
                          self.isAutoPassing else { return }
                    guard !self.isWorking, self.activeRefreshes == 0 else { continue }
                    guard let context = self.yieldContext else {
                        self.stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message); return
                    }
                    switch self.yieldPolicy.evaluate(context, now: ProcessInfo.processInfo.systemUptime) {
                    case .wait: continue
                    case .stop(let reason): self.stopAutoPass(reason: reason.message); return
                    case .pass(let identity):
                        guard self.pending == nil, let prompt = self.poll?.prompt,
                              prompt.id == identity.id, prompt.revision == identity.revision,
                              let snapshot = self.snapshot else { continue }
                        self.yieldPolicy.recordPass(identity)
                        let command = GameCommand(type: "pass_priority", gameId: context.matchID,
                                                  playerId: context.viewerID, promptId: prompt.id,
                                                  messageId: Int(prompt.revision), expectedBridgeRevision: snapshot.bridgeRevision)
                        try await self.submit(command, label: String(localized: "Pass priority"), actionID: OnDeviceYieldPolicy.yieldPassActionPrefix + prompt.id)
                    }
                }
            } catch {
                guard let self, self.yieldGeneration == generation else { return }
                // Keep uncertain pending responses for the existing explicit retry UI.
                // Scheduling never retries, guesses a new prompt, or changes request identity.
                self.stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message)
            }
        }
    }

    func stopAutoPass() {
        stopAutoPass(reason: String(localized: "Auto-pass stopped. A pass already sent may still finish."))
    }

    private func stopAutoPass(reason: String) {
        guard isAutoPassing || yieldTask != nil else { return }
        yieldGeneration = UUID(); yieldPolicy.stop(); isAutoPassing = false
        yieldTask?.cancel(); yieldTask = nil; autoPassStatus = reason
    }

    private var yieldContext: OnDeviceYieldPolicy.Context? {
        guard let poll, let root = poll.snapshot, let view = root["gameView"],
              let viewer = root["enginePlayerId"]?.string, view["myPlayerId"]?.string == viewer,
              let turn = view["turn"]?.integer, let active = view["activePlayerId"]?.string,
              let stack = view["stack"]?.object, let controls = root["controlledPlayerViews"]?.object,
              let players = view["players"]?.array,
              let owner = players.first(where: { $0["playerId"]?.string == viewer }),
              owner["isHuman"]?.bool == true,
              let priority = owner["hasPriority"]?.bool, let timer = owner["timerActive"]?.bool else { return nil }
        let prompt = poll.prompt.map {
            OnDeviceYieldPolicy.Prompt(id: $0.id, revision: $0.revision, kind: $0.kind,
                                       selectMode: $0.payload["selectMode"]?.string,
                                       allowsBoolean: $0.responseTypes.contains("boolean"), submitted: $0.submitted,
                                       manaPlayerID: $0.payload["manaPlayerId"]?.string)
        }
        // `controlled` is only a viewer marker upstream, not turn-control proof.
        // A routed self-priority prompt and active timer are required to send.
        let selfAuthority = controls.isEmpty && (!priority || timer) && (prompt == nil || priority)
        // A skip that passes responses still stops for an opponent's removal or sweeper, if you asked to.
        let threat = !stack.isEmpty && (smartPass ?? .load()).stopForThreats && (snapshot.map(OnDeviceSmartPass.threatensViewer) ?? false)
        return .init(matchID: poll.matchID, seatID: poll.seatID, viewerID: viewer, activePlayerID: active,
                     turn: turn, phase: poll.phase, localHumanEnabled: allowsSeatScopedAutoYield,
                     foreground: isForeground && !isClosing, emptyStack: stack.isEmpty,
                     selfAuthority: selfAuthority, resyncRequired: poll.resyncRequired, prompt: prompt, threatToMe: threat)
    }

    func send(action: LegalAction) async throws {
        stopAutoPass()
        guard let snapshot, let current = snapshot.legalActions?.first(where: { $0.id == action.id }) else {
            throw EngineError.invalidMessage("This action is no longer available")
        }
        let command = GameCommand(action: current, gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision)
        try await send(command, label: current.label, actionID: current.id)
    }

    /// Passing priority after casting a spell (Settings), sent with this seat's next answer.
    func setAutoPassAfterCast(_ enabled: Bool) {
        guard supportedAnswerActions.contains("autoPassAfterCast") else { return }
        standingActions["autoPassAfterCast"] = .object(["type": .string("autoPassAfterCast"), "enabled": .bool(enabled)])
    }

    /// The phone is hot and the engine runs on it: AI seats think for less time (answer action devicePace, engine
    /// release C). The root sets it from DeviceHeat; it rides on the next answer, and again after every attach.
    var devicePaceHot = false { didSet { if devicePaceHot != oldValue { queueDevicePace() } } }

    private func queueDevicePace() {
        guard supportedAnswerActions.contains("devicePace") else { return }
        standingActions["devicePace"] = .object(["type": .string("devicePace"), "hot": .bool(devicePaceHot)])
    }

    /// Forget every remembered answer (asked again from the next one).
    func forgetRememberedAnswers() {
        guard supportedAnswerActions.contains("resetRememberedAnswers") else { return }
        standingActions["resetRememberedAnswers"] = .object(["type": .string("resetRememberedAnswers")])
        rememberedAnswers = 0
    }

    /// Forget every remembered trigger order.
    func forgetTriggerOrder() {
        guard supportedAnswerActions.contains("resetTriggerOrder") else { return }
        standingActions["resetTriggerOrder"] = .object(["type": .string("resetTriggerOrder")])
        rememberedTriggerOrders = 0
    }

    func send(_ command: GameCommand, label: String, actionID: String) async throws {
        stopAutoPass()
        let decision = snapshot
        try await submit(command, label: label, actionID: actionID)
        noteComboStep(command, label: label, actionID: actionID, decision: decision)
    }

    // MARK: Combo loop shortcut (ComboLoop)

    /// Solo games only: the root turns it on for games against the AI.
    var comboLoopsAllowed = false { didSet { if !comboLoopsAllowed { comboHistory = []; comboOffer = nil; comboWinForecast = nil } } }
    /// A round the player has made three times in a row this turn, offered for repeating.
    @Published private(set) var comboOffer: [ComboStep]?
    /// Whether repeating the offered round ends the game: "Until they lose" is offered only then.
    @Published private(set) var comboWinForecast: ComboWinForecast?
    /// Repeating a round: how far it has got, and the last few rounds and notes.
    @Published private(set) var comboRun: ComboRun?
    /// The line shown when repeating stops: rounds, life changes and why.
    @Published var comboResult: String?
    /// What the board shows while a loop repeats: the game without the prompts the repeats answer, updated after every
    /// step for a short run (so its effects play) and once a round for a long one.
    @Published private(set) var comboPresented: GameSnapshot?
    struct ComboRun: Equatable {
        var round: [ComboStep]
        var mode: ComboRepeat
        var done: Int
        var lines: [String] = []
    }
    /// The board's snapshot: the live game, or the repeats' quiet copy while a loop runs.
    var presentedSnapshot: GameSnapshot? { comboRun == nil ? snapshot : (comboPresented ?? snapshot?.withoutPrompts) }
    private var comboHistory: [(step: ComboStep, turn: Int, standings: [String: ComboWinForecast.Standing])] = []
    private var comboDeclined: [ComboStep]?
    private var comboStopRequested = false
    private var comboFastMode = false
    /// Rounds a winning loop still needs, while it finishes behind its curtain; nil otherwise.
    @Published private(set) var comboFinishing: Int?
    private var comboTask: Task<Void, Never>?

    private func noteComboStep(_ command: GameCommand, label: String, actionID: String, decision: GameSnapshot?) {
        guard comboLoopsAllowed, comboRun == nil else { return }
        switch ComboLoop.note(command: command, label: label, actionID: actionID, snapshot: decision) {
        case .ignore:
            return
        case .breaks:
            comboHistory = []; comboOffer = nil; comboWinForecast = nil
        case .step(let step):
            let turn = decision?.turn ?? 0
            // A loop is offered only for rounds made in one turn.
            if let last = comboHistory.last, last.turn != turn { comboHistory = [] }
            comboHistory.append((step, turn, decision.map(ComboWinForecast.standings) ?? [:]))
            if comboHistory.count > ComboLoop.historyLimit { comboHistory.removeFirst(comboHistory.count - ComboLoop.historyLimit) }
            let round = ComboLoop.cycle(in: comboHistory.map(\.step))
            comboOffer = round != nil && round != comboDeclined ? round : nil
            comboWinForecast = comboOffer.flatMap { round in
                // The opponents' standings at the start of each of the last rounds.
                let length = round.count
                let starts = stride(from: comboHistory.count - length * ComboLoop.repeatsToOffer, to: comboHistory.count, by: length)
                    .filter { $0 >= 0 }.map { comboHistory[$0].standings }
                guard let current = snapshot ?? decision else { return nil }
                return ComboWinForecast.forecast(starts: starts, opponentsCanRespond: ComboWinForecast.opponentsCanRespond(current))
            }
        }
    }

    /// The player said no to this round: it isn't offered again until they make a different one.
    func declineComboLoop() {
        comboDeclined = comboOffer
        comboOffer = nil
        comboWinForecast = nil
    }

    /// Repeats the offered round: a number of times, until a step can't be taken, or until every opponent has lost (at
    /// most ComboLoop.maxRepeats rounds).
    func startComboLoop(_ mode: ComboRepeat) {
        guard let round = comboOffer, comboRun == nil, let start = snapshot else { return }
        // "Until they lose" only runs when the rounds so far show it wins; it then goes straight to the end.
        if mode == .untilWin, comboWinForecast?.canFinish != true { return }
        comboFinishing = mode == .untilWin ? comboWinForecast?.rounds : nil
        comboOffer = nil
        comboWinForecast = nil
        comboResult = nil
        comboStopRequested = false
        comboPresented = start.withoutPrompts
        comboRun = ComboRun(round: round, mode: mode, done: 0)
        comboTask = Task { [weak self] in await self?.runComboLoop(round, mode: mode, start: start) }
    }

    func stopComboLoop() { comboStopRequested = true }

    private enum ComboWait {
        case ready(ComboReplay)
        case stop(ComboLoopStop)
    }

    private func noteComboLine(_ line: String) {
        guard var run = comboRun else { return }
        run.lines = Array((run.lines + [line]).suffix(3))
        comboRun = run
    }

    private func runComboLoop(_ round: [ComboStep], mode: ComboRepeat, start: GameSnapshot) async {
        // A long run skips the board's effects and shows the board once a round; a short one plays them at a pace you can follow.
        let watch = mode.watchable
        comboFastMode = !watch
        BoardFXLevel.suppressedForLoop = !watch
        defer { BoardFXLevel.suppressedForLoop = false; comboFastMode = false }
        let limit = min(mode.count ?? comboFinishing.map { $0 + 2 } ?? ComboLoop.maxRepeats, ComboLoop.maxRepeats)
        var rounds = 0, unchanged = 0
        var lastDigest = ComboLoop.digest(start)
        var prefer: [Int: [String]] = [:]
        var stop = ComboLoopStop.finished
        repeating: while rounds < limit {
            var chosen: [String] = []
            for (index, step) in round.enumerated() {
                switch await waitForComboStep(step, prefer: prefer[index] ?? []) {
                case .stop(let reason):
                    stop = reason
                    break repeating
                case .ready(let replay):
                    do { try await submit(replay.command, label: replay.label, actionID: replay.actionID) }
                    catch { stop = .failed(error.localizedDescription); break repeating }
                    if !replay.chosenNames.isEmpty {
                        prefer[index] = replay.chosenNames
                        if chosen.isEmpty || step.targets.contains(where: { $0.controller == "opponent" }) { chosen = replay.chosenNames }
                    }
                    if let swap = replay.retargeted { noteComboLine(String(localized: "\(swap.from) is gone, now \(swap.to)")) }
                    if watch, let current = snapshot { comboPresented = current.withoutPrompts }
                }
            }
            rounds += 1
            comboRun?.done = rounds
            noteComboLine(ComboLoop.roundLine(rounds, round, chosen: chosen))
            guard let current = snapshot else { break }
            if comboFinishing == nil { comboPresented = current.withoutPrompts }
            if current.isCompleted { stop = .gameOver; break }
            if watch {
                await waitForBoardPresentation()
                try? await Task.sleep(for: .milliseconds(450))
            }
            // Open-ended repeats stop a loop that has stopped doing anything visible; a count simply runs out.
            if mode.count == nil {
                let digest = ComboLoop.digest(current)
                unchanged = digest == lastDigest ? unchanged + 1 : 0
                lastDigest = digest
                if unchanged >= ComboLoop.unchangedRoundsToStop { stop = .nothingChanged; break }
            }
        }
        if mode.count == nil, stop == .finished { stop = comboFinishing != nil ? .didNotFinish(rounds) : .reachedLimit }
        let summary = ComboLoop.summary(rounds: rounds, before: start, after: snapshot ?? start)
        switch stop {
        case .finished, .gameOver:
            comboResult = summary
        case .stepMissing(let why) where mode == .untilCant && rounds > 0:
            comboResult = String(localized: "\(summary), until it couldn't go on: \(why).")
        default:
            comboResult = "\(summary). \(stop.message)"
        }
        comboRun = nil
        comboPresented = nil
        comboFinishing = nil
        comboHistory = []
        comboDeclined = round
        comboTask = nil
    }

    /// Waits for this step's answer to be possible: the session idle, the player's own triggers resolved when the step
    /// was taken with an empty stack (passing priority for them), and the step among the choices. Stops when the game
    /// ends, an opponent responds, the player is asked something the round doesn't answer, or nothing comes.
    private func waitForComboStep(_ step: ComboStep, prefer: [String]) async -> ComboWait {
        let started = Date()
        var askedSince: Date?
        var passedFor: String?
        while Date().timeIntervalSince(started) < 45 {
            if comboStopRequested || Task.isCancelled || isClosing { return .stop(.stoppedByPlayer) }
            if let current = snapshot {
                if current.isCompleted || isOverForSeat { return .stop(.gameOver) }
                let idle = !isWorking && !isAutoPassing && pendingActionID == nil && pending == nil && smartPassTask == nil
                    && heldAbilitySnapshot == nil && abilityAutoAnswer == nil
                if idle {
                    if ComboLoop.opponentResponded(current) { return .stop(.opponentResponded) }
                    let asked = current.legalActions?.isEmpty == false || current.promptEnvelopeV2.map { current.isViewer($0.playerId) } == true
                    if ComboLoop.waitsForStack(step, in: current) {
                        // The round's own triggers are still resolving: pass for them, once per prompt.
                        let key = current.promptEnvelopeV2?.id ?? "\(current.bridgeRevision ?? 0)"
                        if let pass = ComboLoop.pass(in: current), passedFor != key {
                            passedFor = key
                            askedSince = nil
                            do { try await submit(pass.command, label: pass.label, actionID: "combo-loop-pass-\(key)") }
                            catch { return .stop(.failed(error.localizedDescription)) }
                            continue
                        }
                        if asked, ComboLoop.pass(in: current) == nil {
                            askedSince = askedSince ?? Date()
                            if Date().timeIntervalSince(askedSince!) > 3 { return .stop(.stepMissing(String(localized: "a choice the loop doesn't make came up"))) }
                        }
                    } else if let replay = ComboLoop.command(for: step, in: current, prefer: prefer) {
                        return .ready(replay)
                    } else if asked {
                        askedSince = askedSince ?? Date()
                        if Date().timeIntervalSince(askedSince!) > 3 { return .stop(.stepMissing(ComboLoop.missing(step))) }
                    } else {
                        askedSince = nil
                    }
                }
            }
            // A long or winning run checks back quickly; nothing is drawn between its rounds.
            try? await Task.sleep(for: .milliseconds(comboFastMode ? 40 : 120))
        }
        return .stop(.stepMissing(ComboLoop.missing(step)))
    }

    private func submit(_ command: GameCommand, label: String, actionID: String) async throws {
        let token = epoch
        try await acquireResponseSlot()
        defer { if epoch == token { isWorking = false; responding = false; waitingForPolls = false } }
        guard client != nil, let matchID, seatID != nil, let snapshot, let prompt = poll?.prompt,
              !isClosing, pendingActionID == nil, isForeground, !snapshot.isCompleted,
              !["ended", "failed", "closed"].contains(poll?.phase ?? ""),
              command.gameId == matchID, command.playerId == snapshot.viewerID,
              command.expectedBridgeRevision == nil || command.expectedBridgeRevision == snapshot.bridgeRevision else {
            throw EngineError.invalidMessage("The game or decision changed. Refresh before choosing again.")
        }
        let requested = (command.answerActions ?? []).filter(supportedAnswerActions.contains)
        let standing = Array(standingActions.values)
        let answer = OnDevicePromptAdapter.answer(
            try OnDevicePromptAdapter.answer(for: command, prompt: prompt, viewerPlayerID: snapshot.viewerID),
            with: try OnDevicePromptAdapter.answerActions(requested, command: command, prompt: prompt) + standing)
        if ["make_mana", "activate_ability", "play_land", "cast_spell"].contains(command.type), let ability = command.abilityId,
           let source = command.sourceInstanceId ?? command.cardInstanceId {
            chosenAbility = ChosenAbility(sourceID: source, abilityID: ability, activationPromptID: prompt.id)
        } else if command.type != "choose_ability" {
            chosenAbility = nil
        }
        pending = Submission(prompt: prompt, answer: answer, requestID: UUID(), label: label)
        pendingActionID = actionID; pendingCardID = command.cardInstanceId ?? command.sourceInstanceId
        try await performPendingResponse()
        // Delivered: the standing instructions went with it, and what was remembered is counted for the forget controls.
        if epoch == token {
            // One changed meanwhile (a setting flipped during the call) is a new value and stays queued.
            standingActions = standingActions.filter { !standing.contains($0.value) }
            if requested.contains("rememberAnswer") { rememberedAnswers += 1 }
            if requested.contains("rememberTriggerFirst") { rememberedTriggerOrders += 1 }
        }
    }

    func retryPending() async throws {
        stopAutoPass()
        let requestID = pending?.requestID
        let token = epoch
        try await acquireResponseSlot()
        defer { if epoch == token { isWorking = false; responding = false; waitingForPolls = false } }
        guard let pending, pending.requestID == requestID,
              poll?.prompt?.id == pending.prompt.id, poll?.prompt?.revision == pending.prompt.revision,
              !["ended", "failed", "closed"].contains(poll?.phase ?? "") else {
            throw EngineError.invalidMessage("There is no pending response to retry")
        }
        try await performPendingResponse()
    }

    /// Reserve the response lane before suspending so periodic/manual refreshes
    /// cannot overtake the tap. Existing polls finish; callers then revalidate
    /// their original command or retry identity against the newly applied poll.
    private func acquireResponseSlot() async throws {
        guard !isWorking, !isClosing, isForeground, client != nil else {
            throw EngineError.invalidMessage("Wait for the current operation before responding")
        }
        let token = epoch
        isWorking = true
        waitingForPolls = true
        do {
            while activeRefreshes > 0 {
                try Task.checkCancellation()
                guard epoch == token, isForeground, !isClosing else {
                    throw EngineError.invalidMessage("The game changed while waiting to respond")
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()
            guard epoch == token, isForeground, !isClosing else {
                throw EngineError.invalidMessage("The game changed while waiting to respond")
            }
        } catch {
            if epoch == token { isWorking = false; waitingForPolls = false }
            throw error
        }
    }

    private func performPendingResponse() async throws {
        guard let pending, let client, let matchID, let seatID else {
            throw EngineError.invalidMessage("There is no pending response to retry")
        }
        let token = epoch
        var responseAcknowledged = false
        do {
            responding = true
            waitingForPolls = false
            noteAction()
            _ = try await client.respond(matchID: matchID, seatID: seatID, prompt: pending.prompt,
                                         answer: pending.answer, requestID: pending.requestID)
            responseAcknowledged = true
            responding = false
            guard epoch == token else { return }
            errorMessage = nil; status = "\(pending.label) sent; waiting for XMage"
            try await refresh()
        } catch {
            responding = false
            if epoch == token {
                errorMessage = error.localizedDescription
                // An engine rejection is certain. A transport timeout or busy RPC is not:
                // retain the exact request ID and answer for a safe user-triggered retry.
                // A rejected follow-up poll cannot retract an acknowledged answer.
                if !responseAcknowledged, case EngineError.rejected(let code, _) = error, code != "rpc_busy" {
                    self.pending = nil; pendingActionID = nil; pendingCardID = nil
                    try? await refresh()
                }
            }
            throw error
        }
    }

    /// Only a fresh ability prompt that offers the exact chosen ability qualifies. Anything
    /// else forgets the choice. Ability IDs are unique within a game; the row's `sourceId`
    /// can name a half of an MDFC, split or adventure card rather than the whole card, so
    /// it is not compared.
    private func chosenAbilityAnswer(for prompt: EnginePrompt?) -> ChosenAbility? {
        guard let chosen = chosenAbility, let prompt else { return nil }
        if prompt.id == chosen.activationPromptID { return nil }
        guard ["CHOOSE_ABILITY", "PICK_ABILITY"].contains(prompt.kind), !prompt.submitted,
              let rows = prompt.payload["abilities"]?.array,
              rows.contains(where: { $0["id"]?.string == chosen.abilityID }) else {
            chosenAbility = nil
            return nil
        }
        return chosen
    }

    private func answerChosenAbility(_ chosen: ChosenAbility, promptID: String) async {
        defer { abilityAutoAnswer = nil }
        // The activation's own response slot releases right after its refresh.
        for _ in 0..<150 where isWorking { try? await Task.sleep(for: .milliseconds(20)) }
        chosenAbility = nil
        guard let matchID, let snapshot, poll?.prompt?.id == promptID else { return publishHeldAbilityPrompt() }
        let command = GameCommand(type: "choose_ability", gameId: matchID, playerId: snapshot.viewerID,
                                  abilityId: chosen.abilityID, promptId: promptID,
                                  messageId: poll?.prompt.map { Int($0.revision) })
        pendingActionID = nil
        do {
            try await submit(command, label: String(localized: "Choose ability"), actionID: "auto-ability-\(chosen.abilityID)")
            heldAbilitySnapshot = nil
        } catch {
            publishHeldAbilityPrompt()
        }
    }

    /// Show the held ability prompt so the player can answer it by hand.
    private func publishHeldAbilityPrompt() {
        if let held = heldAbilitySnapshot, poll?.prompt?.id == held.promptID { snapshot = held.snapshot }
        heldAbilitySnapshot = nil
        if pendingActionID?.hasPrefix("auto-ability-") == true { pendingActionID = nil; pendingCardID = nil }
    }

    /// This seat concedes. XMage records the loss; in a pod the others play on and this seat
    /// keeps polling as a spectator. An engine without the operation rejects it as unknown.
    func concede() async throws {
        stopAutoPass()
        guard let client, let matchID, let seatID, !isClosing,
              !["ended", "failed", "closed"].contains(poll?.phase ?? "") else {
            throw EngineError.invalidMessage("This game is already over.")
        }
        abilityAutoAnswer?.cancel(); abilityAutoAnswer = nil
        smartPassTask?.cancel(); smartPassTask = nil
        chosenAbility = nil; heldAbilitySnapshot = nil
        noteAction()
        try await client.concede(matchID: matchID, seatID: seatID)
        // The engine retracted this seat's open question; nothing sent earlier can still apply.
        pending = nil; pendingActionID = nil; pendingCardID = nil
        errorMessage = nil; status = "Conceded"
        try? await refresh()
        beginPolling()
    }

    func close() async throws {
        comboStopRequested = true; comboTask?.cancel(); comboHistory = []; comboOffer = nil; comboWinForecast = nil
        stopAutoPass()
        smartPassTask?.cancel(); smartPassTask = nil
        abilityAutoAnswer?.cancel(); abilityAutoAnswer = nil
        chosenAbility = nil; heldAbilitySnapshot = nil
        guard !isWorking else { throw EngineError.invalidMessage("Wait for the current operation before closing") }
        guard let closeEndpoint else { return }
        isWorking = true; isClosing = true; pollingTask?.cancel(); pollingTask = nil
        status = "Closing game"
        epoch = UUID()
        defer { isWorking = false }
        do { try await closeEndpoint() }
        catch {
            errorMessage = error.localizedDescription
            status = "Closing interrupted. Leave again to retry cleanup."
            throw error
        }
        isClosing = false
        refreshSequence = 0; appliedRefreshSequence = 0
        epoch = UUID(); client = nil; matchID = nil; seatID = nil; poll = nil; snapshot = nil
        pollReader = nil; pollExchange = nil
        table = nil; lastActionAt = nil; checkpoint = nil; isOverForSeat = false
        messageLog = OnDeviceMessageLog()
        tableRounds = TableRounds()
        self.closeEndpoint = nil; pending = nil; pendingActionID = nil; pendingCardID = nil; errorMessage = nil; status = "Ready"
    }

    func setForeground(_ value: Bool) {
        if isForeground != value { visibilityEpoch = UUID() }
        if !value { stopAutoPass(); smartPassTask?.cancel(); smartPassTask = nil }
        isForeground = value
        if value { beginPolling() }
        else {
            pollingTask?.cancel(); pollingTask = nil
            if !isClosing, client != nil, !["ended", "failed", "closed"].contains(poll?.phase ?? "") {
                status = "Paused while this app is in the background"
            }
        }
    }

    private func beginPolling() {
        guard pollingTask == nil, automaticPolling, client != nil, isForeground, !isClosing,
              !["ended", "failed", "closed"].contains(poll?.phase ?? "") else { return }
        pollingTask = Task { [weak self] in
            var hostRetries = OnDeviceHostRetryPolicy(delays: self?.hostRetryDelays ?? OnDeviceHostRetryPolicy.defaultDelays)
            var lastPoll = ProcessInfo.processInfo.systemUptime
            // A new loop (attach, return to the foreground, a manual refresh) polls on the short
            // timer first, so a guest catches up on notices it could not receive meanwhile.
            var firstPoll = true, retryNow = false
            while !Task.isCancelled {
                do {
                    let interval = OnDeviceLocalPollSchedule.interval(idlePolls: self?.idlePolls ?? 0,
                                                                      awaitingPlayer: self?.awaitsLocalAnswer ?? false,
                                                                      stackChain: self?.inStackChain ?? false)
                    if firstPoll { try await Task.sleep(for: .seconds(min(interval, OnDeviceLocalPollSchedule.idle))) }
                    else if !retryNow { try await self?.waitForNextPoll(since: lastPoll, interval: interval) }
                    firstPoll = false; retryNow = false
                    guard let self, !Task.isCancelled else { return }
                    if self.isAutoPassing { lastPoll = ProcessInfo.processInfo.systemUptime; continue }
                    try await self.refresh()
                    lastPoll = ProcessInfo.processInfo.systemUptime
                    hostRetries.reset()
                    guard !Task.isCancelled else { return }
                    if ["ended", "failed", "closed"].contains(self.poll?.phase ?? "") {
                        self.pollingTask = nil
                        return
                    }
                } catch {
                    lastPoll = ProcessInfo.processInfo.systemUptime
                    guard let self, !Task.isCancelled else { return }
                    // A lost host answer: poll again (never re-send an answer) before giving up.
                    if let table = self.table, table.role == .guest, let delay = hostRetries.delay(after: error) {
                        self.status = table.waitingStatus
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        retryNow = true
                        continue
                    }
                    self.pollingTask = nil
                    self.errorMessage = error.localizedDescription; self.status = "Updates interrupted. Refresh to retry."
                    return
                }
            }
        }
    }

    /// The stack is resolving shortly after this seat's own answer (OnDeviceLocalPollSchedule.chain).
    private var inStackChain: Bool {
        guard let lastActionAt, !(snapshot?.xmage?.stack.isEmpty ?? true) else { return false }
        return ProcessInfo.processInfo.systemUptime - lastActionAt < OnDeviceLocalPollSchedule.chainWindow
    }

    /// Local games poll on a short timer. A guest at a phone-hosted table waits for its
    /// host's revision notice, polls promptly while its own answer is outstanding, and otherwise
    /// polls only on the heartbeat.
    private func waitForNextPoll(since lastPoll: TimeInterval, interval: TimeInterval) async throws {
        guard let table, table.role == .guest else {
            // The long wait (the engine is waiting on this player) ends as soon as an answer goes out
            // or the board changes, so the next poll is prompt again.
            let action = lastActionAt
            var remaining = interval
            while remaining > 0 {
                let step = min(remaining, OnDeviceLocalPollSchedule.active)
                try await Task.sleep(for: .seconds(step))
                remaining -= step
                if lastActionAt != action || idlePolls < OnDeviceLocalPollSchedule.idleAfter { return }
            }
            return
        }
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let step = OnDeviceGuestPollSchedule.next(
                hostAnnounces: table.hostAnnounces, noticedRevision: table.noticedRevision, appliedRevision: poll?.revision,
                awaitingAnswer: pending != nil || abilityAutoAnswer != nil, sinceAction: lastActionAt.map { now - $0 },
                sinceLastPoll: now - lastPoll, spacing: interval)
            switch step {
            case .poll(let delay):
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) } else { await Task.yield() }
                try Task.checkCancellation()
                return
            case .awaitNotice(let timeout):
                await table.waitForNotice(timeout: timeout)
                try Task.checkCancellation()
            }
        }
    }

    /// A local game (no table) whose engine is waiting on this player: nothing can change until they
    /// answer. A hosted table never qualifies, because other people act at any time.
    private var awaitsLocalAnswer: Bool {
        guard table == nil, pending == nil, abilityAutoAnswer == nil, !isAutoPassing, !responding,
              let prompt = poll?.prompt, !prompt.submitted, poll?.phase != "starting" else { return false }
        return true
    }

    /// An answer or concede is on its way: a waiting guest polls promptly until it lands.
    private func noteAction() {
        lastActionAt = ProcessInfo.processInfo.systemUptime
        table?.wake()
    }
}
