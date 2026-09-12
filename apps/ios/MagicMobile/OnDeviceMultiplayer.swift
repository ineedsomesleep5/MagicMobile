import Foundation
import MagicMobileOnDevice

/// IDs come exclusively from GKMatch.players and GKLocalPlayer, never packet fields.
struct OnDeviceMultiplayerLobby {
    let peerIDs: [String]
    let localPeerID: String
    var hostID: String { peerIDs[0] }
    private(set) var submissions: [String: MagicMobileOnDevice.JSONValue] = [:]
    var isReady: Bool { submissions.count == peerIDs.count }

    init(peerIDs: [String], localPeerID: String) throws {
        guard (2...4).contains(peerIDs.count), Set(peerIDs).count == peerIDs.count,
              peerIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }), peerIDs.contains(localPeerID) else {
            throw EngineError.invalidMessage("Game Center must connect 2–4 distinct authenticated players.")
        }
        self.peerIDs = peerIDs.sorted()
        self.localPeerID = localPeerID
    }

    func seatID(for authenticatedPeerID: String) throws -> String {
        guard let index = peerIDs.firstIndex(of: authenticatedPeerID) else { throw EngineError.unboundPeer }
        return "player\(index + 1)"
    }

    func verifyHandshake(_ value: MagicMobileOnDevice.JSONValue, from authenticatedPeerID: String,
                         identity: BuildIdentity, epoch: UUID?) throws -> UUID {
        _ = try seatID(for: authenticatedPeerID)
        guard let fields = value.object, let type = fields["type"]?.string,
              ["offer", "submission", "start"].contains(type) else { throw EngineError.incompatibleBuild }
        let keys: Set<String> = type == "submission" ? ["type", "epoch", "build", "roster", "player"] :
            type == "start" ? ["type", "epoch", "build", "roster", "matchId"] : ["type", "epoch", "build", "roster"]
        guard Set(fields.keys) == keys, value["build"] == identity.json,
              value["roster"] == .array(peerIDs.map(MagicMobileOnDevice.JSONValue.string)),
              let epochString = value["epoch"]?.string, let incomingEpoch = UUID(uuidString: epochString),
              epoch.map({ $0 == incomingEpoch }) ?? (type == "offer") else { throw EngineError.incompatibleBuild }
        if type == "submission" {
            guard localPeerID == hostID, authenticatedPeerID != hostID else { throw EngineError.unboundPeer }
        } else {
            guard localPeerID != hostID, authenticatedPeerID == hostID else { throw EngineError.unboundPeer }
        }
        return incomingEpoch
    }

    static func validateSubmission(_ value: MagicMobileOnDevice.JSONValue) throws {
        guard try value.encoded().count <= 64 * 1024,
              let fields = value.object, Set(fields.keys) == ["name", "deck"],
              let name = fields["name"]?.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 40, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let deck = fields["deck"]?.object,
              Set(deck.keys).isSubset(of: ["name", "main", "commanders", "companions"]),
              let main = deck["main"]?.array, let commanders = deck["commanders"]?.array else {
            throw EngineError.invalidMessage("Invalid player name or resolved deck. Names must contain 1–40 characters.")
        }
        if let name = deck["name"], name.string == nil || (name.string?.count ?? 0) > 200 {
            throw EngineError.invalidMessage("Invalid deck name.")
        }
        if let companions = deck["companions"], companions.array == nil {
            throw EngineError.invalidMessage("Invalid companion list.")
        }
        // Resource bounds only; XMage owns Commander legality, including special deck sizes.
        let rows = main + commanders + (deck["companions"]?.array ?? [])
        guard rows.count <= 2000 else { throw EngineError.messageTooLarge }
        var total: Int64 = 0
        for row in rows {
            guard let fields = row.object,
                  Set(fields.keys).isSubset(of: ["name", "setCode", "collectorNumber", "count"]),
                  let count = fields["count"]?.integer, (1...2000).contains(count),
                  let set = fields["setCode"]?.string, !set.isEmpty, set.utf8.count <= 64,
                  let number = fields["collectorNumber"]?.string, !number.isEmpty, number.utf8.count <= 64 else {
                throw EngineError.invalidMessage("Deck must contain resolved compiled printings.")
            }
            if let name = fields["name"], name.string == nil || (name.string?.utf8.count ?? 0) > 512 {
                throw EngineError.invalidMessage("Invalid printing name.")
            }
            total += count
            guard total <= 2000 else { throw EngineError.messageTooLarge }
        }
    }

    mutating func submit(_ value: MagicMobileOnDevice.JSONValue, from authenticatedPeerID: String) throws {
        _ = try seatID(for: authenticatedPeerID)
        try Self.validateSubmission(value)
        if let previous = submissions[authenticatedPeerID], previous != value {
            throw EngineError.invalidMessage("A player changed their submitted lobby deck.")
        }
        submissions[authenticatedPeerID] = value
    }

    func configuration() throws -> MagicMobileOnDevice.JSONValue {
        guard localPeerID == hostID, isReady else { throw EngineError.invalidMessage("The host is waiting for every player’s deck.") }
        return .object(["seats": .array(try peerIDs.map { peer in
            guard let submitted = submissions[peer], let name = submitted["name"], let deck = submitted["deck"] else {
                throw EngineError.unboundPeer
            }
            return .object(["seatId": .string(try seatID(for: peer)), "controller": .string("human"), "name": name, "deck": deck])
        })])
    }
}

