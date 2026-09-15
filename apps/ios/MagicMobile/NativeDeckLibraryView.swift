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
    @State private var metadata: NativeDeckMetadataCatalogue?
    @State private var resolver: OnDeviceDeckResolver?
    @State private var catalogueError: String?

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
                    Text("Your decks").font(.largeTitle.bold()).foregroundStyle(MagicPalette.parchment)
                    Text("Local drafts and included Commander decks.").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button { sheet = .importer } label: { Label("Import", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                            .buttonStyle(MagicPrimaryButtonStyle(compact: true))
                        Button { sheet = .editor(nil) } label: { Label("New deck", systemImage: "plus").frame(maxWidth: .infinity) }
                            .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                    }
                    DisclosureGroup("Artwork & privacy") { NativeArtworkPreferenceView().padding(.vertical, 8) }
                    if let errorMessage { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) }
                    if let catalogueError { Text(catalogueError).foregroundStyle(MagicPalette.warningAmber) }
                    else if metadata == nil { ProgressView("Loading local card catalogue…") }
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
            .fullScreenCover(item: $sheet) { destination in
                switch destination {
                case .importer:
                    NativeDeckImportSheet(library: library) { record in selectedDeckID = "local:\(record.id)" }
                case .editor(let record):
                    NativeDeckEditorSheet(library: library, record: record, metadata: metadata, catalogueError: catalogueError) { saved in selectedDeckID = "local:\(saved.id)" }
                }
            }
        }.preferredColorScheme(.dark).tint(MagicPalette.antiqueGold)
            .task {
                guard resolver == nil else { return }
                catalogueError = nil
                do {
                    let loaded = try await Task.detached(priority: .userInitiated) {
                        (try NativeDeckMetadataCatalogue.bundled(), try OnDeviceDeckResolver.bundled())
                    }.value
                    try Task.checkCancellation()
                    metadata = loaded.0
                    resolver = loaded.1
                } catch is CancellationError { } catch {
                    catalogueError = "Local card catalogue could not load. Deck selection is unavailable: \(error.localizedDescription)"
                }
            }
    }

    private func deckSection(_ title: String, records: [DeckLibraryRecord], bundled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(MagicPalette.antiqueGold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(records.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.commander?.cardName.localizedCaseInsensitiveContains(search) ?? false) }) { record in
                    NavigationLink {
                        NativeDeckDetailView(library: library, original: record, bundled: bundled,
                                             selectedDeckID: $selectedDeckID, metadata: metadata,
                                             resolver: resolver, catalogueError: catalogueError)
                    } label: {
                        NativeDeckCover(record: record, selected: selectedDeckID == (bundled ? record.id : "local:\(record.id)"))
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
    var contentMode: ContentMode = .fit
    var body: some View {
        NativeCardArtworkView(name: name, variant: inspection ? .inspection : .board, contentMode: contentMode) { _, failed in
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
    var contentMode: ContentMode = .fit
    @ViewBuilder let placeholder: (_ loading: Bool, _ failed: Bool) -> Placeholder
    @AppStorage("magicmobile.deckArtworkNetworkEnabled") private var remoteArtwork = false
    @State private var artwork: UIImage?
    @State private var completedRequest: Request?
    @State private var failedRequest: Request?

    private struct Request: Hashable {
        let name: String
        let variant: NativeDeckArtwork.Variant
        let allowNetwork: Bool
    }

    var body: some View {
        let request = Request(name: name, variant: variant == .inspection ? .inspection : .board, allowNetwork: remoteArtwork)
        let permitted = NativeCardArtworkPolicy.permitsLookup(name: name)
        Group {
            if permitted, completedRequest == request, let artwork {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder(permitted && remoteArtwork && completedRequest != request && failedRequest != request,
                            permitted && failedRequest == request)
            }
        }
            .task(id: request) {
                guard permitted else { artwork = nil; completedRequest = nil; failedRequest = nil; return }
                artwork = nil; completedRequest = nil; failedRequest = nil
                // CardImageURL only supplies a generated cache path here; never fetch its remote fallback.
                if let url = CardImageURL.image(name, variant: variant), url.isFileURL,
                   let data = NativeDeckArtwork.localImageData(at: url),
                   let image = NativeDeckArtwork.decodedImage(data, variant: request.variant) {
                    guard !Task.isCancelled else { return }
                    artwork = UIImage(cgImage: image); completedRequest = request
                    if NativeDeckArtwork.isSufficient(data, for: request.variant) { return }
                    // Keep a safe low-resolution image visible offline or if upgrade fails.
                } else if request.variant == .inspection,
                          let url = CardImageURL.image(name, variant: .board), url.isFileURL,
                          let data = NativeDeckArtwork.localImageData(at: url),
                          let image = NativeDeckArtwork.decodedImage(data, variant: .inspection) {
                    guard !Task.isCancelled else { return }
                    artwork = UIImage(cgImage: image); completedRequest = request
                }
                do {
                    if artwork == nil, request.variant == .inspection,
                       let cached = try await NativeDeckArtwork.shared.imageData(name: name, variant: .board, allowNetwork: false),
                       let image = NativeDeckArtwork.decodedImage(cached, variant: .inspection) {
                        try Task.checkCancellation()
                        artwork = UIImage(cgImage: image); completedRequest = request
                    }
                    guard !Task.isCancelled, request.allowNetwork == remoteArtwork else { return }
                    let data = try await NativeDeckArtwork.shared.imageData(name: name, variant: request.variant, allowNetwork: request.allowNetwork)
                    try Task.checkCancellation()
                    guard request.allowNetwork == remoteArtwork else { return }
                    if let data, let image = NativeDeckArtwork.decodedImage(data, variant: request.variant) {
                        artwork = UIImage(cgImage: image)
                    }
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
    @State private var inspection: DeckCardSelection?
    @State private var editRecord: DeckLibraryRecord?
    @State private var search = ""
    @State private var detailTab = "Cards"
    let metadata: NativeDeckMetadataCatalogue?
    let resolver: OnDeviceDeckResolver?
    let catalogueError: String?
    @State private var cardType = ""
    @State private var color = ""
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

    private var deckContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(record.name).font(.title2.bold()).lineLimit(2).textSelection(.enabled)
                Text("\(NativeDeckDisplay.cardCount(record.cardCount)) · \(bundled ? "Included deck" : "Saved locally")").foregroundStyle(.secondary)
                Text("XMage checks Commander legality when you start a game. Saved drafts may be incomplete.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        guard let resolver else { return }
                        do {
                            _ = try resolver.resolve(record.deckList)
                            selectedDeckID = selectionID
                        } catch { errorMessage = error.localizedDescription }
                    } label: { Label(selectedDeckID == selectionID ? "Selected" : "Use for play", systemImage: "checkmark.shield").frame(maxWidth: .infinity) }
                        .buttonStyle(MagicPrimaryButtonStyle(compact: true))
                        .disabled(resolver == nil)
                    Button {
                        editRecord = bundled || record.isCloudBacked ? DeckLibraryRecord(deck: DeckList(name: "\(record.name) — My copy", commander: record.commander, entries: record.entries), sourceURL: record.sourceURL) : record
                    } label: { Label(bundled || record.isCloudBacked ? "Edit a local copy" : "Edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) }
                if let catalogueError {
                    Text(catalogueError).foregroundStyle(MagicPalette.warningAmber)
                } else if resolver == nil {
                    Text("Loading local card catalogue before deck selection…").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Deck section", selection: $detailTab) {
                    ForEach(["Cards", "Stats", "Info"], id: \.self) {
                        Text($0).tag($0).accessibilityIdentifier("nativeDeck.section.\($0.lowercased())")
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("nativeDeck.sections")
                switch detailTab {
                case "Stats": NativeDeckStatisticsView(deck: record.deckList, metadata: metadata)
                case "Info": infoSection
                default: cardsSection
                }
                if !bundled && !record.isCloudBacked {
                    Button("Delete local deck", role: .destructive) { confirmDelete = true }.padding(.top)
                }
            }.padding(16)
        }
    }

    var body: some View {
        Group {
            if detailTab == "Cards" {
                deckContent.searchable(text: $search, prompt: "Find a card in this deck")
            } else {
                deckContent
            }
        }
        .background(BattlefieldSurface().ignoresSafeArea())
        .navigationTitle("Deck details").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $inspection) { card in NativeDeckInspectionSheet(name: card.name, card: metadata?.card(named: card.name)) }
        .fullScreenCover(item: $editRecord) { draft in
            NativeDeckEditorSheet(library: library, record: draft, metadata: metadata, catalogueError: catalogueError) { saved in selectedDeckID = "local:\(saved.id)" }
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

    private var cardsSection: some View {
        VStack(spacing: 10) {
            NativeDeckFilterBar(cardType: $cardType, color: $color)
            let indexed = Array(allEntries.enumerated()).filter {
                NativeDeckDisplay.matches(name: $0.element.cardName, query: search, type: cardType, color: color, metadata: metadata)
            }
            let groups = Dictionary(grouping: indexed) { item in
                NativeDeckDisplay.group(section: item.element.section,
                    primary: record.commander != nil && item.offset == 0,
                    card: metadata?.card(named: item.element.cardName))
            }
            ForEach(groups.keys.sorted(by: NativeDeckDisplay.groupOrder), id: \.self) { title in
                let rows = groups[title] ?? []
                NativeDeckGroupHeader(title: title, count: rows.reduce(0) { $0 + $1.element.quantity })
                ForEach(rows.sorted { $0.element.cardName < $1.element.cardName }, id: \.offset) { item in
                    let entry = item.element
                    let card = metadata?.card(named: entry.cardName)
                    NativeDeckCardRow(name: entry.cardName, quantity: entry.quantity, manaCost: card?.manaCost,
                                      typeLine: card?.typeLine, inspect: { inspection = DeckCardSelection(name: entry.cardName) })
                    Divider()
                }
            }
            if indexed.isEmpty { Text(search.isEmpty ? "No cards match these filters." : "No cards match this search.").foregroundStyle(.secondary) }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Source", value: bundled ? "Included precon · copy to edit" : (record.isCloudBacked ? "Cloud record · copy to edit" : "Local draft"))
            if let source = record.sourceURL {
                Text("Imported from").font(.headline)
                Text(source).font(.caption).textSelection(.enabled)
            }
            LabeledContent("Saved revision", value: String(record.revision))
            if !bundled { LabeledContent("Updated", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened)) }
            Text("No automatic uploads or edits to the source deck. Selected-printing metadata is local; Commander legality is checked by XMage at game start.")
                .font(.caption).foregroundStyle(.secondary)
            ShareLink(item: exportedText) { Label("Export deck text", systemImage: "square.and.arrow.up") }
            if let exportedJSON {
                ShareLink(item: exportedJSON) { Label("Export complete draft (JSON)", systemImage: "doc.badge.arrow.up") }
                Text("JSON preserves the deck name, commander role and every section, including unfinished drafts. Paste it back into Import to restore a copy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NativeArtworkPreferenceView()
            NativeDeckEDHRECSection(deck: record.deckList)
        }
    }
}

private struct NativeDeckEDHRECSection: View {
    let deck: DeckList
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var openFailed = false

    var body: some View {
        let handoff = NativeDeckEDHREC(deck: deck)
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("EDHREC · manual recommendations").font(.headline)
            Text("1. Copy the main deck below. 2. Open EDHREC, enter your commander(s), paste into Decklist, and submit there. Return here to edit your deck manually.")
                .font(.subheadline)
            Text("Commander(s)").font(.subheadline.bold())
            if handoff.commanders.isEmpty {
                Text("No commander set in this draft. Choose one before requesting recommendations.")
                    .font(.caption).foregroundStyle(MagicPalette.warningAmber)
            } else {
                ForEach(handoff.commanders, id: \.self) { Text($0).textSelection(.enabled) }
            }
            Text("Copies main/deck rows only, with quantities. Commander(s) are entered separately; companion, sideboard and other sections are excluded. Your saved deck is unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            Text("External website: opening EDHREC shares your IP address and browser information. MagicMobile does not send your deck or scrape recommendations. Card names are shared only if you paste them into the website. Copy uses this device’s clipboard only.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: handoff.deckText]],
                                             options: [.localOnly: true])
                copied = true
            } label: {
                Label("Copy main deck text", systemImage: "doc.on.doc").frame(minHeight: 44)
            }.disabled(handoff.deckText.isEmpty).accessibilityIdentifier("nativeDeck.edhrec.copy")
            if copied { Text("Main deck copied. Paste it into EDHREC’s Decklist field.").font(.caption) }
            Button {
                openFailed = false
                openURL(NativeDeckEDHREC.websiteURL) { accepted in openFailed = !accepted }
            } label: {
                Label("Open EDHREC website", systemImage: "arrow.up.right.square").frame(minHeight: 44)
            }.accessibilityIdentifier("nativeDeck.edhrec.open")
            if openFailed {
                Text("Could not open the website. Open https://edhrec.com/recs in your browser.")
                    .font(.caption).textSelection(.enabled).foregroundStyle(MagicPalette.warningAmber)
            }
        }.onChange(of: deck) { _, _ in copied = false }
    }
}

private struct DeckCardSelection: Identifiable {
    var id: String { name }
    let name: String
}

private struct NativeDeckInspectionSheet: View {
    let name: String
    let card: NativeDeckMetadataCatalogue.Card?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NativeCardArtworkView(name: name, variant: .inspection) { _, failed in
                        Label(failed ? "Artwork unavailable" : "Artwork downloads are optional", systemImage: "photo")
                            .font(.caption).foregroundStyle(.secondary).padding(12)
                    }
                        .frame(maxWidth: 360, maxHeight: 400).frame(maxWidth: .infinity)
                    Text(name).font(.title2.bold())
                    if let card {
                        Text(card.typeLine ?? "Type unavailable").font(.headline)
                        NativeDeckManaCost(cost: card.manaCost)
                        Text(card.oracleText ?? "Rules text unavailable in the local catalogue.")
                            .textSelection(.enabled)
                        Text("Local selected-printing metadata. XMage remains authoritative for play.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Card text unavailable in the local catalogue.").foregroundStyle(.secondary)
                    }
                }.padding(16)
            }
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
                        .accessibilityIdentifier("nativeDeck.import.submit")
                } footer: { Text("Exact compiled card names are checked locally. XMage validates deck legality when starting a game.") }
            }
            .scrollContentBackground(.hidden).background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Import deck").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { importTask?.cancel(); dismiss() }
                    .accessibilityIdentifier("nativeDeck.import.cancel")
            } }
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
    let metadata: NativeDeckMetadataCatalogue?
    let catalogueError: String?
    let didSave: (DeckLibraryRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeDeckDraft
    @State private var search = ""
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    @State private var resultLimit = 60
    @State private var portraitPane = "Collection"
    private enum EditorField: Hashable { case search, name }
    @FocusState private var focusedField: EditorField?
    @State private var lastAdded: String?
    @State private var searching = true
    @State private var section = "deck"
    @State private var cardType = ""
    @State private var color = ""
    @State private var errorMessage: String?
    @State private var inspection: DeckCardSelection?
    @State private var confirmDiscard = false
    @State private var changed = false

    init(library: DeckLibraryStore, record: DeckLibraryRecord?, metadata: NativeDeckMetadataCatalogue?, catalogueError: String?, didSave: @escaping (DeckLibraryRecord) -> Void) {
        self.library = library; self.record = record; self.didSave = didSave
        self.metadata = metadata
        self.catalogueError = catalogueError
        _draft = State(initialValue: record.map { NativeDeckDraft(deck: $0.deckList) } ?? NativeDeckDraft())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if NativeDeckBuilderLayout.usesColumns(width: geometry.size.width) {
                        HStack(spacing: 0) {
                            collectionPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                            Rectangle().fill(MagicPalette.antiqueGold.opacity(0.35)).frame(width: 1)
                            deckPane.frame(width: NativeDeckBuilderLayout.deckWidth(width: geometry.size.width))
                        }.accessibilityElement(children: .contain)
                            .accessibilityIdentifier("nativeDeck.builder.split")
                    } else {
                        Picker("Builder view", selection: $portraitPane) {
                            Text("Collection").tag("Collection")
                            Text("Deck (\(totalQuantity))").tag("Deck")
                        }.pickerStyle(.segmented).padding(12)
                            .accessibilityIdentifier("nativeDeck.builder.mode")
                        if portraitPane == "Collection" { collectionPane }
                        else { deckPane }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(MagicPalette.warningAmber)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle(record == nil ? "Build a deck" : "Edit deck").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } }
                        .accessibilityIdentifier("nativeDeck.editor.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save).disabled(!canSave)
                        .accessibilityIdentifier("nativeDeck.editor.save")
                }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog("Discard unsaved edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard edits", role: .destructive) { dismiss() }
            }
            .sheet(item: $inspection) { card in NativeDeckInspectionSheet(name: card.name, card: metadata?.card(named: card.name)) }
            .task(id: [search, cardType, color, metadata == nil ? "loading" : "ready"]) {
                searching = true; results = []; resultLimit = 60
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard !Task.isCancelled else { return }
                refreshResults()
            }
        }.preferredColorScheme(.dark)
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var collectionPane: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MagicPalette.antiqueGold)
                    TextField("Search exact card names", text: $search)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .search).submitLabel(.search)
                        .onSubmit { focusedField = nil }
                        .accessibilityIdentifier("nativeDeck.cardSearch")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                            .accessibilityLabel("Clear card search")
                    }
                }.padding(.leading, 10).frame(minHeight: 44)
                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                NativeDeckBuilderFilters(cardType: $cardType, color: $color)
                HStack {
                    Text("Printed colors · exact match").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Add to", selection: $section) {
                        Text("Main deck").tag("deck")
                        Text("Commander / partner").tag("commanders")
                        Text("Companion").tag("companions")
                    }.pickerStyle(.menu).font(.caption)
                }
            }.padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if metadata == nil {
                        if let catalogueError { Text(catalogueError).foregroundStyle(MagicPalette.warningAmber) }
                        else { ProgressView("Loading local card catalogue…") }
                    } else if searching {
                        ProgressView("Searching local cards…")
                    } else if results.isEmpty {
                        Text("No compiled cards match these filters.").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 12) {
                        ForEach(results) { card in
                            NativeDeckCollectionTile(card: card,
                                count: draft.rows.filter { $0.cardName == card.name }.reduce(0) { $0 + $1.quantity },
                                canAdd: totalQuantity < 2000, section: section,
                                inspect: { inspection = DeckCardSelection(name: card.name) },
                                add: { addCard(card.name) })
                        }
                    }
                    if results.count == resultLimit {
                        if resultLimit < 2000 {
                            Button("Show more cards") { resultLimit = min(2000, resultLimit + 60); refreshResults() }
                                .frame(minHeight: 44).accessibilityIdentifier("nativeDeck.collection.more")
                        } else { Text("Showing 2,000 matches. Refine your search to find more.").font(.caption) }
                    }
                    DisclosureGroup("Artwork & privacy") { NativeArtworkPreferenceView().padding(.vertical, 8) }
                }.padding(12)
            }.scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("nativeDeck.collection.scroll")
            if let lastAdded {
                Text("Added \(lastAdded) · \(NativeDeckDisplay.cardCount(totalQuantity))")
                    .font(.caption).lineLimit(2).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MagicPalette.antiqueGold.opacity(0.12))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deckPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Deck name", text: $draft.name).font(.headline)
                    .focused($focusedField, equals: .name).submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .onChange(of: draft.name) { _, _ in changed = true }
                Text("\(NativeDeckDisplay.cardCount(totalQuantity)) · \(changed ? "Unsaved changes" : "Local draft")")
                    .font(.caption).foregroundStyle(MagicPalette.antiqueGold)
            }.padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    NativeDeckBasicLandTools(count: { draft.basicLandCount($0) },
                        supported: { metadata?.card(named: $0) != nil },
                        change: { name, delta in
                            do {
                                try draft.setBasicLandCount(name, quantity: draft.basicLandCount(name) + delta)
                                changed = true
                            } catch { errorMessage = error.localizedDescription }
                        }, canAdd: totalQuantity < 2000)
                    ForEach(editorGroups, id: \.self) { group in
                        let rows = draft.rows.filter { groupName($0) == group }
                        NativeDeckGroupHeader(title: group, count: rows.reduce(0) { $0 + $1.quantity })
                        ForEach(rows) { row in
                            NativeDeckBuilderRow(row: row, card: metadata?.card(named: row.cardName),
                                canAdd: totalQuantity < 2000,
                                inspect: { inspection = DeckCardSelection(name: row.cardName) },
                                increase: { changeQuantity(id: row.id, delta: 1) },
                                decrease: { changeQuantity(id: row.id, delta: -1) },
                                remove: { draft.rows.removeAll { $0.id == row.id }; changed = true },
                                move: { moveRow(id: row.id, to: $0) })
                        }
                    }
                    if draft.rows.isEmpty {
                        Text("Your deck is empty. Add cards from the collection.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    Text("XMage checks Commander legality before play.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(10)
            }.scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("nativeDeck.editor.rows")
            VStack(spacing: 6) {
                Button(action: save) { Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(MagicPrimaryButtonStyle(compact: true)).disabled(!canSave)
                    .accessibilityIdentifier("nativeDeck.editor.done")
            }.padding(10)
        }.frame(maxHeight: .infinity).background(.black.opacity(0.25))
    }

    private func addCard(_ name: String) {
        guard metadata?.card(named: name) != nil, totalQuantity < 2000 else { return }
        if let index = draft.rows.firstIndex(where: {
            let effectiveSection = $0.isPrimaryCommander ? "commanders" : $0.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return $0.cardName == name && (effectiveSection == section || (section == "deck" && effectiveSection == "main"))
        }) {
            draft.rows[index].quantity += 1
        } else { draft.rows.append(NativeDeckRow(cardName: name, quantity: 1, section: section)) }
        changed = true; lastAdded = name
    }

    private func moveRow(id: UUID, to section: String) {
        guard let index = draft.rows.firstIndex(where: { $0.id == id }) else { return }
        draft.rows[index].section = section
        draft.rows[index].isPrimaryCommander = false
        changed = true
    }

    private var totalQuantity: Int { draft.rows.reduce(0) { $0 + $1.quantity } }
    private func groupName(_ row: NativeDeckRow) -> String {
        NativeDeckDisplay.group(section: row.section, primary: row.isPrimaryCommander,
                                card: metadata?.card(named: row.cardName))
    }
    private var editorGroups: [String] { Set(draft.rows.map(groupName)).sorted(by: NativeDeckDisplay.groupOrder) }

    private func changeQuantity(id: UUID, delta: Int) {
        guard let index = draft.rows.firstIndex(where: { $0.id == id }), delta < 0 || totalQuantity < 2000 else { return }
        if draft.rows[index].quantity + delta <= 0 { draft.rows.remove(at: index) }
        else { draft.rows[index].quantity += delta }
        changed = true
    }

    private func refreshResults() {
        if let metadata {
            var filter = NativeDeckMetadataCatalogue.SearchFilter()
            filter.query = search; filter.type = cardType
            filter.colors = color.isEmpty ? nil : (color == "C" ? [] : [color])
            results = metadata.search(filter, limit: resultLimit)
        } else {
            results = []
        }
        searching = false
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
