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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compactLandscape: Bool { verticalSizeClass == .compact && !dynamicType.isAccessibilitySize }
    @State private var tab = "Cards"
    @State private var ideas = "Combos"
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
    @State private var showArtworkPreferences = false
    @FocusState private var deckSearchFocused: Bool
    init(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Bool,
         metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?, selectForPlay: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: DeckStudioEditorModel(library: library, record: record, included: included, defaults: MagicMobilePreferences.current))
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
            GeometryReader { geometry in
            let split = geometry.size.width >= 700 && !dynamicType.isAccessibilitySize && !model.readOnly
            if verticalSizeClass != .compact && !split && tab == "Cards" {
                portraitCardsWorkspace
            } else {
            VStack(spacing: 0) {
                if !compactLandscape && geometry.size.height > 500 { header.padding(.horizontal, 20).padding(.vertical, 12) }
                else if !compactLandscape {
                    HStack {
                        Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name).font(.headline).lineLimit(1)
                        Spacer()
                        Text("\(DeckStudioDraftPresentation.gameCount(model.draft)) cards").font(.caption)
                        Text(model.saveLabel).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }.padding(.horizontal, 20).padding(.vertical, 6)
                }
                if let error = model.error { DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle").padding(.horizontal, 20).padding(.bottom, 10) }
                if !compactLandscape { workspaceTabs.padding(.horizontal, 20).padding(.bottom, 12) }
                if tab == "Cards" {
                    HStack(spacing: 0) {
                        if split {
                            cardSearch(embedded: true).frame(width: geometry.size.width * 0.48)
                            Divider()
                        }
                        cardsTab(showAddButton: !split)
                    }
                }
                else if tab == "Ideas" { ideasTab }
                else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if tab == "Analysis" {
                                DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect)
                                DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect)
                            } else {
                                DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay)
                                DeckStudioPlaytestInsightsView(signature: signature)
                            }
                        }.padding(20)
                    }
                }
            }
            }
            }
            .background(DeckStudioPalette.background.ignoresSafeArea())
            .navigationTitle("Deck Studio").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DeckStudioPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if compactLandscape {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 12) {
                            Text(model.draft.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Picker("Deck workspace", selection: $tab) {
                                ForEach(["Cards", "Ideas", "Analysis", "Playtest"], id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu).accessibilityIdentifier("deckStudio.workspace")
                            Text("\(DeckStudioDraftPresentation.gameCount(model.draft))").font(.caption).monospacedDigit()
                                .accessibilityLabel("\(DeckStudioDraftPresentation.gameCount(model.draft)) cards")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) { Button("Done") { if model.isDirty { confirmClose = true } else { dismiss() } }.accessibilityIdentifier("deckStudio.close") }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.readOnly { Button("Edit a copy") { model.makeEditableCopy() } }
                    else { Button("Save") { model.save() }.disabled(!model.canSave).accessibilityIdentifier("deckStudio.save") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DeckStudioOrganizationButton(recordID: model.record?.id, title: model.draft.name).id(model.record?.id ?? "new")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Validate & playtest", systemImage: "checkmark.shield") { showValidation = true }
                        Button("Change primary commander", systemImage: "crown") { showCommander = true }.disabled(model.readOnly || metadata == nil)
                        Button("Basic lands", systemImage: "leaf") { showBasics = true }.disabled(model.readOnly)
                        Button("Rename deck", systemImage: "pencil") { showRename = true }.disabled(model.readOnly)
                        Button("Artwork & privacy", systemImage: "photo") { showArtworkPreferences = true }
                        if let deck, let text = try? DeckStudioTextExport.text(deck) { ShareLink(item: text) { Label("Export plain text", systemImage: "doc.plaintext") } }
                        else { Text("Plain text unavailable · use JSON to preserve this draft") }
                        if let data = try? model.draft.exportJSON(), let json = String(data: data, encoding: .utf8) { ShareLink(item: json) { Label("Export native JSON", systemImage: "square.and.arrow.up") } }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                }
            }
            .sheet(isPresented: $showSearch) {
                cardSearch(embedded: false)
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
            .sheet(isPresented: $showArtworkPreferences) {
                NavigationStack {
                    Form { NativeArtworkPreferenceView() }
                        .navigationTitle("Artwork & privacy")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showArtworkPreferences = false } } }
                }.preferredColorScheme(.light)
            }
            .confirmationDialog("Save your changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Save and close") { if model.save() != nil { dismiss() } }.disabled(!model.canSave)
                Button("Keep recovery draft and close") { if model.persistRecovery() { dismiss() } }.disabled(model.recoveryBlocked)
                Button("Discard unsaved changes and close", role: .destructive) { model.discardUnsavedChanges(); dismiss() }
            } message: { Text(model.recoveryBlocked ? "Recovery is paused to preserve unreadable data. Save this deck before closing to keep your edits, or cancel to continue editing." : "Your existing saved deck is unchanged until you save. An incomplete deck can remain a local draft.") }
            .interactiveDismissDisabled(model.isDirty)
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() } }
            .onChange(of: tab) { _, value in if value != "Ideas" { browser.pause() } }
            .onChange(of: ideas) { _, value in if value != "EDHREC" { browser.pause() } }
            .onDisappear { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    @ViewBuilder private var workspaceTabs: some View {
        if dynamicType.isAccessibilitySize {
            Picker("Deck workspace", selection: $tab) { ForEach(["Cards", "Ideas", "Analysis", "Playtest"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
        } else {
            HStack(spacing: 4) {
                ForEach(["Cards", "Ideas", "Analysis", "Playtest"], id: \.self) { destination in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { tab = destination }
                    } label: {
                        Text(destination).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                            .foregroundStyle(tab == destination ? DeckStudioPalette.surface : DeckStudioPalette.secondaryInk)
                            .background(tab == destination ? DeckStudioPalette.ink : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == destination ? [.isSelected] : [])
                }
            }.padding(4).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .contain).accessibilityLabel("Deck workspace")
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicType.isAccessibilitySize {
                DeckStudioArtwork(name: DeckStudioDraftPresentation.commanders(model.draft).first ?? "")
                    .frame(width: 68, height: 96).clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: DeckStudioPalette.ink.opacity(0.12), radius: 8, y: 4)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name).font(.system(.title2, design: .default).weight(.bold)).tracking(-0.5).lineLimit(2)
                Text(DeckStudioDraftPresentation.commanders(model.draft).joined(separator: " • ")).font(.caption).lineLimit(2).foregroundStyle(DeckStudioPalette.secondaryInk)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        DeckStudioColorIdentity(colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata))
                        deckCount
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        DeckStudioColorIdentity(colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata))
                        deckCount
                    }
                }
                Text(model.saveLabel).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                Button { showValidation = true } label: { Label(currentValidationPassed ? "Validated · playtest" : "Validate & playtest", systemImage: currentValidationPassed ? "checkmark.shield.fill" : "checkmark.shield").font(.caption.weight(.semibold)).frame(minHeight: 44) }
            }
            Spacer(minLength: 0)
        }
    }
    private var deckCount: some View {
        Text("\(DeckStudioDraftPresentation.gameCount(model.draft)) cards · Commander")
            .font(.caption).monospacedDigit()
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: DeckStudioDraftPresentation.gameCount(model.draft))
    }
    private func cardSearch(embedded: Bool) -> some View {
        DeckStudioCardSearch(metadata: metadata, colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata), add: { model.add($0, section: $1) }, resolver: resolver, model: model, embedded: embedded)
    }
    private func cardsTab(showAddButton: Bool) -> some View {
        VStack(spacing: 0) {
            cardFilters
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: compactLandscape ? [] : [.sectionHeaders]) {
                    cardSections
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("deckStudio.cards.list")
            if !model.readOnly && showAddButton { addCardsButton }
        }
    }

    /// The collection owns a single vertical scroll in portrait. Only its workspace
    /// selector pins; card groups and editing tools naturally leave the viewport.
    private var portraitCardsWorkspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header.padding(.horizontal, 20).padding(.vertical, 12)
                    .accessibilityIdentifier("deckStudio.deckHeader")
                if let error = model.error {
                    DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                        .padding(.horizontal, 20).padding(.bottom, 10)
                }
                Section {
                    cardFilters
                    // This inner lazy stack does not pin its group headers over the tabs.
                    LazyVStack(alignment: .leading, spacing: 8) {
                        cardSections
                    }.padding(.horizontal, 20).padding(.bottom, 16)
                } header: {
                    workspaceTabs.padding(.horizontal, 20).padding(.vertical, 8)
                        .background(DeckStudioPalette.background)
                        .accessibilityIdentifier("deckStudio.workspace.pinned")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("deckStudio.cards.list")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.readOnly {
                addCardsButton.padding(.top, 8).background(DeckStudioPalette.background)
            }
        }
    }

    private var addCardsButton: some View {
        Button { showSearch = true } label: { Label("Add cards", systemImage: "plus").frame(maxWidth: .infinity) }
            .buttonStyle(DeckStudioButtonStyle()).padding(.horizontal, 20).padding(.bottom, 12)
            .accessibilityIdentifier("deckStudio.addCards")
    }

    private var cardFilters: some View {
        VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search this deck", text: $query).autocorrectionDisabled().accessibilityIdentifier("deckStudio.cards.search")
                        .focused($deckSearchFocused).submitLabel(.search).onSubmit { deckSearchFocused = false }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("Clear deck search")
                    }
                    if compactLandscape {
                        Menu {
                            deckFilterOptions
                            Picker("Group cards", selection: $grouping) { ForEach(["Type", "Section", "Mana value", "Color", "Name"], id: \.self) { Text($0).tag($0) } }
                            Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } }
                            Button("Undo deck edit", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.history.canUndo || model.readOnly)
                            Button("Redo deck edit", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.history.canRedo || model.readOnly)
                        } label: {
                            Image(systemName: sectionFilter.isEmpty && colorFilter.isEmpty ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("Deck filters, grouping and editing").accessibilityIdentifier("deckStudio.cards.options")
                    }
                }.padding(.horizontal, 12).frame(minHeight: 44).background(.white, in: RoundedRectangle(cornerRadius: 12))
                if !compactLandscape {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            Menu {
                                deckFilterOptions
                            } label: { Label("Filter", systemImage: sectionFilter.isEmpty && colorFilter.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill").frame(minHeight: 44) }
                            Menu { Picker("Group cards", selection: $grouping) { ForEach(["Type", "Section", "Mana value", "Color", "Name"], id: \.self) { Text($0).tag($0) } } } label: { Label("Group", systemImage: "square.grid.2x2").frame(minHeight: 44) }
                            Menu { Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } } } label: { Label("Sort", systemImage: "arrow.up.arrow.down").frame(minHeight: 44) }
                            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!model.history.canUndo || model.readOnly).accessibilityLabel("Undo deck edit")
                            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!model.history.canRedo || model.readOnly).accessibilityLabel("Redo deck edit")
                        }.font(.caption)
                    }
                }
        }.padding(.horizontal, 20)
    }

    @ViewBuilder private var cardSections: some View {
                    if model.draft.rows.isEmpty { ContentUnavailableView("A deck of possibilities", systemImage: "plus.rectangle.on.rectangle", description: Text("Add your commander and cards. Incomplete drafts are welcome.")) }
                    else if filteredRows.isEmpty {
                        ContentUnavailableView("No matching cards", systemImage: "line.3.horizontal.decrease", description: Text("Clear the search or filters to see the full draft."))
                        Button("Clear search and filters") { query = ""; sectionFilter = ""; colorFilter = "" }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                    }
                    ForEach(groupNames, id: \.self) { group in
                        Section { ForEach(filteredRows.filter { groupName($0) == group }) { cardRow($0) } } header: {
                            HStack { Text(group).font(.subheadline.weight(.semibold)); Spacer(); Text("\(filteredRows.filter { groupName($0) == group }.reduce(0) { $0 + $1.quantity })").font(.caption) }
                                .padding(.vertical, compactLandscape ? 4 : 10).background(DeckStudioPalette.background)
                        }
                    }
    }
    @ViewBuilder private var deckFilterOptions: some View {
        Picker("Section", selection: $sectionFilter) { Text("All sections").tag(""); ForEach(Set(model.draft.rows.map(DeckStudioDraftPresentation.section)).sorted(), id: \.self) { Text($0.capitalized).tag($0) } }
        Picker("Card color", selection: $colorFilter) { Text("Any color").tag(""); ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { Text($0 == "C" ? "Colorless" : $0).tag($0) } }
        Button("Clear filters") { sectionFilter = ""; colorFilter = "" }
    }
    private func cardRow(_ row: NativeDeckRow) -> some View {
        Group {
            if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                cardIdentity(row)
                HStack { Spacer(); cardControls(row) }
            }
            } else {
                HStack(spacing: 8) {
                    cardIdentity(row).frame(maxWidth: .infinity, alignment: .leading)
                    cardControls(row)
                }
            }
        }.padding(8).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func cardIdentity(_ row: NativeDeckRow) -> some View {
        Button { inspect(row.cardName) } label: {
            HStack(spacing: 8) {
                if !dynamicType.isAccessibilitySize { DeckStudioArtwork(name: row.cardName).frame(width: 38, height: 52).clipShape(RoundedRectangle(cornerRadius: 5)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.cardName).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let card = metadata?.card(named: row.cardName) {
                        if let cost = card.manaCost, !cost.isEmpty { NativeDeckManaCost(cost: cost) }
                        else { Text(card.typeLine ?? "Card").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk) }
                    } else { Text("Unknown card · tap to review").font(.caption2).foregroundStyle(DeckStudioPalette.warning) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Inspect \(row.cardName), quantity \(row.quantity)")
    }
    private func cardControls(_ row: NativeDeckRow) -> some View {
        HStack(spacing: 0) {
            if !model.readOnly {
                    Button { model.quantity(id: row.id, delta: -1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Remove one \(row.cardName)")
            }
            Text("\(row.quantity)").font(.subheadline.monospacedDigit()).frame(minWidth: 20)
            if !model.readOnly {
                    Button { model.quantity(id: row.id, delta: 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add one \(row.cardName)")
                    Menu {
                        Button("Replace card", systemImage: "arrow.triangle.2.circlepath") { replacement = row }
                        Menu("Move to…") { ForEach(["deck", "commanders", "companions", "sideboard", "maybeboard"], id: \.self) { destination in Button(destination.capitalized) { model.move(id: row.id, to: destination) } } }
                        Button("Remove row", systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("More options for \(row.cardName)")
            }
        }.fixedSize(horizontal: true, vertical: false)
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
            Picker("Ideas source", selection: $ideas) { ForEach(["Combos", "EDHREC"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 20)
            if ideas == "EDHREC" { DeckStudioEDHRECPanel(model: browser, commanders: DeckStudioDraftPresentation.commanders(model.draft)) }
            else if ideas == "Combos" {
                DeckStudioComboPanel(model: combos, draft: model.draft, metadata: metadata, resolver: resolver, readOnly: model.readOnly, add: { name, section, approved in
                    guard approved == DeckStudioSpellbookInput.make(model.draft, resolver: resolver), resolver?.canonicalCardName(name) == name else { return false }
                    return model.add(name, section: section)
                }, inspect: inspect)
            }
        }
    }
    private func preparePlay(_ playing: DeckList) {
        guard let resolver, currentValidationPassed, let selection = model.preparePlayable(playing, resolver: resolver) else { return }
        showValidation = false; selectForPlay(selection)
    }
    private func inspect(_ name: String) { inspection = InspectedCard(name: name) }
}
