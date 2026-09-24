import Foundation

// Board FX phase 1: turn successive public snapshots into presentation events.
// XMage stays the source of truth. These events only decorate a transition the
// client has already applied, and they never read beyond the viewer's snapshot.

enum BoardFXZone: String, Equatable {
    case hand, library, battlefield, graveyard, exile, command, stack
}

enum BoardFXTint: String, Equatable {
    case white, blue, black, red, green, multicolor, colorless

    init(card: CardIdentity) {
        var colors = Set<String>()
        if let manaCost = card.manaCost?.uppercased() {
            for symbol in ["W", "U", "B", "R", "G"] where manaCost.contains(symbol) {
                colors.insert(symbol)
            }
        }
        if colors.isEmpty, let tokenColors = card.tokenColors {
            for color in tokenColors {
                switch color.lowercased() {
                case "w", "white": colors.insert("W")
                case "u", "blue": colors.insert("U")
                case "b", "black": colors.insert("B")
                case "r", "red": colors.insert("R")
                case "g", "green": colors.insert("G")
                default: break
                }
            }
        }
        switch colors.count {
        case 0: self = .colorless
        case 1:
            switch colors.first {
            case "W": self = .white
            case "U": self = .blue
            case "B": self = .black
            case "R": self = .red
            default: self = .green
            }
        default: self = .multicolor
        }
    }
}

/// Printed mana value from a visible cost such as "{3}{B}{B}". X counts as zero.
enum BoardFXManaValue {
    static func of(_ cost: String?) -> Int {
        guard let cost, let regex = try? NSRegularExpression(pattern: #"\{([^}]+)\}"#) else { return 0 }
        let text = cost as NSString
        return regex.matches(in: cost, range: NSRange(location: 0, length: text.length)).reduce(0) { total, match in
            let symbol = text.substring(with: match.range(at: 1)).uppercased()
            if let number = Int(symbol) { return total + number }
            if symbol == "X" || symbol == "Y" || symbol == "Z" { return total }
            // {2/W} costs two; other hybrid and Phyrexian symbols cost one.
            if symbol.hasPrefix("2/") { return total + 2 }
            return total + 1
        }
    }
}

/// Cheap change key: the board recomputes FX state only when this moves.
struct BoardFXRevisionKey: Equatable {
    let gameID: String
    let bridgeRevision: Int?
    let xmageCycle: Int?
    let turn: Int
    let lives: [Int]

    init(snapshot: GameSnapshot) {
        gameID = snapshot.id
        bridgeRevision = snapshot.bridgeRevision
        xmageCycle = snapshot.xmageCycle
        turn = snapshot.turn
        lives = snapshot.players.map(\.life)
    }
}

/// Minimal public board state used for diffing.
struct BoardFXState: Equatable {
    struct Card: Equatable {
        let id: String
        let playerID: String
        let zone: BoardFXZone
        let name: String
        let tint: BoardFXTint
        let damage: Int
        let counters: Int
        let attacking: Bool
        var blocking: [String] = []
        var isLand = false
        var isToken = false
    }

    struct StackItem: Equatable {
        let id: String
        let name: String
        let controllerID: String?
        let tint: BoardFXTint
        var isAbility = false
        var manaValue = 0
    }

    let gameID: String
    let step: String
    let lives: [String: Int]
    let cards: [String: Card]
    let stack: [StackItem]
    /// Attacker instance ID to the defending player or permanent ID (public combat groups).
    let defenders: [String: String]
    /// Non-token card names currently in any command zone (commanders).
    let commandNames: Set<String>

    init(gameID: String, step: String, lives: [String: Int], cards: [String: Card], stack: [StackItem] = [],
         defenders: [String: String] = [:], commandNames: Set<String> = []) {
        self.gameID = gameID
        self.step = step
        self.lives = lives
        self.cards = cards
        self.stack = stack
        self.defenders = defenders
        self.commandNames = commandNames
    }

