import Foundation

/// Goldfish sample hand: draw seven from the main deck, London mulligan (shuffle,
/// draw seven, put one card on the bottom per mulligan taken), then draw a card
/// each turn. Commanders and other boards stay out of the library.
struct DeckStudioSampleHand: Equatable {
    struct Card: Identifiable, Equatable {
        let id: Int
        let name: String
    }
    static let handSize = 7

    private(set) var library: [Card]
    private(set) var hand: [Card] = []
    private(set) var mulligans = 0
    /// Cards still to put on the bottom after the latest mulligan.
    private(set) var toBottom = 0
    private(set) var draws = 0
    var turn: Int { draws + 1 }
    var canMulligan: Bool { draws == 0 && toBottom == 0 && mulligans < Self.handSize && !hand.isEmpty }
    var canDraw: Bool { toBottom == 0 && !library.isEmpty }

    /// Main-deck cards, one entry per copy.
    static func libraryNames(from draft: NativeDeckDraft) -> [String] {
        draft.rows.filter { DeckStudioBoard.of($0) == "deck" }.flatMap { Array(repeating: $0.cardName, count: max(0, min($0.quantity, 2000))) }
    }

    init(names: [String]) {
        library = names.enumerated().map { Card(id: $0.offset, name: $0.element) }
    }

    /// A fresh opening hand from the whole deck.
    mutating func deal<G: RandomNumberGenerator>(using generator: inout G) {
        library = (library + hand).sorted { $0.id < $1.id }
        hand = []; mulligans = 0; toBottom = 0; draws = 0
        drawSeven(using: &generator)
    }
    mutating func mulligan<G: RandomNumberGenerator>(using generator: inout G) {
        guard canMulligan else { return }
        library += hand; hand = []
        mulligans += 1
        drawSeven(using: &generator)
        toBottom = min(mulligans, hand.count)
    }
    mutating func putOnBottom(_ id: Int) {
        guard toBottom > 0, let index = hand.firstIndex(where: { $0.id == id }) else { return }
        library.append(hand.remove(at: index))
        toBottom -= 1
    }
    mutating func draw() {
        guard canDraw else { return }
        hand.append(library.removeFirst())
        draws += 1
    }
    private mutating func drawSeven<G: RandomNumberGenerator>(using generator: inout G) {
        library.shuffle(using: &generator)
        let count = min(Self.handSize, library.count)
        hand = Array(library.prefix(count))
        library.removeFirst(count)
    }
}
