import XCTest
@testable import MagicMobile

final class OnDeviceStartingPlayerChoiceTests: XCTestCase {
    private let player1 = "00000000-0000-4000-8000-000000000001"
    private let player2 = "00000000-0000-4000-8000-000000000002"

    func testUsesWinnerUUIDOnlyForCurrentStartingPrompt() throws {
        let snapshot = try makeSnapshot()
        let command = try XCTUnwrap(OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerName: "Ada"))
        XCTAssertEqual(command.type, "choose_target")
        XCTAssertEqual(command.targetIds, [player2])
        XCTAssertEqual(command.promptId, "start-prompt")
        XCTAssertEqual(command.messageId, 8)
        XCTAssertEqual(command.expectedBridgeRevision, 27)
        XCTAssertNil(OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerName: "Unknown"))
    }

    func testDuplicatePlayerNamesFailClosed() throws {
        let snapshot = try makeSnapshot(secondName: "Caleb")
        XCTAssertNil(OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerName: "Caleb"))
        XCTAssertEqual(OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerPlayerID: player2)?.targetIds,
                       [player2])
        XCTAssertNil(OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerPlayerID: "unknown"))
    }

    private func makeSnapshot(secondName: String = "Ada") throws -> GameSnapshot {
        let json = #"""
        {
          "id":"match","source":"xmage-ondevice","phase":"beginning","turn":0,
          "players":[
            {"playerId":"\#(player1)","displayName":"Caleb","life":40,"poison":0,"commanderTax":0,"zones":{"library":[],"hand":[],"battlefield":[],"graveyard":[],"exile":[],"command":[],"stack":[]}},
            {"playerId":"\#(player2)","displayName":"\#(secondName)","life":40,"poison":0,"commanderTax":0,"zones":{"library":[],"hand":[],"battlefield":[],"graveyard":[],"exile":[],"command":[],"stack":[]}}
          ],
          "log":[],"viewerPlayerId":"\#(player1)","bridgeRevision":27,
          "promptEnvelopeV2":{
            "id":"start-prompt","method":"PICK_TARGET","messageId":8,
            "playerId":"\#(player1)","responseKind":"target",
            "message":"Select a starting player",
            "targetIds":["\#(player1)","\#(player2)"],
            "responseCommand":{"type":"choose_target","promptId":"start-prompt","messageId":8}
          }
        }
        """#
        return try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: Data(json.utf8))
    }
}
