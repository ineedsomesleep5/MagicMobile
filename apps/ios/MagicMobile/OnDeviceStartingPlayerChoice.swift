import Foundation

/// Converts a shared pregame winner into the exact current XMage prompt answer.
/// Names are used only to reconcile the pregame seat roster with XMage's UUIDs;
/// ambiguity or a changed prompt fails closed instead of choosing someone else.
enum OnDeviceStartingPlayerChoice {
    static func command(snapshot: GameSnapshot, winnerName: String) -> GameCommand? {
        let matches = snapshot.players.filter { $0.displayName == winnerName }
        guard matches.count == 1, let winnerID = matches.first?.playerId else { return nil }
        return command(snapshot: snapshot, winnerPlayerID: winnerID)
    }

    static func command(snapshot: GameSnapshot, winnerPlayerID: String) -> GameCommand? {
        guard snapshot.source == "xmage-ondevice",
              let prompt = snapshot.promptEnvelopeV2,
              prompt.playerId == snapshot.viewerID,
              prompt.method == "PICK_TARGET",
              prompt.message.localizedLowercase.contains("starting player"),
              prompt.responseCommand?.type == "choose_target",
              prompt.responseCommand?.promptId == prompt.id,
              prompt.responseCommand?.messageId == prompt.messageId,
              let candidates = prompt.targetIds,
              let revision = snapshot.bridgeRevision else { return nil }
        guard snapshot.players.contains(where: { $0.playerId == winnerPlayerID }),
              candidates.contains(winnerPlayerID) else { return nil }
        return GameCommand(type: "choose_target", gameId: snapshot.id,
                           playerId: snapshot.viewerID, promptId: prompt.id,
                           messageId: prompt.messageId, targetIds: [winnerPlayerID],
                           expectedBridgeRevision: revision)
    }
}
