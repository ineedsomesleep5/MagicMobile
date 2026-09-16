import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// A captured real projection plus explicit event fixtures exercises production
/// client/session/board adaptation. This does not execute native XMage gameplay.
final class OnDeviceMessageSessionTests: XCTestCase {
    @MainActor
    func testPrivateNoticesReachExistingLogWithoutReplayOrCrossGameRetention() async throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "2p-initial-player-1", withExtension: "json", subdirectory: "OnDevice"))
        let initial = try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)))
        var raw = initial.raw.object!
        raw["events"] = .array([.object([
            "revision": .integer(initial.revision), "kind": .string("message"),
            "body": .object(["message": .string("Only this seat may read this notice")])
        ])])
        let transport = NoticeProjectionTransport(poll: .object(raw))
        let session = OnDeviceSession()
        try await session.attach(client: EngineClient(transport: transport), matchID: initial.matchID,
                                 seatID: initial.seatID, autoPoll: false, close: {})
        XCTAssertEqual(session.snapshot?.log.map(\.message), ["Only this seat may read this notice"])
        try await session.refresh()
        XCTAssertEqual(session.snapshot?.log.count, 1)
        try await session.close()
        XCTAssertNil(session.snapshot)
        var fresh = initial.raw.object!
        fresh["events"] = .array([])
        let replacement = NoticeProjectionTransport(poll: .object(fresh))
        try await session.attach(client: EngineClient(transport: replacement), matchID: initial.matchID,
                                 seatID: initial.seatID, autoPoll: false, close: {})
        XCTAssertTrue(session.snapshot?.log.isEmpty == true)
        try await session.close()
    }
}

private actor NoticeProjectionTransport: EngineTransport {
    let poll: MagicMobileOnDevice.JSONValue
    init(poll: MagicMobileOnDevice.JSONValue) { self.poll = poll }
    func request(_ data: Data) async throws -> Data {
        guard try MagicMobileOnDevice.JSONValue.decode(data)["op"]?.string == "poll" else {
            throw EngineError.invalidMessage("Notice fixture supports poll only; it is not an engine")
        }
        return try MagicMobileOnDevice.JSONValue.object([
            "protocol": .integer(1), "ok": .bool(true), "result": poll
        ]).encoded()
    }
}
