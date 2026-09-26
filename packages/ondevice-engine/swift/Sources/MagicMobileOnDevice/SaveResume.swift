import Foundation

/// Solo save/resume on the engine boundary. Only engines that advertise
/// `"saveResume": true` accept the checkpoint field on create and the restore operation;
/// older engines reject unknown request fields, so nothing here is sent to them.
public enum EngineSaveResume {
    /// Engine error codes for a restore that cannot continue.
    public static let unavailableCode = "checkpoint_unavailable"
    public static let incompatibleCode = "checkpoint_incompatible"
    public static let corruptCode = "checkpoint_corrupt"

    /// True only when the capabilities explicitly advertise checkpoint support.
    public static func isSupported(_ capabilities: JSONValue?) -> Bool {
        capabilities?["saveResume"]?.bool == true
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

/// The engine's latest checkpoint write, reported on each poll after it.
public struct EngineCheckpoint: Sendable, Equatable, Codable {
    public let sequence: Int64
    public let savedAtMillis: Int64
    public let turn: Int64
    public let bytes: Int64

    public init(sequence: Int64, savedAtMillis: Int64, turn: Int64, bytes: Int64) {
        self.sequence = sequence; self.savedAtMillis = savedAtMillis; self.turn = turn; self.bytes = bytes
    }

    /// Nil for an absent or malformed field. Checkpoint progress is advisory: it never
    /// blocks the game update that carries it.
    public init?(_ value: JSONValue?) {
        guard let value, value != .null, let sequence = value["sequence"]?.integer,
              let saved = value["savedAtMillis"]?.integer, let turn = value["turn"]?.integer,
              let bytes = value["bytes"]?.integer,
              sequence >= 0, saved > 0, turn >= 0, bytes >= 0 else { return nil }
        self.init(sequence: sequence, savedAtMillis: saved, turn: turn, bytes: bytes)
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
}
