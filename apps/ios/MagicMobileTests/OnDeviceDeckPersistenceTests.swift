import Combine
import Foundation
import XCTest
@testable import MagicMobile

final class OnDeviceDeckPersistenceTests: XCTestCase {
    @MainActor
    func testUpdateAndDeleteAreDurableAndPreserveIdentityAndProvenance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("decks.json")
        let store = DeckLibraryStore(cacheURL: cache)
        let saved = try store.addLocalDurably(DeckList(name: "Draft", commander: nil, entries: []), sourceURL: "https://example.test/original")
        var edit = saved
        edit.name = "Renamed"; edit.entries = [DeckEntry(cardName: "Forest", quantity: 4, section: "custom")]
        // Callers cannot accidentally overwrite original provenance/format metadata.
        edit.sourceURL = nil; edit.format = "other"
        let updated = try store.updateLocalDurably(edit)
        XCTAssertEqual(updated.id, saved.id)
        XCTAssertEqual(updated.revision, saved.revision + 1)
        XCTAssertEqual(updated.sourceURL, saved.sourceURL)
        XCTAssertEqual(updated.format, saved.format)
        XCTAssertFalse(updated.isCloudBacked)
        XCTAssertGreaterThanOrEqual(updated.updatedAt, saved.updatedAt)
        XCTAssertEqual(DeckLibraryStore(cacheURL: cache).decks.first?.deckList, updated.deckList)
        XCTAssertThrowsError(try store.updateLocalDurably(edit))
        XCTAssertThrowsError(try store.deleteLocalDurably(id: saved.id, expectedRevision: saved.revision))
        try store.deleteLocalDurably(id: updated.id)
        XCTAssertTrue(DeckLibraryStore(cacheURL: cache).decks.isEmpty)
    }

    @MainActor
    func testCopyGetsFreshLocalIdentityAndDoesNotAlterSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeckLibraryStore(cacheURL: directory.appendingPathComponent("decks.json"))
        let source = DeckLibraryRecord(id: "bundled-or-cloud", name: "Original", commander: nil,
                                       entries: [DeckEntry(cardName: "Forest", quantity: 2, section: "sideboard")],
                                       sourceURL: "https://example.test/precon", revision: 7, isCloudBacked: true)
        let copy = try store.duplicateLocalDurably(source, name: "Editing copy")
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.revision, 1)
        XCTAssertEqual(copy.entries, source.entries)
        XCTAssertEqual(copy.sourceURL, source.sourceURL)
        XCTAssertFalse(copy.isCloudBacked)
        XCTAssertEqual(source.name, "Original")
        XCTAssertEqual(source.revision, 7)
    }

    @MainActor
    func testUpdateDeleteWriteFailuresDoNotPublishOrLoseSavedData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("decks.json")
        let backup = directory.appendingPathComponent("backup.json")
        let store = DeckLibraryStore(cacheURL: cache)
        let saved = try store.addLocalDurably(DeckList(name: "Original", commander: nil, entries: []))
        let bytes = try Data(contentsOf: cache)
        var edit = saved; edit.name = "Edited"
        var publications = 0
        let subscription = store.$decks.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        try FileManager.default.moveItem(at: cache, to: backup)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.updateLocalDurably(edit))
        XCTAssertThrowsError(try store.deleteLocalDurably(id: saved.id))
        XCTAssertEqual(store.decks, [saved])
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.moveItem(at: backup, to: cache)
        let updated = try store.updateLocalDurably(edit)
        XCTAssertEqual(updated.name, "Edited")
        XCTAssertEqual(publications, 1)
        try store.deleteLocalDurably(id: saved.id)
        XCTAssertEqual(publications, 2)
    }

    @MainActor
    func testCloudRecordsRequireCopyAndInvalidDraftCannotReplaceSavedDeck() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("decks.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cloud = DeckLibraryRecord(id: "cloud", name: "Cloud", commander: nil, entries: [], isCloudBacked: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode([cloud]); try bytes.write(to: cache)
        let store = DeckLibraryStore(cacheURL: cache)
        let loaded = try XCTUnwrap(store.decks.first)
        XCTAssertTrue(loaded.isCloudBacked)
        XCTAssertThrowsError(try store.updateLocalDurably(loaded))
        XCTAssertThrowsError(try store.deleteLocalDurably(id: loaded.id))
        XCTAssertEqual(try Data(contentsOf: cache), bytes)
        let copy = try store.duplicateLocalDurably(loaded, name: "Local")
        var invalid = copy; invalid.name = " "
        let before = try Data(contentsOf: cache)
        XCTAssertThrowsError(try store.updateLocalDurably(invalid))
        XCTAssertEqual(try Data(contentsOf: cache), before)
        XCTAssertEqual(store.decks.first, copy)
    }

    @MainActor
    func testUnreadableOrExternallyChangedCacheIsNeverReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appendingPathComponent("decks.json")
        let corrupt = Data("unreadable library".utf8)
        try corrupt.write(to: cache)
        let broken = DeckLibraryStore(cacheURL: cache)
        let input = DeckList(name: "Draft", commander: nil, entries: [])
        XCTAssertThrowsError(try broken.addLocalDurably(input))
        XCTAssertEqual(try Data(contentsOf: cache), corrupt)
        try FileManager.default.removeItem(at: cache)
        let first = DeckLibraryStore(cacheURL: cache)
        let second = DeckLibraryStore(cacheURL: cache)
        let record = try first.addLocalDurably(input)
        XCTAssertThrowsError(try second.addLocalDurably(input))
        XCTAssertEqual(DeckLibraryStore(cacheURL: cache).decks.first?.id, record.id)
    }

    @MainActor
    func testDurableAddRoundTripsEverySectionAndRetainsExistingDecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("library/decks.json")
        let store = DeckLibraryStore(cacheURL: cacheURL)
        let existing = DeckList(name: "Existing", commander: nil, entries: [])
        let existingRecord = try store.addLocalDurably(existing)
        let deck = DeckList(
            name: "All sections",
            commander: DeckEntry(cardName: "Tymna the Weaver", quantity: 1, section: "commander"),
            entries: [
                DeckEntry(cardName: "Thrasios, Triton Hero", quantity: 1, section: "commanders"),
                DeckEntry(cardName: "Zirda, the Dawnwaker", quantity: 1, section: "Companion"),
                DeckEntry(cardName: "Forest", quantity: 12, section: "deck"),
                DeckEntry(cardName: "Island", quantity: 3, section: "sideboard")
            ]
        )

        let saved = try store.addLocalDurably(deck)
        let reloaded = DeckLibraryStore(cacheURL: cacheURL)

        XCTAssertEqual(store.decks.map(\.id), [saved.id, existingRecord.id])
        XCTAssertEqual(reloaded.decks.map(\.id), [saved.id, existingRecord.id])
        XCTAssertEqual(reloaded.decks.map(\.deckList), [deck, existing])
        XCTAssertFalse(saved.isCloudBacked)
        XCTAssertEqual(saved.deckList, deck)
    }

    @MainActor
    func testWriteFailurePreservesPublishedDecksAndInputForRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("decks.json")
        let backupURL = directory.appendingPathComponent("backup.json")
        let store = DeckLibraryStore(cacheURL: cacheURL)
        let existing = DeckList(name: "Existing", commander: nil, entries: [])
        _ = try store.addLocalDurably(existing)
        let before = store.decks
        let input = DeckList(name: "Retry me", commander: nil, entries: [
            DeckEntry(cardName: "Forest", quantity: 12, section: "deck")
        ])
        let originalInput = input
        var publications = 0
        let subscription = store.$decks.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }

        // A directory at the destination allows directory creation but rejects the atomic file write.
        try FileManager.default.moveItem(at: cacheURL, to: backupURL)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try store.addLocalDurably(input))
        XCTAssertEqual(store.decks, before)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(input, originalInput)

        try FileManager.default.removeItem(at: cacheURL)
        try FileManager.default.moveItem(at: backupURL, to: cacheURL)
        XCTAssertEqual(DeckLibraryStore(cacheURL: cacheURL).decks.map(\.deckList), [existing])
        let saved = try store.addLocalDurably(input)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(DeckLibraryStore(cacheURL: cacheURL).decks.map(\.deckList), [input, existing])
        XCTAssertEqual(store.decks.first?.id, saved.id)
    }
}
