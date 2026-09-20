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
    @AppStorage("magicmobile.artworkDownloadTokens") private var includeTokens = true
    @AppStorage("magicmobile.artworkDownloadScope") private var scope = "catalogue"
    @State private var catalogueNames: [String] = []
    @State private var loadingCatalogue = true
    @State private var catalogueError: String?
    @State private var confirmFullDownload = false
    @AppStorage("magicmobile.artworkDownloadQuality") private var quality: NativeArtworkQuality = .standard
    @ObservedObject private var downloads = NativeAssetDownloads.shared
    @AppStorage(NativeArtworkPreference.key) private var remoteArtwork = false
    @Environment(\.dismiss) private var dismiss

    init(decks: [NativeDownloadDeck], selectedDeckID: String, engineReady: Bool) {
        self.decks = decks
        self.engineReady = engineReady
        let previousDeck = MagicMobilePreferences.current.string(forKey: "magicmobile.artworkDownloadDeck") ?? selectedDeckID
        _selectedDeckID = State(initialValue: decks.contains { $0.id == previousDeck }
                               ? previousDeck : decks.first?.id ?? "")
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
        let running: Bool
    }
    private var scanSelection: ScanSelection {
        ScanSelection(scope: scope, deck: selectedDeckID, quality: quality, catalogueCount: catalogueNames.count, running: downloads.isRunning)
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
                    Toggle("Include tokens", isOn: $includeTokens)
                        .disabled(downloads.isRunning)
                } header: { Text("Artwork") } footer: {
                    Text("Full catalogue includes opponents’ cards too.")
                }

                Section("On this device") {
                    if loadingCatalogue && scope == "catalogue" { ProgressView("Reading the installed catalogue…") }
                    if let catalogueError, scope == "catalogue" { Text(catalogueError).foregroundStyle(.red) }
                    LabeledContent("Cards", value: "\(downloads.cardStored.formatted()) / \(downloads.cardTotal.formatted())")
                        .accessibilityIdentifier("downloads.cards")
                    LabeledContent("Tokens", value: downloads.tokenDiscoveryRemaining > 0 ? "Not checked" : "\(downloads.tokenStored.formatted()) / \(downloads.tokenTotal.formatted())")
                    if downloads.isScanning { ProgressView("Checking local files…") }
                    LabeledContent("Stored", value: ByteCountFormatter.string(fromByteCount: Int64(downloads.storedBytes), countStyle: .file))
                    LabeledContent("Full download estimate", value: "≈ \(estimatedSize)")
                    Button("Check for missing artwork") {
                        Task { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue") }
                    }
                    .disabled(downloads.isRunning || downloads.isScanning)
                    .accessibilityIdentifier("downloads.check")
                }

                Section {
                    Toggle("Download card artwork", isOn: $remoteArtwork)
                        .accessibilityIdentifier("nativeArtwork.downloads")
                    Text("Uses Scryfall. Online requests share your IP and card names, including your hand.")
                        .font(.caption).foregroundStyle(.secondary)
                    if downloads.isRunning {
                        ProgressView(value: Double(downloads.completed), total: Double(max(1, downloads.total)))
                        Text(downloads.status).font(.callout)
                            .accessibilityIdentifier("downloads.status")
                        Button("Cancel download", role: .cancel) { downloads.cancel() }
                            .accessibilityIdentifier("downloads.cancel")
                    } else {
                        if downloads.total > 0 && !downloads.status.isEmpty {
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
                } header: { Text("Download") } footer: {
                    Text("You can play or leave the app while images download. Wi-Fi is recommended.")
                }

                Section {
                    DisclosureGroup("More info") {
                        Label(engineReady ? "Local engine ready" : "Local engine not ready", systemImage: engineReady ? "checkmark.circle" : "exclamationmark.circle")
                        Label(catalogueIncluded ? "Card catalogue included" : "Card catalogue unavailable", systemImage: catalogueIncluded ? "checkmark.circle" : "exclamationmark.circle")
                        Label("Mana symbols included", systemImage: "checkmark.circle")
                        Text("These downloads supply artwork for decks and games. Rules and the supported card catalogue are already included; artwork is optional.")
                        Text("Compact saves space. Standard balances clarity and size. High gives the sharpest inspection images. Higher-quality files already stored count toward lower-quality coverage.")
                        Text("Full catalogue covers this build’s supported cards, not every printing. Alternate faces are checked during download. Estimates exclude faces, tokens and metadata; actual size varies. Check for missing artwork after app updates.")
                        Text("Full downloads use Scryfall’s bulk image index. Deck and on-demand requests share card names and your IP address. Stored artwork works offline.")
                        Text("Compact is fastest. Downloads use several direct image transfers at once and remember completed files. iOS controls background timing; force-quitting pauses transfers until you reopen the app. The initial image-list preparation may need the app open on a slow connection.")
                        Text("Storage is capped at 20 GB, with 1 GB of free space reserved. Unavailable or ambiguous token art remains a labeled placeholder. Use Download missing artwork to retry interruptions.")
                    }
                    .font(.callout)
                    .accessibilityIdentifier("downloads.info")
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
                    Section {
                        DisclosureGroup("Missing tokens · \(downloads.missingTokenNames.count.formatted())") {
                            ForEach(Array(downloads.missingTokenNames.prefix(20).enumerated()), id: \.offset) { _, name in Text(name) }
                        }
                    }
                }
                if !downloads.missingNames.isEmpty {
                    Section {
                        DisclosureGroup("Missing cards · \(downloads.missingNames.count.formatted())") {
                            ForEach(downloads.missingNames.prefix(20), id: \.self) { Text($0) }
                            if downloads.missingNames.count > 20 {
                                Text("And \(downloads.missingNames.count - 20) more")
                                    .foregroundStyle(.secondary)
                            }
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
            .task(id: scanSelection) {
                if !downloads.isRunning { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue") }
            }
            .alert("Download the full catalogue?", isPresented: $confirmFullDownload) {
                Button("Download \(names.count) cards · \(quality.label)") { startDownload() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Approximately \(estimatedSize), plus tokens and the image list. Actual size varies. Images continue downloading while you play or leave the app. Wi-Fi is recommended.")
            }
            .onChange(of: remoteArtwork) { _, enabled in if !enabled { downloads.cancel() } }
            .onChange(of: selectedDeckID) { _, deck in
                MagicMobilePreferences.current.set(deck, forKey: "magicmobile.artworkDownloadDeck")
            }
        }
        .preferredColorScheme(.dark)
    }
}
