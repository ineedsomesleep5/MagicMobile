import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class OnDeviceSessionTests: XCTestCase {
    @MainActor
    func testManualTapWaitsForPollAndNeverRetargetsChangedPrompt() async throws {
        for changed in [false, true] {
            let poll = try fixture("2p-priority")
            let transport = SessionFixtureTransport(poll: poll.raw)
            let session = OnDeviceSession()
            try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                     seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
            let action = try XCTUnwrap(session.snapshot?.legalActions?.first(where: { $0.type == "pass_priority" }))
            if changed {
                var next = poll.raw.object!; var prompt = next["prompt"]!.object!
                prompt["promptId"] = .string("replacement-priority")
                prompt["revision"] = .integer(poll.prompt!.revision + 1)
                next["prompt"] = .object(prompt); next["revision"] = .integer(poll.revision + 1)
                await transport.replacePoll(.object(next))
            }
            session.endTurn()
            let gate = await transport.suspendNextPoll()
            let refresh = Task { try await session.refresh() }
            await gate.waitUntilEntered()
            let send = Task { try await session.send(action: action) }
            // Bounded wait lets the manual task reach its suspended-poll barrier.
            for _ in 0..<100 {
                if session.isWorking { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertTrue(session.isWorking, "Manual tap must wait, not reject an in-flight poll")
            XCTAssertFalse(session.isAutoPassing)
            let before = await transport.responses()
            XCTAssertTrue(before.isEmpty)
            await gate.release()
            try await refresh.value
            do {
                try await send.value
                if changed { XCTFail("Retargeted changed prompt") }
            } catch {
                if !changed { XCTFail("Valid manual tap rejected: \(error)") }
            }
            let sent = await transport.responses()
            XCTAssertEqual(sent.count, changed ? 0 : 1)
            if !changed {
                XCTAssertEqual(sent.first?["command"]?["promptId"]?.string, poll.prompt?.id)
                XCTAssertEqual(sent.first?["command"]?["promptRevision"]?.integer, poll.prompt?.revision)
            }
            let overlap = await transport.maximumConcurrentRequests()
            XCTAssertEqual(overlap, 1)
            XCTAssertFalse(session.isWorking)
            try await session.close()
        }
    }

    @MainActor
    func testCancelledManualWaitReleasesResponseSlotWithoutSending() async throws {
        let poll = try fixture("2p-priority")
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                 seatID: poll.seatID, autoPoll: false, close: {})
        let action = try XCTUnwrap(session.snapshot?.legalActions?.first(where: { $0.type == "pass_priority" }))
        let gate = await transport.suspendNextPoll()
        let refresh = Task { try await session.refresh() }
        await gate.waitUntilEntered()
        let send = Task { try await session.send(action: action) }
        for _ in 0..<100 {
            if session.isWorking { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(session.isWorking)
        send.cancel()
        do { try await send.value; XCTFail("Cancelled tap sent") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(session.isWorking)
        let before = await transport.responses()
        XCTAssertTrue(before.isEmpty)
        await gate.release()
        try await refresh.value
        try await session.send(action: action)
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 1)
        let overlap = await transport.maximumConcurrentRequests()
        XCTAssertEqual(overlap, 1)
        try await session.close()
    }

    @MainActor
    func testRetryWaitsForPollAndPreservesExactRequest() async throws {
        for consumed in [false, true] {
            let poll = try fixture()
            let transport = SessionFixtureTransport(poll: poll.raw, responseFailures: [URLError(.timedOut)])
            let session = OnDeviceSession()
            try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                     seatID: poll.seatID, autoPoll: false, close: {})
            let command = GameCommand(type: "answer_yes_no", gameId: poll.matchID, playerId: session.snapshot!.viewerID,
                                      promptId: poll.prompt!.id, messageId: Int(poll.prompt!.revision), confirmed: false)
            do { try await session.send(command, label: "Keep", actionID: "keep"); XCTFail() } catch { }
            if consumed { await transport.consumePrompt() }
            let gate = await transport.suspendNextPoll()
            let refresh = Task { try await session.refresh() }
            await gate.waitUntilEntered()
            let retry = Task { try await session.retryPending() }
            for _ in 0..<100 {
                if session.isWorking { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertTrue(session.isWorking)
            await gate.release()
            try await refresh.value
            do { try await retry.value; if consumed { XCTFail("Retried consumed prompt") } }
            catch { if !consumed { XCTFail("Valid retry rejected: \(error)") } }
            let sent = await transport.responses()
            XCTAssertEqual(sent.count, consumed ? 1 : 2)
            if sent.count == 2 { XCTAssertEqual(sent[0]["command"], sent[1]["command"]) }
            let overlap = await transport.maximumConcurrentRequests()
            XCTAssertEqual(overlap, 1)
            try await session.close()
        }
    }

    @MainActor
    func testAutoPassIsOptInAndStopBeforeSchedulingSendsNothing() async throws {
        let poll = try fixture("2p-priority")
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                 seatID: poll.seatID, autoPoll: false, close: {})
        XCTAssertFalse(session.canEndTurn)
        XCTAssertFalse(session.canEndTurnSkippingResponses)
        XCTAssertFalse(session.canSkipToMyTurn)
        session.endTurnSkippingResponses(); session.skipToMyTurn()
        XCTAssertFalse(session.isAutoPassing)
        session.endTurn()
        XCTAssertFalse(session.isAutoPassing)
        try await session.close()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                 seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
        XCTAssertTrue(session.canEndTurn)
        session.endTurn(); XCTAssertTrue(session.isAutoPassing)
        session.stopAutoPass()
        try await Task.sleep(for: .milliseconds(350))
        let sent = await transport.responses()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(session.isAutoPassing)
        XCTAssertFalse(session.autoPassStatus.isEmpty)
        try await session.close()
    }

    @MainActor
    func testExplicitSkippingModesUseSameResponseIdentityAndStopAtNextOwnTurn() async throws {
        for untilMyTurn in [false, true] {
            let poll = try fixture("2p-priority")
            let transport = SessionFixtureTransport(poll: poll.raw)
            let session = OnDeviceSession()
            try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                     seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
            XCTAssertTrue(session.canEndTurnSkippingResponses)
            XCTAssertTrue(session.canSkipToMyTurn)
            if untilMyTurn { session.skipToMyTurn() } else { session.endTurnSkippingResponses() }
            try await waitForResponses(1, transport: transport)
            try await waitUntilIdle(session)
            let sent = await transport.responses()
            XCTAssertEqual(sent.count, 1)
            XCTAssertEqual(sent[0]["command"]?["promptId"]?.string, poll.prompt?.id)
            XCTAssertEqual(sent[0]["command"]?["promptRevision"]?.integer, poll.prompt?.revision)
            XCTAssertEqual(sent[0]["command"]?["answer"], EnginePrompt.answer("boolean", .bool(true)))
            var next = poll.raw.object!
            var root = next["snapshot"]!.object!; var view = root["gameView"]!.object!
            view["turn"] = .integer(view["turn"]!.integer! + 1)
            root["gameView"] = .object(view); next["snapshot"] = .object(root)
            next["revision"] = .integer(poll.revision + 1)
            await transport.replacePoll(.object(next))
            try await session.refresh()
            XCTAssertFalse(session.isAutoPassing)
            let overlap = await transport.maximumConcurrentRequests()
            XCTAssertEqual(overlap, 1)
            try await session.close()
        }
    }

    @MainActor
    func testAutoPassUsesExactIdentityOncePerPrompt() async throws {
        let poll = try fixture("2p-priority")
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                 seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
        session.endTurn()
        try await waitForResponses(1, transport: transport)
        try await Task.sleep(for: .milliseconds(350))
        var sent = await transport.responses()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["viewerId"]?.string, poll.seatID)
        XCTAssertEqual(sent[0]["command"]?["promptId"]?.string, poll.prompt?.id)
        XCTAssertEqual(sent[0]["command"]?["promptRevision"]?.integer, poll.prompt?.revision)
        XCTAssertEqual(sent[0]["command"]?["answer"], EnginePrompt.answer("boolean", .bool(true)))
        var next = poll.raw.object!
        var prompt = poll.raw["prompt"]!.object!
        prompt["promptId"] = .string("next-priority")
        prompt["revision"] = .integer(poll.prompt!.revision + 1)
        next["prompt"] = .object(prompt); next["revision"] = .integer(poll.revision + 1)
        await transport.replacePoll(.object(next))
        try await waitForResponses(2, transport: transport)
        session.stopAutoPass()
        sent = await transport.responses()
        XCTAssertEqual(sent[1]["command"]?["promptId"]?.string, "next-priority")
        XCTAssertNotEqual(sent[0]["command"]?["requestId"], sent[1]["command"]?["requestId"])
        let overlap = await transport.maximumConcurrentRequests()
        XCTAssertEqual(overlap, 1)
        try await waitUntilIdle(session)
        try await session.close()
    }

    @MainActor
    func testAutoPassStopsOnTurnChangeOrMandatoryChoice() async throws {
        for change in ["turn", "choice", "control", "failed"] {
            let poll = try fixture("2p-priority")
            let transport = SessionFixtureTransport(poll: poll.raw)
            let session = OnDeviceSession()
            try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                     seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
            session.endTurn()
            var next = poll.raw.object!
            next["revision"] = .integer(poll.revision + 1)
            if change == "failed" { next["phase"] = .string("failed") }
            else if change == "turn" {
                var root = next["snapshot"]!.object!; var view = root["gameView"]!.object!
                view["turn"] = .integer(2); root["gameView"] = .object(view); next["snapshot"] = .object(root)
            } else {
                var prompt = next["prompt"]!.object!
                if change == "choice" {
                    prompt["kind"] = .string("ASK"); prompt["responseTypes"] = .array([.string("boolean")])
                    prompt["payload"] = .object(["message": .string("Choose"), "required": .bool(true)])
                } else {
                    var payload = prompt["payload"]!.object!; payload["manaPlayerId"] = .string(poll.snapshot!["gameView"]!["players"]!.array!.first!["playerId"]!.string!)
                    prompt["payload"] = .object(payload)
                }
                next["prompt"] = .object(prompt)
            }
            await transport.replacePoll(.object(next))
            try await session.refresh()
            XCTAssertFalse(session.isAutoPassing, change)
            let sent = await transport.responses()
            XCTAssertTrue(sent.isEmpty, change)
            try await session.close()
        }
    }

    @MainActor
    func testBackgroundDuringResponseStopsWithoutPollOverlapOrAutomaticRetry() async throws {
        let poll = try fixture("2p-priority")
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                 seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
        let gate = await transport.suspendNextResponse()
        session.endTurn()
        await gate.waitUntilEntered()
        try await session.refresh()
        let overlap = await transport.maximumConcurrentRequests()
        XCTAssertEqual(overlap, 1)
        session.setForeground(false)
        XCTAssertFalse(session.isAutoPassing)
        await gate.release()
        try await waitUntilIdle(session)
        session.setForeground(true)
        try await session.refresh()
        try await Task.sleep(for: .milliseconds(350))
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(session.isAutoPassing)
        try await session.close()
    }

    @MainActor
    func testUncertainAutoPassStopsAndKeepsExactUserRetry() async throws {
        let poll = try fixture("2p-priority")
        let transport = SessionFixtureTransport(poll: poll.raw, responseFailures: [URLError(.timedOut)])
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
                                 seatID: poll.seatID, autoPoll: false, allowsSeatScopedAutoYield: true, close: {})
        session.endTurn()
        try await waitForResponses(1, transport: transport)
        try await waitUntilIdle(session)
        XCTAssertFalse(session.isAutoPassing)
        XCTAssertNotNil(session.pendingActionID)
        try await session.retryPending()
        let sent = await transport.responses()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["command"], sent[1]["command"])
        XCTAssertFalse(session.isAutoPassing)
        try await session.close()
    }

    @MainActor
    private func waitForResponses(_ count: Int, transport: SessionFixtureTransport) async throws {
        for _ in 0..<400 {
            if await transport.responses().count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw EngineError.invalidMessage("Auto-pass fixture did not respond")
    }

    @MainActor
    private func waitUntilIdle(_ session: OnDeviceSession) async throws {
        for _ in 0..<400 {
            if !session.isWorking { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw EngineError.invalidMessage("Auto-pass fixture remained busy")
    }

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
    func testOnlinePollingReconnectsWithoutResendingAnAction() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
            seatID: poll.seatID, reconnectsAutomatically: true, close: {})
        await transport.failNextPoll()
        for _ in 0..<300 where session.errorMessage == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.status, "Reconnecting…")
        await transport.consumePrompt()
        for _ in 0..<600 where session.snapshot?.bridgeRevision == Int(poll.revision) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(session.snapshot?.bridgeRevision, Int(poll.revision + 1))
        XCTAssertNil(session.errorMessage)
        let responses = await transport.responses()
        XCTAssertTrue(responses.isEmpty, "Reconnecting must only poll, never replay an action")
        try await session.close()
    }

    @MainActor
    func testOnlineInitialPollTimeoutStillStartsRecovery() async throws {
        let poll = try fixture()
        let transport = SessionFixtureTransport(poll: poll.raw)
        await transport.failNextPoll()
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: poll.matchID,
            seatID: poll.seatID, reconnectsAutomatically: true, close: {})
        XCTAssertEqual(session.status, "Reconnecting…")
        for _ in 0..<300 where session.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(session.snapshot)
        XCTAssertNil(session.errorMessage)
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
    private var responseGate: SessionGate?
    private var concurrentRequests = 0
    private var maximumRequests = 0
    init(poll: MagicMobileOnDevice.JSONValue, responseFailures: [Error] = []) { self.poll = poll; self.responseFailures = responseFailures }
    func request(_ data: Data) async throws -> Data {
        concurrentRequests += 1; maximumRequests = max(maximumRequests, concurrentRequests)
        defer { concurrentRequests -= 1 }
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
            if let gate = responseGate { responseGate = nil; await gate.wait() }
            if !responseFailures.isEmpty { throw responseFailures.removeFirst() }
            result = .object(["status": .string("queued")])
        } else { throw EngineError.invalidMessage("Unexpected fixture operation") }
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func responses() -> [MagicMobileOnDevice.JSONValue] { sent }
    func maximumConcurrentRequests() -> Int { maximumRequests }
    func replacePoll(_ value: MagicMobileOnDevice.JSONValue) { poll = value }
    func suspendNextResponse() -> SessionGate { let gate = SessionGate(); responseGate = gate; return gate }
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
