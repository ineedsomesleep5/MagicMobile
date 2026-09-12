import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class OnDeviceSessionTests: XCTestCase {
    @MainActor
    func testRefreshResumesPeriodicPollingAfterTransientFailure() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, close: {})
        await transport.failNextPoll()
        for _ in 0..<200 where session.errorMessage == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(session.errorMessage)
        try await session.refresh()
        XCTAssertNil(session.errorMessage)
        await transport.consumePrompt()
        for _ in 0..<200 where session.snapshot?.bridgeRevision == Int(poll.revision) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision + 1))
        try await session.close()
    }

    @MainActor
    func testCloseDiscardsOutstandingRefreshWhileShutdownIsPending() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        let shutdown = SessionGate()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false) {
            await shutdown.wait()
        }
        await transport.consumePrompt()
        let heldPoll = await transport.suspendNextPoll()
        let refresh = Task { try await session.refresh() }
        await heldPoll.waitUntilEntered()
        let close = Task { try await session.close() }
        await shutdown.waitUntilEntered()
        await heldPoll.release()
        try await refresh.value
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision))
        await shutdown.release()
        try await close.value
        XCTAssertNil(session.matchID)
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(session.status, "Ready")
    }

    @MainActor
    func testClosedSessionRefreshCannotReplaceReattachedMatch() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        await transport.consumePrompt()
        let heldPoll = await transport.suspendNextPoll()
        let oldRefresh = Task { try await session.refresh() }
        await heldPoll.waitUntilEntered()
        try await session.close()
        XCTAssertNil(session.snapshot)
        let replacement = SessionFixtureTransport(poll: poll.raw)
        try await session.attach(client: EngineClient(transport: replacement), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        await heldPoll.release()
        try await oldRefresh.value
        XCTAssertEqual(session.matchID, poll.matchID)
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision))
        XCTAssertEqual(session.status, "Live")
        XCTAssertNil(session.errorMessage)
        try await session.close()
    }

    @MainActor
    func testOutOfOrderPollCannotRestoreConsumedPromptOrOlderSnapshot() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let command = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                  promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false,
                                  expectedBridgeRevision: Int(poll.revision))
        try await session.send(command, label: "Keep hand", actionID: "keep")
        XCTAssertEqual(session.pendingActionID, "keep")
        let heldPoll = await transport.suspendNextPoll()
        let olderRefresh = Task { try await session.refresh() }
        await heldPoll.waitUntilEntered()
        await transport.consumePrompt()
        try await session.refresh()
        XCTAssertNil(session.pendingActionID)
        await heldPoll.release()
        try await olderRefresh.value
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision + 1))
        XCTAssertNil(session.pendingActionID)
        let staleCommand = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                       promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false)
        do { try await session.send(staleCommand, label: "Keep hand", actionID: "keep"); XCTFail("Restored consumed prompt") } catch { }
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 1)
        try await session.close()
    }

    @MainActor
    func testSessionRejectsWrongMatchBeforeTransport() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let command = GameCommand(type: "answer_yes_no", gameId: "wrong-match", playerId: session.snapshot!.viewerID,
                                  promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false,
                                  expectedBridgeRevision: Int(poll.revision))
        do { try await session.send(command, label: "No", actionID: "no"); XCTFail("Wrong game accepted") }
        catch { }
        let requests = await transport.responses()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(session.pendingActionID)
        try await session.close()
    }

    @MainActor
    func testUncertainResponseRetryReusesRequestIDAndWaitsForConsumption() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw, responseFailures: [URLError(.timedOut)])
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let command = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                  promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false,
                                  expectedBridgeRevision: Int(poll.revision))
        do { try await session.send(command, label: "Keep hand", actionID: "keep"); XCTFail("Expected timeout") }
        catch { }
        XCTAssertEqual(session.pendingActionID, "keep")
        try await session.retryPending()
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["command"], sent[1]["command"])
        XCTAssertEqual(session.pendingActionID, "keep")
        await transport.consumePrompt()
        try await session.refresh()
        XCTAssertNil(session.pendingActionID)
        XCTAssertEqual(session.snapshot?.human?.zones.hand.count, 7)
        try await session.close()
    }

    @MainActor
    func testRPCBusyAfterTimeoutRetainsExactResponseForRetry() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw, responseFailures: [
            URLError(.timedOut), EngineError.rejected(code: "rpc_busy", message: "Previous request is outstanding")
        ])
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let command = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                  promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false,
                                  expectedBridgeRevision: Int(poll.revision))
        do { try await session.send(command, label: "Keep hand", actionID: "keep"); XCTFail("Expected timeout") } catch { }
        do { try await session.retryPending(); XCTFail("Expected busy transport") } catch {
            XCTAssertEqual(error as? EngineError, .rejected(code: "rpc_busy", message: "Previous request is outstanding"))
        }
        XCTAssertEqual(session.pendingActionID, "keep")
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision))
        XCTAssertFalse(session.isWorking)
        try await session.retryPending()
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 3)
        XCTAssertNotNil(sent.first?["command"]?["requestId"]?.string)
        XCTAssertTrue(sent.allSatisfy { $0["command"] == sent.first?["command"] })
        XCTAssertEqual(session.pendingActionID, "keep")
        await transport.consumePrompt()
        try await session.refresh()
        XCTAssertNil(session.pendingActionID)
        try await session.close()
    }

    @MainActor
    func testDefiniteEngineRejectionClearsPendingResponse() async throws {
        let poll = try fixture()
        let rejection = EngineError.rejected(code: "stale_prompt", message: "Decision changed")
        let transport = SessionFixtureTransport(poll: poll.raw, responseFailures: [rejection])
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let command = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                  promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false)
        do { try await session.send(command, label: "Keep hand", actionID: "keep"); XCTFail("Expected rejection") } catch {
            XCTAssertEqual(error as? EngineError, rejection)
        }
        XCTAssertNil(session.pendingActionID)
        XCTAssertNil(session.pendingCardID)
        XCTAssertFalse(session.isWorking)
        do { try await session.retryPending(); XCTFail("Retried a rejected response") } catch { }
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 1)
        try await session.close()
    }

    @MainActor
    func testBusyShutdownRetainsSeatAndSnapshotUntilSuccessfulRetry() async throws {
        let poll = try fixture()
        let client = EngineClient(transport: SessionFixtureTransport(poll: poll.raw))
        let session = OnDeviceSession()
        var closes = 0
        try await session.attach(client: client, matchID: poll.matchID, seatID: poll.seatID, autoPoll: false) {
            closes += 1
            if closes == 1 { throw EngineError.rejected(code: "engine_busy_shutdown", message: "Still closing") }
        }
        do { try await session.close(); XCTFail("Busy shutdown was discarded") } catch { }
        XCTAssertEqual(session.matchID, poll.matchID)
        XCTAssertNotNil(session.snapshot)
        XCTAssertFalse(session.isWorking)
        do { try await session.attach(client: client, matchID: "new", seatID: "other", autoPoll: false, close: {}); XCTFail("Replaced retained match") } catch { }
        try await session.close()
        XCTAssertEqual(closes, 2)
        XCTAssertNil(session.matchID)
        XCTAssertNil(session.snapshot)
    }

    @MainActor
    func testBackgroundPreventsNewAnswers() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        session.setForeground(false)
        let command = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                  promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false)
        do { try await session.send(command, label: "No", actionID: "no"); XCTFail("Sent while backgrounded") } catch { }
        let sent = await transport.responses()
        XCTAssertTrue(sent.isEmpty)
        try await session.close()
    }

    @MainActor
    func testCardActionUsesCanonicalPromptAndObjectUUID() async throws {
        let poll = try fixture("2p-priority")
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID, seatID: poll.seatID, autoPoll: false, close: {})
        let action = try XCTUnwrap(session.snapshot?.legalActions?.first { $0.type == "play_land" })
        try await session.send(action: action)
        let sent = await transport.responses()
        XCTAssertEqual(sent.first?["command"]?["promptId"]?.string, poll.prompt?.id)
        XCTAssertEqual(sent.first?["command"]?["promptRevision"]?.integer, poll.prompt?.revision)
        XCTAssertEqual(sent.first?["command"]?["answer"], EnginePrompt.answer("uuid", .string(action.cardInstanceId!)))
        try await session.close()
    }

    private func fixture(_ name: String = "2p-initial-player-1") throws -> MatchPoll {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "OnDevice"))
        return try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)))
    }
}

