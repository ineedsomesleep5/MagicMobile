import Foundation

public struct PacketChunk: Codable, Equatable, Sendable {
    public let id: UUID, index: Int, count: Int, totalBytes: Int, bytes: Data
    public init(id: UUID, index: Int, count: Int, totalBytes: Int, bytes: Data) {
        self.id = id; self.index = index; self.count = count; self.totalBytes = totalBytes; self.bytes = bytes
    }
    public static func split(_ data: Data, id: UUID = UUID()) throws -> [PacketChunk] {
        guard !data.isEmpty, data.count <= WireLimits.maxJSONBytes else { throw EngineError.messageTooLarge }
        let count = (data.count + WireLimits.chunkBytes - 1) / WireLimits.chunkBytes
        return (0..<count).map { i in
            let start = i * WireLimits.chunkBytes, end = min(data.count, (i + 1) * WireLimits.chunkBytes)
            return PacketChunk(id: id, index: i, count: count, totalBytes: data.count, bytes: data.subdata(in: start..<end))
        }
    }
}
/** Bounded, per-authenticated-peer assembly. Safe for out-of-order reliable packets. */
public actor PacketAssembler {
    private struct Key: Hashable { let peer: String, id: UUID }
    private struct Assembly { let count: Int, total: Int, started: TimeInterval; var pieces: [Int: Data] = [:] }
    private var pending: [Key: Assembly] = [:]
    public init() {}
    public func receive(_ c: PacketChunk, from peer: String, now: TimeInterval = Date().timeIntervalSince1970) throws -> Data? {
        guard !peer.isEmpty else { throw EngineError.unboundPeer }
        pending = pending.filter { now - $0.value.started < 15 }
        guard c.totalBytes > 0, c.totalBytes <= WireLimits.maxJSONBytes, c.index >= 0,
              c.count == (c.totalBytes + WireLimits.chunkBytes - 1) / WireLimits.chunkBytes, c.index < c.count else {
            throw EngineError.invalidMessage("Invalid chunk metadata")
        }
        let expected = c.index == c.count - 1 ? c.totalBytes - (c.count - 1) * WireLimits.chunkBytes : WireLimits.chunkBytes
        guard c.bytes.count == expected else { throw EngineError.invalidMessage("Invalid chunk length") }
        let key = Key(peer: peer, id: c.id)
        if pending[key] == nil {
            guard pending.count < 12, pending.keys.filter({ $0.peer == peer }).count < 4,
                  pending.values.reduce(0, { $0 + $1.total }) + c.totalBytes <= 16 * 1024 * 1024 else { throw EngineError.messageTooLarge }
            pending[key] = Assembly(count: c.count, total: c.totalBytes, started: now)
        }
        guard var a = pending[key], a.total == c.totalBytes, a.count == c.count else { throw EngineError.invalidMessage("Conflicting chunk header") }
        if let existing = a.pieces[c.index], existing != c.bytes { throw EngineError.invalidMessage("Conflicting duplicate chunk") }
        a.pieces[c.index] = c.bytes; pending[key] = a
        guard a.pieces.count == a.count else { return nil }
        var data = Data(capacity: a.total)
        for i in 0..<a.count { guard let part = a.pieces[i] else { return nil }; data.append(part) }
        pending.removeValue(forKey: key); return data
    }
    public func drop(peer: String) { pending = pending.filter { $0.key.peer != peer } }
    public func pendingCount() -> Int { pending.count }
}
