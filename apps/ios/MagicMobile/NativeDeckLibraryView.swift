import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Native-only deck management. No account, cloud library, or rules server is used.
@MainActor
struct NativeDeckLibraryView: View {
    @ObservedObject var library: DeckLibraryStore
    @Binding var selectedDeckID: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var sheet: DeckSheet?
    @State private var errorMessage: String?

    private enum DeckSheet: Identifiable {
        case importer
        case editor(DeckLibraryRecord?)
        var id: String {
            switch self { case .importer: return "import"; case .editor(let record): return record?.id ?? "new" }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your spellbooks").font(.largeTitle.bold()).foregroundStyle(MagicPalette.parchment)
                    Text("Build on this device. Bring a list from the web. Find your next table.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button { sheet = .importer } label: { Label("Import", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                            .buttonStyle(MagicPrimaryButtonStyle(compact: true))
                        Button { sheet = .editor(nil) } label: { Label("New deck", systemImage: "plus").frame(maxWidth: .infinity) }
                            .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                    }
                    NativeArtworkPreferenceView()
                    if let errorMessage { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) }
                    if let notice = library.notice { Text(notice).foregroundStyle(MagicPalette.warningAmber) }
                    deckSection("Saved on this device", records: library.decks, bundled: false)
                    if library.decks.isEmpty && search.isEmpty {
                        Text("Import a deck or make an editable copy of an included deck to begin.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    deckSection("Included Commander decks", records: PreconCatalog.all.map {
                        DeckLibraryRecord(deck: $0.deckList, id: "precon:\($0.id)", sourceURL: $0.sourceURL.absoluteString)
                    }, bundled: true)
                }.padding(16)
            }
            .background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Decks").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a deck or commander")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .importer:
                    NativeDeckImportSheet(library: library) { record in selectedDeckID = "local:\(record.id)" }
                case .editor(let record):
                    NativeDeckEditorSheet(library: library, record: record) { saved in selectedDeckID = "local:\(saved.id)" }
                }
            }
        }.preferredColorScheme(.dark).tint(MagicPalette.antiqueGold)
    }

    private func deckSection(_ title: String, records: [DeckLibraryRecord], bundled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(MagicPalette.antiqueGold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(records.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.commander?.cardName.localizedCaseInsensitiveContains(search) ?? false) }) { record in
                    NavigationLink {
                        NativeDeckDetailView(library: library, original: record, bundled: bundled,
                                             selectedDeckID: $selectedDeckID)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            NativeDeckCardImage(name: record.commander?.cardName ?? record.entries.first?.cardName ?? "", inspection: false)
                                .frame(height: 160).frame(maxWidth: .infinity)
                            Text(record.name).font(.headline).lineLimit(2)
                            Text(record.commander?.cardName ?? "Choose a commander").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                Text("\(record.cardCount) cards")
                                Spacer()
                                if selectedDeckID == (bundled ? record.id : "local:\(record.id)") { Image(systemName: "checkmark.circle.fill") }
                            }.font(.caption.bold()).foregroundStyle(MagicPalette.antiqueGold)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("nativeDeck.\(bundled ? "bundled" : "saved").\(record.name)")
                }
            }
        }
    }
}

struct NativeArtworkPreferenceView: View {
    @AppStorage("magicmobile.deckArtworkNetworkEnabled") private var remoteArtwork = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Download card artwork", isOn: $remoteArtwork)
                .accessibilityIdentifier("nativeArtwork.downloads")
            Text("Optional: Scryfall receives displayed card names, including your hand, and your IP address. Applies to decks and gameplay. Cached artwork works offline; rules stay on this device.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NativeDeckCardImage: View {
    let name: String
    var inspection = false
    var body: some View {
        NativeCardArtworkView(name: name, variant: inspection ? .inspection : .board) { _, failed in
            VStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.largeTitle)
                Text(name.isEmpty ? "Your next deck" : name).font(.caption.bold()).multilineTextAlignment(.center)
                Text(failed ? "Artwork unavailable" : "Artwork downloads are optional").font(.caption2)
            }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(MagicPalette.parchment)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityElement(children: .ignore).accessibilityLabel(name.isEmpty ? "Deck cover" : name)
    }
}

