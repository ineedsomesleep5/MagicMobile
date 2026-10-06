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
    @Environment(\.grimoireClose) private var grimoireClose
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compactLandscape: Bool { verticalSizeClass == .compact && !dynamicType.isAccessibilitySize }
    /// Sideways the book lies open as a spread: two pages, each with its own content.
    @State private var wide = UIScreen.main.bounds.width > UIScreen.main.bounds.height
    private var spread: Bool { wide && !dynamicType.isAccessibilitySize }   // Grimoire.isSpread
    @State private var tab = "Cards"
    @State private var headerExpanded = true
    /// The pinned workspace tabs' measured height (portrait).
    @State private var tabsHeight: CGFloat = 68
    /// A portrait tab change waiting to land on the pinned tabs.
    @State private var landingTab: String?
    @State private var ideas = "Combos"
    @State private var query = ""
    @State private var grouping = "Type"
    @State private var sorting = "Name"
    @State private var sectionFilter = ""
    @State private var colorFilter = ""
    @State private var listFilter: DeckStudioListFilter?
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
    /// The book shows a deck as its cards' full art (Caleb, 2026-10-05); the list is one tap away.
    @AppStorage("deckStudio.cards.layout.v1") private var cardLayout = "Grid"
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
    /// Inside the book, leaving turns the page back to the library.
    private func leave() { if let grimoireClose { grimoireClose() } else { dismiss() } }
    private static let chapters = ["Cards", "Ideas", "Analysis", "Playtest"]
    /// A chapter change turns the page: forward for a later chapter, back for an earlier one.
    private func chooseTab(_ destination: String) {
        guard destination != tab else { return }
        let forward = (Self.chapters.firstIndex(of: destination) ?? 0) > (Self.chapters.firstIndex(of: tab) ?? 0)
        GrimoireStage.shared.turnPage(forward: forward) { tab = destination }
    }
    /// A swipe turns to the next chapter or the one before; back past the first chapter is the
    /// library's page again (asking about unsaved changes first, like Done).
    private func turnChapter(by step: Int) {
        guard let index = Self.chapters.firstIndex(of: tab) else { return }
        if Self.chapters.indices.contains(index + step) { chooseTab(Self.chapters[index + step]) }
        else if step < 0, grimoireClose != nil { if model.isDirty { confirmClose = true } else { leave() } }
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
            if spread {
                spreadWorkspace(size: geometry.size)
            } else if verticalSizeClass != .compact && !split {
                portraitScrollingWorkspace(height: geometry.size.height)
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
                else if tab == "Ideas" { ideasTab() }
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
                    // Each tab starts at its top, as in portrait.
                    .id(tab)
                    .accessibilityIdentifier(tab == "Playtest" ? "deckStudio.playtest.list" : "deckStudio.analysis.list")
                }
            }
            }
            }
            .background(GrimoirePaper().ignoresSafeArea())
            .navigationTitle("Deck Studio").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GrimoirePaper.barStyle, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // Nothing in the middle of the bar: the deck's name is on the page itself, and on a spread the
                // middle is the fold. (The system would otherwise squeeze a truncated title in there.)
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                ToolbarItem(placement: .topBarLeading) { Button("Done") { if model.isDirty { confirmClose = true } else { leave() } }.accessibilityIdentifier("deckStudio.close") }
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
                        Button(DeckStudioPlayText.editAsText, systemImage: "text.alignleft") { showTextEditor = true }.disabled(model.readOnly)
                        if let deck, let list = try? DeckStudioTextExport.text(deck) {
                            Button(DeckStudioPlayText.copyList, systemImage: "doc.on.doc") { copyList(list) }
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
            .alert(DeckStudioPlayText.setQuantity, isPresented: $showBulkQuantity) {
                TextField("Quantity", text: $bulkQuantity).keyboardType(.numberPad)
                Button("Apply") { applyBulkQuantity() }
                Button("Cancel", role: .cancel) {}
            } message: { Text(DeckStudioPlayText.quantityMessage) }
            .confirmationDialog(DeckStudioPlayText.removeSelectedTitle, isPresented: $confirmBulkRemove, titleVisibility: .visible) {
                Button(DeckStudioPlayText.remove, role: .destructive) { removeSelection() }
            } message: { Text(DeckStudioPlayText.removeSelectedMessage) }
            .overlay(alignment: .top) {
                if listCopied {
                    Label(DeckStudioPlayText.listCopied, systemImage: "checkmark").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .foregroundStyle(DeckStudioPalette.surfaceElevated).background(DeckStudioPalette.ink, in: Capsule())
                        .padding(.top, 8).transition(.opacity).accessibilityAddTraits(.isStaticText)
                }
            }
            .task { await offerCommanderFirst() }
            .task(id: roleKey) { loadRolePreferences() }
            .onChange(of: tab) { _, value in if value == "Cards" { loadRolePreferences() } else { selecting = false; selection = [] } }
            // A fixed issue clears its filter, so the list never stays filtered to nothing.
            .onChange(of: model.draft) { _, _ in if let listFilter, listRows(listFilter).isEmpty { self.listFilter = nil } }
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
                        .background(GrimoirePaper()).grimoireTitle("Validate & playtest").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showValidation = false } } }
                }.preferredColorScheme(.light).grimoirePage(.loose)
            }
            .sheet(isPresented: $showRename) {
                NavigationStack {
                    GrimoireForm { TextField("Deck name", text: Binding(get: { model.draft.name }, set: { name in model.change { $0.name = name } })) }
                        .grimoireTitle("Rename deck").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRename = false } } }
                }.presentationDetents([.medium]).preferredColorScheme(.light).grimoirePage(.loose)
            }
            .sheet(isPresented: $showArtworkPreferences) {
                NavigationStack {
                    GrimoireForm { NativeArtworkPreferenceView() }
                        .grimoireTitle("Artwork & privacy")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showArtworkPreferences = false } } }
                }.preferredColorScheme(.light).grimoirePage(.loose)
            }
            .confirmationDialog("Save your changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Save and close") { if model.save() != nil { leave() } }.disabled(!model.canSave)
                Button("Keep recovery draft and close") { if model.persistRecovery() { leave() } }.disabled(model.recoveryBlocked)
                Button("Discard unsaved changes and close", role: .destructive) { model.discardUnsavedChanges(); leave() }
            } message: { Text(model.recoveryBlocked ? "Recovery is paused to preserve unreadable data. Save this deck before closing to keep your edits, or cancel to continue editing." : "Your existing saved deck is unchanged until you save. An incomplete deck can remain a local draft.") }
            .interactiveDismissDisabled(model.isDirty)
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() } }
            .onChange(of: tab) { _, value in if value != "Ideas" { browser.pause() } }
            .onChange(of: ideas) { _, value in if value != "EDHREC", !spread { browser.pause() } }
            .onDisappear { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { wide = $0 }
        .grimoirePage()
        .grimoireSwipe(next: { turnChapter(by: 1) }, previous: { turnChapter(by: -1) })
    }
    /// The deck's chapters as ribbon markers at the head of the page.
    @ViewBuilder private var workspaceTabs: some View {
        if dynamicType.isAccessibilitySize {
            Picker("Deck workspace", selection: Binding(get: { tab }, set: chooseTab)) { ForEach(Self.chapters, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
        } else {
            GrimoireRibbons(chapters: Self.chapters, selected: tab, choose: chooseTab)
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
                preflightBar
                .padding(.top, 8)
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }
    private var preflightBar: some View {
        DeckStudioPreflightBar(preflight: preflight, filter: Binding(get: { listFilter?.issue }, set: { value in
            listFilter = value.map(DeckStudioListFilter.quickCheck)
            if value != nil { tab = "Cards" }
        }), chooseCommander: { if !model.readOnly { showCommanderFirst = true } })
    }

    /// Sideways the book lies open as a spread and each page has its own content: nothing runs across
    /// the fold (Caleb, 2026-10-05). The left page carries the chapter ribbons and the chapter's
    /// companion; the right page carries its main list.
    ///
    ///     Cards     the card search (editing, with room for it), else the title page | the deck's cards
    ///     Ideas     combos                                                          | EDHREC
    ///     Analysis  the deck at a glance                                            | roles
    ///     Playtest  the rules check and a sample hand                               | game history
    private func spreadWorkspace(size: CGSize) -> some View {
        // The search needs room: on a narrow spread the left page is the title page, and Add cards
        // on the right page opens the search as a leaf.
        let searchPage = size.width >= 700 && !model.readOnly
        return GrimoireSpread {
            VStack(spacing: 0) {
                workspaceTabs.padding(.horizontal, 20).padding(.bottom, 6)
                if let error = model.error {
                    DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                        .padding(.horizontal, 20).padding(.bottom, 8)
                }
                switch tab {
                case "Cards":
                    if searchPage { cardSearch(embedded: true) } else { titlePage }
                case "Ideas":
                    combosPanel(embedded: false)
                case "Analysis":
                    ScrollView {
                        DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect).padding(20)
                    }
                default:
                    ScrollView {
                        VStack(spacing: 16) {
                            DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay)
                            DeckStudioSampleHandView(draft: model.draft, metadata: metadata, inspect: inspect)
                        }.padding(20)
                    }
                }
            }
        } right: {
            switch tab {
            case "Cards":
                cardsTab(showAddButton: !searchPage)
            case "Ideas":
                DeckStudioEDHRECPanel(model: browser, commanders: DeckStudioDraftPresentation.commanders(model.draft))
            case "Analysis":
                ScrollView {
                    DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect).padding(20)
                }.accessibilityIdentifier("deckStudio.analysis.list")
            default:
                ScrollView {
                    DeckStudioPlaytestInsightsView(signature: signature, metadata: metadata, openMatch: openHistory).padding(20)
                }.accessibilityIdentifier("deckStudio.playtest.list")
            }
        }
        // Each chapter starts at the top of both pages.
        .id(tab)
    }

    /// A deck's title page: who leads it, what it holds, Play, and the quick check.
    private var titlePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                expandedHeader
                preflightBar
            }.padding(.horizontal, 20).padding(.vertical, 8)
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

    /// Every portrait tab shares one scroll: the artwork/header leaves the viewport while
    /// the workspace selector remains pinned above the content. A tab change lands on the
    /// pinned tabs, so the new tab starts at its top.
    private func portraitScrollingWorkspace(height: CGFloat) -> some View {
        // Ideas and Analysis fill at least the screen below the tabs, so the header can
        // always scroll away and a tab change always lands in the same place.
        let content = max(0, height - tabsHeight)
        return ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // A container keeps the header's own identifiers (deckStudio.play, the quick
                // check); an identifier on a plain stack would replace every child's.
                header.padding(.horizontal, 20).padding(.vertical, 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("deckStudio.deckHeader")
                if let error = model.error {
                    DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                        .padding(.horizontal, 20).padding(.bottom, 10)
                }
                DeckStudioTabsLanding(tab: tab, landing: $landingTab, proxy: proxy)
                Section {
                    switch tab {
                    case "Cards":
                        cardFilters
                        // This inner lazy stack does not pin its group headers over the tabs.
                        LazyVStack(alignment: .leading, spacing: 8) {
                            cardSections
                        }.padding(.horizontal, 20).padding(.bottom, 16)
                    case "Ideas":
                        // The combo results keep their own lazy stack inside this plain one.
                        ideasTab(embedded: true, viewport: content).padding(.top, 4)
                            .frame(minHeight: content, alignment: .top)
                    case "Analysis":
                        VStack(spacing: 16) {
                            DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect)
                            DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect)
                        }.padding(20).frame(minHeight: content, alignment: .top)
                    default:
                        // Three fixed panels: a plain stack. A lazy one here, between the pinned
                        // outer stack and the history's lazy rows, kept re-measuring near the end
                        // of the history under UI automation and hung the main thread.
                        VStack(spacing: 16) {
                            DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay)
                            DeckStudioPlaytestInsightsView(signature: signature, metadata: metadata, openMatch: openHistory)
                            DeckStudioSampleHandView(draft: model.draft, metadata: metadata, inspect: inspect)
                        }.padding(20)
                    }
                } header: {
                    workspaceTabs.padding(.horizontal, 20).padding(.vertical, 8)
                        .background(GrimoirePaper())
                        .background(GeometryReader { tabs in
                            Color.clear.onAppear { tabsHeight = tabs.size.height }
                                .onChange(of: tabs.size.height) { _, value in tabsHeight = value }
                        })
                        .accessibilityIdentifier("deckStudio.workspace.pinned")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(Self.listIdentifiers[tab] ?? "deckStudio.playtest.list")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == "Cards" && !model.readOnly {
                cardsBottomBar(showAdd: true).padding(.top, 8).background(GrimoirePaper())
            }
        }
        }
        // The pinned lazy section must be rebuilt when its tab changes. Keeping
        // one identity can leave the previous tab's header and rows on screen.
        // The reader is rebuilt with it, so a landing scrolls only this tab's view.
        .id(tab)
        .onChange(of: tab) { _, value in landingTab = value }
    }
    private static let listIdentifiers = ["Cards": "deckStudio.cards.list", "Ideas": "deckStudio.ideas.list",
                                          "Analysis": "deckStudio.analysis.list", "Playtest": "deckStudio.playtest.list"]

    private var addCardsButton: some View {
        Button { showSearch = true } label: { Label(DeckStudioPlayText.addCards, systemImage: "plus").frame(maxWidth: .infinity) }
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
                            Button(cardLayout == "Grid" ? DeckStudioPlayText.showAsList : DeckStudioPlayText.showAsGrid, systemImage: cardLayout == "Grid" ? "list.bullet" : "square.grid.3x2") { toggleLayout() }
                            if !model.readOnly { Button(selecting ? DeckStudioPlayText.doneSelecting : DeckStudioPlayText.selectCards, systemImage: "checkmark.circle") { toggleSelecting() } }
                            Button("Undo deck edit", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.history.canUndo || model.readOnly)
                            Button("Redo deck edit", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.history.canRedo || model.readOnly)
                        } label: {
                            Image(systemName: sectionFilter.isEmpty && colorFilter.isEmpty ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("Deck filters, grouping and editing").accessibilityIdentifier("deckStudio.cards.options")
                    }
                }.padding(.horizontal, 12).frame(minHeight: 44).grimoireField(cornerRadius: 12)
                if !compactLandscape {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            Menu {
                                deckFilterOptions
                            } label: { Label("Filter", systemImage: sectionFilter.isEmpty && colorFilter.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill").frame(minHeight: 44) }
                            Menu { Picker("Group cards", selection: $grouping) { ForEach(Self.groupings, id: \.self) { Text($0).tag($0) } } } label: { Label("Group", systemImage: "square.grid.2x2").frame(minHeight: 44) }
                            Menu { Picker("Sort cards", selection: $sorting) { ForEach(["Name", "Quantity", "Mana value"], id: \.self) { Text($0).tag($0) } } } label: { Label("Sort", systemImage: "arrow.up.arrow.down").frame(minHeight: 44) }
                            Button { toggleLayout() } label: { Image(systemName: cardLayout == "Grid" ? "list.bullet" : "square.grid.3x2").frame(width: 44, height: 44) }
                                .accessibilityLabel(cardLayout == "Grid" ? DeckStudioPlayText.showAsList : DeckStudioPlayText.showAsGrid).accessibilityIdentifier("deckStudio.cards.layout")
                            if !model.readOnly {
                                Button { toggleSelecting() } label: { Text(selecting ? "Done" : DeckStudioPlayText.select).frame(minHeight: 44) }
                                    .accessibilityLabel(selecting ? DeckStudioPlayText.doneSelecting : DeckStudioPlayText.selectCards).accessibilityIdentifier("deckStudio.cards.select")
                            }
                            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!model.history.canUndo || model.readOnly).accessibilityLabel("Undo deck edit")
                            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!model.history.canRedo || model.readOnly).accessibilityLabel("Redo deck edit")
                        }.font(.caption)
                    }
                }
                if let listFilter {
                    HStack {
                        Label(listFilter.title, systemImage: "exclamationmark.triangle").font(.caption.weight(.semibold))
                            .foregroundStyle(DeckStudioPalette.warning)
                        Spacer()
                        Button(DeckStudioPlayText.showAll) { self.listFilter = nil }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("deckStudio.cards.showAll")
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

    /// Until the first tap on a card changes its count, the page says what a tap does.
    @AppStorage("deckStudio.cards.tapHintSeen.v1") private var tapHintSeen = false

    @ViewBuilder private var cardSections: some View {
                    let check = preflight
                    let rows = filteredRows(check)
                    if cardLayout == "Grid", !model.readOnly, !tapHintSeen, !rows.isEmpty {
                        Text("Tap a card's right side to add a copy, its left side to take one away. Hold a card to see it large.")
                            .font(.footnote).italic().foregroundStyle(DeckStudioPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                            .accessibilityIdentifier("deckStudio.cards.tapHint")
                    }
                    if model.draft.rows.isEmpty { ContentUnavailableView("A deck of possibilities", systemImage: "plus.rectangle.on.rectangle", description: Text("Add your commander and cards. Incomplete drafts are welcome.")) }
                    else if rows.isEmpty {
                        ContentUnavailableView("No matching cards", systemImage: "line.3.horizontal.decrease", description: Text("Clear the search or filters to see the full draft."))
                        Button("Clear search and filters") { query = ""; sectionFilter = ""; colorFilter = ""; listFilter = nil }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                    }
                    ForEach(cardGroups(rows)) { group in
                        Section {
                            if cardLayout == "Grid" {
                                // Just the cards, several to a row (Caleb, 2026-10-05): four across on a big phone.
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 150 : 85), spacing: 10, alignment: .top)],
                                          alignment: .leading, spacing: 10) {
                                    ForEach(group.rows) { gridTile($0, issues: check.issues(for: $0.id)) }
                                }
                            } else {
                                ForEach(group.rows) { cardRow($0, issues: check.issues(for: $0.id)) }
                            }
                        } header: {
                            GrimoireSubheading(title: group.title, count: group.count)
                                .padding(.vertical, compactLandscape ? 4 : 10).background(GrimoirePaper())
                        }
                    }
    }
    @ViewBuilder private var deckFilterOptions: some View {
        Picker("Section", selection: $sectionFilter) { Text("All sections").tag(""); ForEach(Set(model.draft.rows.map(DeckStudioBoard.of)).sorted(), id: \.self) { Text($0.capitalized).tag($0) } }
        Picker("Card color", selection: $colorFilter) { Text("Any color").tag(""); ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { Text($0 == "C" ? "Colorless" : $0).tag($0) } }
        Button("Clear filters") { sectionFilter = ""; colorFilter = ""; listFilter = nil }
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
    /// One card of the deck as its full art. While the deck is being edited, tapping the right half of
    /// a card adds a copy and tapping the left half takes one away (the last copy removes the card;
    /// Undo brings it back). A long press shows the card and everything else that can be done with
    /// it. A read-only deck's cards open on a tap.
    private func gridTile(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
        let editable = !model.readOnly && !selecting
        return DeckStudioCardGridTile(row: row, card: metadata?.card(named: row.cardName), issues: issues,
                                      selected: selecting ? selection.contains(row.id) : nil, editable: editable)
            .overlay {
                if editable {
                    HStack(spacing: 0) {
                        Button { model.quantity(id: row.id, delta: -1); tapHintSeen = true } label: { Color.clear.contentShape(Rectangle()) }
                            .accessibilityLabel("Remove one \(row.cardName)")
                        Button { model.quantity(id: row.id, delta: 1); tapHintSeen = true } label: { Color.clear.contentShape(Rectangle()) }
                            .accessibilityLabel("Add one \(row.cardName)")
                    }.buttonStyle(.plain)
                } else {
                    Button { if selecting { toggleSelection(row.id) } else { inspect(row.cardName) } } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selecting ? "\(row.cardName), quantity \(row.quantity)" : "Inspect \(row.cardName), quantity \(row.quantity)")
                        .accessibilityAddTraits(selecting && selection.contains(row.id) ? [.isSelected] : [])
                }
            }
            .sensoryFeedback(.selection, trigger: row.quantity)
            .contextMenu { if !selecting { cardActions(row) } } preview: { DeckStudioCardPreview(name: row.cardName, card: metadata?.card(named: row.cardName)) }
    }
    /// Long-press actions shared by list rows and grid tiles.
    @ViewBuilder private func cardActions(_ row: NativeDeckRow) -> some View {
        Button(DeckStudioPlayText.cardDetails, systemImage: "info.circle") { inspect(row.cardName) }
        if !model.readOnly {
            Button(DeckStudioPlayText.addOne, systemImage: "plus") { model.quantity(id: row.id, delta: 1) }
            Button(DeckStudioPlayText.removeOne, systemImage: "minus") { model.quantity(id: row.id, delta: -1) }
            Button(DeckStudioPlayText.replaceCard, systemImage: "arrow.triangle.2.circlepath") { replacement = row }
            Menu(DeckStudioPlayText.moveTo) { ForEach(DeckStudioBulkBar.destinations, id: \.section) { destination in Button(destination.title) { model.move(id: row.id, to: destination.section) } } }
            Button(DeckStudioPlayText.removeRow, systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
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
    private func listRows(_ filter: DeckStudioListFilter, _ check: DeckStudioPreflight? = nil) -> Set<UUID> {
        filter.rows(check ?? preflight, draft: model.draft) { resolver?.canonicalCardName($0) }
    }
    private func filteredRows(_ check: DeckStudioPreflight) -> [NativeDeckRow] {
        let flagged = listFilter.map { listRows($0, check) }
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
            model.error = DeckStudioPlayText.quantityError; return
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
    /// Combos or EDHREC. Embedded in the portrait scroll, neither panel has a ScrollView of its
    /// own, and the page keeps a bounded height: the viewport below the tabs, less the source
    /// picker and the browser controls above it.
    private func ideasTab(embedded: Bool = false, viewport: CGFloat = 0) -> some View {
        VStack(spacing: 12) {
            GrimoireChoice(title: "Ideas source", options: [("Combos", "Combos"), ("EDHREC", "EDHREC")], selection: $ideas).padding(.horizontal, 20)
            if ideas == "EDHREC" {
                DeckStudioEDHRECPanel(model: browser, commanders: DeckStudioDraftPresentation.commanders(model.draft),
                                      embedded: embedded, webHeight: max(320, viewport - 150))
            }
            else if ideas == "Combos" { combosPanel(embedded: embedded) }
        }
    }
    private func combosPanel(embedded: Bool) -> some View {
        DeckStudioComboPanel(model: combos, draft: model.draft, metadata: metadata, resolver: resolver, readOnly: model.readOnly, add: { name, section, approved in
            guard approved == DeckStudioSpellbookInput.make(model.draft, resolver: resolver), resolver?.canonicalCardName(name) == name else { return false }
            return model.add(name, section: section)
        }, inspect: inspect, embedded: embedded)
    }
    /// The validation panel's Play runs the same flow as the header button. Its sheet
    /// closes first, so the flow's own sheet can present.
    private func preparePlay(_ playing: DeckList) {
        guard showValidation else { DeckStudioPlayAction.perform(play, model: model); return }
        showValidation = false
        Task { try? await Task.sleep(for: .milliseconds(450)); DeckStudioPlayAction.perform(play, model: model) }
    }
    /// Fix deck: back to the Cards tab, showing only the rows XMage named ("Showing only:
    /// Needs fixes" with Show all). A card the list cannot find leaves the list whole.
    private func fixDeck(_ deckID: String?, _ cards: [String]) {
        showValidation = false; tab = "Cards"; query = ""; sectionFilter = ""; colorFilter = ""
        let filter = DeckStudioListFilter.needsFixes(cards)
        listFilter = cards.isEmpty || listRows(filter).isEmpty ? nil : filter
    }
    private func inspect(_ name: String) { inspection = InspectedCard(name: name) }
}

/// The point a portrait tab change scrolls to: just above the pinned workspace tabs, so the
/// header is scrolled away and the new tab starts at its top. iOS 17 has no scroll position
/// API that can target the pinned tabs, so this uses ScrollViewReader.
private struct DeckStudioTabsLanding: View {
    let tab: String
    @Binding var landing: String?
    let proxy: ScrollViewProxy
    @State private var id = UUID()
    var body: some View {
        // One point tall: scrolling to a zero-height anchor here landed hundreds of points
        // past the tabs.
        Color.clear.frame(height: 1).id(id)
            // The tab change and this anchor's first layout come in either order.
            .onAppear(perform: land)
            .onChange(of: landing) { _, _ in land() }
    }
    private func land() {
        guard landing == tab else { return }
        landing = nil
        // The first scroll can stop short, or not move at all, while the rebuilt lazy stack
        // is still sizing its content (iOS 27 simulator), so repeat it briefly. Once it has
        // landed, a repeat does nothing.
        for delay in [0, 0.1, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { proxy.scrollTo(id, anchor: .top) }
        }
    }
}
