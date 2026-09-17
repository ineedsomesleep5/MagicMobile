import SwiftUI

@MainActor
struct DeckStudioWorkspaceScreen: View {
    @StateObject private var model: DeckStudioEditorModel
    @StateObject private var browser = DeckStudioEDHRECModel()
    @StateObject private var combos = DeckStudioComboModel()
    @StateObject private var validation = DeckStudioValidationState()
    let metadata: NativeDeckMetadataCatalogue?
    let resolver: OnDeviceDeckResolver?
    let selectForPlay: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var tab = "Cards"
    @State private var ideas = "Insights"
    @State private var query = ""
    @State private var grouping = "Type"
    @State private var sorting = "Name"
    @State private var sectionFilter = ""
    @State private var colorFilter = ""
    @State private var showSearch = false
    @State private var showValidation = false
    @State private var showCommander = false
    @State private var showBasics = false
    @State private var replacement: NativeDeckRow?
    @State private var inspection: InspectedCard?
    @State private var confirmClose = false
    @State private var showRename = false
    init(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Bool,
         metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?, selectForPlay: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: DeckStudioEditorModel(library: library, record: record, included: included))
        self.metadata = metadata; self.resolver = resolver; self.selectForPlay = selectForPlay
    }
    private struct InspectedCard: Identifiable { let name: String; var id: String { name } }
    private var deck: DeckList? { try? model.draft.deck() }
    private var signature: DeckStudioDeckSignature? {
        guard let deck, let resolver else { return nil }
        return try? DeckStudioPlayProjection(deck).signature(resolver)
    }
    private var currentValidationPassed: Bool {
        guard let deck, let resolver, let receipt = validation.receipt,
              let request = try? DeckStudioPlayProjection(deck).resolve(resolver).encoded() else { return false }
        return receipt.valid && receipt.matches(request: request, upstream: resolver.upstreamCommit, catalogue: resolver.catalogueHash, appBuild: DeckStudioValidationService.appBuild)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header.padding(.horizontal, 20).padding(.vertical, 12)
                if let error = model.error { DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle").padding(.horizontal, 20).padding(.bottom, 10) }
                workspaceTabs.padding(.horizontal, 20).padding(.bottom, 12)
                if tab == "Cards" { cardsTab }
                else if tab == "Ideas" { ideasTab }
                else {
                    ScrollView {
                        VStack(spacing: 16) {
                            DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: tab == "Curve", inspect: inspect)
                            if tab == "Stats" {
                                DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay)
                                DeckStudioPlaytestInsightsView(signature: signature)
                            }
                        }.padding(20)
                    }
                }
            }
            .background(DeckStudioPalette.background.ignoresSafeArea())
            .navigationTitle("Deck Studio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { if model.isDirty { confirmClose = true } else { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.readOnly { Button("Edit a copy") { model.makeEditableCopy() } }
                    else { Button("Save") { model.save() }.disabled(!model.canSave).accessibilityIdentifier("deckStudio.save") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Validate & playtest", systemImage: "checkmark.shield") { showValidation = true }
                        Button("Change primary commander", systemImage: "crown") { showCommander = true }.disabled(model.readOnly || metadata == nil)
                        Button("Basic lands", systemImage: "leaf") { showBasics = true }.disabled(model.readOnly)
                        Button("Rename deck", systemImage: "pencil") { showRename = true }.disabled(model.readOnly)
                        if let data = try? model.draft.exportJSON(), let json = String(data: data, encoding: .utf8) { ShareLink(item: json) { Label("Export native JSON", systemImage: "square.and.arrow.up") } }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                }
            }
            .sheet(isPresented: $showSearch) {
                DeckStudioCardSearch(metadata: metadata, colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata), add: { model.add($0, section: $1) }, resolver: resolver)
            }
            .sheet(item: $inspection) { item in DeckStudioCardInspector(name: item.name, metadata: metadata?.card(named: item.name)) }
            .sheet(isPresented: $showCommander) { DeckStudioReplacementPicker(metadata: metadata, commander: true) { model.commander($0, keepOld: $1) } }
            .sheet(item: $replacement) { row in DeckStudioReplacementPicker(metadata: metadata, commander: false) { name, _ in model.replace(rowID: row.id, name: name) } }
            .sheet(isPresented: $showBasics) { DeckStudioBasicLandsSheet(draft: model.draft) { model.basics($0, expected: $1) } }
            .sheet(isPresented: $showValidation) {
                NavigationStack {
                    ScrollView { DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay).padding(20) }
                        .background(DeckStudioPalette.background).navigationTitle("Validate & playtest").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showValidation = false } } }
                }.preferredColorScheme(.light)
            }
            .sheet(isPresented: $showRename) {
                NavigationStack {
                    Form { TextField("Deck name", text: Binding(get: { model.draft.name }, set: { name in model.change { $0.name = name } })) }
                        .navigationTitle("Rename deck").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRename = false } } }
                }.presentationDetents([.medium]).preferredColorScheme(.light)
            }
            .confirmationDialog("Save your changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Save and close") { if model.save() != nil { dismiss() } }.disabled(!model.canSave)
                Button("Keep recovery draft and close") { if model.persistRecovery() { dismiss() } }
            } message: { Text("Your existing saved deck is unchanged until you save. An incomplete deck can remain a local draft.") }
            .interactiveDismissDisabled(model.isDirty)
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() } }
            .onChange(of: tab) { _, value in if value != "Ideas" { browser.pause() } }
            .onChange(of: ideas) { _, value in if value != "EDHREC" { browser.pause() } }
            .onDisappear { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    @ViewBuilder private var workspaceTabs: some View {
        if dynamicType.isAccessibilitySize {
            Picker("Deck workspace", selection: $tab) { ForEach(["Cards", "Ideas", "Curve", "Stats"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
        } else {
            Picker("Deck workspace", selection: $tab) { ForEach(["Cards", "Ideas", "Curve", "Stats"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicType.isAccessibilitySize { DeckStudioArtwork(name: DeckStudioDraftPresentation.commanders(model.draft).first ?? "").frame(width: 54, height: 76).clipShape(RoundedRectangle(cornerRadius: 10)) }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name).font(.system(.title2, design: .serif).weight(.bold)).lineLimit(2)
                Text(DeckStudioDraftPresentation.commanders(model.draft).joined(separator: " • ")).font(.caption).lineLimit(2).foregroundStyle(DeckStudioPalette.secondaryInk)
                HStack {
                    DeckStudioColorIdentity(colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata))
                    Text("\(DeckStudioDraftPresentation.gameCount(model.draft)) cards · Commander").font(.caption)
                }
                Text(model.saveLabel).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                Button { showValidation = true } label: { Label(currentValidationPassed ? "Validated · playtest" : "Validate & playtest", systemImage: currentValidationPassed ? "checkmark.shield.fill" : "checkmark.shield").font(.caption.weight(.semibold)).frame(minHeight: 44) }
            }
            Spacer(minLength: 0)
        }
    }
    private var cardsTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack { Image(systemName: "magnifyingglass"); TextField("Search this deck", text: $query).autocorrectionDisabled().accessibilityIdentifier("deckStudio.cards.search") }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        Menu {
                            Picker("Section", selection: $sectionFilter) { Text("All sections").tag(""); ForEach(Set(model.draft.rows.map(DeckStudioDraftPresentation.section)).sorted(), id: \.self) { Text($0.capitalized).tag($0) } }
                            Picker("Card color", selection: $colorFilter) { Text("Any color").tag(""); ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { Text($0 == "C" ? "Colorless" : $0).tag($0) } }
                            Button("Clear filters") { sectionFilter = ""; colorFilter = "" }
                        } label: { Label("Filter", systemImage: sectionFilter.isEmpty && colorFilter.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill").frame(minHeight: 44) }
                        Menu { Picker("Group cards", selection: $grouping) { ForEach(["Type", "Section", "Mana value", "Color", "Name"], id: \.self) { Text($0).tag($0) } } } label: { Label("Group", systemImage: "square.grid.2x2").frame(minHeight: 44) }
                        Menu { Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } } } label: { Label("Sort", systemImage: "arrow.up.arrow.down").frame(minHeight: 44) }
                        Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!model.history.canUndo || model.readOnly).accessibilityLabel("Undo deck edit")
                        Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!model.history.canRedo || model.readOnly).accessibilityLabel("Redo deck edit")
                    }.font(.caption)
                }
            }.padding(.horizontal, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    if model.draft.rows.isEmpty { ContentUnavailableView("A deck of possibilities", systemImage: "plus.rectangle.on.rectangle", description: Text("Add your commander and cards. Incomplete drafts are welcome.")) }
                    else if filteredRows.isEmpty { ContentUnavailableView("No matching cards", systemImage: "line.3.horizontal.decrease", description: Text("Clear the search or filters to see the full draft.")) }
                    ForEach(groupNames, id: \.self) { group in
                        Section { ForEach(filteredRows.filter { groupName($0) == group }) { cardRow($0) } } header: {
                            HStack { Text(group).font(.subheadline.weight(.semibold)); Spacer(); Text("\(filteredRows.filter { groupName($0) == group }.reduce(0) { $0 + $1.quantity })").font(.caption) }
                                .padding(.vertical, 10).background(DeckStudioPalette.background)
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }.scrollDismissesKeyboard(.interactively)
            if !model.readOnly {
                Button { showSearch = true } label: { Label("Add cards", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(DeckStudioButtonStyle()).padding(.horizontal, 20).padding(.bottom, 12).disabled(metadata == nil).accessibilityIdentifier("deckStudio.addCards")
            }
        }
    }
    private func cardRow(_ row: NativeDeckRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if !dynamicType.isAccessibilitySize { DeckStudioArtwork(name: row.cardName).frame(width: 34, height: 48).clipShape(RoundedRectangle(cornerRadius: 5)) }
                Button { inspect(row.cardName) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.cardName).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                        Text(metadata?.card(named: row.cardName)?.typeLine ?? "Unresolved metadata — replace or review this card").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                        if let cost = metadata?.card(named: row.cardName)?.manaCost { Text(cost).font(.caption2.monospaced()) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Inspect \(row.cardName), quantity \(row.quantity)")
                Text("×\(row.quantity)").font(.caption.monospacedDigit())
            }
            if !model.readOnly {
                HStack {
                    Button { model.quantity(id: row.id, delta: -1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Remove one \(row.cardName)")
                    Button { model.quantity(id: row.id, delta: 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add one \(row.cardName)")
                    Spacer()
                    Menu {
                        Button("Replace card", systemImage: "arrow.triangle.2.circlepath") { replacement = row }
                        Menu("Move to…") { ForEach(["deck", "commanders", "companions", "sideboard", "maybeboard"], id: \.self) { destination in Button(destination.capitalized) { model.move(id: row.id, to: destination) } } }
                        Button("Remove row", systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
                    } label: { Label("Edit", systemImage: "ellipsis").font(.caption).frame(minHeight: 44) }
                }
            }
        }.padding(10).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var filteredRows: [NativeDeckRow] {
        model.draft.rows.filter { row in
            let card = metadata?.card(named: row.cardName)
            return (query.isEmpty || row.cardName.localizedCaseInsensitiveContains(query) || (card?.oracleText?.localizedCaseInsensitiveContains(query) ?? false)) &&
                (sectionFilter.isEmpty || DeckStudioDraftPresentation.section(row) == sectionFilter) &&
                (colorFilter.isEmpty || (colorFilter == "C" ? card?.colors?.isEmpty == true : card?.colors?.contains(colorFilter) == true))
        }.sorted { a, b in
            if sorting == "Quantity", a.quantity != b.quantity { return a.quantity > b.quantity }
            if sorting == "Mana value" { let left = metadata?.card(named: a.cardName)?.manaValue ?? .infinity, right = metadata?.card(named: b.cardName)?.manaValue ?? .infinity; if left != right { return left < right } }
            return a.cardName == b.cardName ? a.id.uuidString < b.id.uuidString : a.cardName < b.cardName
        }
    }
    private var groupNames: [String] { Set(filteredRows.map(groupName)).sorted { a, b in let left = groupOrder(a), right = groupOrder(b); return left == right ? a < b : left < right } }
    private func groupOrder(_ name: String) -> Double {
        if name == "Commanders" { return -1 }
        if name.hasPrefix("Mana value "), let number = Double(name.dropFirst(11)) { return min(number, 1_000_000) }
        return 1_000_001
    }
    private func groupName(_ row: NativeDeckRow) -> String {
        let section = DeckStudioDraftPresentation.section(row)
        guard section == "deck" else { return section.capitalized }
        let card = metadata?.card(named: row.cardName)
        switch grouping {
        case "Name", "Section": return "Main deck"
        case "Mana value": return card?.manaValue.map { "Mana value \(String(format: "%g", $0))" } ?? "Unknown mana value"
        case "Color": return card?.colors.map { colors in colors.isEmpty ? "Colorless" : ["W", "U", "B", "R", "G"].filter(colors.contains).joined(separator: " / ") } ?? "Unknown color"
        default:
            guard let types = card?.types else { return "Unclassified" }
            return ["LAND", "CREATURE", "PLANESWALKER", "INSTANT", "SORCERY", "ARTIFACT", "ENCHANTMENT", "BATTLE"].first(where: types.contains)?.capitalized ?? "Other types"
        }
    }
    private var ideasTab: some View {
        VStack(spacing: 12) {
            Picker("Ideas source", selection: $ideas) { ForEach(["Insights", "Combos", "EDHREC"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 20)
            if ideas == "EDHREC" { DeckStudioEDHRECPanel(model: browser, commanders: DeckStudioDraftPresentation.commanders(model.draft)) }
            else if ideas == "Combos" {
                DeckStudioComboPanel(model: combos, draft: model.draft, metadata: metadata, resolver: resolver, readOnly: model.readOnly, add: { name, section, approved in
                    guard approved == DeckStudioSpellbookInput.make(model.draft, resolver: resolver), resolver?.canonicalCardName(name) == name else { return false }
                    return model.add(name, section: section)
                }, inspect: inspect)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        DeckStudioNotice(title: "MagicMobile Insights", message: "Explained local analysis, not EDHREC popularity or a deck-quality score.", icon: "sparkles")
                        DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect)
                        DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect)
                        Button("Validate & playtest with real rules") { showValidation = true }.buttonStyle(DeckStudioButtonStyle())
                    }.padding(20)
                }
            }
        }
    }
    private func preparePlay(_ playing: DeckList) {
        guard let resolver, currentValidationPassed, let selection = model.preparePlayable(playing, resolver: resolver) else { return }
        showValidation = false; selectForPlay(selection)
    }
    private func inspect(_ name: String) { inspection = InspectedCard(name: name) }
}