    init(snapshot: GameSnapshot) {
        gameID = snapshot.id
        step = (snapshot.step ?? snapshot.phase).lowercased().replacingOccurrences(of: "_", with: "-")
        lives = Dictionary(snapshot.players.map { ($0.playerId, $0.life) }, uniquingKeysWith: { first, _ in first })
        var cards: [String: Card] = [:]
        var commandNames = Set<String>()
        for player in snapshot.players {
            let zones: [(BoardFXZone, [ZoneCard])] = [
                (.hand, player.zones.hand), (.library, player.zones.library),
                (.battlefield, player.zones.battlefield), (.graveyard, player.zones.graveyard),
                (.exile, player.zones.exile), (.command, player.zones.command), (.stack, player.zones.stack),
            ]
            for (zone, zoneCards) in zones {
                for card in zoneCards where cards[card.instanceId] == nil {
                    cards[card.instanceId] = Card(
                        id: card.instanceId, playerID: player.playerId, zone: zone,
                        name: card.card.name, tint: BoardFXTint(card: card.card),
                        damage: card.damage ?? 0,
                        counters: (card.counters ?? [:]).values.reduce(0, +),
                        attacking: card.isAttacking == true,
                        blocking: card.blocking ?? [],
                        isLand: card.card.isLand,
                        isToken: card.card.isToken == true)
                }
            }
            for card in player.zones.command where card.card.isToken != true {
                commandNames.insert(card.card.name)
            }
        }
        self.cards = cards
        self.commandNames = commandNames
        stack = snapshot.stackTopFirst.map { object in
            let source = object.displaySourceCard
            let tint = object.sourceCard.map { BoardFXTint(card: $0.card) } ?? .colorless
            let ability = object.objectType?.localizedCaseInsensitiveContains("ability") == true
                || object.displayName.localizedCaseInsensitiveContains("ability")
            return StackItem(id: object.id, name: object.displayName, controllerID: object.controllerId, tint: tint,
                             isAbility: ability, manaValue: BoardFXManaValue.of(source?.card.manaCost))
        }
        var defenders: [String: String] = [:]
        for group in snapshot.xmage?.combat ?? [] {
            for attacker in group.attackers { defenders[attacker.instanceId] = group.defenderId }
        }
        self.defenders = defenders
    }
}

/// How much ceremony a stack object gets.
enum BoardFXSpellWeight: Equatable {
    case ability, spell, big, commander
}

/// How a permanent arrives: straight to its slot, or shown at the center first.
enum BoardFXEntrance: Equatable {
    case plain, showcase, commander
}

enum BoardFXStrikeTarget: Equatable {
    case card(String), player(String)
}

enum BoardFXEvent: Equatable {
    case spellCast(stackID: String, name: String, controllerID: String?, tint: BoardFXTint, weight: BoardFXSpellWeight)
    case attackDeclared(cardID: String, tint: BoardFXTint)
    case blockDeclared(cardID: String, attackerID: String)
    case combatStrike(attackerID: String, target: BoardFXStrikeTarget, tint: BoardFXTint)
    case damageMarked(cardID: String, amount: Int)
    case leftBattlefield(cardID: String, playerID: String, to: BoardFXZone?, tint: BoardFXTint)
    case enteredBattlefield(cardID: String, playerID: String, from: BoardFXZone?, tint: BoardFXTint, entrance: BoardFXEntrance)
    case countersAdded(cardID: String, amount: Int)
    case lifeChanged(playerID: String, delta: Int)

    /// Presentation order inside one snapshot transition.
    var order: Int {
        switch self {
        case .spellCast: return 0
        case .attackDeclared: return 1
        case .blockDeclared: return 2
        case .combatStrike: return 3
        case .damageMarked: return 4
        case .leftBattlefield: return 5
        case .enteredBattlefield: return 6
        case .countersAdded: return 7
        case .lifeChanged: return 8
        }
    }

    /// Card, stack object or player the effect is about.
    var subjectID: String {
        switch self {
        case let .spellCast(id, _, _, _, _), let .leftBattlefield(id, _, _, _), let .damageMarked(id, _),
             let .enteredBattlefield(id, _, _, _, _), let .countersAdded(id, _), let .attackDeclared(id, _),
             let .blockDeclared(id, _), let .combatStrike(id, _, _), let .lifeChanged(id, _):
            return id
        }
    }

