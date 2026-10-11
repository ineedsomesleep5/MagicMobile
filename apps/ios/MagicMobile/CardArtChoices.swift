import Foundation

/// Which art a card view draws: the player's choice for that card name (the default everywhere cards
/// are drawn by name), or an exact one. A deck row passes its own choice, `.exact(nil)` meaning the
/// card's default art, so another deck's choice never shows on it.
enum CardArtSelection: Hashable {
    case active
    case exact(CardPrinting?)
    /// The reverse face of exactly this printing, for a deck row's card turned over.
    case exactBack(CardPrinting)
}

/// Which printing's art a card shows. The player picks it per deck row in Deck Studio; everywhere a
/// card is drawn by name (the board, the opening hand, the inspector, profile and match history)
/// the choice is found here, so the picture matches what the player chose. The playing deck's
/// choices come first, then those of the saved decks, the most recently saved deck first.
/// Android's CardArtChoices (core/CardPrinting.kt) follows the same order.
final class CardArtChoices: @unchecked Sendable {
    /// The app's choices. The bundled catalogue is read for reverse faces only once some card has a choice.
    static let shared = CardArtChoices(reverseFaceLoader: { (try? NativeDeckMetadataCatalogue.bundled())?.reverseFaceFronts })
    /// Posted (on the main thread) when the choices a card name resolves to change.
    static let didChange = Notification.Name("MagicMobileCardArtChoicesChanged")

    struct SavedDeck: Equatable {
        let id: String
        let deck: DeckList
        let updated: Date
        init(id: String, deck: DeckList, updated: Date) { self.id = id; self.deck = deck; self.updated = updated }
    }
    /// What to draw for a name: a printing, and whether the name is that card's reverse face.
    struct Selection: Hashable, Sendable {
        let printing: CardPrinting
        let back: Bool
    }

    private let lock = NSLock()
    private var library: [SavedDeck] = []
    private var selectedID: String?
    private var byName: [String: CardPrinting] = [:]
    /// Reverse face name key to its front face's name key: a double-faced card's other face.
    private var reverse: [String: String] = [:]
    private let reverseFaceLoader: (@Sendable () -> [String: String]?)?
    private var loadingReverseFaces = false

    init(reverseFaceLoader: (@Sendable () -> [String: String]?)? = nil) { self.reverseFaceLoader = reverseFaceLoader }

    static func key(_ name: String) -> String { NativeAssetStore.cardKey(name) }

    /// The saved decks (ids as the deck picker spells them, "local:<id>").
    func setLibrary(_ decks: [SavedDeck]) { apply { library = decks } }
    /// The deck chosen for play, by the picker's id; a precon or included deck has no choices of its own.
    func select(deckID: String?) { apply { selectedID = deckID } }
    func update(library decks: [SavedDeck], selectedDeckID: String?) { apply { library = decks; selectedID = selectedDeckID } }
    private func apply(_ change: () -> Void) {
        lock.lock()
        change()
        let changed = rebuild()
        let load = !byName.isEmpty && reverse.isEmpty && !loadingReverseFaces && reverseFaceLoader != nil
        if load { loadingReverseFaces = true }
        lock.unlock()
        if changed { Self.announce() }
        if load, let loader = reverseFaceLoader {
            DispatchQueue.global(qos: .utility).async { [self] in
                if let faces = loader() { setReverseFaces(faces) }
                lock.lock(); loadingReverseFaces = false; lock.unlock()
            }
        }
    }

    /// The reverse faces of double-faced cards, so a transformed permanent shows its own face of the chosen printing.
    func setReverseFaces(_ faces: [String: String]) {
        lock.lock()
        reverse = Dictionary(faces.map { (Self.key($0.key), Self.key($0.value)) }, uniquingKeysWith: { first, _ in first })
        lock.unlock()
        Self.announce()
    }
    var needsReverseFaces: Bool { lock.lock(); defer { lock.unlock() }; return reverse.isEmpty && !byName.isEmpty }

