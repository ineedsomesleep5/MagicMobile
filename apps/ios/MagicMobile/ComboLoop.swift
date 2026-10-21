import Foundation

/// The combo loop shortcut (roadmap release B): after the player makes the same sequence of choices three times in a row
/// in one turn, the app offers to repeat it. Each repeat is an ordinary answer the engine checks, so no rule is skipped;
/// the repeats stop the moment anything differs. Steps are kept by meaning, never by ids (a token made by the loop has a
/// new id each time round): an action by its card's name and text, a choice by the kind of thing chosen (yours or an
/// opponent's, creature or artifact, token or card), with the name as the first preference. Passing priority is not a
/// step: before a step that was taken with an empty stack, the repeats let the player's own triggers resolve first.
/// Android's ComboLoop.kt matches it; apps/android/core/src/test/resources/parity/combo-loop-cases.json checks both.

/// Something chosen in a step. Two choices are the same kind when they belong to the same side, are the same sort of
/// object and are both tokens or both cards; the name is only a preference (options like modes keep their name).
struct ComboTarget: Codable, Hashable, Sendable {
    var name: String
    /// "you", "opponent", or "" for options that belong to nobody (modes, choices).
    var controller: String = ""
    /// "creature", "planeswalker", "artifact", "enchantment", "land", "player", "card" or "option".
    var kind: String = "option"
    var token: Bool = false

    static func == (lhs: ComboTarget, rhs: ComboTarget) -> Bool {
        lhs.controller == rhs.controller && lhs.kind == rhs.kind && lhs.token == rhs.token
            && (lhs.kind != "option" || lhs.name == rhs.name)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(controller); hasher.combine(kind); hasher.combine(token)
        if kind == "option" { hasher.combine(name) }
    }

    /// Words for messages and the preview: "a Squirrel token", "an opponent's creature".
    var phrase: String {
        switch kind {
        case "option", "player": return name
        default:
            if controller == "opponent" { return token ? String(localized: "an opponent's \(kind) token") : String(localized: "an opponent's \(kind)") }
            return token ? String(localized: "a \(name) token") : String(localized: "your \(name)")
        }
    }
}

struct ComboStep: Codable, Hashable, Sendable {
    /// A legal action from the board (cast, activate, play, tap for mana), or an answer to a prompt.
    enum Kind: String, Codable, Sendable { case action, prompt }

    var kind: Kind
    var type: String
    /// The source card's name, for actions.
    var source: String?
    /// The action's text, normalized; for prompts, the prompt's method (GAME_TARGET, GAME_ASK, ...).
    var label: String
    /// What was chosen, in order.
    var targets: [ComboTarget] = []
    var amount: Int?
    var amounts: [Int]?
    var pile: Int?
    var manaTypes: [String]?
    var confirmed: Bool?
    var pay: Bool?
    var useCommandZone: Bool?
    /// Taken with nothing on the stack: the repeats let the player's own triggers resolve before this step.
    var stackEmpty = false
    /// Mana an action makes, for tapping another source of the same mana when the original is gone.
    var producedMana: [String]?

    /// The same step, whatever the stack and the exact mana source looked like.
    static func == (lhs: ComboStep, rhs: ComboStep) -> Bool {
        lhs.kind == rhs.kind && lhs.type == rhs.type && lhs.source == rhs.source && lhs.label == rhs.label && lhs.targets == rhs.targets
            && lhs.amount == rhs.amount && lhs.amounts == rhs.amounts && lhs.pile == rhs.pile && lhs.manaTypes == rhs.manaTypes
            && lhs.confirmed == rhs.confirmed && lhs.pay == rhs.pay && lhs.useCommandZone == rhs.useCommandZone
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind); hasher.combine(type); hasher.combine(source); hasher.combine(label); hasher.combine(targets)
    }
}

/// How many rounds to repeat.
enum ComboRepeat: Equatable, Sendable {
    case times(Int)
    /// Until a step can't be taken any more: a normal finish.
    case untilCant
    /// Until every opponent has lost.
    case untilWin

