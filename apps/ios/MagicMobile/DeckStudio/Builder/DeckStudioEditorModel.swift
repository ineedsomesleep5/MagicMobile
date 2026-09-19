import Foundation
import Combine

/// One source of truth for draft, disk revision and undo/redo. Existing durable
/// local storage and recovery remain authoritative; no cloud writes occur here.
@MainActor
final class DeckStudioEditorModel: ObservableObject {
    @Published private(set) var history: DeckStudioEditHistory<NativeDeckDraft>
    @Published private(set) var record: DeckLibraryRecord?
    @Published private(set) var readOnly: Bool
    @Published private(set) var recovered = false
    @Published var error: String?
    private(set) var recoveryBlocked = false
    private var recoveryKey: String
    private let library: DeckLibraryStore
    private var sourceURL: String?
    private let defaults: UserDefaults

    init(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Bool = false, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.library = library; self.record = record; sourceURL = record?.sourceURL
        readOnly = included || record?.isCloudBacked == true
        history = DeckStudioEditHistory(record.map { NativeDeckDraft(deck: $0.deckList) } ?? NativeDeckDraft())
        recoveryKey = record.map { "\($0.id).\($0.revision)" } ?? "new"
        if !readOnly {
            do {
                if let saved = try NativeDeckDraftRecovery.load(key: recoveryKey, defaults: defaults) {
                    history.restore(saved); recovered = history.isDirty
                }
            } catch {
                recoveryBlocked = true
                self.error = "A recovery draft could not be read. It has been preserved; automatic recovery writes are paused. \(error.localizedDescription)"
            }
        }
    }
    var draft: NativeDeckDraft { history.value }
    var isDirty: Bool { history.isDirty }
    var canSave: Bool { !readOnly && (try? draft.deck()) != nil }
    var saveLabel: String {
        if readOnly { return "Included / read-only" }
        if recoveryBlocked { return "Recovery paused · original data preserved" }
        if error != nil && isDirty { return "Unsaved changes · check recovery error" }
        if recovered && isDirty { return "Recovered draft · unsaved" }
        if isDirty { return "Unsaved changes · recovery kept locally" }
        return record == nil ? "New local draft" : "Saved on this device"
    }
    @discardableResult func change(_ operation: (inout NativeDeckDraft) throws -> Void) -> Bool {
        guard !readOnly else { return false }
        do {
            try history.edit { value in
                try operation(&value)
                var checked = value; checked.name = "Draft"
                _ = try checked.deck()
            }
            persistRecovery()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func undo() { guard !readOnly else { return }; history.undo(); persistRecovery() }
    func redo() { guard !readOnly else { return }; history.redo(); persistRecovery() }
    /// Explicit discard never overwrites the saved record or unreadable recovery.
    func discardUnsavedChanges() {
        guard !readOnly else { return }
        history = DeckStudioEditHistory(history.baseline)
        recovered = false
        if !recoveryBlocked { NativeDeckDraftRecovery.clear(key: recoveryKey, defaults: defaults) }
        error = nil
    }
    func makeEditableCopy() {
        guard readOnly, let source = record else { return }
        do {
            let copy = try library.duplicateLocalDurably(source, name: draft.name + " — My copy")
            record = copy; readOnly = false; recoveryKey = "\(copy.id).\(copy.revision)"
            history = DeckStudioEditHistory(NativeDeckDraft(deck: copy.deckList))
            recovered = false; error = nil
            Task { [weak self] in
                do { try await DeckStudioOrganizationStore.shared.duplicate(from: source.id, to: copy.id) }
                catch {
                    guard let self, self.record?.id == copy.id else { return }
                    self.error = "The deck cards were copied, but their optional notes/tags could not be copied. The original details remain intact."
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func add(_ name: String, section: String = "deck") -> Bool {
        change { value in
            let effective = DeckStudioDraftPresentation.normalizedSection(section)
            if let index = value.rows.firstIndex(where: { $0.cardName == name && DeckStudioDraftPresentation.section($0) == effective }) {
                let (quantity, overflow) = value.rows[index].quantity.addingReportingOverflow(1)
                guard !overflow else { throw OnDeviceDeckEditing.Error.invalidEntry }
                value.rows[index].quantity = quantity
            }
            else { value.rows.append(NativeDeckRow(cardName: name, section: section)) }
        }
    }
    func cardCount(_ name: String, section: String? = nil) -> Int {
        let destination = section.map(DeckStudioDraftPresentation.normalizedSection)
        return draft.rows.filter { $0.cardName == name && (destination == nil || DeckStudioDraftPresentation.section($0) == destination) }.reduce(0) { $0 + $1.quantity }
    }
    func removeOne(_ name: String, section: String) {
        guard let row = draft.rows.last(where: { $0.cardName == name && DeckStudioDraftPresentation.section($0) == DeckStudioDraftPresentation.normalizedSection(section) }) else { return }
        quantity(id: row.id, delta: -1)
    }
    /// Advisory only: XMage remains responsible for exceptions and exact legality.
    func needsSingletonReview(_ name: String, metadata: NativeDeckMetadataCatalogue.Card?, destination: String) -> Bool {
        guard ["deck", "commanders"].contains(DeckStudioDraftPresentation.normalizedSection(destination)),
              cardCount(name, section: "deck") + cardCount(name, section: "commanders") > 0 else { return false }
        if metadata?.typeLine?.hasPrefix("Basic ") == true { return false }
        if metadata?.oracleText?.localizedCaseInsensitiveContains("A deck can have") == true { return false }
        return true
    }
    func quantity(id: UUID, delta: Int) {
        change { value in
            guard let index = value.rows.firstIndex(where: { $0.id == id }) else { throw OnDeviceDeckEditing.Error.missingEntry }
            let (next, overflow) = value.rows[index].quantity.addingReportingOverflow(delta)
            guard !overflow else { throw OnDeviceDeckEditing.Error.invalidEntry }
            if next <= 0 { value.rows.remove(at: index) } else { value.rows[index].quantity = next }
        }
    }
    func move(id: UUID, to section: String) {
        change { value in
            guard let index = value.rows.firstIndex(where: { $0.id == id }) else { throw OnDeviceDeckEditing.Error.missingEntry }
            value.rows[index].section = section; value.rows[index].isPrimaryCommander = false
        }
    }
    func remove(id: UUID) { change { $0.rows.removeAll { $0.id == id } } }
    func replace(rowID: UUID, name: String) -> Bool { change { try DeckStudioEditorOperations.replaceCard(in: &$0, rowID: rowID, name: name) } }
    func commander(_ name: String, keepOld: Bool) -> Bool { change { try DeckStudioEditorOperations.replacePrimaryCommander(in: &$0, name: name, keepOld: keepOld) } }
    func basics(_ values: [String: Int], expected: NativeDeckDraft) -> Bool {
        guard expected == draft else { error = "The draft changed. Reopen the land tool."; return false }
        return change { try DeckStudioEditorOperations.setBasicLands(in: &$0, quantities: values) }
    }
    /// A draft with non-playing boards produces a separate playable copy. It is
    /// never rewritten to satisfy the resolver; unsaved source changes are saved first.
    func preparePlayable(_ playing: DeckList, resolver: OnDeviceDeckResolver) -> String? {
        do {
            let projection = try DeckStudioPlayProjection(draft.deck())
            guard try projection.resolve(resolver) == resolver.resolve(playing) else { throw OnDeviceDeckEditing.Error.staleRevision }
            if projection.excluded.isEmpty {
                if readOnly, let record { return record.id.hasPrefix("precon:") ? record.id : "local:\(record.id)" }
                return save().map { "local:\($0.id)" }
            }
            if !readOnly, isDirty || record == nil { guard save() != nil else { return nil } }
            let copy = DeckList(name: String(playing.name.prefix(96)) + " — Playtest", commander: playing.commander, entries: playing.entries)
            let saved = try library.addLocalDurably(copy, sourceURL: sourceURL)
            return "local:\(saved.id)"
        } catch { self.error = error.localizedDescription; return nil }
    }
    @discardableResult func save() -> DeckLibraryRecord? {
        guard canSave else { return nil }
        do {
            let deck = try draft.deck()
            let saved: DeckLibraryRecord
            if let record { saved = try library.updateLocalDurably(deck, id: record.id, expectedRevision: record.revision) }
            else { saved = try library.addLocalDurably(deck, sourceURL: sourceURL) }
            if !recoveryBlocked { NativeDeckDraftRecovery.clear(key: recoveryKey, defaults: defaults) }
            record = saved; recoveryKey = "\(saved.id).\(saved.revision)"
            history.markSaved(); recovered = false; error = nil
            return saved
        } catch { self.error = error.localizedDescription; return nil }
    }
    @discardableResult func persistRecovery() -> Bool {
        guard !readOnly else { return true }
        guard !recoveryBlocked else { return false }
        do {
            if history.isDirty { try NativeDeckDraftRecovery.save(draft, key: recoveryKey, defaults: defaults) }
            else { NativeDeckDraftRecovery.clear(key: recoveryKey, defaults: defaults) }
            return true
        } catch { self.error = "Draft recovery could not be saved: \(error.localizedDescription)"; return false }
    }
}

enum DeckStudioDraftPresentation {
    static func normalizedSection(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "deck", "main": return "deck"
        case "commander", "commanders": return "commanders"
        case "companion", "companions": return "companions"
        default: return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
    static func section(_ row: NativeDeckRow) -> String { row.isPrimaryCommander ? "commanders" : normalizedSection(row.section) }
    static func commanders(_ draft: NativeDeckDraft) -> [String] { draft.rows.filter { section($0) == "commanders" }.map(\.cardName) }
    static func gameCount(_ draft: NativeDeckDraft) -> Int { draft.rows.filter { ["deck", "commanders"].contains(section($0)) }.reduce(0) { $0 + $1.quantity } }
    static func colors(_ draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?) -> [String]? {
        let commanders = commanders(draft)
        guard !commanders.isEmpty else { return nil }
        var union = Set<String>()
        for name in commanders {
            guard let colors = metadata?.card(named: name)?.colorIdentity else { return nil }
            union.formUnion(colors)
        }
        return ["W", "U", "B", "R", "G"].filter { union.contains($0) }
    }
}
