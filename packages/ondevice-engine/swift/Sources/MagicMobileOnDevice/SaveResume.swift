import Foundation

/// Solo save/resume on the engine boundary. Only engines that advertise
/// `"saveResume": true` accept the checkpoint field on create and the restore operation;
/// older engines reject unknown request fields, so nothing here is sent to them.
public enum EngineSaveResume {
    /// Engine error codes for a restore that cannot continue.
    public static let unavailableCode = "checkpoint_unavailable"
    public static let incompatibleCode = "checkpoint_incompatible"
    public static let corruptCode = "checkpoint_corrupt"
    /// A `checkpoint` request for a match the engine no longer has.
    public static let matchUnavailableCode = "match_unavailable"
    /// The longest a `checkpoint` request may wait for its save.
    public static let maxWaitMillis = 1000

    /// True only when the capabilities explicitly advertise checkpoint support.
    public static func isSupported(_ capabilities: JSONValue?) -> Bool {
        capabilities?["saveResume"]?.bool == true
    }

    /// True only for an engine that saves when asked (`checkpoint`, `cancelCheckpoint`) instead
    /// of at every decision. Older `saveResume` engines are never sent those operations.
    public static func supportsOnDemand(_ capabilities: JSONValue?) -> Bool {
        isSupported(capabilities) && capabilities?["checkpointOnDemand"]?.bool == true
    }

    /// The create configuration with `"checkpoint": {"path": ...}` added. Throws, sending
    /// nothing, for an engine without `saveResume`, a relative path, or a table that does not
    /// have exactly one human seat.
    public static func configuration(_ configuration: JSONValue, checkpointPath: String,
                                     capabilities: JSONValue?) throws -> JSONValue {
        guard isSupported(capabilities) else {
            throw EngineError.invalidMessage("This engine cannot save games for resuming")
        }
        guard var object = configuration.object, object["checkpoint"] == nil,
              let seats = object["seats"]?.array else {
            throw EngineError.invalidMessage("Invalid game configuration for checkpoints")
        }
        guard seats.filter({ $0["controller"]?.string == "human" }).count == 1 else {
            throw EngineError.invalidMessage("Only a game with exactly one player can be saved")
        }
        object["checkpoint"] = .object(["path": .string(try validatedPath(checkpointPath))])
        return .object(object)
    }

    static func validatedPath(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else {
            throw EngineError.invalidMessage("Checkpoint path must be absolute")
        }
        return path
    }
}

/// The engine's latest checkpoint write, reported on each poll after it and by a `checkpoint`
/// request that saved.
public struct EngineCheckpoint: Sendable, Equatable, Codable {
    public let sequence: Int64
    public let savedAtMillis: Int64
    public let turn: Int64
    public let bytes: Int64
    /// How long the write took, when the engine reports it.
    public let writeMillis: Int64?

    public init(sequence: Int64, savedAtMillis: Int64, turn: Int64, bytes: Int64, writeMillis: Int64? = nil) {
        self.sequence = sequence; self.savedAtMillis = savedAtMillis; self.turn = turn; self.bytes = bytes
        self.writeMillis = writeMillis
    }

    /// Nil for an absent or malformed field. Checkpoint progress is advisory: it never
    /// blocks the game update that carries it.
    public init?(_ value: JSONValue?) {
        guard let value, value != .null, let sequence = value["sequence"]?.integer,
              let saved = value["savedAtMillis"]?.integer, let turn = value["turn"]?.integer,
              let bytes = value["bytes"]?.integer,
              sequence >= 0, saved > 0, turn >= 0, bytes >= 0 else { return nil }
        self.init(sequence: sequence, savedAtMillis: saved, turn: turn, bytes: bytes,
                  writeMillis: value["writeMillis"]?.integer.flatMap { $0 >= 0 ? $0 : nil })
    }
}

