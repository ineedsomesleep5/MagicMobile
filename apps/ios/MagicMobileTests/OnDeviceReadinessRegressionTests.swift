import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Protocol fixtures exercise production session state, not XMage/device gameplay.
final class OnDeviceReadinessRegressionTests: XCTestCase {
    @MainActor
    func testEqualRevisionDelayedPollCannotRestoreSubmittedChoice() async throws {
        let original = try fixture()
        let transport = ReadinessTransport(original.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: original.matchID,
                                 seatID: original.seatID, autoPoll: false, close: {})
        XCTAssertNotNil(session.snapshot?.promptEnvelopeV2)
        let gate = await transport.holdNextPoll()
        let delayed = Task { try await session.refresh() }
        await gate.waitUntilEntered()
        // MatchMailbox.submit marks submitted without incrementing the match revision.
        await transport.markSubmitted()
        try await session.refresh()
        XCTAssertNil(session.snapshot?.promptEnvelopeV2)
        XCTAssertEqual(session.snapshot?.pendingStatus, "waiting_for_xmage")
        await gate.release()
        try await delayed.value
        XCTAssertNil(session.snapshot?.promptEnvelopeV2, "An older equal-revision response restored the decision")
        XCTAssertEqual(session.snapshot?.pendingStatus, "waiting_for_xmage")
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(original.revision))
        try await session.close()
    }

    @MainActor
    func testClosedPollRemovesPrivateBoardAndDoesNotReportLive() async throws {
        let original = try fixture()
        let transport = ReadinessTransport(original.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: original.matchID,
                                 seatID: original.seatID, autoPoll: false, close: {})
        XCTAssertEqual(session.snapshot?.human?.zones.hand.count, 7)
        await transport.closePoll()
        try await session.refresh()
        XCTAssertNil(session.snapshot, "Discarded match retained its private hand and legal actions")
        XCTAssertEqual(session.status, "Game closed")
        XCTAssertNil(session.pendingActionID)
        // Keep ownership until explicit shutdown completes; a closed match is not a win.
        XCTAssertEqual(session.matchID, original.matchID)
        try await session.close()
    }

    @MainActor
    func testBusyShutdownBlocksNewResponseBeforeItReachesEngine() async throws {
        let original = try fixture()
        let transport = ReadinessTransport(original.raw)
        let session = OnDeviceSession()
        var attempts = 0
        try await session.attach(client: EngineClient(transport: transport), matchID: original.matchID,
                                 seatID: original.seatID, autoPoll: false) {
            attempts += 1
            if attempts == 1 { throw EngineError.rejected(code: "engine_busy_shutdown", message: "Still closing") }
        }
        let command = GameCommand(type: "answer_yes_no", gameId: original.matchID,
                                  playerId: try XCTUnwrap(session.snapshot?.viewerID),
                                  promptId: try XCTUnwrap(original.prompt?.id),
                                  messageId: Int(try XCTUnwrap(original.prompt?.revision)), confirmed: false)
        do { try await session.close(); XCTFail("Expected pending shutdown") } catch { }
        do { try await session.send(command, label: "Keep hand", actionID: "keep"); XCTFail("Answered a closing match") } catch { }
        let sent = await transport.responseCount()
        XCTAssertEqual(sent, 0, "Input must be blocked locally after shutdown starts")
        try await session.close()
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(session.matchID)
    }

    private func fixture() throws -> MatchPoll {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "2p-initial-player-1", withExtension: "json", subdirectory: "OnDevice"))
        return try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)))
    }
}

private actor ReadinessTransport: EngineTransport {
    private var poll: MagicMobileOnDevice.JSONValue
    private var gate: ReadinessGate?
    private var sent = 0
    init(_ poll: MagicMobileOnDevice.JSONValue) { self.poll = poll }
    func request(_ data: Data) async throws -> Data {
        let request = try MagicMobileOnDevice.JSONValue.decode(data)
        let result: MagicMobileOnDevice.JSONValue
        switch request["op"]?.string {
        case "poll":
            result = poll
            if let held = gate { gate = nil; await held.wait() }
        case "respond":
            sent += 1
            result = .object(["status": .string("queued")])
        default: throw EngineError.invalidMessage("Unexpected readiness fixture operation")
        }
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func holdNextPoll() -> ReadinessGate { let held = ReadinessGate(); gate = held; return held }
    func markSubmitted() {
        var fields = poll.object!
        var prompt = fields["prompt"]!.object!
        prompt["submitted"] = .bool(true)
        fields["prompt"] = .object(prompt)
        poll = .object(fields)
    }
    func closePoll() {
        var fields = poll.object!
        fields["phase"] = .string("closed")
        fields["snapshot"] = .null
        fields["prompt"] = .null
        fields["events"] = .array([])
        fields["revision"] = .integer(poll["revision"]!.integer! + 1)
        poll = .object(fields)
    }
    func responseCount() -> Int { sent }
}

private actor ReadinessGate {
    private var blocked: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            blocked = continuation
            entered?.resume(); entered = nil
        }
    }
    func waitUntilEntered() async {
        guard blocked == nil else { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
}
