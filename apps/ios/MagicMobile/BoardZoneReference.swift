import Foundation

/// Resolves membership from the current authorized snapshot, never a cached card list.
enum BoardZoneReference: Hashable {
    enum PlayerZone: String, CaseIterable {
        case library, hand, battlefield, graveyard, exile, command, stack
    }

    enum NamedKind: String, CaseIterable {
        case exile, companion, revealed, lookedAt

        fileprivate var title: String {
            self == .lookedAt ? "Looked at" : rawValue.capitalized
        }

        fileprivate func groups(in snapshot: GameSnapshot) -> [XmageNamedZone] {
            guard let xmage = snapshot.xmage else { return [] }
            switch self {
            case .exile: return xmage.exileZones
            case .companion: return xmage.companion
            case .revealed: return xmage.revealed
            case .lookedAt: return xmage.lookedAt
            }
        }
    }

    case player(playerID: String, zone: PlayerZone)
    case named(kind: NamedKind, id: String)
    case collection(NamedKind)

    func cards(in snapshot: GameSnapshot) -> [ZoneCard] {
        switch self {
        case let .player(playerID, zone):
            guard let zones = snapshot.players.first(where: { $0.playerId == playerID })?.zones else { return [] }
            switch zone {
            case .library: return zones.library
            case .hand: return zones.hand
            case .battlefield: return zones.battlefield
            case .graveyard: return zones.graveyard
            case .exile: return zones.exile
            case .command: return zones.command
            case .stack: return zones.stack
            }
        case let .named(kind, id):
            return kind.groups(in: snapshot).first { $0.id == id }?.cards ?? []
        case let .collection(kind):
            return kind.groups(in: snapshot).flatMap(\.cards)
        }
    }

    func title(in snapshot: GameSnapshot) -> String {
        switch self {
        case let .player(playerID, zone):
            let name = snapshot.players.first { $0.playerId == playerID }?.displayName
            let label = name.map { EngineDisplayText.label($0) } ?? ""
            let zoneTitle = zone.rawValue.capitalized + ([PlayerZone.hand, .library].contains(zone) ? " — visible cards" : "")
            return label.isEmpty ? zoneTitle : "\(label) · \(zoneTitle)"
        case let .named(kind, id):
            let name = kind.groups(in: snapshot).first { $0.id == id }?.name
            return name.map { EngineDisplayText.label($0, fallback: kind.title) } ?? kind.title
        case let .collection(kind):
            return kind.title
        }
    }

    static func namedReferences(in snapshot: GameSnapshot) -> [BoardZoneReference] {
        NamedKind.allCases.flatMap { kind in
            kind.groups(in: snapshot).map { .named(kind: kind, id: $0.id) }
        }
    }
}
