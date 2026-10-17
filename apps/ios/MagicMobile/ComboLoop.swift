import Foundation

/// The combo loop shortcut (roadmap release B): after the player makes the same sequence of choices three times in a row
/// in one turn, the app offers to repeat it. Each repeat is an ordinary answer the engine checks, so no rule is skipped;
/// the repeats stop the moment anything differs. Steps are kept by meaning (the card's name, the action's text, the
/// targets' names), never by ids: a token made by the loop has a new id each time round. Android's ComboLoop.kt matches it;
/// apps/android/core/src/test/resources/parity/combo-loop-cases.json checks both.
struct ComboStep: Codable, Equatable, Hashable, Sendable {
    /// A legal action from the board (cast, activate, play, tap for mana, pass), or an answer to a prompt.
    enum Kind: String, Codable, Sendable { case action, prompt }

    var kind: Kind
    var type: String
    /// The source card's name, for actions.
    var source: String?
    /// The action's text, normalized; for prompts, the prompt's method (GAME_TARGET, GAME_ASK, ...).
    var label: String
    /// The chosen targets, cards or options by their shown names, in order.
    var targets: [String] = []
    var amount: Int?
    var amounts: [Int]?
    var pile: Int?
    var manaTypes: [String]?
    var confirmed: Bool?
    var pay: Bool?
    var useCommandZone: Bool?
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
    /// The counts offered (plus "until they lose").
    static let repeatChoices = [5, 10, 20]
    /// A full round that changes nothing visible twice in a row stops the repeats.
    static let unchangedRoundsToStop = 2

    private static let comboTypes: Set<String> = ["activate_ability", "cast_spell"]
    private static let excludedTypes: Set<String> = ["declare_attackers", "declare_blockers", "mulligan", "keep_hand", "concede",
                                                     "commander_replacement", "choose_starting_player"]

    // MARK: Steps

