import Foundation

/// The guided first game (Caleb, 2026-10-11): a real game against one easy AI, with a coach that
/// explains each moment the first time it comes up, in place of Hearthstone's scripted matches
/// or Arena's Color Challenge. The engine plays it like any solo game; only the notes are extra.
/// Android's GuidedGame.kt (core, io.magicmobile.android.game) holds the same rules and words,
/// and both platforms' parity tests read them from
/// apps/android/core/src/test/resources/parity/guided-game-cases.json.
enum GuidedGameTip: String, CaseIterable, Equatable {
    case firstPlayer, mulligan, attack, block, pay, target, opponentSpell, commander, land, cast, pass, inspect, basics

    /// Tips that ask for something on the table go away once it's done; the others wait for Got it.
    var isActionable: Bool { self != .inspect && self != .basics }
}

/// The match and its words: one source on iOS.
enum GuidedGameText {
    static let title = "Guided first game"
    static let subtitle = "A real game against an easy AI, with tips as each moment comes up."
    static let start = "Play a guided game"
    static let gotIt = "Got it"
    static let turnOff = "Turn off tips"
    /// The welcome on the first launch: the guided game, the slideshow, or neither.
    static let welcomeTitle = "Welcome to the tavern"
    static let welcomeBody = "New to Magic or to MagicMobile? Learn by playing, one short lesson at a time."
    static let readHowToPlay = "Read How to Play"
    static let skip = "I know Magic"

    static func title(_ tip: GuidedGameTip) -> String {
        switch tip {
        case .firstPlayer: "Who goes first"
        case .mulligan: "Your opening hand"
        case .attack: "Attack"
        case .block: "Block"
        case .pay: "Pay the cost"
        case .target: "Choose a target"
        case .opponentSpell: "A spell on the stack"
        case .commander: "Cast your commander"
        case .land: "Play a land"
        case .cast: "Cast a spell"
        case .pass: "Pass with the hourglass"
        case .inspect: "Read a card"
        case .basics: "You know the basics"
        }
    }

    static func body(_ tip: GuidedGameTip) -> String {
        switch tip {
        case .firstPlayer:
            "Welcome to your guided game. I'll explain each moment the first time it comes up. Choose yourself to take the first turn."
        case .mulligan:
            "These are your first seven cards. A good hand has two to five lands. Tap Keep, or Mulligan for a fresh seven."
        case .attack:
            "Tap each creature you want to send into combat, then Done Attacking. Creatures that arrived this turn can't attack yet."
        case .block:
            "You're being attacked. Tap your creature, then the attacker it should block, and tap Done Blocking. Unblocked attackers hit you."
        case .pay:
            "Tap your lands to pay for the spell. The tray shows how much mana is still owed."
        case .target:
            "This needs a target. Anything glowing red can be chosen: tap it."
        case .opponentSpell:
            "Your opponent's spell waits on the stack until everyone passes. You could answer with an instant; for now, tap the hourglass to let it resolve."
        case .commander:
            "Your commander is ready in the command zone, and its medallion glows. Tap the medallion to cast it."
        case .land:
            "Lands make the mana you cast spells with. Drag a land from your hand up onto the mat. You can play one each turn."
        case .cast:
            "A green glow means a card can be played now. Drag it from your hand onto the mat to cast it."
        case .pass:
            "Nothing left to play? Tap the hourglass to move on. Skip jumps to your next turn and still stops when you're needed."
        case .inspect:
            "Press and hold any card, yours or your opponent's, to read its full rules text."
        case .basics:
            "That's everything you need. Bring your opponent from 40 life to 0 to win, or leave from the game menu any time."
        }
    }
}

/// The guided game's decks and settings.
enum GuidedGameSetup {
    /// Token Triumph: green-white creatures, the simplest precon to attack with.
    static let playerDeckID = "precon:token-triumph"
    static let playerPreconID = "token-triumph"
    /// Grave Danger: a zombie deck that plays fair at skill 1.
    static let opponentDeckID = "grave-danger"
    static let aiSkill = 1
    /// The player picks who starts, so the first note can tell them to pick themselves.
    static let startingPlayerMode = "choose"
}

/// What the coach shows: a pure function of the snapshot, the note on screen and the notes
/// already shown, so both platforms answer the same and the rules can be tested.
enum GuidedGameCoach {
    /// The notes every guided game should reach before `basics`; the others only come up if the game does.
    static let core: [GuidedGameTip] = [.mulligan, .land, .cast, .pass, .attack, .inspect]

    struct Step: Equatable {
        /// The note to show now, or nil.
        let current: GuidedGameTip?
        /// The note shown for the first time on this step, to remember.
        let newlyShown: GuidedGameTip?
    }

    /// The next note: the one on screen stays while it still applies (or, for a note that asks
    /// for nothing, until a note that does arrives); a finished game shows none.
    static func advance(current: GuidedGameTip?, snapshot: GameSnapshot, shown: Set<GuidedGameTip>) -> Step {
        if snapshot.isCompleted { return Step(current: nil, newlyShown: nil) }
        let next = nextTip(snapshot: snapshot, shown: shown)
        if let current {
            let keeps = current.isActionable ? applies(current, snapshot: snapshot) : (next.map { !$0.isActionable } ?? true)
            if keeps { return Step(current: current, newlyShown: nil) }
        }
        return Step(current: next, newlyShown: next)
    }

