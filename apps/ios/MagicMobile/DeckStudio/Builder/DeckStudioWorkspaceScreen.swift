import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DeckStudioWorkspaceScreen: View {
    @StateObject private var model: DeckStudioEditorModel
    @StateObject private var browser = DeckStudioEDHRECModel()
    @StateObject private var combos = DeckStudioComboModel()
    @StateObject private var validation = DeckStudioValidationState()
    let metadata: NativeDeckMetadataCatalogue?
    let resolver: OnDeviceDeckResolver?
    @ObservedObject private var play: DeckStudioPlaySelection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compactLandscape: Bool { verticalSizeClass == .compact && !dynamicType.isAccessibilitySize }
    @State private var tab = "Cards"
    @State private var headerExpanded = true
    @State private var ideas = "Combos"
    @State private var query = ""
    @State private var grouping = "Type"
    @State private var sorting = "Name"
    @State private var sectionFilter = ""
    @State private var colorFilter = ""
    @State private var issueFilter: DeckStudioPreflight.Issue?
    @State private var showCommanderFirst = false
    @State private var offeredCommanderFirst = false
    @State private var showTextEditor = false
    @State private var listCopied = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var showBulkQuantity = false
    @State private var bulkQuantity = ""
    @State private var confirmBulkRemove = false
    @State private var rolePreferences = DeckStudioRolePreferences()
    @AppStorage("deckStudio.cards.layout.v1") private var cardLayout = "List"
    @State private var showSearch = false
    @State private var showValidation = false
    @State private var showCommander = false
    @State private var showBasics = false
    @State private var replacement: NativeDeckRow?
    @State private var inspection: InspectedCard?
    @State private var historyReview: HistoryReview?
    @State private var confirmClose = false
    @State private var showRename = false
    @State private var showArtworkPreferences = false
    @FocusState private var deckSearchFocused: Bool
    init(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Bool,
         metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?, play: DeckStudioPlaySelection) {
        _model = StateObject(wrappedValue: DeckStudioEditorModel(library: library, record: record, included: included, defaults: MagicMobilePreferences.current))
        self.metadata = metadata; self.resolver = resolver; self.play = play
    }
    private struct InspectedCard: Identifiable { let name: String; var id: String { name } }
    private struct HistoryReview: Identifiable {
        let game: DeckStudioRecordedGame
        let exactDeck: Bool
        let layoutFixture: Bool
        var id: UUID { game.id }
    }
    private func openHistory(_ game: DeckStudioRecordedGame, fixture: Bool) {
        historyReview = HistoryReview(game: game, exactDeck: signature == game.deck, layoutFixture: fixture)
    }
    private var deck: DeckList? { try? model.draft.deck() }
    private var signature: DeckStudioDeckSignature? {
        guard let deck, let resolver else { return nil }
        return try? DeckStudioPlayProjection(deck).signature(resolver)
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            let split = geometry.size.width >= 700 && !dynamicType.isAccessibilitySize && !model.readOnly
            if verticalSizeClass != .compact && !split && (tab == "Cards" || tab == "Playtest") {
                portraitScrollingWorkspace
            } else {
            VStack(spacing: 0) {
                if !compactLandscape && geometry.size.height > 500 { header.padding(.horizontal, 20).padding(.vertical, 12) }
                else if !compactLandscape {
                    HStack {
                        Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name).font(.headline).lineLimit(1)
                        Spacer()
                        Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(model.draft))).font(.caption)
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
                                DeckStudioPlaytestInsightsView(signature: signature, metadata: metadata, openMatch: openHistory)
                                DeckStudioSampleHandView(draft: model.draft, metadata: metadata, inspect: inspect)
                            }
                        }.padding(20)
                    }
                    .accessibilityIdentifier(tab == "Playtest" ? "deckStudio.playtest.list" : "deckStudio.analysis.list")
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
                                .accessibilityLabel(CardCountText.label(DeckStudioDraftPresentation.gameCount(model.draft)))
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
                        DeckStudioPlayMenuItem(selection: play, model: model)
                        Button("Validate & playtest", systemImage: "checkmark.shield") { showValidation = true }
                        Button("Change primary commander", systemImage: "crown") { showCommander = true }.disabled(model.readOnly || metadata == nil)
                        Button("Basic lands", systemImage: "leaf") { showBasics = true }.disabled(model.readOnly)
                        Button("Rename deck", systemImage: "pencil") { showRename = true }.disabled(model.readOnly)
                        Button("Artwork & privacy", systemImage: "photo") { showArtworkPreferences = true }
                        if let deck, let text = try? DeckStudioTextExport.text(deck) { ShareLink(item: text) { Label("Export plain text", systemImage: "doc.plaintext") } }
                        else { Text("Plain text unavailable · use JSON to preserve this draft") }
                        if let data = try? model.draft.exportJSON(), let json = String(data: data, encoding: .utf8) { ShareLink(item: json) { Label("Export native JSON", systemImage: "square.and.arrow.up") } }
                        Button("Edit as text", systemImage: "text.alignleft") { showTextEditor = true }.disabled(model.readOnly)
                        if let deck, let list = try? DeckStudioTextExport.text(deck) {
                            Button("Copy list", systemImage: "doc.on.doc") { copyList(list) }
                        }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                }
            }
            .deckStudioPlayFeedback(play, deckID: model.playDeckID, validation: validation, fix: fixDeck)
            .sheet(isPresented: $showSearch) {
                cardSearch(embedded: false)
            }
            .sheet(item: $inspection) { item in DeckStudioCardInspector(name: item.name, metadata: metadata?.card(named: item.name)) }
            .sheet(isPresented: $showCommanderFirst) {
                DeckStudioCommanderFirstPicker(metadata: metadata) { name in
                    model.change { try DeckStudioEditorOperations.startWithCommander(in: &$0, name: name) }
                }
            }
            .sheet(isPresented: $showTextEditor) {
                DeckStudioTextEditorSheet(draft: model.draft) { expected, next in
                    guard expected == model.draft else { return false }
                    return model.change { $0 = next }
                }
            }
            .alert("Set quantity", isPresented: $showBulkQuantity) {
                TextField("Quantity", text: $bulkQuantity).keyboardType(.numberPad)
                Button("Apply") { applyBulkQuantity() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Every selected card gets this quantity, from 1 to 2,000.") }
            .confirmationDialog("Remove the selected cards?", isPresented: $confirmBulkRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removeSelection() }
            } message: { Text("Undo brings them back.") }
            .overlay(alignment: .top) {
                if listCopied {
                    Label("List copied", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .foregroundStyle(DeckStudioPalette.surfaceElevated).background(DeckStudioPalette.ink, in: Capsule())
                        .padding(.top, 8).transition(.opacity).accessibilityAddTraits(.isStaticText)
                }
            }
            .task { await offerCommanderFirst() }
            .task(id: roleKey) { loadRolePreferences() }
            .onChange(of: tab) { _, value in if value == "Cards" { loadRolePreferences() } else { selecting = false; selection = [] } }
            // A fixed issue clears its filter, so the list never stays filtered to nothing.
            .onChange(of: model.draft) { _, _ in if let issueFilter, preflight.rows(issueFilter).isEmpty { self.issueFilter = nil } }
            // Presentation belongs to the workspace, not a lazy history row or
            // an orientation-specific branch which can disappear while covered.
            .fullScreenCover(item: $historyReview) { review in
                MatchHistoryDashboard(game: review.game, exactDeck: review.exactDeck,
                                      layoutFixture: review.layoutFixture, metadata: metadata)
            }
            .sheet(isPresented: $showCommander) { DeckStudioReplacementPicker(metadata: metadata, commander: true) { model.commander($0, keepOld: $1) } }
            .sheet(item: $replacement) { row in
                DeckStudioReplacementPicker(metadata: metadata, commander: false, colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata)) { name, _ in model.replace(rowID: row.id, name: name) }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { headerExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name)
                        .font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(model.draft)))
                        .font(.caption).monospacedDigit()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(headerExpanded ? 180 : 0))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Deck details")
                .accessibilityValue(headerExpanded ? "Expanded" : "Collapsed")
            if headerExpanded {
                expandedHeader.transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
            if headerExpanded {
                DeckStudioPreflightBar(preflight: preflight, filter: Binding(get: { issueFilter }, set: { value in
                    issueFilter = value
                    if value != nil { tab = "Cards" }
                }), chooseCommander: { if !model.readOnly { showCommanderFirst = true } })
                .padding(.top, 8)
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }
    private var expandedHeader: some View {
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
                DeckStudioPlayDeckButton(selection: play, model: model).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
    private var deckCount: some View {
        Text("\(CardCountText.label(DeckStudioDraftPresentation.gameCount(model.draft))) · Commander")
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
            if !model.readOnly { cardsBottomBar(showAdd: showAddButton) }
        }
    }

    /// Quick Add with Add cards, or the bulk actions while selecting. Compact
    /// landscape keeps the single Add cards button so the list keeps its height.
    @ViewBuilder private func cardsBottomBar(showAdd: Bool) -> some View {
        if selecting {
            DeckStudioBulkBar(count: liveSelection.count, move: moveSelection(to:),
                              setQuantity: { bulkQuantity = ""; showBulkQuantity = true },
                              remove: { confirmBulkRemove = true },
                              selectAll: { selection = Set(filteredRows(preflight).map(\.id)) })
                .padding(.horizontal, 20).padding(.vertical, 8)
        } else if showAdd {
            if compactLandscape { addCardsButton }
            else {
                DeckStudioQuickAddBar(metadata: metadata, model: model, openSearch: { showSearch = true })
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
    }

    /// Cards and Playtest share one portrait scroll: the artwork/header leaves the
    /// viewport while the workspace selector remains pinned above either content.
    private var portraitScrollingWorkspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header.padding(.horizontal, 20).padding(.vertical, 12)
                    .accessibilityIdentifier("deckStudio.deckHeader")
                if let error = model.error {
                    DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                        .padding(.horizontal, 20).padding(.bottom, 10)
                }
                Section {
                    if tab == "Cards" {
                        cardFilters
                        // This inner lazy stack does not pin its group headers over the tabs.
                        LazyVStack(alignment: .leading, spacing: 8) {
                            cardSections
                        }.padding(.horizontal, 20).padding(.bottom, 16)
                    } else {
                        LazyVStack(spacing: 16) {
                            DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay)
                            DeckStudioPlaytestInsightsView(signature: signature, metadata: metadata, openMatch: openHistory)
                            DeckStudioSampleHandView(draft: model.draft, metadata: metadata, inspect: inspect)
                        }.padding(20)
                    }
                } header: {
                    workspaceTabs.padding(.horizontal, 20).padding(.vertical, 8)
                        .background(DeckStudioPalette.background)
                        .accessibilityIdentifier("deckStudio.workspace.pinned")
                }
            }
        }
        // The pinned lazy section must be rebuilt when its tab changes. Keeping
        // one identity can leave the previous tab's header and rows on screen.
        .id(tab)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(tab == "Cards" ? "deckStudio.cards.list" : "deckStudio.playtest.list")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == "Cards" && !model.readOnly {
                cardsBottomBar(showAdd: true).padding(.top, 8).background(DeckStudioPalette.background)
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
                            Picker("Group cards", selection: $grouping) { ForEach(Self.groupings, id: \.self) { Text($0).tag($0) } }
                            Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } }
                            Button(cardLayout == "Grid" ? "Show as list" : "Show as grid", systemImage: cardLayout == "Grid" ? "list.bullet" : "square.grid.3x2") { toggleLayout() }
                            if !model.readOnly { Button(selecting ? "Done selecting" : "Select cards", systemImage: "checkmark.circle") { toggleSelecting() } }
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
                            Menu { Picker("Group cards", selection: $grouping) { ForEach(Self.groupings, id: \.self) { Text($0).tag($0) } } } label: { Label("Group", systemImage: "square.grid.2x2").frame(minHeight: 44) }
                            Menu { Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } } } label: { Label("Sort", systemImage: "arrow.up.arrow.down").frame(minHeight: 44) }
                            Button { toggleLayout() } label: { Image(systemName: cardLayout == "Grid" ? "list.bullet" : "square.grid.3x2").frame(width: 44, height: 44) }
                                .accessibilityLabel(cardLayout == "Grid" ? "Show as list" : "Show as grid").accessibilityIdentifier("deckStudio.cards.layout")
                            if !model.readOnly {
                                Button { toggleSelecting() } label: { Text(selecting ? "Done" : "Select").frame(minHeight: 44) }
                                    .accessibilityLabel(selecting ? "Done selecting" : "Select cards").accessibilityIdentifier("deckStudio.cards.select")
                            }
                            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!model.history.canUndo || model.readOnly).accessibilityLabel("Undo deck edit")
                            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!model.history.canRedo || model.readOnly).accessibilityLabel("Redo deck edit")
                        }.font(.caption)
                    }
                }
                if let issueFilter {
                    HStack {
                        Label("Showing only: \(issueFilter.badge)", systemImage: "exclamationmark.triangle").font(.caption.weight(.semibold))
                            .foregroundStyle(DeckStudioPalette.warning)
                        Spacer()
                        Button("Show all") { self.issueFilter = nil }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityElement(children: .contain)
                }
        }.padding(.horizontal, 20)
    }
    private static let groupings = ["Type", "Role", "Section", "Mana value", "Color", "Name"]
    private func toggleLayout() { cardLayout = cardLayout == "Grid" ? "List" : "Grid" }
    private func toggleSelecting() {
        selecting.toggle(); selection = []
        if selecting { deckSearchFocused = false }
    }

    @ViewBuilder private var cardSections: some View {
                    let check = preflight
                    let rows = filteredRows(check)
                    if model.draft.rows.isEmpty { ContentUnavailableView("A deck of possibilities", systemImage: "plus.rectangle.on.rectangle", description: Text("Add your commander and cards. Incomplete drafts are welcome.")) }
                    else if rows.isEmpty {
                        ContentUnavailableView("No matching cards", systemImage: "line.3.horizontal.decrease", description: Text("Clear the search or filters to see the full draft."))
                        Button("Clear search and filters") { query = ""; sectionFilter = ""; colorFilter = ""; issueFilter = nil }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                    }
                    ForEach(cardGroups(rows)) { group in
                        Section {
                            if cardLayout == "Grid" {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 150 : 100), spacing: 10, alignment: .top)],
                                          alignment: .leading, spacing: 12) {
                                    ForEach(group.rows) { gridTile($0, issues: check.issues(for: $0.id)) }
                                }
                            } else {
                                ForEach(group.rows) { cardRow($0, issues: check.issues(for: $0.id)) }
                            }
                        } header: {
                            HStack {
                                Text(group.title).font(.subheadline.weight(.semibold)); Spacer()
                                Text("\(group.count)").font(.caption).accessibilityLabel(CardCountText.label(group.count))
                            }
                                .padding(.vertical, compactLandscape ? 4 : 10).background(DeckStudioPalette.background)
                        }
                    }
    }
    @ViewBuilder private var deckFilterOptions: some View {
        Picker("Section", selection: $sectionFilter) { Text("All sections").tag(""); ForEach(Set(model.draft.rows.map(DeckStudioBoard.of)).sorted(), id: \.self) { Text($0.capitalized).tag($0) } }
        Picker("Card color", selection: $colorFilter) { Text("Any color").tag(""); ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { Text($0 == "C" ? "Colorless" : $0).tag($0) } }
        Button("Clear filters") { sectionFilter = ""; colorFilter = ""; issueFilter = nil }
    }
    private func cardRow(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
        Group {
            if selecting {
                Button { toggleSelection(row.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selection.contains(row.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(selection.contains(row.id) ? DeckStudioPalette.accent : DeckStudioPalette.secondaryInk)
                        identityContent(row, issues: issues)
                        Text("\(row.quantity)").font(.subheadline.monospacedDigit()).frame(minWidth: 20)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(row.cardName), quantity \(row.quantity)")
                    .accessibilityAddTraits(selection.contains(row.id) ? [.isSelected] : [])
            } else if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                cardIdentity(row, issues: issues)
                HStack { Spacer(); cardControls(row) }
            }
            } else {
                HStack(spacing: 8) {
                    cardIdentity(row, issues: issues).frame(maxWidth: .infinity, alignment: .leading)
                    cardControls(row)
                }
            }
        }.padding(8).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func cardIdentity(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
        Button { inspect(row.cardName) } label: {
            identityContent(row, issues: issues)
        }.buttonStyle(.plain).accessibilityLabel("Inspect \(row.cardName), quantity \(row.quantity)")
            .contextMenu { cardActions(row) } preview: { DeckStudioCardPreview(name: row.cardName, card: metadata?.card(named: row.cardName)) }
    }
    private func identityContent(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
            HStack(spacing: 8) {
                if !dynamicType.isAccessibilitySize { DeckStudioArtwork(name: row.cardName).frame(width: 38, height: 52).clipShape(RoundedRectangle(cornerRadius: 5)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.cardName).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let card = metadata?.card(named: row.cardName) {
                        if let cost = card.manaCost, !cost.isEmpty { NativeDeckManaCost(cost: cost) }
                        else { Text(card.typeLine ?? "Card").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk) }
                    } else { Text("Unknown card · tap to review").font(.caption2).foregroundStyle(DeckStudioPalette.warning) }
                    DeckStudioIssueBadges(issues: issues)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 52).contentShape(Rectangle())
    }
    private func gridTile(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
        Button { if selecting { toggleSelection(row.id) } else { inspect(row.cardName) } } label: {
            DeckStudioCardGridTile(row: row, card: metadata?.card(named: row.cardName), issues: issues,
                                   selected: selecting ? selection.contains(row.id) : nil)
        }.buttonStyle(DeckStudioArtworkButtonStyle())
            .accessibilityLabel(selecting ? "\(row.cardName), quantity \(row.quantity)" : "Inspect \(row.cardName), quantity \(row.quantity)")
            .accessibilityAddTraits(selecting && selection.contains(row.id) ? [.isSelected] : [])
            .contextMenu { if !selecting { cardActions(row) } } preview: { DeckStudioCardPreview(name: row.cardName, card: metadata?.card(named: row.cardName)) }
    }
    /// Long-press actions shared by list rows and grid tiles.
    @ViewBuilder private func cardActions(_ row: NativeDeckRow) -> some View {
        Button("Card details", systemImage: "info.circle") { inspect(row.cardName) }
        if !model.readOnly {
            Button("Add one", systemImage: "plus") { model.quantity(id: row.id, delta: 1) }
            Button("Remove one", systemImage: "minus") { model.quantity(id: row.id, delta: -1) }
            Button("Replace card", systemImage: "arrow.triangle.2.circlepath") { replacement = row }
            Menu("Move to…") { ForEach(DeckStudioBulkBar.destinations, id: \.section) { destination in Button(destination.title) { model.move(id: row.id, to: destination.section) } } }
            Button("Remove row", systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
        }
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
    private var preflight: DeckStudioPreflight { DeckStudioPreflight(draft: model.draft, metadata: metadata, resolver: resolver) }
    private func filteredRows(_ check: DeckStudioPreflight) -> [NativeDeckRow] {
        let flagged = issueFilter.map(check.rows)
        return model.draft.rows.filter { row in
            let card = metadata?.card(named: row.cardName)
            return (query.isEmpty || row.cardName.localizedCaseInsensitiveContains(query) || (card?.oracleText?.localizedCaseInsensitiveContains(query) ?? false)) &&
                (sectionFilter.isEmpty || DeckStudioBoard.of(row) == sectionFilter) &&
                (colorFilter.isEmpty || (colorFilter == "C" ? card?.colors?.isEmpty == true : card?.colors?.contains(colorFilter) == true)) &&
                (flagged == nil || flagged!.contains(row.id))
        }.sorted { a, b in
            if sorting == "Quantity", a.quantity != b.quantity { return a.quantity > b.quantity }
            if sorting == "Mana value" { let left = metadata?.card(named: a.cardName)?.manaValue ?? .infinity, right = metadata?.card(named: b.cardName)?.manaValue ?? .infinity; if left != right { return left < right } }
            return a.cardName == b.cardName ? a.id.uuidString < b.id.uuidString : a.cardName < b.cardName
        }
    }
    private struct CardGroup: Identifiable {
        let title: String
        let order: Double
        var rows: [NativeDeckRow]
        /// Quantities, or unique cards for Role groups where one card can sit in several.
        var count: Int
        var id: String { title }
    }
    /// Commanders first, then main-deck groups, then the other boards. A Role group
    /// lists a card under every role it has.
    private func cardGroups(_ rows: [NativeDeckRow]) -> [CardGroup] {
        let roles = grouping == "Role"
            ? DeckStudioRoleGroups.membership(rows: rows.filter { DeckStudioBoard.of($0) == "deck" }, metadata: metadata, overrides: rolePreferences.overrides)
            : [:]
        var groups: [String: CardGroup] = [:]
        for row in rows {
            for (title, order) in groupKeys(row, roles: roles) {
                groups[title, default: CardGroup(title: title, order: order, rows: [], count: 0)].rows.append(row)
            }
        }
        return groups.values.map { group in
            var group = group
            let byRole = grouping == "Role" && DeckStudioRoleGroups.order.contains(group.title)
            group.count = byRole ? DeckStudioRoleGroups.uniqueCards(group.rows) : group.rows.reduce(0) { $0 + $1.quantity }
            return group
        }.sorted { $0.order == $1.order ? $0.title < $1.title : $0.order < $1.order }
    }
    private func groupKeys(_ row: NativeDeckRow, roles: [UUID: [String]]) -> [(String, Double)] {
        let section = DeckStudioBoard.of(row)
        if section == "commanders" { return [("Commanders", -1)] }
        guard section == "deck" else { return [(section.capitalized, 2_000_000)] }
        let card = metadata?.card(named: row.cardName)
        switch grouping {
        case "Role":
            return (roles[row.id] ?? [DeckStudioRoleGroups.other]).map { title in
                (title, Double(DeckStudioRoleGroups.order.firstIndex(of: title) ?? DeckStudioRoleGroups.order.count))
            }
        case "Name", "Section": return [("Main deck", 1_000_001)]
        case "Mana value":
            guard let value = card?.manaValue else { return [("Unknown mana value", 1_000_001)] }
            return [("Mana value \(String(format: "%g", value))", min(value, 1_000_000))]
        case "Color": return [(card?.colors.map { colors in colors.isEmpty ? "Colorless" : ["W", "U", "B", "R", "G"].filter(colors.contains).joined(separator: " / ") } ?? "Unknown color", 1_000_001)]
        default:
            guard let types = card?.types else { return [("Unclassified", 1_000_001)] }
            return [(["LAND", "CREATURE", "PLANESWALKER", "INSTANT", "SORCERY", "ARTIFACT", "ENCHANTMENT", "BATTLE"].first(where: types.contains)?.capitalized ?? "Other types", 1_000_001)]
        }
    }
    private var roleKey: String { "deckStudio.roles.v1." + (model.record?.id ?? "new") }
    /// Your own role reviews live with the Analysis tab's role insights.
    private func loadRolePreferences() { rolePreferences = (try? DeckStudioRolePreferences.load(key: roleKey)) ?? DeckStudioRolePreferences() }
    private func offerCommanderFirst() async {
        guard !offeredCommanderFirst, model.record == nil, !model.readOnly, !model.recovered, model.draft.rows.isEmpty else { return }
        offeredCommanderFirst = true
        // Let the workspace finish presenting before the picker slides over it.
        try? await Task.sleep(for: .milliseconds(350))
        guard model.draft.rows.isEmpty else { return }
        showCommanderFirst = true
    }
    private var liveSelection: Set<UUID> { selection.intersection(model.draft.rows.map(\.id)) }
    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    private func moveSelection(to section: String) {
        let ids = liveSelection
        guard !ids.isEmpty else { return }
        model.change { try DeckStudioEditorOperations.moveRows(in: &$0, ids: ids, to: section) }
    }
    private func applyBulkQuantity() {
        let ids = liveSelection
        guard let value = Int(bulkQuantity.trimmingCharacters(in: .whitespaces)), (1...2000).contains(value) else {
            model.error = "Use a quantity from 1 to 2,000. Nothing was changed."; return
        }
        guard !ids.isEmpty else { return }
        model.change { try DeckStudioEditorOperations.setQuantity(in: &$0, ids: ids, quantity: value) }
    }
    private func removeSelection() {
        let ids = liveSelection
        guard !ids.isEmpty else { return }
        if model.change({ try DeckStudioEditorOperations.removeRows(in: &$0, ids: ids) }) { selection = [] }
    }
    private func copyList(_ text: String) {
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: true])
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { listCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { listCopied = false }
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
    /// The validation panel's Play runs the same flow as the header button. Its sheet
    /// closes first, so the flow's own sheet can present.
    private func preparePlay(_ playing: DeckList) {
        guard showValidation else { DeckStudioPlayAction.perform(play, model: model); return }
        showValidation = false
        Task { try? await Task.sleep(for: .milliseconds(450)); DeckStudioPlayAction.perform(play, model: model) }
    }
    /// Fix deck: back to the Cards tab, showing the named card when there is one.
    private func fixDeck(_ deckID: String?, _ cards: [String]) {
        showValidation = false; tab = "Cards"
        query = cards.count == 1 ? cards[0] : ""
    }
    private func inspect(_ name: String) { inspection = InspectedCard(name: name) }
}