    static func normalized(_ label: String) -> String {
        label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A card or option's shown name by id, from the prompt first, then every visible zone and the stack.
    static func names(in snapshot: GameSnapshot) -> [String: String] {
        var names: [String: String] = [:]
        for player in snapshot.players {
            names[player.playerId] = player.playerId == snapshot.viewerID ? "You" : (player.displayName ?? player.playerId)
            let zones = player.zones
            for card in zones.battlefield + zones.hand + zones.graveyard + zones.exile + zones.command + zones.stack + zones.library {
                names[card.instanceId] = card.card.name
            }
        }
        for object in snapshot.xmage?.stack ?? [] {
            if let id = object.sourceInstanceId, let name = object.sourceName { names[id] = names[id] ?? name }
        }
        if let prompt = snapshot.promptEnvelopeV2 {
            for option in (prompt.targets ?? []) + (prompt.choices ?? []) + (prompt.modes ?? []) + (prompt.orderedItems ?? []) {
                names[option.id] = option.label
            }
            for card in prompt.cards ?? [] { names[card.instanceId] = card.card.name }
            for player in prompt.players ?? [] { names[player.id] = player.label; names[player.playerId] = player.label }
            for ability in prompt.abilities ?? [] { names[ability.id] = ability.label }
        }
        return names
    }

    /// The step a player's answer makes, or nil for answers that never belong in a loop.
    static func step(command: GameCommand, label: String, actionID: String, snapshot: GameSnapshot?) -> ComboStep? {
        guard let snapshot, !excludedTypes.contains(command.type) else { return nil }
        let names = names(in: snapshot)
        func named(_ ids: [String]?) -> [String] { (ids ?? []).map { names[$0] ?? "?" } }
        if let action = snapshot.legalActions?.first(where: { $0.id == actionID }) {
            let source = (action.sourceInstanceId ?? action.cardInstanceId).flatMap { names[$0] } ?? action.cardName
            return ComboStep(kind: .action, type: command.type, source: source, label: normalized(action.label),
                             targets: named(command.targetIds) + named(command.cardInstanceIds) + named(command.playerIds),
                             amount: command.amount, amounts: command.amounts, pile: command.pile,
                             manaTypes: command.manaTypes ?? command.manaType.map { [$0] }, confirmed: command.confirmed, pay: command.pay,
                             useCommandZone: command.useCommandZone)
        }
        guard let prompt = snapshot.promptEnvelopeV2, command.promptId == prompt.id || command.promptId == prompt.responseCommand?.promptId else { return nil }
        let chosen = named(command.targetIds) + named(command.cardInstanceIds) + named(command.playerIds) + named(command.choiceIds)
            + named(command.modeIds) + named(command.orderedIds) + named(command.abilityId.map { [$0] })
        return ComboStep(kind: .prompt, type: command.type, source: nil, label: prompt.method, targets: chosen,
                         amount: command.amount, amounts: command.amounts, pile: command.pile,
                         manaTypes: command.manaTypes ?? command.manaType.map { [$0] }, confirmed: command.confirmed, pay: command.pay,
                         useCommandZone: command.useCommandZone)
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

    /// What the offer says about the loop: its casts and activations, briefly.
    static func describe(_ round: [ComboStep]) -> String {
        let parts = round.filter { $0.kind == .action && comboTypes.contains($0.type) }.map { step -> String in
            let verb = step.type == "cast_spell" ? String(localized: "Cast") : String(localized: "Activate")
            return "\(verb) \(step.source ?? step.label)"
        }
        return parts.joined(separator: " → ")
    }

    // MARK: Repeating it

    /// The answer this step makes now, from the current legal actions or prompt; nil when it isn't available.
    static func command(for step: ComboStep, in snapshot: GameSnapshot) -> (command: GameCommand, label: String, actionID: String)? {
        let names = names(in: snapshot)
        switch step.kind {
        case .action:
            guard let action = snapshot.legalActions?.first(where: { action in
                action.type == step.type && normalized(action.label) == step.label
                    && ((action.sourceInstanceId ?? action.cardInstanceId).flatMap { names[$0] } ?? action.cardName) == step.source
            }) else { return nil }
            return (GameCommand(action: action, gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision), action.label, action.id)
        case .prompt:
            guard let prompt = snapshot.promptEnvelopeV2, prompt.method == step.label, snapshot.isViewer(prompt.playerId) else { return nil }
            // Each chosen name takes a different option with that name (two Squirrels are two choices).
            var pool: [(id: String, name: String)] = []
            for option in (prompt.targets ?? []) + (prompt.choices ?? []) + (prompt.modes ?? []) + (prompt.orderedItems ?? []) { pool.append((option.id, option.label)) }
            for card in prompt.cards ?? [] { pool.append((card.instanceId, card.card.name)) }
            for player in prompt.players ?? [] { pool.append((player.playerId, player.label)) }
            for ability in prompt.abilities ?? [] { pool.append((ability.id, ability.label)) }
            var ids: [String] = []
            for name in step.targets {
                guard let index = pool.firstIndex(where: { $0.name == name || names[$0.id] == name }) else { return nil }
                ids.append(pool.remove(at: index).id)
            }
            let promptID = prompt.responseCommand?.promptId ?? prompt.id
            if step.type == "answer_yes_no" || step.type == "pay_cost" {
                guard let confirmed = step.confirmed ?? step.pay else { return nil }
                return (GameCommand(type: step.type, gameId: snapshot.id, playerId: snapshot.viewerID, promptId: promptID,
                                    messageId: prompt.responseCommand?.messageId ?? prompt.messageId, confirmed: confirmed,
                                    pay: step.type == "pay_cost" ? confirmed : nil), step.type, "combo-loop-\(promptID)")
            }
            guard let command = PromptCommandBuilder.command(gameId: snapshot.id, promptEnvelope: prompt, type: step.type, promptId: promptID,
                                                             playerId: snapshot.viewerID, ids: ids, amount: step.amount, amounts: step.amounts,
                                                             pile: step.pile, useCommandZone: step.useCommandZone,
                                                             manaType: step.manaTypes?.first, pay: step.pay) else { return nil }
            return (command, step.type, "combo-loop-\(promptID)")
        }
    }

    /// The parts of the game a loop changes: life, poison, zone sizes, counters, mana and spells cast. A round that leaves
    /// all of it unchanged has stopped doing anything.
    static func digest(_ snapshot: GameSnapshot) -> String {
        snapshot.players.sorted { $0.playerId < $1.playerId }.map { player in
            let zones = player.zones
            let pool = player.manaPool.map { "\($0.W),\($0.U),\($0.B),\($0.R),\($0.G),\($0.C)" } ?? ""
            let counters = zones.battlefield.reduce(0) { $0 + ($1.counters?.values.reduce(0, +) ?? 0) } + (player.counters?.values.reduce(0, +) ?? 0)
            return "\(player.playerId):\(player.life):\(player.poison):\(zones.visibleHandCount):\(zones.visibleLibraryCount):\(zones.battlefield.count):"
                + "\(zones.graveyard.count):\(zones.exile.count):\(counters):\(pool)"
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
}

/// Why repeating a loop stopped.
enum ComboLoopStop: Equatable, Sendable {
    case finished
    case gameOver
    case stepMissing
    case opponentResponded
    case nothingChanged
    case reachedLimit
    case stoppedByPlayer
    case failed(String)

    var message: String {
        switch self {
        case .finished: return String(localized: "Done.")
        case .gameOver: return String(localized: "The game is over.")
        case .stepMissing: return String(localized: "A step isn't available any more, so it's your turn to choose.")
        case .opponentResponded: return String(localized: "An opponent responded, so it's your turn to choose.")
        case .nothingChanged: return String(localized: "The loop stopped changing the game.")
        case .reachedLimit: return String(localized: "Stopped after \(ComboLoop.maxRepeats) rounds.")
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
