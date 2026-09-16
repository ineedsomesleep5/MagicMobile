import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Explicit event fixtures test production routing; they are not XMage games.
final class OnDeviceMessageLogTests: XCTestCase {
    private typealias J = MagicMobileOnDevice.JSONValue
    private func event(_ revision: Int64, _ message: J = .string("Private notice"), kind: String = "message") -> J {
        .object(["revision": .integer(revision), "kind": .string(kind), "body": .object(["message": message])])
    }
    private func poll(_ events: J? = .array([]), revision: Int64 = 10, match: String = "match-a", seat: String = "seat-a") throws -> MatchPoll {
        var raw: [String: J] = ["matchId": .string(match), "viewerId": .string(seat),
                               "revision": .integer(revision), "phase": .string("running"),
                               "resyncRequired": .bool(false), "prompt": .null, "snapshot": .null]
        raw["events"] = events
        return try MatchPoll(.object(raw))
    }
    func testExplicitNoticeKeepsExactTextAndDoesNotInventTimestamp() throws {
        var log = OnDeviceMessageLog()
        try log.ingest(poll(.array([event(1, .string("<b>Only your information</b> 🃏"))])))
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].message, "<b>Only your information</b> 🃏")
        XCTAssertNil(log.entries[0].createdAt)
        XCTAssertEqual(log.entries[0].id, "xmage:match-a:seat-a:1")
    }
    func testSnapshotsAndPromptMetadataNeverBecomeNoticeText() throws {
        var log = OnDeviceMessageLog()
        try log.ingest(poll(.array([event(1, .string("snapshot secret"), kind: "snapshot"),
                                  event(2, .string("prompt secret"), kind: "prompt"), event(3)])))
        XCTAssertEqual(log.entries.map(\.message), ["Private notice"])
    }
    func testRepeatedPollDoesNotDuplicateMessages() throws {
        var log = OnDeviceMessageLog()
        let value = try poll(.array([event(1)]))
        try log.ingest(value); try log.ingest(value)
        XCTAssertEqual(log.entries.count, 1)
    }
    func testIncrementalHistoryPreservesEarlierNotices() throws {
        var log = OnDeviceMessageLog()
        try log.ingest(poll(.array([event(1)]), revision: 1))
        try log.ingest(poll(.array([event(2, .string("Second"))]), revision: 2))
        XCTAssertEqual(log.entries.map(\.message), ["Private notice", "Second"])
    }
    func testOlderPollCannotReplaceCurrentHistory() throws {
        var log = OnDeviceMessageLog()
        try log.ingest(poll(.array([event(8, .string("Current"))])))
        try log.ingest(poll(.array([event(1, .string("Old"))]), revision: 1))
        XCTAssertEqual(log.entries.map(\.message), ["Current"])
    }
    func testOtherSeatCannotReusePrivateLog() throws {
        var log = OnDeviceMessageLog(); try log.ingest(poll(.array([event(1)])))
        XCTAssertThrowsError(try log.ingest(poll(.array([event(11)]), revision: 11, seat: "opponent")))
        XCTAssertEqual(log.entries.count, 1)
    }
    func testOtherMatchCannotReusePrivateLog() throws {
        var log = OnDeviceMessageLog(); try log.ingest(poll())
        XCTAssertThrowsError(try log.ingest(poll(match: "another-match")))
    }
    func testMalformedBatchDoesNotPartiallyAppendOrAdvanceCursor() throws {
        var log = OnDeviceMessageLog()
        XCTAssertThrowsError(try log.ingest(poll(.array([event(1), event(2, .integer(5))]))))
        XCTAssertTrue(log.entries.isEmpty)
        try log.ingest(poll(.array([event(1)])))
        XCTAssertEqual(log.entries.count, 1)
    }
    func testFutureRevisionRejected() throws {
        var log = OnDeviceMessageLog()
        XCTAssertThrowsError(try log.ingest(poll(.array([event(11)]))))
    }
    func testUnorderedAndDuplicateRevisionsRejected() throws {
        for revisions: [Int64] in [[2, 1], [1, 1]] {
            var log = OnDeviceMessageLog()
            XCTAssertThrowsError(try log.ingest(poll(.array(revisions.map { event($0) }))))
            XCTAssertTrue(log.entries.isEmpty)
        }
    }
    func testMissingHistoryRemainsCompatibleWithInitialPoll() throws {
        var log = OnDeviceMessageLog(); try log.ingest(poll(nil))
        XCTAssertTrue(log.entries.isEmpty)
    }
    func testMalformedHistoryRejected() throws {
        var log = OnDeviceMessageLog()
        XCTAssertThrowsError(try log.ingest(poll(.object([:]))))
    }
    func testNullAndEmptyNoticesDoNotInventMessageContent() throws {
        var log = OnDeviceMessageLog()
        try log.ingest(poll(.array([event(1, .null), event(2, .string(""))])))
        XCTAssertTrue(log.entries.isEmpty)
    }
    func testHistoryIsBoundedAndKeepsMostRecentMessages() throws {
        var log = OnDeviceMessageLog()
        try log.ingest(poll(.array((1...128).map { event(Int64($0), .string("Notice \($0)")) }), revision: 128))
        XCTAssertEqual(log.entries.count, 64)
        XCTAssertEqual(log.entries.first?.message, "Notice 65")
        XCTAssertEqual(log.entries.last?.message, "Notice 128")
    }
    func testByteBudgetDropsOldNoticesWithoutTruncatingTheLatest() throws {
        var log = OnDeviceMessageLog()
        let first = String(repeating: "a", count: 800_000)
        let second = String(repeating: "b", count: 800_000)
        try log.ingest(poll(.array([event(1, .string(first)), event(2, .string(second))]), revision: 2))
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].message, second)
    }
    func testOversizedEventBatchIsRejectedBeforeMutation() throws {
        var log = OnDeviceMessageLog()
        XCTAssertThrowsError(try log.ingest(poll(.array((1...129).map { event(Int64($0)) }), revision: 129)))
        XCTAssertTrue(log.entries.isEmpty)
    }
    func testNewLogDropsPriorMatchPrivateInformation() throws {
        var log = OnDeviceMessageLog(); try log.ingest(poll(.array([event(1)])))
        log = OnDeviceMessageLog()
        try log.ingest(poll(match: "new-match", seat: "new-seat"))
        XCTAssertTrue(log.entries.isEmpty)
    }
}
