import Foundation

/// The editor history validates and commits a candidate atomically. One Undo
/// reverses a whole replacement, commander promotion, or basic-land operation.
enum DeckStudioEditorOperations {
    static func replaceCard(in draft: inout NativeDeckDraft, rowID: UUID, name: String) throws {
        guard let index = draft.rows.firstIndex(where: { $0.id == rowID }) else { throw OnDeviceDeckEditing.Error.missingEntry }
        draft.rows[index].cardName = name
    }
    static func replacePrimaryCommander(in draft: inout NativeDeckDraft, name: String, keepOld: Bool) throws {
        let primary = draft.rows.firstIndex(where: { $0.isPrimaryCommander }) ?? draft.rows.firstIndex(where: {
            ["commander", "commanders"].contains($0.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        })
        if let primary, draft.rows[primary].cardName == name { return }
        if let primary {
            let old = draft.rows[primary]
            draft.rows[primary].cardName = name
            draft.rows[primary].quantity = 1
            draft.rows[primary].section = "commanders"
            draft.rows[primary].isPrimaryCommander = true
            if keepOld { draft.rows.append(.init(cardName: old.cardName, quantity: old.quantity, section: "maybeboard")) }
        } else { draft.rows.insert(.init(cardName: name, section: "commanders", isPrimaryCommander: true), at: 0) }
        // Explicit promotion moves one main-deck copy; partners and other boards stay intact.
        if let index = draft.rows.firstIndex(where: { !$0.isPrimaryCommander && $0.cardName == name && ["main", "deck"].contains($0.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
            if draft.rows[index].quantity == 1 { draft.rows.remove(at: index) }
            else { draft.rows[index].quantity -= 1 }
        }
    }
    static func setBasicLands(in draft: inout NativeDeckDraft, quantities: [String: Int]) throws {
        guard Set(quantities.keys) == Set(NativeDeckDraft.basicLandNames) else { throw OnDeviceDeckEditing.Error.invalidEntry }
        var candidate = draft
        for name in NativeDeckDraft.basicLandNames where quantities[name]! < candidate.basicLandCount(name) {
            try candidate.setBasicLandCount(name, quantity: quantities[name]!)
        }
        for name in NativeDeckDraft.basicLandNames { try candidate.setBasicLandCount(name, quantity: quantities[name]!) }
        draft = candidate
    }
}
