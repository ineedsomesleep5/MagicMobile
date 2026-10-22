import SwiftUI

/// The collection and editor share a quiet, artwork-led workshop.
@MainActor
struct DeckStudioRootView: View {
    @ObservedObject var library: DeckLibraryStore
    @Binding var selectedDeckID: String
    /// True while a game or match room is open: the playing deck cannot change then.
    var isGameLive: () -> Bool = { false }
    /// Opens straight into this deck (the setup screen's "Fix in Deck Studio").
    var focus: DeckStudioPlaySelection.FixRequest? = nil
    var preparePlay: () -> Void = {}
    /// Closes the book (the closing film); without it the screen dismisses itself.
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = DeckStudioLibraryQuery()
    @State private var tags: [String: [String]] = [:]
    @State private var tagLoadToken = UUID()
    @State private var favorites: Set<String> = []
    @State private var favoritesReadable = true
    @State private var metadata: NativeDeckMetadataCatalogue?
    @State private var resolver: OnDeviceDeckResolver?
    @State private var loadError: String?
    @State private var error: String?
    @State private var route: Route?
    @State private var pendingDelete: DeckLibraryRecord?
    @State private var showPreferences = false
    @FocusState private var searchFocused: Bool
    @StateObject private var play = DeckStudioPlaySelection()
    /// Each deck's check key; nil when the resolver cannot read the deck.
    @State private var checkKeys: [String: DeckStudioCheckKey?] = [:]
    @State private var openAfterImport: DeckLibraryRecord?
    @State private var focusHandled = false
    private let favoritesKey = "deckStudio.library.favorites.v1"

    private enum Route: Identifiable {
        case deck(DeckLibraryRecord?, Bool), importer
        var id: String {
            switch self { case .deck(let record, _): return record?.id ?? "new"; case .importer: return "import" }
        }
    }
    private struct Entry: Identifiable {
        let record: DeckLibraryRecord
        let included: Bool
        var id: String { included ? record.id : "local:\(record.id)" }
    }
    private var records: [Entry] {
        library.decks.map { Entry(record: $0, included: false) } + PreconCatalog.all.map {
            var record = DeckLibraryRecord(deck: $0.deckList, id: "precon:\($0.id)", sourceURL: $0.sourceURL.absoluteString)
            record.updatedAt = .distantPast
            return Entry(record: record, included: true)
        }
    }
    private func selectionID(_ record: DeckLibraryRecord, included: Bool) -> String { included ? record.id : "local:\(record.id)" }
    private var visible: [Entry] {
        let all = records
        let items = all.map { value in
            DeckStudioShelfItem(id: selectionID(value.record, included: value.included), name: value.record.name,
                commanders: DeckStudioDraftPresentation.commanders(NativeDeckDraft(deck: value.record.deckList)),
                tags: tags[value.record.id] ?? [], origin: value.included ? .included : .local, updatedAt: value.included ? nil : value.record.updatedAt)
        }
        let indices = Dictionary(uniqueKeysWithValues: all.enumerated().map { (selectionID($0.element.record, included: $0.element.included), $0.offset) })
        return query.apply(to: items, favorites: favorites).compactMap { item in indices[item.id].map { all[$0] } }
    }

    /// The deck whose details show beside the boxes (the playing deck until another is chosen).
    @State private var focused: String?
    private var focusedEntry: Entry? { records.first { $0.id == (focused ?? selectedDeckID) } ?? visible.first }

