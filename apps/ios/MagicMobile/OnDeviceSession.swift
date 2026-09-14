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
    private var client: EngineClient?
    private var poll: MatchPoll?
    private var messageLog = OnDeviceMessageLog()
    private var pollingTask: Task<Void, Never>?
    private var closeEndpoint: (@MainActor () async throws -> Void)?
    private var epoch = UUID()
    private var refreshSequence: UInt64 = 0
    private var appliedRefreshSequence: UInt64 = 0
    private var isForeground = true
    private var automaticPolling = true
    private struct Submission {
        let prompt: EnginePrompt
        let answer: MagicMobileOnDevice.JSONValue
        let requestID: UUID
        let label: String
    }
    private var pending: Submission?

    func attach(client: EngineClient, matchID: String, seatID: String, autoPoll: Bool = true,
                close: @escaping @MainActor () async throws -> Void) async throws {
        guard self.client == nil, !isWorking else { throw EngineError.invalidMessage("Close the active game first") }
        self.client = client; self.matchID = matchID; self.seatID = seatID
        closeEndpoint = close; automaticPolling = autoPoll; epoch = UUID()
        refreshSequence = 0; appliedRefreshSequence = 0; isClosing = false
        messageLog = OnDeviceMessageLog()
        status = "Starting local game"
        try await refresh()
        beginPolling()
    }

    func refresh() async throws {
        guard let client, let matchID, let seatID, isForeground, !isClosing else { return }
        let token = epoch
        refreshSequence += 1
        let sequence = refreshSequence
        let next = try await client.poll(matchID: matchID, seatID: seatID, after: poll?.revision ?? 0)
        guard epoch == token, self.matchID == matchID, isForeground, !isClosing, !Task.isCancelled else { return }
        guard next.matchID == matchID, next.seatID == seatID else { throw EngineError.unboundPeer }
        // Submission can change at the same mailbox revision. Do not let an older
        // in-flight poll restore a choice after a newer response hid it.
        if let poll, next.revision < poll.revision ||
            (next.revision == poll.revision && sequence <= appliedRefreshSequence) { return }
        var nextLog = messageLog
        try nextLog.ingest(next)
        if next.phase == "closed" {
            snapshot = nil
            nextLog = OnDeviceMessageLog()
            pending = nil; pendingActionID = nil; pendingCardID = nil
        } else if next.snapshot != nil {
            snapshot = try OnDeviceSnapshotAdapter.snapshot(next, expectedSeatID: seatID, log: nextLog.entries)
        }
        messageLog = nextLog
        poll = next
        appliedRefreshSequence = max(appliedRefreshSequence, sequence)
        if let pending, next.prompt?.id != pending.prompt.id || next.prompt?.revision != pending.prompt.revision {
            self.pending = nil; pendingActionID = nil; pendingCardID = nil
        }
        switch next.phase {
        case "ended": status = "Game complete"
        case "failed": status = "Game stopped"
        case "closed": status = "Game closed"
        case "starting": status = "Starting local game"
        default: status = "Live"
        }
        errorMessage = next.raw["failure"]?["message"]?.string
        beginPolling()
    }

    func send(action: LegalAction) async throws {
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
        guard client != nil, let matchID, seatID != nil, let snapshot, let prompt = poll?.prompt,
              !isWorking, !isClosing, pendingActionID == nil, isForeground, !snapshot.isCompleted,
              !["ended", "failed", "closed"].contains(poll?.phase ?? ""),
              command.gameId == matchID, command.playerId == snapshot.viewerID,
              command.expectedBridgeRevision == nil || command.expectedBridgeRevision == snapshot.bridgeRevision else {
            throw EngineError.invalidMessage("The game or decision changed. Refresh before choosing again.")
        }
        let answer = try OnDevicePromptAdapter.answer(for: command, prompt: prompt, viewerPlayerID: snapshot.viewerID)
        pending = Submission(prompt: prompt, answer: answer, requestID: UUID(), label: label)
        pendingActionID = actionID; pendingCardID = command.cardInstanceId ?? command.sourceInstanceId
        try await retryPending()
    }

    func retryPending() async throws {
        guard let pending, let client, let matchID, let seatID, isForeground, !isWorking, !isClosing else {
            throw EngineError.invalidMessage("There is no pending response to retry")
        }
        isWorking = true
        let token = epoch
        defer { if epoch == token { isWorking = false } }
        do {
            _ = try await client.respond(matchID: matchID, seatID: seatID, prompt: pending.prompt,
                                         answer: pending.answer, requestID: pending.requestID)
            guard epoch == token else { return }
            errorMessage = nil; status = "\(pending.label) sent; waiting for XMage"
            try await refresh()
        } catch {
            if epoch == token {
                errorMessage = error.localizedDescription
                // An engine rejection is certain. A transport timeout or busy RPC is not:
                // retain the exact request ID and answer for a safe user-triggered retry.
                if case EngineError.rejected(let code, _) = error, code != "rpc_busy" {
                    self.pending = nil; pendingActionID = nil; pendingCardID = nil
                    try? await refresh()
                }
            }
            throw error
        }
    }

    func close() async throws {
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
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    guard let self, !Task.isCancelled else { return }
                    try await self.refresh()
                    guard !Task.isCancelled else { return }
                    if ["ended", "failed", "closed"].contains(self.poll?.phase ?? "") {
                        self.pollingTask = nil
                        return
                    }
                } catch is CancellationError { return }
                catch {
                    guard let self, !Task.isCancelled else { return }
                    self.pollingTask = nil
                    self.errorMessage = error.localizedDescription; self.status = "Updates interrupted. Refresh to retry."
                    return
                }
            }
        }
    }
}
