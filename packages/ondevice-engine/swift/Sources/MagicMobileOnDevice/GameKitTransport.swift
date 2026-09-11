#if canImport(GameKit)
import Foundation
import GameKit

/** GameKit handles connectivity; rules execute on the selected host's embedded engine. */
@MainActor
public final class GameKitTransport: NSObject, GKMatchDelegate {
    public var onPacket: (@MainActor @Sendable (Data, String) -> Void)?
    public var onDisconnect: (@MainActor @Sendable (String) -> Void)?
    public var onError: (@MainActor @Sendable (String) -> Void)?
    public let match: GKMatch
    private let assembler = PacketAssembler()
    public init(match: GKMatch) { self.match = match; super.init(); match.delegate = self }
    public func send(_ data: Data, to authenticatedPeerID: String) throws {
        guard let player = match.players.first(where: { $0.gamePlayerID == authenticatedPeerID }) else { throw EngineError.unboundPeer }
        for chunk in try PacketChunk.split(data) {
            try match.send(JSONEncoder().encode(chunk), to: [player], dataMode: .reliable)
        }
    }
    nonisolated public func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        // Bound before decoding base64. Encoded 8 KiB chunks fit well inside this limit.
        guard data.count <= 16 * 1024 else { return }
        let peer = player.gamePlayerID
        Task { @MainActor [weak self] in
            guard let self, self.match.players.contains(where: { $0.gamePlayerID == peer }) else { return }
            do {
                let c = try JSONDecoder().decode(PacketChunk.self, from: data)
                if let packet = try await self.assembler.receive(c, from: peer) { self.onPacket?(packet, peer) }
            } catch { self.onError?("Rejected invalid multiplayer packet") }
        }
    }
    nonisolated public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .disconnected else { return }; let peer = player.gamePlayerID
        Task { @MainActor [weak self] in
            guard let self else { return }; await self.assembler.drop(peer: peer); self.onDisconnect?(peer)
        }
    }
    nonisolated public func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        Task { @MainActor [weak self] in self?.onError?("GameKit connection failed") }
    }
}
#endif
