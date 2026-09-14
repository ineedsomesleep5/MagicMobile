import Foundation

/// Presentation decisions never rewrite an engine action or a seat identity.
enum PortraitInteractionPolicy {
    static func authorizedCards(_ snapshot: GameSnapshot) -> [ZoneCard] {
        var cards: [ZoneCard] = []
        for player in snapshot.players {
            let zones = player.zones
            cards.append(contentsOf: zones.hand)
            cards.append(contentsOf: zones.library)
            cards.append(contentsOf: zones.battlefield)
            cards.append(contentsOf: zones.graveyard)
            cards.append(contentsOf: zones.exile)
            cards.append(contentsOf: zones.command)
            cards.append(contentsOf: zones.stack)
        }
        if let xmage = snapshot.xmage {
            cards.append(contentsOf: xmage.stack.compactMap(\.displaySourceCard))
            for group in xmage.revealed + xmage.lookedAt + xmage.exileZones + (xmage.companion ?? []) {
                cards.append(contentsOf: group.cards)
            }
        }
        cards.append(contentsOf: snapshot.promptEnvelopeV2?.cards ?? [])
        for pile in snapshot.promptEnvelopeV2?.piles ?? [] { cards.append(contentsOf: pile.cards) }
        return cards
    }

    static func isCardAction(_ action: LegalAction) -> Bool {
        ["play_land", "cast_spell", "make_mana", "activate_ability"].contains(action.type)
            && (action.cardInstanceId != nil || action.sourceInstanceId != nil)
    }

    static func dockActions(_ actions: [LegalAction]) -> [LegalAction] {
        actions.filter { !isCardAction($0) && $0.type != "concede" }
    }

    static func turnCueKey(_ snapshot: GameSnapshot) -> String? {
        guard !snapshot.isCompleted, snapshot.isViewer(snapshot.activePlayerId) else { return nil }
        return "\(snapshot.id):\(snapshot.turn):\(snapshot.viewerID)"
    }
}

enum BoardOpponentFocus {
    static func opponents(in snapshot: GameSnapshot) -> [PlayerGameState] {
        snapshot.players.filter { !snapshot.isViewer($0.playerId) }
    }

    static func snapshot(_ snapshot: GameSnapshot, selecting playerID: String?) -> GameSnapshot {
        var selected = snapshot
        if let playerID, opponents(in: snapshot).contains(where: { $0.playerId == playerID }) {
            selected.selectedOpponentId = playerID
        }
        return selected
    }
}
