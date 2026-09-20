import SwiftUI

struct DeckStudioAnalysisView: View {
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let curveOnly: Bool
    let inspect: (String) -> Void
    var body: some View { ScrollView { DeckStudioAnalysisContent(draft: draft, metadata: metadata, curveOnly: curveOnly, inspect: inspect).padding(20) } }
}

struct DeckStudioAnalysisContent: View {
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let curveOnly: Bool
    let inspect: (String) -> Void
    @State private var selectedBin: Int?
    @State private var requiredLands = 3
    @State private var cardsSeen = 7
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var statistics: NativeDeckMetadataCatalogue.Statistics? {
        var display = draft
        if display.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { display.name = "Draft" }
        guard let deck = try? display.deck() else { return nil }
        return try? metadata?.statistics(for: deck)
    }
    private var mainRows: [NativeDeckRow] { draft.rows.filter { DeckStudioDraftPresentation.section($0) == "deck" } }
    private func curveBin(_ row: NativeDeckRow) -> Int? {
        guard let card = metadata?.card(named: row.cardName), let types = card.types,
              !types.contains("LAND"), let mv = card.manaValue else { return nil }
        return mv >= 7 ? 7 : Int(mv)
    }
    private func binCount(_ bin: Int) -> Int { mainRows.filter { curveBin($0) == bin }.reduce(0) { $0 + $1.quantity } }
    private func typeCount(_ type: String) -> Int { mainRows.filter { metadata?.card(named: $0.cardName)?.types?.contains(type) == true }.reduce(0) { $0 + $1.quantity } }
    private func colorCount(_ color: String) -> Int {
        mainRows.filter { row in
            guard let colors = metadata?.card(named: row.cardName)?.colors else { return false }
            return color == "C" ? colors.isEmpty : colors.contains(color)
        }.reduce(0) { $0 + $1.quantity }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let statistics {
                if !curveOnly {
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your deck at a glance").font(.title2.weight(.semibold))
                            metric("Main deck", "\(statistics.cardCount)")
                            metric("Commander(s)", "\(draft.rows.filter { DeckStudioDraftPresentation.section($0) == "commanders" }.reduce(0) { $0 + $1.quantity })")
                            metric("Other sections", "\(draft.rows.filter { !["deck", "commanders"].contains(DeckStudioDraftPresentation.section($0)) }.reduce(0) { $0 + $1.quantity })")
                            metric("Lands in main", "\(statistics.landCount)")
                            metric("Average nonland mana value", statistics.averageManaValue.map { String(format: "%.2f", $0) } ?? "Unavailable")
                            Text("Deck statistics · check legality in Playtest.")
                                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                    }
                }
                DeckStudioPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Main-deck mana curve").font(.headline)
                        Text("Tap a bar to see its cards. Main-deck nonlands only.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        if dynamicType.isAccessibilitySize {
                            ForEach(0...7, id: \.self) { bin in
                                Button { selectedBin = selectedBin == bin ? nil : bin } label: { metric(bin == 7 ? "7+ mana" : "\(bin) mana", "\(binCount(bin)) cards") }.frame(minHeight: 44)
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .bottom, spacing: 6) {
                                    ForEach(0...7, id: \.self) { bin in
                                        Button { selectedBin = selectedBin == bin ? nil : bin } label: {
                                            VStack(spacing: 7) {
                                                Text("\(binCount(bin))").font(.caption.monospacedDigit())
                                                RoundedRectangle(cornerRadius: 5).fill(selectedBin == bin ? DeckStudioPalette.accent : DeckStudioPalette.ink)
                                                    .frame(height: max(3, 100 * Double(binCount(bin)) / Double(max(1, (0...7).map(binCount).max() ?? 1))))
                                                Text(bin == 7 ? "7+" : "\(bin)").font(.caption)
                                            }.frame(width: 44, height: 144, alignment: .bottom)
                                        }.buttonStyle(.plain).accessibilityLabel("Mana value \(bin == 7 ? "7 or more" : "\(bin)"), \(binCount(bin)) cards. Show cards.")
                                    }
                                }
                            }
                        }
                        if let selectedBin {
                            ForEach(mainRows.filter { curveBin($0) == selectedBin }) { row in
                                Button { inspect(row.cardName) } label: {
                                    HStack(spacing: 10) {
                                        if !dynamicType.isAccessibilitySize {
                                            DeckStudioArtwork(name: row.cardName).frame(width: 36, height: 50)
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                        }
                                        metric(row.cardName, "×\(row.quantity)")
                                    }
                                }.frame(minHeight: 44)
                            }
                        }
                        if statistics.unknownTypeCount > 0 || statistics.unknownManaValueCount > 0 {
                            DeckStudioNotice(title: "Incomplete metadata", message: "\(statistics.unknownTypeCount) unknown types; \(statistics.unknownManaValueCount) unknown mana values. Missing data is excluded, not treated as zero.")
                        }
                    }
                }
                DeckStudioPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Printed mana symbols").font(.headline)
                        ForEach(statistics.manaSymbolCounts.keys.sorted(), id: \.self) { symbol in
                            HStack {
                                ManaSymbolView(symbol: symbol, size: 24)
                                Spacer()
                                Text("\(statistics.manaSymbolCounts[symbol, default: 0])").foregroundStyle(DeckStudioPalette.secondaryInk)
                            }.accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(symbol) mana symbol: \(statistics.manaSymbolCounts[symbol, default: 0])")
                        }
                        DisclosureGroup("How to read these counts") {
                            Text("Printed costs, not available mana sources. Hybrid and Phyrexian symbols stay distinct. Conditional mana, land-face choices and cost reductions are not inferred.")
                        }.font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                }
                if !curveOnly {
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Card types & colors").font(.headline)
                            ForEach(["CREATURE", "ARTIFACT", "ENCHANTMENT", "INSTANT", "SORCERY", "LAND", "PLANESWALKER", "BATTLE"], id: \.self) { type in metric(type.capitalized, "\(typeCount(type))") }
                            Divider()
                            ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { color in
                                HStack {
                                    ManaSymbolView(symbol: color, size: 24)
                                    Spacer()
                                    Text("\(colorCount(color))").foregroundStyle(DeckStudioPalette.secondaryInk)
                                }.accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(["W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green", "C": "Colorless"][color] ?? color): \(colorCount(color)) cards")
                            }
                            DisclosureGroup("About types and colors") {
                                Text("Main-deck quantities; categories overlap for multi-type and multicolor cards. Unknown colors are excluded. Card colors are not commander identity or mana sources.")
                            }.font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                    }
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Opening hands & land draws").font(.headline)
                            Stepper("At least \(requiredLands) lands", value: $requiredLands, in: 1...7)
                            Stepper("Cards seen: \(cardsSeen)", value: $cardsSeen, in: 7...30)
                            if statistics.cardCount >= cardsSeen, statistics.unknownTypeCount == 0,
                               let value = try? DeckStudioProbability.atLeast(requiredLands, successes: statistics.landCount, population: statistics.cardCount, draws: cardsSeen) {
                                Text(value, format: .percent.precision(.fractionLength(1))).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                Text("Chance of at least \(requiredLands) lands in \(cardsSeen) random cards.")
                                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                                DisclosureGroup("What this estimate includes") {
                                    Text("Uses printed lands in the \(statistics.cardCount)-card main deck. Seven cards represents an opening hand; commanders stay outside the library. No mulligans, tutors, extra draws, land-face choices or play decisions are modeled. Enough lands does not guarantee each land drop or the colors you need.")
                                }.font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            } else { Text("Requires at least \(cardsSeen) main-deck cards and known card types.").font(.caption) }
                        }
                    }
                }
                if !statistics.unknownNames.isEmpty {
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Unresolved cards", systemImage: "exclamationmark.triangle").font(.headline)
                            ForEach(statistics.unknownNames, id: \.self) { Text($0).font(.subheadline) }
                        }
                    }
                }
            } else { DeckStudioNotice(title: "Analysis unavailable", message: "Wait for the local metadata catalogue or fix malformed draft entries. Your saved deck is unchanged.") }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).font(.subheadline); Spacer(minLength: 16); Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(DeckStudioPalette.secondaryInk) }.accessibilityElement(children: .combine)
    }
}
