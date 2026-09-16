import SwiftUI

struct DeckStudioCardSearch: View {
    let metadata: NativeDeckMetadataCatalogue?
    let colors: [String]?
    let add: (String, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var type = ""
    @State private var section = "deck"
    @State private var constrainIdentity = true
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    @State private var lastAdded: String?
    @State private var loading = false
    @State private var addError: String?
    private struct Request: Equatable {
        let query: String
        let type: String
        let identity: [String]?
    }
    private var requestKey: Request { Request(query: query, type: type, identity: constrainIdentity ? colors : nil) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    TextField("Card name or rules text", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    HStack {
                        Picker("Type", selection: $type) {
                            Text("All types").tag("")
                            ForEach(["Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker"], id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Add to", selection: $section) {
                            Text("Main deck").tag("deck"); Text("Commander(s)").tag("commanders"); Text("Maybeboard").tag("maybeboard")
                        }
                    }
                    if colors != nil { Toggle("Within commander color identity", isOn: $constrainIdentity).font(.caption) }
                    if let addError { Text(addError).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                    if let lastAdded { Text("Added \(lastAdded)").font(.caption).foregroundStyle(DeckStudioPalette.success).accessibilityAddTraits(.updatesFrequently) }
                }.padding(.horizontal, 20)
                if loading { ProgressView("Searching local cards") }
                List(results) { card in
                    HStack(spacing: 12) {
                        DeckStudioArtwork(name: card.name).frame(width: 36, height: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name).font(.subheadline.weight(.medium))
                            Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                        Spacer()
                        Button {
                            if add(card.name, section) { lastAdded = card.name; addError = nil }
                            else { lastAdded = nil; addError = "Could not add this card. Check the draft quantity or section limits." }
                        } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Add \(card.name) to \(section)")
                    }.listRowBackground(DeckStudioPalette.surface)
                }.scrollContentBackground(.hidden)
                Text("Bundled XMage catalogue · showing up to 80 matches. Refine your search for more. Color identity is not deck validation.")
                    .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk).padding(.horizontal, 20).padding(.bottom, 12)
            }
            .background(DeckStudioPalette.background).navigationTitle("Add cards").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: requestKey) { await search() }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    private func search() async {
        guard let metadata else { return }
        loading = true
        let capturedQuery = query, capturedType = type, identity = constrainIdentity ? colors : nil
        do {
            try await Task.sleep(for: .milliseconds(150))
            let loaded = await Task.detached(priority: .userInitiated) {
                DeckStudioCatalogueSearch.cards(in: metadata, query: capturedQuery,
                                               type: capturedType, allowedIdentity: identity)
            }.value
            try Task.checkCancellation()
            results = loaded; loading = false
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
                    NativeCardArtworkView(name: name, variant: .inspection) { _, _ in
                        DeckStudioNotice(title: name, message: "Artwork is optional. Card text remains available offline.", icon: "rectangle.portrait")
                    }.frame(maxWidth: 340, minHeight: 120, maxHeight: 420).frame(maxWidth: .infinity)
                    Text(name).font(.system(.title, design: .serif).weight(.bold))
                    Text(metadata?.typeLine ?? "Type not in the loaded catalogue").font(.headline)
                    if let cost = metadata?.manaCost { Text(cost).font(.body.monospaced()) }
                    Text(metadata?.oracleText ?? "Text unavailable in the bundled metadata.").textSelection(.enabled)
                    Text("Bundled selected-printing metadata. Rules and legality follow the installed XMage version.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                }.padding(24)
            }.background(DeckStudioPalette.background).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}