private actor SessionFixtureTransport: EngineTransport {
    private var poll: MagicMobileOnDevice.JSONValue
    private var sent: [MagicMobileOnDevice.JSONValue] = []
    private var responseFailures: [Error]
    private var shouldFailPoll = false
    private var pollGate: SessionGate?
    init(poll: MagicMobileOnDevice.JSONValue, responseFailures: [Error] = []) { self.poll = poll; self.responseFailures = responseFailures }
    func request(_ data: Data) async throws -> Data {
        let request = try MagicMobileOnDevice.JSONValue.decode(data)
        let result: MagicMobileOnDevice.JSONValue
        if request["op"]?.string == "poll" {
            if shouldFailPoll { shouldFailPoll = false; throw URLError(.timedOut) }
            result = poll
            if let gate = pollGate {
                pollGate = nil
                await gate.wait()
            }
        }
        else if request["op"]?.string == "respond" {
            sent.append(request)
            if !responseFailures.isEmpty { throw responseFailures.removeFirst() }
            result = .object(["status": .string("queued")])
        } else { throw EngineError.invalidMessage("Unexpected fixture operation") }
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func responses() -> [MagicMobileOnDevice.JSONValue] { sent }
    func failNextPoll() { shouldFailPoll = true }
    func suspendNextPoll() -> SessionGate {
        let gate = SessionGate()
        pollGate = gate
        return gate
    }
    func consumePrompt() {
        var fields = poll.object!
        fields["prompt"] = .null
        fields["revision"] = .integer(poll["revision"]!.integer! + 1)
        poll = .object(fields)
    }
}

private actor SessionGate {
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

    func release() {
        blocked?.resume(); blocked = nil
    }
}
