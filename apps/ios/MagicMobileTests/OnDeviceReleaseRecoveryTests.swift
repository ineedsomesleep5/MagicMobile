import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Session/transport fixtures only. Native XMage and phone acceptance are separate.
final class OnDeviceReleaseRecoveryTests: XCTestCase {
    @MainActor
    func testAcknowledgedAnswerSurvivesRejectedFollowupPoll() async throws {
        let poll = try fixture()
        let transport = RecoveryTransport(poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        await transport.rejectPollAfterNextAnswer()
        let command = try keepCommand(session, poll)
        do { try await session.send(command, label: "Keep", actionID: "keep"); XCTFail("Expected poll rejection") } catch {}
        XCTAssertEqual(session.pendingActionID, "keep", "A read failure cannot retract an acknowledged response")
        try await session.retryPending()
        let replies = await transport.answers()
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies.first?["command"], replies.last?["command"], "Retry must keep the exact request ID")
        try await session.close()
    }

    @MainActor
    func testBackgroundDiscardsOutstandingPoll() async throws {
        try await checkSuspendedPoll(resumeBeforeReply: false)
    }

    @MainActor
    func testResumeDoesNotAcceptAPreSuspensionPoll() async throws {
        try await checkSuspendedPoll(resumeBeforeReply: true)
    }

    @MainActor
    private func checkSuspendedPoll(resumeBeforeReply: Bool) async throws {
        let poll = try fixture()
        let transport = RecoveryTransport(poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        await transport.consumePrompt()
        let gate = await transport.holdNextPoll()
        let refresh = Task { try await session.refresh() }
        await gate.waitUntilEntered()
        session.setForeground(false)
        if resumeBeforeReply { session.setForeground(true) }
        await gate.release()
        try await refresh.value
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision), "A pre-suspension response crossed the visibility boundary")
        if !resumeBeforeReply { XCTAssertTrue(session.status.contains("background")) }
        session.setForeground(true)
        try await session.refresh()
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision + 1))
        try await session.close()
    }

    @MainActor
    func testBusyCloseRejectsNewWorkUntilCloseSucceeds() async throws {
        let poll = try fixture()
        let transport = RecoveryTransport(poll.raw)
        let session = OnDeviceSession()
        var closes = 0
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false) {
            closes += 1
            if closes == 1 { throw EngineError.rejected(code: "engine_busy_shutdown", message: "Still closing") }
        }
        let command = try keepCommand(session, poll)
        do { try await session.close(); XCTFail("Expected busy close") } catch {}
        let before = await transport.pollCount()
        session.setForeground(false); session.setForeground(true)
        try await session.refresh()
        let after = await transport.pollCount()
        XCTAssertEqual(before, after, "Closing cannot restart polling")
        do { try await session.send(command, label: "Keep", actionID: "keep"); XCTFail("Answered a closing engine") } catch {}
        let answers = await transport.answers()
        XCTAssertTrue(answers.isEmpty)
        XCTAssertEqual(session.matchID, poll.matchID, "Retain the handle for cleanup retry")
        try await session.close()
        XCTAssertNil(session.matchID)
        XCTAssertEqual(closes, 2)
    }

    @MainActor
    func testUnexpectedTransportCancellationCanResumePolling() async throws {
        let poll = try fixture()
        let transport = RecoveryTransport(poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, close: {})
        await transport.cancelNextPoll()
        for _ in 0..<200 where session.errorMessage == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(session.errorMessage, "Unexpected transport cancellation cannot leave a dead polling task registered")
        try await session.refresh()
        XCTAssertNil(session.errorMessage)
        await transport.consumePrompt()
        for _ in 0..<200 where session.snapshot?.bridgeRevision == Int(poll.revision) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision + 1))
        try await session.close()
    }

    @MainActor
    func testOldRefreshErrorDoesNotEscapeIntoReplacementSession() async throws {
        let poll = try fixture()
        let transport = RecoveryTransport(poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let gate = await transport.holdNextPoll(failure: URLError(.timedOut))
        let refresh = Task { try await session.refresh() }
        await gate.waitUntilEntered()
        try await session.close()
        let replacement = RecoveryTransport(poll.raw)
        try await session.attach(client: EngineClient(transport: replacement), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        await gate.release()
        do { try await refresh.value } catch { XCTFail("Stale error escaped into a replacement session: \(error)") }
        XCTAssertEqual(session.status, "Live")
        XCTAssertNil(session.errorMessage)
        try await session.close()
    }

    @MainActor
    private func keepCommand(_ session: OnDeviceSession, _ poll: MatchPoll) throws -> GameCommand {
        let viewer = try XCTUnwrap(session.snapshot?.viewerID)
        let prompt = try XCTUnwrap(poll.prompt)
        return GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: viewer,
                           promptId: prompt.id, messageId: Int(prompt.revision), confirmed: false)
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

private actor RecoveryTransport: EngineTransport {
    private var poll: MagicMobileOnDevice.JSONValue
    private var sent: [MagicMobileOnDevice.JSONValue] = []
    private var polls = 0
    private var nextFailure: Error?
    private var rejectAfterAnswer = false
    private var held: (RecoveryGate, Error?)?
    init(_ poll: MagicMobileOnDevice.JSONValue) { self.poll = poll }
    func request(_ data: Data) async throws -> Data {
        let request = try MagicMobileOnDevice.JSONValue.decode(data)
        let result: MagicMobileOnDevice.JSONValue
        switch request["op"]?.string {
        case "poll":
            polls += 1
            if let failure = nextFailure { nextFailure = nil; throw failure }
            result = poll
            if let (gate, failure) = held {
                held = nil
                await gate.wait()
                if let failure { throw failure }
            }
        case "respond":
            sent.append(request)
            if rejectAfterAnswer {
                rejectAfterAnswer = false
                nextFailure = EngineError.rejected(code: "invalid_cursor", message: "Poll cursor rejected")
            }
            result = .object(["status": .string("queued")])
        default: throw EngineError.invalidMessage("Unexpected fixture operation")
        }
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func answers() -> [MagicMobileOnDevice.JSONValue] { sent }
    func pollCount() -> Int { polls }
    func rejectPollAfterNextAnswer() { rejectAfterAnswer = true }
    func cancelNextPoll() { nextFailure = CancellationError() }
    func holdNextPoll(failure: Error? = nil) -> RecoveryGate {
        let gate = RecoveryGate(); held = (gate, failure); return gate
    }
    func consumePrompt() {
        var fields = poll.object!
        fields["prompt"] = .null
        fields["revision"] = .integer(poll["revision"]!.integer! + 1)
        poll = .object(fields)
    }
}

private actor RecoveryGate {
    private var blocked: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            blocked = continuation; entered?.resume(); entered = nil
        }
    }
    func waitUntilEntered() async {
        guard blocked == nil else { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
}