    var count: Int? { if case .times(let count) = self { return count }; return nil }
    /// Small counts play their effects at a pace you can follow; long runs go fast and show the board once a round.
    var watchable: Bool { (count ?? Int.max) <= ComboLoop.watchableRounds }
}

/// What a player's answer means for spotting loops.
enum ComboNote: Equatable, Sendable {
    case step(ComboStep)
    /// Not part of a round (passing priority): neither recorded nor breaking the rounds around it.
    case ignore
    /// Never part of a loop (combat, the opening): the rounds start over.
    case breaks
}

/// The answer a step makes now, and what it chose (so the next round can keep the same target).
struct ComboReplay {
    let command: GameCommand
    let label: String
    let actionID: String
    let chosenNames: [String]
    /// A target was gone and another of the same kind was chosen ("Kinjalli's Caller" → "Zacama").
    let retargeted: (from: String, to: String)?
}

enum ComboLoop {
    /// How many identical rounds in a row make a loop worth offering.
    static let repeatsToOffer = 3
    /// The longest loop looked for, in steps.
    static let maxCycleLength = 12
    /// Steps remembered for spotting loops.
    static let historyLimit = 48
    /// The most rounds one shortcut runs, whatever was asked.
    static let maxRepeats = 300
    /// The count picker starts here.
    static let pickerDefault = 5
    /// Up to this many rounds play their effects, at a pace you can follow.
    static let watchableRounds = 10
    /// Open-ended repeats stop when this many rounds in a row change nothing visible.
    static let unchangedRoundsToStop = 3

    private static let comboTypes: Set<String> = ["activate_ability", "cast_spell"]
    private static let ignoredTypes: Set<String> = ["pass_priority"]
    private static let excludedTypes: Set<String> = ["declare_attackers", "declare_blockers", "mulligan", "keep_hand", "concede",
                                                     "commander_replacement", "choose_starting_player"]

