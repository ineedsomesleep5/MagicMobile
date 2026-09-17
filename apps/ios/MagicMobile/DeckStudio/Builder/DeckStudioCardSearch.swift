import SwiftUI

struct DeckStudioCardSearch: View {
    let metadata: NativeDeckMetadataCatalogue?
    let colors: [String]?
    let add: (String, String) -> Bool
    var resolver: OnDeviceDeckResolver? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var source = "Local"
    @State private var query = ""
    @State private var type = ""
    @State private var section = "deck"
    @State private var setCode = ""
    @State private var minMV = ""
    @State private var maxMV = ""
    @State private var constrainIdentity = true
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    @State private var lastAdded: String?
    @State private var loading = false
    @State private var addError: String?
    @State private var inspection: NativeDeckMetadataCatalogue.Card?
    private struct Request: Equatable { let query: String; let type: String; let identity: [String]?; let set: String; let min: String; let max: String }
    private var requestKey: Request { Request(query: query, type: type, identity: constrainIdentity ? colors : nil, set: setCode, min: minMV, max: maxMV) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Search source", selection: $source) { Text("Local catalogue").tag("Local"); Text("Scryfall — online").tag("Online") }.pickerStyle(.segmented).padding(.horizontal, 20)
                Picker("Add to", selection: $section) { Text("Main deck").tag("deck"); Text("Commander(s)").tag("commanders"); Text("Maybeboard").tag("maybeboard") }.pickerStyle(.menu)
                if source == "Online" { DeckStudioOnlineSearch(resolver: resolver, destination: section, add: add).padding(.horizontal, 20) }
                else { localSearch }
            }.background(DeckStudioPalette.background).navigationTitle("Add cards").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $inspection) { card in DeckStudioCardInspector(name: card.name, metadata: card) }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    private var localSearch: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                TextField("Card name or rules text", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                DisclosureGroup("Filters") {
                    VStack(spacing: 12) {
                        Picker("Type", selection: $type) { Text("All types").tag(""); ForEach(["Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker", "Battle"], id: \.self) { Text($0).tag($0) } }
                        HStack { TextField("Min MV", text: $minMV).keyboardType(.decimalPad); TextField("Max MV", text: $maxMV).keyboardType(.decimalPad); TextField("Set code", text: $setCode).autocorrectionDisabled().textInputAutocapitalization(.characters) }.textFieldStyle(.roundedBorder)
                        if colors != nil { Toggle("Within commander color identity", isOn: $constrainIdentity).font(.caption) }
                        Button("Reset filters") { type = ""; minMV = ""; maxMV = ""; setCode = ""; constrainIdentity = true }
                    }.padding(.vertical, 10)
                }.font(.caption)
                if let addError { Text(addError).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                if let lastAdded { Text("Added \(lastAdded)").font(.caption).foregroundStyle(DeckStudioPalette.success).accessibilityAddTraits(.updatesFrequently) }
            }.padding(.horizontal, 20)
            if loading { ProgressView("Searching local cards") }
            List(results) { card in
                HStack(spacing: 12) {
                    DeckStudioArtwork(name: card.name).frame(width: 36, height: 50)
                    Button { inspection = card } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name).font(.subheadline.weight(.medium))
                            Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            if let cost = card.manaCost { Text(cost).font(.caption2.monospaced()) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button {
                        if add(card.name, section) { lastAdded = card.name; addError = nil }
                        else { lastAdded = nil; addError = "Could not add this card. Check the draft quantity or section limits." }
                    } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Add \(card.name) to \(section)")
                }.listRowBackground(DeckStudioPalette.surface)
            }.scrollContentBackground(.hidden)
            Text("Bundled XMage catalogue · up to 80 matches. Refine the filters for more. Color identity and name resolution are not Commander validation.").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk).padding(.horizontal, 20).padding(.bottom, 12)
        }.task(id: requestKey) { await search() }
    }
    private func search() async {
        guard let metadata else { return }
        loading = true
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
                    Text(metadata?.typeLine ?? "Type not in the loaded catalogue").font(.headline)
                    if let cost = metadata?.manaCost { Text(cost).font(.body.monospaced()) }
                    Text(metadata?.oracleText ?? "Text unavailable in the bundled metadata.").textSelection(.enabled)
                    Text("Bundled selected-printing metadata. Rules and legality follow the installed XMage version.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    DeckStudioScryfallReference(name: name)
                }.padding(24)
            }.background(DeckStudioPalette.background).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}