struct OnDeviceMultiplayerEndpoint {
    let client: EngineClient
    let matchID: String
    let seatID: String
    let isHost: Bool
}

/// Correlations bind replies to their authenticated sender, epoch and original sequence.
/// The engine command's requestId is forwarded unchanged, including on caller retries.
@MainActor
final class OnDeviceRemoteEngineTransport: EngineTransport {
    typealias SendPacket = @MainActor @Sendable (Data, String) throws -> Void
    private struct Pending {
        let sequence: UInt64
        let continuation: CheckedContinuation<MagicMobileOnDevice.JSONValue, Error>
        let timeout: Task<Void, Never>
    }
    private let hostID: String, matchID: String, seatID: String
    private let epoch: UUID, send: SendPacket, timeoutNanoseconds: UInt64
    private var sequence: UInt64 = 0
    private var pending: [UUID: Pending] = [:]
    private var closed = false
    private var ready = false

    init(hostID: String, matchID: String, seatID: String, epoch: UUID,
         timeoutNanoseconds: UInt64 = 15_000_000_000, send: @escaping SendPacket) {
        self.hostID = hostID; self.matchID = matchID; self.seatID = seatID
        self.epoch = epoch; self.timeoutNanoseconds = timeoutNanoseconds; self.send = send
    }

    func hello(identity: BuildIdentity) async throws {
        let result = try await exchange(operation: "hello", payload: identity.json)
        guard result["seatId"]?.string == seatID, result["build"] == identity.json else { throw EngineError.incompatibleBuild }
        ready = true
    }

    func request(_ data: Data) async throws -> Data {
        guard ready, !closed else { throw EngineError.invalidMessage("Multiplayer connection is not ready.") }
        let value = try MagicMobileOnDevice.JSONValue.decode(data)
        guard let fields = value.object, fields["protocol"]?.integer == 1,
              fields["matchId"]?.string == matchID, fields["viewerId"]?.string == seatID,
              let operation = fields["op"]?.string else { throw EngineError.unboundPeer }
        let payload: MagicMobileOnDevice.JSONValue
        switch operation {
        case "poll":
            guard Set(fields.keys) == ["protocol", "op", "matchId", "viewerId", "after"],
                  let after = fields["after"]?.integer, after >= 0 else { throw EngineError.invalidMessage("Invalid remote poll.") }
            payload = .object(["after": .integer(after)])
        case "respond":
            guard Set(fields.keys) == ["protocol", "op", "matchId", "viewerId", "command"], let command = fields["command"] else {
                throw EngineError.invalidMessage("Invalid remote response.")
            }
            payload = command
        default: throw EngineError.invalidMessage("Only the host may create or close the native match.")
        }
        let result = try await exchange(operation: operation, payload: payload)
        if operation == "poll" {
            guard result["matchId"]?.string == matchID, result["viewerId"]?.string == seatID else { throw EngineError.unboundPeer }
        }
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }

