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
    /// The sideways title plate's quick check, folded into a chip until tapped.
    @State private var spreadQuickCheck = false
    /// An upright chapter change waiting to land on the chapter's top.
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
    @State private var confirmClose = false
    @State private var showRename = false
    @State private var showArtworkPreferences = false
    @FocusState private var deckSearchFocused: Bool
    /// The binder's two shelves: the deck's own cards, or every card there is to add (Caleb, 2026-10-06).
    @State private var shelf: BinderShelf = .deck
    /// The rail's mana value coins, for both shelves; none lit shows every card.
    @State private var manaFilter: Set<Int> = []
    @State private var catalogueQuery = ""
    @State private var catalogueType = ""
    @State private var withinIdentity = true
    init(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Bool,
         metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?, play: DeckStudioPlaySelection) {
        _model = StateObject(wrappedValue: DeckStudioEditorModel(library: library, record: record, included: included, defaults: MagicMobilePreferences.current))
        self.metadata = metadata; self.resolver = resolver; self.play = play
    }
    private struct InspectedCard: Identifiable { let name: String; var id: String { name } }
    /// Inside the book, leaving turns the page back to the library.
    private func leave() { if let grimoireClose { grimoireClose() } else { dismiss() } }
    /// The deck's chapters. There is no Playtest chapter (Caleb, 2026-10-06): a game against the AI is the
    /// playtest, and the game history lives in the player's profile.
    private static let chapters = ["Cards", "Ideas", "Analysis"]
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
            } else {
                // Upright: one page with the binder's head (Done, Save) written at its top, and the chapters as
                // index tabs down the binder's outer edge (Caleb chose concept B, 2026-10-06; the head is part of
                // the paper so it turns with the page).
                HStack(alignment: .top, spacing: 0) {
                    BinderPage(gutter: .leading) {
                        VStack(spacing: 0) {
                            binderBar
                            if verticalSizeClass != .compact && !split {
                                portraitScrollingWorkspace(height: geometry.size.height - 70)
                            } else {
                                compactWorkspace(split: split, size: geometry.size)
                            }
                        }
                    }
                    // The page lies over the tabs' tucked ends (BinderIndexTabs.tuck).
                    .zIndex(1)
                    indexTabs.padding(.top, 14)
                }
                .padding(.leading, 4).padding(.trailing, dynamicType.isAccessibilitySize ? 4 : 0).padding(.top, 4).padding(.bottom, 2)
            }
            }
            .binderScreen()
            .toolbar(.hidden, for: .navigationBar)
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
            .binderConfirm(DeckStudioPlayText.setQuantity, isPresented: $showBulkQuantity, message: DeckStudioPlayText.quantityMessage) {
                TextField("Quantity", text: $bulkQuantity).keyboardType(.numberPad)
                    .font(.system(size: 17, weight: .semibold, design: .serif)).multilineTextAlignment(.center)
                    .padding(.vertical, 10).background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Binder.brass, lineWidth: 1))
                Button("Apply") { applyBulkQuantity() }
            }
            .binderConfirm(DeckStudioPlayText.removeSelectedTitle, isPresented: $confirmBulkRemove, message: DeckStudioPlayText.removeSelectedMessage) {
                Button(DeckStudioPlayText.remove, role: .destructive) { removeSelection() }
            }
            .overlay(alignment: .top) {
                if listCopied {
                    BinderTag(text: DeckStudioPlayText.listCopied, material: .leather, accent: Color(red: 0.42, green: 0.85, blue: 0.40))
                        .padding(.top, 8).transition(.opacity).accessibilityAddTraits(.isStaticText)
                }
            }
            .task { await offerCommanderFirst() }
            .task(id: roleKey) { loadRolePreferences() }
            .onChange(of: tab) { _, value in if value == "Cards" { loadRolePreferences() } else { selecting = false; selection = [] } }
            // A fixed issue clears its filter, so the list never stays filtered to nothing.
            .onChange(of: model.draft) { _, _ in if let listFilter, listRows(listFilter).isEmpty { self.listFilter = nil } }
            .sheet(isPresented: $showCommander) { DeckStudioReplacementPicker(metadata: metadata, commander: true) { model.commander($0, keepOld: $1) } }
            .sheet(item: $replacement) { row in
                DeckStudioReplacementPicker(metadata: metadata, commander: false, colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata)) { name, _ in model.replace(rowID: row.id, name: name) }
            }
            .sheet(isPresented: $showBasics) { DeckStudioBasicLandsSheet(draft: model.draft) { model.basics($0, expected: $1) } }
            .sheet(isPresented: $showValidation) {
                NavigationStack {
                    ScrollView { DeckStudioValidationPanel(state: validation, deck: deck, resolver: resolver, play: preparePlay).padding(20) }
                        .background(GrimoirePaper())
                        .binderLeaf("Validate deck", trailing: BinderLeafAction(title: "Done") { showValidation = false })
                }.preferredColorScheme(.light).grimoirePage(.loose)
            }
            .sheet(isPresented: $showRename) {
                NavigationStack {
                    GrimoireForm { TextField("Deck name", text: Binding(get: { model.draft.name }, set: { name in model.change { $0.name = name } })) }
                        .binderLeaf("Rename deck", trailing: BinderLeafAction(title: "Done", identifier: "deckStudio.rename.done") { showRename = false })
                }.presentationDetents([.medium]).preferredColorScheme(.light).grimoirePage(.loose)
            }
            .sheet(isPresented: $showArtworkPreferences) {
                NavigationStack {
                    GrimoireForm { NativeArtworkPreferenceView() }
                        .binderLeaf("Artwork & privacy", trailing: BinderLeafAction(title: "Done") { showArtworkPreferences = false })
                }.preferredColorScheme(.light).grimoirePage(.loose)
            }
            .binderConfirm("Save your changes?", isPresented: $confirmClose,
                           message: model.recoveryBlocked ? "Recovery is paused to preserve unreadable data. Save this deck before closing to keep your edits, or cancel to continue editing." : "Your existing saved deck is unchanged until you save. An incomplete deck can remain a local draft.") {
                Button("Save and close") { if model.save() != nil { leave() } }.disabled(!model.canSave)
                Button("Keep recovery draft and close") { if model.persistRecovery() { leave() } }.disabled(model.recoveryBlocked)
                Button("Discard unsaved changes and close", role: .destructive) { model.discardUnsavedChanges(); leave() }
            }
            .interactiveDismissDisabled(model.isDirty)
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() } }
            .onChange(of: tab) { _, value in if value != "Ideas" { browser.pause() } }
            .onChange(of: ideas) { _, value in if value != "EDHREC", !spread { browser.pause() } }
            .onDisappear { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() }
            // The workspace's confirmations sit outside binderScreen(), so they get a host of their own.
            .binderOverlayHost()
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { wide = $0 }
        .grimoireSwipe(next: { turnChapter(by: 1) }, previous: { turnChapter(by: -1) })
    }
    /// The binder's head on the leather: Done as a leather strap with a buckle, Save as a brass plaque,
    /// then the deck's tags and everything else.
    private var binderBar: some View {
        HStack(spacing: 6) {
            Button("Done") { if model.isDirty { confirmClose = true } else { leave() } }
                .buttonStyle(BinderStrapButtonStyle())
                .accessibilityIdentifier("deckStudio.close")
            Spacer(minLength: 2)
            if model.readOnly {
                Button("Edit a copy") { model.makeEditableCopy() }.buttonStyle(BinderPlaqueButtonStyle())
            } else {
                Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .buttonStyle(BinderPlaqueButtonStyle()).disabled(!model.canSave)
                    .accessibilityIdentifier("deckStudio.save")
            }
            DeckStudioOrganizationButton(recordID: model.record?.id, title: model.draft.name, binder: true).id(model.record?.id ?? "new")
            moreMenu
        }
        // Written at the top of the page, like BinderHead.
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
    }
    private var moreMenu: some View {
        BinderMenu(accessibilityLabel: "More", identifier: "deckStudio.more") {
            let action = DeckStudioPlayAction(selection: play, model: model)
            BinderMenuButton(action.title, systemImage: action.kind == .playing ? "checkmark.circle" : "play.circle") {
                DeckStudioPlayAction.perform(play, model: model)
            }.disabled(!action.enabled)
            BinderMenuButton("Validate deck", systemImage: "checkmark.shield") { showValidation = true }
            BinderMenuButton("Change primary commander", systemImage: "crown") { showCommander = true }.disabled(model.readOnly || metadata == nil)
            BinderMenuButton("Basic lands", systemImage: "leaf") { showBasics = true }.disabled(model.readOnly)
            BinderMenuButton("Rename deck", systemImage: "pencil") { showRename = true }.disabled(model.readOnly)
            BinderMenuButton("Artwork & privacy", systemImage: "photo") { showArtworkPreferences = true }
            BinderMenuDivider()
            if let deck, let text = try? DeckStudioTextExport.text(deck) { BinderMenuShare(title: "Export plain text", systemImage: "doc.plaintext", item: text) }
            else { BinderMenuNote("Plain text unavailable · use JSON to preserve this draft") }
            if let data = try? model.draft.exportJSON(), let json = String(data: data, encoding: .utf8) { BinderMenuShare(title: "Export native JSON", systemImage: "square.and.arrow.up", item: json) }
            BinderMenuButton(DeckStudioPlayText.editAsText, systemImage: "text.alignleft") { showTextEditor = true }.disabled(model.readOnly)
            if let deck, let list = try? DeckStudioTextExport.text(deck) {
                BinderMenuButton(DeckStudioPlayText.copyList, systemImage: "doc.on.doc") { copyList(list) }
            }
        } label: { BinderPlaque(square: true) { Image(systemName: "ellipsis") } }
    }
    /// The deck's chapters as leather index tabs down the binder's outer edge. At the accessibility text
    /// sizes the chapters are a menu at the head of the page instead (`workspaceTabs`), so their names
    /// keep their size.
    @ViewBuilder private var indexTabs: some View {
        if !dynamicType.isAccessibilitySize {
            BinderIndexTabs(chapters: Self.chapters, selected: tab, tabHeight: spread ? 86 : 102, choose: chooseTab)
        }
    }
    @ViewBuilder private var workspaceTabs: some View {
        if dynamicType.isAccessibilitySize {
            BinderMenuPicker(title: "Deck workspace", selection: Binding(get: { tab }, set: chooseTab), options: Self.chapters.map { ($0, $0) })
        }
    }
    /// The deck's title plate: its name (which folds the plate away), and under it who leads it, how
    /// full it is, Play, and the quick check.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { headerExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name)
                        .font(.system(size: 24, weight: .bold, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if !headerExpanded {
                        Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(model.draft)))
                            .font(.caption).monospacedDigit()
                    }
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy)).foregroundStyle(Binder.engraved)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Binder.brass)).overlay(Circle().stroke(Binder.brassDeep, lineWidth: 0.8))
                        .rotationEffect(.degrees(headerExpanded ? 180 : 0))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Deck details")
                .accessibilityValue(headerExpanded ? "Expanded" : "Collapsed")
            if headerExpanded {
                expandedHeader.transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                preflightBar.padding(.top, 4).transition(reduceMotion ? .identity : .opacity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .binderPlate()
    }
    private var preflightBar: some View {
        DeckStudioPreflightBar(preflight: preflight, filter: Binding(get: { listFilter?.issue }, set: { value in
            listFilter = value.map(DeckStudioListFilter.quickCheck)
            if value != nil { tab = "Cards" }
        }), chooseCommander: { if !model.readOnly { showCommanderFirst = true } })
    }

    /// Sideways the binder lies open as a spread and each page has its own content: nothing runs across
    /// the fold (Caleb, 2026-10-05). Both pages run the binder's full height (Caleb, 2026-10-06: the head
    /// above the left page made the two pages look mismatched), so the head — Done, Save, tags, ⋯ — is
    /// written at the top of the left page. The left page carries the chapter's companion, the right page
    /// its main list, with the index tabs on its outer edge.
    ///
    ///     Cards     the compact title plate and the rail (shelf, search, tools, mana coins) | the cards
    ///     Ideas     combos                                                                | EDHREC
    ///     Analysis  the deck at a glance                                                  | roles
    private func spreadWorkspace(size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 6) {
            BinderPage(gutter: .trailing) {
                VStack(spacing: 0) {
                    binderBar
                    if let error = model.error {
                        DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                            .padding(.horizontal, 12).padding(.bottom, 6)
                    }
                    Group {
                        switch tab {
                        case "Cards":
                            ScrollView {
                                VStack(spacing: 10) {
                                    spreadHeader.padding(.horizontal, 12)
                                    binderRail(compact: true)
                                }.padding(.top, 2).padding(.bottom, 12)
                            }
                        case "Ideas":
                            combosPanel(embedded: false)
                        default:
                            ScrollView {
                                DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect).padding(16)
                            }
                        }
                    }
                    // Each chapter starts at the top of both pages.
                    .id(tab)
                }
            }
            BinderPage(gutter: .leading) {
                Group {
                    switch tab {
                    case "Cards":
                        cardsTab(showAddButton: true, rail: false)
                    case "Ideas":
                        DeckStudioEDHRECPanel(model: browser, commanders: DeckStudioDraftPresentation.commanders(model.draft))
                    default:
                        ScrollView {
                            DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect).padding(16)
                        }.accessibilityIdentifier("deckStudio.analysis.list")
                    }
                }
                .id(tab)
            }
            .zIndex(1)
            indexTabs.padding(.top, 14).padding(.leading, -6)   // against the page, not the spread's spacing
        }
        .padding(.top, 4).padding(.bottom, 2)
    }

    /// The title plate for a sideways page, where height is short: the commander's art beside the name,
    /// colours, the gauge and the save state, then Play beside the quick check, which opens on a tap.
    /// Everything shows whole (Caleb, 2026-10-06: no cut-off text or commander art on the left page).
    private var spreadHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                DeckStudioArtwork(name: DeckStudioDraftPresentation.commanders(model.draft).first ?? "", art: .exact(DeckStudioDraftPresentation.commanderPrinting(model.draft)))
                    .frame(width: 54, height: 75).clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Binder.brass, lineWidth: 2))
                    .overlay { BinderCorners(size: 11, style: .card).allowsHitTesting(false) }
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.draft.name.isEmpty ? "Untitled draft" : model.draft.name)
                        .font(.system(size: 20, weight: .bold, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        DeckStudioColorIdentity(colors: DeckStudioDraftPresentation.colors(model.draft, metadata: metadata))
                        Text(DeckStudioDraftPresentation.commanders(model.draft).joined(separator: " • "))
                            .font(.system(size: 12, design: .serif)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                    BinderGauge(count: DeckStudioDraftPresentation.gameCount(model.draft))
                    Text(model.saveLabel).font(.system(size: 11, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                DeckStudioPlayDeckButton(selection: play, model: model, compact: true)
                quickCheckChip
            }
            if spreadQuickCheck {
                preflightBar.transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .binderPlate()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deckStudio.deckHeader")
    }

    /// The quick check folded into one chip: the count and what it found. A tap opens the details.
    private var quickCheckChip: some View {
        let check = preflight
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { spreadQuickCheck.toggle() }
        } label: {
            BinderChip(title: check.issueCount == 0 ? "No issues" : "\(check.issueCount) to check",
                       icon: check.issueCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", chosen: spreadQuickCheck)
                .fixedSize()
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick check: \(check.summary)")
        .accessibilityValue(spreadQuickCheck ? "Expanded" : "Collapsed")
    }

    /// One page that is not the upright scroll: an iPad held upright (the card search beside the deck's
    /// cards) or the accessibility text sizes held sideways.
    private func compactWorkspace(split: Bool, size: CGSize) -> some View {
        VStack(spacing: 0) {
            workspaceTabs.padding(.horizontal, 16).padding(.top, 8)
            if size.height > 500 { header.padding(12) }
            if let error = model.error { DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle").padding(.horizontal, 16).padding(.bottom, 10) }
            if tab == "Cards" {
                HStack(spacing: 0) {
                    if split {
                        cardSearch(embedded: true).frame(width: size.width * 0.46)
                        Divider()
                    }
                    cardsTab(showAddButton: !split, rail: true)
                }
            }
            else if tab == "Ideas" { ideasTab() }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect)
                        DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect)
                    }.padding(16)
                }
                // Each chapter starts at its top, as upright.
                .id(tab)
                .accessibilityIdentifier("deckStudio.analysis.list")
            }
        }
    }
    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicType.isAccessibilitySize {
                DeckStudioArtwork(name: DeckStudioDraftPresentation.commanders(model.draft).first ?? "", art: .exact(DeckStudioDraftPresentation.commanderPrinting(model.draft)))
                    .frame(width: 72, height: 100).clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Binder.brass, lineWidth: 2.5))
                    .overlay { BinderCorners(size: 14, style: .card).allowsHitTesting(false) }
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
            }
            VStack(alignment: .leading, spacing: 6) {
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
                BinderGauge(count: DeckStudioDraftPresentation.gameCount(model.draft))
                Text(model.saveLabel).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                DeckStudioPlayDeckButton(selection: play, model: model).padding(.top, 2)
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
    /// The Cards chapter on a page of its own: the rail (unless it is on the facing page), the shelf, and
    /// Quick Add floating over the foot of the page, with the cards running under it.
    private func cardsTab(showAddButton: Bool, rail: Bool) -> some View {
        VStack(spacing: 0) {
            if rail { binderRail().padding(.top, 10) }
            ScrollView {
                shelfContent.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 16)
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("deckStudio.cards.list")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !model.readOnly { cardsBottomBar(showAdd: showAddButton).padding(.top, 18).background(pageFade) }
            }
        }
    }

    /// The deck's own cards, or every card to add.
    @ViewBuilder private var shelfContent: some View {
        if shelf == .all && !model.readOnly {
            DeckStudioBinderCatalogue(metadata: metadata, model: model, filters: catalogueFilters, inspect: inspect)
        } else {
            LazyVStack(alignment: .leading, spacing: 8) { cardSections }
        }
    }
    private var catalogueFilters: DeckStudioBinderCatalogue.Filters {
        .init(query: catalogueQuery, type: catalogueType, color: colorFilter, mana: manaFilter,
              identity: withinIdentity ? DeckStudioDraftPresentation.colors(model.draft, metadata: metadata) : nil)
    }

    /// Under the floating Quick Add: the page's own paper, fading in from clear so the cards slip under it
    /// (Caleb, 2026-10-06: no leather foot; the page runs from top to bottom).
    private var pageFade: some View {
        GrimoirePaper()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 0.35),
                                         .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Quick Add with Add cards, or the bulk actions while selecting. A narrow sideways page keeps the
    /// single Add cards button so the cards keep their height.
    @ViewBuilder private func cardsBottomBar(showAdd: Bool) -> some View {
        if selecting {
            DeckStudioBulkBar(count: liveSelection.count, move: moveSelection(to:),
                              setQuantity: { bulkQuantity = ""; showBulkQuantity = true },
                              remove: { confirmBulkRemove = true },
                              selectAll: { selection = Set(filteredRows(preflight).map(\.id)) })
                .padding(.horizontal, 12).padding(.bottom, 8)
                .background { GrimoirePaper(tone: .plate).clipShape(RoundedRectangle(cornerRadius: 10)) }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Binder.brass, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .padding(.horizontal, 8).padding(.bottom, 6)
        } else if showAdd {
            if compactLandscape { addCardsButton }
            else {
                DeckStudioQuickAddBar(metadata: metadata, model: model, openSearch: { showSearch = true }, binder: true)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }

    /// Every upright chapter shares one scroll down the page: the title plate leaves the page as it
    /// scrolls, and the chapters stay on the index tabs at the binder's edge. A chapter change lands
    /// on the chapter's own top, with the title plate scrolled away.
    private func portraitScrollingWorkspace(height: CGFloat) -> some View {
        // Ideas and Analysis fill at least the page, so the plate can always scroll away and a chapter
        // change always lands in the same place.
        let content = max(0, height)
        return ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // A container keeps the header's own identifiers (deckStudio.play, the quick
                // check); an identifier on a plain stack would replace every child's.
                header.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("deckStudio.deckHeader")
                if let error = model.error {
                    DeckStudioNotice(title: "Check this draft", message: error, icon: "exclamationmark.triangle")
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
                workspaceTabs.padding(.horizontal, 16).padding(.bottom, 8)
                DeckStudioTabsLanding(tab: tab, landing: $landingTab, proxy: proxy)
                switch tab {
                case "Cards":
                    binderRail().padding(.top, 2).padding(.bottom, 12)
                    shelfContent.padding(.horizontal, 12).padding(.bottom, 16)
                case "Ideas":
                    // The combo results keep their own lazy stack inside this plain one.
                    ideasTab(embedded: true, viewport: content).padding(.top, 4)
                        .frame(minHeight: content, alignment: .top)
                default:
                    VStack(spacing: 16) {
                        DeckStudioAnalysisContent(draft: model.draft, metadata: metadata, curveOnly: false, inspect: inspect)
                        DeckStudioRoleInsightsView(draft: model.draft, metadata: metadata, contextID: model.record?.id, inspect: inspect)
                    }.padding(16).frame(minHeight: content, alignment: .top)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(Self.listIdentifiers[tab] ?? "deckStudio.analysis.list")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == "Cards" && !model.readOnly {
                cardsBottomBar(showAdd: true).padding(.top, 18).background(pageFade)
            }
        }
        }
        // The chapter's lazy stack is rebuilt when the chapter changes, so the previous chapter's rows
        // never linger; the reader is rebuilt with it, so a landing scrolls only this chapter's view.
        .id(tab)
        .onChange(of: tab) { _, value in landingTab = value }
    }
    private static let listIdentifiers = ["Cards": "deckStudio.cards.list", "Ideas": "deckStudio.ideas.list",
                                          "Analysis": "deckStudio.analysis.list"]

    private var addCardsButton: some View {
        Button { showSearch = true } label: { Label(DeckStudioPlayText.addCards, systemImage: "plus").frame(maxWidth: .infinity) }
            .buttonStyle(BinderPlaqueButtonStyle()).padding(.horizontal, 12).padding(.bottom, 8)
            .accessibilityIdentifier("deckStudio.addCards")
    }

    /// The binder's brass rail (Caleb, 2026-10-06: keep the mana filter and the other filters, and choose
    /// between the deck's cards and cards to add): which shelf, the search, the tools, and the mana
    /// value coins. It is a plain row of the page, never a pinned header (flexible things laid out in a
    /// lazy list's pinned header kept that list re-measuring; see GRIMOIRE.md).
    /// `compact` (a sideways page) puts the shelf switch, as symbols, beside the search.
    private func binderRail(compact: Bool = false) -> some View {
        let search = BinderSearchField(placeholder: shelf == .all ? "Search all cards" : "Search this deck",
                                       text: shelf == .all ? $catalogueQuery : $query,
                                       identifier: shelf == .all ? "deckStudio.catalogue.search" : "deckStudio.cards.search",
                                       clearLabel: shelf == .all ? "Clear card search" : "Clear deck search",
                                       focus: $deckSearchFocused)
        return BinderRail {
            VStack(spacing: compact ? 6 : 8) {
                if compact {
                    HStack(spacing: 8) {
                        if !model.readOnly { BinderShelfSwitch(shelf: $shelf, compact: true) }
                        search
                    }
                } else {
                    if !model.readOnly { BinderShelfSwitch(shelf: $shelf) }
                    search
                }
                ViewThatFits(in: .horizontal) {
                    railTools(compact: false)
                    railTools(compact: true)
                }
                BinderManaFilter(selection: $manaFilter)
                if let listFilter, shelf == .deck {
                    HStack {
                        Label(listFilter.title, systemImage: "exclamationmark.triangle").font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.45))
                        Spacer()
                        Button(DeckStudioPlayText.showAll) { self.listFilter = nil }.font(.caption.weight(.bold)).frame(minHeight: 44)
                            .foregroundStyle(TavernPalette.parchment)
                            .accessibilityIdentifier("deckStudio.cards.showAll")
                    }.accessibilityElement(children: .contain)
                }
            }
        }
        .padding(.horizontal, 10)
    }

    /// The rail's brass tools. Narrow, Group, Sort, the layout and Select move into Filter's menu.
    private func railTools(compact: Bool) -> some View {
        let deckShelf = shelf == .deck || model.readOnly
        let filtersOn = !colorFilter.isEmpty || (deckShelf ? !sectionFilter.isEmpty : !catalogueType.isEmpty || !withinIdentity)
        return HStack(spacing: 0) {
            BinderMenu(accessibilityLabel: compact ? "Filters, grouping and layout" : "Filter", identifier: "deckStudio.cards.filter") {
                if deckShelf { deckFilterOptions } else { catalogueFilterOptions }
                if compact && deckShelf {
                    BinderMenuDivider()
                    BinderMenuPick("Group cards", selection: $grouping, options: Self.groupings.map { ($0, $0) })
                    BinderMenuPick("Sort cards", selection: $sorting, options: Self.sortings.map { ($0, $0) })
                    BinderMenuDivider()
                    BinderMenuButton(cardLayout == "Grid" ? DeckStudioPlayText.showAsList : DeckStudioPlayText.showAsGrid, systemImage: cardLayout == "Grid" ? "list.bullet" : "square.grid.3x2") { toggleLayout() }
                    if !model.readOnly { BinderMenuButton(selecting ? DeckStudioPlayText.doneSelecting : DeckStudioPlayText.selectCards, systemImage: "checkmark.circle") { toggleSelecting() } }
                }
            } label: {
                BinderPlaque(square: true, on: filtersOn) { Image(systemName: filtersOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") }
            }
            .frame(maxWidth: .infinity)
            if !compact {
                BinderMenu(accessibilityLabel: "Group") { BinderMenuPick("Group cards", selection: $grouping, options: Self.groupings.map { ($0, $0) }) }
                    label: { BinderPlaque(square: true) { Image(systemName: "square.stack.3d.up.fill") } }
                    .disabled(!deckShelf).frame(maxWidth: .infinity)
                BinderMenu(accessibilityLabel: "Sort") { BinderMenuPick("Sort cards", selection: $sorting, options: Self.sortings.map { ($0, $0) }) }
                    label: { BinderPlaque(square: true) { Image(systemName: "arrow.up.arrow.down") } }
                    .disabled(!deckShelf).frame(maxWidth: .infinity)
                Button { toggleLayout() } label: { Image(systemName: cardLayout == "Grid" ? "list.bullet" : "square.grid.3x2") }
                    .buttonStyle(BinderPlaqueButtonStyle(square: true)).disabled(!deckShelf)
                    .accessibilityLabel(cardLayout == "Grid" ? DeckStudioPlayText.showAsList : DeckStudioPlayText.showAsGrid)
                    .accessibilityIdentifier("deckStudio.cards.layout").frame(maxWidth: .infinity)
                if !model.readOnly {
                    Button { toggleSelecting() } label: { Image(systemName: "checkmark.circle") }
                        .buttonStyle(BinderPlaqueButtonStyle(square: true, on: selecting)).disabled(!deckShelf)
                        .accessibilityLabel(selecting ? DeckStudioPlayText.doneSelecting : DeckStudioPlayText.selectCards)
                        .accessibilityIdentifier("deckStudio.cards.select").frame(maxWidth: .infinity)
                }
            }
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(BinderPlaqueButtonStyle(square: true)).disabled(!model.history.canUndo || model.readOnly)
                .accessibilityLabel("Undo deck edit").frame(maxWidth: .infinity)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(BinderPlaqueButtonStyle(square: true)).disabled(!model.history.canRedo || model.readOnly)
                .accessibilityLabel("Redo deck edit").frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private var catalogueFilterOptions: some View {
        BinderMenuPick("Card type", selection: $catalogueType,
                       options: [("", "All types")] + ["Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker", "Battle"].map { ($0, $0) })
        BinderMenuColorPick(selection: $colorFilter)
        if DeckStudioDraftPresentation.colors(model.draft, metadata: metadata) != nil {
            BinderMenuDivider()
            BinderMenuToggle(DeckStudioPlayText.withinIdentity, isOn: $withinIdentity)
        }
        BinderMenuDivider()
        BinderMenuButton("Clear filters", systemImage: "xmark.circle") { catalogueType = ""; colorFilter = ""; manaFilter = []; withinIdentity = true }
    }
    private static let groupings = ["Type", "Role", "Section", "Mana value", "Color", "Name"]
    private static let sortings = ["Name", "Quantity", "Mana value"]
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
                        Text("Tap a card's right side or its plus to add a copy, its left side or its minus to take one away. Hold a card to see it large.")
                            .font(.footnote).italic().foregroundStyle(DeckStudioPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                            .accessibilityIdentifier("deckStudio.cards.tapHint")
                    }
                    if model.draft.rows.isEmpty { BinderEmptyLeaf(title: "A deck of possibilities", icon: "plus.rectangle.on.rectangle", message: "Add your commander and cards. Incomplete drafts are welcome.") }
                    else if rows.isEmpty {
                        BinderEmptyLeaf(title: "No matching cards", icon: "line.3.horizontal.decrease", message: "Clear the search or filters to see the full draft.")
                        Button("Clear search and filters") { query = ""; sectionFilter = ""; colorFilter = ""; manaFilter = []; listFilter = nil }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                    }
                    ForEach(cardGroups(rows)) { group in
                        Section {
                            if cardLayout == "Grid" {
                                // Just the cards, in sleeves, several to a row (Caleb, 2026-10-05 and 2026-10-06):
                                // three across an upright phone.
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 150 : 100), spacing: 10, alignment: .top)],
                                          alignment: .leading, spacing: 12) {
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
        BinderMenuPick("Section", selection: $sectionFilter,
                       options: [("", "All sections")] + Set(model.draft.rows.map(DeckStudioBoard.of)).sorted().map { ($0, $0.capitalized) })
        BinderMenuColorPick(selection: $colorFilter)
        BinderMenuDivider()
        BinderMenuButton("Clear filters", systemImage: "xmark.circle") { sectionFilter = ""; colorFilter = ""; manaFilter = []; listFilter = nil }
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
        BinderGuardedButton { inspect(row.cardName) } label: {
            identityContent(row, issues: issues)
        }.buttonStyle(.plain).accessibilityLabel("Inspect \(row.cardName), quantity \(row.quantity)")
            .binderContextMenu { cardActions(row) }
    }
    private func identityContent(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
            HStack(spacing: 8) {
                if !dynamicType.isAccessibilitySize { DeckStudioArtwork(name: row.cardName, art: .exact(row.printing)).frame(width: 38, height: 52).clipShape(RoundedRectangle(cornerRadius: 5)) }
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
    /// One card of the deck in its sleeve. While the deck is being edited, tapping the right half of a
    /// card (or the plus under it) adds a copy and the left half (or the minus) takes one away; the last
    /// copy removes the card, and Undo brings it back. A long press shows the card and everything else
    /// that can be done with it. A read-only deck's cards open on a tap; while selecting, a tap selects.
    private func gridTile(_ row: NativeDeckRow, issues: [DeckStudioPreflight.Issue]) -> some View {
        BinderSleeve(name: row.cardName, quantity: row.quantity, card: metadata?.card(named: row.cardName),
                     notes: issues.map(\.badge), selected: selecting ? selection.contains(row.id) : nil,
                     canEdit: !model.readOnly,
                     tapLabel: selecting ? "\(row.cardName), quantity \(row.quantity)" : "Inspect \(row.cardName), quantity \(row.quantity)",
                     art: .exact(row.printing),
                     add: { model.quantity(id: row.id, delta: 1); tapHintSeen = true },
                     remove: { model.quantity(id: row.id, delta: -1); tapHintSeen = true },
                     tap: { if selecting { toggleSelection(row.id) } else { inspect(row.cardName) } })
            .binderContextMenu(enabled: !selecting) { cardActions(row) }
    }
    /// Long-press actions shared by list rows and grid tiles.
    @ViewBuilder private func cardActions(_ row: NativeDeckRow) -> some View {
        BinderMenuHeading(row.cardName)
        BinderMenuButton(DeckStudioPlayText.cardDetails, systemImage: "info.circle") { inspect(row.cardName) }
        if !model.readOnly {
            BinderMenuButton(DeckStudioPlayText.addOne, systemImage: "plus") { model.quantity(id: row.id, delta: 1) }
            BinderMenuButton(DeckStudioPlayText.removeOne, systemImage: "minus") { model.quantity(id: row.id, delta: -1) }
            BinderMenuButton(DeckStudioPlayText.replaceCard, systemImage: "arrow.triangle.2.circlepath") { replacement = row }
            BinderMenuSubmenu(DeckStudioPlayText.moveTo, systemImage: "arrow.right.doc.on.clipboard") {
                ForEach(DeckStudioBulkBar.destinations, id: \.section) { destination in BinderMenuButton(destination.title) { model.move(id: row.id, to: destination.section) } }
            }
            BinderMenuDivider()
            BinderMenuButton(DeckStudioPlayText.removeRow, systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
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
                    BinderMenu(accessibilityLabel: "More options for \(row.cardName)") {
                        BinderMenuButton("Replace card", systemImage: "arrow.triangle.2.circlepath") { replacement = row }
                        BinderMenuSubmenu("Move to…", systemImage: "arrow.right.doc.on.clipboard") {
                            ForEach(["deck", "commanders", "companions", "sideboard", "maybeboard"], id: \.self) { destination in BinderMenuButton(destination.capitalized) { model.move(id: row.id, to: destination) } }
                        }
                        BinderMenuButton("Remove row", systemImage: "trash", role: .destructive) { model.remove(id: row.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
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
                BinderManaFilter.matches(card?.manaValue, manaFilter) &&
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
        showValidation = false; tab = "Cards"; shelf = .deck; query = ""; sectionFilter = ""; colorFilter = ""; manaFilter = []
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
