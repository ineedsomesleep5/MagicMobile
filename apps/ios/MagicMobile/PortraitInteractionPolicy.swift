import Foundation

/// A cue follows engine steps, never priority changes or repeated polls.
struct BoardPhaseAnnouncement: Equatable {
    let key: String
    let title: String
    let owner: String

    static func make(_ snapshot: GameSnapshot) -> Self? {
        guard !snapshot.isCompleted, let active = snapshot.activePlayerId else { return nil }
        let raw = (snapshot.step ?? snapshot.phase).lowercased().replacingOccurrences(of: "_", with: "-")
        let titles = ["beginning": "Beginning phase", "untap": "Untap", "upkeep": "Upkeep", "draw": "Draw",
                      "precombat-main": "Main phase 1", "postcombat-main": "Main phase 2",
                      "combat": "Combat", "begin-combat": "Begin combat", "declare-attackers": "Declare attackers",
                      "declare-blockers": "Declare blockers", "first-combat-damage": "First-strike damage",
                      "combat-damage": "Combat damage", "end-combat": "End combat", "ending": "End step",
                      "end-turn": "End step", "cleanup": "Cleanup"]
        guard let title = titles[raw] else { return nil }
        return Self(key: "\(snapshot.id):\(snapshot.turn):\(active):\(raw)", title: title,
                    owner: snapshot.isViewer(active) ? "Your turn" : "\(snapshot.playerLabel(active))’s turn")
    }
}

/// Presentation decisions never rewrite an engine action or a seat identity.
enum PortraitInteractionPolicy {
    static func cardChoiceKey(_ snapshot: GameSnapshot) -> String? {
        guard !snapshot.isCompleted, let prompt = snapshot.promptEnvelopeV2,
              snapshot.isViewer(prompt.playerId), prompt.cards?.isEmpty == false,
              prompt.responseCommand?.type == "choose_target", prompt.maxChoices == 1 else { return nil }
        return "\(snapshot.id):\(prompt.playerId):\(prompt.id):\(prompt.messageId)"
    }

    static func detailChoiceKey(_ snapshot: GameSnapshot) -> String? {
        guard cardChoiceKey(snapshot) == nil, !snapshot.isCompleted,
              let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId) else { return nil }
        // Priority can contain a "pass" choice, but it belongs in the dock, not
        // an automatically opened card-choice sheet over the stack inspector.
        guard prompt.responseCommand?.type != "pass_priority", prompt.responseKind != "priority" else { return nil }
        let kind = MobilePromptPresentation.kind(for: prompt)
        guard [.cardChoice, .search, .abilityChoice, .order, .amount, .multiAmount, .pile].contains(kind) else { return nil }
        return "\(snapshot.id):\(prompt.playerId):\(prompt.id):\(prompt.messageId)"
    }

    static func automaticCardAction(_ cardActions: [LegalAction]) -> LegalAction? {
        cardActions.count == 1 ? cardActions.first : nil
    }

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
            for group in xmage.revealed + xmage.lookedAt + xmage.exileZones + xmage.companion {
                cards.append(contentsOf: group.cards)
            }
        }
        cards.append(contentsOf: snapshot.promptEnvelopeV2?.cards ?? [])
        cards.append(contentsOf: snapshot.promptEnvelopeV2?.abilities?.compactMap(\.sourceCard) ?? [])
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
