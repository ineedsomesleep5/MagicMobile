import Foundation
import XCTest
@testable import MagicMobileOnDevice

private actor Issue4ReplyTransport: EngineTransport {
    let data: Data
    private(set) var calls = 0
    init(_ result: JSONValue) throws {
        data = try JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func request(_ data: Data) async throws -> Data { calls += 1; return self.data }
}

// Test methods keep all mutable fixture state in independent transport actors.
final class Issue4CorrelationTests: XCTestCase, @unchecked Sendable {
    private func poll(match: String = "match-a", seat: String = "seat-a", revision: Int64 = 7,
                      resync: Bool = false, prompt: JSONValue = .null) -> JSONValue {
        .object(["matchId": .string(match), "viewerId": .string(seat), "revision": .integer(revision),
                 "phase": .string("running"), "resyncRequired": .bool(resync), "prompt": prompt,
                 "snapshot": .object(["privateSentinel": .string("only-seat-a")])])
    }
    private func prompt(_ changes: [String: JSONValue] = [:]) -> JSONValue {
        var value: [String: JSONValue] = ["promptId": .string("prompt-a"), "revision": .integer(3),
            "kind": .string("ASK"), "payload": .object(["message": .string("Mulligan?")]),
            "submitted": .bool(false), "responseTypes": .array([.string("boolean")]),
            "min": .integer(0), "max": .integer(0)]
        value.merge(changes) { _, new in new }
        return .object(value)
    }
    func testMatchingPollReturned() async throws {
        let client = EngineClient(transport: try Issue4ReplyTransport(poll()))
        let result = try await client.poll(matchID: "match-a", seatID: "seat-a")
        XCTAssertEqual(result.snapshot?["privateSentinel"]?.string, "only-seat-a")
    }
    func testWrongMatchRejectedBeforePresentation() async throws {
        let client = EngineClient(transport: try Issue4ReplyTransport(poll(match: "old-match")))
        do { _ = try await client.poll(matchID: "match-a", seatID: "seat-a"); XCTFail("Accepted other match") }
        catch EngineError.invalidMessage(let message) { XCTAssertEqual(message, "Poll response identity mismatch") }
    }
    func testWrongSeatRejectedBeforePresentation() async throws {
        let client = EngineClient(transport: try Issue4ReplyTransport(poll(seat: "opponent")))
        do { _ = try await client.poll(matchID: "match-a", seatID: "seat-a"); XCTFail("Accepted other seat") }
        catch EngineError.invalidMessage(let message) { XCTAssertEqual(message, "Poll response identity mismatch") }
    }
    func testEmptyReturnedIdentityRejected() async throws {
        let client = EngineClient(transport: try Issue4ReplyTransport(poll(match: "")))
        do { _ = try await client.poll(matchID: "match-a", seatID: "seat-a"); XCTFail("Accepted empty match") }
        catch EngineError.invalidMessage { }
    }
    func testEmptyRequestMatchDoesNotReachTransport() async throws {
        let transport = try Issue4ReplyTransport(poll())
        do { _ = try await EngineClient(transport: transport).poll(matchID: "", seatID: "seat-a"); XCTFail() }
        catch EngineError.invalidMessage { }
        let calls = await transport.calls; XCTAssertEqual(calls, 0)
    }
    func testEmptyRequestSeatDoesNotReachTransport() async throws {
        let transport = try Issue4ReplyTransport(poll())
        do { _ = try await EngineClient(transport: transport).poll(matchID: "match-a", seatID: ""); XCTFail() }
        catch EngineError.invalidMessage { }
        let calls = await transport.calls; XCTAssertEqual(calls, 0)
    }
    func testNegativeRequestRevisionDoesNotReachTransport() async throws {
        let transport = try Issue4ReplyTransport(poll())
        do { _ = try await EngineClient(transport: transport).poll(matchID: "match-a", seatID: "seat-a", after: -1); XCTFail() }
        catch EngineError.invalidMessage { }
        let calls = await transport.calls; XCTAssertEqual(calls, 0)
    }
    func testLegitimateResyncAtLowerRevisionIsNotBlocked() async throws {
        let client = EngineClient(transport: try Issue4ReplyTransport(poll(revision: 5, resync: true)))
        let result = try await client.poll(matchID: "match-a", seatID: "seat-a", after: 9)
        XCTAssertEqual(result.revision, 5); XCTAssertTrue(result.resyncRequired)
    }
    func testValidPromptRetainsExactKeyAndRevision() throws {
        let result = try EnginePrompt(prompt())
        XCTAssertEqual(result.id, "prompt-a"); XCTAssertEqual(result.revision, 3)
        XCTAssertEqual(result.responseTypes, ["boolean"])
    }
    func testEmptyPromptIDRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["promptId": .string("")]))) }
    func testEmptyPromptKindRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["kind": .string("")]))) }
    func testNonObjectPayloadRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["payload": .array([])]))) }
    func testNullPayloadRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["payload": .null]))) }
    func testReversedBoundsRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["min": .integer(9), "max": .integer(2)]))) }
    func testEmptyResponseTypesRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["responseTypes": .array([])]))) }
    func testDuplicateResponseTypesRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["responseTypes": .array([.string("boolean"), .string("boolean")])])) ) }
    func testUnknownResponseTypeRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["responseTypes": .array([.string("invented-batch")])])) ) }
    func testNonStringResponseTypeRejected() { XCTAssertThrowsError(try EnginePrompt(prompt(["responseTypes": .array([.integer(1)])])) ) }
    func testAllExistingResponseTypesAccepted() throws {
        let types = ["boolean", "uuid", "string", "integer", "integers", "mana"]
        let result = try EnginePrompt(prompt(["responseTypes": .array(types.map(JSONValue.string)),
                                             "min": .integer(Int64(Int32.min)), "max": .integer(Int64(Int32.max))]))
        XCTAssertEqual(result.responseTypes, types)
    }
    func testSubmittedPromptStillDecodesForExistingCallerPolicy() throws {
        XCTAssertTrue(try EnginePrompt(prompt(["submitted": .bool(true)])).submitted)
    }
    func testMalformedPromptInsidePollRejected() async throws {
        let client = EngineClient(transport: try Issue4ReplyTransport(poll(prompt: prompt(["min": .integer(3)]))))
        do { _ = try await client.poll(matchID: "match-a", seatID: "seat-a"); XCTFail("Accepted bad prompt") }
        catch EngineError.invalidMessage { }
    }
}
