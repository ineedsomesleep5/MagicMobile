import XCTest
@testable import MagicMobile

/// Actual application model and durable local store, isolated from the user's
/// library/preferences. Compiled by the app's SDK gate; execution needs Apple tests.
@MainActor
final class DeckStudioEditorModelTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "MagicMobile.DeckStudioTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func store() -> DeckLibraryStore { DeckLibraryStore(cacheURL: directory.appendingPathComponent("decks.json")) }
    private var deck: DeckList {
        DeckList(name: "My deck", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: 1, section: "deck")])
    }
    func testSaveReopenAndUndoPreserveStableRowAndDiskRevision() throws {
        let library = store(), saved = try library.addLocalDurably(deck)
        let model = DeckStudioEditorModel(library: library, record: saved, defaults: defaults)
        let id = try XCTUnwrap(model.draft.rows.first?.id)
        model.quantity(id: id, delta: 1)
        XCTAssertEqual(model.draft.rows.first?.id, id)
        XCTAssertEqual(model.draft.rows.first?.quantity, 2)
        model.undo(); XCTAssertEqual(model.draft.rows.first?.quantity, 1)
        model.redo(); XCTAssertEqual(model.draft.rows.first?.quantity, 2)
        let update = try XCTUnwrap(model.save())
        XCTAssertEqual(update.revision, saved.revision + 1)
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(store().decks.first?.entries.first?.quantity, 2)
    }
    func testAStaleEditorCannotOverwriteAnotherSave() throws {
        let library = store(), record = try library.addLocalDurably(deck)
        let first = DeckStudioEditorModel(library: library, record: record, defaults: defaults)
        let second = DeckStudioEditorModel(library: library, record: record, defaults: defaults)
        first.change { $0.name = "First writer" }
        XCTAssertNotNil(first.save())
        second.change { $0.name = "Stale writer" }
        XCTAssertNil(second.save())
        XCTAssertEqual(library.decks.first?.name, "First writer")
        XCTAssertNotNil(second.error)
    }
    func testReadOnlyDeckCopiesBeforeAnyEditing() throws {
        let library = store()
        let original = DeckLibraryRecord(deck: deck, id: "precon:example")
        let model = DeckStudioEditorModel(library: library, record: original, included: true, defaults: defaults)
        XCTAssertFalse(model.add("Plains")); XCTAssertTrue(library.decks.isEmpty)
        model.makeEditableCopy()
        XCTAssertFalse(model.readOnly)
        XCTAssertNotEqual(model.record?.id, original.id)
        XCTAssertEqual(library.decks.count, 1)
        XCTAssertTrue(model.add("Plains"))
        XCTAssertEqual(original.entries.count, 1)
    }
    func testCorruptRecoveryIsNotSilentlyOverwritten() throws {
        let library = store(), saved = try library.addLocalDurably(deck)
        let key = "deckStudio.draft.\(saved.id).\(saved.revision)"
        let bytes = Data("corrupt".utf8)
        defaults.set(bytes, forKey: key)
        let model = DeckStudioEditorModel(library: library, record: saved, defaults: defaults)
        XCTAssertTrue(model.recoveryBlocked)
        model.change { $0.name = "Unsaved edit" }
        XCTAssertFalse(model.persistRecovery())
        XCTAssertEqual(defaults.data(forKey: key), bytes)
    }
    func testFailedQuantityEditIsTransactional() throws {
        let library = store(), record = try library.addLocalDurably(deck)
        let model = DeckStudioEditorModel(library: library, record: record, defaults: defaults)
        let before = model.draft
        model.change { $0.rows[0].quantity = 2001 }
        XCTAssertEqual(model.draft, before)
        XCTAssertNotNil(model.error)
    }
    func testExplicitDiscardCanLeaveInvalidNameWithoutLosingSavedDeck() throws {
        let library = store(), record = try library.addLocalDurably(deck)
        let model = DeckStudioEditorModel(library: library, record: record, defaults: defaults)
        let baseline = model.draft
        model.change { $0.name = "" }
        XCTAssertTrue(model.isDirty)
        XCTAssertFalse(model.canSave)
        model.discardUnsavedChanges()
        XCTAssertEqual(model.draft, baseline)
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(library.decks.first?.name, "My deck")
        XCTAssertNil(defaults.data(forKey: "deckStudio.draft.\(record.id).\(record.revision)"))
    }
    func testDiscardPreservesUnreadableRecoveryAndUnrelatedDrafts() throws {
        let library = store(), record = try library.addLocalDurably(deck)
        let key = "deckStudio.draft.\(record.id).\(record.revision)"
        let corrupt = Data("preserve original".utf8)
        defaults.set(corrupt, forKey: key)
        defaults.set(corrupt, forKey: "deckStudio.draft.unrelated.1")
        let model = DeckStudioEditorModel(library: library, record: record, defaults: defaults)
        model.change { $0.name = "" }
        model.discardUnsavedChanges()
        XCTAssertFalse(model.isDirty)
        XCTAssertTrue(model.recoveryBlocked)
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
        XCTAssertEqual(defaults.data(forKey: "deckStudio.draft.unrelated.1"), corrupt)
    }
    func testQuantityOverflowIsRejectedWithoutChangingHistory() throws {
        let library = store(), record = try library.addLocalDurably(deck)
        let model = DeckStudioEditorModel(library: library, record: record, defaults: defaults)
        let before = model.draft, generation = model.history.generation
        model.quantity(id: before.rows[0].id, delta: Int.max)
        XCTAssertEqual(model.draft, before)
        XCTAssertEqual(model.history.generation, generation)
        XCTAssertNotNil(model.error)
    }
}