    /// Life totals are always shown; they carry game information, not decoration.
    var isEssential: Bool {
        if case .lifeChanged = self { return true }
        return false
    }
}

enum BoardEventDiffer {
    /// Steps before combat damage; leaving them with attackers present means damage was dealt.
    static let preDamageSteps: Set<String> = ["combat", "begin-combat", "declare-attackers", "declare-blockers"]
    /// Spells at or above this printed mana value get the big-spell flash.
    static let bigSpellManaValue = 6

    static func events(from old: BoardFXState, to new: BoardFXState, commanders: Set<String> = []) -> [BoardFXEvent] {
        // A new game, reconnect to another match or design preview swap is a cut, not a transition.
        guard old.gameID == new.gameID else { return [] }
        var events: [BoardFXEvent] = []

        let oldStackIDs = Set(old.stack.map(\.id))
        var castNames = Set<String>()
        for item in new.stack where !oldStackIDs.contains(item.id) {
            let weight: BoardFXSpellWeight
            if item.isAbility { weight = .ability }
            else if commanders.contains(item.name) { weight = .commander }
            else if item.manaValue >= bigSpellManaValue { weight = .big }
            else { weight = .spell }
            if !item.isAbility { castNames.insert(item.name) }
            events.append(.spellCast(stackID: item.id, name: item.name, controllerID: item.controllerID, tint: item.tint, weight: weight))
        }
        // A permanent spell that was on the stack flies from there, without a second showcase.
        let resolvedNames = Set(old.stack.filter { !$0.isAbility }.map(\.name)).union(castNames)

        var claimedArrivals = Set<String>()
        for card in old.cards.values.sorted(by: { $0.id < $1.id }) where card.zone == .battlefield {
            if let next = new.cards[card.id] {
                if next.zone != .battlefield {
                    events.append(.leftBattlefield(cardID: card.id, playerID: card.playerID, to: next.zone, tint: card.tint))
                }
                continue
            }
            // XMage can assign a new object ID when a card changes zones. Match the
            // same name arriving in a public zone of the same player; otherwise unknown.
            let arrival = new.cards.values
                .filter { $0.playerID == card.playerID && $0.name == card.name && old.cards[$0.id] == nil && !claimedArrivals.contains($0.id) }
                .filter { [.graveyard, .exile, .command].contains($0.zone) }
                .min { $0.id < $1.id }
            if let arrival { claimedArrivals.insert(arrival.id) }
            events.append(.leftBattlefield(cardID: card.id, playerID: card.playerID, to: arrival?.zone, tint: card.tint))
        }

        for card in new.cards.values.sorted(by: { $0.id < $1.id }) where card.zone == .battlefield {
            let previous = old.cards[card.id]
            guard let previous, previous.zone == .battlefield else {
                var source = previous?.zone
                let entrance: BoardFXEntrance
                if !card.isToken && commanders.contains(card.name) {
                    entrance = .commander
                    if resolvedNames.contains(card.name) { source = .stack }
                } else if resolvedNames.contains(card.name) && source != .hand {
                    entrance = .plain
                    source = .stack
                } else if !card.isLand && !card.isToken && (source == nil || source == .hand) {
                    // Cast and resolved between two snapshots: nobody saw it on the stack.
                    entrance = .showcase
                } else {
                    entrance = .plain
                }
                events.append(.enteredBattlefield(cardID: card.id, playerID: card.playerID, from: source, tint: card.tint, entrance: entrance))
                continue
            }
            if card.attacking && !previous.attacking {
                events.append(.attackDeclared(cardID: card.id, tint: card.tint))
            }
            if let attacker = card.blocking.first, previous.blocking.isEmpty {
                events.append(.blockDeclared(cardID: card.id, attackerID: attacker))
            }
            if card.damage > previous.damage {
                events.append(.damageMarked(cardID: card.id, amount: card.damage - previous.damage))
            }
            if card.counters > previous.counters {
                events.append(.countersAdded(cardID: card.id, amount: card.counters - previous.counters))
            }
        }

        if preDamageSteps.contains(old.step) && !preDamageSteps.contains(new.step) {
            for attacker in old.cards.values.sorted(by: { $0.id < $1.id })
            where attacker.zone == .battlefield && attacker.attacking {
                events.append(.combatStrike(attackerID: attacker.id, target: strikeTarget(attacker, old: old, new: new), tint: attacker.tint))
            }
        }

        for (playerID, life) in new.lives.sorted(by: { $0.key < $1.key }) {
            if let previous = old.lives[playerID], previous != life {
                events.append(.lifeChanged(playerID: playerID, delta: life - previous))
            }
        }

        return events.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }

