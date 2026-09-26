import Foundation

/// "Group by Role" for the Cards list: automatic categories from the role
/// classifier. A card sits under every role it has, and your own role review
/// replaces the automatic hints for that card. Cards with no role are "Other".
enum DeckStudioRoleGroups {
    static let other = "Other"
    static var order: [String] { DeckStudioRole.allCases.map(\.title) + [other] }

    struct CardFacts {
        let text: String?
        let types: [String]?
        let curated: [DeckStudioRole]
    }

    /// Role group titles for each row, in `order`.
    static func membership(rows: [NativeDeckRow], card: (String) -> CardFacts?,
                           overrides: [String: Set<DeckStudioRole>]) -> [UUID: [String]] {
        var byName: [String: [String]] = [:]
        var result: [UUID: [String]] = [:]
        for row in rows {
            if byName[row.cardName] == nil {
                let facts = card(row.cardName)
                let roles = DeckStudioRoleClassifier.classify(text: facts?.text, types: facts?.types,
                                                              curated: facts?.curated ?? [], reviewed: overrides[row.cardName]).map(\.role)
                byName[row.cardName] = roles.isEmpty ? [other] : DeckStudioRole.allCases.filter { roles.contains($0) }.map(\.title)
            }
            result[row.id] = byName[row.cardName]
        }
        return result
    }

    static func membership(rows: [NativeDeckRow], metadata: NativeDeckMetadataCatalogue?,
                           overrides: [String: Set<DeckStudioRole>]) -> [UUID: [String]] {
        membership(rows: rows, card: { name in
            metadata?.card(named: name).map {
                CardFacts(text: $0.oracleText, types: $0.types, curated: $0.roles.compactMap(DeckStudioRole.init(rawValue:)))
            }
        }, overrides: overrides)
    }

    /// Group headers count unique cards, since one card can appear in several groups.
    static func uniqueCards(_ rows: [NativeDeckRow]) -> Int { Set(rows.map(\.cardName)).count }
}
