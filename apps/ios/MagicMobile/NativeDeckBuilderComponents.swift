import SwiftUI

enum NativeDeckBuilderLayout {
    // Width-based so presenting the keyboard does not switch portrait into a split.
    static func usesColumns(width: CGFloat) -> Bool { width >= 650 }
    static func deckWidth(width: CGFloat) -> CGFloat { max(320, width * 0.48) }
}

struct NativeDeckBuilderFilters: View {
    @Binding var cardType: String
    @Binding var color: String

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Button { color = "" } label: { Text("All").font(.caption.bold()).frame(width: 44, height: 44) }
                        .accessibilityLabel("All printed colors")
                        .background(color.isEmpty ? MagicPalette.antiqueGold.opacity(0.25) : .clear, in: Circle())
                    ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { symbol in
                        Button { color = color == symbol ? "" : symbol } label: {
                            ManaSymbolView(symbol: symbol, size: 25).frame(width: 44, height: 44)
                        }.background(color == symbol ? MagicPalette.antiqueGold.opacity(0.25) : .clear, in: Circle())
                            .accessibilityLabel("Printed colors exactly \(symbol == "C" ? "colorless" : symbol)")
                            .accessibilityValue(color == symbol ? "Selected" : "Not selected")
                            .accessibilityIdentifier("nativeDeck.filter.color.\(symbol)")
                    }
                }
            }
            Picker("Card type", selection: $cardType) {
                Text("All types").tag("")
                ForEach(["Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Land", "Battle"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).font(.caption).accessibilityIdentifier("nativeDeck.filter.type")
        }.buttonStyle(.plain)
    }
}

struct NativeDeckCollectionTile: View {
    let card: NativeDeckMetadataCatalogue.Card
    let count: Int
    let canAdd: Bool
    let section: String
    let inspect: () -> Void
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: inspect) {
                HStack(spacing: 8) {
                    NativeDeckCardImage(name: card.name).frame(width: 40, height: 54).clipped()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name).font(.subheadline.weight(.semibold))
                            .foregroundStyle(MagicPalette.parchment).fixedSize(horizontal: false, vertical: true)
                        NativeDeckManaCost(cost: card.manaCost)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Inspect \(card.name)")
                .accessibilityIdentifier("nativeDeck.collection.inspect.\(card.name)")
            Button(action: add) {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                    Text("\(count) in deck").font(.caption2).monospacedDigit()
                }.frame(minWidth: 54, minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canAdd)
                .accessibilityLabel("Add \(card.name) to \(section)")
                .accessibilityIdentifier("nativeDeck.collection.add.\(card.name)")
                .background(MagicPalette.antiqueGold.opacity(0.12))
        }.padding(6)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            count > 0 ? MagicPalette.antiqueGold.opacity(0.65) : .white.opacity(0.15), lineWidth: 1))
    }
}

struct NativeDeckBuilderRow: View {
    let row: NativeDeckRow
    let card: NativeDeckMetadataCatalogue.Card?
    let canAdd: Bool
    let inspect: () -> Void
    let increase: () -> Void
    let decrease: () -> Void
    let remove: () -> Void
    let move: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: inspect) {
                HStack(spacing: 8) {
                    NativeDeckCardImage(name: row.cardName).frame(width: 36, height: 50).clipped()
                    Text("\(row.quantity)×").font(.headline).monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.cardName).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        NativeDeckManaCost(cost: card?.manaCost)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 4).padding(.leading, 6).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("nativeDeck.inspect.\(row.cardName)")
                .accessibilityValue("\(row.quantity) copies")
            HStack(spacing: 0) {
                Menu {
                    Button("Main deck") { move("deck") }
                    Button("Commander / partner") { move("commanders") }
                    Button("Companion") { move("companions") }
                    Button("Remove all copies", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Section and actions for \(row.cardName)")
                Button(action: decrease) { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Remove one \(row.cardName)")
                Button(action: increase) { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .disabled(!canAdd).accessibilityLabel("Add one \(row.cardName)")
            }.buttonStyle(.borderless)
        }.background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
    }
}