    static func normalized(_ label: String) -> String {
        label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: What things are

    struct Known {
        var name: String
        var controller: String
        var kind: String
        var token: Bool
    }

    static func kind(of card: CardIdentity) -> String {
        let type = card.typeLine.lowercased()
        for kind in ["creature", "planeswalker", "artifact", "enchantment", "land"] where type.contains(kind) { return kind }
        return "card"
    }

    /// Everything nameable by id: cards in every visible zone (with whose they are), players, and the prompt's options.
    static func known(in snapshot: GameSnapshot) -> [String: Known] {
        var known: [String: Known] = [:]
        for player in snapshot.players {
            let side = snapshot.isViewer(player.playerId) ? "you" : "opponent"
            known[player.playerId] = Known(name: side == "you" ? "You" : (player.displayName ?? player.playerId), controller: side, kind: "player", token: false)
            let zones = player.zones
            for card in zones.battlefield + zones.hand + zones.graveyard + zones.exile + zones.command + zones.stack + zones.library {
                known[card.instanceId] = Known(name: card.card.name, controller: side, kind: kind(of: card.card), token: card.card.isToken == true)
            }
        }
        for object in snapshot.xmage?.stack ?? [] {
            if let id = object.sourceInstanceId, known[id] == nil, let name = object.sourceName {
                known[id] = Known(name: name, controller: "", kind: "card", token: false)
            }
        }
        if let prompt = snapshot.promptEnvelopeV2 {
            for option in (prompt.targets ?? []) + (prompt.choices ?? []) + (prompt.modes ?? []) + (prompt.orderedItems ?? []) where known[option.id] == nil {
                if let card = option.cardInstanceId.flatMap({ known[$0] }) { known[option.id] = card; continue }
                known[option.id] = Known(name: option.label, controller: "", kind: "option", token: false)
            }
            for card in prompt.cards ?? [] where known[card.instanceId] == nil {
                known[card.instanceId] = Known(name: card.card.name, controller: "", kind: kind(of: card.card), token: card.card.isToken == true)
            }
            for player in prompt.players ?? [] where known[player.playerId] == nil {
                known[player.playerId] = Known(name: player.label, controller: snapshot.isViewer(player.playerId) ? "you" : "opponent", kind: "player", token: false)
            }
            for ability in prompt.abilities ?? [] { known[ability.id] = Known(name: ability.label, controller: "", kind: "option", token: false) }
        }
        return known
    }

    static func target(_ id: String, _ known: [String: Known]) -> ComboTarget {
        guard let thing = known[id] else { return ComboTarget(name: "?") }
        return ComboTarget(name: thing.name, controller: thing.controller, kind: thing.kind, token: thing.token)
    }

    /// Nothing on the stack, anyone's.
    static func stackIsEmpty(_ snapshot: GameSnapshot) -> Bool {
        (snapshot.xmage?.stack ?? []).isEmpty && snapshot.players.allSatisfy { $0.zones.stack.isEmpty }
    }

    // MARK: Recording

    /// What a player's answer means for spotting loops.
    static func note(command: GameCommand, label: String, actionID: String, snapshot: GameSnapshot?) -> ComboNote {
        if ignoredTypes.contains(command.type) { return .ignore }
        guard let snapshot, !excludedTypes.contains(command.type) else { return .breaks }
        let known = known(in: snapshot)
        func chosen(_ ids: [String]?) -> [ComboTarget] { (ids ?? []).map { target($0, known) } }
        let empty = stackIsEmpty(snapshot)
        if let action = snapshot.legalActions?.first(where: { $0.id == actionID }) {
            let source = (action.sourceInstanceId ?? action.cardInstanceId).flatMap { known[$0]?.name } ?? action.cardName
            return .step(ComboStep(kind: .action, type: command.type, source: source, label: normalized(action.label),
                                   targets: chosen(command.targetIds) + chosen(command.cardInstanceIds) + chosen(command.playerIds),
                                   amount: command.amount, amounts: command.amounts, pile: command.pile,
                                   manaTypes: command.manaTypes ?? command.manaType.map { [$0] }, confirmed: command.confirmed, pay: command.pay,
                                   useCommandZone: command.useCommandZone, stackEmpty: empty, producedMana: action.producedMana))
        }
        guard let prompt = snapshot.promptEnvelopeV2, command.promptId == prompt.id || command.promptId == prompt.responseCommand?.promptId else { return .breaks }
        let picked = chosen(command.targetIds) + chosen(command.cardInstanceIds) + chosen(command.playerIds) + chosen(command.choiceIds)
            + chosen(command.modeIds) + chosen(command.orderedIds) + chosen(command.abilityId.map { [$0] })
        return .step(ComboStep(kind: .prompt, type: command.type, source: nil, label: prompt.method, targets: picked,
                               amount: command.amount, amounts: command.amounts, pile: command.pile,
                               manaTypes: command.manaTypes ?? command.manaType.map { [$0] }, confirmed: command.confirmed, pay: command.pay,
                               useCommandZone: command.useCommandZone, stackEmpty: empty))
    }

    /// The step a player's answer makes, or nil when it isn't one.
    static func step(command: GameCommand, label: String, actionID: String, snapshot: GameSnapshot?) -> ComboStep? {
        if case .step(let step) = note(command: command, label: label, actionID: actionID, snapshot: snapshot) { return step }
        return nil
    }

    // MARK: Spotting a loop

    /// A round worth repeating: something is cast or activated, and nothing in it is combat or the opening.
    static func isLoopable(_ round: [ComboStep]) -> Bool {
        round.contains { $0.kind == .action && comboTypes.contains($0.type) } && !round.contains { excludedTypes.contains($0.type) }
    }

    /// The shortest round the last steps repeat `repeatsToOffer` times in a row, or nil.
    static func cycle(in history: [ComboStep]) -> [ComboStep]? {
        // Fewer steps than one round repeated three times: nothing to find (and `1...0` would trap).
        let longest = min(maxCycleLength, history.count / repeatsToOffer)
        guard longest >= 1 else { return nil }
        for length in 1...longest {
            let tail = Array(history.suffix(length * repeatsToOffer))
            guard (length..<tail.count).allSatisfy({ tail[$0] == tail[$0 - length] }) else { continue }
            let round = Array(tail.prefix(length))
            if isLoopable(round) { return round }
        }
        return nil
    }

    /// The offer's headline: the round's casts and activations.
    static func describe(_ round: [ComboStep]) -> String {
        round.filter { $0.kind == .action && comboTypes.contains($0.type) }.map { step in
            let verb = step.type == "cast_spell" ? String(localized: "Cast") : String(localized: "Activate")
            return "\(verb) \(step.source ?? step.label)"
        }.joined(separator: " → ")
    }

    /// What one round does, step by step, for the offer's preview.
    static func preview(_ round: [ComboStep]) -> [String] {
        round.map { step in
            switch step.kind {
            case .action:
                let name = step.source ?? step.label
                switch step.type {
                case "cast_spell": return String(localized: "Cast \(name)")
                case "activate_ability": return String(localized: "Activate \(name)")
                case "make_mana": return String(localized: "Mana from \(name)")
                case "play_land": return String(localized: "Play \(name)")
                default: return name
                }
            case .prompt:
                if step.type == "answer_yes_no" { return step.confirmed == true ? String(localized: "Answer Yes") : String(localized: "Answer No") }
                if step.type == "play_mana" || step.type == "choose_mana" { return String(localized: "Pay {\((step.manaTypes ?? []).joined())}") }
                let things = step.targets.map(\.phrase).joined(separator: ", ")
                return things.isEmpty ? step.label : String(localized: "Choose \(things)")
            }
        }
    }

    // MARK: Repeating it

    /// The step must wait for the stack to clear first: it was taken with nothing on the stack.
    static func waitsForStack(_ step: ComboStep, in snapshot: GameSnapshot) -> Bool { step.stackEmpty && !stackIsEmpty(snapshot) }

    /// Passing priority so the player's own triggers resolve: the board's pass, when it's offered.
    static func pass(in snapshot: GameSnapshot) -> (command: GameCommand, label: String, actionID: String)? {
        guard let action = snapshot.legalActions?.first(where: { $0.type == "pass_priority" }) else { return nil }
        return (GameCommand(action: action, gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision), action.label, action.id)
    }

    /// The answer this step makes now, from the current legal actions or prompt; nil when it isn't available. Each chosen
    /// thing prefers the name `prefer` gives for its place (last round's choice, so a shrinking creature stays the target
    /// until it dies), then the recorded name, then anything of the same kind.
    static func command(for step: ComboStep, in snapshot: GameSnapshot, prefer: [String] = []) -> ComboReplay? {
        let known = known(in: snapshot)
        switch step.kind {
        case .action:
            let actions = snapshot.legalActions ?? []
            func source(_ action: LegalAction) -> String? { (action.sourceInstanceId ?? action.cardInstanceId).flatMap { known[$0]?.name } ?? action.cardName }
            var match = actions.first { $0.type == step.type && normalized($0.label) == step.label && source($0) == step.source }
            // The same mana from another source when the original is gone (a sacrificed Treasure).
            if match == nil, step.type == "make_mana", let mana = step.producedMana, !mana.isEmpty {
                match = actions.first { $0.type == "make_mana" && Set($0.producedMana ?? []).isSuperset(of: mana) }
            }
            guard let action = match else { return nil }
            return ComboReplay(command: GameCommand(action: action, gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision),
                               label: action.label, actionID: action.id, chosenNames: [], retargeted: nil)
        case .prompt:
            guard let prompt = snapshot.promptEnvelopeV2, prompt.method == step.label, snapshot.isViewer(prompt.playerId) else { return nil }
            var pool: [(id: String, target: ComboTarget)] = []
            for option in (prompt.targets ?? []) + (prompt.choices ?? []) + (prompt.modes ?? []) + (prompt.orderedItems ?? []) { pool.append((option.id, target(option.id, known))) }
            for card in prompt.cards ?? [] { pool.append((card.instanceId, target(card.instanceId, known))) }
            for player in prompt.players ?? [] { pool.append((player.playerId, target(player.playerId, known))) }
            for ability in prompt.abilities ?? [] { pool.append((ability.id, target(ability.id, known))) }
            var ids: [String] = [], names: [String] = []
            var retargeted: (from: String, to: String)?
            for (place, wanted) in step.targets.enumerated() {
                let preferred = place < prefer.count ? prefer[place] : wanted.name
                let found = pool.firstIndex { $0.target == wanted && $0.target.name == preferred }
                    ?? pool.firstIndex { $0.target == wanted && $0.target.name == wanted.name }
                    ?? pool.firstIndex { $0.target == wanted }
                guard let index = found else { return nil }
                let picked = pool.remove(at: index)
                if picked.target.name != preferred, wanted.kind != "option", wanted.controller == "opponent", retargeted == nil {
                    retargeted = (preferred, picked.target.name)
                }
                ids.append(picked.id); names.append(picked.target.name)
            }
            let promptID = prompt.responseCommand?.promptId ?? prompt.id
            if step.type == "answer_yes_no" || step.type == "pay_cost" {
                guard let confirmed = step.confirmed ?? step.pay else { return nil }
                return ComboReplay(command: GameCommand(type: step.type, gameId: snapshot.id, playerId: snapshot.viewerID, promptId: promptID,
                                                        messageId: prompt.responseCommand?.messageId ?? prompt.messageId, confirmed: confirmed,
                                                        pay: step.type == "pay_cost" ? confirmed : nil),
                                   label: step.type, actionID: "combo-loop-\(promptID)", chosenNames: names, retargeted: nil)
            }
            guard let command = PromptCommandBuilder.command(gameId: snapshot.id, promptEnvelope: prompt, type: step.type, promptId: promptID,
                                                             playerId: snapshot.viewerID, ids: ids, amount: step.amount, amounts: step.amounts,
                                                             pile: step.pile, useCommandZone: step.useCommandZone,
                                                             manaType: step.manaTypes?.first, pay: step.pay) else { return nil }
            return ComboReplay(command: command, label: step.type, actionID: "combo-loop-\(promptID)", chosenNames: names, retargeted: retargeted)
        }
    }

    /// The parts of the game a loop changes: life, poison, every permanent's power, toughness, damage, counters and tapped
    /// state, zone sizes, mana and spells cast. A round that leaves all of it unchanged did nothing visible.
    static func digest(_ snapshot: GameSnapshot) -> String {
        snapshot.players.sorted { $0.playerId < $1.playerId }.map { player in
            let zones = player.zones
            let pool = player.manaPool.map { "\($0.W),\($0.U),\($0.B),\($0.R),\($0.G),\($0.C)" } ?? ""
            let permanents = zones.battlefield.map { card -> String in
                let counters = (card.counters ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)\($0.value)" }.joined()
                return "\(card.card.name)/\(card.power ?? -99)/\(card.toughness ?? -99)/\(card.damage ?? 0)/\(card.tapped == true ? 1 : 0)/\(counters)"
            }.sorted().joined(separator: ",")
            let counters = (player.counters ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)\($0.value)" }.joined()
            return "\(player.playerId):\(player.life):\(player.poison):\(zones.visibleHandCount):\(zones.visibleLibraryCount):"
                + "\(zones.graveyard.count):\(zones.exile.count):\(counters):\(pool):[\(permanents)]"
        }.joined(separator: "|") + "|storm:\(snapshot.stormCount ?? 0)"
    }

    /// An opponent put something on the stack: their spell, or an ability of one of their permanents.
    static func opponentResponded(_ snapshot: GameSnapshot) -> Bool {
        let opponents = snapshot.players.filter { !snapshot.isViewer($0.playerId) }
        if opponents.contains(where: { !$0.zones.stack.isEmpty }) { return true }
        let theirs = Set(opponents.flatMap { $0.zones.battlefield.map(\.instanceId) })
        return (snapshot.xmage?.stack ?? []).contains { object in
            if let controller = object.controllerId, !controller.isEmpty, !snapshot.isViewer(controller),
               snapshot.players.contains(where: { $0.playerId == controller }) { return true }
            return object.sourceInstanceId.map(theirs.contains) ?? false
        }
    }

    /// One round on the running card: "Round 3 · Activate Chatterfang → Kinjalli's Caller".
    static func roundLine(_ round: Int, _ cycle: [ComboStep], chosen: [String]) -> String {
        let at = chosen.first.map { " → \($0)" } ?? ""
        return String(localized: "Round \(round) · \(describe(cycle))\(at)")
    }

    /// The closing line: how many rounds ran and whose life changed.
    static func summary(rounds: Int, before: GameSnapshot, after: GameSnapshot) -> String {
        var parts = [rounds == 1 ? String(localized: "Repeated once") : String(localized: "Repeated \(rounds) times")]
        for player in after.players {
            guard let old = before.players.first(where: { $0.playerId == player.playerId }), old.life != player.life else { continue }
            let name = after.isViewer(player.playerId) ? String(localized: "You") : (player.displayName ?? String(localized: "Opponent"))
            parts.append("\(name) \(old.life) → \(player.life)")
        }
        return parts.joined(separator: " · ")
    }

    /// Why a step couldn't be taken, in words: "no Squirrel token to choose", "Chatterfang isn't available".
    static func missing(_ step: ComboStep) -> String {
        switch step.kind {
        case .action: return String(localized: "\(step.source ?? step.label) isn't available")
        case .prompt:
            guard let thing = step.targets.first, thing.kind != "option" else { return String(localized: "the next choice isn't offered") }
            if thing.controller == "opponent" { return thing.token ? String(localized: "no opponent's \(thing.kind) token left to choose") : String(localized: "no opponent's \(thing.kind) left to choose") }
            return thing.token ? String(localized: "no \(thing.name) token left") : String(localized: "\(thing.name) isn't there to choose")
        }
    }
}

/// Why repeating a loop stopped.
/// Whether repeating a round ends the game, read from the rounds the player made: every opponent lost the same life
/// (or got the same poison) each round, so the rounds still needed can be counted; and whether an opponent can visibly
/// answer (cards in hand and an untapped land). A hidden instant can still stop the loop: the rules check every step.
struct ComboWinForecast: Equatable, Sendable {
    /// Life and poison of one opponent at the start of a round.
    struct Standing: Equatable, Sendable {
        var life: Int
        var poison: Int
    }