enum NativeCardArtworkPolicy {
    static func permitsLookup(card: ZoneCard) -> Bool {
        permitsLookup(name: card.card.name) &&
            !(card.cardIcons ?? []).contains { $0.iconType.uppercased() == "OTHER_FACEDOWN" }
    }

    static func permitsLookup(name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["", "hidden card", "face-down card", "face down card", "face-down", "face down",
                 "card details unavailable"].contains(normalized)
    }
}

/// The one consent-aware artwork route for native deck and gameplay cards.
/// AppStorage inherits the native root's default store, including isolated UI-test suites.
struct NativeCardArtworkView<Placeholder: View>: View {
    let name: String
    let variant: CardImageCacheVariant
    @ViewBuilder let placeholder: (_ loading: Bool, _ failed: Bool) -> Placeholder
    @AppStorage("magicmobile.deckArtworkNetworkEnabled") private var remoteArtwork = false
    @State private var artwork: UIImage?
    @State private var completedRequest: Request?
    @State private var failedRequest: Request?

    private struct Request: Hashable {
        let name: String
        let variant: String
        let allowNetwork: Bool
    }

    var body: some View {
        let request = Request(name: name, variant: variant.queryVersion, allowNetwork: remoteArtwork)
        let permitted = NativeCardArtworkPolicy.permitsLookup(name: name)
        Group {
            if permitted, completedRequest == request, let artwork {
                Image(uiImage: artwork).resizable().scaledToFit()
            } else {
                placeholder(permitted && remoteArtwork && completedRequest != request && failedRequest != request,
                            permitted && failedRequest == request)
            }
        }
            .task(id: request) {
                guard permitted else { artwork = nil; completedRequest = nil; failedRequest = nil; return }
                // CardImageURL only supplies a generated cache path here; never fetch its remote fallback.
                if let url = CardImageURL.image(name, variant: variant), url.isFileURL,
                   let image = UIImage(contentsOfFile: url.path) {
                    guard !Task.isCancelled else { return }
                    artwork = image; completedRequest = request; failedRequest = nil; return
                }
                do {
                    let data = try await NativeDeckArtwork.shared.imageData(name: name, allowNetwork: request.allowNetwork)
                    try Task.checkCancellation()
                    artwork = data.flatMap(UIImage.init(data:))
                    completedRequest = request
                    failedRequest = request.allowNetwork && artwork == nil ? request : nil
                } catch is CancellationError { } catch {
                    guard !Task.isCancelled else { return }
                    failedRequest = request
                }
            }
    }
}

