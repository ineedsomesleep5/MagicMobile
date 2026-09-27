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
                Label(DeckStudioPlayText.sampleHand, systemImage: "hand.raised").font(.title2.weight(.semibold))
                Text(DeckStudioPlayText.sampleHandCaption)
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if names.isEmpty {
                    Text(DeckStudioPlayText.sampleHandEmpty).font(.subheadline)
                } else if let hand {
                    Text(hand.status).font(.subheadline.weight(.semibold))
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
                                    // Long-press shows the card large, as on Android.
                                    .contextMenu {
                                        Button(DeckStudioPlayText.cardDetails, systemImage: "info.circle") { inspect(card.name) }
                                    } preview: { DeckStudioCardPreview(name: card.name, card: metadata?.card(named: card.name)) }
                                    .accessibilityLabel(card.name)
                                    .accessibilityHint(hand.toBottom > 0 ? "Puts this card on the bottom of your library" : "Shows the card")
                            }
                        }.padding(.vertical, 2)
                    }
                    Text(DeckStudioPlayText.handCounts(hand: hand.hand.count, library: hand.library.count))
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { controls(hand) }
                        VStack(alignment: .leading, spacing: 8) { controls(hand) }
                    }
                } else {
                    Button(DeckStudioPlayText.draw7, systemImage: "hand.draw") { deal() }
                        .buttonStyle(DeckStudioButtonStyle()).accessibilityIdentifier("deckStudio.sampleHand.draw7")
                }
            }
        }
        .onChange(of: names) { _, _ in hand = nil }
    }
    @ViewBuilder private func controls(_ hand: DeckStudioSampleHand) -> some View {
        Button(DeckStudioPlayText.newHand) { deal() }.buttonStyle(DeckStudioButtonStyle(primary: false))
        Button(DeckStudioPlayText.mulligan) {
            var generator = SystemRandomNumberGenerator()
            self.hand?.mulligan(using: &generator)
        }.buttonStyle(DeckStudioButtonStyle(primary: false)).disabled(!hand.canMulligan)
        Button(DeckStudioPlayText.draw) { self.hand?.draw() }.buttonStyle(DeckStudioButtonStyle()).disabled(!hand.canDraw)
            .accessibilityIdentifier("deckStudio.sampleHand.drawCard")
    }
    private func deal() {
        var generator = SystemRandomNumberGenerator()
        var next = DeckStudioSampleHand(names: names)
        next.deal(using: &generator)
        hand = next
    }
}
