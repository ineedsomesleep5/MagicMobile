import Foundation

/// Both means two current engine offers, never merely a double-faced card.
enum CardPlayAffordance: Equatable {
    case none, land, spell, landAndSpell

    init(land: Bool, spell: Bool) {
        self = land ? (spell ? .landAndSpell : .land) : (spell ? .spell : .none)
    }

    var accessibilityValue: String {
        switch self {
        case .none: return "No play offered"
        case .land: return "Play land available"
        case .spell: return "Cast spell available"
        case .landAndSpell: return "Play land or cast spell available"
        }
    }
}

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
    static func primaryDockAction(_ actions: [LegalAction], prompt: PromptEnvelopeV2?) -> LegalAction? {
        if let prompt, prompt.method == "GAME_SELECT", prompt.responseKind == "target" {
            // Combat's special string means Attack all. It is never a safe
            // substitute for the primary Done / Pass control, in any order.
            return actions.first {
                $0.type == "answer_yes_no" && $0.confirmed == true &&
                $0.promptId == (prompt.responseCommand?.promptId ?? prompt.id) &&
                $0.messageId == (prompt.responseCommand?.messageId ?? prompt.messageId) &&
                $0.playerId == prompt.playerId
            }
        }
        return actions.first
    }

    static func matchesCardSearch(_ card: ZoneCard, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let visibleText = [card.card.name, card.card.typeLine, card.card.oracleText ?? ""].joined(separator: " ")
        return words.allSatisfy { visibleText.localizedStandardContains(String($0)) }
    }

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

/// Which players the board shows. Presentation only: the viewer's seat, permissions, polling
/// and hidden information never change.
enum BoardOpponentFocus {
    /// The bottom seat. While the viewer watches after leaving the game, the next living
    /// player after them in turn order stands in, so the board never shows an empty seat.
    /// Recomputed on every poll, so a knocked-out stand-in hands the seat to the next player.
    static func seatPlayerID(in snapshot: GameSnapshot) -> String {
        let players = snapshot.players
        guard snapshot.isSpectating, let viewer = players.firstIndex(where: { snapshot.isViewer($0.playerId) }) else {
            return snapshot.viewerID
        }
        for offset in 1..<max(players.count, 1) {
            let player = players[(viewer + offset) % players.count]
            // Someone else must stay for the top of the board.
            if !player.isOut, players.contains(where: { !snapshot.isViewer($0.playerId) && $0.playerId != player.playerId }) {
                return player.playerId
            }
        }
        return snapshot.viewerID
    }

    /// Players the top of the board can show: everyone but the viewer and the bottom seat.
    static func opponents(in snapshot: GameSnapshot) -> [PlayerGameState] {
        let seat = seatPlayerID(in: snapshot)
        return snapshot.players.filter { !snapshot.isViewer($0.playerId) && $0.playerId != seat }
    }

    static func snapshot(_ snapshot: GameSnapshot, selecting playerID: String?) -> GameSnapshot {
        var selected = snapshot
        let seat = seatPlayerID(in: snapshot)
        selected.seatPlayerId = snapshot.isViewer(seat) ? nil : seat
        if let playerID, opponents(in: snapshot).contains(where: { $0.playerId == playerID }) {
            selected.selectedOpponentId = playerID
        }
        return selected
    }

    /// The bottom seat's hand as cards. A stand-in's hand is hidden: the board shows its count only.
    static func seatHand(in snapshot: GameSnapshot) -> [ZoneCard] {
        snapshot.isViewer(snapshot.seatID) ? snapshot.seat?.zones.hand ?? [] : []
    }

    /// The viewer is answering a prompt, so the board holds still under their finger.
    static func viewerIsAnswering(_ snapshot: GameSnapshot) -> Bool {
        guard !snapshot.isCompleted, let prompt = snapshot.promptEnvelopeV2 else { return false }
        return snapshot.isViewer(prompt.playerId)
    }
}

/// The top of the board follows the turn: when a turn starts it shows the active player, unless
/// that is the viewer (or the stand-in at the bottom), where it keeps the last one shown. A tap
/// on another opponent sticks until the next turn starts. The switch never happens while the
/// viewer answers a prompt; it waits until the prompt is answered.
struct BoardFocusTracker: Equatable {
    static let followTurnsKey = "magicmobile.followTurns"

    /// The opponent the viewer picked or the turn moved to; nil shows the first opponent.
    private(set) var focusedID: String?
    private var gameID: String?
    private var turnKey: String?
    private var switchPending = false

    /// Changes whenever a poll could move the focus; the board observes each new value.
    static func observationKey(_ snapshot: GameSnapshot, followTurns: Bool) -> String {
        "\(snapshot.id)|\(snapshot.turn)|\(snapshot.activePlayerId ?? "")|\(BoardOpponentFocus.viewerIsAnswering(snapshot))|"
            + "\(BoardOpponentFocus.seatPlayerID(in: snapshot))|\(followTurns)"
    }

    /// A tap on an opponent. It replaces any switch still waiting on a prompt.
    mutating func select(_ playerID: String) {
        focusedID = playerID
        switchPending = false
    }

    mutating func observe(_ snapshot: GameSnapshot, followTurns: Bool) {
        if snapshot.id != gameID {
            self = BoardFocusTracker()
            gameID = snapshot.id
        }
        let key = "\(snapshot.turn):\(snapshot.activePlayerId ?? "")"
        if key != turnKey {
            turnKey = key
            switchPending = snapshot.activePlayerId != nil
        }
        guard followTurns else { switchPending = false; return }
        guard switchPending, !BoardOpponentFocus.viewerIsAnswering(snapshot) else { return }
        switchPending = false
        if let active = snapshot.activePlayerId,
           BoardOpponentFocus.opponents(in: snapshot).contains(where: { $0.playerId == active }) {
            focusedID = active
        }
    }
}

/// The bar that replaces the viewer's controls while they watch: whose seat the bottom shows.
enum SpectatorSeatPresentation {
    static func title(_ snapshot: GameSnapshot) -> String {
        guard let seat = snapshot.seat, !snapshot.isViewer(seat.playerId) else { return "Watching" }
        return "Watching \(snapshot.playerLabel(seat.playerId))"
    }

    static func detail(_ snapshot: GameSnapshot) -> String {
        let count = snapshot.remainingOpponents.count
        let players = count == 1 ? "1 player still in" : "\(count) players still in"
        guard let seat = snapshot.seat, !snapshot.isViewer(seat.playerId) else {
            return "You’re out · \(players) · Turn \(snapshot.turn)"
        }
        // The hand row already shows the stand-in's hand count; this line fits a phone.
        return "\(seat.life) life · \(players) · Turn \(snapshot.turn)"
    }
}
