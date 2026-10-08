import SwiftUI

/// The binder's "All cards" shelf (Caleb, 2026-10-06: "choose to look at cards in your deck or cards you
/// want to add"): every card in the local catalogue that passes the rail's search, mana value coins, type
/// and colour filters, in sleeves. The plus adds a copy to the main deck, the minus takes one away, and a
/// card's own right and left halves do the same. Online search stays behind Add cards.
struct DeckStudioBinderCatalogue: View {
    struct Filters: Equatable {
        var query = ""
        var type = ""
        /// W, U, B, R, G, or C for colourless; empty for any.
        var color = ""
        var mana: Set<Int> = []
        /// The commander's colour identity when the search keeps to it.
        var identity: [String]? = nil
    }

    let metadata: NativeDeckMetadataCatalogue?
    @ObservedObject var model: DeckStudioEditorModel
    let filters: Filters
    let inspect: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    @State private var loading = false
    @State private var error: String?

    /// How many sleeves a search shows; more is a sign to narrow it.
    nonisolated static let limit = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if metadata == nil {
                DeckStudioNotice(title: "Local catalogue unavailable", message: "Close this editor and retry the catalogue from your library, or use Add cards to search online.")
            } else if loading && results.isEmpty {
                ProgressView("Searching local cards").frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if results.isEmpty {
                BinderEmptyLeaf(title: "No matching cards", icon: "magnifyingglass",
                                message: "Try another name, or tap a lit mana coin to turn it off.")
            }
            if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 150 : 100), spacing: 10, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(results) { card in sleeve(card) }
            }
            if !results.isEmpty {
                Text(results.count == Self.limit ? "The first \(Self.limit) cards · search or filter to narrow" : "\(results.count) cards")
                    .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityIdentifier("deckStudio.catalogue.list")
        .task(id: filters) { await search() }
    }

    private func sleeve(_ card: NativeDeckMetadataCatalogue.Card) -> some View {
        let here = model.cardCount(card.name, section: "deck")
        let warning = model.needsSingletonReview(card.name, metadata: card, destination: "deck")
        return BinderSleeve(name: card.name, quantity: here, card: card,
                            notes: warning ? ["Already in playing deck, check the copy limit"] : [],
                            canEdit: !model.readOnly,
                            addLabel: "Add \(card.name) to deck", removeLabel: "Remove one \(card.name) from deck",
                            tapLabel: "Inspect \(card.name)",
                            add: { if !model.add(card.name, section: "deck") { error = "Could not add \(card.name). Check the draft's quantity or section limits." } else { error = nil } },
                            remove: { model.removeOne(card.name, section: "deck"); error = nil },
                            tap: { inspect(card.name) })
            .binderContextMenu {
                BinderMenuHeading(card.name)
                BinderMenuButton(DeckStudioPlayText.cardDetails, systemImage: "info.circle") { inspect(card.name) }
            }
    }

    private func search() async {
        guard let metadata else { return }
        loading = true
        let captured = filters
        do {
            try await Task.sleep(for: .milliseconds(150))
            let found = await Task.detached(priority: .userInitiated) { Self.cards(in: metadata, captured) }.value
            try Task.checkCancellation()
            results = found
        } catch {}
        loading = false
    }

    /// The catalogue search with the coins and colour applied. The coins can pick values that are not
    /// next to each other (1 and 5), so the search asks for the whole span and keeps the chosen ones.
    nonisolated static func cards(in metadata: NativeDeckMetadataCatalogue, _ filters: Filters) -> [NativeDeckMetadataCatalogue.Card] {
        let low = filters.mana.min().map(Double.init)
        let high = filters.mana.isEmpty || filters.mana.contains(7) ? nil : filters.mana.max().map { Double($0) + 0.99 }
        let span = DeckStudioCatalogueSearch.cards(in: metadata, query: filters.query, type: filters.type, allowedIdentity: filters.identity,
                                                   minimumManaValue: low, maximumManaValue: high, limit: 2000)
        return Array(span.lazy.filter { card in
            BinderManaFilter.matches(card.manaValue, filters.mana) &&
            (filters.color.isEmpty || (filters.color == "C" ? card.colors?.isEmpty == true : card.colors?.contains(filters.color) == true))
        }.prefix(limit))
    }
}
