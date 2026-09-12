import Combine
import Foundation
import XCTest
@testable import MagicMobile

final class OnDeviceDeckPersistenceTests: XCTestCase {
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
