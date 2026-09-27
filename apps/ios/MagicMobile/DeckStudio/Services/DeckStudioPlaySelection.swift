import Foundation
import Combine
import MagicMobileOnDevice

/// Deck Studio's player-facing wording for Play and the builder: one source on iOS.
/// Android's DeckStudioPlayText (core) holds the same strings, and both platforms'
/// parity tests read them from apps/android/core/src/test/resources/parity/deck-studio-cases.json.
enum DeckStudioPlayText {
    // Play
    static let play = "Play this deck"
    static let saveAndPlay = "Save & play"
    static let playing = "Playing"
    static let playingAccessibility = "This is your playing deck"
    static let ready = "Ready"
    static let needsFixes = "Needs fixes"
    static let notChecked = "Not checked"
    static let fixDeck = "Fix deck"
    static let notNow = "Not now"
    static let setUpGame = "Set up game"
    static let cannotPlayTitle = "Can't play this deck yet"
    static let checkingTitle = "Checking your deck"
    static let checkingProgress = "Checking Commander rules…"
    static let gameLive = "Leave your current game to change decks."
    static let catalogueLoading = "The local card catalogue is still loading."
    static let setupReady = "Ready · checked on this device"
    static let setupNotChecked = "Not checked — Start will check it"
    static let setupNeedsFixes = "Needs fixes · Fix in Deck Studio"
    static let panelCaption = "Check the Commander rules on this device, then play this deck."
    static let showAll = "Show all"
    /// A stored pass from a game XMage created.
    static let startPassed = "Passed the installed XMage Commander validator"
    // Card actions (long-press on a row or tile)
    static let cardDetails = "Card details"
    static let addOne = "Add one"
    static let removeOne = "Remove one"
    static let replaceCard = "Replace card"
    static let moveTo = "Move to…"
    static let removeRow = "Remove row"
    /// Move to… destinations: board and title. "considering" counts as maybeboard.
    static let destinations: [(section: String, title: String)] = [
        ("deck", "Main deck"), ("commanders", "Commanders"), ("companions", "Companions"),
        ("sideboard", "Sideboard"), ("maybeboard", "Maybeboard")
    ]
    // Select mode
    static let select = "Select"
    static let selectCards = "Select cards"
    static let doneSelecting = "Done selecting"
    static let selectAll = "Select all"
    static let setQuantity = "Set quantity"
    static let remove = "Remove"
    static let removeSelectedTitle = "Remove the selected cards?"
    static let removeSelectedMessage = "Undo brings them back."
    static let quantityMessage = "Every selected card gets this quantity, from 1 to 2,000."
    static let quantityError = "Use a quantity from 1 to 2,000. Nothing was changed."
    static let showAsGrid = "Show as grid"
    static let showAsList = "Show as list"
    // Quick Add
    static let quickAdd = "Quick add"
    static let quickAddMain = "Main"
    static let quickAddMaybe = "Maybe"
    static let quickAddMaybeboard = "Add to maybeboard"
    static let addCards = "Add cards"
    static let quickAddHint = "Type a card name, or a count first, like 2x Sol Ring. Return adds the top match."
    static let quickAddNeedsName = "Type a card name, like 2x Sol Ring."
    static let quickAddFailed = "Could not add this card. Check the draft's size limits."
    static let undo = "Undo"
    // Edit as text
    static let editAsText = "Edit as text"
    static let copyList = "Copy list"
    static let listCopied = "List copied"
    static let reviewChanges = "Review changes"
    static let applyChanges = "Apply changes"
    static let keepEditing = "Keep editing"
    static let diffAdded = "Added"
    static let diffRemoved = "Removed"
    static let noChanges = "No changes to apply."
    static let textEditorHint = "One card per line, like 1 Sol Ring, under Commander, Deck, Companion, Sideboard or Maybeboard headings."
    // Commander-first new decks
    static let chooseCommander = "Choose a commander"
    static let skip = "Skip"
    static let commanderFirstTitle = "Start with your commander"
    static let commanderFirstCaption = "Legendary creatures and cards that say they can be your commander. The deck takes its name until you rename it."
    static let searchCommanders = "Search commanders"
    // Search
    static let searchHint = "Filters work too: t:creature, o:draw, mv<=3, id:wu"
    static let withinIdentity = "Within commander color identity"
    // Sample hand
    static let sampleHand = "Sample hand"
    static let sampleHandCaption = "Draw seven from your main deck. Commanders stay in the command zone, and sideboard and maybeboard cards stay out."
    static let sampleHandEmpty = "Add main-deck cards to draw a sample hand."
    static let draw7 = "Draw 7"
    static let newHand = "New hand"
    static let mulligan = "Mulligan"
    static let draw = "Draw"

