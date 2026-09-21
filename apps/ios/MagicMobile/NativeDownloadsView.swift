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
        case "tokens": return []
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
    @State private var scannedSelection: ScanSelection?
    private var scanSelection: ScanSelection {
        ScanSelection(scope: scope, deck: selectedDeckID, quality: quality, catalogueCount: catalogueNames.count, running: downloads.isRunning)
    }
    private var downloadsTokens: Bool { includeTokens || scope == "tokens" }
    private var missingCardCount: Int { scope == "tokens" ? 0 : downloads.missingNames.count }
    private var missingTokenCount: Int { downloadsTokens ? downloads.missingTokenNames.count : 0 }
    private var scanPending: Bool { downloads.isScanning || !downloads.scanSucceeded || scannedSelection != scanSelection }
    private var discoveryIncomplete: Bool {
        scanPending || (scope == "catalogue" && (loadingCatalogue || downloads.faceDiscoveryPending)) ||
            (downloadsTokens && downloads.tokenDiscoveryRemaining > 0)
    }
    private var missingSummary: String {
        if scanPending { return "Checking needed to count missing artwork." }
        let cards = "\(missingCardCount.formatted()) card/face \(missingCardCount == 1 ? "image" : "images")"
        let tokens = "\(missingTokenCount.formatted()) token \(missingTokenCount == 1 ? "image" : "images")"
        let count = scope == "tokens" ? tokens : (downloadsTokens ? "\(cards) · \(tokens)" : cards)
        return discoveryIncomplete ? "Found so far: \(count). Checking needed for the remaining artwork." : "Missing: \(count)"
    }
    private var estimatedAdditionalSize: String {
        guard !discoveryIncomplete else { return "Checking needed" }
        let tokensToDownload = downloadsTokens ? downloads.downloadableMissingTokenCount : 0
        let bytes = Int64(missingCardCount + tokensToDownload) * Int64(quality.estimatedBytes)
        return "≈ \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
    private var preparingDownload: Bool {
        downloads.isScanning || downloads.status.hasPrefix("Preparing") || downloads.status.hasPrefix("Checking")
    }
    private func startDownload() {
        downloads.download(names: names, includeTokens: downloadsTokens, allowNetwork: remoteArtwork,
                           quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens")
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
                        Text("All supported tokens").tag("tokens")
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
                    if scope != "tokens" { Toggle("Include tokens", isOn: $includeTokens)
                        .disabled(downloads.isRunning)
                    }
                } header: { Text("Artwork") } footer: {
                    Text(scope == "tokens" ? "Token-only downloads contain no ordinary card images." : "Full catalogue includes opponents’ cards too.")
                }

                Section("On this device") {
                    if loadingCatalogue && scope == "catalogue" { ProgressView("Reading the installed catalogue…") }
                    if let catalogueError, scope == "catalogue" { Text(catalogueError).foregroundStyle(.red) }
                    if scope != "tokens" {
                        LabeledContent("Cards", value: scanPending || (scope == "catalogue" && loadingCatalogue)
                                       ? "Checking needed" : "\(downloads.cardStored.formatted()) / \(downloads.cardTotal.formatted())")
                            .accessibilityIdentifier("downloads.cards")
                    }
                    LabeledContent("Tokens", value: scanPending || downloads.tokenDiscoveryRemaining > 0
                                   ? "Checking needed" : "\(downloads.tokenStored.formatted()) / \(downloads.tokenTotal.formatted())")
                    if downloads.isScanning { ProgressView("Checking local files…") }
                    LabeledContent("Stored", value: ByteCountFormatter.string(fromByteCount: Int64(downloads.storedBytes), countStyle: .file))
                    LabeledContent("Missing artwork", value: missingSummary)
                    LabeledContent("Estimated additional download", value: estimatedAdditionalSize)
                    Text("Approximate at \(quality.label.lowercased()) quality. Actual download and device storage vary with image sizes, metadata and images already stored.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Check for missing artwork") {
                        Task { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens") }
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
                        if preparingDownload {
                            ProgressView("Preparing image list…")
                        } else {
                            ProgressView(value: Double(downloads.completed), total: Double(max(1, downloads.total)))
                        }
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
                            if scope == "catalogue" || scope == "tokens" { confirmFullDownload = true }
                            else { startDownload() }
                        }
                        .disabled(!remoteArtwork || (names.isEmpty && scope != "tokens") || downloads.isScanning || (scope == "catalogue" && loadingCatalogue))
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
                        Text("Full catalogue covers this build’s supported cards, not every printing. Alternate faces are checked during download. Estimates use currently discovered missing images; more faces or tokens may be found while preparing. Actual download and storage vary. Check for missing artwork after app updates.")
                        Text("Full and token-only downloads use Scryfall’s bulk image index. Deck and on-demand requests share card names and your IP address. Stored artwork works offline.")
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
                let selection = scanSelection
                if !downloads.isRunning {
                    await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens")
                    if selection == scanSelection && !downloads.isScanning && downloads.scanSucceeded { scannedSelection = selection }
                }
            }
            .alert("Download missing artwork?", isPresented: $confirmFullDownload) {
                Button("Download missing images · \(quality.label)") { startDownload() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(missingSummary) \(discoveryIncomplete ? "The additional download estimate needs checking." : "Estimated additional download: \(estimatedAdditionalSize).") This is approximate; actual download and device storage vary. Images continue downloading while you play or leave the app. Wi-Fi is recommended.")
            }
            .onChange(of: remoteArtwork) { _, enabled in if !enabled { downloads.cancel() } }
            .onChange(of: selectedDeckID) { _, deck in
                MagicMobilePreferences.current.set(deck, forKey: "magicmobile.artworkDownloadDeck")
            }
        }
        .preferredColorScheme(.dark)
    }
}