    /// Rounds until every opponent has lost.
    let rounds: Int
    /// An opponent holds cards and has an untapped land.
    let opponentsCanRespond: Bool

    var canFinish: Bool { !opponentsCanRespond }

    /// `starts`: each opponent's standing at the start of the last rounds, oldest first (at least three). Only round
    /// starts count: the latest round's drain can still be waiting on the stack (Blood Artist, Impact Tremors) when the
    /// loop is offered. `rounds` is what's still needed once that latest round has finished.
    static func forecast(starts: [[String: Standing]], opponentsCanRespond: Bool,
                         cap: Int = ComboLoop.maxRepeats) -> ComboWinForecast? {
        guard starts.count >= 3, let last = starts.last, !last.isEmpty else { return nil }
        var needed = 0
        for (player, standing) in last {
            let history = starts.compactMap { $0[player] }
            guard history.count == starts.count else { return nil }
            let lifeLoss = zip(history, history.dropFirst()).map { $0.life - $1.life }
            let poisonGain = zip(history, history.dropFirst()).map { $1.poison - $0.poison }
            let rounds: Int
            if let loss = lifeLoss.first, loss > 0, lifeLoss.allSatisfy({ $0 == loss }) {
                rounds = max(0, (standing.life + loss - 1) / loss - 1)
            } else if let gain = poisonGain.first, gain > 0, poisonGain.allSatisfy({ $0 == gain }) {
                rounds = max(0, (10 - standing.poison + gain - 1) / gain - 1)
            } else {
                return nil
            }
            needed = max(needed, rounds)
        }
        guard needed <= cap else { return nil }
        return ComboWinForecast(rounds: needed, opponentsCanRespond: opponentsCanRespond)
    }