    static func checking(_ name: String) -> String { "XMage is checking \(name) against the Commander rules on this device." }
    static func nowPlaying(_ name: String) -> String { "Now playing \(name)" }
    static func nowPlayingStrip(_ name: String, _ status: DeckStudioPlayStatus) -> String { "Now playing: \(name) · \(status.label)" }
    static func issueCount(_ count: Int) -> String { count == 1 ? "1 issue" : "\(count) issues" }
    static func blocked(_ count: Int) -> String { count == 1 ? "1 rule issue blocks play" : "\(count) rule issues block play" }
    static func notShown(_ count: Int) -> String { "\(issueCount(count)) not shown" }
    static func excluded(_ cards: Int) -> String { "Sideboard and maybeboard stay out of play (\(CardCountText.label(cards)))." }
    static func deletePlaying(_ fallback: String) -> String { "This is your playing deck. \(fallback) will be selected instead." }
    static func showingOnly(_ label: String) -> String { "Showing only: \(label)" }
    static func selected(_ count: Int) -> String { "\(count) selected" }
    static func added(_ quantity: Int, _ name: String, maybeboard: Bool) -> String {
        "Added \(quantity) × \(name)" + (maybeboard ? " to maybeboard" : "")
    }
    static func noCardNamed(_ name: String) -> String { "No card named \u{201C}\(name)\u{201D} in this app\u{2019}s catalogue." }
    static func handCounts(hand: Int, library: Int) -> String {
        "\(CardCountText.label(hand)) in hand · \(CardCountText.label(library)) in library"
    }
}

/// The rules Play shares on every screen. Android's DeckStudioPlayRules (core) follows
/// the same rules, and deck-studio-cases.json pins them on both platforms.
enum DeckStudioPlayRules {
    /// Rows the offline resolver cannot play: unknown names and sections, and cards
    /// split between playing sections. Sideboard, maybeboard and considering rows stay out.
    static func unplayableCards(_ deck: DeckList, canonical: (String) -> String?) -> [String] {
        let playing: Set<String> = ["main", "deck", "commander", "commanders", "companion", "companions"]
        let excluded: Set<String> = ["sideboard", "maybeboard", "considering"]
        let rows = [deck.commander.map { DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "commanders") }].compactMap { $0 } + deck.entries
        var cards: [String] = []
        func note(_ name: String) { if !cards.contains(name) { cards.append(name) } }
        var sections: [String: Set<String>] = [:]
        for row in rows {
            let section = row.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if excluded.contains(section) { continue }
            guard playing.contains(section), let name = canonical(row.cardName) else { note(row.cardName); continue }
            sections[name, default: []].insert(DeckStudioBoard.normalized(section))
        }
        for row in rows where sections[canonical(row.cardName) ?? ""].map({ $0.count > 1 }) == true { note(row.cardName) }
        return cards
    }

    /// Whether Start's answer is stored for the player's deck. A pass always is. A
    /// rejection is not when this exact deck already passed, or when an issue names a
    /// card outside the player's deck (it came from another seat's deck).
    static func storesStartResult(valid: Bool, issueCards: [String], deckCards: [String], alreadyPassed: Bool) -> Bool {
        if valid { return true }
        if alreadyPassed { return false }
        let names = Set(deckCards.map(key))
        return issueCards.allSatisfy { names.contains(key($0)) }
    }

    /// Fix deck: the rows XMage named, matched by canonical name and ignoring case.
    /// Sideboard and maybeboard rows are out of play, so they never match.
    static func fixRows(_ rows: [NativeDeckRow], cards: [String], canonical: (String) -> String?) -> Set<UUID> {
        func name(_ value: String) -> String { key(canonical(value) ?? value) }
        let wanted = Set(cards.map(name))
        return Set(rows.filter { !["sideboard", "maybeboard"].contains(DeckStudioBoard.of($0)) && wanted.contains(name($0.cardName)) }.map(\.id))
    }

    private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

/// One flow for "Play this deck" from a library tile, the workspace header and the
/// validation panel: save a dirty draft, resolve the playing cards offline, reuse a
/// matching stored XMage check or run one, then select the source deck (never a copy).
@MainActor
final class DeckStudioPlaySelection: ObservableObject {
    enum Outcome: Equatable {
        case gameLive
        case cannotPlay(deckID: String?, name: String, message: String, cards: [String])
        case checking(deckID: String, name: String)
        case blocked(deckID: String, name: String, check: DeckStudioStoredCheck)
        case nowPlaying(deckID: String, name: String, excludedCards: Int)

        var presentsSheet: Bool {
            switch self {
            case .cannotPlay, .checking, .blocked: return true
            case .gameLive, .nowPlaying: return false
            }
        }
    }
    /// A saved deck ready to play: its selection id and its saved cards.
    struct Prepared: Equatable {
        let deckID: String
        let deck: DeckList
    }
    struct FixRequest: Equatable {
        let deckID: String
        let cards: [String]
    }
    typealias Validator = @MainActor (MagicMobileOnDevice.JSONValue, OnDeviceDeckResolver) async throws -> DeckStudioValidationReceipt

