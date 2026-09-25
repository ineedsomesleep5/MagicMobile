import Foundation

/// What happened in one game, gathered from consecutive snapshots for the result screen.
/// Only public information is used: life totals, combat groups and zone contents.
struct GameStats: Equatable {
    private(set) var gameID = ""
    private(set) var turns = 0
    private(set) var startingLife: Int?
    private(set) var finalLife: Int?
    /// Combat damage your unblocked attackers dealt to players.
    private(set) var combatDamage = 0
    /// The largest combat hit you landed on one player at once.
    private(set) var biggestHit = 0
    private(set) var damageByCard: [String: Int] = [:]
    private(set) var creaturesDestroyed = 0
    private(set) var creaturesLost = 0
    private var previous: Capture?

    /// The lightweight part of a snapshot the next one is compared with.
    private struct Capture: Equatable {
        let life: [String: Int]
        let battlefieldCreatures: [String: Set<String>]
        let attacks: [Attack]
    }

    private struct Attack: Equatable {
        let defender: String
        let attackers: [(name: String, power: Int)]

        static func == (lhs: Attack, rhs: Attack) -> Bool {
            lhs.defender == rhs.defender && lhs.attackers.map(\.name) == rhs.attackers.map(\.name)
                && lhs.attackers.map(\.power) == rhs.attackers.map(\.power)
        }
    }

    mutating func record(_ snapshot: GameSnapshot) {
        if snapshot.id != gameID { self = GameStats(); gameID = snapshot.id }
        turns = max(turns, snapshot.turn)
        let viewer = snapshot.viewerID
        if let life = snapshot.human?.life {
            if startingLife == nil { startingLife = life }
            finalLife = life
        }
        let yourBattlefield = Set(snapshot.human?.zones.battlefield.map(\.instanceId) ?? [])
        let capture = Capture(
            life: Dictionary(snapshot.players.map { ($0.playerId, $0.life) }, uniquingKeysWith: { first, _ in first }),
            battlefieldCreatures: Dictionary(snapshot.players.map { player in
                (player.playerId, Set(player.zones.battlefield.filter(\.isCreature).map(\.instanceId)))
            }, uniquingKeysWith: { first, _ in first }),
            attacks: (snapshot.xmage?.combat ?? []).compactMap { group in
                guard !group.blocked, group.defenderId != viewer else { return nil }
                let mine = group.attackers.filter { yourBattlefield.contains($0.instanceId) }
                    .map { (name: $0.card.name, power: max(0, Int($0.displayPower ?? "") ?? $0.power ?? 0)) }
                    .filter { $0.power > 0 }
                return mine.isEmpty ? nil : Attack(defender: group.defenderId, attackers: mine)
            }
        )
        if let previous { compare(previous, capture, snapshot: snapshot) }
        previous = capture
    }

    private mutating func compare(_ old: Capture, _ new: Capture, snapshot: GameSnapshot) {
        // Credit a defender's life loss to the unblocked attackers that were swinging at them.
        for attack in old.attacks {
            guard let before = old.life[attack.defender], let after = new.life[attack.defender], after < before else { continue }
            let total = attack.attackers.reduce(0) { $0 + $1.power }
            let credited = min(total, before - after)
            guard total > 0, credited > 0 else { continue }
            combatDamage += credited
            biggestHit = max(biggestHit, credited)
            for attacker in attack.attackers {
                damageByCard[attacker.name, default: 0] += Int((Double(attacker.power) * Double(credited) / Double(total)).rounded())
            }
        }
        // A creature that left the battlefield for its owner's graveyard died (tokens just vanish).
        for player in snapshot.players {
            let gone = (old.battlefieldCreatures[player.playerId] ?? []).subtracting(new.battlefieldCreatures[player.playerId] ?? [])
            guard !gone.isEmpty else { continue }
            let graveyard = Set(player.zones.graveyard.map(\.instanceId))
            let died = gone.intersection(graveyard).count
            if snapshot.isViewer(player.playerId) { creaturesLost += died } else { creaturesDestroyed += died }
        }
    }

    /// The card of yours that dealt the most combat damage to players.
    var topCard: (name: String, damage: Int)? {
        damageByCard.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }
            .flatMap { $0.value > 0 ? ($0.key, $0.value) : nil }
    }

    static func == (lhs: GameStats, rhs: GameStats) -> Bool {
        lhs.gameID == rhs.gameID && lhs.turns == rhs.turns && lhs.combatDamage == rhs.combatDamage
            && lhs.finalLife == rhs.finalLife && lhs.creaturesLost == rhs.creaturesLost
            && lhs.creaturesDestroyed == rhs.creaturesDestroyed && lhs.damageByCard == rhs.damageByCard
    }
}