    /// Blocker first, then the public combat defender, then the first opponent.
    static func strikeTarget(_ attacker: BoardFXState.Card, old: BoardFXState, new: BoardFXState) -> BoardFXStrikeTarget {
        let blockers = (old.cards.values.filter { $0.blocking.contains(attacker.id) }
            + new.cards.values.filter { $0.blocking.contains(attacker.id) }).map(\.id).sorted()
        if let blocker = blockers.first { return .card(blocker) }
        if let defender = old.defenders[attacker.id] ?? new.defenders[attacker.id] {
            if old.lives[defender] != nil { return .player(defender) }
            if old.cards[defender] != nil { return .card(defender) }
        }
        let opponent = old.lives.keys.sorted().first { $0 != attacker.playerID }
        return .player(opponent ?? attacker.playerID)
    }
}

enum BoardFXLevel: String, CaseIterable, Identifiable {
    case full, reduced, off

    static let key = "magicmobile.boardEffectsLevel"
    static let defaultValue = BoardFXLevel.full.rawValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full"
        case .reduced: return "Reduced"
        case .off: return "Off"
        }
    }

    /// System Reduce Motion always caps the level at `.reduced`.
    static func resolved(stored: String, reduceMotion: Bool) -> BoardFXLevel {
        let level = BoardFXLevel(rawValue: stored) ?? .full
        return reduceMotion && level == .full ? .reduced : level
    }
}

struct ScheduledBoardFX: Equatable, Identifiable {
    let id: Int
    let event: BoardFXEvent
    let delay: TimeInterval
    let duration: TimeInterval
    /// Particles, shake and large motion are omitted when false.
    let usesMotion: Bool

    var end: TimeInterval { delay + duration }

    /// When a card arriving with this effect lands in its slot (the tile appears).
    var landing: TimeInterval {
        guard usesMotion, case let .enteredBattlefield(_, _, _, _, entrance) = event else { return delay }
        return delay + duration * BoardFXScheduler.landingFraction(entrance)
    }

    /// When the next group of effects may begin. Spell showcases finish first,
    /// strikes hand over at impact, and showcased arrivals once they land.
    var handoff: TimeInterval {
        switch event {
        case let .spellCast(_, _, _, _, weight):
            guard usesMotion else { return delay + 0.4 }
            return weight == .ability ? delay + 0.55 : end - 0.3
        case .combatStrike where usesMotion:
            return delay + duration * BoardFXScheduler.strikeImpactFraction
        case let .enteredBattlefield(_, _, _, _, entrance) where usesMotion && entrance != .plain:
            return landing
        default:
            return delay + (usesMotion ? 0.16 : 0.06)
        }
    }

    /// Showcases share the center of the board, so they play one after another.
    var isSequential: Bool {
        guard usesMotion else { return false }
        switch event {
        case let .spellCast(_, _, _, _, weight): return weight != .ability
        case let .enteredBattlefield(_, _, _, _, entrance): return entrance != .plain
        default: return false
        }
    }
}

enum BoardFXScheduler {
    /// Decorative effects per transition; board wipes collapse to the first few.
    static let decorativeLimit = 10
    static let stagger: TimeInterval = 0.07
    /// Effects never wait more than this for a showcase from an earlier snapshot.
    static let maximumHold: TimeInterval = 3

