import SwiftUI

/// Resolve against the shipped catalogue before sharing. Never sends other draft sections.
enum DeckStudioSpellbookInput {
    static func make(_ draft: NativeDeckDraft, resolver: OnDeviceDeckResolver?) -> SpellbookDeck? {
        guard let resolver else { return nil }
        var main: [SpellbookDeck.Card] = [], commanders: [SpellbookDeck.Card] = []
        for row in draft.rows {
            let section = DeckStudioDraftPresentation.section(row)
            guard section == "deck" || section == "commanders" else { continue }
            guard let name = resolver.canonicalCardName(row.cardName) else { return nil }
            let card = SpellbookDeck.Card(card: name, quantity: row.quantity)
            if section == "commanders" { commanders.append(card) } else { main.append(card) }
        }
        return try? SpellbookDeck(main: main, commanders: commanders)
    }
}

@MainActor
struct DeckStudioComboPanel: View {
    @ObservedObject var model: DeckStudioComboModel
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let resolver: OnDeviceDeckResolver?
    let readOnly: Bool
    let add: (String, String, SpellbookDeck) -> Bool
    let inspect: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var approval: SpellbookDeck?
    @State private var selected: SpellbookVariant?
    @State private var feedback: String?
    private var input: SpellbookDeck? { DeckStudioSpellbookInput.make(draft, resolver: resolver) }
    private var snapshot: SpellbookSnapshot? { model.snapshot?.deck == input ? model.snapshot : nil }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DeckStudioPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Discover the connections.").font(.title2.weight(.semibold))
                        Text("Commander Spellbook finds documented combos and nearby possibilities. Results are not EDHREC recommendations or proof a combo will execute in a game.")
                            .font(.subheadline).foregroundStyle(DeckStudioPalette.secondaryInk)
                        Text("A lookup shares resolved main-deck and commander names, quantities, and your network address with Commander Spellbook. Other sections, deck title and private notes stay here.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        Button(snapshot == nil ? "Find combos" : "Refresh this deck’s combos", systemImage: "sparkles") { approval = input }
                            .buttonStyle(DeckStudioButtonStyle()).disabled(input == nil || model.loading)
                            .accessibilityIdentifier("deckStudio.combos.lookup")
                        if input == nil {
                            Text("Choose commander(s) and resolve main-deck card names before looking up combos. You can still edit and save your draft.")
                                .font(.caption).foregroundStyle(DeckStudioPalette.warning)
                        }
                        Link("About Commander Spellbook", destination: URL(string: "https://commanderspellbook.com/about/")!).font(.caption)
                    }
                }
                if model.loading {
                    HStack {
                        ProgressView("Looking up combos…")
                        Spacer()
                        Button("Cancel") { model.cancel() }.frame(minHeight: 44)
                    }
                }
                if let error = model.error {
                    DeckStudioNotice(title: "Lookup unavailable", message: error, icon: "wifi.exclamationmark")
                }
                if let feedback { Text(feedback).font(.caption).accessibilityAddTraits(.updatesFrequently) }
                if let snapshot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(snapshot.loadedCount) results loaded").font(.headline)
                        Text("Commander Spellbook · \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        if let note = model.cacheNote { Text(note).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk) }
                        if snapshot.nextOffset != nil {
                            Text("More results exist. Counts below cover only the pages you have loaded.").font(.caption)
                        }
                    }
                    group(.included, snapshot: snapshot)
                    group(.almostIncluded, snapshot: snapshot)
                    if SpellbookGroup.allCases.filter(\.isOther).contains(where: { !snapshot.groups[$0, default: []].isEmpty }) {
                        DisclosureGroup("Other possibilities — require deck changes") {
                            VStack(spacing: 12) {
                                ForEach(SpellbookGroup.allCases.filter(\.isOther), id: \.self) { group($0, snapshot: snapshot) }
                            }.padding(.top, 12)
                        }
                    }
                    if snapshot.loadedCount == 0 {
                        DeckStudioNotice(title: "No documented matches returned", message: "This does not prove the deck has no combos. New or undocumented interactions may not be in this database.")
                    }
                    if snapshot.nextOffset != nil, snapshot.loadedCount < SpellbookAPI.maximumResults {
                        Button("Load next page") { model.analyze(approvedDeck: snapshot.deck, more: true) }
                            .buttonStyle(DeckStudioButtonStyle(primary: false)).disabled(model.loading)
                    } else if snapshot.nextOffset != nil {
                        Text("Local result limit reached. Continue on Commander Spellbook’s website.").font(.caption)
                    }
                    Button("Clear saved combo lookups", role: .destructive) { Task { await model.clear() } }.frame(minHeight: 44)
                    Text("XMage remains the rules authority. Named pieces, color identity and provider legality alone do not establish mana, timing, zones or a winning line.")
                        .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                }
            }.padding(20)
        }
        .task(id: input) { feedback = nil; await model.setInput(input) }
        .onDisappear { model.cancel() }
        .confirmationDialog("Send this deck to Commander Spellbook?", isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } }), titleVisibility: .visible) {
            if let deck = approval {
                Button("Send deck and find combos") {
                    approval = nil
                    guard deck == input else { feedback = "The deck changed. Review it before a new lookup."; return }
                    model.analyze(approvedDeck: deck)
                }
            }
            Button("Cancel", role: .cancel) { approval = nil }
        } message: {
            Text("This is an optional online lookup of the current main deck and commanders. It never changes your deck automatically.")
        }
        .sheet(item: $selected) { DeckStudioComboDetail(variant: $0) }
    }

    @ViewBuilder private func group(_ value: SpellbookGroup, snapshot: SpellbookSnapshot) -> some View {
        let variants = snapshot.groups[value, default: []]
        if !variants.isEmpty {
            Text("\(value.title) · \(variants.count)").font(.headline)
            ForEach(variants) { variant in
                let assessment = SpellbookAssessment.make(variant: variant, group: value, deck: snapshot.deck,
                    commanderColors: DeckStudioDraftPresentation.colors(draft, metadata: metadata),
                    canonicalName: { resolver?.canonicalCardName($0) })
                DeckStudioPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(variant.uses.map(\.card.name).joined(separator: " + "))
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(variant.produces.enumerated()), id: \.offset) { _, effect in
                            Text(effect.feature.name).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                        readiness(assessment)
                        Text(assessment.explanation).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(variant.uses.enumerated()), id: \.offset) { _, ingredient in
                                let canonical = resolver?.canonicalCardName(ingredient.card.name) ?? ingredient.card.name
                                Button { inspect(canonical) } label: {
                                    HStack(spacing: 10) {
                                        // Artwork uses the engine's name for this card, because a
                                        // provider spelling need not be an exact Scryfall name.
                                        if !dynamicType.isAccessibilitySize {
                                            DeckStudioArtwork(name: canonical).frame(width: 44, height: 61)
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                        }
                                        Text(ingredient.card.name).multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        Text("×\(ingredient.quantity)")
                                    }
                                }.font(.caption).frame(minHeight: 44)
                            }
                        }
                        Button("Prerequisites and steps", systemImage: "list.bullet.rectangle") { selected = variant }.frame(minHeight: 44)
                        if case .oneCardAway(let name) = assessment.readiness, !readOnly {
                            Menu {
                                Button("Add to main deck") { addCard(name, section: "deck", snapshot: snapshot) }
                                Button("Save to maybeboard") { addCard(name, section: "maybeboard", snapshot: snapshot) }
                            } label: { Label("Add \(name)", systemImage: "plus.circle").frame(minHeight: 44) }
                            .accessibilityIdentifier("deckStudio.combos.addMissing")
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder private func readiness(_ assessment: SpellbookAssessment) -> some View {
        switch assessment.readiness {
        case .namedPiecesPresent: Label("Named pieces present", systemImage: "checkmark.circle").font(.caption.weight(.semibold))
        case .oneCardAway: Label("One named card away", systemImage: "plus.circle").font(.caption.weight(.semibold))
        case .reviewRequirements: Label("Requirements need review", systemImage: "info.circle").font(.caption.weight(.semibold))
        }
    }
    private func addCard(_ name: String, section: String, snapshot: SpellbookSnapshot) {
        guard snapshot.deck == input, add(name, section, snapshot.deck) else {
            feedback = "The deck changed or the edit could not be saved. No automatic replacement was made."; return
        }
        feedback = "Added \(name) to \(section == "deck" ? "main deck" : "maybeboard"). Undo is available in Cards."
    }
}

private struct DeckStudioComboDetail: View {
    let variant: SpellbookVariant
    @Environment(\.dismiss) private var dismiss
    private func zones(_ values: [String]) -> String {
        let names = ["B": "Battlefield", "H": "Hand", "G": "Graveyard", "E": "Exile", "L": "Library", "C": "Command zone"]
        return values.map { names[$0] ?? $0 }.joined(separator: ", ")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Commander Spellbook").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    Text(variant.uses.map(\.card.name).joined(separator: " + ")).font(.title2.weight(.semibold))
                    section("Mana required", variant.manaNeeded)
                    ForEach(Array(variant.uses.enumerated()), id: \.offset) { _, row in
                        section("\(row.quantity) × \(row.card.name)",
                            ([zones(row.zoneLocations), row.mustBeCommander ? "Must be your commander" : "",
                              row.battlefieldCardState, row.exileCardState, row.graveyardCardState, row.libraryCardState])
                                .filter { !$0.isEmpty }.joined(separator: "\n"))
                    }
                    ForEach(Array(variant.requires.enumerated()), id: \.offset) { _, row in
                        section("Flexible requirement: \(row.quantity) × \(row.template.name)",
                            ([zones(row.zoneLocations), row.mustBeCommander ? "Must be your commander" : "",
                              row.battlefieldCardState, row.exileCardState, row.graveyardCardState, row.libraryCardState])
                                .filter { !$0.isEmpty }.joined(separator: "\n"))
                    }
                    section("Prerequisites", variant.easyPrerequisites)
                    section("Additional prerequisites", variant.notablePrerequisites)
                    section("Steps", variant.description)
                    section("Results", variant.produces.map(\.feature.name).joined(separator: "\n"))
                    section("Notes", variant.notes)
                    Text("Provider Commander legality: \(variant.legalities.commander.map { $0 ? "legal" : "not legal" } ?? "unknown"). This is not validation of your complete deck or execution in XMage.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    if let url = variant.websiteURL { Link("Read on Commander Spellbook", destination: url).frame(minHeight: 44) }
                }.padding(24).textSelection(.enabled)
            }.background(DeckStudioPalette.background).navigationTitle("Combo details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    @ViewBuilder private func section(_ title: String, _ value: String) -> some View {
        if !value.isEmpty { VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(value).font(.subheadline) } }
    }
}
