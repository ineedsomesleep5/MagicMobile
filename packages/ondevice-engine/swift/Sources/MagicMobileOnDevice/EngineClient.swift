import Foundation
import CMagicEngine

public protocol EngineTransport: Sendable {
    func request(_ data: Data) async throws -> Data
}
/** Pinned C lifetime, accessed only from the NativeEngineTransport actor. */
private final class NativeHandle: @unchecked Sendable {
    private var pointer: OpaquePointer?
    init() throws {
        var p: OpaquePointer?
        let status = mm_runtime_create(&p)
        guard status == MM_OK, let p else {
            if status == MM_NOT_LINKED { throw EngineError.nativeEngineNotLinked }
            throw EngineError.runtimeFailure(Int32(status.rawValue))
        }
        pointer = p
    }
    func perform(_ data: Data) throws -> Data {
        guard let pointer else { throw EngineError.invalidMessage("Native engine transport is closed") }
        guard !data.isEmpty, data.count <= WireLimits.maxJSONBytes else { throw EngineError.messageTooLarge }
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = data.withUnsafeBytes { buffer in
            mm_runtime_request(pointer, buffer.bindMemory(to: UInt8.self).baseAddress, data.count, &output, &length)
        }
        guard status == MM_OK, let output else { throw EngineError.runtimeFailure(Int32(status.rawValue)) }
        defer { mm_response_free(output) }
        return Data(bytes: output, count: length)
    }
    func close() throws {
        guard let pointer else { return }
        let status = mm_runtime_destroy(pointer)
        guard status == MM_OK else { throw EngineError.runtimeFailure(Int32(status.rawValue)) }
        self.pointer = nil
    }
    deinit {
        // No caller remains to retry. On failure the C runtime/isolate must remain allocated;
        // this intentionally leaks rather than freeing memory beneath a live engine worker.
        if let pointer { _ = mm_runtime_destroy(pointer) }
    }
}
public actor NativeEngineTransport: EngineTransport {
    private let handle: NativeHandle
    public init() throws { handle = try NativeHandle() }
    public func request(_ data: Data) async throws -> Data { try handle.perform(data) }
    /// Call explicitly before releasing the transport. A failure retains ownership for retry.
    public func close() async throws { try handle.close() }
}
public struct EngineClient: Sendable {
    private let transport: any EngineTransport
    public init(transport: any EngineTransport) { self.transport = transport }
    public func call(_ operation: String, fields: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard fields["op"] == nil, fields["protocol"] == nil else { throw EngineError.invalidMessage("Reserved request keys") }
        var object = fields; object["protocol"] = .integer(1); object["op"] = .string(operation)
        let reply = try JSONValue.decode(try await transport.request(JSONValue.object(object).encoded()))
        guard reply["protocol"]?.integer == 1, let success = reply["ok"]?.bool else { throw EngineError.invalidMessage("Invalid engine response envelope") }
        guard success else {
            if let details = reply["error"]?["details"], details.object != nil {
                throw EngineError.rejectionDetails(code: reply["error"]?["code"]?.string ?? "unknown",
                    message: reply["error"]?["message"]?.string ?? "Engine rejected request", details: details)
            }
            throw EngineError.rejected(code: reply["error"]?["code"]?.string ?? "unknown", message: reply["error"]?["message"]?.string ?? "Engine rejected request")
        }
        guard let result = reply["result"] else { throw EngineError.invalidMessage("Missing result") }
        return result
    }
    public func capabilities() async throws -> JSONValue { try await call("capabilities") }
    public func create(configuration: JSONValue) async throws -> JSONValue { try await call("create", fields: ["configuration": configuration]) }
    public func poll(matchID: String, seatID: String, after: Int64 = 0) async throws -> MatchPoll {
        guard !matchID.isEmpty, !seatID.isEmpty, after >= 0 else {
            throw EngineError.invalidMessage("Invalid poll identity or revision")
        }
        let value = try await call("poll", fields: ["matchId": .string(matchID), "viewerId": .string(seatID), "after": .integer(after)])
        let poll = try MatchPoll(value)
        // Do not let a stale/misrouted response enter another match's presentation.
        // Seat authority remains the host's responsibility; this is correlation,
        // not protection against a malicious authoritative host.
        guard poll.matchID == matchID, poll.seatID == seatID else {
            throw EngineError.invalidMessage("Poll response identity mismatch")
        }
        return poll
    }
    public func respond(matchID: String, seatID: String, prompt: EnginePrompt, answer: JSONValue, requestID: UUID = UUID()) async throws -> JSONValue {
        try await call("respond", fields: ["matchId": .string(matchID), "viewerId": .string(seatID), "command": prompt.command(answer: answer, requestID: requestID)])
    }
    /// The seat concedes. In a pod the game goes on and the seat keeps polling as a spectator.
    public func concede(matchID: String, seatID: String) async throws {
        guard !matchID.isEmpty, !seatID.isEmpty else { throw EngineError.invalidMessage("Invalid concede identity") }
        _ = try await call("concede", fields: ["matchId": .string(matchID), "viewerId": .string(seatID)])
    }
    public func destroy(matchID: String) async throws { _ = try await call("destroy", fields: ["matchId": .string(matchID)]) }
}
public struct EnginePrompt: Sendable, Equatable {
    public let id: String, revision: Int64, kind: String, payload: JSONValue, submitted: Bool
    public let responseTypes: [String]
    public let minimum: Int64, maximum: Int64
    public init(_ value: JSONValue) throws {
        guard let id = value["promptId"]?.string, let revision = value["revision"]?.integer,
              revision >= 0, let kind = value["kind"]?.string, let payload = value["payload"],
              let submitted = value["submitted"]?.bool, let types = value["responseTypes"]?.array,
              let minimum = value["min"]?.integer, let maximum = value["max"]?.integer else {
            throw EngineError.invalidMessage("Malformed engine prompt")
        }
        guard !id.isEmpty, !kind.isEmpty, payload.object != nil, minimum <= maximum,
              !types.isEmpty, types.count <= 6 else {
            throw EngineError.invalidMessage("Invalid prompt structure or bounds")
        }
        self.id = id; self.revision = revision; self.kind = kind; self.payload = payload
        self.submitted = submitted; self.minimum = minimum; self.maximum = maximum
        self.responseTypes = try types.map { guard let s = $0.string else { throw EngineError.invalidMessage("Response type must be a string") }; return s }
        let supported: Set<String> = ["boolean", "uuid", "string", "integer", "integers", "mana"]
        guard Set(responseTypes).count == responseTypes.count, Set(responseTypes).isSubset(of: supported) else {
            throw EngineError.invalidMessage("Unknown or duplicate prompt response type")
        }
    }
    public func command(answer: JSONValue, requestID: UUID = UUID()) -> JSONValue {
        .object(["requestId": .string(requestID.uuidString.lowercased()), "promptId": .string(id),
                 "promptRevision": .integer(revision), "answer": answer])
    }
    public static func answer(_ kind: String, _ value: JSONValue) -> JSONValue { .object(["kind": .string(kind), "value": value]) }
}
public struct MatchPoll: Sendable, Equatable {
    public let raw: JSONValue
    public let matchID: String, seatID: String, phase: String
    public let revision: Int64, prompt: EnginePrompt?, snapshot: JSONValue?, resyncRequired: Bool
    public init(_ value: JSONValue) throws {
        guard let matchID = value["matchId"]?.string, let seatID = value["viewerId"]?.string,
              let revision = value["revision"]?.integer, revision >= 0,
              let phase = value["phase"]?.string, let resync = value["resyncRequired"]?.bool else {
            throw EngineError.invalidMessage("Malformed match poll")
        }
        raw = value; self.matchID = matchID; self.seatID = seatID; self.revision = revision
        self.phase = phase; self.resyncRequired = resync
        snapshot = value["snapshot"] == .null ? nil : value["snapshot"]
        if let p = value["prompt"], p != .null { prompt = try EnginePrompt(p) } else { prompt = nil }
    }
}