    private func exchange(operation: String, payload: MagicMobileOnDevice.JSONValue) async throws -> MagicMobileOnDevice.JSONValue {
        try Task.checkCancellation()
        guard !closed, pending.count < 4, sequence < UInt64(Int64.max) else { throw EngineError.invalidMessage("Multiplayer connection is closed or busy.") }
        sequence += 1
        let number = sequence, id = UUID()
        let data = try MagicMobileOnDevice.JSONValue.object([
            "type": .string("request"), "id": .string(id.uuidString), "epoch": .string(epoch.uuidString),
            "sequence": .integer(Int64(number)), "operation": .string(operation), "payload": payload
        ]).encoded()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { @MainActor [weak self, timeoutNanoseconds] in
                    do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
                    self?.finish(id, result: .failure(EngineError.invalidMessage("The host did not answer in time. Keep every player’s app in the foreground.")))
                }
                pending[id] = Pending(sequence: number, continuation: continuation, timeout: timeout)
                do { try send(data, hostID) } catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    func receive(_ value: MagicMobileOnDevice.JSONValue, from authenticatedPeerID: String) throws {
        guard authenticatedPeerID == hostID else { throw EngineError.unboundPeer }
        guard let fields = value.object,
              Set(fields.keys) == ["type", "id", "epoch", "sequence", "result", "error"],
              fields["type"]?.string == "reply", fields["epoch"]?.string == epoch.uuidString,
              let idString = fields["id"]?.string, let id = UUID(uuidString: idString),
              let sequence = fields["sequence"]?.integer, sequence > 0 else { throw EngineError.incompatibleBuild }
        guard let request = pending[id], request.sequence == UInt64(sequence) else { throw EngineError.replayedMessage }
        if let error = fields["error"]?.object {
            guard Set(error.keys) == ["code", "message"], error["code"]?.string == "busy",
                  let message = error["message"]?.string, message.utf8.count <= 1024,
                  fields["result"] == .null else { throw EngineError.invalidMessage("Invalid remote transport error.") }
            // Unlike a definitive engine rejection, busy must retain Session's pending
            // command and requestId: the original timed-out command may still execute.
            finish(id, result: .failure(EngineError.invalidMessage(message)))
        } else if let error = fields["error"]?.string {
            guard error.utf8.count <= 1024, fields["result"] == .null else { throw EngineError.invalidMessage("Invalid remote error.") }
            finish(id, result: .failure(EngineError.rejected(code: "host_rejected", message: error)))
        } else {
            guard fields["error"] == .null, let result = fields["result"] else { throw EngineError.invalidMessage("Invalid remote result.") }
            try result.validated()
            finish(id, result: .success(result))
        }
    }

    func close() {
        closed = true; ready = false
        for id in Array(pending.keys) { finish(id, result: .failure(CancellationError())) }
    }

    private func finish(_ id: UUID, result: Result<MagicMobileOnDevice.JSONValue, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }
}

/// One drain per authenticated peer retains arrival order through the router await.
/// Queued + active RPCs share the four-request limit. No sequence gaps are awaited.
@MainActor
final class OnDeviceHostRequestDispatcher {
    private struct Request {
        let id: UUID
        let frame: PeerFrame
    }
    private let router: HostRouter, epoch: UUID, peerIDs: Set<String>
    private let send: @MainActor (MagicMobileOnDevice.JSONValue, String) throws -> Void
    private let onError: @MainActor (String) -> Void
    private var queues: [String: [Request]] = [:]
    private var pending: [String: Set<UUID>] = [:]
    private var workers: [String: Task<Void, Never>] = [:]
    private var closed = false

