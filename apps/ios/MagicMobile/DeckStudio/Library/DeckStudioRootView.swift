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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = DeckStudioLibraryQuery()
    @AppStorage("deckStudio.library.grid.v1") private var grid = true
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
    @StateObject private var play = DeckStudioPlaySelection()
    @State private var checkKeys: [String: DeckStudioCheckKey] = [:]
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    DeckStudioArtworkInvitation()
                    if let error = error ?? library.notice {
                        DeckStudioNotice(title: "Your library is preserved", message: error, icon: "exclamationmark.triangle")
                    }
                    if let loadError {
                        DeckStudioNotice(title: "Card catalogue unavailable", message: loadError)
                        Button("Retry local catalogue", action: { Task { await loadCatalogue() } })
                    }
                    libraryFilters
                    HStack {
                        Text("\(visible.count) decks").font(.subheadline).foregroundStyle(DeckStudioPalette.secondaryInk)
                        Spacer()
                        Menu { Picker("Sort decks", selection: $query.sort) { ForEach(DeckStudioLibraryQuery.Sort.allCases) { Text($0.rawValue).tag($0) } } }
                            label: { Label(query.sort.rawValue, systemImage: "arrow.up.arrow.down").font(.subheadline).frame(minHeight: 44) }
                        Button { grid.toggle() } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2").frame(width: 44, height: 44) }
                            .accessibilityLabel(grid ? "Show deck list" : "Show deck grid")
                    }
                    if visible.isEmpty {
                        ContentUnavailableView(query.text.isEmpty ? "Your next deck starts here" : "No matching decks",
                            systemImage: "rectangle.stack", description: Text("Create a deck, import a list, or change your filters."))
                    }
                    LazyVGrid(columns: grid && !dynamicType.isAccessibilitySize
                              ? [GridItem(.adaptive(minimum: 160, maximum: 320), spacing: 16)] : [GridItem(.flexible())], spacing: 16) {
                        ForEach(visible) { value in tile(value.record, included: value.included) }
                    }
                }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let playing = records.first(where: { $0.id == selectedDeckID }) {
                    DeckStudioNowPlayingStrip(name: playing.record.name, status: status(playing.id)) { open(playing.id) }
                }
            }
            .background(DeckStudioPalette.background.ignoresSafeArea())
            .navigationTitle("Deck Studio").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DeckStudioPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPreferences = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Deck artwork and privacy")
                }
            }
            .sheet(isPresented: $showPreferences) {
                NavigationStack { Form { NativeArtworkPreferenceView() }.navigationTitle("Artwork & privacy")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreferences = false } } } }
                    .preferredColorScheme(.light)
            }
            .fullScreenCover(item: $route, onDismiss: {
                Task { await reloadTags() }
                // A reviewed import opens in its workspace, where Play is one tap away.
                if let saved = openAfterImport { openAfterImport = nil; route = .deck(saved, false) }
            }) { route in
                switch route {
                case .deck(let record, let included):
                    DeckStudioWorkspaceScreen(library: library, record: record, included: included,
                        metadata: metadata, resolver: resolver, play: play)
                case .importer:
                    DeckStudioImportScreen(library: library, resolver: resolver) { saved in openAfterImport = saved }
                }
            }
            .confirmationDialog("Delete this local deck?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                if let record = pendingDelete {
                    Button("Delete \(record.name)", role: .destructive) { delete(record) }
                }
            } message: {
                if let record = pendingDelete, "local:\(record.id)" == selectedDeckID {
                    Text(DeckStudioPlayText.deletePlaying(PreconCatalog.all.first { "precon:\($0.id)" == OnDeviceSetupPreferences.defaultDeckID }?.name ?? "The default deck"))
                } else { Text("Included decks and source websites are never changed.") }
            }
            .deckStudioPlayFeedback(play, active: route == nil) { deckID, cards in
                guard let deckID else { return }
                play.requestFix(deckID: deckID, cards: cards); open(deckID)
            }
        }
        .tint(DeckStudioPalette.ink).foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light)
        .task { connectPlay(); loadFavorites(); await loadCatalogue(); refreshCheckKeys(); openFocus(); await reloadTags() }
        .onChange(of: library.decks.map(\.id)) { _, _ in Task { await reloadTags() } }
        .onChange(of: library.decks) { _, _ in refreshCheckKeys() }
        .onChange(of: selectedDeckID) { _, value in play.selectedDeckID = value }
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
        var keys: [String: DeckStudioCheckKey] = [:]
        for entry in records {
            keys[entry.id] = try? DeckStudioPlaySelection.key(deckID: entry.id, deck: entry.record.deckList, resolver: resolver, appBuild: play.appBuild)
            DeckStudioDeckColors.remember(commanders: DeckStudioDraftPresentation.commanders(NativeDeckDraft(deck: entry.record.deckList)), metadata: metadata)
        }
        checkKeys = keys
    }
    private func status(_ id: String) -> DeckStudioPlayStatus { play.store.status(for: checkKeys[id]) }
    private func open(_ id: String) {
        guard let entry = records.first(where: { $0.id == id }) else { return }
        route = .deck(entry.record, entry.included)
    }
    private func openFocus() {
        guard !focusHandled, let focus else { return }
        focusHandled = true
        play.requestFix(deckID: focus.deckID, cards: focus.cards); open(focus.deckID)
    }
    private func playFromLibrary(_ entry: Entry) {
        play.play(name: entry.record.name) { .init(deckID: entry.id, deck: entry.record.deckList) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR COLLECTION").font(.caption.weight(.semibold)).tracking(1.8).foregroundStyle(DeckStudioPalette.secondaryInk)
            Text("My Decks").font(.system(.largeTitle, design: .default).weight(.bold)).tracking(-1)
            Text("Find your next move.").font(.subheadline).foregroundStyle(DeckStudioPalette.secondaryInk)
            ViewThatFits(in: .horizontal) {
                HStack { createButton; importButton }
                VStack { createButton; importButton }
            }.padding(.top, 8)
        }
    }
    private var createButton: some View {
        Button { route = .deck(nil, false) } label: { Label("Create deck", systemImage: "plus").frame(maxWidth: .infinity) }
            .buttonStyle(DeckStudioButtonStyle()).accessibilityIdentifier("deckStudio.create")
    }
    private var importButton: some View {
        Button { route = .importer } label: { Label("Import", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
            .buttonStyle(DeckStudioButtonStyle(primary: false)).accessibilityIdentifier("deckStudio.import")
            .disabled(resolver == nil)
    }
    private var libraryFilters: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search decks, commanders or tags", text: $query.text).autocorrectionDisabled()
                    .accessibilityIdentifier("deckStudio.library.search")
                if !query.text.isEmpty { Button { query.text = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DeckStudioLibraryQuery.Filter.allCases) { filter in
                        Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { query.filter = filter } } label: {
                            Text(filter.rawValue).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                                .foregroundStyle(query.filter == filter ? .white : DeckStudioPalette.ink)
                                .background(query.filter == filter ? DeckStudioPalette.ink : DeckStudioPalette.surface, in: Capsule())
                        }.accessibilityAddTraits(query.filter == filter ? [.isSelected] : [])
                    }
                }
            }
        }
    }
    private func tile(_ record: DeckLibraryRecord, included: Bool) -> some View {
        let id = selectionID(record, included: included)
        let draft = NativeDeckDraft(deck: record.deckList)
        return VStack(alignment: .leading, spacing: 0) {
            Button { route = .deck(record, included) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    DeckStudioTileCover(height: grid ? 164 : 130) {
                        DeckStudioArtwork(name: record.commander?.cardName ?? "", hero: true,
                                          colors: DeckStudioDraftPresentation.colors(draft, metadata: metadata))
                    }
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                if id == selectedDeckID { DeckStudioPlayingBadge() }
                                if resolver != nil { DeckStudioPlayStatusChip(status: status(id)) }
                            }.padding(10)
                        }
                    DeckStudioTileDetails(name: record.name,
                        commanders: DeckStudioDraftPresentation.commanders(draft).joined(separator: " • "),
                        colors: DeckStudioDraftPresentation.colors(draft, metadata: metadata),
                        tags: tags[record.id] ?? [], showTags: tags.values.contains(where: { !$0.isEmpty }),
                        summary: "\(CardCountText.label(DeckStudioDraftPresentation.gameCount(draft))) · \(included ? "Included" : "Local draft")")
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(DeckStudioArtworkButtonStyle()).accessibilityIdentifier("deckStudio.deck.\(id)")
            HStack(spacing: 0) {
                Group {
                    if !included { Text(record.updatedAt, style: .date) }
                    else { Text("Make it your own") }
                }.font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .lineLimit(2, reservesSpace: true).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Button { toggleFavorite(id) } label: { Image(systemName: favorites.contains(id) ? "star.fill" : "star").frame(width: 44, height: 44) }
                    .foregroundStyle(DeckStudioPalette.ink).accessibilityLabel(favorites.contains(id) ? "Unfavorite \(record.name)" : "Favorite \(record.name)")
                Menu { deckActions(record, included: included) } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(record.name)")
            }.padding(.horizontal, 14)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: DeckStudioPalette.ink.opacity(0.04), radius: 12, y: 4)
        .contextMenu { deckActions(record, included: included) }
    }
    @ViewBuilder private func deckActions(_ record: DeckLibraryRecord, included: Bool) -> some View {
            Button(DeckStudioPlayText.play, systemImage: "play.fill") { playFromLibrary(Entry(record: record, included: included)) }
                .disabled(resolver == nil || play.isChecking)
            Button("Open deck", systemImage: "pencil") { route = .deck(record, included) }
            Button("Duplicate locally", systemImage: "doc.on.doc") {
                Task {
                    do {
                        let copy = try library.duplicateLocalDurably(record, name: record.name + " — Copy")
                        do { try await DeckStudioOrganizationStore.shared.duplicate(from: record.id, to: copy.id) }
                        catch { self.error = "Cards were copied, but their optional details could not be copied: \(error.localizedDescription)" }
                        await reloadTags(); route = .deck(copy, false)
                    } catch { self.error = error.localizedDescription }
                }
            }
            if let data = try? OnDeviceDeckEditing(record.deckList).exportJSON(), let text = String(data: data, encoding: .utf8) {
                ShareLink(item: text) { Label("Export native JSON", systemImage: "square.and.arrow.up") }
            }
            if let text = try? DeckStudioTextExport.text(record.deckList) {
                ShareLink(item: text) { Label("Export plain text", systemImage: "doc.plaintext") }
            } else { Text("Plain text unavailable · use JSON to preserve this draft") }
            if !included && !record.isCloudBacked {
                Button("Delete local deck", systemImage: "trash", role: .destructive) { pendingDelete = record }
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
    var body: some View {
        NativeCardArtworkView(name: name, variant: .board, contentMode: hero ? .fill : .fit, artOnly: hero) { _, _ in
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on artwork across the app to send displayed card names and your IP address to Scryfall. Saved images remain available offline. Change this anytime in Artwork & privacy.")
                        .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                Button("Turn on") { remoteArtwork = true }
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("deckStudio.artwork.enable")
                }
            } label: {
                Label("Online card images are off", systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold)).frame(minHeight: 32)
            }
            .foregroundStyle(DeckStudioPalette.ink)
            .padding(12)
            .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DeckStudioPalette.separator))
        }
    }
}