    @Published private(set) var outcome: Outcome?
    @Published var selectedDeckID: String
    @Published var resolver: OnDeviceDeckResolver?
    @Published private(set) var pendingFix: FixRequest?
    let store: DeckStudioReceiptStore
    let appBuild: String
    /// Writes the chosen id to the app's selected-deck preference.
    var onSelect: (String) -> Void = { _ in }
    /// True while a game or match room is open; validation starts its own engine.
    var isGameLive: () -> Bool = { false }
    /// Leaves Deck Studio for the game setup screen.
    var setUpGame: () -> Void = {}
    private let validator: Validator
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var storeObservation: AnyCancellable?

    init(selectedDeckID: String = OnDeviceSetupPreferences.defaultDeckID, store: DeckStudioReceiptStore? = nil,
         appBuild: String? = nil, validator: Validator? = nil) {
        self.selectedDeckID = selectedDeckID
        self.store = store ?? .shared
        self.appBuild = appBuild ?? DeckStudioValidationService.appBuild
        self.validator = validator ?? { try await DeckStudioValidationService.shared.validate($0, resolver: $1) }
        storeObservation = self.store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isChecking: Bool { if case .checking = outcome { return true } else { return false } }

    // MARK: Status

    nonisolated static func key(deckID: String, deck: DeckList, resolver: OnDeviceDeckResolver, appBuild: String) throws -> DeckStudioCheckKey {
        let request = try DeckStudioPlayProjection(deck).resolve(resolver).encoded()
        return DeckStudioCheckKey(deckID: deckID, request: request, upstream: resolver.upstreamCommit,
                                  catalogue: resolver.catalogueHash, appBuild: appBuild)
    }

    func key(deckID: String, deck: DeckList) -> DeckStudioCheckKey? {
        guard let resolver else { return nil }
        return try? Self.key(deckID: deckID, deck: deck, resolver: resolver, appBuild: appBuild)
    }

    /// A deck the loaded resolver cannot read needs fixes; otherwise its stored result decides.
    func status(deckID: String, deck: DeckList) -> DeckStudioPlayStatus {
        guard let resolver else { return .notChecked }
        guard let key = try? Self.key(deckID: deckID, deck: deck, resolver: resolver, appBuild: appBuild) else { return .needsFixes }
        return store.status(for: key)
    }

    /// Selected, and its check still matches these cards and this install.
    func isPlaying(deckID: String, deck: DeckList) -> Bool {
        deckID == selectedDeckID && status(deckID: deckID, deck: deck) == .ready
    }

    /// Every game start plays this projection: sideboard, maybeboard and considering
    /// cards stay in the saved deck and out of play. A deck the projection cannot read
    /// is returned unchanged, so the resolver reports the problem at Start.
    nonisolated static func playingDeck(_ deck: DeckList) -> DeckList { (try? DeckStudioPlayProjection(deck).playing) ?? deck }

    /// Rows the offline resolver cannot play (DeckStudioPlayRules.unplayableCards).
    nonisolated static func unplayableCards(_ deck: DeckList, resolver: OnDeviceDeckResolver) -> [String] {
        DeckStudioPlayRules.unplayableCards(deck) { resolver.canonicalCardName($0) }
    }

    // MARK: Flow

    /// Runs the whole flow. `prepare` saves a dirty or new draft first and returns the
    /// source deck; it throws when the draft cannot be saved.
    @discardableResult
    func play(name: String, prepare: () throws -> Prepared) -> Task<Void, Never>? {
        guard !isChecking else { return nil }
        guard !isGameLive() else { outcome = .gameLive; return nil }
        guard let resolver else {
            outcome = .cannotPlay(deckID: nil, name: name, message: DeckStudioPlayText.catalogueLoading, cards: [])
            return nil
        }
        let prepared: Prepared
        do { prepared = try prepare() } catch {
            outcome = .cannotPlay(deckID: nil, name: name, message: error.localizedDescription, cards: [])
            return nil
        }
        let projection: DeckStudioPlayProjection
        let request: MagicMobileOnDevice.JSONValue
        let key: DeckStudioCheckKey
        do {
            projection = try DeckStudioPlayProjection(prepared.deck)
            request = try projection.resolve(resolver)
            key = DeckStudioCheckKey(deckID: prepared.deckID, request: try request.encoded(), upstream: resolver.upstreamCommit,
                                     catalogue: resolver.catalogueHash, appBuild: appBuild)
        } catch {
            outcome = .cannotPlay(deckID: prepared.deckID, name: name, message: error.localizedDescription,
                                  cards: Self.unplayableCards(prepared.deck, resolver: resolver))
            return nil
        }
        let excluded = projection.excluded.reduce(0) { $0 + $1.quantity }
        // The same request, engine, catalogue and build always gets the same answer.
        if let stored = store.check(for: key) {
            finish(stored, name: name, excluded: excluded)
            return nil
        }
        let captured = UUID(); token = captured
        outcome = .checking(deckID: prepared.deckID, name: name)
        let validator = self.validator
        let deckID = prepared.deckID
        task = Task { [weak self] in
            do {
                let receipt = try await validator(request, resolver)
                try Task.checkCancellation()
                guard let self, self.token == captured else { return }
                self.task = nil
                let stored = DeckStudioStoredCheck(deckID: deckID, receipt: receipt)
                self.store.record(stored)
                self.finish(stored, name: name, excluded: excluded)
            } catch {
                guard let self, self.token == captured else { return }
                self.task = nil
                self.outcome = error is CancellationError ? nil
                    : .cannotPlay(deckID: deckID, name: name, message: error.localizedDescription, cards: [])
            }
        }
        return task
    }

    private func finish(_ check: DeckStudioStoredCheck, name: String, excluded: Int) {
        guard check.valid else {
            outcome = .blocked(deckID: check.key.deckID, name: name, check: check)
            return
        }
        guard !isGameLive() else { outcome = .gameLive; return }
        selectedDeckID = check.key.deckID
        onSelect(check.key.deckID)
        outcome = .nowPlaying(deckID: check.key.deckID, name: name, excludedCards: excluded)
    }

    /// Stops a running check; the playing deck does not change.
    func cancel() {
        token = UUID(); task?.cancel(); task = nil
        if isChecking { outcome = nil }
    }

    func dismiss() {
        if isChecking { cancel() } else { outcome = nil }
    }

    /// Fix deck: the caller opens the deck; the workspace takes the cards when it appears.
    func requestFix(deckID: String, cards: [String]) {
        pendingFix = FixRequest(deckID: deckID, cards: cards)
        outcome = nil
    }

    func takeFix(for deckID: String?) -> [String]? {
        guard let deckID, let fix = pendingFix, fix.deckID == deckID else { return nil }
        pendingFix = nil
        return fix.cards
    }
}

/// XMage re-checks every deck when a game is created. A failed local Start is
/// stored like any other failed check, then shown with the same issues sheet.
struct DeckStudioStartRejection: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let details: MagicMobileOnDevice.JSONValue