@MainActor
private struct NativeDeckDetailView: View {
    @ObservedObject var library: DeckLibraryStore
    let original: DeckLibraryRecord
    let bundled: Bool
    @Binding var selectedDeckID: String
    @Environment(\.dismiss) private var dismiss
    @State private var editRecord: DeckLibraryRecord?
    @State private var inspection: DeckCardSelection?
    @State private var search = ""
    @State private var showGrid = true
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    private var record: DeckLibraryRecord { bundled ? original : library.decks.first { $0.id == original.id } ?? original }
    private var allEntries: [DeckEntry] { (record.commander.map { [$0] } ?? []) + record.entries }
    private var selectionID: String { bundled ? record.id : "local:\(record.id)" }
    private var exportedText: String {
        let commander = record.commander.map { "Commander\n\($0.quantity) \($0.cardName)\n\n" } ?? ""
        return commander + record.entries.map { "\($0.section.capitalized)\n\($0.quantity) \($0.cardName)" }.joined(separator: "\n\n")
    }
    private var exportedJSON: String? {
        guard let data = try? OnDeviceDeckEditing(record.deckList).exportJSON() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(record.name).font(.largeTitle.bold())
                Text("\(record.cardCount) cards · \(bundled ? "Included deck" : "Saved locally")").foregroundStyle(.secondary)
                Text("XMage checks Commander legality when you start a game. Saved drafts may be incomplete.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        do {
                            _ = try OnDeviceDeckResolver.bundled().resolve(record.deckList)
                            selectedDeckID = selectionID
                        } catch { errorMessage = error.localizedDescription }
                    } label: { Label(selectedDeckID == selectionID ? "Selected" : "Use for play", systemImage: "checkmark.shield").frame(maxWidth: .infinity) }
                        .buttonStyle(MagicPrimaryButtonStyle(compact: true))
                    Button {
                        editRecord = bundled || record.isCloudBacked ? DeckLibraryRecord(deck: DeckList(name: "\(record.name) — My copy", commander: record.commander, entries: record.entries), sourceURL: record.sourceURL) : record
                    } label: { Label(bundled || record.isCloudBacked ? "Edit a local copy" : "Edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) }
                Picker("Card view", selection: $showGrid) {
                    Text("Cards").tag(true); Text("List").tag(false)
                }.pickerStyle(.segmented)
                ForEach(Array(Set(allEntries.map(\.section))).sorted(), id: \.self) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.capitalized).font(.headline).foregroundStyle(MagicPalette.antiqueGold)
                        let entries = allEntries.enumerated().filter { $0.element.section == section && (search.isEmpty || $0.element.cardName.localizedCaseInsensitiveContains(search)) }
                        if showGrid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 10)], spacing: 12) {
                                ForEach(entries, id: \.offset) { _, entry in
                                    Button { inspection = DeckCardSelection(name: entry.cardName) } label: {
                                        VStack(spacing: 5) {
                                            NativeDeckCardImage(name: entry.cardName).frame(height: 165)
                                            Text("\(entry.quantity) × \(entry.cardName)").font(.caption.bold()).lineLimit(2)
                                        }.frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain).accessibilityIdentifier("nativeDeck.inspect.\(entry.cardName)")
                                }
                            }
                        } else {
                            ForEach(entries, id: \.offset) { _, entry in
                                Button { inspection = DeckCardSelection(name: entry.cardName) } label: {
                                    HStack { Text("\(entry.quantity)×").monospacedDigit(); Text(entry.cardName); Spacer(); Image(systemName: "magnifyingglass") }
                                        .frame(minHeight: 44)
                                }.buttonStyle(.plain).accessibilityIdentifier("nativeDeck.inspect.\(entry.cardName)")
                            }
                        }
                    }
                }
                ShareLink(item: exportedText) { Label("Export deck text", systemImage: "square.and.arrow.up") }
                if let exportedJSON {
                    ShareLink(item: exportedJSON) { Label("Export complete draft (JSON)", systemImage: "doc.badge.arrow.up") }
                    Text("JSON preserves the deck name, commander role and every section, including unfinished drafts. Paste it back into Import to restore a copy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !bundled && !record.isCloudBacked {
                    Button("Delete local deck", role: .destructive) { confirmDelete = true }.padding(.top)
                }
            }.padding(16)
        }
        .background(BattlefieldSurface().ignoresSafeArea())
        .navigationTitle("Deck details").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a card in this deck")
        .sheet(item: $inspection) { card in NativeDeckInspectionSheet(name: card.name) }
        .sheet(item: $editRecord) { draft in
            NativeDeckEditorSheet(library: library, record: draft) { saved in selectedDeckID = "local:\(saved.id)" }
        }
        .confirmationDialog("Delete this local deck?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete local deck", role: .destructive) {
                do {
                    try library.deleteLocalDurably(id: record.id)
                    if selectedDeckID == selectionID { selectedDeckID = OnDeviceSetupPreferences.defaultDeckID }
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            }.accessibilityIdentifier("nativeDeck.confirmDelete")
        } message: { Text("The source website and included decks will not be changed. Export a copy first if you want a backup.") }
    }
}

private struct DeckCardSelection: Identifiable {
    var id: String { name }
    let name: String
}