    static func schedule(_ events: [BoardFXEvent], level: BoardFXLevel, firstID: Int = 0,
                         hold: TimeInterval = 0) -> [ScheduledBoardFX] {
        guard level != .off else { return [] }
        let motion = level == .full
        var decorativeCount = 0
        var kept: [BoardFXEvent] = []
        for event in events {
            if event.isEssential {
                kept.append(event)
            } else if decorativeCount < decorativeLimit {
                decorativeCount += 1
                kept.append(event)
            }
        }
        var result: [ScheduledBoardFX] = []
        var groupStart = min(max(hold, 0), maximumHold)
        var sequentialCursor = groupStart
        var previousOrder: Int?
        var indexInGroup = 0
        for event in kept {
            if let previousOrder, previousOrder != event.order {
                groupStart = result.map(\.handoff).max() ?? groupStart
                sequentialCursor = groupStart
                indexInGroup = 0
            }
            previousOrder = event.order
            let duration = duration(of: event, motion: motion)
            let id = firstID + result.count
            let probe = ScheduledBoardFX(id: id, event: event, delay: 0, duration: duration, usesMotion: motion)
            let fx: ScheduledBoardFX
            if probe.isSequential {
                fx = ScheduledBoardFX(id: id, event: event, delay: sequentialCursor, duration: duration, usesMotion: motion)
                sequentialCursor = fx.handoff + 0.1
            } else {
                let delay = groupStart + Double(indexInGroup) * (motion ? stagger : 0.02)
                fx = ScheduledBoardFX(id: id, event: event, delay: delay, duration: duration, usesMotion: motion)
                indexInGroup += 1
            }
            result.append(fx)
        }
        return result
    }

    /// Share of a plain arrival spent flying before the card lands (Full level only).
    static let arrivalFlightFraction = 0.42
    /// Share of a strike spent winding up and charging before impact.
    static let strikeImpactFraction = 0.42

    static func landingFraction(_ entrance: BoardFXEntrance) -> Double {
        switch entrance {
        case .plain: return arrivalFlightFraction
        case .showcase: return 0.82
        case .commander: return 0.8
        }
    }

    static func duration(of event: BoardFXEvent, motion: Bool) -> TimeInterval {
        switch event {
        case let .spellCast(_, _, _, _, weight):
            // Long enough to read the card at the center before it moves on.
            switch weight {
            case .ability: return motion ? 1.3 : 1.1
            case .spell: return motion ? 2.4 : 1.5
            case .big: return motion ? 2.7 : 1.5
            case .commander: return motion ? 3.1 : 1.6
            }
        case let .enteredBattlefield(_, _, _, _, entrance):
            guard motion else { return 0.9 }
            switch entrance {
            case .plain: return 1.0
            case .showcase: return 2.5
            case .commander: return 3.1
            }
        case .leftBattlefield: return motion ? 0.95 : 0.9
        case .damageMarked: return 0.8
        case .countersAdded: return 0.7
        case .attackDeclared: return motion ? 0.7 : 0.6
        case .blockDeclared: return motion ? 0.8 : 0.6
        case .combatStrike: return motion ? 0.95 : 0.6
        case .lifeChanged: return motion ? 1.3 : 0.9
        }
    }
}

struct ActiveBoardFX: Equatable, Identifiable {
    let scheduled: ScheduledBoardFX
    let start: Date

    var id: Int { scheduled.id }
    var endDate: Date { start.addingTimeInterval(scheduled.end) }
}

/// Owns the previous FX state and the effects currently playing. The board view
/// stores one of these and feeds it every accepted snapshot transition.
struct BoardFXDirector: Equatable {
    private(set) var previous: BoardFXState?
    private(set) var active: [ActiveBoardFX] = []
    /// Card faces for flights, keyed by event subject. Departed cards come from the
    /// previous snapshot, so a flight can show a card that is no longer on the board.
    private(set) var subjects: [String: ZoneCard] = [:]
    /// Every commander name seen in a command zone this game.
    private(set) var commanderNames = Set<String>()
    private(set) var level = BoardFXLevel.full
    private var previousBattlefield: [String: ZoneCard] = [:]
    private var nextID = 0