    func printing(forName name: String) -> CardPrinting? { selection(forName: name)?.printing }

    func selection(forName name: String) -> Selection? {
        let key = Self.key(name)
        lock.lock(); defer { lock.unlock() }
        if let printing = byName[key] { return Selection(printing: printing, back: false) }
        if let front = reverse[key], let printing = byName[front] { return Selection(printing: printing, back: true) }
        return nil
    }

    /// Whether any card currently has a choice.
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return byName.isEmpty }

    /// The choices of the decks, in priority order. A card the playing deck holds takes that deck's
    /// choice, or its default art when none was made, whatever other decks chose. Caller holds the lock.
    private func rebuild() -> Bool {
        var ordered = library.sorted { $0.updated > $1.updated }
        if let selectedID, let index = ordered.firstIndex(where: { $0.id == selectedID }) { ordered.insert(ordered.remove(at: index), at: 0) }
        var next: [String: CardPrinting] = [:]
        var decided = Set<String>()
        for (position, saved) in ordered.enumerated() {
            let playing = position == 0 && saved.id == selectedID
            var held = Set<String>()
            for entry in ([saved.deck.commander].compactMap { $0 } + saved.deck.entries) {
                let key = Self.key(entry.cardName)
                guard !decided.contains(key) else { continue }
                held.insert(key)
                if let printing = entry.printing, next[key] == nil { next[key] = printing }
            }
            if playing { decided.formUnion(held) }
            else { decided.formUnion(held.filter { next[$0] != nil }) }
        }
        defer { byName = next }
        return next != byName
    }

    private static func announce() {
        if Thread.isMainThread { NotificationCenter.default.post(name: didChange, object: nil) }
        else { DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) } }
    }
}

/// The two faces of double-faced cards by name, so a card can be turned over to show its other face
/// (Deck Studio's card details and the in-game inspector). Built from the bundled catalogue's reverse
/// faces on first use. Android's DoubleFacedCards (core/CardPrinting.kt) matches.
final class DoubleFacedCards: @unchecked Sendable {
    static let shared = DoubleFacedCards(loader: { (try? NativeDeckMetadataCatalogue.bundled())?.reverseFaceFronts })

    /// A card's other face: its name, and whether it is the back.
    struct Face: Hashable, Sendable {
        let name: String
        let isBack: Bool
    }

    private let lock = NSLock()
    private var frontOfBack: [String: String]?
    private var backOfFront: [String: String] = [:]
    private let loader: (@Sendable () -> [String: String]?)?

    init(reverseFaces: [String: String]? = nil, loader: (@Sendable () -> [String: String]?)? = nil) {
        self.loader = loader
        if let reverseFaces { setReverseFaces(reverseFaces) }
    }

    /// Reverse face name to its front face's name.
    func setReverseFaces(_ faces: [String: String]) {
        // A front with several attested backs keeps the first by name, so the pairing is stable.
        let backs = Dictionary(faces.map { ($0.value, $0.key) }, uniquingKeysWith: { min($0, $1) })
        lock.lock(); frontOfBack = faces; backOfFront = backs; lock.unlock()
    }

    /// The other face, once the faces are known; nil for a single-faced card.
    func otherFace(of name: String) -> Face? {
        lock.lock(); defer { lock.unlock() }
        if let back = backOfFront[name] { return Face(name: back, isBack: true) }
        if let front = frontOfBack?[name] { return Face(name: front, isBack: false) }
        return nil
    }

    /// The other face, reading the bundled catalogue off the main thread the first time.
    func loadedOtherFace(of name: String) async -> Face? {
        if !isLoaded, let loader {
            let faces = await Task.detached(priority: .userInitiated) { loader() }.value
            if !isLoaded { setReverseFaces(faces ?? [:]) }
        }
        return otherFace(of: name)
    }
    private var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return frontOfBack != nil }
}
