import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class OnDeviceStartingRollTests: XCTestCase {
    func testHighestD20StartsAndAllDevicesDecodeSameResult() throws {
        var values = [4, 17, 10]
        let seats = ["player1", "player2", "player3"]
        let roll = try OnDeviceStartingRoll.generate(seatIDs: seats) { values.removeFirst() }
        XCTAssertEqual(roll.winnerSeatID, "player2")
        XCTAssertEqual(roll.rounds.count, 1)
        XCTAssertEqual(try OnDeviceStartingRoll(roll.encoded(seatIDs: seats), seatIDs: seats), roll)
    }

    func testOnlyTiedLeadersReroll() throws {
        var values = [20, 3, 20, 6, 15]
        let seats = ["player1", "player2", "player3"]
        let roll = try OnDeviceStartingRoll.generate(seatIDs: seats) { values.removeFirst() }
        XCTAssertEqual(roll.winnerSeatID, "player3")
        XCTAssertEqual(roll.rounds.count, 2)
        XCTAssertEqual(roll.rounds[1].rolls, ["player1": 6, "player3": 15])
        XCTAssertEqual(try OnDeviceStartingRoll(roll.encoded(seatIDs: seats), seatIDs: seats), roll)
        XCTAssertEqual(roll.steps.map(\.seatID), ["player1", "player2", "player3", "player1", "player3"])
    }

    func testSharedProgressRequiresEachHumanTapAndHostAdvancesBots() throws {
        var values = [8, 14, 5]
        let roll = try OnDeviceStartingRoll.generate(seatIDs: ["player1", "player2", "player3"]) {
            values.removeFirst()
        }
        var host = OnDeviceStartingRollProgress(roll: roll, humanSeatIDs: ["player1", "player2"])
        var guest = host
        XCTAssertEqual(host.nextSeatID, "player1")
        XCTAssertThrowsError(try host.advance(seatID: "player2", automated: false))
        XCTAssertThrowsError(try host.advance(seatID: "player1", automated: true))
        XCTAssertEqual(try host.advance(seatID: "player1", automated: false), 0)
        try guest.acceptHostAdvance(index: 0)
        XCTAssertEqual(guest.nextSeatID, "player2")
        XCTAssertThrowsError(try guest.acceptHostAdvance(index: 0))
        XCTAssertEqual(try host.advance(seatID: "player2", automated: false), 1)
        try guest.acceptHostAdvance(index: 1)
        XCTAssertEqual(try host.advance(seatID: "player3", automated: true), 2)
        try guest.acceptHostAdvance(index: 2)
        XCTAssertTrue(host.isComplete)
        XCTAssertEqual(host, guest)
    }

    func testAIViewerRollsFirstEvenWhenItsIDSortsLast() throws {
        var values = [3, 19]
        let roll = try OnDeviceStartingRoll.generate(seatIDs: ["z-viewer", "a-bot"]) { values.removeFirst() }
        XCTAssertEqual(roll.steps.map(\.seatID), ["z-viewer", "a-bot"])
        XCTAssertEqual(roll.winnerSeatID, "a-bot")
    }

    func testRejectsInventedWinnerOrOutOfRangeValue() throws {
        let seats = ["player1", "player2"]
        let badWinner: MagicMobileOnDevice.JSONValue = .object([
            "rounds": .array([.array([
                .object(["seatId": .string("player1"), "value": .integer(20)]),
                .object(["seatId": .string("player2"), "value": .integer(2)])
            ])]),
            "winnerSeatId": .string("player2")
        ])
        XCTAssertThrowsError(try OnDeviceStartingRoll(badWinner, seatIDs: seats))
        let badValue: MagicMobileOnDevice.JSONValue = .object([
            "rounds": .array([.array([
                .object(["seatId": .string("player1"), "value": .integer(21)]),
                .object(["seatId": .string("player2"), "value": .integer(2)])
            ])]),
            "winnerSeatId": .string("player1")
        ])
        XCTAssertThrowsError(try OnDeviceStartingRoll(badValue, seatIDs: seats))
    }
}