    /// Returns only the newly scheduled effects, for haptics and accessibility.
    @discardableResult
    mutating func ingest(_ snapshot: GameSnapshot, level: BoardFXLevel, now: Date) -> [ScheduledBoardFX] {
        let state = BoardFXState(snapshot: snapshot)
        let battlefield = Dictionary(snapshot.players.flatMap(\.zones.battlefield).map { ($0.instanceId, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let departedFaces = previousBattlefield
        self.level = level
        defer { previous = state; previousBattlefield = battlefield }
        // Lenient: the overlay may start a batch late (first-frame clock) and prunes
        // precisely itself; this only drops effects that are surely finished.
        prune(now: now.addingTimeInterval(-BoardFXDirector.renderGrace))
        guard let previous, previous.gameID == state.gameID else {
            active = []
            subjects = [:]
            commanderNames = state.commandNames
            return []
        }
        commanderNames.formUnion(state.commandNames)
        let events = BoardEventDiffer.events(from: previous, to: state, commanders: commanderNames)
        // Let a showcase from an earlier snapshot finish before this batch plays.
        let showcaseEnd = active.filter(\.scheduled.isSequential)
            .map { $0.start.addingTimeInterval($0.scheduled.handoff) }.max()
        let hold = showcaseEnd.map { $0.timeIntervalSince(now) } ?? 0
        let scheduled = BoardFXScheduler.schedule(events, level: level, firstID: nextID, hold: hold)
        nextID += scheduled.count
        active += scheduled.map { ActiveBoardFX(scheduled: $0, start: now) }
        for fx in scheduled {
            switch fx.event {
            case let .enteredBattlefield(id, _, _, _, _): subjects[id] = battlefield[id]
            case let .leftBattlefield(id, _, _, _): subjects[id] = departedFaces[id]
            case let .combatStrike(id, _, _): subjects[id] = departedFaces[id] ?? battlefield[id]
            case let .spellCast(id, _, _, _, _):
                subjects[id] = snapshot.stackTopFirst.first { $0.id == id }?.displaySourceCard
            default: break
            }
        }
        return scheduled
    }

    static let renderGrace: TimeInterval = 2

    mutating func prune(now: Date) {
        active.removeAll { $0.endDate <= now }
        let live = Set(active.map(\.scheduled.event.subjectID))
        subjects = subjects.filter { live.contains($0.key) }
    }

    /// Per-card motion for the real board tiles: hide cards while a flight stands in
    /// for them, lunge new attackers, and hold attackers and blockers forward.
    func cardMotion(viewerID: String) -> BoardFXCardMotion {
        var motion = BoardFXCardMotion()
        guard level != .off else { return motion }
        for effect in active where effect.scheduled.usesMotion {
            let fx = effect.scheduled
            switch fx.event {
            case let .enteredBattlefield(id, _, _, _, _) where subjects[id] != nil:
                motion.hidden[id] = BoardFXCardMotion.Hidden(batch: effect.start, from: 0, until: fx.landing)
            case let .combatStrike(id, _, _) where subjects[id] != nil:
                motion.hidden[id] = BoardFXCardMotion.Hidden(batch: effect.start, from: fx.delay, until: fx.end)
            case let .attackDeclared(id, _):
                let owner = previous?.cards[id]?.playerID
                motion.lunges[id] = BoardFXCardMotion.Lunge(token: effect.id, direction: owner == viewerID ? -1 : 1)
            default: break
            }
        }
        for card in previous?.cards.values.sorted(by: { $0.id < $1.id }) ?? [] where card.zone == .battlefield {
            let direction: Double = card.playerID == viewerID ? -1 : 1
            if card.attacking {
                motion.stances[card.id] = .init(kind: .attacking, direction: direction, moves: level == .full)
            } else if !card.blocking.isEmpty {
                motion.stances[card.id] = .init(kind: .blocking, direction: direction, moves: level == .full)
            }
        }
        return motion
    }

    var latestEnd: Date? { active.map(\.endDate).max() }
}

struct BoardFXCardMotion: Equatable {
    struct Lunge: Equatable {
        let token: Int
        /// -1 moves up the screen (the viewer's creatures), +1 moves down.
        let direction: Double
    }

    /// A window, timed from the batch's first drawn frame (see BoardFXClock), in
    /// which a flight draws the card instead of its tile. `from` 0 hides at once.
    struct Hidden: Equatable {
        let batch: Date
        let from: TimeInterval
        let until: TimeInterval
    }

    /// Combat posture held for as long as the snapshot says so.
    struct Stance: Equatable {
        enum Kind: Equatable { case attacking, blocking }
        let kind: Kind
        let direction: Double
        /// Reduced level keeps the glow but not the offset.
        let moves: Bool
    }

    var hidden: [String: Hidden] = [:]
    var lunges: [String: Lunge] = [:]
    var stances: [String: Stance] = [:]
}
