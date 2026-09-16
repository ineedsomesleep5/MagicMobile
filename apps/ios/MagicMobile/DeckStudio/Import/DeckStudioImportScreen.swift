import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Vision
import ImageIO

@MainActor
struct DeckStudioImportScreen: View {
    @ObservedObject var library: DeckLibraryStore
    let resolver: OnDeviceDeckResolver?
    let didImport: (DeckLibraryRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var method = "Paste"
    @State private var name = "Imported Commander Deck"
    @State private var text = ""
    @State private var link = ""
    @State private var excludeSideboards = false
    @State private var preview: OnDeviceDeckLinkImporter.Preview?
    @State private var sourceURL: String?
    @State private var error: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var photo: PhotosPickerItem?
    @State private var filePicker = false
    @State private var scanNotice: String?
    @State private var receiptURL: URL?
    @State private var saved: DeckLibraryRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Bring your deck.").font(.system(.largeTitle, design: .serif).weight(.bold))
                    Text("Paste, link, or scan a decklist. Review every card before saving.").foregroundStyle(DeckStudioPalette.secondaryInk)
                    Picker("Import method", selection: $method) {
                        Text("Paste").tag("Paste"); Text("Link").tag("Link"); Text("Scan image").tag("Scan")
                    }.pickerStyle(.segmented).disabled(busy || saved != nil)
                    inputPanel
                    if let scanNotice { DeckStudioNotice(title: "Check recognized text", message: scanNotice) }
                    if let error { DeckStudioNotice(title: "Import needs attention", message: error, icon: "exclamationmark.triangle") }
                    if busy { ProgressView(method == "Scan" ? "Reading image on this device…" : "Preparing review…") }
                    if method != "Scan" {
                        Button("Review decklist", action: beginPreview).buttonStyle(DeckStudioButtonStyle())
                            .disabled(busy || resolver == nil || saved != nil || (method == "Link" ? link : text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("deckStudio.import.review")
                    }
                    if let preview { review(preview) }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(DeckStudioPalette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("Import deck").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if let preview {
                    Button(saved == nil ? "Save reviewed draft" : "Finish import") { save(preview) }
                        .buttonStyle(DeckStudioButtonStyle()).padding(16).frame(maxWidth: .infinity)
                        .background(DeckStudioPalette.background).disabled(busy)
                        .accessibilityIdentifier("deckStudio.import.confirm")
                }
            }
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
            .onChange(of: method) { _, _ in invalidate() }
            .onChange(of: excludeSideboards) { _, _ in invalidate() }
            .onChange(of: photo) { _, item in if let item { beginScan(item) } }
            .onDisappear { task?.cancel() }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    private var inputPanel: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 14) {
                if method == "Paste" {
                    TextField("Deck name", text: $name).textFieldStyle(.roundedBorder)
                    TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 220)
                        .scrollContentBackground(.hidden).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Decklist text")
                    Text("Commander\n1 Your Commander\n\nDeck\n1 Sol Ring")
                        .font(.caption.monospaced()).foregroundStyle(DeckStudioPalette.secondaryInk)
                    Button("Open text or native JSON file", systemImage: "doc") { filePicker = true }.frame(minHeight: 44)
                } else if method == "Link" {
                    TextField("Public Archidekt or Moxfield deck URL", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    Toggle("Exclude sideboard / maybeboard", isOn: $excludeSideboards)
                    Text("Public links only, subject to provider access. This contacts the deck provider. No sign-in, bot-check bypass or scraping. When a provider is unavailable, paste its text export instead.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    Button("Switch to pasted export") { method = "Paste" }.frame(minHeight: 44)
                } else {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose decklist photo or screenshot", systemImage: "text.viewfinder").frame(minHeight: 60)
                    }
                    Text("Apple Vision recognizes text on this device. Images are not uploaded. You will review and correct the recognized text before parsing; this is not a physical-card scanner.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
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
                Label("XMage Commander validation: not run", systemImage: "clock")
                Text("\(DeckStudioDraftPresentation.gameCount(draft)) main + commander cards; \(preview.deck.totalCards) across all imported sections.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                Text("Saving a draft does not certify legality. Exact rules validation remains in game setup until the dedicated editor validation service is added.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                DisclosureGroup("Review cards and sections") {
                    ForEach(draft.rows) { row in
                        HStack { Text("\(row.quantity)× \(row.cardName)"); Spacer(); Text(DeckStudioDraftPresentation.section(row)).font(.caption) }
                        if preview.unresolvedNames.contains(row.cardName) { Text("Unresolved; retained in draft").font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                    }
                }
                if !preview.annotations.isEmpty {
                    DisclosureGroup("\(preview.annotations.count) source annotations") {
                        ForEach(Array(preview.annotations.enumerated()), id: \.offset) { _, note in
                            Text("Line \(note.line): \(note.text)").font(.caption)
                        }
                    }
                    Text("An on-device import receipt preserves these annotations and the reviewed deck. Printing annotations do not change the compiled gameplay identity.").font(.caption2)
                }
            }
        }
    }
    private func invalidate() {
        guard saved == nil else { return }
        generation = UUID(); task?.cancel(); busy = false; preview = nil; receiptURL = nil
    }
    private func beginPreview() {
        guard let resolver else { return }
        invalidate(); error = nil; busy = true
        let token = generation, input = text, title = name, url = link, fromLink = method == "Link", exclude = excludeSideboards
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                let importer = OnDeviceDeckLinkImporter(resolver: resolver)
                let result: OnDeviceDeckLinkImporter.Preview
                if fromLink { result = try importer.preview(await importer.importDeck(url: url, excludeSideboards: exclude, reviewOnly: true)) }
                else if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { result = try importer.preview(OnDeviceDeckEditing.importJSON(Data(input.utf8)).deckList) }
                else { result = try importer.preview(text: input, name: title) }
                try Task.checkCancellation()
                guard generation == token else { return }
                preview = result; sourceURL = fromLink ? url : nil
            } catch is CancellationError { } catch { if generation == token { self.error = error.localizedDescription } }
        }
    }
    private func beginScan(_ item: PhotosPickerItem) {
        invalidate(); error = nil; busy = true
        let token = generation
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw OnDeviceDeckResolver.ResolutionError("Could not read the chosen image.") }
                guard data.count <= 20 * 1024 * 1024 else { throw OnDeviceDeckResolver.ResolutionError("Choose an image no larger than 20 MiB.") }
                let recognized = try await Task.detached(priority: .userInitiated) { try DeckStudioOCR.recognize(data) }.value
                try Task.checkCancellation()
                guard generation == token else { return }
                text = recognized; method = "Paste"
                scanNotice = "OCR can misread quantities and card names. Correct the text, then choose Review decklist."
            } catch is CancellationError { } catch { if generation == token { self.error = error.localizedDescription } }
        }
    }
    private func save(_ preview: OnDeviceDeckLinkImporter.Preview) {
        do {
            // Archive review information first; a library write failure cannot lose it.
            if receiptURL == nil { receiptURL = try DeckStudioImportReceipt.store(preview, sourceURL: sourceURL) }
            if saved == nil { saved = try library.addLocalDurably(preview.deck, sourceURL: sourceURL) }
            if let saved { didImport(saved); dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

private enum DeckStudioOCR {
    static func recognize(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000,
              Int64(width) * Int64(height) <= 80_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3000
              ] as CFDictionary) else { throw OnDeviceDeckResolver.ResolutionError("The image is unsupported or too large to read safely.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.isEmpty, text.utf8.count <= OnDeviceDeckLinkImporter.maximumBytes else { throw OnDeviceDeckResolver.ResolutionError("No usable decklist text was found. Try a clearer image or paste an export.") }
        return text
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
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }
}
