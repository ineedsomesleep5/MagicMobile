import SwiftUI

struct DeckStudioReplacementPicker: View {
    let metadata: NativeDeckMetadataCatalogue?
    let commander: Bool
    let replace: (String, Bool) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var keepOld = true
    @State private var error: String?
    private var results: [NativeDeckMetadataCatalogue.Card] {
        guard let metadata else { return [] }
        var filter = NativeDeckMetadataCatalogue.SearchFilter(); filter.query = query
        return metadata.search(filter, limit: 80)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Search exact catalogue cards", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled().padding(.horizontal, 20)
                if commander {
                    Toggle("Keep replaced commander in maybeboard", isOn: $keepOld).font(.caption).padding(.horizontal, 20)
                    Text("Replaces the primary commander only. Partners remain. One matching main-deck copy is promoted; XMage still checks commander eligibility and duplicates.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk).padding(.horizontal, 20)
                } else { Text("Keeps the row's quantity, section and identity. Undo reverses the replacement.").font(.caption).padding(.horizontal, 20) }
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                List(results) { card in
                    Button {
                        if replace(card.name, keepOld) { dismiss() }
                        else { error = "The draft changed or this edit exceeds its limits. No partial edit was committed." }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(card.name).font(.subheadline); Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk) }
                            .frame(minHeight: 44)
                    }.listRowBackground(DeckStudioPalette.surface)
                }.scrollContentBackground(.hidden)
            }.background(DeckStudioPalette.background).navigationTitle(commander ? "Change commander" : "Replace card").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}

struct DeckStudioBasicLandsSheet: View {
    let draft: NativeDeckDraft
    let apply: ([String: Int], NativeDeckDraft) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Int]
    @State private var error: String?
    init(draft: NativeDeckDraft, apply: @escaping ([String: Int], NativeDeckDraft) -> Bool) {
        self.draft = draft; self.apply = apply
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: NativeDeckDraft.basicLandNames.map { ($0, draft.basicLandCount($0)) }))
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("Set main-deck basic-land counts. Other sections, snow basics and nonbasic lands stay unchanged. This is your edit, not an automatic mana-base recommendation.").font(.caption)
                ForEach(NativeDeckDraft.basicLandNames, id: \.self) { name in
                    Stepper("\(name): \(values[name, default: 0])", value: Binding(get: { values[name, default: 0] }, set: { values[name] = $0 }), in: 0...2000)
                }
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
            }.navigationTitle("Basic lands").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { if apply(values, draft) { dismiss() } else { error = "The draft changed or these counts exceed its limits. Nothing was partially applied." } }
                    }
                }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}
