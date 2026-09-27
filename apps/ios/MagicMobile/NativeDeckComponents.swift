import SwiftUI
import UIKit

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
                Text("Commander · \(CardCountText.label(record.cardCount))").font(.caption)
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
            Text(CardCountText.label(count)).font(.caption).foregroundStyle(.secondary)
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
            Text("Main deck only · \(CardCountText.label(statistics.cardCount))").font(.headline)
            Text("Commander, companion and other sections excluded: \(CardCountText.label(statistics.excludedCardCount)).")
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
                        .accessibilityLabel("Mana value \(value.formatted()): \(CardCountText.label(curve[value] ?? 0))")
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

enum NativeArtworkPreference {
    /// One spelling of the consent key, so a new surface cannot drift onto its own store.
    static let key = "magicmobile.deckArtworkNetworkEnabled"
}

struct NativeArtworkPreferenceView: View {
    @AppStorage(NativeArtworkPreference.key) private var remoteArtwork = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Scryfall live images", isOn: $remoteArtwork)
                .accessibilityIdentifier("nativeArtwork.downloads")
            Text("Show saved art first, then sharper images online. Offline download quality stays unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Scryfall receives card names—including your hand—and your IP address.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NativeDeckCardImage: View {
    let name: String
    var inspection = false
    var contentMode: ContentMode = .fit
    var body: some View {
        NativeCardArtworkView(name: name, variant: inspection ? .inspection : .board, contentMode: contentMode) { _, failed in
            VStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.largeTitle)
                Text(name.isEmpty ? "Your next deck" : name).font(.caption.bold()).multilineTextAlignment(.center)
                Text(failed ? "Artwork unavailable" : "Artwork downloads are optional").font(.caption2)
            }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(MagicPalette.parchment)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityElement(children: .ignore).accessibilityLabel(name.isEmpty ? "Deck cover" : name)
    }
}

enum NativeCardArtworkPolicy {
    static func permitsLookup(card: ZoneCard) -> Bool {
        permitsLookup(name: card.card.name) &&
            !(card.cardIcons ?? []).contains { $0.iconType.uppercased() == "OTHER_FACEDOWN" }
    }

    static func permitsLookup(name: String) -> Bool {
        NativeDeckArtwork.permitsSourceName(name)
    }
}

/// The one consent-aware artwork route for native deck and gameplay cards.
/// AppStorage inherits the native root's default store, including isolated UI-test suites.
struct NativeCardArtworkView<Placeholder: View>: View {
    let name: String
    let variant: CardImageCacheVariant
    var contentMode: ContentMode = .fit
    var artOnly = false
    var tokenTypeLine: String? = nil
    var tokenOracleText: String? = nil
    var tokenPower: String? = nil
    var tokenToughness: String? = nil
    var tokenColors: [String]? = nil
    /// Supply only an explicitly identified, visible card that the token copies.
    var tokenSourceName: String? = nil
    @ViewBuilder let placeholder: (_ loading: Bool, _ failed: Bool) -> Placeholder
    @AppStorage(NativeArtworkPreference.key) private var remoteArtwork = false
    @State private var artwork: UIImage?
    @State private var completedRequest: Request?
    @State private var failedRequest: Request?
    @State private var downloadRevision = 0

    private struct Request: Hashable {
        let name: String
        let variant: NativeDeckArtwork.Variant
        let allowNetwork: Bool
        let tokenTypeLine: String?
        let tokenOracleText: String?
        let tokenPower: String?
        let tokenToughness: String?
        let tokenColors: [String]?
        let tokenSourceName: String?
        let downloadRevision: Int
        let artOnly: Bool
    }