private struct NativeDeckInspectionSheet: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            NativeDeckCardImage(name: name, inspection: true).padding(16)
                .background(BattlefieldSurface().ignoresSafeArea())
                .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

@MainActor
private struct NativeDeckImportSheet: View {
    @ObservedObject var library: DeckLibraryStore
    let didImport: (DeckLibraryRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var useLink = false
    @State private var name = "Imported Commander Deck"
    @State private var text = ""
    @State private var link = ""
    @State private var excludeSideboards = false
    @State private var errorMessage: String?
    @State private var importing = false
    @State private var importTask: Task<Void, Never>?
    @State private var filePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Import from", selection: $useLink) {
                        Text("Paste list").tag(false); Text("Deck link").tag(true)
                    }.pickerStyle(.segmented)
                    if useLink {
                        TextField("Public Moxfield or Archidekt URL", text: $link)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Exclude sideboard and considering cards", isOn: $excludeSideboards)
                        Text("When enabled, only the main deck, commanders and companion are imported. Sideboard, maybeboard and categories marked outside the deck are omitted; the source website is unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Public links only. If a provider blocks access or the deck is private, export it as text and use Paste list. Nothing is sent to a MagicMobile rules server.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("Deck name", text: $name)
                        TextEditor(text: $text).frame(minHeight: 230).font(.body.monospaced())
                            .accessibilityLabel("Deck list text")
                        Text("Commander\n1 Emmara, Soul of the Accord\n\nDeck\n1 Sol Ring\n...")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Button { filePicker = true } label: { Label("Open text file", systemImage: "doc") }
                    }
                }.disabled(importing)
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) } }
                Section {
                    Button(action: beginImport) {
                        HStack { if importing { ProgressView() }; Text(importing ? "Importing…" : "Import and select") }
                    }.disabled(importing || (useLink ? link : text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: { Text("Exact compiled card names are checked locally. XMage validates deck legality when starting a game.") }
            }
            .scrollContentBackground(.hidden).background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Import deck").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { importTask?.cancel(); dismiss() } } }
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.plainText, .json, UTType(filenameExtension: "dec") ?? .plainText]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= OnDeviceDeckLinkImporter.maximumBytes else { throw OnDeviceDeckResolver.ResolutionError("Deck file is too large.") }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: OnDeviceDeckLinkImporter.maximumBytes + 1) ?? Data()
                    guard data.count <= OnDeviceDeckLinkImporter.maximumBytes,
                          let decoded = String(data: data, encoding: .utf8) else {
                        throw OnDeviceDeckResolver.ResolutionError("Use a UTF-8 deck file no larger than 2 MiB.")
                    }
                    text = decoded
                    name = url.deletingPathExtension().lastPathComponent
                } catch { errorMessage = error.localizedDescription }
            }
            .onDisappear { importTask?.cancel() }
        }.preferredColorScheme(.dark)
    }

    private func beginImport() {
        importing = true; errorMessage = nil
        importTask = Task { @MainActor in
            defer { importing = false }
            do {
                let importer = OnDeviceDeckLinkImporter(resolver: try .bundled())
                let deck: DeckList
                if useLink { deck = try await importer.importDeck(url: link, excludeSideboards: excludeSideboards) }
                else if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    deck = try OnDeviceDeckEditing.importJSON(Data(text.utf8)).deckList
                } else { deck = try importer.importDeck(text: text, name: name) }
                try Task.checkCancellation()
                let saved = try library.addLocalDurably(deck, sourceURL: useLink ? link : nil)
                didImport(saved); dismiss()
            } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
        }
    }
}

