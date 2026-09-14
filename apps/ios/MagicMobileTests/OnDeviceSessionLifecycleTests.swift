import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

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
