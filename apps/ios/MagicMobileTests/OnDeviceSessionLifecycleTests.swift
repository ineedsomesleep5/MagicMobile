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
        try await gate.waitUntilEntered()
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
        try await gate.waitUntilEntered()
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
    private var held: (LifecycleGate, Error?)?
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
    func holdNextPoll(failure: Error? = nil) -> LifecycleGate {
        let gate = LifecycleGate(); held = (gate, failure); return gate
    }
    func consumePrompt() {
        var fields = poll.object!
        fields["prompt"] = .null
        fields["revision"] = .integer(poll["revision"]!.integer! + 1)
        poll = .object(fields)
    }
}



/// Control-flow regressions using transport fixtures, not native/gameplay acceptance.
final class OnDeviceSessionLifecycleTests: XCTestCase {
    @MainActor
    func testNewRefreshCannotEnterWhileCloseIsSuspended() async throws {
        let initial = try fixture()
        let transport = LifecyclePollTransport(initial.raw)
        let session = OnDeviceSession()
        let shutdown = LifecycleGate()
        try await session.attach(client: EngineClient(transport: transport), matchID: initial.matchID,
                                 seatID: initial.seatID, autoPoll: false) { await shutdown.wait() }
        let close = Task { try await session.close() }
        try await shutdown.waitUntilEntered()
        await transport.advance()
        try await session.refresh()
        let requests = await transport.requestCount()
        XCTAssertEqual(requests, 1, "A fresh refresh must not enter an engine being closed")
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(initial.revision))
        await shutdown.release()
        try await close.value
        XCTAssertNil(session.snapshot)
        XCTAssertNil(session.matchID)
    }

    @MainActor
    func testBackgroundDiscardsAnAlreadyRequestedPoll() async throws {
        let initial = try fixture()
        let transport = LifecyclePollTransport(initial.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: initial.matchID,
                                 seatID: initial.seatID, autoPoll: false, close: {})
        await transport.advance()
        let gate = await transport.holdNext()
        let refresh = Task { try await session.refresh() }
        try await gate.waitUntilEntered()
        session.setForeground(false)
        await gate.release()
        try await refresh.value
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(initial.revision))
        XCTAssertEqual(session.status, "Paused while this app is in the background")
        try await session.close()
    }

    @MainActor
    func testCancellationDiscardsAnAlreadyRequestedPoll() async throws {
        let initial = try fixture()
        let transport = LifecyclePollTransport(initial.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: initial.matchID,
                                 seatID: initial.seatID, autoPoll: false, close: {})
        await transport.advance()
        let gate = await transport.holdNext()
        let refresh = Task { try await session.refresh() }
        try await gate.waitUntilEntered()
        refresh.cancel()
        await gate.release()
        try await refresh.value
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(initial.revision))
        try await session.close()
    }

    @MainActor
    func testClosedPollErasesTheOldPrivateSnapshot() async throws {
        let initial = try fixture()
        let transport = LifecyclePollTransport(initial.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: initial.matchID,
                                 seatID: initial.seatID, autoPoll: false, close: {})
        XCTAssertNotNil(session.snapshot)
        await transport.markClosed()
        try await session.refresh()
        XCTAssertNil(session.snapshot)
        XCTAssertNil(session.pendingActionID)
        XCTAssertEqual(session.status, "Game closed")
        try await session.close()
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

private actor LifecyclePollTransport: EngineTransport {
    private var value: MagicMobileOnDevice.JSONValue
    private var count = 0
    private var gate: LifecycleGate?
    init(_ value: MagicMobileOnDevice.JSONValue) { self.value = value }
    func request(_ data: Data) async throws -> Data {
        guard try MagicMobileOnDevice.JSONValue.decode(data)["op"]?.string == "poll" else {
            throw EngineError.invalidMessage("Only fixture polls are permitted")
        }
        count += 1
        let captured = value
        if let held = gate { gate = nil; await held.wait() }
        return try MagicMobileOnDevice.JSONValue.object([
            "protocol": .integer(1), "ok": .bool(true), "result": captured
        ]).encoded()
    }
    func requestCount() -> Int { count }
    func holdNext() -> LifecycleGate { let result = LifecycleGate(); gate = result; return result }
    func advance() {
        var fields = value.object!
        fields["revision"] = .integer(value["revision"]!.integer! + 1)
        value = .object(fields)
    }
    func markClosed() {
        advance()
        var fields = value.object!
        fields["phase"] = .string("closed"); fields["snapshot"] = .null; fields["prompt"] = .null
        fields["events"] = .array([])
        value = .object(fields)
    }
}

private actor LifecycleGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async throws {
        for _ in 0..<400 {
            if entered { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw EngineError.invalidMessage("Lifecycle fixture did not enter its gate")
    }
    func release() { continuation?.resume(); continuation = nil }
}