    init?(_ error: Error) {
        guard let engine = error as? EngineError, case .rejectionDetails(let code, let message, let details) = engine,
              code == "invalid_deck" else { return nil }
        self.message = message; self.details = details
    }

    /// The failed check for the player's deck, or nil when it cannot be the player's:
    /// the deck already passed this exact check, or an issue names a card outside it.
    @MainActor func check(deckID: String, deck: DeckList, resolver: OnDeviceDeckResolver, appBuild: String,
               store: DeckStudioReceiptStore) -> DeckStudioStoredCheck? {
        guard let request = try? DeckStudioPlayProjection(deck).resolve(resolver).encoded(),
              let receipt = try? DeckStudioValidationReceipt.rejection(details: details.encoded(), message: message,
                  request: request, upstream: resolver.upstreamCommit, catalogue: resolver.catalogueHash, appBuild: appBuild)
        else { return nil }
        let check = DeckStudioStoredCheck(deckID: deckID, receipt: receipt)
        let playing = DeckStudioPlaySelection.playingDeck(deck)
        let names = ([playing.commander].compactMap { $0 } + playing.entries).flatMap { entry in
            [entry.cardName, resolver.canonicalCardName(entry.cardName)].compactMap { $0 }
        }
        guard DeckStudioPlayRules.storesStartResult(valid: false, issueCards: check.cardNames, deckCards: names,
                                                    alreadyPassed: store.check(for: check.key)?.valid == true) else { return nil }
        return check
    }

    /// XMage created the game, so the player's deck passed the same Commander check:
    /// stored as a pass under the key Deck Studio reads.
    @MainActor static func pass(deckID: String, deck: DeckList, resolver: OnDeviceDeckResolver, appBuild: String) -> DeckStudioStoredCheck? {
        guard let request = try? DeckStudioPlayProjection(deck).resolve(resolver).encoded() else { return nil }
        return DeckStudioStoredCheck(key: DeckStudioCheckKey(deckID: deckID, request: request, upstream: resolver.upstreamCommit,
                                                             catalogue: resolver.catalogueHash, appBuild: appBuild),
                                     checkedAt: Date(), valid: true, summary: DeckStudioPlayText.startPassed, issues: [])
    }
}
