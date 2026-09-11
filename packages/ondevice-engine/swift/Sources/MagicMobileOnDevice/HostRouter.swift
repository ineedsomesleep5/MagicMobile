import Foundation

public struct BuildIdentity: Codable, Sendable, Equatable {
    public let protocolVersion: Int, upstreamCommit: String, catalogueHash: String, adapterVersion: String
    public init(upstreamCommit: String, catalogueHash: String, adapterVersion: String = "ondevice-0.1") {
        protocolVersion = 1; self.upstreamCommit = upstreamCommit; self.catalogueHash = catalogueHash; self.adapterVersion = adapterVersion
    }
    public var json: JSONValue { .object(["protocolVersion": .integer(Int64(protocolVersion)), "upstreamCommit": .string(upstreamCommit), "catalogueHash": .string(catalogueHash), "adapterVersion": .string(adapterVersion)]) }
}
public struct PeerFrame: Codable, Sendable, Equatable {
    public let epoch: UUID, sequence: UInt64, operation: String, payload: JSONValue
    public init(epoch: UUID, sequence: UInt64, operation: String, payload: JSONValue) {
        self.epoch = epoch; self.sequence = sequence; self.operation = operation; self.payload = payload
    }
}
/**
 * Only the HOST constructs this actor. The authenticated GameKit peer ID is an
 * out-of-band argument, never a value read from a peer-supplied JSON actor field.
 * No create/destroy/shutdown/raw engine operation is exposed to remote peers.
 */
public actor HostRouter {
    private struct Binding { let seat: String; var ready = false; var lastSequence: UInt64 = 0 }
    private let engine: EngineClient, matchID: String, identity: BuildIdentity
    public let epoch: UUID
    private var peers: [String: Binding] = [:]
    private var suspended = false
    public init(engine: EngineClient, matchID: String, identity: BuildIdentity, epoch: UUID = UUID()) {
        self.engine = engine; self.matchID = matchID; self.identity = identity; self.epoch = epoch
    }
    public func bind(authenticatedPeerID: String, seatID: String) throws {
        guard !authenticatedPeerID.isEmpty, !seatID.isEmpty, peers.count < 3,
              peers[authenticatedPeerID] == nil, !peers.values.contains(where: { $0.seat == seatID }) else {
            throw EngineError.invalidMessage("Duplicate/invalid peer binding or a full match")
        }
        peers[authenticatedPeerID] = Binding(seat: seatID)
    }
    public func setSuspended(_ value: Bool) { suspended = value }
    public func handle(_ frame: PeerFrame, authenticatedPeerID: String) async throws -> JSONValue {
        guard var binding = peers[authenticatedPeerID] else { throw EngineError.unboundPeer }
        guard frame.epoch == epoch else { throw EngineError.incompatibleBuild }
        guard frame.sequence > binding.lastSequence else { throw EngineError.replayedMessage }
        try frame.payload.validated()
        // Advance before awaiting the engine so concurrent requests cannot reuse a sequence.
        binding.lastSequence = frame.sequence; peers[authenticatedPeerID] = binding
        if frame.operation == "hello" {
            guard frame.payload == identity.json else { throw EngineError.incompatibleBuild }
            binding.ready = true; peers[authenticatedPeerID] = binding
            return .object(["seatId": .string(binding.seat), "build": identity.json])
        }
        guard binding.ready else { throw EngineError.incompatibleBuild }
        switch frame.operation {
        case "poll":
            guard let p = frame.payload.object, Set(p.keys) == Set(["after"]), let after = p["after"]?.integer else { throw EngineError.invalidMessage("Invalid poll payload") }
            return try await engine.poll(matchID: matchID, seatID: binding.seat, after: after).raw
        case "respond":
            guard !suspended else { throw EngineError.hostSuspended }
            guard let p = frame.payload.object, Set(p.keys) == Set(["requestId", "promptId", "promptRevision", "answer"]) else { throw EngineError.invalidMessage("Invalid answer payload") }
            return try await engine.call("respond", fields: ["matchId": .string(matchID), "viewerId": .string(binding.seat), "command": frame.payload])
        default: throw EngineError.invalidMessage("Remote operation not allowed")
        }
    }
}