    /// Each opponent's life and poison in a snapshot.
    static func standings(_ snapshot: GameSnapshot) -> [String: Standing] {
        Dictionary(uniqueKeysWithValues: snapshot.players.filter { !snapshot.isViewer($0.playerId) && !$0.isOut }
            .map { ($0.playerId, Standing(life: $0.life, poison: $0.poison)) })
    }

    /// An opponent holds cards and has an untapped land: they could answer.
    static func opponentsCanRespond(_ snapshot: GameSnapshot) -> Bool {
        snapshot.players.filter { !snapshot.isViewer($0.playerId) && !$0.isOut }.contains { player in
            player.zones.visibleHandCount > 0 && player.zones.battlefield.contains { $0.card.isLand && $0.tapped != true }
        }
    }
}

enum ComboLoopStop: Equatable, Sendable {
    case finished
    case gameOver
    case stepMissing(String)
    case opponentResponded
    case nothingChanged
    case reachedLimit
    /// "Until they lose" ran the rounds its forecast needed, and a few more, without ending the game.
    case didNotFinish(Int)
    case stoppedByPlayer
    case failed(String)

    var message: String {
        switch self {
        case .finished: return String(localized: "Done.")
        case .gameOver: return String(localized: "The game is over.")
        case .stepMissing(let why): return String(localized: "Stopped: \(why).")
        case .opponentResponded: return String(localized: "An opponent responded, so it's your turn to choose.")
        case .nothingChanged: return String(localized: "The loop stopped changing the game.")
        case .reachedLimit: return String(localized: "Stopped after \(ComboLoop.maxRepeats) rounds.")
        case .didNotFinish(let rounds): return String(localized: "Stopped after \(rounds) rounds: the loop didn't end the game.")
        case .stoppedByPlayer: return String(localized: "Stopped.")
        case .failed(let reason): return reason
        }
    }
}

extension GameCommand {
    /// The command a board action sends (OnDeviceSession.send(action:)).
    init(action: LegalAction, gameId: String, bridgeRevision: Int?) {
        self.init(
            type: action.type, gameId: gameId, playerId: action.playerId,
            cardInstanceId: action.cardInstanceId, sourceInstanceId: action.sourceInstanceId,
            abilityId: action.abilityId, promptId: action.promptId, messageId: action.messageId,
            choiceIds: action.choiceIds, targetIds: action.targetIds, cardInstanceIds: action.cardInstanceIds,
            modeIds: action.modeIds, pile: action.pile?.value, amount: action.amount, amounts: action.amounts,
            orderedIds: action.orderedIds, useCommandZone: action.useCommandZone,
            manaType: action.manaType, manaTypes: action.manaTypes, playerIds: action.playerIds,
            confirmed: action.confirmed, pay: action.pay, sourceZone: action.sourceZone,
            fromZone: action.sourceZone, cardName: action.cardName, attackers: action.attackers,
            blockers: action.blockers, expectedBridgeRevision: bridgeRevision
        )
    }
}

extension GameSnapshot {
    /// The board's copy while a loop repeats: the prompts the repeats answer are not shown.
    var withoutPrompts: GameSnapshot {
        var copy = self
        copy.legalActions = nil
        copy.choicePrompt = nil
        copy.promptEnvelope = nil
        copy.promptEnvelopeV2 = nil
        copy.manaPayment = nil
        return copy
    }
}