    /// The first note not shown yet whose moment this is, most urgent first.
    static func nextTip(snapshot: GameSnapshot, shown: Set<GuidedGameTip>) -> GuidedGameTip? {
        if snapshot.isCompleted { return nil }
        let order: [GuidedGameTip] = [.firstPlayer, .mulligan, .attack, .block, .pay, .target, .opponentSpell,
                                      .commander, .land, .cast, .pass, .inspect]
        if let tip = order.first(where: { !shown.contains($0) && applies($0, snapshot: snapshot) }) { return tip }
        if !shown.contains(.basics), core.allSatisfy(shown.contains), applies(.basics, snapshot: snapshot) { return .basics }
        return nil
    }

    static func applies(_ tip: GuidedGameTip, snapshot: GameSnapshot) -> Bool {
        let viewer = snapshot.viewerID
        let prompt = snapshot.promptEnvelopeV2.flatMap { $0.playerId == viewer ? $0 : nil }
        let actions = snapshot.legalActions ?? []
        let types = Set(actions.map(\.type))
        let myTurn = snapshot.activePlayerId == viewer
        let myPriority = snapshot.priorityPlayerId == viewer
        let opponentStack = snapshot.players.contains { $0.playerId != viewer && !$0.zones.stack.isEmpty }
        let anyStack = snapshot.players.contains { !$0.zones.stack.isEmpty }
        let main = "\(snapshot.phase) \(snapshot.step ?? "")".lowercased().contains("main")
        // Free to act: holding priority with no question beyond "what next?".
        let free = myPriority && !isMana(prompt) && !isTarget(prompt) && !types.contains("declare_attackers")
            && !types.contains("declare_blockers")
        switch tip {
        case .firstPlayer:
            return prompt.map { $0.message.lowercased().contains("starting player") } ?? false
        case .mulligan:
            return prompt.map { $0.confirmation != nil && $0.message.lowercased().contains("mulligan") } ?? false
        case .attack: return types.contains("declare_attackers")
        case .block: return types.contains("declare_blockers")
        case .pay: return isMana(prompt) || snapshot.manaPayment?.active == true
        case .target: return isTarget(prompt) && !isMana(prompt)
        case .opponentSpell: return free && opponentStack
        case .commander: return free && actions.contains { $0.type == "cast_spell" && $0.sourceZone == "command" }
        case .land: return free && myTurn && types.contains("play_land")
        case .cast: return free && myTurn && actions.contains { $0.type == "cast_spell" && $0.sourceZone != "command" }
        case .pass:
            return free && myTurn && main && !anyStack && !types.contains("play_land") && !types.contains("cast_spell")
                && types.contains("pass_priority")
        case .inspect, .basics: return free && myTurn && snapshot.turn >= 3
        }
    }

    private static func isMana(_ prompt: PromptEnvelopeV2?) -> Bool {
        guard let prompt else { return false }
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        return ["play_mana", "choose_mana", "pay_cost", "play_x_mana"].contains(type)
            || ["mana", "pay_cost", "cost", "x_mana"].contains(kind)
            || ["GAME_PLAY_MANA", "GAME_PLAY_XMANA"].contains(prompt.method)
    }

    private static func isTarget(_ prompt: PromptEnvelopeV2?) -> Bool {
        guard let prompt, !prompt.message.lowercased().contains("starting player") else { return false }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_target" || prompt.responseKind.lowercased() == "target"
            || prompt.method.uppercased().contains("TARGET")
    }
}

/// What the guided game remembers on this phone: the notes already shown (each shows once, even
/// across a resumed game), whether a guided game is under way, and whether the welcome was answered.
/// Android's GuidedGameLaunch uses the same keys.
enum GuidedGameLaunch {
    static let shownTipsKey = "magicmobile.guidedGame.shownTips"
    static let activeKey = "magicmobile.guidedGame.active"
    static let welcomeSeenKey = "magicmobile.guidedGame.welcomeSeen"

    static func shownTips(in defaults: UserDefaults) -> Set<GuidedGameTip> {
        Set((defaults.stringArray(forKey: shownTipsKey) ?? []).compactMap(GuidedGameTip.init(rawValue:)))
    }

    static func remember(_ tip: GuidedGameTip, in defaults: UserDefaults) {
        var ids = defaults.stringArray(forKey: shownTipsKey) ?? []
        if !ids.contains(tip.rawValue) { ids.append(tip.rawValue); defaults.set(ids, forKey: shownTipsKey) }
    }

    /// A new guided game teaches from the start again.
    static func begin(in defaults: UserDefaults) {
        defaults.removeObject(forKey: shownTipsKey)
        defaults.set(true, forKey: activeKey)
        defaults.set(true, forKey: welcomeSeenKey)
    }

    static func end(in defaults: UserDefaults) { defaults.set(false, forKey: activeKey) }

    /// The welcome replaces the walkthrough's automatic first opening: it shows when the
    /// walkthrough would have, and never again once answered either way.
    static func shouldShowWelcome(defaults: UserDefaults,
                                  arguments: [String] = ProcessInfo.processInfo.arguments,
                                  environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !defaults.bool(forKey: welcomeSeenKey)
            && HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: arguments, environment: environment)
    }

    static func markWelcomeSeen(in defaults: UserDefaults) { defaults.set(true, forKey: welcomeSeenKey) }
}
