import Foundation

/// The lock enqueues synchronously at the delegate boundary. One consumer per peer
/// awaits assembly AND delivery before reading the next chunk; actor FIFO is not assumed.
final class OrderedPacketIngress: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: [Data]] = [:]
    private var queuedBytes: [String: Int] = [:]
    private var draining: Set<String> = []
    private var closed = false
    private let assembler = PacketAssembler()
    @MainActor var onPacket: (@MainActor @Sendable (Data, String) -> Void)?
    @MainActor var onPacketRejected: (@MainActor @Sendable (String) -> Void)?

    @MainActor init(onPacket: (@MainActor @Sendable (Data, String) -> Void)? = nil,
                    onPacketRejected: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.onPacket = onPacket; self.onPacketRejected = onPacketRejected
    }

    /// A full ingress queue drops traffic without allocating a task for every rejected packet.
    @discardableResult func receive(_ data: Data, from peer: String) -> Bool {
        lock.lock()
        guard !closed, !peer.isEmpty, data.count <= 16 * 1024,
              queues[peer] != nil || queues.count < 3,
              (queues[peer]?.count ?? 0) < 2048,
              (queuedBytes[peer] ?? 0) + data.count <= 6 * 1024 * 1024,
              queuedBytes.values.reduce(0, +) + data.count <= 16 * 1024 * 1024 else {
            lock.unlock(); return false
        }
        queues[peer, default: []].append(data)
        queuedBytes[peer, default: 0] += data.count
        let start = draining.insert(peer).inserted
        lock.unlock()
        if start { Task { @MainActor [weak self] in await self?.drain(peer: peer) } }
        return true
    }

    private func next(peer: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !closed, var queue = queues[peer], !queue.isEmpty else {
            queues[peer] = nil; queuedBytes[peer] = nil; draining.remove(peer); return nil
        }
        let data = queue.removeFirst()
        queues[peer] = queue; queuedBytes[peer, default: 0] -= data.count
        return data
    }

    @MainActor private func drain(peer: String) async {
        while let data = next(peer: peer) {
            do {
                let chunk = try JSONDecoder().decode(PacketChunk.self, from: data)
                if let packet = try await assembler.receive(chunk, from: peer), isOpen() { onPacket?(packet, peer) }
            } catch { onPacketRejected?(peer) }
        }
    }

    private func isOpen() -> Bool { lock.lock(); defer { lock.unlock() }; return !closed }

    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true; queues.removeAll(); queuedBytes.removeAll()
    }
}

#if canImport(GameKit)
import GameKit

/** GameKit handles connectivity; rules execute on the selected host's embedded engine. */
@MainActor
public final class GameKitTransport: NSObject, GKMatchDelegate {
    public var onPacket: (@MainActor @Sendable (Data, String) -> Void)?
    public var onDisconnect: (@MainActor @Sendable (String) -> Void)?
    public var onError: (@MainActor @Sendable (String) -> Void)?
    public var onPacketRejected: (@MainActor @Sendable (String) -> Void)?
    public let match: GKMatch
    private let ingress = OrderedPacketIngress()
    public init(match: GKMatch) {
        self.match = match; super.init()
        ingress.onPacket = { [weak self] packet, peer in
            guard let self, self.match.players.contains(where: { $0.gamePlayerID == peer }) else { return }
            self.onPacket?(packet, peer)
        }
        ingress.onPacketRejected = { [weak self] peer in self?.onPacketRejected?(peer) }
        match.delegate = self
    }
    public func disconnect() { ingress.close(); match.disconnect() }
    public func send(_ data: Data, to authenticatedPeerID: String) throws {
        guard let player = match.players.first(where: { $0.gamePlayerID == authenticatedPeerID }) else { throw EngineError.unboundPeer }
        for chunk in try PacketChunk.split(data) {
            try match.send(JSONEncoder().encode(chunk), to: [player], dataMode: .reliable)
        }
    }
    nonisolated public func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        ingress.receive(data, from: player.gamePlayerID)
    }
    nonisolated public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .disconnected else { return }; let peer = player.gamePlayerID
        Task { @MainActor [weak self] in
            self?.onDisconnect?(peer)
        }
    }
    nonisolated public func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        Task { @MainActor [weak self] in self?.onError?("GameKit connection failed") }
    }
}
#endif
