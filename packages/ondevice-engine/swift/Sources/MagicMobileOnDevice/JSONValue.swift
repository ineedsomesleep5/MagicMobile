import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), integer(Int64), number(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public subscript(_ key: String) -> JSONValue? { if case .object(let v) = self { return v[key] }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var integer: Int64? { if case .integer(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public func validated(depth: Int = 0) throws {
        guard depth <= 64 else { throw EngineError.invalidMessage("JSON nesting limit exceeded") }
        switch self {
        case .array(let a): for v in a { try v.validated(depth: depth + 1) }
        case .object(let o): for v in o.values { try v.validated(depth: depth + 1) }
        case .number(let n): guard n.isFinite else { throw EngineError.invalidMessage("Nonfinite number") }
        default: break
        }
    }
    public func encoded() throws -> Data {
        try validated()
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try e.encode(self)
        guard data.count <= WireLimits.maxJSONBytes else { throw EngineError.messageTooLarge }
        return data
    }
    public static func decode(_ data: Data) throws -> JSONValue {
        guard !data.isEmpty, data.count <= WireLimits.maxJSONBytes else { throw EngineError.messageTooLarge }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        try value.validated(); return value
    }
}
public enum WireLimits {
    public static let maxJSONBytes = 4 * 1024 * 1024
    public static let chunkBytes = 8 * 1024
}
public enum EngineError: Error, Equatable, Sendable, LocalizedError {
    case nativeEngineNotLinked, messageTooLarge, invalidMessage(String), rejected(code: String, message: String)
    case incompatibleBuild, unboundPeer, replayedMessage, hostSuspended, runtimeFailure(Int32)
    case rejectionDetails(code: String, message: String, details: JSONValue)
    public var errorDescription: String? {
        switch self {
        case .nativeEngineNotLinked: return "The native XMage library is not linked. No remote engine or simulator was substituted."
        case .messageTooLarge: return "Message exceeds the supported size."
        case .invalidMessage(let s): return s
        case .rejected(_, let s): return s
        case .rejectionDetails(_, let message, let details):
            let issues = details["issues"]?.array?.compactMap { issue -> String? in
                guard let text = issue["message"]?.string else { return nil }
                let group = issue["group"]?.string ?? ""
                return group.isEmpty ? text : "\(group): \(text)"
            } ?? []
            return ([message] + issues).joined(separator: "\n")
        case .incompatibleBuild: return "Players must use the same engine, catalogue, and protocol build."
        case .unboundPeer: return "This authenticated peer has not been assigned a seat."
        case .replayedMessage: return "Duplicate or out-of-order transport message."
        case .hostSuspended: return "The host paused input. Return the host app to the foreground."
        case .runtimeFailure(let n): return "Native runtime failed with status \(n)."
        }
    }
}