@MainActor
private struct NativeDeckEditorSheet: View {
    @ObservedObject var library: DeckLibraryStore
    let record: DeckLibraryRecord?
    let didSave: (DeckLibraryRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeDeckDraft
    @State private var resolver: OnDeviceDeckResolver?
    @State private var search = ""
    @State private var results: [String] = []
    @State private var section = "deck"
    @State private var errorMessage: String?
    @State private var inspection: DeckCardSelection?
    @State private var confirmDiscard = false
    @State private var changed = false

    init(library: DeckLibraryStore, record: DeckLibraryRecord?, didSave: @escaping (DeckLibraryRecord) -> Void) {
        self.library = library; self.record = record; self.didSave = didSave
        _draft = State(initialValue: record.map { NativeDeckDraft(deck: $0.deckList) } ?? NativeDeckDraft())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Deck name", text: $draft.name).onChange(of: draft.name) { _, _ in changed = true }
                    Text("\(draft.rows.reduce(0) { $0 + $1.quantity }) cards · local draft").foregroundStyle(.secondary)
                    Text("Save as you build. The real XMage validator checks Commander rules before play.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Add from the compiled card catalogue") {
                    TextField("Search exact card names", text: $search).autocorrectionDisabled()
                    Picker("Add to", selection: $section) {
                        Text("Main deck").tag("deck")
                        Text("Commander / partner").tag("commanders")
                        Text("Companion").tag("companions")
                    }
                    ForEach(results, id: \.self) { name in
                        HStack {
                            Button { inspection = DeckCardSelection(name: name) } label: {
                                Label(name, systemImage: "magnifyingglass")
                            }.buttonStyle(.borderless)
                            Spacer()
                            Button {
                                if let index = draft.rows.firstIndex(where: { $0.cardName == name && $0.section == section }) {
                                    guard draft.rows[index].quantity < 2000 else { return }
                                    draft.rows[index].quantity += 1
                                } else { draft.rows.append(NativeDeckRow(cardName: name, quantity: 1, section: section)) }
                                changed = true
                            } label: { Image(systemName: "plus.circle.fill").frame(minWidth: 44, minHeight: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Add \(name) to \(section)")
                        }
                    }
                    if !search.isEmpty && results.isEmpty { Text("No compiled card matches this search.").foregroundStyle(.secondary) }
                }
                Section("Cards · swipe to remove") {
                    ForEach($draft.rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { inspection = DeckCardSelection(name: row.cardName) } label: {
                                Label(row.cardName, systemImage: "rectangle.portrait").font(.headline)
                            }.buttonStyle(.borderless)
                            Stepper("Quantity: \(row.quantity)", value: $row.quantity, in: 1...2000)
                                .onChange(of: row.quantity) { _, _ in changed = true }
                            Picker("Section", selection: $row.section) {
                                Text("Main deck").tag("deck")
                                Text("Commander / partner").tag("commanders")
                                Text("Companion").tag("companions")
                                if !["deck", "commanders", "companions"].contains(row.section) {
                                    Text(row.section.capitalized).tag(row.section)
                                }
                            }.onChange(of: row.section) { _, _ in
                                row.isPrimaryCommander = false
                                changed = true
                            }
                        }.padding(.vertical, 5)
                    }.onDelete { draft.rows.remove(atOffsets: $0); changed = true }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) } }
            }
            .scrollContentBackground(.hidden).background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle(record == nil ? "Build a deck" : "Edit deck").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog("Discard unsaved edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard edits", role: .destructive) { dismiss() }
            }
            .sheet(item: $inspection) { card in NativeDeckInspectionSheet(name: card.name) }
            .task {
                do { resolver = try .bundled() } catch { errorMessage = error.localizedDescription }
            }
            .task(id: search) {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard !Task.isCancelled else { return }
                results = resolver?.searchCardNames(query: search, limit: 20) ?? []
            }
        }.preferredColorScheme(.dark)
    }

    private func save() {
        do {
            let deck = try draft.deck()
            let saved: DeckLibraryRecord
            if let record, library.decks.contains(where: { $0.id == record.id }) {
                saved = try library.updateLocalDurably(deck, id: record.id, expectedRevision: record.revision)
            } else { saved = try library.addLocalDurably(deck, sourceURL: record?.sourceURL) }
            changed = false; didSave(saved); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