/// What a `checkpoint` request found (engines with `checkpointOnDemand` only).
public enum EngineCheckpointResult: Sendable, Equatable {
    /// The current decision is saved: written now, or already saved earlier.
    case saved(EngineCheckpoint)
    /// The AI is thinking or something is resolving. The request stays armed, and the engine
    /// saves at the player's next priority decision.
    case waitingForEngine
    /// The player is in the middle of an action (targets, payment, mulligan, attackers...),
    /// which cannot be saved.
    case waitingForPlayer
    /// The write failed: the engine's `checkpointFailure`.
    case failed(JSONValue)
    /// The match ended, or this seat is out of it.
    case over
    /// `checkpoint_unavailable` (no checkpoint path, a table, or no support) or `match_unavailable`.
    case unavailable(code: String)

    public init(_ value: JSONValue) throws {
        switch value["state"]?.string {
        case "saved":
            guard let checkpoint = EngineCheckpoint(value["checkpoint"]) else {
                throw EngineError.invalidMessage("Malformed checkpoint result")
            }
            self = .saved(checkpoint)
        case "pending":
            switch value["waitingFor"]?.string {
            case "engine": self = .waitingForEngine
            case "player": self = .waitingForPlayer
            default: throw EngineError.invalidMessage("Malformed checkpoint result")
            }
        case "failed": self = .failed(value["checkpointFailure"] ?? .null)
        case "over": self = .over
        default: throw EngineError.invalidMessage("Malformed checkpoint result")
        }
    }
}

/// A restore result: the same shape as create plus `restored`.
public struct EngineRestoredMatch: Sendable, Equatable {
    public let result: JSONValue
    public let matchID: String
    public let turn: Int64
    public let savedAtMillis: Int64

    public init(_ value: JSONValue) throws {
        guard let matchID = value["matchId"]?.string, !matchID.isEmpty,
              let restored = value["restored"], let turn = restored["turn"]?.integer, turn >= 0,
              let saved = restored["savedAtMillis"]?.integer, saved > 0 else {
            throw EngineError.invalidMessage("Malformed restore result")
        }
        result = value; self.matchID = matchID; self.turn = turn; savedAtMillis = saved
    }
}

extension EngineClient {
    /// Restores a checkpointed solo game. `capabilities` gate the call: an engine without
    /// `saveResume` is never sent the operation.
    public func restore(checkpointPath: String, capabilities: JSONValue?) async throws -> EngineRestoredMatch {
        guard EngineSaveResume.isSupported(capabilities) else {
            throw EngineError.invalidMessage("This engine cannot resume saved games")
        }
        let path = try EngineSaveResume.validatedPath(checkpointPath)
        let value = try await call("restore", fields: ["checkpoint": .object(["path": .string(path)])])
        return try EngineRestoredMatch(value)
    }

    /// Asks the engine to save the match now, waiting up to `waitMillis` (0...1000) for the
    /// write. Only for an engine that passes `EngineSaveResume.supportsOnDemand`.
    /// `checkpoint_unavailable` and `match_unavailable` return `.unavailable`; anything else throws.
    public func requestCheckpoint(matchID: String, waitMillis: Int) async throws -> EngineCheckpointResult {
        guard !matchID.isEmpty, (0...EngineSaveResume.maxWaitMillis).contains(waitMillis) else {
            throw EngineError.invalidMessage("Invalid checkpoint request")
        }
        let value: JSONValue
        do {
            value = try await call("checkpoint", fields: ["matchId": .string(matchID), "waitMillis": .integer(Int64(waitMillis))])
        } catch EngineError.rejected(let code, _) where Self.unavailableCodes.contains(code) {
            return .unavailable(code: code)
        } catch EngineError.rejectionDetails(let code, _, _) where Self.unavailableCodes.contains(code) {
            return .unavailable(code: code)
        }
        return try EngineCheckpointResult(value)
    }

    /// Clears an armed `checkpoint` request (engines with `checkpointOnDemand` only).
    public func cancelCheckpoint(matchID: String) async throws {
        guard !matchID.isEmpty else { throw EngineError.invalidMessage("Invalid checkpoint request") }
        _ = try await call("cancelCheckpoint", fields: ["matchId": .string(matchID)])
    }

    private static let unavailableCodes: Set<String> = [EngineSaveResume.unavailableCode, EngineSaveResume.matchUnavailableCode]
}
