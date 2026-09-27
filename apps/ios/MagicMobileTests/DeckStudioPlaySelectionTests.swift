import Foundation
import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// "Play this deck": the play projection, stored XMage check results and the selection
/// flow, with a synthetic catalogue and a scripted validator. No engine runs here.
@MainActor
final class DeckStudioPlaySelectionTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeckChecks-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func resolver(upstream: String = "upstream", catalogue: String = "registry") throws -> OnDeviceDeckResolver {
        let cards = ["Emmara, Soul of the Accord", "Forest", "Sol Ring", "Island"].enumerated().map {
            ["name": $0.element, "setCode": "SET", "collectorNumber": String($0.offset + 1)]
        }
        return try OnDeviceDeckResolver(catalogueData: JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "upstreamCommit": upstream, "catalogueHash": catalogue,
            "sourceCatalogueSHA256": "source", "sourceRegistrySHA256": "report", "cards": cards
        ]))
    }

    private func store(_ name: String = "checks.json") -> DeckStudioReceiptStore {
        DeckStudioReceiptStore(url: directory.appendingPathComponent(name))
    }

    /// Main deck plus boards that never play. Plains and Swamp are not even in the
    /// catalogue: excluded boards must not stop the deck from resolving.
    private var deck: DeckList {
        DeckList(name: "Emmara Tokens", commander: DeckEntry(cardName: "Emmara, Soul of the Accord", quantity: 1, section: "commander"), entries: [
            DeckEntry(cardName: "Forest", quantity: 2, section: "deck"),
            DeckEntry(cardName: "Sol Ring", quantity: 1, section: "main"),
            DeckEntry(cardName: "Island", quantity: 3, section: "sideboard"),
            DeckEntry(cardName: "Plains", quantity: 1, section: "Maybeboard"),
            DeckEntry(cardName: "Swamp", quantity: 2, section: "considering")
        ])
    }

    private func receipt(for deck: DeckList, resolver: OnDeviceDeckResolver, valid: Bool, appBuild: String = "7",
                         issues: [DeckStudioValidationReceipt.Issue] = []) throws -> DeckStudioValidationReceipt {
        let request = try DeckStudioPlayProjection(deck).resolve(resolver).encoded()
        return DeckStudioValidationReceipt(request: request, upstream: resolver.upstreamCommit, catalogue: resolver.catalogueHash,
            appBuild: appBuild, checkedAt: Date(timeIntervalSince1970: 1_000), valid: valid, issues: issues,
            summary: valid ? "Passed" : "Deck failed the pinned XMage Commander validator")
    }

    private func check(_ deckID: String, _ deck: DeckList, _ resolver: OnDeviceDeckResolver, valid: Bool = true,
                       appBuild: String = "7") throws -> DeckStudioStoredCheck {
        let issues = valid ? [] : [DeckStudioValidationReceipt.Issue(index: 0, type: "OTHER", group: "Sol Ring", message: "Too many copies", cardName: "Sol Ring")]
        return DeckStudioStoredCheck(deckID: deckID, receipt: try receipt(for: deck, resolver: resolver, valid: valid, appBuild: appBuild, issues: issues))
    }

    private final class Calls { var validations: [MagicMobileOnDevice.JSONValue] = []; var selected: [String] = []; var prepared = 0 }

    private func selection(_ store: DeckStudioReceiptStore, _ resolver: OnDeviceDeckResolver, calls: Calls, live: Bool = false,
                           validator: @escaping (MagicMobileOnDevice.JSONValue) async throws -> DeckStudioValidationReceipt) -> DeckStudioPlaySelection {
        let value = DeckStudioPlaySelection(selectedDeckID: "precon:token-triumph", store: store, appBuild: "7") { request, _ in
            calls.validations.append(request)
            return try await validator(request)
        }
        value.resolver = resolver
        value.isGameLive = { live }
        value.onSelect = { calls.selected.append($0) }
        return value
    }

    // MARK: Projection

    func testPlayingDeckLeavesSideboardMaybeboardAndConsideringOutOfPlay() throws {
        let resolver = try resolver()
        let playing = DeckStudioPlaySelection.playingDeck(deck)
        XCTAssertEqual(playing.name, "Emmara Tokens")
        XCTAssertEqual(playing.commander?.cardName, "Emmara, Soul of the Accord")
        XCTAssertEqual(playing.entries.map(\.cardName), ["Forest", "Sol Ring"])
        XCTAssertThrowsError(try resolver.resolve(deck), "The saved deck keeps its boards; only the projection plays")
        XCTAssertNoThrow(try resolver.resolve(playing))
        // Other boards never change which check applies.
        let mainOnly = DeckList(name: deck.name, commander: deck.commander, entries: Array(deck.entries.prefix(2)))
        XCTAssertEqual(try DeckStudioPlaySelection.key(deckID: "local:a", deck: deck, resolver: resolver, appBuild: "7"),
                       try DeckStudioPlaySelection.key(deckID: "local:a", deck: mainOnly, resolver: resolver, appBuild: "7"))
        // A section the projection cannot place is left for the resolver to report at Start.
        let unknown = DeckList(name: "Odd", commander: nil, entries: [DeckEntry(cardName: "Forest", quantity: 1, section: "wishlist")])
        XCTAssertEqual(DeckStudioPlaySelection.playingDeck(unknown), unknown)
        XCTAssertEqual(DeckStudioPlaySelection.unplayableCards(deck, resolver: resolver), [])
    }

    // MARK: Stored check results

    func testStoredCheckMatchesOnlyTheSameDeckRequestEngineCatalogueAndBuild() throws {
        let resolver = try resolver(), store = store()
        let key = try DeckStudioPlaySelection.key(deckID: "local:a", deck: deck, resolver: resolver, appBuild: "7")
        XCTAssertEqual(store.status(for: key), .notChecked)
        XCTAssertEqual(store.status(for: nil), .notChecked)
        XCTAssertTrue(store.record(try check("local:a", deck, resolver)))
        XCTAssertEqual(store.status(for: key), .ready)

        let edited = DeckList(name: deck.name, commander: deck.commander,
                              entries: [DeckEntry(cardName: "Forest", quantity: 3, section: "deck")] + deck.entries.dropFirst())
        let misses = [
            try DeckStudioPlaySelection.key(deckID: "local:b", deck: deck, resolver: resolver, appBuild: "7"),
            try DeckStudioPlaySelection.key(deckID: "local:a", deck: edited, resolver: resolver, appBuild: "7"),
            try DeckStudioPlaySelection.key(deckID: "local:a", deck: deck, resolver: self.resolver(upstream: "newer"), appBuild: "7"),
            try DeckStudioPlaySelection.key(deckID: "local:a", deck: deck, resolver: self.resolver(catalogue: "other"), appBuild: "7"),
            try DeckStudioPlaySelection.key(deckID: "local:a", deck: deck, resolver: resolver, appBuild: "8")
        ]
        for miss in misses { XCTAssertEqual(store.status(for: miss), .notChecked, "\(miss)") }
        XCTAssertEqual(key.requestSHA256.count, 64)

        store.record(try check("local:c", deck, resolver, valid: false))
        XCTAssertEqual(store.status(for: try DeckStudioPlaySelection.key(deckID: "local:c", deck: deck, resolver: resolver, appBuild: "7")), .needsFixes)
    }

    func testStoreKeepsTheNewest200AndPersists() throws {
        let resolver = try resolver(), store = store()
        for index in 0..<205 { store.record(try check("local:\(index)", deck, resolver)) }
        XCTAssertEqual(DeckStudioReceiptStore.maximumResults, 200)
        XCTAssertEqual(store.checks.count, 200)
        XCTAssertEqual(store.checks.first?.key.deckID, "local:204")
        XCTAssertEqual(store.checks.last?.key.deckID, "local:5")
        XCTAssertFalse(store.checks.contains { $0.key.deckID == "local:4" })
        // Recording the same key again replaces it instead of adding a duplicate.
        store.record(try check("local:100", deck, resolver, valid: false))
        XCTAssertEqual(store.checks.count, 200)
        XCTAssertEqual(store.checks.first?.valid, false)

        let reopened = self.store()
        XCTAssertEqual(reopened.checks, store.checks)
        reopened.forget(deckID: "local:100")
        XCTAssertEqual(self.store().checks.count, 199)
    }

    func testANewInstallInvalidatesOlderResultsAndCorruptFilesAreACacheMiss() throws {
        let resolver = try resolver(), store = store()
        store.record(try check("local:a", deck, resolver))
        store.record(try check("local:b", deck, resolver))
        store.record(try check("local:a", deck, resolver, appBuild: "8"))
        XCTAssertEqual(store.checks.map(\.key.appBuild), ["8"], "Results from the previous build can never match again")
        XCTAssertEqual(store.status(for: try DeckStudioPlaySelection.key(deckID: "local:b", deck: deck, resolver: resolver, appBuild: "7")), .notChecked)

        try Data("not json".utf8).write(to: directory.appendingPathComponent("checks.json"))
        XCTAssertEqual(self.store().checks, [])
    }

    func testStoredCheckGroupsIssuesAndRebuildsItsReceiptOnlyForItsRequest() throws {
        let resolver = try resolver()
        let issues = [
            DeckStudioValidationReceipt.Issue(index: 0, type: "DECK_SIZE", group: "Deck", message: "Must contain 100 cards", cardName: nil),
            DeckStudioValidationReceipt.Issue(index: 1, type: "OTHER", group: "Sol Ring", message: "Too many copies", cardName: "Sol Ring"),
            DeckStudioValidationReceipt.Issue(index: 2, type: "PRIMARY", group: nil, message: "Commander is missing", cardName: " "),
            DeckStudioValidationReceipt.Issue(index: 3, type: "OTHER", group: "Deck", message: "Too few lands", cardName: "Sol Ring")
        ]
        let failed = try receipt(for: deck, resolver: resolver, valid: false, issues: issues)
        let stored = DeckStudioStoredCheck(deckID: "local:a", receipt: failed)
        XCTAssertEqual(stored.issueCount, 4)
        XCTAssertEqual(stored.groups.map(\.title), ["Deck", "Sol Ring", "Primary"])
        XCTAssertEqual(stored.groups.first?.issues.count, 2)
        XCTAssertEqual(stored.cardNames, ["Sol Ring"])
        XCTAssertEqual(stored.receipt(request: failed.request), failed)
        XCTAssertNil(stored.receipt(request: Data("{}".utf8)))
    }

    // MARK: Flow

    func testAStoredPassSelectsTheSourceDeckWithoutRunningXMage() throws {
        let resolver = try resolver(), store = store(), calls = Calls()
        store.record(try check("local:a", deck, resolver))
        let play = selection(store, resolver, calls: calls) { _ in XCTFail("No check needed"); throw CancellationError() }
        XCTAssertFalse(play.isPlaying(deckID: "local:a", deck: deck))
        XCTAssertNil(play.play(name: "Emmara Tokens") { calls.prepared += 1; return .init(deckID: "local:a", deck: self.deck) })
        XCTAssertEqual(calls.prepared, 1)
        XCTAssertTrue(calls.validations.isEmpty)
        XCTAssertEqual(play.selectedDeckID, "local:a")
        XCTAssertEqual(calls.selected, ["local:a"])
        XCTAssertEqual(play.outcome, .nowPlaying(deckID: "local:a", name: "Emmara Tokens", excludedCards: 6))
        XCTAssertTrue(play.isPlaying(deckID: "local:a", deck: deck))
        XCTAssertEqual(DeckStudioPlayText.excluded(6), "Sideboard and maybeboard stay out of play (6 cards).")
    }

    func testADirtyDraftIsSavedThenCheckedAndTheSavedSourceDeckIsSelected() async throws {
        let resolver = try resolver(), store = store(), calls = Calls()
        let play = selection(store, resolver, calls: calls) { _ in try self.receipt(for: self.deck, resolver: resolver, valid: true) }
        var saved = false
        let task = play.play(name: "Emmara Tokens") {
            // Stands in for DeckStudioEditorModel.preparePlayable: save, then the source id.
            saved = true; return .init(deckID: "local:new", deck: self.deck)
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(play.outcome, .checking(deckID: "local:new", name: "Emmara Tokens"))
        XCTAssertTrue(play.isChecking)
        XCTAssertEqual(DeckStudioPlayText.checking("Emmara Tokens"), "XMage is checking Emmara Tokens against the Commander rules on this device.")
        await task?.value
        XCTAssertEqual(calls.validations, [try resolver.resolve(DeckStudioPlaySelection.playingDeck(deck))])
        XCTAssertEqual(play.selectedDeckID, "local:new", "The source deck plays; no copy is made")
        XCTAssertEqual(calls.selected, ["local:new"])
        XCTAssertEqual(play.outcome, .nowPlaying(deckID: "local:new", name: "Emmara Tokens", excludedCards: 6))
        XCTAssertEqual(play.status(deckID: "local:new", deck: deck), .ready)
        XCTAssertEqual(self.store().status(for: play.key(deckID: "local:new", deck: deck)), .ready, "The result is stored on disk")
    }

    func testAFailedCheckIsStoredAndBlocksPlayWithoutChangingTheSelection() async throws {
        let resolver = try resolver(), store = store(), calls = Calls()
        let failed = try check("local:a", deck, resolver, valid: false)
        let play = selection(store, resolver, calls: calls) { _ in
            try self.receipt(for: self.deck, resolver: resolver, valid: false, issues: failed.issues.map {
                .init(index: $0.index, type: $0.type, group: $0.group, message: $0.message, cardName: $0.cardName)
            })
        }
        await play.play(name: "Emmara Tokens") { .init(deckID: "local:a", deck: self.deck) }?.value
        guard case .blocked(let deckID, _, let stored)? = play.outcome else { return XCTFail("\(String(describing: play.outcome))") }
        XCTAssertEqual(deckID, "local:a")
        XCTAssertEqual(stored.cardNames, ["Sol Ring"])
        XCTAssertEqual(DeckStudioPlayText.blocked(stored.issueCount), "1 rule issue blocks play")
        XCTAssertEqual(play.selectedDeckID, "precon:token-triumph")
        XCTAssertTrue(calls.selected.isEmpty)
        XCTAssertEqual(play.status(deckID: "local:a", deck: deck), .needsFixes)
        // The same cards on the same install get the same answer: shown again, not rechecked.
        play.dismiss()
        XCTAssertNil(play.play(name: "Emmara Tokens") { .init(deckID: "local:a", deck: self.deck) })
        XCTAssertEqual(calls.validations.count, 1)
        guard case .blocked? = play.outcome else { return XCTFail("Expected the stored failure") }
    }

    func testALiveGameStopsBeforeSavingOrChecking() throws {
        let resolver = try resolver(), calls = Calls()
        let play = selection(store(), resolver, calls: calls, live: true) { _ in XCTFail("No check while a game is live"); throw CancellationError() }
        XCTAssertNil(play.play(name: "Emmara Tokens") { calls.prepared += 1; return .init(deckID: "local:a", deck: self.deck) })
        XCTAssertEqual(play.outcome, .gameLive)
        XCTAssertEqual(calls.prepared, 0, "A dirty draft is not saved when play is refused")
        XCTAssertTrue(calls.validations.isEmpty)
        XCTAssertEqual(play.selectedDeckID, "precon:token-triumph")
        XCTAssertEqual(DeckStudioPlayText.gameLive, "Leave your current game to change decks.")
    }

    func testDecksThatCannotResolveOrSaveExplainWhyAndNameTheCards() throws {
        let resolver = try resolver(), calls = Calls()
        let play = selection(store(), resolver, calls: calls) { _ in XCTFail("Resolve first"); throw CancellationError() }
        let broken = DeckList(name: "Broken", commander: deck.commander,
                              entries: deck.entries + [DeckEntry(cardName: "Mystery Card", quantity: 1, section: "deck")])
        play.play(name: "Broken") { .init(deckID: "local:b", deck: broken) }
        guard case .cannotPlay(let deckID, let name, let message, let cards)? = play.outcome else { return XCTFail("\(String(describing: play.outcome))") }
        XCTAssertEqual(deckID, "local:b"); XCTAssertEqual(name, "Broken")
        XCTAssertTrue(message.contains("Mystery Card"), message)
        XCTAssertEqual(cards, ["Mystery Card"])
        XCTAssertTrue(calls.validations.isEmpty)

        play.dismiss()
        play.play(name: "Unsaved") { throw OnDeviceDeckResolver.ResolutionError("Name this deck before saving.") }
        XCTAssertEqual(play.outcome, .cannotPlay(deckID: nil, name: "Unsaved", message: "Name this deck before saving.", cards: []))
        XCTAssertEqual(play.selectedDeckID, "precon:token-triumph")
    }

    func testEngineErrorsAreShownAndCancelKeepsTheSelection() async throws {
        let resolver = try resolver(), store = store(), calls = Calls()
        let failing = selection(store, resolver, calls: calls) { _ in throw EngineError.invalidMessage("The rules engine is still closing.") }
        await failing.play(name: "Emmara Tokens") { .init(deckID: "local:a", deck: self.deck) }?.value
        XCTAssertEqual(failing.outcome, .cannotPlay(deckID: "local:a", name: "Emmara Tokens", message: "The rules engine is still closing.", cards: []))
        XCTAssertTrue(store.checks.isEmpty, "An engine error is not a check result")

        let slow = selection(store, resolver, calls: calls) { _ in
            try await Task.sleep(for: .seconds(30))
            return try self.receipt(for: self.deck, resolver: resolver, valid: true)
        }
        let task = slow.play(name: "Emmara Tokens") { .init(deckID: "local:a", deck: self.deck) }
        XCTAssertTrue(slow.isChecking)
        slow.cancel()
        await task?.value
        XCTAssertNil(slow.outcome)
        XCTAssertEqual(slow.selectedDeckID, "precon:token-triumph")
        XCTAssertTrue(store.checks.isEmpty)
    }

    func testAnUnreadableDeckNeedsFixesAndPlayWaitsForTheCatalogue() throws {
        let resolver = try resolver(), calls = Calls()
        let play = selection(store(), resolver, calls: calls) { _ in XCTFail("Resolve first"); throw CancellationError() }
        let broken = DeckList(name: "Broken", commander: deck.commander, entries: [DeckEntry(cardName: "Mystery Card", quantity: 1, section: "deck")])
        XCTAssertEqual(play.status(deckID: "local:b", deck: broken), .needsFixes, "A deck the resolver cannot read needs fixes")
        XCTAssertEqual(play.status(deckID: "local:a", deck: deck), .notChecked)
        play.resolver = nil
        XCTAssertEqual(play.status(deckID: "local:b", deck: broken), .notChecked, "Nothing is judged before the catalogue loads")
        XCTAssertNil(play.play(name: "Broken") { calls.prepared += 1; return .init(deckID: "local:b", deck: broken) })
        XCTAssertEqual(play.outcome, .cannotPlay(deckID: nil, name: "Broken", message: DeckStudioPlayText.catalogueLoading, cards: []))
        XCTAssertEqual(calls.prepared, 0, "A draft is not saved while the catalogue is still loading")
    }

    func testFixRequestsWaitForTheirDeck() {
        let play = DeckStudioPlaySelection(store: store(), appBuild: "7")
        play.requestFix(deckID: "local:a", cards: ["Sol Ring"])
        XCTAssertNil(play.takeFix(for: "local:b"))
        XCTAssertNil(play.takeFix(for: nil))
        XCTAssertEqual(play.takeFix(for: "local:a"), ["Sol Ring"])
        XCTAssertNil(play.takeFix(for: "local:a"))
    }

    // MARK: Start rejected by XMage

    func testAnInvalidDeckAtStartIsStoredForThePlayersDeckOnly() throws {
        let resolver = try resolver(), store = store()
        func rejection(card: String) -> Error {
            EngineError.rejectionDetails(code: "invalid_deck", message: "Deck failed the pinned XMage Commander validator", details: .object([
                "validator": .string("Commander"),
                "issues": .array([.object(["type": .string("OTHER"), "group": .string(card), "message": .string("Too many copies"), "cardName": .string(card)])])
            ]))
        }
        XCTAssertNil(DeckStudioStartRejection(EngineError.rejected(code: "unknown_printing", message: "No printing")))
        XCTAssertNil(DeckStudioStartRejection(CancellationError()))
        let playing = DeckStudioPlaySelection.playingDeck(deck)
        let value = try XCTUnwrap(DeckStudioStartRejection(rejection(card: "Sol Ring")))
        let stored = try XCTUnwrap(value.check(deckID: "local:a", deck: playing, resolver: resolver, appBuild: "7", store: store))
        XCTAssertFalse(stored.valid)
        XCTAssertEqual(stored.key, try DeckStudioPlaySelection.key(deckID: "local:a", deck: deck, resolver: resolver, appBuild: "7"),
                       "Start stores under the same key Deck Studio reads")
        // An issue naming a card outside this deck came from another seat's deck.
        let other = try XCTUnwrap(DeckStudioStartRejection(rejection(card: "Grave Titan")))
        XCTAssertNil(other.check(deckID: "local:a", deck: playing, resolver: resolver, appBuild: "7", store: store))
        // A deck that already passed this exact check was not the one XMage rejected.
        store.record(try check("local:a", deck, resolver))
        XCTAssertNil(value.check(deckID: "local:a", deck: playing, resolver: resolver, appBuild: "7", store: store))
    }

    // MARK: Wording shared with Android

    func testSharedWording() {
        XCTAssertEqual(DeckStudioPlayText.play, "Play this deck")
        XCTAssertEqual(DeckStudioPlayText.saveAndPlay, "Save & play")
        XCTAssertEqual(DeckStudioPlayText.playing, "Playing")
        XCTAssertEqual(DeckStudioPlayText.playingAccessibility, "This is your playing deck")
        XCTAssertEqual([DeckStudioPlayStatus.ready, .needsFixes, .notChecked].map(\.label), ["Ready", "Needs fixes", "Not checked"])
        XCTAssertEqual([DeckStudioPlayStatus.ready, .notChecked, .needsFixes].map(\.setupLine),
                       ["Ready · checked on this device", "Not checked — Start will check it", "Needs fixes · Fix in Deck Studio"])
        XCTAssertEqual([DeckStudioPlayText.fixDeck, DeckStudioPlayText.notNow, DeckStudioPlayText.setUpGame], ["Fix deck", "Not now", "Set up game"])
        XCTAssertEqual(DeckStudioPlayText.cannotPlayTitle, "Can't play this deck yet")
        XCTAssertEqual(DeckStudioPlayText.checkingTitle, "Checking your deck")
        XCTAssertEqual(DeckStudioPlayText.nowPlaying("Emmara Tokens"), "Now playing Emmara Tokens")
        XCTAssertEqual(DeckStudioPlayText.nowPlayingStrip("Emmara Tokens", .ready), "Now playing: Emmara Tokens · Ready")
        XCTAssertEqual(DeckStudioPlayText.blocked(3), "3 rule issues block play")
        XCTAssertEqual(DeckStudioPlayText.issueCount(1), "1 issue")
        XCTAssertEqual(DeckStudioPlayText.issueCount(2), "2 issues")
        XCTAssertEqual(DeckStudioPlayText.excluded(1), "Sideboard and maybeboard stay out of play (1 card).")
        XCTAssertEqual(DeckStudioPlayText.deletePlaying("Token Triumph"), "This is your playing deck. Token Triumph will be selected instead.")
    }
}
