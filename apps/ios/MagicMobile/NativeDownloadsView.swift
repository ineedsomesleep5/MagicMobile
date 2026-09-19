import SwiftUI
import UIKit

struct NativeDownloadDeck: Identifiable {
    let id: String
    let name: String
    let cardNames: [String]

    init(id: String, deck: DeckList) {
        self.id = id
        name = deck.name
        cardNames = Array(Set(deck.entries.map(\.cardName) + [deck.commander?.cardName].compactMap { $0 })).sorted()
    }
}

/// Explicit artwork downloads, separate from the bundled rules engine and catalogue.
struct NativeDownloadsView: View {
    let decks: [NativeDownloadDeck]
    let engineReady: Bool
    @State private var selectedDeckID: String
    @State private var includeTokens = true
    @State private var scope = "catalogue"
    @State private var catalogueNames: [String] = []
    @State private var loadingCatalogue = true
    @State private var catalogueError: String?
    @State private var confirmFullDownload = false
    @AppStorage("magicmobile.artworkDownloadQuality") private var quality: NativeArtworkQuality = .standard
    @StateObject private var downloads = NativeAssetDownloads()
    @AppStorage(NativeArtworkPreference.key) private var remoteArtwork = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(decks: [NativeDownloadDeck], selectedDeckID: String, engineReady: Bool) {
        self.decks = decks
        self.engineReady = engineReady
        _selectedDeckID = State(initialValue: decks.contains { $0.id == selectedDeckID }
                               ? selectedDeckID : decks.first?.id ?? "")
    }

