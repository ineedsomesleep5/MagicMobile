import SwiftUI

/// Reference metadata only: never overwrites the shipped XMage catalogue.
struct DeckStudioScryfallReference: View {
    let name: String
    var initialCard: DeckStudioScryfallCard? = nil
    @State private var value: DeckStudioScryfallClient.CachedCard?
    @State private var error: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Scryfall reference", systemImage: "globe").font(.headline)
                Text("Optional online reference. Scryfall receives this card name and your IP address. Its current text/legality may differ from the installed XMage version; it never changes the rules engine.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if let card = value?.card ?? initialCard {
                    Text(card.name).font(.subheadline.weight(.semibold))
                    if let value { Text("\(value.cached ? "Cached" : "Fetched") \(value.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk) }
                    else { Text("From the selected Scryfall search result").font(.caption2) }
                    if let cost = card.manaCost { Text(cost).font(.caption.monospaced()) }
                    if let text = card.oracleText { Text(text).font(.subheadline).textSelection(.enabled) }
                    ForEach(Array((card.faces ?? []).enumerated()), id: \.offset) { _, face in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(face.name).font(.subheadline.weight(.semibold))
                            if let text = face.oracleText { Text(text).font(.subheadline).textSelection(.enabled) }
                        }
                    }
                    if let legal = card.legalities?["commander"] { Text("Scryfall Commander status: \(legal)").font(.caption) }
                    if let url = card.websiteURL { Link("View on Scryfall", destination: url).frame(minHeight: 44) }
                }
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                if busy {
                    ProgressView("Looking up reference…")
                    Button("Cancel") { task?.cancel(); generation = UUID(); busy = false }
                } else {
                    Button(value == nil ? "Look up on Scryfall" : "Refresh Scryfall reference") { lookup(network: true) }
                        .buttonStyle(DeckStudioButtonStyle(primary: false))
                }
            }
        }
        .task(id: name) { lookup(network: false) }
        .onDisappear { task?.cancel(); generation = UUID(); busy = false }
    }
    private func lookup(network: Bool) {
        task?.cancel(); let token = UUID(); generation = token; busy = network; error = nil
        task = Task {
            do {
                let result = try await DeckStudioScryfallClient.shared.named(name, allowNetwork: network, refresh: network)
                try Task.checkCancellation(); guard token == generation else { return }
                value = result; busy = false
            } catch {
                guard token == generation else { return }
                busy = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}

struct DeckStudioOnlineSearch: View {
    let resolver: OnDeviceDeckResolver?
    let destination: String
    let add: (String, String) -> Bool
    @ObservedObject var model: DeckStudioEditorModel
    @State private var query = ""
    @State private var result: DeckStudioScryfallPage?
    @State private var error: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var selected: DeckStudioScryfallCard?
    @State private var feedback: String?
    var body: some View {
        VStack(spacing: 12) {
            Text("Online Scryfall search").font(.headline)
            DisclosureGroup("About online search") {
                Text("Only your search query is sent to Scryfall. Cards not supported by the installed engine are available for reference, not play.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            }.font(.caption)
            HStack {
                TextField("Name or Scryfall query", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Search") { search(page: 1) }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).frame(minHeight: 44)
            }
            if busy { HStack { ProgressView("Searching…"); Button("Cancel") { cancel() } } }
            if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(DeckStudioPalette.success) }
            if let result {
                Text("Page \(result.page) · \(result.cached ? "cached" : "fetched") \(result.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2)
                List(result.cards) { card in
                    HStack {
                        Button { selected = card } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.name).font(.subheadline.weight(.medium))
                                Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                                if let name = resolver?.canonicalCardName(card.name), model.cardCount(name) > 0 {
                                    Text("\(model.cardCount(name)) in deck · \(model.cardCount(name, section: destination)) here").font(.caption2).foregroundStyle(DeckStudioPalette.success)
                                }
                                if resolver?.canonicalCardName(card.name) == nil { Text("Not playable in this engine build").font(.caption2).foregroundStyle(DeckStudioPalette.warning) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if let name = resolver?.canonicalCardName(card.name) {
                            if model.cardCount(name, section: destination) > 0 {
                                Button { model.removeOne(name, section: destination) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.buttonStyle(.borderless)
                                    .accessibilityLabel("Remove one \(name) from \(destination)")
                            }
                            Button {
                                feedback = add(name, destination) ? "Added \(name) to \(destination)" : "Could not add this card; check the draft."
                            } label: { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }.buttonStyle(.borderless)
                                .accessibilityLabel("Add \(name) to \(destination)")
                        }
                    }.listRowBackground(DeckStudioPalette.surface)
                }.listStyle(.plain).scrollContentBackground(.hidden)
                HStack {
                    if result.page > 1 { Button("Previous page") { search(page: result.page - 1) }.frame(minHeight: 44) }
                    Spacer()
                    if result.hasMore, result.page < 10 { Button("Next page") { search(page: result.page + 1) }.frame(minHeight: 44) }
                }.disabled(busy)
            }
        }
        .onChange(of: query) { _, _ in cancel(); result = nil; feedback = nil }
        .onDisappear { cancel() }
        .sheet(item: $selected) { card in
            NavigationStack {
                ScrollView { DeckStudioScryfallReference(name: card.name, initialCard: card).padding(20) }
                    .navigationTitle("Card reference").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } } }
                    .background(DeckStudioPalette.background)
            }.preferredColorScheme(.light)
        }
    }
    private func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    private func search(page: Int) {
        cancel(); let token = generation; let captured = query
        busy = true; error = nil
        task = Task {
            do {
                let value = try await DeckStudioScryfallClient.shared.search(captured, page: page, allowNetwork: true)
                try Task.checkCancellation(); guard generation == token, query == captured else { return }
                result = value; busy = false
            } catch {
                guard generation == token else { return }
                busy = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}
