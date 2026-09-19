import Foundation
import Testing
@testable import MagicMobileOnDevice

private actor ValidationPrivacyRecorder: EngineTransport {
    private(set) var count = 0
    func request(_ data: Data) async throws -> Data { count += 1; throw EngineError.invalidMessage("Must not reach engine") }
}
@Suite("Standalone validation is a trusted local operation")
struct DeckValidationPrivacyTests {
    @Test func authenticatedPeersCannotInvokeStandaloneValidation() async throws {
        let recorder = ValidationPrivacyRecorder(), identity = BuildIdentity(upstreamCommit: "test", catalogueHash: "hash")
        let epoch = UUID()
        let router = HostRouter(engine: EngineClient(transport: recorder), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "peer", seatID: "seat")
        _ = try await router.handle(PeerFrame(epoch: epoch, sequence: 1, operation: "hello", payload: identity.json), authenticatedPeerID: "peer")
        await #expect(throws: EngineError.invalidMessage("Remote operation not allowed")) {
            try await router.handle(PeerFrame(epoch: epoch, sequence: 2, operation: "validateDeck", payload: .object(["deck": .object([:])])), authenticatedPeerID: "peer")
        }
        #expect(await recorder.count == 0)
    }
}
