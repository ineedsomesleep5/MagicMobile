import SwiftUI

/// A card-shaped image that respects the artwork and privacy preference: with no
/// downloaded art it becomes a text tile (name, cost and type), never a blank box.
struct DeckStudioCardImageTile: View {
    let name: String
    let card: NativeDeckMetadataCatalogue.Card?
    var large = false
    var body: some View {
        NativeCardArtworkView(name: name, variant: large ? .inspection : .board, contentMode: .fit) { _, _ in textTile }
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: large ? 14 : DeckStudioMetrics.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: large ? 14 : DeckStudioMetrics.cardRadius).stroke(DeckStudioPalette.separator))
    }
    private var textTile: some View {
        VStack(alignment: .leading, spacing: large ? 10 : 4) {
            Text(name).font(large ? .title3.weight(.bold) : .caption.weight(.semibold))
                .multilineTextAlignment(.leading).lineLimit(large ? 4 : 3).minimumScaleFactor(0.8)
            if let cost = card?.manaCost, !cost.isEmpty { NativeDeckManaCost(cost: cost) }
            Spacer(minLength: 0)
            Text(card?.typeLine ?? "Unknown card").font(large ? .subheadline : .caption2)
                .foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(large ? 3 : 2)
            if large, let text = card?.oracleText {
                Text(text).font(.caption).foregroundStyle(DeckStudioPalette.ink).lineLimit(10)
            }
        }
        .padding(large ? 16 : 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeckStudioPalette.surfaceElevated)
        .foregroundStyle(DeckStudioPalette.ink)
    }
}

/// The long-press preview: the card at a readable size.
struct DeckStudioCardPreview: View {
    let name: String
    let card: NativeDeckMetadataCatalogue.Card?
    var body: some View {
        DeckStudioCardImageTile(name: name, card: card, large: true)
            .frame(width: 300).padding(8).background(GrimoirePaper())
            .preferredColorScheme(.light).grimoirePage(.loose)
    }
}

/// Inline quick-check badges on a Cards row or grid tile.
struct DeckStudioIssueBadges: View {
    let issues: [DeckStudioPreflight.Issue]
    var body: some View {
        if !issues.isEmpty {
            HStack(spacing: 4) {
                ForEach(issues) { issue in
                    Text(issue.badge).font(.caption2.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(DeckStudioPalette.warning)
                        .background(DeckStudioPalette.warning.opacity(0.12), in: Capsule())
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("Quick check: " + issues.map(\.badge).joined(separator: ", "))
        }
    }
}

/// One card in the Cards grid: its full art, with how many copies the deck holds. While the deck is
/// being edited the corners show what a tap does: the left half takes a copy away, the right half
/// adds one (Caleb, 2026-10-05). In select mode a tap toggles the selection.
struct DeckStudioCardGridTile: View {
    let name: String
    /// Copies in the deck; a search result not in the deck yet has none.
    let quantity: Int
    let card: NativeDeckMetadataCatalogue.Card?
    let issues: [DeckStudioPreflight.Issue]
    /// nil outside select mode.
    let selected: Bool?
    /// Taps change the quantity: show the count always, and the minus and plus in the corners.
    var editable = false
    /// Something to know about this card that is not a quick-check issue (a copy limit to check).
    var warning: String? = nil

    init(row: NativeDeckRow, card: NativeDeckMetadataCatalogue.Card?, issues: [DeckStudioPreflight.Issue], selected: Bool?, editable: Bool = false) {
        self.init(name: row.cardName, quantity: row.quantity, card: card, issues: issues, selected: selected, editable: editable)
    }
    init(name: String, quantity: Int, card: NativeDeckMetadataCatalogue.Card?, issues: [DeckStudioPreflight.Issue] = [], selected: Bool? = nil,
         editable: Bool = false, warning: String? = nil) {
        self.name = name; self.quantity = quantity; self.card = card; self.issues = issues; self.selected = selected; self.editable = editable
        self.warning = warning
    }

    /// What the quick check (or `warning`) has to say, read out on the warning disc.
    private var notes: [String] { issues.map(\.badge) + (warning.map { [$0] } ?? []) }

    var body: some View {
        // Just the card (Caleb, 2026-10-05): its own text is on it, so nothing is written beneath, and
        // what there is to know sits on the card as a small disc.
        DeckStudioCardImageTile(name: name, card: card)
            .overlay(alignment: .topLeading) {
                if selected == nil, !notes.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DeckStudioPalette.surfaceElevated)
                        .frame(width: 22, height: 22)
                        .background(DeckStudioPalette.warning.opacity(0.92), in: Circle())
                        .padding(4)
                        .accessibilityLabel("Quick check: " + notes.joined(separator: ", "))
                }
            }
                .overlay(alignment: .topTrailing) {
                    if quantity > 1 || (editable && quantity > 0) {
                        Text("×\(quantity)").font(.caption.weight(.bold)).monospacedDigit()
                            .contentTransition(.numericText())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(DeckStudioPalette.surfaceElevated)
                            .background(DeckStudioPalette.ink.opacity(0.85), in: Capsule()).padding(4)
                            .accessibilityLabel("\(name), quantity \(quantity)")
                    }
                }
                .overlay(alignment: .bottom) {
                    if editable {
                        HStack {
                            // Nothing to take away from a card the deck does not hold yet.
                            cornerHint("minus").opacity(quantity > 0 ? 1 : 0)
                            Spacer(minLength: 0)
                            cornerHint("plus")
                        }.padding(5).accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let selected {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(selected ? DeckStudioPalette.accent : DeckStudioPalette.surfaceElevated)
                            .background(Circle().fill(selected ? DeckStudioPalette.surfaceElevated : DeckStudioPalette.ink.opacity(0.35)))
                            .padding(4)
                    }
                }
            .overlay {
                if selected == true {
                    RoundedRectangle(cornerRadius: DeckStudioMetrics.cardRadius).stroke(DeckStudioPalette.accent, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
    }

    /// A small inked disc in a bottom corner: what tapping that side of the card does.
    private func cornerHint(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .heavy))
            .foregroundStyle(DeckStudioPalette.surfaceElevated)
            .frame(width: 22, height: 22)
            .background(DeckStudioPalette.ink.opacity(0.78), in: Circle())
            .overlay(Circle().strokeBorder(DeckStudioPalette.surfaceElevated.opacity(0.35), lineWidth: 0.8))
    }
}
