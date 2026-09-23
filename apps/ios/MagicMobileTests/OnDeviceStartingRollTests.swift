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
