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
            .frame(width: 300).padding(8).background(DeckStudioPalette.background)
            .preferredColorScheme(.light)
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

/// One card in the Cards grid. In select mode a tap toggles the selection.
struct DeckStudioCardGridTile: View {
    let row: NativeDeckRow
    let card: NativeDeckMetadataCatalogue.Card?
    let issues: [DeckStudioPreflight.Issue]
    /// nil outside select mode.
    let selected: Bool?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DeckStudioCardImageTile(name: row.cardName, card: card)
                .overlay(alignment: .topTrailing) {
                    if row.quantity > 1 {
                        Text("×\(row.quantity)").font(.caption.weight(.bold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(DeckStudioPalette.surfaceElevated)
                            .background(DeckStudioPalette.ink.opacity(0.85), in: Capsule()).padding(4)
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
            DeckStudioIssueBadges(issues: issues)
        }.contentShape(Rectangle())
    }
}
