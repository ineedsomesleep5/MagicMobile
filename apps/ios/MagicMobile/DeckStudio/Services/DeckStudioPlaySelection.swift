import Foundation
import Combine
import MagicMobileOnDevice

/// Player-facing wording for choosing the playing deck. Android's
/// DeckStudioPlaySelection.kt shows the same strings; change both together.
enum DeckStudioPlayText {
    static let play = "Play this deck"
    static let saveAndPlay = "Save & play"
    static let playing = "Playing"
    static let playingAccessibility = "This is your playing deck"
    static let fixDeck = "Fix deck"
    static let notNow = "Not now"
    static let setUpGame = "Set up game"
    static let cannotPlayTitle = "Can't play this deck yet"
    static let checkingTitle = "Checking your deck"
    static let gameLive = "Leave your current game to change decks."
    static func checking(_ name: String) -> String { "XMage is checking \(name) against the Commander rules on this device." }
    static func nowPlaying(_ name: String) -> String { "Now playing \(name)" }
    static func nowPlayingStrip(_ name: String, _ status: DeckStudioPlayStatus) -> String { "Now playing: \(name) · \(status.label)" }
    static func issueCount(_ count: Int) -> String { "\(count) \(count == 1 ? "issue" : "issues")" }
    static func blocked(_ count: Int) -> String { count == 1 ? "1 rule issue blocks play" : "\(count) rule issues block play" }
    static func excluded(_ cards: Int) -> String { "Sideboard and maybeboard stay out of play (\(CardCountText.label(cards)))." }
    static func deletePlaying(_ fallback: String) -> String { "This is your playing deck. \(fallback) will be selected instead." }
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

    func status(deckID: String, deck: DeckList) -> DeckStudioPlayStatus { store.status(for: key(deckID: deckID, deck: deck)) }

    /// Selected, and its check still matches these cards and this install.
    func isPlaying(deckID: String, deck: DeckList) -> Bool {
        deckID == selectedDeckID && status(deckID: deckID, deck: deck) == .ready
    }

    /// Every game start plays this projection: sideboard, maybeboard and considering
    /// cards stay in the saved deck and out of play. A deck the projection cannot read
    /// is returned unchanged, so the resolver reports the problem at Start.
    nonisolated static func playingDeck(_ deck: DeckList) -> DeckList { (try? DeckStudioPlayProjection(deck).playing) ?? deck }

    /// Playing cards the offline resolver has no printing for.
    nonisolated static func unresolvedCards(_ deck: DeckList, resolver: OnDeviceDeckResolver) -> [String] {
        let playing = playingDeck(deck)
        var seen = Set<String>()
        return ([playing.commander].compactMap { $0 } + playing.entries).compactMap { entry in
            resolver.canonicalCardName(entry.cardName) == nil && seen.insert(entry.cardName).inserted ? entry.cardName : nil
        }
    }

    // MARK: Flow

    /// Runs the whole flow. `prepare` saves a dirty or new draft first and returns the
    /// source deck; it throws when the draft cannot be saved.
    @discardableResult
    func play(name: String, prepare: () throws -> Prepared) -> Task<Void, Never>? {
        guard !isChecking else { return nil }
        guard !isGameLive() else { outcome = .gameLive; return nil }
        guard let resolver else { return nil }
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
                                  cards: Self.unresolvedCards(prepared.deck, resolver: resolver))
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
        if store.check(for: check.key)?.valid == true { return nil }
        let playing = DeckStudioPlaySelection.playingDeck(deck)
        let names = Set(([playing.commander].compactMap { $0 } + playing.entries).flatMap { entry in
            [entry.cardName, resolver.canonicalCardName(entry.cardName)].compactMap { $0 }
        })
        guard check.cardNames.allSatisfy(names.contains) else { return nil }
        return check
    }
}
