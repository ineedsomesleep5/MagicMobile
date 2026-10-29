import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// TableLeaveRules against parity/table-leave-cases.json, which Android runs too.
final class TableLeaveRulesTests: XCTestCase {
    private func cases() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/core/src/test/resources/parity/table-leave-cases.json").standardizedFileURL
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testSharedCases() throws {
        let root = try cases()
        XCTAssertEqual((root["voteAfterSeconds"] as? NSNumber)?.doubleValue, TableLeaveRules.voteAfterSeconds)
        for item in try XCTUnwrap(root["passes"] as? [[String: Any]]) {
            XCTAssertEqual(TableLeaveRules.passes(yes: item["yes"] as! Int, eligible: item["eligible"] as! Int),
                           item["expect"] as! Bool, item["name"] as? String ?? "")
        }
        for item in try XCTUnwrap(root["packets"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? ""
            let data = try JSONSerialization.data(withJSONObject: item["packet"]!)
            let packet = try MagicMobileOnDevice.JSONValue.decode(data)
            let parsed = Result { try TableContinueVote.parse(packet, names: ["player3": "Jed"], localSeat: item["localSeat"] as? String) }
            switch item["expect"] {
            case let expected as [String: Any]:
                let vote = try XCTUnwrap(try parsed.get(), name)
                XCTAssertEqual(vote.seatID, expected["seat"] as? String, name)
                XCTAssertEqual(vote.voters, expected["voters"] as? [String], name)
                XCTAssertEqual(vote.needed, expected["needed"] as? Int, name)
                XCTAssertEqual(vote.voted, expected["voted"] as? Bool, name)
            case let text as String where text == "invalid":
                XCTAssertThrowsError(try parsed.get(), name)
            default:
                XCTAssertNil(try parsed.get(), name)
            }
        }
    }

    func testThePacketRoundTripsAndTheButtonCounts() throws {
        let vote = TableContinueVote(seatID: "player3", name: "Jed", voters: ["player1"], needed: 2, voted: false)
        let parsed = try XCTUnwrap(TableContinueVote.parse(vote.packet(epoch: "E"), names: ["player3": "Jed"], localSeat: "player1"))
        XCTAssertEqual(parsed, vote.with(voted: true))
        XCTAssertEqual(TableLeaveRules.buttonTitle(vote), "Continue without Jed (1/2)")
        XCTAssertNil(try TableContinueVote.parse(TableContinueVote.none.packet(epoch: "E"), names: [:], localSeat: nil))
    }
}