    /// Anything to tell the player: the library's notices and the artwork invitation.
    @ViewBuilder private var notices: some View {
        if let error = error ?? library.notice {
            DeckStudioNotice(title: "Your library is preserved", message: error, icon: "exclamationmark.triangle")
        }
        if let loadError {
            DeckStudioNotice(title: "Card catalogue unavailable", message: loadError)
            Button("Retry local catalogue", action: { Task { await loadCatalogue() } })
                .buttonStyle(ArenaPillButtonStyle())
        }
        DeckStudioArtworkInvitation()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let wide = proxy.size.width > proxy.size.height && !dynamicType.isAccessibilitySize
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                libraryBar(wide: true)
                                shelf
                            }
                            detail(wide: true)
                                .frame(width: 236)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            libraryBar(wide: false)
                            shelf
                            detail(wide: false)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            }
            .binderScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPreferences) {
                NavigationStack { GrimoireForm { NativeArtworkPreferenceView() }
                    .binderLeaf("Artwork & privacy", trailing: BinderLeafAction(title: "Done") { showPreferences = false }) }
                    .preferredColorScheme(.dark).grimoirePage(.loose)
            }
            .fullScreenCover(item: $route, onDismiss: {
                Task { await reloadTags() }
                // A reviewed import opens in its workspace, where Play is one tap away.
                if let saved = openAfterImport { openAfterImport = nil; turn(to: .deck(saved, false)) }
            }) { route in
                Group {
                    switch route {
                    case .deck(let record, let included):
                        DeckStudioWorkspaceScreen(library: library, record: record, included: included,
                            metadata: metadata, resolver: resolver, play: play)
                    case .importer:
                        DeckStudioImportScreen(library: library, resolver: resolver) { saved in openAfterImport = saved }
                    }
                }
                .environment(\.grimoireClose, { turn(to: nil) })
            }
            .binderConfirm("Delete this local deck?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                           message: pendingDelete.map { record in "local:\(record.id)" == selectedDeckID
                               ? DeckStudioPlayText.deletePlaying(PreconCatalog.all.first { "precon:\($0.id)" == OnDeviceSetupPreferences.defaultDeckID }?.name ?? "The default deck")
                               : "Included decks and source websites are never changed." }) {
                if let record = pendingDelete {
                    Button("Delete \(record.name)", role: .destructive) { delete(record) }
                }
            }
            .deckStudioPlayFeedback(play, active: route == nil) { deckID, cards in
                guard let deckID else { return }
                play.requestFix(deckID: deckID, cards: cards); open(deckID)
            }
            .binderOverlayHost()
        }
        .tint(DeckStudioPalette.accent).foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.dark)
        .task { connectPlay(); loadFavorites(); await loadCatalogue(); refreshCheckKeys(); openFocus(); await reloadTags() }
        .onChange(of: library.decks.map(\.id)) { _, _ in Task { await reloadTags() } }
        .onChange(of: library.decks) { _, _ in refreshCheckKeys() }
        .onChange(of: selectedDeckID) { _, value in play.selectedDeckID = value }
    }

    /// The bar over the boxes: search, which decks, their order, Import and the artwork settings.
    private func libraryBar(wide: Bool) -> some View {
        let pills = HStack(spacing: 8) {
            BinderMenu { BinderMenuPick("Show decks", selection: $query.filter, options: DeckStudioLibraryQuery.Filter.allCases.map { ($0, $0.rawValue) }) }
                label: { BinderPlaque { HStack(spacing: 5) { Text(query.filter == .all ? "All decks" : query.filter.rawValue); Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy)) } } }
                .accessibilityIdentifier("deckStudio.library.filter")
            BinderMenu { BinderMenuPick("Sort decks", selection: $query.sort, options: DeckStudioLibraryQuery.Sort.allCases.map { ($0, $0.rawValue) }) }
                label: { BinderPlaque { HStack(spacing: 5) { Text(query.sort.rawValue); Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy)) } } }
            Button { turn(to: .importer) } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .buttonStyle(BinderPlaqueButtonStyle()).accessibilityIdentifier("deckStudio.import")
                .disabled(resolver == nil)
            Button { showPreferences = true } label: { Image(systemName: "photo.on.rectangle.angled") }
                .buttonStyle(BinderPlaqueButtonStyle(square: true))
                .accessibilityLabel("Deck artwork and privacy")
        }
        return VStack(alignment: .leading, spacing: 4) {
            if wide {
                HStack(spacing: 8) {
                    BinderSearchField(placeholder: "Search decks", text: $query.text,
                                      identifier: "deckStudio.library.search", focus: $searchFocused)
                        .frame(minWidth: 140, maxWidth: 240)
                    pills.fixedSize()
                    Spacer(minLength: 0)
                }
            } else {
                BinderSearchField(placeholder: "Search decks, commanders or tags", text: $query.text,
                                  identifier: "deckStudio.library.search", focus: $searchFocused)
                ScrollView(.horizontal) { pills }.scrollIndicators(.hidden)
            }
            notices
        }
    }

    /// Every deck as a deck box (the first box makes a new deck); the chosen one stands open.
    private var shelf: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 12
            let usable = proxy.size.width - 8
            let columns = max(2, Int((usable + gap) / (112 + gap)))
            let width = floor((usable - gap * CGFloat(columns - 1)) / CGFloat(columns))
            let rise = ArenaBoxGeometry(width: width).rise
            ScrollView {
                HStack(alignment: .firstTextBaseline) {
                    ArenaSectionHeader(title: "My Decks", count: visible.count)
                    Spacer()
                }
                if visible.isEmpty {
                    BinderEmptyLeaf(title: query.text.isEmpty ? "Your next deck starts here" : "No matching decks",
                                    icon: "rectangle.stack", message: "Create a deck, import a list, or change your filters.")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: gap, alignment: .top), count: columns),
                          alignment: .leading, spacing: rise + 10) {
                    Button { turn(to: .deck(nil, false)) } label: { ArenaNewDeckBox(width: width) }
                        .buttonStyle(BrandPressStyle())
                        .accessibilityLabel("Create deck")
                        .accessibilityIdentifier("deckStudio.create")
                    ForEach(visible) { entry in deckBox(entry, width: width) }
                }
                .padding(.top, rise + 10)
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func deckBox(_ entry: Entry, width: CGFloat) -> some View {
        let id = entry.id
        let draft = NativeDeckDraft(deck: entry.record.deckList)
        let chosen = id == (focused ?? selectedDeckID)
        let bracket = entry.included ? CommanderBracket.core : DeckBracketPreference.effective(
            minimum: BracketRules.bundled.evaluate(entry.record.deckList).minimum,
            declared: DeckBracketPreference.declared(id, in: MagicMobilePreferences.current))
        let tag: String? = resolver != nil && status(id) == .needsFixes ? "FIX" : id == selectedDeckID ? "PLAYING" : nil
        let model = ArenaDeckBoxModel(id: id, name: entry.record.name, commander: entry.record.commander?.cardName,
                                      colors: DeckStudioDraftPresentation.colors(draft, metadata: metadata) ?? [],
                                      subtitle: bracket.name, tag: tag)
        return BinderGuardedButton {
            // Arena's way: the first tap opens the box and shows the deck; a second opens it for editing.
            if chosen { turn(to: .deck(entry.record, entry.included)) } else { focused = id }
        } label: {
            ArenaDeckBox(deck: model, selected: chosen, width: width, edit: { turn(to: .deck(entry.record, entry.included)) })
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityIdentifier("deckStudio.deck.\(id)")
        .binderContextMenu { deckActions(entry.record, included: entry.included) }
    }

    /// The chosen deck: its art, name, commander and colours, its bracket and check, and Edit Deck and Play.
    @ViewBuilder private func detail(wide: Bool) -> some View {
        if let entry = focusedEntry {
            let record = entry.record, id = entry.id
            let draft = NativeDeckDraft(deck: record.deckList)
            let bracket = entry.included ? CommanderBracket.core : DeckBracketPreference.effective(
                minimum: BracketRules.bundled.evaluate(record.deckList).minimum,
                declared: DeckBracketPreference.declared(id, in: MagicMobilePreferences.current))
            let facts = VStack(alignment: .leading, spacing: 4) {
                Text(record.name).font(ArenaMenuStyle.font(17, .bold)).foregroundStyle(ArenaMenuStyle.text).lineLimit(2)
                Text(DeckStudioDraftPresentation.commanders(draft).joined(separator: " • "))
                    .font(ArenaMenuStyle.font(12, .medium)).italic().foregroundStyle(ArenaMenuStyle.dim).lineLimit(1)
                HStack(spacing: 8) {
                    ArenaPips(colors: DeckStudioDraftPresentation.colors(draft, metadata: metadata) ?? [], size: 16)
                    BracketTag(bracket: bracket, short: true)
                        .accessibilityIdentifier("deckStudio.bracket.\(id)")
                }
                Text("\(CardCountText.label(DeckStudioDraftPresentation.gameCount(draft))) · \(entry.included ? "Included" : "Your deck")")
                    .font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                if resolver != nil && status(id) == .needsFixes { DeckStudioPlayStatusChip(status: .needsFixes) }
            }
            let tools = HStack(spacing: 0) {
                Button { toggleFavorite(id) } label: { Image(systemName: favorites.contains(id) ? "star.fill" : "star") }
                    .buttonStyle(BinderCoinButtonStyle(lit: favorites.contains(id)))
                    .accessibilityLabel(favorites.contains(id) ? "Unfavorite \(record.name)" : "Favorite \(record.name)")
                BinderMenu { deckActions(record, included: entry.included) } label: { BinderCoin { Image(systemName: "ellipsis") } }
                    .accessibilityLabel("Options for \(record.name)")
            }
            let actions = Group {
                Button { turn(to: .deck(record, entry.included)) } label: { Text("Edit Deck").frame(maxWidth: .infinity) }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("deckStudio.edit")
                Button { playFromLibrary(entry) } label: { Text(id == selectedDeckID ? "Playing" : "Play").frame(maxWidth: .infinity) }
                    .buttonStyle(ArenaPlayButtonStyle(fontSize: 18))
                    .frame(height: 44)
                    .disabled(resolver == nil || play.isChecking)
                    .accessibilityIdentifier("deckStudio.library.play")
            }
            Group {
                if wide {
                    VStack(alignment: .leading, spacing: 10) {
                        ArenaArt(name: record.commander?.cardName ?? "", colors: DeckStudioDraftPresentation.colors(draft, metadata: metadata) ?? [])
                            .frame(height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
                        facts
                        tools
                        Spacer(minLength: 0)
                        actions
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ArenaArt(name: record.commander?.cardName ?? "", colors: DeckStudioDraftPresentation.colors(draft, metadata: metadata) ?? [])
                            .frame(width: 92, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
                        VStack(alignment: .leading, spacing: 6) {
                            facts
                            HStack(spacing: 8) { tools; actions }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil, alignment: .topLeading)
            .modifier(ArenaGlassPanel(cornerRadius: 14, opacity: 0.92))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("deckStudio.detail")
        }
    }

    // MARK: Playing deck

    private func connectPlay() {
        play.selectedDeckID = selectedDeckID
        play.onSelect = { selectedDeckID = $0 }
        play.isGameLive = isGameLive
        play.setUpGame = { route = nil; dismiss(); preparePlay() }
        DeckStudioValidationService.shared.isGameLive = isGameLive
    }
    /// Check keys depend only on a deck's playing cards and this install, so they are
    /// computed when decks or the catalogue change, not on every render.
    private func refreshCheckKeys() {
        guard let resolver else { return }
        play.resolver = resolver
        var keys: [String: DeckStudioCheckKey?] = [:]
        for entry in records {
            keys.updateValue(try? DeckStudioPlaySelection.key(deckID: entry.id, deck: entry.record.deckList, resolver: resolver, appBuild: play.appBuild),
                             forKey: entry.id)
            DeckStudioDeckColors.remember(commanders: DeckStudioDraftPresentation.commanders(NativeDeckDraft(deck: entry.record.deckList)), metadata: metadata)
        }
        checkKeys = keys
    }
    /// A deck the resolver cannot read needs fixes, as on the setup screen and Android.
    private func status(_ id: String) -> DeckStudioPlayStatus {
        switch checkKeys[id] {
        case .some(.some(let key)): return play.store.status(for: key)
        case .some(.none): return .needsFixes
        case .none: return .notChecked
        }
    }
    private func open(_ id: String) {
        guard let entry = records.first(where: { $0.id == id }) else { return }
        turn(to: .deck(entry.record, entry.included))
    }
    /// Moving between this page and a deck or the importer turns the page of the book.
    private func turn(to next: Route?) {
        GrimoireStage.shared.turnPage(forward: next != nil) { route = next }
    }
    private func openFocus() {
        #if DEBUG
        // Development fixture (MAGICMOBILE_UI_TEST_OPEN=deck): the playing deck's workspace.
        if !focusHandled, SocialFixtures.openScreen == "deck" { focusHandled = true; open(selectedDeckID); return }
        #endif
        guard !focusHandled, let focus else { return }
        focusHandled = true
        play.requestFix(deckID: focus.deckID, cards: focus.cards); open(focus.deckID)
    }
    private func playFromLibrary(_ entry: Entry) {
        play.play(name: entry.record.name) { .init(deckID: entry.id, deck: entry.record.deckList) }
    }

    @ViewBuilder private func deckActions(_ record: DeckLibraryRecord, included: Bool) -> some View {
            BinderMenuHeading(record.name)
            BinderMenuButton(DeckStudioPlayText.play, systemImage: "play.fill") { playFromLibrary(Entry(record: record, included: included)) }
                .disabled(resolver == nil || play.isChecking)
            BinderMenuButton("Open deck", systemImage: "pencil") { turn(to: .deck(record, included)) }
            BinderMenuButton("Duplicate locally", systemImage: "doc.on.doc") {
                Task {
                    do {
                        let copy = try library.duplicateLocalDurably(record, name: record.name + " — Copy")
                        do { try await DeckStudioOrganizationStore.shared.duplicate(from: record.id, to: copy.id) }
                        catch { self.error = "Cards were copied, but their optional details could not be copied: \(error.localizedDescription)" }
                        await reloadTags(); turn(to: .deck(copy, false))
                    } catch { self.error = error.localizedDescription }
                }
            }
            BinderMenuDivider()
            if let data = try? OnDeviceDeckEditing(record.deckList).exportJSON(), let text = String(data: data, encoding: .utf8) {
                BinderMenuShare(title: "Export native JSON", systemImage: "square.and.arrow.up", item: text)
            }
            if let text = try? DeckStudioTextExport.text(record.deckList) {
                BinderMenuShare(title: "Export plain text", systemImage: "doc.plaintext", item: text)
            } else { BinderMenuNote("Plain text unavailable · use JSON to preserve this draft") }
            if !included && !record.isCloudBacked {
                BinderMenuDivider()
                BinderMenuButton("Delete local deck", systemImage: "trash", role: .destructive) { pendingDelete = record }
            }
    }
    private func delete(_ record: DeckLibraryRecord) {
        do {
            try library.deleteLocalDurably(id: record.id, expectedRevision: record.revision)
            NativeDeckDraftRecovery.clear(recordID: record.id)
            tags.removeValue(forKey: record.id)
            Task {
                do { try await DeckStudioOrganizationStore.shared.delete(recordID: record.id) }
                catch { self.error = "Deck cards were deleted, but optional local details could not be removed: \(error.localizedDescription)" }
            }
            favorites.remove("local:\(record.id)"); saveFavorites()
            play.store.forget(deckID: "local:\(record.id)")
            if selectedDeckID == "local:\(record.id)" { selectedDeckID = OnDeviceSetupPreferences.defaultDeckID }
        } catch { self.error = error.localizedDescription }
        pendingDelete = nil
    }
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey) else { return }
        do {
            guard data.count <= 256 * 1024 else { throw CocoaError(.coderReadCorrupt) }
            let value = try JSONDecoder().decode([String].self, from: data)
            guard value.count <= 4000, value.allSatisfy({ $0.utf8.count <= 256 }) else { throw CocoaError(.coderReadCorrupt) }
            favorites = Set(value)
        } catch { favoritesReadable = false; self.error = "Favorite preferences could not load. They have been preserved; your decks are unchanged." }
    }
    private func saveFavorites() {
        guard favoritesReadable else { return }
        do { UserDefaults.standard.set(try JSONEncoder().encode(favorites.sorted()), forKey: favoritesKey) }
        catch { self.error = error.localizedDescription }
    }
    private func toggleFavorite(_ id: String) {
        guard favoritesReadable else { error = "Unreadable favorite preferences are preserved; no changes were written."; return }
        if favorites.contains(id) { favorites.remove(id) } else if favorites.count < 4000 { favorites.insert(id) }
        saveFavorites()
    }
    private func reloadTags() async {
        let token = UUID(); tagLoadToken = token
        let ids = records.map { $0.record.id }
        let result = await DeckStudioOrganizationStore.shared.tagIndex(recordIDs: ids)
        guard tagLoadToken == token, !Task.isCancelled else { return }
        tags = result
    }
    private func loadCatalogue() async {
        guard metadata == nil else { return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                (try NativeDeckMetadataCatalogue.bundled(), try OnDeviceDeckResolver.bundled())
            }.value
            try Task.checkCancellation()
            metadata = loaded.0; resolver = loaded.1; loadError = nil
        } catch is CancellationError { } catch { loadError = error.localizedDescription }
    }
}

/// Each metadata slot reserves the same number of lines; Dynamic Type determines
/// their height instead of a fixed tile height that could clip larger text.
struct DeckStudioTileDetails: View {
    let name: String
    let commanders: String
    let colors: [String]?
    let tags: [String]
    let showTags: Bool
    let summary: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            Text(commanders.isEmpty ? " " : commanders).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(2, reservesSpace: true)
                .accessibilityHidden(commanders.isEmpty)
            DeckStudioColorIdentity(colors: colors)
            if showTags {
                Text(tags.isEmpty ? " " : tags.joined(separator: " · ")).font(.caption2).foregroundStyle(DeckStudioPalette.accent).lineLimit(2, reservesSpace: true)
                    .accessibilityHidden(tags.isEmpty)
            }
            Text(summary).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(2, reservesSpace: true)
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// The grid owns the width, not the intrinsic aspect ratio of the loaded illustration.
struct DeckStudioTileCover<Artwork: View>: View {
    let height: CGFloat
    @ViewBuilder var artwork: () -> Artwork
    var body: some View {
        GeometryReader { geometry in
            artwork().frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.frame(height: height)
    }
}

struct DeckStudioArtwork: View {
    let name: String
    var hero = false
    /// Color identity for the cover drawn when the commander's art is not on this iPhone.
    var colors: [String]? = nil
    /// A deck's own row passes its chosen printing here; anywhere else the player's choice for the name shows.
    var art: CardArtSelection = .active
    var body: some View {
        NativeCardArtworkView(name: name, variant: .board, contentMode: hero ? .fill : .fit, artOnly: hero, art: art) { _, _ in
            if hero {
                DeckCoverPlaceholder(commander: name, colors: colors)
            } else {
                ZStack {
                    DeckStudioPalette.background
                    Image(systemName: "sparkle").font(.body).foregroundStyle(DeckStudioPalette.secondaryInk)
                }
            }
        }.accessibilityHidden(true)
    }
}

/// A deck cover without artwork: the deck's colors as light through glass, its
/// commander's name and mana pips. Downloaded art replaces it.
struct DeckCoverPlaceholder: View {
    let commander: String
    let colors: [String]?

    private static let tints: [String: Color] = [
        "W": Color(red: 0.93, green: 0.86, blue: 0.66), "U": Color(red: 0.2, green: 0.46, blue: 0.78),
        "B": Color(red: 0.3, green: 0.22, blue: 0.34), "R": Color(red: 0.8, green: 0.28, blue: 0.18),
        "G": Color(red: 0.22, green: 0.55, blue: 0.32)
    ]

    private var palette: [Color] {
        let chosen = ["W", "U", "B", "R", "G"].filter { colors?.contains($0) == true }.compactMap { Self.tints[$0] }
        switch chosen.count {
        case 0: return [Color(red: 0.42, green: 0.44, blue: 0.47), Color(red: 0.2, green: 0.21, blue: 0.23)]
        case 1: return [chosen[0], chosen[0].opacity(0.55)]
        default: return chosen
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 4, endRadius: 180)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    if let colors {
                        HStack(spacing: 3) {
                            ForEach(["W", "U", "B", "R", "G"].filter { colors.contains($0) }, id: \.self) {
                                ManaSymbolView(symbol: $0, size: 18)
                            }
                            if colors.isEmpty { ManaSymbolView(symbol: "C", size: 18) }
                        }
                        .padding(5)
                        .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                Text(commander.isEmpty ? String(localized: "Choose a commander") : commander)
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .lineLimit(2).minimumScaleFactor(0.75)
            }
            .padding(12)
        }
    }
}

/// Remote card art is off until the player opts in; cached artwork remains available.
/// The setting otherwise lives behind a
/// toolbar button. Lists that are mostly artwork say so inline, so an empty-looking list
/// reads as a choice rather than a failure. Declining leaves everything else working.
struct DeckStudioArtworkInvitation: View {
    @AppStorage(NativeArtworkPreference.key) private var remoteArtwork = false
    @State private var expanded = false
    var body: some View {
        if !remoteArtwork {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Turn on artwork across the app to send displayed card names and your IP address to Scryfall. Saved images remain available offline. Change this anytime in Artwork & privacy.")
                        .font(.system(size: 13, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Turn on") { remoteArtwork = true }
                        .buttonStyle(BinderPlaqueButtonStyle())
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("deckStudio.artwork.enable")
                }
            } label: {
                HStack(spacing: 10) {
                    BinderStamp(icon: "photo.on.rectangle.angled", size: 28)
                    Text("Online card images are off").font(.system(size: 15, weight: .bold, design: .serif))
                }
                .frame(minHeight: 32)
            }
            .disclosureGroupStyle(BinderDisclosureStyle())
            .foregroundStyle(DeckStudioPalette.ink)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .binderPlate()
        }
    }
}
