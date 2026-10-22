import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DeckStudioImportScreen: View {
    @ObservedObject var library: DeckLibraryStore
    let resolver: OnDeviceDeckResolver?
    let didImport: (DeckLibraryRecord) -> Void
    @StateObject private var validation = DeckStudioValidationState()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grimoireClose) private var grimoireClose
    /// Inside the book, leaving turns the page back.
    private func leave() { if let grimoireClose { grimoireClose() } else { dismiss() } }
    @State private var method = "Paste"
    @State private var name = "Imported Commander Deck"
    @State private var text = ""
    @State private var link = ""
    @State private var excludeSideboards = false
    @State private var preview: OnDeviceDeckLinkImporter.Preview?
    @State private var sourceURL: String?
    @State private var error: String?
    @State private var busy = false
    @State private var saving = false
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var filePicker = false
    @State private var receiptURL: URL?
    @State private var saved: DeckLibraryRecord?
    /// Commander first: the card the player picks leads the import even when the list doesn't mark it.
    @State private var commander: String?
    @State private var commanderQuery = ""
    @State private var commanderSuggestions: [NativeDeckMetadataCatalogue.Card] = []
    @State private var metadata: NativeDeckMetadataCatalogue?
    /// Archidekt account: a username's public decks, picked with checkmarks.
    @State private var archidektUser = ""
    @State private var archidektDecks: [OnDeviceDeckLinkImporter.ArchidektDeckSummary] = []
    @State private var archidektPage = 0
    @State private var archidektHasMore = false
    @State private var archidektSearched = false
    @State private var listing = false
    @State private var listTask: Task<Void, Never>?
    @State private var picked: Set<Int> = []
    /// Several picked decks are saved one by one: each deck's outcome, in order.
    @State private var batch: [(name: String, outcome: BatchOutcome)] = []
    private enum BatchOutcome { case waiting, saved, failed(String) }
    @State private var batchDone = false
    private var pickedDecks: [OnDeviceDeckLinkImporter.ArchidektDeckSummary] { archidektDecks.filter { picked.contains($0.id) } }
    private var isBatch: Bool { method == "Account" && picked.count > 1 }

    var body: some View {
        NavigationStack {
            Group {
                if spread {
                    // The list goes in on the left page and is reviewed on the right; nothing runs across the fold.
                    // The head is written on the left page, so both pages are the same height.
                    HStack(alignment: .top, spacing: 6) {
                        BinderPage(gutter: .trailing) {
                            VStack(spacing: 0) {
                                importHead
                                ScrollView { VStack(alignment: .leading, spacing: 20) { entry }.padding(16) }
                            }
                        }
                        BinderPage(gutter: .leading) {
                            VStack(spacing: 0) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 20) {
                                        if preview == nil {
                                            Text("Your decklist appears here for review, card by card, before anything is saved.")
                                                .font(.callout).italic().foregroundStyle(DeckStudioPalette.secondaryInk)
                                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                        }
                                        reviewed
                                    }.padding(16)
                                }
                                confirmButton
                            }
                        }
                    }
                } else {
                    BinderPage(gutter: .leading) {
                        VStack(spacing: 0) {
                            importHead
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    entry
                                    reviewed
                                }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
                            }
                            .safeAreaInset(edge: .bottom) { confirmButton }
                        }
                    }
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 2)
            .scrollDismissesKeyboard(.interactively)
            .binderScreen()
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(saving)
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.plainText, .json]) { result in
                do {
                    let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let data = try handle.read(upToCount: OnDeviceDeckLinkImporter.maximumBytes + 1) ?? Data()
                    guard data.count <= OnDeviceDeckLinkImporter.maximumBytes, let value = String(data: data, encoding: .utf8) else {
                        throw OnDeviceDeckResolver.ResolutionError("Choose a UTF-8 deck file of at most 2 MiB.")
                    }
                    text = value; name = url.deletingPathExtension().lastPathComponent; method = "Paste"
                } catch { self.error = error.localizedDescription }
            }
            .onChange(of: text) { _, _ in invalidate() }
            .onChange(of: name) { _, _ in invalidate() }
            .onChange(of: link) { _, _ in invalidate() }
            .onChange(of: method) { _, value in
                invalidate()
                // Most Archidekt decks keep a maybeboard; a whole account would otherwise stop at each one.
                if value == "Account" { excludeSideboards = true }
            }
            .onChange(of: excludeSideboards) { _, _ in invalidate() }
            .onChange(of: commander) { _, _ in invalidate() }
            .onChange(of: picked) { _, _ in invalidate() }
            .task { metadata = await Task.detached(priority: .userInitiated) { try? NativeDeckMetadataCatalogue.bundled() }.value }
            .task(id: commanderQuery) { await suggestCommanders() }
            .onDisappear { task?.cancel(); listTask?.cancel(); validation.cancelPending() }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.accent).preferredColorScheme(.dark)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { wide = $0 }
    }
    /// The binder's head: Cancel as the strap, the page's name stamped beside it.
    private var importHead: some View {
        BinderHead(strap: "Cancel", strapIdentifier: "deckStudio.import.cancel", title: "Import deck", strapDisabled: saving,
                   action: { task?.cancel(); validation.cancelPending(); leave() }) { Color.clear.frame(width: 44, height: 1) }
    }
    /// Sideways the book lies open as a spread: two pages, each with its own content.
    @State private var wide = UIScreen.main.bounds.width > UIScreen.main.bounds.height
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var spread: Bool { wide && !dynamicType.isAccessibilitySize }   // Grimoire.isSpread

    /// Where the list goes in: the heading, the method, the input, and Review. In a spread, the left page.
    @ViewBuilder private var entry: some View {
        Text("Bring your deck.").font(.largeTitle.weight(.bold)).tracking(-1)
        Text("Paste or link a decklist. Review every card before saving.").foregroundStyle(DeckStudioPalette.secondaryInk)
        GrimoireChoice(title: "Import method", options: [("Paste", "Paste"), ("Link", "Link"), ("Account", "Archidekt")], selection: $method)
            .disabled(busy || saved != nil || !batch.isEmpty)
        if !isBatch && batch.isEmpty { commanderPanel }
        inputPanel
        if !batch.isEmpty { batchPanel }
        if let error { DeckStudioNotice(title: "Import needs attention", message: error, icon: "exclamationmark.triangle") }
        if busy { ProgressView(saving ? "Saving deck and import details…" : "Preparing review…") }
        if method == "Account" {
            if batchDone {
                Button("Done", action: leave).buttonStyle(DeckStudioButtonStyle()).accessibilityIdentifier("deckStudio.import.batchDone")
            } else if !picked.isEmpty {
                Button(isBatch ? "Import \(picked.count) decks" : "Review deck", action: isBatch ? importPicked : beginPreview)
                    .buttonStyle(DeckStudioButtonStyle())
                    .disabled(busy || resolver == nil || saved != nil || !batch.isEmpty)
                    .accessibilityIdentifier("deckStudio.import.review")
            }
        } else {
            Button("Review decklist", action: beginPreview).buttonStyle(DeckStudioButtonStyle())
                .disabled(busy || resolver == nil || saved != nil || (method == "Link" ? link : text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("deckStudio.import.review")
        }
    }

    /// The reviewed list and its rules check. In a spread, the right page.
    @ViewBuilder private var reviewed: some View {
        if let preview {
            review(preview)
            DeckStudioValidationPanel(state: validation, deck: preview.deck, resolver: resolver)
        }
    }

    @ViewBuilder private var confirmButton: some View {
        if let preview {
            Button(saved == nil ? "Save reviewed draft" : "Finish import") { save(preview) }
                .buttonStyle(DeckStudioButtonStyle()).padding(16).frame(maxWidth: .infinity)
                .background(GrimoirePaper()).disabled(busy)
                .accessibilityIdentifier("deckStudio.import.confirm")
        }
    }
    /// Type a commander's name and pick it from the suggestions, as on Archidekt.
    private var commanderPanel: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Commander").font(.headline)
                if let commander {
                    HStack(spacing: 12) {
                        if !dynamicType.isAccessibilitySize {
                            DeckStudioArtwork(name: commander).frame(width: 40, height: 56).clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(commander).font(.subheadline.weight(.semibold))
                            Text("Leads the deck, even if the list marks another card or none.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Button("Change") { self.commander = nil; commanderQuery = "" }
                            .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("deckStudio.import.commander.change")
                    }.accessibilityElement(children: .combine)
                } else {
                    Text("Optional. Pick it first and the import treats it as your commander, even when the list doesn't say so.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    TextField("Type a commander's name", text: $commanderQuery).textFieldStyle(GrimoireFieldStyle())
                        .autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.done)
                        .onSubmit { if let first = commanderSuggestions.first { chooseCommander(first.name) } }
                        .accessibilityIdentifier("deckStudio.import.commander.search")
                    if metadata == nil, !commanderQuery.isEmpty {
                        Text("The card catalogue is still loading.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    } else if commanderSuggestions.isEmpty, !commanderQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("No legendary creature or commander matches \"\(commanderQuery)\".").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                    ForEach(commanderSuggestions) { card in
                        Button { chooseCommander(card.name) } label: {
                            HStack(spacing: 12) {
                                if !dynamicType.isAccessibilitySize {
                                    DeckStudioArtwork(name: card.name).frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.name).font(.subheadline.weight(.medium))
                                    Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                DeckStudioColorIdentity(colors: card.colorIdentity)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Choose \(card.name) as commander")
                    }
                }
            }.disabled(busy || saved != nil)
        }
    }
    /// An Archidekt username's public decks. Pick one to review it, or several to save them all as drafts.
    @ViewBuilder private var archidektPicker: some View {
        HStack(spacing: 10) {
            TextField("Archidekt username", text: $archidektUser).textFieldStyle(GrimoireFieldStyle())
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .onSubmit { findArchidektDecks(more: false) }
                .accessibilityIdentifier("deckStudio.import.archidekt.username")
            Button("Find decks") { findArchidektDecks(more: false) }
                .buttonStyle(BinderPlaqueButtonStyle())
                .disabled(busy || listing || archidektUser.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("deckStudio.import.archidekt.find")
        }
        Toggle("Exclude sideboard / maybeboard", isOn: $excludeSideboards)
        Text("Lists the public decks on that Archidekt account. No sign-in: private and unlisted decks don't appear, so make them public or paste their text export. This contacts Archidekt.")
            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
        if listing { ProgressView("Asking Archidekt…") }
        if archidektSearched && archidektDecks.isEmpty && !listing {
            Text("No public decks found for \"\(archidektUser.trimmingCharacters(in: .whitespaces))\".").font(.callout)
        }
        if !archidektDecks.isEmpty {
            HStack {
                Text("\(archidektDecks.count) public decks · \(picked.count) picked").font(.subheadline.weight(.semibold))
                Spacer()
                Button(picked.count == archidektDecks.count ? "Clear" : "Pick all") {
                    picked = picked.count == archidektDecks.count ? [] : Set(archidektDecks.map(\.id))
                }.frame(minHeight: 44)
            }
            ForEach(archidektDecks) { deck in
                Button { if picked.contains(deck.id) { picked.remove(deck.id) } else { picked.insert(deck.id) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: picked.contains(deck.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deck.name).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                            Text([deck.size.map { "\($0) cards" }, deck.updatedDay.map { "updated \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(picked.contains(deck.id) ? [.isSelected] : [])
                    .accessibilityIdentifier("deckStudio.import.archidekt.deck.\(deck.id)")
            }
            if archidektHasMore {
                Button("Show more decks") { findArchidektDecks(more: true) }.frame(minHeight: 44).disabled(busy || listing)
            }
            if isBatch {
                Text("Several decks are saved as drafts straight away. Open each one in your library to review it and pick its commander.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
        }
    }
    private var batchPanel: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(batchDone ? "Import finished" : "Importing decks…").font(.headline)
                ForEach(Array(batch.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        switch item.outcome {
                        case .waiting: Image(systemName: "clock")
                        case .saved: Image(systemName: "checkmark.circle")
                        case .failed: Image(systemName: "exclamationmark.triangle")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline)
                            if case .failed(let reason) = item.outcome { Text(reason).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func findArchidektDecks(more: Bool) {
        guard let resolver, !busy, !listing else { return }
        let user = archidektUser, page = more ? archidektPage + 1 : 1
        error = nil; listing = true
        if !more { archidektDecks = []; picked = []; archidektSearched = false }
        listTask = Task { @MainActor in
            defer { listing = false }
            do {
                let found = try await OnDeviceDeckLinkImporter(resolver: resolver).archidektDecks(username: user, page: page)
                let known = Set(archidektDecks.map(\.id))
                archidektDecks += found.decks.filter { !known.contains($0.id) }
                archidektPage = page; archidektHasMore = found.hasMore; archidektSearched = true
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    /// Saves each picked deck as a draft, one at a time, and lists what happened to each.
    private func importPicked() {
        guard let resolver, !busy else { return }
        let decks = pickedDecks, exclude = excludeSideboards
        invalidate(); error = nil; busy = true; saving = true
        batch = decks.map { ($0.name, .waiting) }
        task = Task { @MainActor in
            defer { busy = false; saving = false; batchDone = true }
            let importer = OnDeviceDeckLinkImporter(resolver: resolver)
            for (index, deck) in decks.enumerated() {
                do {
                    try Task.checkCancellation()
                    let preview = try importer.preview(await importer.importDeck(url: deck.link, excludeSideboards: exclude, reviewOnly: true))
                    let receipt = try DeckStudioImportReceipt.store(preview, sourceURL: deck.link)
                    let record = try library.addLocalDurably(preview.deck, sourceURL: deck.link)
                    try await DeckStudioOrganizationStore.shared.retainImport(recordID: record.id, annotations: [], source: deck.link,
                                                                              receiptFile: receipt.lastPathComponent)
                    batch[index].outcome = .saved
                } catch is CancellationError { return } catch {
                    batch[index].outcome = .failed(error.localizedDescription)
                }
            }
        }
    }
    private func chooseCommander(_ name: String) {
        commander = name; commanderQuery = ""; commanderSuggestions = []
    }
    private func suggestCommanders() async {
        let query = commanderQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let metadata, !query.isEmpty else { commanderSuggestions = []; return }
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        let found = await Task.detached(priority: .userInitiated) {
            DeckStudioCatalogueSearch.commanders(in: metadata, query: query, limit: 6)
        }.value
        guard !Task.isCancelled, query == commanderQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        commanderSuggestions = found
    }
    private var inputPanel: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 14) {
                if method == "Paste" {
                    TextField("Deck name", text: $name).textFieldStyle(GrimoireFieldStyle())
                    TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 220)
                        .scrollContentBackground(.hidden).padding(10).grimoireField(cornerRadius: 12)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Decklist text")
                    Text("Commander\n1 Your Commander\n\nDeck\n1 Sol Ring").font(.caption.monospaced()).foregroundStyle(DeckStudioPalette.secondaryInk)
                    Button("Open text or native JSON file", systemImage: "doc") { filePicker = true }.frame(minHeight: 44)
                } else if method == "Link" {
                    TextField("Public Archidekt or Moxfield deck URL", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(GrimoireFieldStyle())
                    Toggle("Exclude sideboard / maybeboard", isOn: $excludeSideboards)
                    Text("Public links only, subject to provider access. This contacts the deck provider. No sign-in, bot-check bypass or scraping. When a provider is unavailable, paste its text export instead.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    Button("Switch to pasted export") { method = "Paste" }.frame(minHeight: 44)
                } else {
                    archidektPicker
                }
            }.disabled(busy || saved != nil)
        }
    }
    private func review(_ preview: OnDeviceDeckLinkImporter.Preview) -> some View {
        let draft = NativeDeckDraft(deck: preview.deck)
        return DeckStudioPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(preview.deck.name).font(.title2.weight(.semibold))
                Label("Parsed · syntax accepted", systemImage: "checkmark.circle")
                Label(preview.unresolvedNames.isEmpty ? "Names resolved in the compiled catalogue" : "\(preview.unresolvedNames.count) unresolved names retained",
                      systemImage: preview.unresolvedNames.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                Text("\(DeckStudioDraftPresentation.gameCount(draft)) main + commander cards; \(preview.deck.totalCards) across all imported sections.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                Text("Parsing and name resolution do not certify Commander legality. Check with XMage below, or save an unfinished draft and continue editing. Validation never silently discards other boards.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                DisclosureGroup("Review cards and sections") {
                    ForEach(draft.rows) { row in
                        HStack { Text("\(row.quantity)× \(row.cardName)"); Spacer(); Text(DeckStudioDraftPresentation.section(row)).font(.caption) }
                        if preview.unresolvedNames.contains(row.cardName) { Text("Unresolved; retained in draft").font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                    }
                }
                if !preview.annotations.isEmpty {
                    DisclosureGroup("\(preview.annotations.count) source annotations") {
                        ForEach(Array(preview.annotations.enumerated()), id: \.offset) { _, note in Text("Line \(note.line): \(note.text)").font(.caption) }
                    }
                    Text("An on-device import receipt preserves these annotations and the reviewed deck. A printing written as (SET) number is kept as that card's chosen artwork; it does not change the compiled gameplay identity.").font(.caption2)
                }
            }
        }
    }
    private func invalidate() {
        guard saved == nil else { return }
        generation = UUID(); task?.cancel(); busy = false; preview = nil; receiptURL = nil; validation.prepare(nil)
    }
    private func beginPreview() {
        guard let resolver else { return }
        invalidate(); error = nil; busy = true
        let token = generation, input = text, title = name, fromLink = method == "Link" || method == "Account", exclude = excludeSideboards, lead = commander
        let url = method == "Account" ? pickedDecks.first?.link ?? "" : link
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                let importer = OnDeviceDeckLinkImporter(resolver: resolver)
                var result: OnDeviceDeckLinkImporter.Preview
                if fromLink { result = try importer.preview(await importer.importDeck(url: url, excludeSideboards: exclude, reviewOnly: true)) }
                else if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { result = try importer.preview(OnDeviceDeckEditing.importJSON(Data(input.utf8)).deckList) }
                else { result = try importer.preview(text: input, name: title) }
                if let lead { result = try importer.preview(result, commander: lead) }
                try Task.checkCancellation()
                guard generation == token else { return }
                preview = result; sourceURL = fromLink ? url : nil
            } catch is CancellationError { } catch { if generation == token { self.error = error.localizedDescription } }
        }
    }
    private func save(_ preview: OnDeviceDeckLinkImporter.Preview) {
        guard !busy else { return }
        busy = true; saving = true; error = nil
        task = Task { @MainActor in
            defer { busy = false; saving = false }
            do {
                if receiptURL == nil { receiptURL = try DeckStudioImportReceipt.store(preview, sourceURL: sourceURL) }
                if saved == nil { saved = try library.addLocalDurably(preview.deck, sourceURL: sourceURL) }
                guard let saved, let receiptURL else { return }
                try await DeckStudioOrganizationStore.shared.retainImport(recordID: saved.id,
                    annotations: preview.annotations.map { "Line \($0.line): \($0.text)" },
                    source: sourceURL, receiptFile: receiptURL.lastPathComponent)
                // A check made during review applies to the saved deck: same playing cards.
                if let receipt = validation.receipt {
                    DeckStudioReceiptStore.shared.record(DeckStudioStoredCheck(deckID: "local:\(saved.id)", receipt: receipt))
                }
                didImport(saved); leave()
            } catch {
                self.error = saved == nil ? error.localizedDescription :
                    "The deck is saved and its full receipt is archived, but linking the details failed. Tap Finish import to retry without making another deck. " + error.localizedDescription
            }
        }
    }

}

private struct DeckStudioImportReceipt: Codable {
    struct Annotation: Codable { let line: Int; let text: String }
    let schemaVersion: Int
    let createdAt: Date
    let sourceURL: String?
    let deck: DeckList
    let annotations: [Annotation]
    static func store(_ preview: OnDeviceDeckLinkImporter.Preview, sourceURL: String?) throws -> URL {
        let receipt = Self(schemaVersion: 1, createdAt: .now, sourceURL: sourceURL, deck: preview.deck,
                           annotations: preview.annotations.map { Annotation(line: $0.line, text: $0.text) })
        let data = try JSONEncoder().encode(receipt)
        guard data.count <= 4 * 1024 * 1024 else { throw OnDeviceDeckResolver.ResolutionError("Import receipt is too large. Your library has not changed.") }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobile/DeckStudio/ImportReceipts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        return url
    }
}
