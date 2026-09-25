import Foundation
import Testing
@testable import MagicMobileOnDevice

// TEST-ONLY protocol fixture. This is not a rules engine.
private actor RecordingTransport: EngineTransport {
    var recorded: [JSONValue] = []
    let reply: JSONValue
    init(reply: JSONValue = .object(["protocol": .integer(1), "ok": .bool(true), "result": .object([:])])) { self.reply = reply }
    func request(_ data: Data) async throws -> Data { recorded.append(try JSONValue.decode(data)); return try reply.encoded() }
    func calls() -> [JSONValue] { recorded }
}
private func pollValue() -> JSONValue {
    .object(["matchId": .string("match"), "viewerId": .string("seat-2"), "revision": .integer(3), "phase": .string("running"), "resyncRequired": .bool(false), "snapshot": .null, "prompt": .null])
}
private func promptValue() -> JSONValue {
    .object(["promptId": .string("prompt"), "revision": .integer(7), "kind": .string("ASK"), "payload": .object([:]), "submitted": .bool(false), "responseTypes": .array([.string("boolean")]), "min": .integer(0), "max": .integer(0)])
}
private func setup() async throws -> (HostRouter, RecordingTransport, BuildIdentity, UUID) {
    let t = RecordingTransport(reply: .object(["protocol": .integer(1), "ok": .bool(true), "result": pollValue()]))
    let b = BuildIdentity(upstreamCommit: "sha", catalogueHash: "hash"), e = UUID()
    let r = HostRouter(engine: EngineClient(transport: t), matchID: "match", identity: b, epoch: e)
    try await r.bind(authenticatedPeerID: "peer", seatID: "seat-2")
    _ = try await r.handle(PeerFrame(epoch: e, sequence: 1, operation: "hello", payload: b.json), authenticatedPeerID: "peer")
    return (r,t,b,e)
}
@Suite("Swift protocol and transport; not XMage/iOS gameplay")
struct SafetyTests {
    @Test func jsonRoundtrip() throws {
        let v = JSONValue.object(["a": .array([.null,.bool(true),.integer(Int64.max)]), "s": .string("🦊\n")])
        #expect(try JSONValue.decode(v.encoded()) == v)
    }
    @Test func oversizeRejected() { #expect(throws: EngineError.messageTooLarge) { try JSONValue.decode(Data(repeating: 32,count: WireLimits.maxJSONBytes+1)) } }
    @Test func depthRejected() {
        var v = JSONValue.null; for _ in 0..<70 { v = .array([v]) }
        #expect(throws: (any Error).self) { try v.encoded() }
    }
    @Test func nonfiniteRejected() { #expect(throws: (any Error).self) { try JSONValue.number(.nan).encoded() } }
    @Test func exactLargeRevision() throws { #expect(try JSONValue.decode(Data("9007199254740993".utf8)).integer == 9007199254740993) }
    @Test func nativeLibraryMissingFailsClosed() { #expect(throws: EngineError.nativeEngineNotLinked) { try NativeEngineTransport() } }
    @Test func envelope() async throws {
        let t = RecordingTransport(); _ = try await EngineClient(transport:t).capabilities(); let calls = await t.calls()
        #expect(calls.first?["op"] == .string("capabilities")); #expect(calls.first?["protocol"] == .integer(1))
    }
    @Test func badProtocol() async {
        let t = RecordingTransport(reply: .object(["protocol":.integer(2),"ok":.bool(true)]))
        await #expect(throws: (any Error).self) { try await EngineClient(transport:t).capabilities() }
    }
    @Test func errorCode() async {
        let t = RecordingTransport(reply: .object(["protocol":.integer(1),"ok":.bool(false),"error":.object(["code":.string("stale"),"message":.string("Refresh")])]))
        await #expect(throws: EngineError.rejected(code:"stale",message:"Refresh")) { try await EngineClient(transport:t).capabilities() }
    }
    @Test func promptMetadata() throws {
        let p = try EnginePrompt(promptValue()), id = UUID(); let c = p.command(answer:EnginePrompt.answer("boolean",.bool(false)),requestID:id)
        #expect(c["promptRevision"] == .integer(7)); #expect(c["promptId"] == .string("prompt"))
        #expect(c["requestId"]?.string == id.uuidString.lowercased()); #expect(c["viewerId"] == nil)
    }
    @Test func malformedPrompt() { #expect(throws:(any Error).self) { try EnginePrompt(.object([:])) } }
    @Test func pollDecodes() throws { #expect(try MatchPoll(pollValue()).revision == 3) }
    @Test func authenticatedActor() async throws {
        let (r,t,_,e) = try await setup()
        _ = try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"poll",payload:.object(["after":.integer(0)])),authenticatedPeerID:"peer")
        let calls = await t.calls(); #expect(calls.last?["viewerId"] == .string("seat-2")); #expect(calls.last?["matchId"] == .string("match"))
    }
    @Test func spoofedActorRejected() async throws {
        let (r,_,_,e) = try await setup()
        await #expect(throws:(any Error).self) { try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"poll",payload:.object(["after":.integer(0),"viewerId":.string("host")])),authenticatedPeerID:"peer") }
    }
    @Test func unboundPeer() async throws {
        let (r,_,_,e) = try await setup()
        await #expect(throws:EngineError.unboundPeer) { try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"poll",payload:.null),authenticatedPeerID:"intruder") }
    }
    @Test func replayRejected() async throws {
        let (r,_,b,e) = try await setup()
        await #expect(throws:EngineError.replayedMessage) { try await r.handle(PeerFrame(epoch:e,sequence:1,operation:"hello",payload:b.json),authenticatedPeerID:"peer") }
    }
    @Test func otherEpoch() async throws {
        let (r,_,b,_) = try await setup()
        await #expect(throws:EngineError.incompatibleBuild) { try await r.handle(PeerFrame(epoch:UUID(),sequence:2,operation:"hello",payload:b.json),authenticatedPeerID:"peer") }
    }
    @Test func buildMismatch() async throws {
        let (r,_,_,e) = try await setup()
        await #expect(throws:EngineError.incompatibleBuild) { try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"hello",payload:.object([:])),authenticatedPeerID:"peer") }
    }
    @Test func noAdministrativeOps() async throws {
        let (r,_,_,e) = try await setup()
        await #expect(throws:(any Error).self) { try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"destroy",payload:.object([:])),authenticatedPeerID:"peer") }
    }
    @Test func diagnosticsNeverReachEngineFromPeer() async throws {
        for operation in ["diagnostics", "clearDiagnostics"] {
            let (router, transport, _, epoch) = try await setup()
            await #expect(throws: (any Error).self) {
                try await router.handle(PeerFrame(epoch: epoch, sequence: 2, operation: operation, payload: .object([:])), authenticatedPeerID: "peer")
            }
            #expect(await transport.calls().isEmpty)
        }
    }
    @Test func suspensionBlocksInput() async throws {
        let (r,_,_,e) = try await setup(); await r.setSuspended(true)
        await #expect(throws:EngineError.hostSuspended) { try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"respond",payload:.object([:])),authenticatedPeerID:"peer") }
    }
    @Test func staleSuspensionUpdatesCannotOverrideLatestPresence() async throws {
        let (r,_,_,e) = try await setup()
        await r.setSuspended(false, revision: 2)
        await r.setSuspended(true, revision: 1)
        let answer: JSONValue = .object(["requestId": .string(UUID().uuidString), "promptId": .string("prompt"),
                                         "promptRevision": .integer(7), "answer": .bool(true)])
        _ = try await r.handle(PeerFrame(epoch: e, sequence: 2, operation: "respond", payload: answer), authenticatedPeerID: "peer")
        await r.setSuspended(true, revision: 3)
        await r.setSuspended(false, revision: 2)
        await #expect(throws: EngineError.hostSuspended) {
            try await r.handle(PeerFrame(epoch: e, sequence: 3, operation: "respond", payload: answer), authenticatedPeerID: "peer")
        }
    }
    @Test func peerConcedesOnlyItsOwnSeatEvenWhileSuspended() async throws {
        let (r,t,_,e) = try await setup(); await r.setSuspended(true)
        _ = try await r.handle(PeerFrame(epoch:e,sequence:2,operation:"concede",payload:.object([:])),authenticatedPeerID:"peer")
        let call = await t.calls().last
        #expect(call?["op"] == .string("concede")); #expect(call?["viewerId"] == .string("seat-2")); #expect(call?["matchId"] == .string("match"))
        await #expect(throws:(any Error).self) {
            try await r.handle(PeerFrame(epoch:e,sequence:3,operation:"concede",payload:.object(["viewerId":.string("host")])),authenticatedPeerID:"peer")
        }
        await #expect(throws:EngineError.unboundPeer) {
            try await r.handle(PeerFrame(epoch:e,sequence:4,operation:"concede",payload:.object([:])),authenticatedPeerID:"intruder")
        }
    }
    @Test func concedeEnvelope() async throws {
        let t = RecordingTransport(); try await EngineClient(transport:t).concede(matchID:"m",seatID:"s")
        let call = await t.calls().first
        #expect(call?["op"] == .string("concede")); #expect(call?["viewerId"] == .string("s")); #expect(call?["matchId"] == .string("m"))
    }
    @Test func duplicateSeatBinding() async throws {
        let (r,_,_,_) = try await setup()
        await #expect(throws:(any Error).self) { try await r.bind(authenticatedPeerID:"other",seatID:"seat-2") }
    }
    @Test func reversedChunks() async throws {
        let data = Data((0..<40000).map{ UInt8($0%251) }), a = PacketAssembler(); var result:Data?
        for c in try PacketChunk.split(data).reversed() { if let d = try await a.receive(c,from:"A") { result = d } }
        #expect(result == data); #expect(await a.pendingCount() == 0)
    }
    @Test @MainActor func packetIngressPreservesOrderAndSurvivesBadChunks() async throws {
        var received: [Data] = [], rejected: [String] = []
        let ingress = OrderedPacketIngress(onPacket: { data, peer in
            #expect(peer == "peer"); received.append(data)
        }, onPacketRejected: { peer in rejected.append(peer) })
        #expect(ingress.receive(Data("not a chunk".utf8), from: "peer"))
        let messages = (0..<20).map { Data(repeating: UInt8($0), count: 20_000) }
        for message in messages {
            for chunk in try PacketChunk.split(message).reversed() {
                #expect(ingress.receive(try JSONEncoder().encode(chunk), from: "peer"))
            }
        }
        for _ in 0..<10_000 { if received.count == messages.count { break }; await Task.yield() }
        #expect(received == messages)
        #expect(rejected == ["peer"])
    }
    @Test @MainActor func packetIngressRetainsPartialMessagesAcrossIdleAndDropsAfterClose() async throws {
        var received: [Data] = []
        let ingress = OrderedPacketIngress(onPacket: { data, _ in received.append(data) })
        let message = Data(repeating: 42, count: 10_000), marker = Data("marker".utf8)
        let chunks = try PacketChunk.split(message)
        #expect(ingress.receive(try JSONEncoder().encode(chunks[0]), from: "peer"))
        #expect(ingress.receive(try JSONEncoder().encode(PacketChunk.split(marker)[0]), from: "peer"))
        for _ in 0..<10_000 { if received == [marker] { break }; await Task.yield() }
        #expect(received == [marker])
        // Let the consumer become idle before the remaining network fragment arrives.
        for _ in 0..<20 { await Task.yield() }
        #expect(ingress.receive(try JSONEncoder().encode(chunks[1]), from: "peer"))
        for _ in 0..<10_000 { if received.count == 2 { break }; await Task.yield() }
        #expect(received == [marker, message])
        ingress.close()
        #expect(!ingress.receive(try JSONEncoder().encode(chunks[0]), from: "peer"))
        #expect(received == [marker, message])
    }
    @Test func chunksPeerScoped() async throws {
        let c = try PacketChunk.split(Data(repeating:1,count:10000)), a = PacketAssembler()
        #expect(try await a.receive(c[0],from:"A") == nil); #expect(try await a.receive(c[1],from:"B") == nil)
        #expect(try await a.receive(c[1],from:"A")?.count == 10000)
    }
    @Test func invalidChunk() async {
        let a = PacketAssembler()
        await #expect(throws:(any Error).self) { try await a.receive(PacketChunk(id:UUID(),index:-1,count:1,totalBytes:3,bytes:Data([1,2,3])),from:"A") }
    }
    @Test func conflictingDuplicateChunk() async throws {
        let chunks = try PacketChunk.split(Data(repeating:1,count:10000)), a = PacketAssembler(); let c = chunks[0]
        _ = try await a.receive(c,from:"A")
        await #expect(throws:(any Error).self) { try await a.receive(PacketChunk(id:c.id,index:c.index,count:c.count,totalBytes:c.totalBytes,bytes:Data(repeating:2,count:c.bytes.count)),from:"A") }
    }
    @Test func identicalDuplicateChunk() async throws {
        let c = try PacketChunk.split(Data(repeating:1,count:10000)), a = PacketAssembler()
        _ = try await a.receive(c[0],from:"A"); _ = try await a.receive(c[0],from:"A")
        #expect(try await a.receive(c[1],from:"A")?.count == 10000)
    }
    @Test func assemblyQuota() async throws {
        let a = PacketAssembler()
        for _ in 0..<4 { _ = try await a.receive(PacketChunk.split(Data(repeating:1,count:10000))[0],from:"A",now:1) }
        await #expect(throws:EngineError.messageTooLarge) { try await a.receive(PacketChunk.split(Data(repeating:1,count:10000))[0],from:"A",now:1) }
    }
    @Test func assemblyExpiry() async throws {
        let a = PacketAssembler()
        _ = try await a.receive(PacketChunk.split(Data(repeating:1,count:10000))[0],from:"A",now:1)
        _ = try await a.receive(PacketChunk.split(Data(repeating:1,count:10000))[0],from:"B",now:17)
        #expect(await a.pendingCount() == 1)
    }
    @Test func dropPeer() async throws {
        let a = PacketAssembler(); _ = try await a.receive(PacketChunk.split(Data(repeating:1,count:10000))[0],from:"A")
        await a.drop(peer:"A"); #expect(await a.pendingCount() == 0)
    }
}
