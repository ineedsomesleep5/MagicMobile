import SwiftUI

struct DeckStudioCardSearch: View {
    let metadata: NativeDeckMetadataCatalogue?
    let colors: [String]?
    let add: (String, String) -> Bool
    var resolver: OnDeviceDeckResolver? = nil
    @ObservedObject var model: DeckStudioEditorModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var source = "Local"
    @State private var query = ""
    @State private var type = ""
    @State private var section = "deck"
    @State private var setCode = ""
    @State private var minMV = ""
    @State private var maxMV = ""
    @State private var constrainIdentity = true
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    @State private var feedback: String?
    @State private var loading = false
    @State private var addError: String?
    @State private var inspection: NativeDeckMetadataCatalogue.Card?
    @FocusState private var searchFocused: Bool
    private struct Request: Equatable { let query: String; let type: String; let identity: [String]?; let set: String; let min: String; let max: String }
    private var requestKey: Request { Request(query: query, type: type, identity: constrainIdentity ? colors : nil, set: setCode, min: minMV, max: maxMV) }
    var body: some View {
        Group {
            if embedded { searchContent }
            else {
                NavigationStack {
                    searchContent.navigationTitle("Add cards").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("deckStudio.search.close") } }
                }
            }
        }
        .sheet(item: $inspection) { card in DeckStudioCardInspector(name: card.name, metadata: card) }
        .tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    private var searchContent: some View {
        VStack(spacing: 8) {
            if embedded {
                HStack {
                    sourcePicker.pickerStyle(.menu)
                    Spacer(minLength: 8)
                    destinationPicker
                }.padding(.horizontal, 12)
            } else {
                Group {
                    if dynamicType.isAccessibilitySize {
                        sourcePicker.pickerStyle(.menu)
                    } else {
                        sourcePicker.pickerStyle(.segmented)
                    }
                }.padding(.horizontal, 20)
                destinationPicker
            }
            if source == "Online" { DeckStudioOnlineSearch(resolver: resolver, destination: section, add: add, model: model) }
            else { localSearch }
        }.frame(maxHeight: .infinity, alignment: .top).background(DeckStudioPalette.background)
            .onChange(of: section) { _, _ in feedback = nil; addError = nil }
    }
    private var sourcePicker: some View {
        Picker("Search source", selection: $source) { Text("Local catalogue").tag("Local"); Text("Scryfall — online").tag("Online") }
    }
    private var destinationPicker: some View {
        Picker("Add to", selection: $section) {
            Text("Main deck").tag("deck"); Text("Commander(s)").tag("commanders")
            Text("Maybeboard").tag("maybeboard"); Text("Sideboard").tag("sideboard"); Text("Companion").tag("companions")
        }.pickerStyle(.menu)
    }
    private var localSearch: some View {
        List {
            VStack(spacing: 10) {
                TextField("Card name or rules text", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                DisclosureGroup("Filters") {
                    VStack(spacing: 12) {
                        Picker("Type", selection: $type) { Text("All types").tag(""); ForEach(["Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker", "Battle"], id: \.self) { Text($0).tag($0) } }
                        HStack { TextField("Min MV", text: $minMV).keyboardType(.decimalPad); TextField("Max MV", text: $maxMV).keyboardType(.decimalPad); TextField("Set code", text: $setCode).autocorrectionDisabled().textInputAutocapitalization(.characters) }.textFieldStyle(.roundedBorder)
                        if colors != nil { Toggle("Within commander color identity", isOn: $constrainIdentity).font(.caption) }
                        Button("Reset filters") { type = ""; minMV = ""; maxMV = ""; setCode = ""; constrainIdentity = true }
                    }.padding(.vertical, 10)
                }.font(.caption)
                if !embedded { DeckStudioArtworkInvitation() }
                if let addError { Text(addError).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                if let feedback { Text(feedback).font(.caption).foregroundStyle(DeckStudioPalette.success).accessibilityAddTraits(.updatesFrequently) }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if loading { ProgressView("Searching local cards") }
            if metadata == nil {
                DeckStudioNotice(title: "Local catalogue unavailable", message: "Close this editor and retry the catalogue from your library, or use online search for reference.")
            } else if !loading && results.isEmpty {
                ContentUnavailableView("No matching cards", systemImage: "magnifyingglass", description: Text("Try another name or reset the filters."))
            }
            ForEach(results) { card in
                HStack(spacing: 12) {
                    if !dynamicType.isAccessibilitySize {
                        DeckStudioArtwork(name: card.name).frame(width: embedded ? 36 : 52, height: embedded ? 50 : 73)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Button { inspection = card } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name).font(.subheadline.weight(.medium))
                            Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            if let cost = card.manaCost { NativeDeckManaCost(cost: cost) }
                            if model.cardCount(card.name) > 0 {
                                Text("\(model.cardCount(card.name)) in deck · \(model.cardCount(card.name, section: section)) here").font(.caption2).foregroundStyle(DeckStudioPalette.success)
                            }
                            if model.needsSingletonReview(card.name, metadata: card, destination: section) {
                                Text("Already in playing deck · check copy limit").font(.caption2).foregroundStyle(DeckStudioPalette.warning)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Inspect \(card.name)")
                    VStack(spacing: 0) {
                    if model.cardCount(card.name, section: section) > 0 {
                        Button {
                            let before = model.cardCount(card.name, section: section)
                            model.removeOne(card.name, section: section)
                            if model.cardCount(card.name, section: section) < before { feedback = "Removed one \(card.name) from \(section)"; addError = nil }
                            else { feedback = nil; addError = "Could not remove this card; check the draft." }
                        } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Remove one \(card.name) from \(section)")
                    }
                    Button {
                        if add(card.name, section) { feedback = "Added \(card.name) to \(section)"; addError = nil }
                        else { feedback = nil; addError = "Could not add this card. Check the draft quantity or section limits." }
                    } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Add \(card.name) to \(section)")
                    }
                }.listRowBackground(DeckStudioPalette.surface)
            }
            Text("\(results.count) matches\(results.count == 80 ? " · refine search for more" : "") · validate before playing")
                .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }.listStyle(.plain).buttonStyle(.borderless).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
            .contentMargins(.top, 0, for: .scrollContent)
            .task(id: requestKey) { await search() }
    }
    private func search() async {
        guard let metadata else { return }
        loading = true; results = []; feedback = nil; addError = nil
        let captured = requestKey
        let lower = captured.min.isEmpty ? nil : Double(captured.min)
        let upper = captured.max.isEmpty ? nil : Double(captured.max)
        guard (captured.min.isEmpty || lower != nil) && (captured.max.isEmpty || upper != nil), lower.map({ $0.isFinite && $0 >= 0 }) ?? true,
              upper.map({ $0.isFinite && $0 >= 0 }) ?? true, lower == nil || upper == nil || lower! <= upper! else {
            results = []; addError = "Use a nonnegative mana-value range with the minimum no greater than the maximum."; loading = false; return
        }
        do {
            try await Task.sleep(for: .milliseconds(150))
            let loaded = await Task.detached(priority: .userInitiated) {
                DeckStudioCatalogueSearch.cards(in: metadata, query: captured.query, type: captured.type, allowedIdentity: captured.identity,
                    setCode: captured.set, minimumManaValue: lower, maximumManaValue: upper)
            }.value
            try Task.checkCancellation()
            results = loaded; loading = false; addError = nil
        } catch is CancellationError { } catch { loading = false }
    }
}

struct DeckStudioCardInspector: View {
    let name: String
    let metadata: NativeDeckMetadataCatalogue.Card?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NativeCardArtworkView(name: name, variant: .inspection) { _, _ in DeckStudioNotice(title: name, message: "Artwork is optional. Card text remains available offline.", icon: "rectangle.portrait") }
                        .frame(maxWidth: 340, minHeight: 120, maxHeight: 420).frame(maxWidth: .infinity)
                    Text(name).font(.system(.title, design: .serif).weight(.bold))
                    DeckStudioArtworkInvitation()
                    Text(metadata?.typeLine ?? "Type not in the loaded catalogue").font(.headline)
                    if let cost = metadata?.manaCost { NativeDeckManaCost(cost: cost) }
                    Text(GameRulesPresentation(source: metadata?.oracleText ?? "Text unavailable in the bundled metadata.", cardName: name).plainText).textSelection(.enabled)
                    Text("Bundled selected-printing metadata. Rules and legality follow the installed XMage version.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    DeckStudioScryfallReference(name: name)
                }.padding(24)
            }.background(DeckStudioPalette.background).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("deckStudio.inspector.close") } }
        }.foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}