    private var names: [String] {
        switch scope {
        case "catalogue": return catalogueNames
        case "decks": return Array(Set(decks.flatMap(\.cardNames))).sorted()
        default: return decks.first { $0.id == selectedDeckID }?.cardNames ?? []
        }
    }
    private struct ScanSelection: Equatable {
        let scope: String
        let deck: String
        let quality: NativeArtworkQuality
        let catalogueCount: Int
    }
    private var scanSelection: ScanSelection {
        ScanSelection(scope: scope, deck: selectedDeckID, quality: quality, catalogueCount: catalogueNames.count)
    }
    private var estimatedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(names.count) * Int64(quality.estimatedBytes), countStyle: .file)
    }
    private func startDownload() {
        downloads.download(names: names, includeTokens: includeTokens, allowNetwork: remoteArtwork,
                           quality: quality, fullCatalogue: scope == "catalogue")
    }
    private var catalogueIncluded: Bool {
        Bundle.main.url(forResource: "ondevice-catalogue", withExtension: "json") != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(engineReady ? "Local engine ready" : "Local engine not ready", systemImage: engineReady ? "checkmark.circle" : "exclamationmark.circle")
                    Label(catalogueIncluded ? "Card catalogue included" : "Card catalogue unavailable", systemImage: catalogueIncluded ? "checkmark.circle" : "exclamationmark.circle")
                    Label("Mana symbols included", systemImage: "checkmark.circle")
                } header: { Text("Included with the app") } footer: {
                    Text("Rules and the card catalogue ship with this build. Artwork is optional and does not change gameplay rules.")
                }

                Section {
                    Picker("Download", selection: $scope) {
                        Text("Full catalogue · recommended").tag("catalogue")
                        Text("All saved & included decks").tag("decks")
                        Text("One deck").tag("deck")
                    }
                    .disabled(downloads.isRunning)
                    .accessibilityIdentifier("downloads.scope")
                    if scope == "deck" {
                        Picker("Deck", selection: $selectedDeckID) {
                            ForEach(decks) { Text($0.name).tag($0.id) }
                        }
                        .disabled(downloads.isRunning)
                        .accessibilityIdentifier("downloads.deck")
                    }
                    Picker("Image quality", selection: $quality) {
                        ForEach(NativeArtworkQuality.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(downloads.isRunning)
                    .accessibilityIdentifier("downloads.quality")
                    Text(quality == .compact ? "Small files; text may look soft when inspecting a card." :
                         quality == .high ? "Sharpest inspection artwork; largest download." : "Balanced clarity and storage for everyday play.")
                        .font(.caption).foregroundStyle(.secondary)
                    if loadingCatalogue && scope == "catalogue" { ProgressView("Reading the installed catalogue…") }
                    if let catalogueError, scope == "catalogue" { Text(catalogueError).foregroundStyle(.red) }
                    LabeledContent("Cards stored", value: "\(downloads.cardStored) / \(downloads.cardTotal)")
                        .accessibilityIdentifier("downloads.cards")
                    LabeledContent("Related tokens stored", value: "\(downloads.tokenStored) / \(downloads.tokenTotal)")
                    if downloads.tokenDiscoveryRemaining > 0 {
                        Text(scope == "catalogue" ? "The full token index still needs downloading. Keep Include related tokens enabled to include it." : "Related tokens still need checking for \(downloads.tokenDiscoveryRemaining) cards. Enable related tokens when downloading to check them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if scope == "catalogue" && downloads.faceDiscoveryPending {
                        Text("Alternate faces will be checked and added when the full image index downloads.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if downloads.isScanning { ProgressView("Checking local files…") }
                    LabeledContent("Offline artwork storage", value: ByteCountFormatter.string(fromByteCount: Int64(downloads.storedBytes), countStyle: .file))
                    LabeledContent("Estimated complete download", value: "≈ \(estimatedSize)")
                    Button("Check downloaded assets") {
                        Task { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue") }
                    }
                    .disabled(downloads.isRunning || downloads.isScanning)
                    .accessibilityIdentifier("downloads.check")
                } header: { Text("Offline artwork") } footer: {
                    Text("Full catalogue is recommended so opponents’ cards can also appear offline. It covers this build’s supported cards, not every printing. Estimates exclude alternate faces, tokens and metadata and vary by image. Higher-quality images already stored count toward lower-quality coverage. New app builds may add cards; check again after updating.")
                }

                Section {
                    Toggle("Download card artwork", isOn: $remoteArtwork)
                        .accessibilityIdentifier("nativeArtwork.downloads")
                    Text("Optional: Scryfall receives displayed card names, including your hand, and your IP address. Applies to decks and gameplay. Cached artwork works offline; rules stay on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Include related tokens", isOn: $includeTokens)
                        .disabled(downloads.isRunning)
                    if downloads.isRunning {
                        ProgressView(value: Double(downloads.completed), total: Double(max(1, downloads.total)))
                        Text(downloads.status).font(.callout)
                            .accessibilityIdentifier("downloads.status")
                        Button("Cancel download", role: .cancel) { downloads.cancel() }
                            .accessibilityIdentifier("downloads.cancel")
                    } else {
                        if !downloads.status.isEmpty {
                            Text(downloads.status).font(.callout)
                                .accessibilityIdentifier("downloads.status")
                        }
                        Button("Download missing artwork") {
                            if scope == "catalogue" { confirmFullDownload = true }
                            else { startDownload() }
                        }
                        .disabled(!remoteArtwork || names.isEmpty || downloads.isScanning || (scope == "catalogue" && loadingCatalogue))
                        .accessibilityIdentifier("downloads.start")
                    }
                } header: { Text("Download options") } footer: {
                    Text("Artwork comes from Scryfall and is the same artwork used in games. Deck downloads share requested card names and your IP address; full-catalogue downloads use Scryfall’s bulk image index. Use Wi-Fi and keep this screen open. The screen stays awake during downloads. Large downloads can take hours; cancel or close the app and resume missing items later. A 20 GB artwork limit and 1 GB free-space reserve protect storage. Some unavailable or ambiguous token variants remain labeled placeholders.")
                }

                if !downloads.failures.isEmpty {
                    Section("Needs attention") {
                        ForEach(Array(downloads.failures.prefix(20).enumerated()), id: \.offset) { _, failure in
                            Text(failure).font(.callout)
                        }
                        if downloads.failures.count > 20 {
                            Text("And \(downloads.failures.count - 20) more issues. Check missing artwork below.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Use Download missing artwork to retry. Already stored artwork is preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !downloads.missingTokenNames.isEmpty {
                    Section("Missing token artwork · \(downloads.missingTokenNames.count)") {
                        ForEach(Array(downloads.missingTokenNames.prefix(20).enumerated()), id: \.offset) { _, name in Text(name) }
                    }
                }
                if !downloads.missingNames.isEmpty {
                    Section("Missing artwork · \(downloads.missingNames.count)") {
                        ForEach(downloads.missingNames.prefix(20), id: \.self) { Text($0) }
                        if downloads.missingNames.count > 20 {
                            Text("And \(downloads.missingNames.count - 20) more")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CommanderPresentation.canvas)
            .tint(CommanderPresentation.accent)
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do {
                    catalogueNames = try await Task.detached(priority: .utility) {
                        try NativeDeckMetadataCatalogue.bundled().artworkCardNames
                    }.value
                } catch { catalogueError = "The installed card catalogue could not be read. Deck downloads are still available." }
                loadingCatalogue = false
            }
            .task(id: scanSelection) { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue") }
            .alert("Download the full catalogue?", isPresented: $confirmFullDownload) {
                Button("Download \(names.count) cards · \(quality.label)") { startDownload() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Approximately \(estimatedSize), plus token artwork and the image index. Actual size varies. This can take hours. Use Wi-Fi, keep this screen open, and resume missing items later if interrupted.")
            }
            .onChange(of: downloads.isRunning) { _, running in UIApplication.shared.isIdleTimerDisabled = running && scenePhase == .active }
            .onChange(of: remoteArtwork) { _, enabled in if !enabled { downloads.cancel() } }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { downloads.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
            }
            .onDisappear { downloads.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        }
        .preferredColorScheme(.dark)
    }
}
