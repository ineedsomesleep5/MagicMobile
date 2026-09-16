import SwiftUI

/// Presentation components shared by the saved-deck browser and durable draft editor.
struct NativeDeckCover: View {
    let record: DeckLibraryRecord
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NativeDeckCardImage(name: record.commander?.cardName ?? record.entries.first?.cardName ?? "",
                                contentMode: .fill)
                .frame(height: 200).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(record.name).font(.headline).lineLimit(2)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(MagicPalette.antiqueGold) }
                }
                Text("Commander · \(NativeDeckDisplay.cardCount(record.cardCount))").font(.caption)
            }.foregroundStyle(.white).padding(12)
        }
        .frame(height: 200)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? MagicPalette.antiqueGold : .white.opacity(0.12)))
        .contentShape(Rectangle())
    }
}

struct NativeDeckManaCost: View {
    let cost: String?
    private var symbols: [String] {
        guard let cost else { return [] }
        return cost.split(separator: "{").compactMap { token in
            guard let end = token.firstIndex(of: "}") else { return nil }
            return String(token[..<end])
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            symbolsRow
            Text(cost?.replacingOccurrences(of: "{*}", with: " // ") ?? "")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cost.map { "Mana cost \($0.replacingOccurrences(of: "{*}", with: " // "))" } ?? "Mana cost unavailable")
    }

    private var symbolsRow: some View {
        HStack(spacing: 3) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                if symbol == "*" {
                    Text("//").font(.caption).foregroundStyle(.secondary)
                } else if ["W", "U", "B", "R", "G", "C"].contains(symbol) {
                    ManaSymbolView(symbol: symbol, size: 19)
                } else {
                    Text(symbol).font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black).frame(minWidth: 19, minHeight: 19)
                        .padding(.horizontal, symbol.count > 1 ? 3 : 0)
                        .background(Color.gray.opacity(0.7), in: Capsule())
                }
            }
        }
    }

}

