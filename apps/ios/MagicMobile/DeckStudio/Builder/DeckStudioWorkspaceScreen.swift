import SwiftUI

@MainActor
struct DeckStudioWorkspaceScreen: View {
    @StateObject private var model: DeckStudioEditorModel
    @StateObject private var browser = DeckStudioEDHRECModel()
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
    @State private var showSearch = false
    @State private var inspection: InspectedCard?
    @State private var confirmClose = false
    @State private var showRename = false

    init(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Bool,
         metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?, selectForPlay: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: DeckStudioEditorModel(library: library, record: record, included: included))
        self.metadata = metadata; self.resolver = resolver; self.selectForPlay = selectForPlay
    }
    private struct InspectedCard: Identifiable { let name: String; var id: String { name } }
    private var namesResolved: Bool {
        guard let resolver, let deck = try? model.draft.deck() else { return false }
        return (try? resolver.resolve(deck)) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header.padding(.horizontal, 20).padding(.vertical, 12)
                if let error = model.error {
                    DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                        .padding(.horizontal, 20).padding(.bottom, 10)
                }
                workspaceTabs.padding(.horizontal, 20).padding(.bottom, 12)
                if tab == "Cards" { cardsTab }
                else if tab == "Ideas" { ideasTab }
                else { DeckStudioAnalysisView(draft: model.draft, metadata: metadata, curveOnly: tab == "Curve", inspect: inspect) }
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
                        Button("Rename deck", systemImage: "pencil") { showRename = true }.disabled(model.readOnly)
                        if let data = try? model.draft.exportJSON(), let json = String(data: data, encoding: .utf8) {
                            ShareLink(item: json) { Label("Export native JSON", systemImage: "square.and.arrow.up") }
                        }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                }
            }
            .sheet(isPresented: $showSearch) { DeckStudioCardSearch(metadata: metadata, colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata), add: { model.add($0, section: $1) }) }
            .sheet(item: $inspection) { item in DeckStudioCardInspector(name: item.name, metadata: metadata?.card(named: item.name)) }
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
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.persistRecovery(); browser.pause() } }
            .onChange(of: tab) { _, value in if value != "Ideas" { browser.pause() } }
            .onChange(of: ideas) { _, value in if value != "EDHREC" { browser.pause() } }
            .onDisappear { model.persistRecovery(); browser.pause() }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }

    @ViewBuilder private var workspaceTabs: some View {
        if dynamicType.isAccessibilitySize {
            Picker("Deck workspace", selection: $tab) {
                ForEach(["Cards", "Ideas", "Curve", "Stats"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
        } else {
            Picker("Deck workspace", selection: $tab) {
                ForEach(["Cards", "Ideas", "Curve", "Stats"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicType.isAccessibilitySize {
                DeckStudioArtwork(name: DeckStudioDraftPresentation.commanders(model.draft).first ?? "")
                    .frame(width: 54, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name)
                    .font(.system(.title2, design: .serif).weight(.bold)).lineLimit(2)
                Text(DeckStudioDraftPresentation.commanders(model.draft).joined(separator: " • "))
                    .font(.caption).lineLimit(2).foregroundStyle(DeckStudioPalette.secondaryInk)
                HStack {
                    DeckStudioColorIdentity(colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata))
                    Text("\(DeckStudioDraftPresentation.gameCount(model.draft)) cards").font(.caption)
                }
                Text(model.saveLabel).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }
    private var cardsTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search this deck", text: $query).autocorrectionDisabled().accessibilityIdentifier("deckStudio.cards.search")
                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 8) {
                    Menu { Picker("Group cards", selection: $grouping) { ForEach(["Type", "Section", "Mana value", "Name"], id: \.self) { Text($0).tag($0) } } }
                        label: { Label("Group", systemImage: "square.grid.2x2").font(.caption).frame(minHeight: 44) }
                    Menu { Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } } }
                        label: { Label("Sort", systemImage: "arrow.up.arrow.down").font(.caption).frame(minHeight: 44) }
                    Spacer(minLength: 0)
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                        .disabled(!model.history.canUndo || model.readOnly).accessibilityLabel("Undo deck edit")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                        .disabled(!model.history.canRedo || model.readOnly).accessibilityLabel("Redo deck edit")
                }
            }.padding(.horizontal, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    if model.draft.rows.isEmpty {
                        ContentUnavailableView("A deck of possibilities", systemImage: "plus.rectangle.on.rectangle",
                            description: Text("Add your commander and cards. Incomplete drafts are welcome."))
                    } else if filteredRows.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(groupNames, id: \.self) { group in
                        Section {
                            ForEach(filteredRows.filter { groupName($0) == group }) { row in cardRow(row) }
                        } header: {
                            HStack {
                                Text(group).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(filteredRows.filter { groupName($0) == group }.reduce(0) { $0 + $1.quantity })").font(.caption)
                            }.padding(.vertical, 10).background(DeckStudioPalette.background)
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }.scrollDismissesKeyboard(.interactively)
            if !model.readOnly {
                Button { showSearch = true } label: { Label("Add cards", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(DeckStudioButtonStyle()).padding(.horizontal, 20).padding(.bottom, 12)
                    .disabled(metadata == nil).accessibilityIdentifier("deckStudio.addCards")
            }
        }
    }
    private func cardRow(_ row: NativeDeckRow) -> some View {
        HStack(spacing: 10) {
            Button { inspect(row.cardName) } label: {
                HStack(spacing: 10) {
                    DeckStudioArtwork(name: row.cardName).frame(width: 34, height: 48).clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.cardName).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                        Text(metadata?.card(named: row.cardName)?.typeLine ?? "Not in loaded metadata")
                            .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(2)
                        if let cost = metadata?.card(named: row.cardName)?.manaCost { Text(cost).font(.caption2.monospaced()) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("Inspect \(row.cardName), quantity \(row.quantity)")
            if model.readOnly { Text("×\(row.quantity)").font(.caption.monospacedDigit()) }
            else {
                HStack(spacing: 0) {
                    Button { model.quantity(id: row.id, delta: -1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Remove one \(row.cardName)")
                    Text("\(row.quantity)").font(.caption.monospacedDigit()).frame(minWidth: 16)
                    Button { model.quantity(id: row.id, delta: 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add one \(row.cardName)")
                }
            }
        }
        .padding(10).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Inspect card", systemImage: "eye") { inspect(row.cardName) }
            if !model.readOnly {
                Menu("Move to…") {
                    ForEach(["deck", "commanders", "companions", "sideboard", "maybeboard"], id: \.self) { destination in
                        Button(destination.capitalized) { model.move(id: row.id, to: destination) }
                    }
                }
                Button("Remove row", systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
            }
        }
    }
    private var filteredRows: [NativeDeckRow] {
        model.draft.rows.filter { query.isEmpty || $0.cardName.localizedCaseInsensitiveContains(query) || (metadata?.card(named: $0.cardName)?.oracleText?.localizedCaseInsensitiveContains(query) ?? false) }
            .sorted { a, b in
                if sorting == "Quantity", a.quantity != b.quantity { return a.quantity > b.quantity }
                if sorting == "Mana value" {
                    let left = metadata?.card(named: a.cardName)?.manaValue ?? .infinity
                    let right = metadata?.card(named: b.cardName)?.manaValue ?? .infinity
                    if left != right { return left < right }
                }
                return a.cardName == b.cardName ? a.id.uuidString < b.id.uuidString : a.cardName < b.cardName
            }
    }
    private var groupNames: [String] { Set(filteredRows.map(groupName)).sorted() }
    private func groupName(_ row: NativeDeckRow) -> String {
        let section = DeckStudioDraftPresentation.section(row)
        guard section == "deck" else { return section.capitalized }
        switch grouping {
        case "Name": return "Main deck"
        case "Section": return "Main deck"
        case "Mana value": return metadata?.card(named: row.cardName)?.manaValue.map { "Mana value \($0.formatted())" } ?? "Unknown mana value"
        default: return metadata?.card(named: row.cardName)?.typeLine?.components(separatedBy: " — ").first ?? "Unclassified"
        }
    }
    private var ideasTab: some View {
        VStack(spacing: 12) {
            Picker("Ideas source", selection: $ideas) {
                ForEach(["Insights", "EDHREC"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 20)
            if ideas == "EDHREC" { DeckStudioEDHRECPanel(model: browser, commanders: DeckStudioDraftPresentation.commanders(model.draft)) }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        DeckStudioPanel {
                            DeckStudioNotice(title: "MagicMobile Insights", message: "Structural facts from the bundled metadata, not EDHREC popularity or a deck-quality score.", icon: "sparkles")
                        }
                        DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect)
                        DeckStudioPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Playtest with real rules").font(.headline)
                                Text("Names are checked locally. The existing setup runs XMage’s Commander validator before starting a game. This draft has not been certified legal by the editor.")
                                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                                Button("Use in playtest setup") { preparePlay() }
                                    .buttonStyle(DeckStudioButtonStyle()).disabled(!namesResolved)
                            }
                        }
                    }.padding(20)
                }
            }
        }
    }
    private func preparePlay() {
        guard namesResolved else { return }
        if model.readOnly, let record = model.record {
            selectForPlay(record.id.hasPrefix("precon:") ? record.id : "local:\(record.id)")
        } else if let saved = model.save() { selectForPlay("local:\(saved.id)") }
    }
    private func inspect(_ name: String) { inspection = InspectedCard(name: name) }
}