    var body: some View {
        let request = Request(name: name, variant: variant == .inspection ? .inspection : .board,
                              allowNetwork: remoteArtwork, tokenTypeLine: tokenTypeLine, tokenOracleText: tokenOracleText,
                              tokenPower: tokenPower, tokenToughness: tokenToughness, tokenColors: tokenColors,
                              tokenSourceName: tokenSourceName,
                              downloadRevision: downloadRevision, artOnly: artOnly)
        let permitted = NativeCardArtworkPolicy.permitsLookup(name: name)
        Group {
            if permitted, completedRequest == request, let artwork {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder(permitted && remoteArtwork && completedRequest != request && failedRequest != request,
                            permitted && failedRequest == request)
            }
        }
            .onReceive(NotificationCenter.default.publisher(for: NativeAssetDownloads.didFinish)) { _ in downloadRevision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: NativeAssetStore.didStoreArtwork).receive(on: RunLoop.main)) { note in
                guard let key = note.userInfo?["key"] as? String else { return }
                if NativeAssetStore.artworkChangeAffects(key: key, storedName: note.userInfo?["name"] as? String,
                                                       name: name, isToken: tokenTypeLine != nil, sourceName: tokenSourceName) {
                    downloadRevision += 1
                }
            }
            .task(id: request) {
                guard permitted else { artwork = nil; completedRequest = nil; failedRequest = nil; return }
                artwork = nil; completedRequest = nil; failedRequest = nil
                // CardImageURL only supplies a generated cache path here; never fetch its remote fallback.
                if tokenTypeLine == nil, let url = CardImageURL.image(name, variant: variant), url.isFileURL,
                   let data = NativeDeckArtwork.localImageData(at: url),
                   let image = NativeDeckArtwork.decodedImage(data, variant: request.variant) {
                    guard !Task.isCancelled else { return }
                    artwork = presentedImage(image); completedRequest = request
                    let quality: NativeArtworkQuality = request.variant == .inspection ? .high : .standard
                    if !request.allowNetwork || quality.accepts(data) { return }
                    // Keep a safe low-resolution image visible offline or if upgrade fails.
                } else if tokenTypeLine == nil, request.variant == .inspection,
                          let url = CardImageURL.image(name, variant: .board), url.isFileURL,
                          let data = NativeDeckArtwork.localImageData(at: url),
                          let image = NativeDeckArtwork.decodedImage(data, variant: .inspection) {
                    guard !Task.isCancelled else { return }
                    artwork = presentedImage(image); completedRequest = request
                }
                do {
                    if artwork == nil,
                       let cached = try await NativeDeckArtwork.shared.imageData(name: name, variant: .board, allowNetwork: false,
                                                                                tokenTypeLine: tokenTypeLine, tokenOracleText: tokenOracleText,
                                                                                tokenPower: tokenPower, tokenToughness: tokenToughness, tokenColors: tokenColors,
                                                                                tokenSourceName: tokenSourceName),
                       let image = NativeDeckArtwork.decodedImage(cached, variant: .inspection) {
                        try Task.checkCancellation()
                        artwork = presentedImage(image); completedRequest = request
                    }
                    guard !Task.isCancelled, request.allowNetwork == remoteArtwork else { return }
                    let data = try await NativeDeckArtwork.shared.imageData(name: name, variant: request.variant, allowNetwork: request.allowNetwork,
                                                                           tokenTypeLine: tokenTypeLine, tokenOracleText: tokenOracleText,
                                                                           tokenPower: tokenPower, tokenToughness: tokenToughness, tokenColors: tokenColors,
                                                                           tokenSourceName: tokenSourceName)
                    try Task.checkCancellation()
                    guard request.allowNetwork == remoteArtwork else { return }
                    if let data, let image = NativeDeckArtwork.decodedImage(data, variant: request.variant) {
                        artwork = presentedImage(image)
                    }
                    completedRequest = request
                    failedRequest = request.allowNetwork && artwork == nil ? request : nil
                } catch is CancellationError { } catch {
                    guard !Task.isCancelled else { return }
                    failedRequest = request
                }
            }
    }

    /// Copy-token art is always the illustration alone, even without `artOnly`:
    /// TokenCopyCardFace draws the token's own name, type line and live stats around it,
    /// and the printed source card (whose name or stats can differ) never shows.
    private func presentedImage(_ image: CGImage) -> UIImage {
        UIImage(cgImage: artOnly || tokenSourceName != nil ? (NativeDeckArtwork.illustrationImage(image) ?? image) : image)
    }
}

extension NativeCardArtworkView {
    /// A game card's artwork. A token looks up its public template (the battlefield card's
    /// `tokenArtwork`, else its live face), and a token copy its explicitly identified source.
    init(card: ZoneCard, variant: CardImageCacheVariant, contentMode: ContentMode = .fit, artOnly: Bool = false,
         @ViewBuilder placeholder: @escaping (_ loading: Bool, _ failed: Bool) -> Placeholder) {
        let token = card.card.isToken == true
        self.init(name: card.card.name, variant: variant, contentMode: contentMode, artOnly: artOnly,
                  tokenTypeLine: token ? (card.card.tokenArtwork?.typeLine ?? card.card.typeLine) : nil,
                  tokenOracleText: token ? (card.card.tokenArtwork?.oracleText ?? card.card.oracleText) : nil,
                  tokenPower: token ? (card.card.tokenArtwork?.power ?? card.displayPower) : nil,
                  tokenToughness: token ? (card.card.tokenArtwork?.toughness ?? card.displayToughness) : nil,
                  tokenColors: token ? (card.card.tokenArtwork?.colors ?? card.card.tokenColors) : nil,
                  tokenSourceName: token ? card.card.copySourceArtworkName : nil,
                  placeholder: placeholder)
    }
}
