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
    }

    struct StackItem: Equatable {
        let id: String
        let name: String
        let controllerID: String?
        let tint: BoardFXTint
    }

    let gameID: String
    let lives: [String: Int]
    let cards: [String: Card]
    let stack: [StackItem]

    init(snapshot: GameSnapshot) {
        gameID = snapshot.id
        lives = Dictionary(snapshot.players.map { ($0.playerId, $0.life) }, uniquingKeysWith: { first, _ in first })
        var cards: [String: Card] = [:]
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
                        attacking: card.isAttacking == true)
                }
            }
        }
        self.cards = cards
        stack = snapshot.stackTopFirst.map { object in
            let tint = object.sourceCard.map { BoardFXTint(card: $0.card) } ?? .colorless
            return StackItem(id: object.id, name: object.displayName, controllerID: object.controllerId, tint: tint)
        }
    }
}

enum BoardFXEvent: Equatable {
    case spellCast(stackID: String, name: String, controllerID: String?, tint: BoardFXTint)
    case leftBattlefield(cardID: String, playerID: String, to: BoardFXZone?, tint: BoardFXTint)
    case damageMarked(cardID: String, amount: Int)
    case enteredBattlefield(cardID: String, playerID: String, from: BoardFXZone?, tint: BoardFXTint)
    case countersAdded(cardID: String, amount: Int)
    case attackDeclared(cardID: String, tint: BoardFXTint)
    case lifeChanged(playerID: String, delta: Int)

    /// Presentation order inside one snapshot transition.
    var order: Int {
        switch self {
        case .spellCast: return 0
        case .attackDeclared: return 1
        case .leftBattlefield: return 2
        case .damageMarked: return 3
        case .enteredBattlefield: return 4
        case .countersAdded: return 5
        case .lifeChanged: return 6
        }
    }

    /// Card, stack object or player the effect is about.
    var subjectID: String {
        switch self {
        case let .spellCast(id, _, _, _), let .leftBattlefield(id, _, _, _), let .damageMarked(id, _),
             let .enteredBattlefield(id, _, _, _), let .countersAdded(id, _), let .attackDeclared(id, _),
             let .lifeChanged(id, _):
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
    static func events(from old: BoardFXState, to new: BoardFXState) -> [BoardFXEvent] {
        // A new game, reconnect to another match or design preview swap is a cut, not a transition.
        guard old.gameID == new.gameID else { return [] }
        var events: [BoardFXEvent] = []

        let oldStackIDs = Set(old.stack.map(\.id))
        for item in new.stack where !oldStackIDs.contains(item.id) {
            events.append(.spellCast(stackID: item.id, name: item.name, controllerID: item.controllerID, tint: item.tint))
        }

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
            guard let previous = old.cards[card.id] else {
                events.append(.enteredBattlefield(cardID: card.id, playerID: card.playerID, from: nil, tint: card.tint))
                continue
            }
            if previous.zone != .battlefield {
                events.append(.enteredBattlefield(cardID: card.id, playerID: card.playerID, from: previous.zone, tint: card.tint))
                continue
            }
            if card.attacking && !previous.attacking {
                events.append(.attackDeclared(cardID: card.id, tint: card.tint))
            }
            if card.damage > previous.damage {
                events.append(.damageMarked(cardID: card.id, amount: card.damage - previous.damage))
            }
            if card.counters > previous.counters {
                events.append(.countersAdded(cardID: card.id, amount: card.counters - previous.counters))
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
}

enum BoardFXScheduler {
    /// Decorative effects per transition; board wipes collapse to the first few.
    static let decorativeLimit = 10
    static let stagger: TimeInterval = 0.07

    static func schedule(_ events: [BoardFXEvent], level: BoardFXLevel, firstID: Int = 0) -> [ScheduledBoardFX] {
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
        var groupStart: TimeInterval = 0
        var previousOrder: Int?
        var indexInGroup = 0
        for event in kept {
            if let previousOrder, previousOrder != event.order {
                groupStart = (result.map(\.delay).max() ?? 0) + (motion ? 0.16 : 0.06)
                indexInGroup = 0
            }
            previousOrder = event.order
            let delay = groupStart + Double(indexInGroup) * (motion ? stagger : 0.02)
            indexInGroup += 1
            result.append(ScheduledBoardFX(id: firstID + result.count, event: event, delay: delay,
                                           duration: duration(of: event, motion: motion), usesMotion: motion))
        }
        return result
    }

    /// Share of an arrival spent flying before the card lands (Full level only).
    static let arrivalFlightFraction = 0.42

    static func duration(of event: BoardFXEvent, motion: Bool) -> TimeInterval {
        let base: TimeInterval
        switch event {
        case .spellCast: base = 1.1
        case .leftBattlefield: base = 0.85
        case .damageMarked: base = 0.8
        case .enteredBattlefield: base = 1.0
        case .countersAdded: base = 0.7
        case .attackDeclared: base = 0.55
        case .lifeChanged: base = 1.2
        }
        return motion ? base : min(base, 0.9)
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
    private var previousBattlefield: [String: ZoneCard] = [:]
    private var nextID = 0

    /// Returns only the newly scheduled effects, for haptics and accessibility.
    @discardableResult
    mutating func ingest(_ snapshot: GameSnapshot, level: BoardFXLevel, now: Date) -> [ScheduledBoardFX] {
        let state = BoardFXState(snapshot: snapshot)
        let battlefield = Dictionary(snapshot.players.flatMap(\.zones.battlefield).map { ($0.instanceId, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let departedFaces = previousBattlefield
        defer { previous = state; previousBattlefield = battlefield }
        // Lenient: the overlay may start a batch late (first-frame clock) and prunes
        // precisely itself; this only drops effects that are surely finished.
        prune(now: now.addingTimeInterval(-BoardFXDirector.renderGrace))
        guard let previous, previous.gameID == state.gameID else {
            active = []
            subjects = [:]
            return []
        }
        let scheduled = BoardFXScheduler.schedule(BoardEventDiffer.events(from: previous, to: state), level: level, firstID: nextID)
        nextID += scheduled.count
        active += scheduled.map { ActiveBoardFX(scheduled: $0, start: now) }
        for fx in scheduled {
            switch fx.event {
            case let .enteredBattlefield(id, _, _, _): subjects[id] = battlefield[id]
            case let .leftBattlefield(id, _, _, _): subjects[id] = departedFaces[id]
            case let .spellCast(id, _, _, _):
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

    /// Per-card motion for the real board tiles: hide arriving cards until their
    /// flight lands, and lunge attackers toward the opponent.
    func cardMotion(viewerID: String) -> BoardFXCardMotion {
        var motion = BoardFXCardMotion()
        for effect in active where effect.scheduled.usesMotion {
            switch effect.scheduled.event {
            case let .enteredBattlefield(id, _, _, _) where subjects[id] != nil:
                let flight = effect.scheduled.duration * BoardFXScheduler.arrivalFlightFraction
                motion.arrivals[id] = BoardFXCardMotion.Arrival(batch: effect.start, landsAfter: effect.scheduled.delay + flight)
            case let .attackDeclared(id, _):
                let owner = previous?.cards[id]?.playerID
                motion.lunges[id] = BoardFXCardMotion.Lunge(token: effect.id, direction: owner == viewerID ? -1 : 1)
            default: break
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

    /// Timed from the tile's first frame after the batch, like the overlay, so a
    /// main-thread stall cannot reveal the tile before its flight lands.
    struct Arrival: Equatable {
        let batch: Date
        let landsAfter: TimeInterval
    }

    var arrivals: [String: Arrival] = [:]
    var lunges: [String: Lunge] = [:]
}
