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
                            Text("Structural counts from bundled metadata. Use Validate & playtest for an exact result from the installed XMage Commander validator.")
                                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                    }
                }
                DeckStudioPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Main-deck mana curve").font(.headline)
                        Text("Tap a mana value to inspect its cards. Lands, commanders and other sections are excluded.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
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
                        ForEach(statistics.manaSymbolCounts.keys.sorted(), id: \.self) { symbol in metric("{\(symbol)}", "\(statistics.manaSymbolCounts[symbol, default: 0])") }
                        Text("Hybrid and Phyrexian symbols stay distinct. Printed costs are not usable mana-source counts. Conditional mana production, land-face decisions and cost reductions are not inferred from card text.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                }
                if !curveOnly {
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Card types & colors").font(.headline)
                            ForEach(["CREATURE", "ARTIFACT", "ENCHANTMENT", "INSTANT", "SORCERY", "LAND", "PLANESWALKER", "BATTLE"], id: \.self) { type in metric(type.capitalized, "\(typeCount(type))") }
                            Divider()
                            ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { color in metric(color == "C" ? "Colorless" : color, "\(colorCount(color))") }
                            Text("Main-deck quantities. Multi-type and multicolor cards count in each applicable category, so categories overlap. Unknown metadata is not assumed colorless. These are card colors, not commander color identity or mana sources.")
                                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
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
                                Text("Chance of seeing at least \(requiredLands) printed land cards in \(cardsSeen) random cards from this \(statistics.cardCount)-card main deck. Seven means an opening hand; add the number of ordinary draws to examine later draws. Commanders are outside the library.")
                                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                                Text("No mulligans, tutors, extra-draw spells, land-side choices or play decisions are modeled. Seeing enough lands is not proof of making each land drop or producing the needed colors.")
                                    .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
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
