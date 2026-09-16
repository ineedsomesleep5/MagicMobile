import SwiftUI

struct DeckStudioAnalysisView: View {
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let curveOnly: Bool
    let inspect: (String) -> Void
    var body: some View {
        ScrollView {
            DeckStudioAnalysisContent(draft: draft, metadata: metadata, curveOnly: curveOnly, inspect: inspect).padding(20)
        }
    }
}

struct DeckStudioAnalysisContent: View {
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let curveOnly: Bool
    let inspect: (String) -> Void
    @State private var selectedBin: Int?
    @State private var requiredLands = 3
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let statistics {
                if !curveOnly {
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your deck at a glance").font(.system(.title2, design: .serif).weight(.semibold))
                            metric("Main deck", "\(statistics.cardCount)")
                            metric("Commander(s)", "\(draft.rows.filter { DeckStudioDraftPresentation.section($0) == "commanders" }.reduce(0) { $0 + $1.quantity })")
                            metric("Other sections", "\(draft.rows.filter { !["deck", "commanders"].contains(DeckStudioDraftPresentation.section($0)) }.reduce(0) { $0 + $1.quantity })")
                            metric("Lands in main", "\(statistics.landCount)")
                            metric("Average nonland mana value", statistics.averageManaValue.map { String(format: "%.2f", $0) } ?? "Unavailable")
                            metric("Commander validation", "Not run in editor")
                            Text("Counts and metadata do not certify a legal deck. The installed XMage validator remains authoritative at game start.")
                                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                    }
                }
                DeckStudioPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Main-deck mana curve").font(.headline)
                        Text("Tap a mana value to inspect its cards. Lands, commanders and other sections are excluded.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
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
                                                RoundedRectangle(cornerRadius: 5).fill(selectedBin == bin ? DeckStudioPalette.gold : DeckStudioPalette.ink)
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
                                Button { inspect(row.cardName) } label: { metric(row.cardName, "×\(row.quantity)") }.frame(minHeight: 44)
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
                        Text("Hybrid and Phyrexian symbols stay distinct. These are printed costs, not a count of usable mana sources or a land recommendation.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                }
                if !curveOnly {
                    DeckStudioPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Opening-hand probability").font(.headline)
                            Stepper("At least \(requiredLands) lands", value: $requiredLands, in: 1...7)
                            if statistics.cardCount >= 7, statistics.unknownTypeCount == 0,
                               let value = try? DeckStudioProbability.atLeast(requiredLands, successes: statistics.landCount, population: statistics.cardCount, draws: 7) {
                                Text(value, format: .percent.precision(.fractionLength(1))).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                Text("In a random 7-card hand from this \(statistics.cardCount)-card main deck. Commanders are outside the library. No mulligans, tutors, extra draws, land-side choices or AI simulations are modeled.")
                                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            } else { Text("Requires at least seven main-deck cards and known card types.").font(.caption) }
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
            } else {
                DeckStudioNotice(title: "Analysis unavailable", message: "Wait for the local metadata catalogue or fix malformed draft entries. Your saved deck is unchanged.")
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline)
            Spacer(minLength: 16)
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(DeckStudioPalette.secondaryInk)
        }.accessibilityElement(children: .combine)
    }
}
