import SwiftUI

/// Goldfish a sample hand from the main deck: draw seven, London mulligan, then
/// draw a card per turn. Commanders stay out of the library.
struct DeckStudioSampleHandView: View {
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let inspect: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var hand: DeckStudioSampleHand?
    private var names: [String] { DeckStudioSampleHand.libraryNames(from: draft) }
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sample hand", systemImage: "hand.raised").font(.title2.weight(.semibold))
                Text("Draw seven from your main deck. Commanders stay in the command zone, and sideboard and maybeboard cards stay out.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if names.isEmpty {
                    Text("Add main-deck cards to draw a sample hand.").font(.subheadline)
                } else if let hand {
                    Text(status(hand)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(hand.toBottom > 0 ? DeckStudioPalette.accent : DeckStudioPalette.ink)
                        .accessibilityIdentifier("deckStudio.sampleHand.status")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(hand.hand) { card in
                                Button {
                                    if hand.toBottom > 0 { self.hand?.putOnBottom(card.id) } else { inspect(card.name) }
                                } label: {
                                    DeckStudioCardImageTile(name: card.name, card: metadata?.card(named: card.name))
                                        .frame(width: dynamicType.isAccessibilitySize ? 150 : 96)
                                }.buttonStyle(DeckStudioArtworkButtonStyle())
                                    .accessibilityLabel(card.name)
                                    .accessibilityHint(hand.toBottom > 0 ? "Puts this card on the bottom of your library" : "Shows the card")
                            }
                        }.padding(.vertical, 2)
                    }
                    Text("\(CardCountText.label(hand.hand.count)) in hand · \(CardCountText.label(hand.library.count)) in library")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { controls(hand) }
                        VStack(alignment: .leading, spacing: 8) { controls(hand) }
                    }
                } else {
                    Button("Draw 7", systemImage: "hand.draw") { deal() }
                        .buttonStyle(DeckStudioButtonStyle()).accessibilityIdentifier("deckStudio.sampleHand.draw7")
                }
            }
        }
        .onChange(of: names) { _, _ in hand = nil }
    }
    @ViewBuilder private func controls(_ hand: DeckStudioSampleHand) -> some View {
        Button("New hand") { deal() }.buttonStyle(DeckStudioButtonStyle(primary: false))
        Button("Mulligan") {
            var generator = SystemRandomNumberGenerator()
            self.hand?.mulligan(using: &generator)
        }.buttonStyle(DeckStudioButtonStyle(primary: false)).disabled(!hand.canMulligan)
        Button("Draw") { self.hand?.draw() }.buttonStyle(DeckStudioButtonStyle()).disabled(!hand.canDraw)
            .accessibilityIdentifier("deckStudio.sampleHand.drawCard")
    }
    private func status(_ hand: DeckStudioSampleHand) -> String {
        if hand.toBottom > 0 { return "Put \(CardCountText.label(hand.toBottom)) on the bottom" }
        let mulligans = hand.mulligans == 0 ? "" : " · \(hand.mulligans) \(hand.mulligans == 1 ? "mulligan" : "mulligans")"
        return "Turn \(hand.turn)\(mulligans)"
    }
    private func deal() {
        var generator = SystemRandomNumberGenerator()
        var next = DeckStudioSampleHand(names: names)
        next.deal(using: &generator)
        hand = next
    }
}