struct NativeDeckCardRow: View {
    let name: String
    let quantity: Int
    var manaCost: String? = nil
    var typeLine: String? = nil
    let inspect: () -> Void
    var decrease: (() -> Void)? = nil
    var increase: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: inspect) {
                HStack(spacing: 10) {
                    NativeCardArtworkView(name: name, variant: .board) { _, _ in
                        Image(systemName: "rectangle.portrait")
                            .font(.title3).foregroundStyle(MagicPalette.parchment.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.06))
                    }
                        .frame(width: 43, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(MagicPalette.parchment)
                            .fixedSize(horizontal: false, vertical: true)
                        if let manaCost, !manaCost.isEmpty { NativeDeckManaCost(cost: manaCost) }
                        else if let typeLine { Text(typeLine).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("nativeDeck.inspect.\(name)")
                .accessibilityValue("\(quantity) copies")
            if decrease != nil || increase != nil {
                VStack(spacing: 0) {
                    Text("\(quantity)").font(.subheadline.bold()).monospacedDigit()
                        .accessibilityLabel("Quantity \(quantity)")
                    HStack(spacing: 0) {
                        Button { decrease?() } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                            .disabled(decrease == nil).accessibilityLabel("Remove one \(name)")
                        Button { increase?() } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                            .disabled(increase == nil).accessibilityLabel("Add one \(name)")
                    }.buttonStyle(.borderless)
                }
            } else {
                Text("\(quantity)×").font(.subheadline.bold()).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct NativeDeckGroupHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text(title).font(.subheadline.bold())
            Spacer()
            Text(NativeDeckDisplay.cardCount(count)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct NativeDeckFilterBar: View {
    @Binding var cardType: String
    @Binding var color: String
    var body: some View {
        HStack {
            Picker("Card type", selection: $cardType) {
                Text("All types").tag("")
                ForEach(["Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Land", "Battle"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            Picker("Printed colors (exact)", selection: $color) {
                Text("All colors").tag("")
                Text("White only").tag("W"); Text("Blue only").tag("U"); Text("Black only").tag("B")
                Text("Red only").tag("R"); Text("Green only").tag("G"); Text("Colorless").tag("C")
            }
            Spacer(minLength: 0)
            if !cardType.isEmpty || !color.isEmpty {
                Button("Clear") { cardType = ""; color = "" }
            }
        }.pickerStyle(.menu).font(.caption).frame(minHeight: 44)
    }
}

struct NativeDeckBasicLandTools: View {
    let count: (String) -> Int
    let supported: (String) -> Bool
    let change: (String, Int) -> Void
    let canAdd: Bool

    var body: some View {
        DisclosureGroup("Basic lands · manual counts") {
            Text("Changes only these main-deck basics. No suggested total or automatic balancing.")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                ForEach(NativeDeckDraft.basicLandNames, id: \.self) { name in
                    VStack(spacing: 3) {
                        Text(name).font(.caption.bold())
                        Text("\(count(name))").font(.title3.bold()).monospacedDigit()
                        HStack(spacing: 0) {
                            Button { change(name, -1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                                .disabled(count(name) == 0).accessibilityLabel("Remove one basic \(name)")
                                .accessibilityIdentifier("nativeDeck.basic.remove.\(name)")
                            Button { change(name, 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                                .disabled(!supported(name) || !canAdd).accessibilityLabel("Add one basic \(name)")
                                .accessibilityIdentifier("nativeDeck.basic.add.\(name)")
                        }.buttonStyle(.borderless)
                    }.padding(.top, 8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.font(.subheadline.weight(.semibold))
    }
}

struct NativeDeckStatsPanel: View {
    let statistics: NativeDeckMetadataCatalogue.Statistics
    let types: [String: Int]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Main deck only · \(NativeDeckDisplay.cardCount(statistics.cardCount))").font(.headline)
            Text("Commander, companion and other sections excluded: \(statistics.excludedCardCount) cards.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Mana value · nonlands").font(.headline)
            let curve = statistics.manaCurve
            let maximum = max(curve.values.max() ?? 0, 1)
            if !curve.isEmpty { ScrollView(.horizontal) {
              HStack(alignment: .bottom, spacing: 12) {
                ForEach(curve.keys.sorted(), id: \.self) { value in
                    VStack(spacing: 6) {
                        Text("\(curve[value] ?? 0)").font(.caption).monospacedDigit()
                        RoundedRectangle(cornerRadius: 4).fill(MagicPalette.antiqueGold)
                            .frame(height: max(2, CGFloat(curve[value] ?? 0) / CGFloat(maximum) * 140))
                        Text(value.formatted()).font(.caption)
                    }.frame(width: 38)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Mana value \(value.formatted()): \(curve[value] ?? 0) cards")
                }
              }.frame(height: 180, alignment: .bottom)
            } }
            if curve.isEmpty { Text("No known nonland mana values in the main deck.").font(.caption).foregroundStyle(.secondary) }
            if let average = statistics.averageManaValue { LabeledContent("Average nonland mana value", value: average.formatted(.number.precision(.fractionLength(2)))) }
            LabeledContent("Lands", value: String(statistics.landCount))
            Text("Card types").font(.headline)
            ForEach(types.keys.sorted(), id: \.self) { type in
                HStack { Text(type); Spacer(); Text("\(types[type] ?? 0)").monospacedDigit() }
                    .font(.subheadline)
            }
            if !statistics.manaSymbolCounts.isEmpty {
                Text("Printed mana symbols").font(.headline)
                ForEach(statistics.manaSymbolCounts.keys.sorted(), id: \.self) { symbol in
                    HStack {
                        NativeDeckManaCost(cost: "{\(symbol)}")
                        Spacer()
                        Text("\(statistics.manaSymbolCounts[symbol] ?? 0) occurrences").font(.subheadline).monospacedDigit()
                    }
                }
                Text("Counts printed symbols across card quantities. Hybrid symbols stay separate; a generic number is one symbol, not one mana. This is not mana production.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Counts include quantities. Multitype cards can appear in more than one type total. Unknown type: \(statistics.unknownTypeCount); unknown mana value: \(statistics.unknownManaValueCount); unknown mana cost: \(statistics.unknownManaCostCount). Unknown types are excluded from the curve. These statistics do not certify legality or predict mana production.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct NativeDeckStatisticsView: View {
    let deck: DeckList
    let metadata: NativeDeckMetadataCatalogue?
    var body: some View {
        if let metadata {
            switch Result(catching: { try metadata.statistics(for: deck) }) {
            case .success(let statistics):
                NativeDeckStatsPanel(statistics: statistics, types: typeCounts(metadata))
            case .failure(let error): Text(error.localizedDescription).foregroundStyle(MagicPalette.warningAmber)
            }
        } else {
            Text("Local card metadata is unavailable. No statistics are inferred.").foregroundStyle(.secondary)
        }
    }

    private func typeCounts(_ metadata: NativeDeckMetadataCatalogue) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in deck.entries where ["main", "deck"].contains(entry.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            for type in metadata.card(named: entry.cardName)?.types ?? [] { counts[type.capitalized, default: 0] += entry.quantity }
        }
        return counts
    }
}

/// View-only grouping/filtering; never changes names, sections, quantities or commander roles.
enum NativeDeckDisplay {
    static func cardCount(_ count: Int) -> String { "\(count) \(count == 1 ? "card" : "cards")" }

    static func matches(name: String, query: String, type: String, color: String, metadata: NativeDeckMetadataCatalogue?) -> Bool {
        let card = metadata?.card(named: name)
        let nameMatches = query.isEmpty || name.localizedCaseInsensitiveContains(query) || card?.oracleText?.localizedCaseInsensitiveContains(query) == true
        let typeMatches = type.isEmpty || card?.typeLine?.localizedCaseInsensitiveContains(type) == true
        let colors: Set<String>? = card?.colors.map { Set($0) }
        let colorMatches = color.isEmpty || colors == (color == "C" ? Set<String>() : Set([color]))
        return nameMatches && typeMatches && colorMatches
    }

    static func group(section: String, primary: Bool, card: NativeDeckMetadataCatalogue.Card?) -> String {
        if primary { return "Commander" }
        switch section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "commander", "commanders": return "Commander"
        case "companion", "companions": return "Companion"
        case "deck", "main":
            for type in ["CREATURE", "PLANESWALKER", "INSTANT", "SORCERY", "ARTIFACT", "ENCHANTMENT", "LAND", "BATTLE"] {
                if card?.types?.contains(type) == true { return type.capitalized }
            }
            return "Main · other / unknown type"
        default: return section.capitalized
        }
    }

    static func groupOrder(_ left: String, _ right: String) -> Bool {
        let order = ["Commander", "Companion", "Creature", "Planeswalker", "Instant", "Sorcery", "Artifact", "Enchantment", "Land", "Battle"]
        let a = order.firstIndex(of: left) ?? order.count
        let b = order.firstIndex(of: right) ?? order.count
        return a == b ? left < right : a < b
    }
}