    init(router: HostRouter, epoch: UUID, peerIDs: Set<String>,
         send: @escaping @MainActor (MagicMobileOnDevice.JSONValue, String) throws -> Void,
         onError: @escaping @MainActor (String) -> Void) {
        self.router = router; self.epoch = epoch; self.peerIDs = peerIDs
        self.send = send; self.onError = onError
    }

    func receive(_ value: MagicMobileOnDevice.JSONValue, from peer: String) throws {
        guard !closed, peerIDs.contains(peer) else { throw EngineError.unboundPeer }
        guard let fields = value.object,
              Set(fields.keys) == ["type", "epoch", "id", "sequence", "operation", "payload"],
              fields["type"]?.string == "request", fields["epoch"]?.string == epoch.uuidString,
              let id = fields["id"]?.string.flatMap(UUID.init(uuidString:)),
              let sequence = fields["sequence"]?.integer, sequence > 0,
              let operation = fields["operation"]?.string, let payload = fields["payload"] else {
            throw EngineError.invalidMessage("Invalid host request.")
        }
        let request = Request(id: id, frame: PeerFrame(epoch: epoch, sequence: UInt64(sequence), operation: operation, payload: payload))
        guard pending[peer]?.contains(id) != true else { throw EngineError.replayedMessage }
        guard (pending[peer]?.count ?? 0) < 4 else {
            reply(to: request, peer: peer, result: .null,
                  error: .object(["code": .string("busy"), "message": .string("The host is busy. Retry the same action.")]))
            return
        }
        pending[peer, default: []].insert(id)
        queues[peer, default: []].append(request)
        if workers[peer] == nil {
            workers[peer] = Task { @MainActor [weak self] in await self?.drain(peer: peer) }
        }
    }

    private func drain(peer: String) async {
        defer { workers[peer] = nil; pending[peer] = nil; queues[peer] = nil }
        while !closed, !Task.isCancelled, queues[peer]?.isEmpty == false {
            let request = queues[peer]!.removeFirst()
            let result: MagicMobileOnDevice.JSONValue, error: MagicMobileOnDevice.JSONValue
            do {
                try Task.checkCancellation()
                result = try await router.handle(request.frame, authenticatedPeerID: peer); error = .null
            } catch let failure {
                result = .null; error = .string(String(failure.localizedDescription.prefix(240)))
            }
            guard !closed, !Task.isCancelled else { return }
            reply(to: request, peer: peer, result: result, error: error)
            pending[peer]?.remove(request.id)
        }
    }

    private func reply(to request: Request, peer: String, result: MagicMobileOnDevice.JSONValue, error: MagicMobileOnDevice.JSONValue) {
        do {
            try send(.object(["type": .string("reply"), "epoch": .string(epoch.uuidString), "id": .string(request.id.uuidString),
                              "sequence": .integer(Int64(request.frame.sequence)), "result": result, "error": error]), peer)
        } catch { onError(error.localizedDescription) }
    }

    func cancel() {
        closed = true; queues.removeAll()
        workers.values.forEach { $0.cancel() }
    }

    func close() async {
        cancel()
        for worker in Array(workers.values) { await worker.value }
    }
}

#if canImport(UIKit) && canImport(GameKit)
import UIKit
import GameKit
import Combine

/// Own at the app root; present authenticationController/matchmakerController in a
/// UIViewControllerRepresentable and forward scene phase changes here.
@MainActor
final class OnDeviceMultiplayer: NSObject, ObservableObject, GKMatchmakerViewControllerDelegate {
    @Published private(set) var authenticationController: UIViewController?
    @Published private(set) var matchmakerController: GKMatchmakerViewController?
    @Published private(set) var endpoint: OnDeviceMultiplayerEndpoint?
    @Published private(set) var status = "Sign in to Game Center to play with friends."
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isConnected = false
    @Published private(set) var isSuspended = false
    @Published private(set) var needsCleanup = false

