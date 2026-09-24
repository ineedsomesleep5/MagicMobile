import Foundation
import Combine
import MagicMobileOnDevice

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
    @Published private var activeRefreshes = 0
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
    private var messageLog = OnDeviceMessageLog()
    private var pollingTask: Task<Void, Never>?
    private var closeEndpoint: (@MainActor () async throws -> Void)?
    private var epoch = UUID()
    private var visibilityEpoch = UUID()
    private var refreshSequence: UInt64 = 0
    private var appliedRefreshSequence: UInt64 = 0
    private var isForeground = true
    private var automaticPolling = true
    private var reconnectsAutomatically = false
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

    func attach(client: EngineClient, matchID: String, seatID: String, autoPoll: Bool = true,
                allowsSeatScopedAutoYield: Bool = false, reconnectsAutomatically: Bool = false,
                close: @escaping @MainActor () async throws -> Void) async throws {
        guard self.client == nil, !isWorking else { throw EngineError.invalidMessage("Close the active game first") }
        self.client = client; self.matchID = matchID; self.seatID = seatID
        // Only trusted routes opt in. Every pass still uses this seat's authenticated prompt.
        self.allowsSeatScopedAutoYield = allowsSeatScopedAutoYield
        self.reconnectsAutomatically = reconnectsAutomatically
        autoPassStatus = ""
        closeEndpoint = close; automaticPolling = autoPoll; epoch = UUID()
        refreshSequence = 0; appliedRefreshSequence = 0; isClosing = false
        messageLog = OnDeviceMessageLog()
        status = "Starting game"
        do { try await refresh() }
        catch {
            guard reconnectsAutomatically, error is URLError else { throw error }
            status = "Reconnecting…"
            errorMessage = "Connection interrupted. Reconnecting to your game."
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
        do {
            next = try await client.poll(matchID: matchID, seatID: seatID, after: poll?.revision ?? 0)
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
        let unchanged = poll?.raw == next.raw && heldAbilitySnapshot == nil && snapshot != nil
        idlePolls = unchanged ? idlePolls + 1 : 0
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
            let adapted = try OnDeviceSnapshotAdapter.snapshot(next, expectedSeatID: seatID, log: nextLog.entries)
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
        appliedRefreshSequence = max(appliedRefreshSequence, sequence)
        if let pending, next.prompt?.id != pending.prompt.id || next.prompt?.revision != pending.prompt.revision {
            self.pending = nil
            if autoAbility == nil { pendingActionID = nil; pendingCardID = nil }
        }
        if let autoAbility, let prompt = next.prompt, abilityAutoAnswer == nil {
            abilityAutoAnswer = Task { [weak self] in await self?.answerChosenAbility(autoAbility, promptID: prompt.id) }
        }
        switch next.phase {
        case "ended": status = "Game complete"
        case "failed": status = "Game stopped"
        case "closed": status = "Game closed"
        case "starting": status = "Starting game"
        default: status = "Live"
        }
        errorMessage = next.raw["failure"]?["message"]?.string
        if errorMessage != nil { stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message) }
        if isAutoPassing {
            if let context = yieldContext {
                if case .stop(let reason) = yieldPolicy.evaluate(context, now: ProcessInfo.processInfo.systemUptime) {
                    stopAutoPass(reason: reason.message)
                }
            } else { stopAutoPass(reason: OnDeviceYieldPolicy.StopReason.interrupted.message) }
        }
        beginPolling()
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
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(300))
                    guard let self, self.epoch == token, self.yieldGeneration == generation, self.isAutoPassing else { return }
                    guard !self.isWorking, self.activeRefreshes == 0 else { continue }
                    // A new authenticated poll, never just the rendered snapshot, authorizes each pass.
                    try await self.refresh()
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
                        try await self.submit(command, label: String(localized: "Pass priority"), actionID: "auto-pass-\(prompt.id)")
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
        return .init(matchID: poll.matchID, seatID: poll.seatID, viewerID: viewer, activePlayerID: active,
                     turn: turn, phase: poll.phase, localHumanEnabled: allowsSeatScopedAutoYield,
                     foreground: isForeground && !isClosing, emptyStack: stack.isEmpty,
                     selfAuthority: selfAuthority, resyncRequired: poll.resyncRequired, prompt: prompt)
    }

    func send(action: LegalAction) async throws {
        stopAutoPass()
        guard let snapshot, let current = snapshot.legalActions?.first(where: { $0.id == action.id }) else {
            throw EngineError.invalidMessage("This action is no longer available")
        }
        let command = GameCommand(
            type: current.type, gameId: snapshot.id, playerId: current.playerId,
            cardInstanceId: current.cardInstanceId, sourceInstanceId: current.sourceInstanceId,
            abilityId: current.abilityId, promptId: current.promptId, messageId: current.messageId,
            choiceIds: current.choiceIds, targetIds: current.targetIds, cardInstanceIds: current.cardInstanceIds,
            modeIds: current.modeIds, pile: current.pile?.value, amount: current.amount, amounts: current.amounts,
            orderedIds: current.orderedIds, useCommandZone: current.useCommandZone,
            manaType: current.manaType, manaTypes: current.manaTypes, playerIds: current.playerIds,
            confirmed: current.confirmed, pay: current.pay, sourceZone: current.sourceZone,
            fromZone: current.sourceZone, cardName: current.cardName, attackers: current.attackers,
            blockers: current.blockers, expectedBridgeRevision: snapshot.bridgeRevision
        )
        try await send(command, label: current.label, actionID: current.id)
    }

    func send(_ command: GameCommand, label: String, actionID: String) async throws {
        stopAutoPass()
        try await submit(command, label: label, actionID: actionID)
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
        let answer = try OnDevicePromptAdapter.answer(for: command, prompt: prompt, viewerPlayerID: snapshot.viewerID)
        if ["make_mana", "activate_ability", "play_land", "cast_spell"].contains(command.type), let ability = command.abilityId,
           let source = command.sourceInstanceId ?? command.cardInstanceId {
            chosenAbility = ChosenAbility(sourceID: source, abilityID: ability, activationPromptID: prompt.id)
        } else if command.type != "choose_ability" {
            chosenAbility = nil
        }
        pending = Submission(prompt: prompt, answer: answer, requestID: UUID(), label: label)
        pendingActionID = actionID; pendingCardID = command.cardInstanceId ?? command.sourceInstanceId
        try await performPendingResponse()
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

    func close() async throws {
        stopAutoPass()
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
        messageLog = OnDeviceMessageLog()
        self.closeEndpoint = nil; pending = nil; pendingActionID = nil; pendingCardID = nil; errorMessage = nil; status = "Ready"
    }

    func setForeground(_ value: Bool) {
        if isForeground != value { visibilityEpoch = UUID() }
        if !value { stopAutoPass() }
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
            var failures = 0
            while !Task.isCancelled {
                do {
                    let idle = (self?.idlePolls ?? 0) >= 3
                    try await Task.sleep(for: .milliseconds(self?.reconnectsAutomatically == true ? 1000 : idle ? 600 : 300))
                    guard let self, !Task.isCancelled else { return }
                    if self.isAutoPassing { continue }
                    try await self.refresh()
                    failures = 0
                    guard !Task.isCancelled else { return }
                    if ["ended", "failed", "closed"].contains(self.poll?.phase ?? "") {
                        self.pollingTask = nil
                        return
                    }
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    if self.reconnectsAutomatically, error is URLError {
                        failures += 1
                        self.status = "Reconnecting…"
                        self.errorMessage = "Connection interrupted. Reconnecting to your game."
                        do { try await Task.sleep(for: .seconds(min(10, failures * 2))) } catch { return }
                        continue
                    }
                    self.pollingTask = nil
                    self.errorMessage = error.localizedDescription; self.status = "Updates interrupted. Refresh to retry."
                    return
                }
            }
        }
    }
}
