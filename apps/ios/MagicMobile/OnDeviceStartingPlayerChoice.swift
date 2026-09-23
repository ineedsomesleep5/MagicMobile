import Foundation

/// Converts a shared pregame winner into the exact current XMage prompt answer.
/// Names are used only to reconcile the pregame seat roster with XMage's UUIDs;
/// ambiguity or a changed prompt fails closed instead of choosing someone else.
enum OnDeviceStartingPlayerChoice {
    /// Both the roll presentation and its answer must recognize the same
    /// authenticated native prompt. The adapter prefixes engine kinds with
    /// GAME_; older snapshots used the unprefixed method.
    static func candidateIDs(snapshot: GameSnapshot) -> [String]? {
        guard snapshot.source == "xmage-ondevice",
              let prompt = snapshot.promptEnvelopeV2,
              prompt.playerId == snapshot.viewerID,
              ["GAME_PICK_TARGET", "PICK_TARGET"].contains(prompt.method),
              prompt.message.localizedLowercase.contains("starting player"),
              prompt.responseCommand?.type == "choose_target",
              prompt.responseCommand?.promptId == prompt.id,
              prompt.responseCommand?.messageId == prompt.messageId,
              let candidates = prompt.targetIds,
              (2...4).contains(candidates.count),
              Set(candidates).count == candidates.count,
              candidates.allSatisfy({ id in snapshot.players.contains { $0.playerId == id } }),
              snapshot.bridgeRevision != nil else { return nil }
        return candidates
    }

    static func command(snapshot: GameSnapshot, winnerName: String) -> GameCommand? {
        let matches = snapshot.players.filter { $0.displayName == winnerName }
        guard matches.count == 1, let winnerID = matches.first?.playerId else { return nil }
        return command(snapshot: snapshot, winnerPlayerID: winnerID)
    }

    static func command(snapshot: GameSnapshot, winnerPlayerID: String) -> GameCommand? {
        guard let candidates = candidateIDs(snapshot: snapshot),
              candidates.contains(winnerPlayerID),
              let prompt = snapshot.promptEnvelopeV2,
              let revision = snapshot.bridgeRevision else { return nil }
        return GameCommand(type: "choose_target", gameId: snapshot.id,
                           playerId: snapshot.viewerID, promptId: prompt.id,
                           messageId: prompt.messageId, targetIds: [winnerPlayerID],
                           expectedBridgeRevision: revision)
    }
}