    private let identity: BuildIdentity
    private let makeHostEngine: @MainActor () async throws -> EngineClient
    private let closeHostEngine: @MainActor (EngineClient) async throws -> Void
    private var transport: GameKitTransport?
    private var remote: OnDeviceRemoteEngineTransport?
    private var router: HostRouter?
    private var lobby: OnDeviceMultiplayerLobby?
    private var submission: MagicMobileOnDevice.JSONValue?
    private var epoch: UUID?
    private var hostEngine: EngineClient?
    private var nativeMatchID: String?
    private var startup: Task<Void, Never>?
    private var hostDispatcher: OnDeviceHostRequestDispatcher?
    private var lobbyTimer: Task<Void, Never>?
    private var suspendedPeers: Set<String> = []
    private var presenceSequence: Int64 = 0
    private var suspensionRevision: UInt64 = 0
    private var peerPresenceSequences: [String: Int64] = [:]
    private var requestedPlayerCount = 2
    private var closing = false
    private var failed = false
    private var generation = UUID()

    init(identity: BuildIdentity,
         makeHostEngine: @escaping @MainActor () async throws -> EngineClient,
         closeHostEngine: @escaping @MainActor (EngineClient) async throws -> Void) {
        self.identity = identity; self.makeHostEngine = makeHostEngine; self.closeHostEngine = closeHostEngine
        super.init()
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authenticationController = controller
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if let lobby = self.lobby, GKLocalPlayer.local.gamePlayerID != lobby.localPeerID {
                    self.fail("The Game Center account changed. Leave this match before starting another.")
                } else if !self.isAuthenticated, self.transport != nil {
                    self.fail("Game Center signed out. Leave this match before starting another.")
                } else if let error {
                    self.status = error.localizedDescription
                } else if self.isAuthenticated, self.transport == nil {
                    self.status = "Game Center is ready. Every player must keep the app in the foreground."
                }
            }
        }
    }

    @discardableResult
    func makeMatchmaker(playerCount: Int, name: String, deck: MagicMobileOnDevice.JSONValue) throws -> GKMatchmakerViewController {
        guard GKLocalPlayer.local.isAuthenticated else { throw EngineError.invalidMessage("Sign in to Game Center first.") }
        guard (2...4).contains(playerCount), transport == nil, hostEngine == nil, startup == nil,
              endpoint == nil, matchmakerController == nil, !closing else { throw EngineError.invalidMessage("Leave the current match before matchmaking again.") }
        let value: MagicMobileOnDevice.JSONValue = .object(["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "deck": deck])
        try OnDeviceMultiplayerLobby.validateSubmission(value)
        let request = GKMatchRequest()
        request.minPlayers = playerCount; request.maxPlayers = playerCount; request.defaultNumberOfPlayers = playerCount
        guard let controller = GKMatchmakerViewController(matchRequest: request) else { throw EngineError.invalidMessage("Game Center matchmaking is unavailable.") }
        controller.matchmakerDelegate = self
        requestedPlayerCount = playerCount; submission = value
        failed = false; generation = UUID()
        matchmakerController = controller
        status = "Finding \(playerCount) players in Game Center…"
        return controller
    }

    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        Task { @MainActor [weak self] in
            guard let self, viewController === self.matchmakerController else { return }
            viewController.dismiss(animated: true)
            self.matchmakerController = nil; self.submission = nil; self.status = "Matchmaking cancelled."
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, viewController === self.matchmakerController else { return }
            viewController.dismiss(animated: true)
            self.matchmakerController = nil; self.submission = nil; self.status = error.localizedDescription
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        Task { @MainActor [weak self] in
            guard let self else { match.disconnect(); return }
            self.foundMatch(match, controller: viewController)
        }
    }

    private func foundMatch(_ match: GKMatch, controller viewController: GKMatchmakerViewController) {
        guard viewController === matchmakerController else { match.disconnect(); return }
        viewController.dismiss(animated: true); matchmakerController = nil
        do {
            guard match.expectedPlayerCount == 0, match.players.count + 1 == requestedPlayerCount,
                  let submission else { throw EngineError.invalidMessage("Game Center has not connected the complete roster.") }
            let localID = GKLocalPlayer.local.gamePlayerID
            var roster = try OnDeviceMultiplayerLobby(peerIDs: match.players.map(\.gamePlayerID) + [localID], localPeerID: localID)
            if roster.hostID == localID { try roster.submit(submission, from: localID); epoch = UUID() }
            lobby = roster
            let transport = GameKitTransport(match: match)
            self.transport = transport
            let token = generation
            transport.onPacket = { [weak self] packet, peer in
                guard let self, self.generation == token, !self.failed, !self.closing else { return }
                do { try self.receive(packet, from: peer) }
                catch { /* Reject malformed, stale or unauthorized packets without ending the match. */ }
            }
            transport.onDisconnect = { [weak self] _ in
                guard let self, self.generation == token, !self.closing else { return }
                self.fail("A player disconnected. This match cannot reconnect or migrate hosts. Leave and start a new match.")
            }
            transport.onError = { [weak self] message in
                guard let self, self.generation == token, !self.closing else { return }
                self.fail(message)
            }
            status = "Connected. Checking builds and waiting for every deck…"
            lobbyTimer = Task { @MainActor [weak self] in
                // Repeat the host offer while peers install their GameKit delegate.
                for _ in 0..<120 {
                    guard let self, !Task.isCancelled, self.generation == token, !self.failed, self.endpoint == nil else { return }
                    if self.startup == nil, self.lobby?.hostID == localID {
                        do { try self.broadcast(self.lobbyPacket(type: "offer")) } catch { self.fail(error.localizedDescription); return }
                    }
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                }
                self?.fail("The multiplayer lobby timed out. Leave and try matchmaking again.")
            }
        } catch {
            match.disconnect(); fail(error.localizedDescription)
        }
    }

    private func lobbyPacket(type: String) throws -> MagicMobileOnDevice.JSONValue {
        guard let lobby, let epoch else { throw EngineError.incompatibleBuild }
        return .object(["type": .string(type), "epoch": .string(epoch.uuidString), "build": identity.json,
                        "roster": .array(lobby.peerIDs.map(MagicMobileOnDevice.JSONValue.string))])
    }

    private func receive(_ data: Data, from peer: String) throws {
        guard let lobby else { throw EngineError.unboundPeer }
        _ = try lobby.seatID(for: peer)
        let value = try MagicMobileOnDevice.JSONValue.decode(data)
        guard let fields = value.object, let type = fields["type"]?.string else { throw EngineError.invalidMessage("Invalid multiplayer packet.") }
        if type == "offer" || type == "submission" || type == "start" {
            let incomingEpoch = try lobby.verifyHandshake(value, from: peer, identity: identity, epoch: epoch)
            if type == "offer" {
                guard let submission else { throw EngineError.unboundPeer }
                epoch = incomingEpoch
                if remote == nil {
                    var reply = try lobbyPacket(type: "submission").object!
                    reply["player"] = submission
                    try send(.object(reply), to: peer)
                }
            } else {
                if type == "submission" {
                    guard let player = value["player"] else { throw EngineError.unboundPeer }
                    try self.lobby?.submit(player, from: peer)
                    if self.lobby?.isReady == true, startup == nil, hostEngine == nil { startHost() }
                } else {
                    guard let matchID = value["matchId"]?.string, UUID(uuidString: matchID) != nil else { throw EngineError.unboundPeer }
                    guard remote == nil else { return }
                    try startClient(matchID: matchID, epoch: incomingEpoch)
                }
            }
            return
        }
        guard let epoch, value["epoch"]?.string == epoch.uuidString else { throw EngineError.incompatibleBuild }
        switch type {
        case "request":
            guard lobby.localPeerID == lobby.hostID, let hostDispatcher else { throw EngineError.unboundPeer }
            try hostDispatcher.receive(value, from: peer)
        case "reply":
            guard let remote else { throw EngineError.unboundPeer }
            try remote.receive(value, from: peer)
        case "presence":
            guard Set(fields.keys) == ["type", "epoch", "sequence", "suspended"],
                  let sequence = fields["sequence"]?.integer, sequence > (peerPresenceSequences[peer] ?? 0),
                  let suspended = fields["suspended"]?.bool else { throw EngineError.replayedMessage }
            guard lobby.localPeerID == lobby.hostID || peer == lobby.hostID else { throw EngineError.unboundPeer }
            peerPresenceSequences[peer] = sequence
            if suspended { suspendedPeers.insert(peer) } else { suspendedPeers.remove(peer) }
            updateSuspension()
        case "end":
            guard Set(fields.keys) == ["type", "epoch"] else { throw EngineError.invalidMessage("Invalid match ending.") }
            fail(peer == lobby.hostID ? "The host ended this match." : "A player left. Start a new match to play again.")
        default: throw EngineError.invalidMessage("Unknown multiplayer packet.")
        }
    }

    private func startHost() {
        guard let lobby, let epoch else { return }
        let token = generation
        startup = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let engine = try await self.makeHostEngine()
                self.hostEngine = engine; self.needsCleanup = true
                try Task.checkCancellation()
                let created = try await engine.create(configuration: lobby.configuration())
                guard let matchID = created["matchId"]?.string, UUID(uuidString: matchID) != nil else { throw EngineError.invalidMessage("The native engine returned an invalid match.") }
                self.nativeMatchID = matchID
                try Task.checkCancellation()
                let router = HostRouter(engine: engine, matchID: matchID, identity: self.identity, epoch: epoch)
                for peer in lobby.peerIDs where peer != lobby.hostID { try await router.bind(authenticatedPeerID: peer, seatID: lobby.seatID(for: peer)) }
                try Task.checkCancellation()
                guard self.generation == token, !self.failed, !self.closing else { return }
                self.router = router
                self.hostDispatcher = OnDeviceHostRequestDispatcher(router: router, epoch: epoch,
                    peerIDs: Set(lobby.peerIDs.filter { $0 != lobby.hostID }), send: { [weak self] value, peer in
                        guard let self, self.generation == token, !self.failed, !self.closing else { return }
                        try self.send(value, to: peer)
                    }, onError: { [weak self] message in
                        guard let self, self.generation == token, !self.closing else { return }
                        self.fail(message)
                    })
                self.suspensionRevision += 1
                await router.setSuspended(!self.suspendedPeers.isEmpty, revision: self.suspensionRevision)
                guard self.generation == token, !self.failed, !self.closing, !Task.isCancelled else { return }
                var start = try self.lobbyPacket(type: "start").object!
                start["matchId"] = .string(matchID)
                try self.broadcast(.object(start))
                self.endpoint = OnDeviceMultiplayerEndpoint(client: engine, matchID: matchID, seatID: try lobby.seatID(for: lobby.localPeerID), isHost: true)
                self.isConnected = true
                self.lobbyTimer?.cancel(); self.status = "Connected as host. Every player must keep the app in the foreground."
            } catch is CancellationError { }
            catch { self.fail(error.localizedDescription) }
        }
    }

    private func startClient(matchID: String, epoch: UUID) throws {
        guard let lobby, let transport else { throw EngineError.unboundPeer }
        let seatID = try lobby.seatID(for: lobby.localPeerID)
        let remote = OnDeviceRemoteEngineTransport(hostID: lobby.hostID, matchID: matchID, seatID: seatID, epoch: epoch) { [weak transport] data, peer in
            guard let transport else { throw EngineError.unboundPeer }
            try transport.send(data, to: peer)
        }
        self.remote = remote
        let token = generation
        startup = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await remote.hello(identity: self.identity)
                guard self.generation == token, !self.failed, !self.closing, !Task.isCancelled else { return }
                self.endpoint = OnDeviceMultiplayerEndpoint(client: EngineClient(transport: remote), matchID: matchID, seatID: seatID, isHost: false)
                self.isConnected = true
                self.lobbyTimer?.cancel(); self.status = "Connected. Every player must keep the app in the foreground."
            } catch is CancellationError { }
            catch { self.fail(error.localizedDescription) }
        }
    }

    func onSuspended() { setSuspended(true) }
    func onResumed() { setSuspended(false) }

    func setSuspended(_ suspended: Bool) {
        guard let lobby, !failed, !closing else { return }
        guard endpoint != nil else {
            if suspended { fail("Matchmaking paused. Keep every player’s app in the foreground and start a new match.") }
            return
        }
        if suspended { suspendedPeers.insert(lobby.localPeerID) } else { suspendedPeers.remove(lobby.localPeerID) }
        updateSuspension()
        if lobby.localPeerID != lobby.hostID { sendPresence(suspended, to: lobby.hostID) }
    }

    private func updateSuspension() {
        guard let lobby, !failed, !closing else { return }
        let paused = !suspendedPeers.isEmpty
        isSuspended = paused
        status = paused ? "Match paused. Every player must return to the foreground." : "Connected. Every player must keep the app in the foreground."
        if lobby.localPeerID == lobby.hostID {
            suspensionRevision += 1
            let revision = suspensionRevision
            if let router { Task { await router.setSuspended(paused, revision: revision) } }
            for peer in lobby.peerIDs where peer != lobby.hostID { sendPresence(paused, to: peer) }
        }
    }

    private func sendPresence(_ suspended: Bool, to peer: String) {
        guard let epoch, presenceSequence < Int64.max else { return }
        presenceSequence += 1
        do { try send(.object(["type": .string("presence"), "epoch": .string(epoch.uuidString),
                              "sequence": .integer(presenceSequence), "suspended": .bool(suspended)]), to: peer) }
        catch { fail(error.localizedDescription) }
    }

    /// A failed native destroy/close retains both the endpoint and engine for retry.
    func leave() async throws {
        guard !closing else { throw EngineError.invalidMessage("Match shutdown is already in progress.") }
        closing = true
        isConnected = false
        defer { closing = false }
        lobbyTimer?.cancel(); startup?.cancel(); remote?.close()
        hostDispatcher?.cancel()
        if let epoch { try? broadcast(.object(["type": .string("end"), "epoch": .string(epoch.uuidString)])) }
        disconnect()
        await startup?.value
        await hostDispatcher?.close()
        startup = nil
        do {
            if let engine = hostEngine {
                if let matchID = nativeMatchID { try await engine.destroy(matchID: matchID); nativeMatchID = nil }
                try await closeHostEngine(engine)
            }
        } catch {
            status = "Native match shutdown failed. Try Leave again: \(error.localizedDescription)"
            throw error
        }
        generation = UUID(); hostEngine = nil; needsCleanup = false; endpoint = nil
        remote = nil; router = nil; hostDispatcher = nil; transport = nil; lobby = nil; epoch = nil; submission = nil
        suspendedPeers.removeAll(); peerPresenceSequences.removeAll(); presenceSequence = 0
        suspensionRevision = 0
        matchmakerController?.dismiss(animated: true); matchmakerController = nil
        failed = false; isSuspended = false; status = "Match closed."
    }

    private func fail(_ message: String) {
        guard !failed else { return }
        failed = true; isConnected = false; status = message
        lobbyTimer?.cancel(); startup?.cancel(); remote?.close()
        hostDispatcher?.cancel()
        if let epoch { try? broadcast(.object(["type": .string("end"), "epoch": .string(epoch.uuidString)])) }
        disconnect()
        // The UI keeps its endpoint and explicitly retries leave if native teardown is busy.
    }

    private func disconnect() {
        transport?.onPacket = nil; transport?.onDisconnect = nil; transport?.onError = nil; transport?.onPacketRejected = nil
        transport?.disconnect()
    }

    private func send(_ value: MagicMobileOnDevice.JSONValue, to peer: String) throws {
        guard let transport else { throw EngineError.unboundPeer }
        try transport.send(value.encoded(), to: peer)
    }

    private func broadcast(_ value: MagicMobileOnDevice.JSONValue) throws {
        guard let lobby else { return }
        for peer in lobby.peerIDs where peer != lobby.localPeerID { try send(value, to: peer) }
    }
}
#endif
