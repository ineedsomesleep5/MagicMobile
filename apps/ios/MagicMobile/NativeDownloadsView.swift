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
    }
    @State private var scannedSelection: ScanSelection?
    private var scanSelection: ScanSelection {
        ScanSelection(scope: scope, deck: selectedDeckID, quality: quality, catalogueCount: catalogueNames.count)
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
        BundledCatalogueData.url(in: .main) != nil
    }

    var body: some View {
        // The tavern's own page (Caleb, 2026-10-04): leather title bar with the wax-seal close,
        // leather cards in brass, parchment pickers and plaque buttons; no system form chrome.
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TavernPanelTitle(text: String(localized: "Downloads"))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("downloads.title")
                Spacer(minLength: 8)
                Button { dismiss() } label: { TavernSealLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Done"))
                    .accessibilityIdentifier("downloads.close")
            }
            .modifier(TavernTitleBar())
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    artworkCard
                    deviceCard
                    downloadCard
                    if !downloads.failures.isEmpty { failuresCard }
                    if !downloads.missingTokenNames.isEmpty || !downloads.missingNames.isEmpty { missingCard }
                    infoCard
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(TavernSheetBackground().ignoresSafeArea())
        .environment(\.tavernBoard, true)
        .tavernConfirmation(active: true, title: String(localized: "Download missing artwork?"),
                            message: "\(missingSummary) \(discoveryIncomplete ? "The additional download estimate needs checking." : "Estimated additional download: \(estimatedAdditionalSize).") This is approximate; actual download and device storage vary. Images continue downloading while you play or leave the app. Wi-Fi is recommended.",
                            isPresented: $confirmFullDownload,
                            actions: [TavernDialogAction(title: "Download missing images · \(quality.label)") { startDownload() }])
        .task {
            do {
                catalogueNames = try await Task.detached(priority: .utility) {
                    try NativeDeckMetadataCatalogue.bundled().artworkCardNames
                }.value
            } catch { catalogueError = "The installed card catalogue could not be read. Deck downloads are still available." }
            loadingCatalogue = false
        }
        .task(id: scanSelection) {
            // Checking reads one directory listing, so it also runs during a download.
            let selection = scanSelection
            await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens")
            if selection == scanSelection && !downloads.isScanning && downloads.scanSucceeded { scannedSelection = selection }
        }
        .onChange(of: remoteArtwork) { _, enabled in if !enabled { downloads.cancel() } }
        .onChange(of: selectedDeckID) { _, deck in
            MagicMobilePreferences.current.set(deck, forKey: "magicmobile.artworkDownloadDeck")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Cards

    private var artworkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Artwork")
            TavernPicker(title: "Download", selection: $scope, sections: [.init(options: [
                ("Full catalogue · recommended", "catalogue"), ("All supported tokens", "tokens"),
                ("All saved & included decks", "decks"), ("One deck", "deck")])], identifier: "downloads.scope")
                .disabled(downloads.isRunning)
            if scope == "deck" {
                TavernPicker(title: "Deck", selection: $selectedDeckID, sections: [.init(options: decks.map { ($0.name, $0.id) })],
                             identifier: "downloads.deck")
                    .disabled(downloads.isRunning)
            }
            TavernPicker(title: "Image quality", selection: $quality,
                         sections: [.init(options: NativeArtworkQuality.allCases.map { ($0.label, $0) })], identifier: "downloads.quality")
                .disabled(downloads.isRunning)
            if scope != "tokens" {
                TavernToggle(title: "Include tokens", isOn: $includeTokens).disabled(downloads.isRunning)
            }
            note(scope == "tokens" ? "Token-only downloads contain no ordinary card images." : "Full catalogue includes opponents’ cards too.")
        }
        .modifier(TavernLeatherCard())
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("On this device")
            if loadingCatalogue && scope == "catalogue" { working("Reading the installed catalogue…") }
            if let catalogueError, scope == "catalogue" {
                Text(catalogueError).font(.system(size: 14, design: .serif)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.45))
            }
            if scope != "tokens" {
                row("Cards", scanPending || (scope == "catalogue" && loadingCatalogue)
                    ? "Checking needed" : "\(downloads.cardStored.formatted()) / \(downloads.cardTotal.formatted())")
                    .accessibilityIdentifier("downloads.cards")
            }
            row("Tokens", scanPending || downloads.tokenDiscoveryRemaining > 0
                ? "Checking needed" : "\(downloads.tokenStored.formatted()) / \(downloads.tokenTotal.formatted())")
            if downloads.isScanning { working("Checking local files…") }
            row("Stored", ByteCountFormatter.string(fromByteCount: Int64(downloads.storedBytes), countStyle: .file))
            row("Missing artwork", missingSummary)
            row("Estimated additional download", estimatedAdditionalSize)
            note("Approximate at \(quality.label.lowercased()) quality. Actual download and device storage vary with image sizes, metadata and images already stored.")
            Button("Check for missing artwork") {
                Task { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens") }
            }
            .buttonStyle(TavernButtonStyle(kind: .secondary, fullWidth: true))
            .disabled(downloads.isRunning || downloads.isScanning)
            .accessibilityIdentifier("downloads.check")
        }
        .modifier(TavernLeatherCard())
    }

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Download")
            TavernToggle(title: "Download card artwork", isOn: $remoteArtwork, identifier: "nativeArtwork.downloads",
                         subtitle: "Uses Scryfall. Online requests share your IP and card names, including your hand.")
            if downloads.isRunning {
                if preparingDownload {
                    working("Preparing image list…")
                } else {
                    BrassProgressBar(fraction: Double(downloads.completed) / Double(max(1, downloads.total)))
                }
                Text(downloads.status).font(.system(size: 14, design: .serif))
                    .accessibilityIdentifier("downloads.status")
                Button("Cancel download") { downloads.cancel() }
                    .buttonStyle(TavernButtonStyle(kind: .danger, fullWidth: true))
                    .accessibilityIdentifier("downloads.cancel")
            } else {
                if downloads.total > 0 && !downloads.status.isEmpty {
                    Text(downloads.status).font(.system(size: 14, design: .serif))
                        .accessibilityIdentifier("downloads.status")
                }
                Button("Download missing artwork") {
                    if scope == "catalogue" || scope == "tokens" { confirmFullDownload = true }
                    else { startDownload() }
                }
                .buttonStyle(TavernButtonStyle(kind: .primary, fullWidth: true))
                .disabled(!remoteArtwork || (names.isEmpty && scope != "tokens") || downloads.isScanning || (scope == "catalogue" && loadingCatalogue))
                .accessibilityIdentifier("downloads.start")
            }
            note("You can play or leave the app while images download. Wi-Fi is recommended.")
        }
        .modifier(TavernLeatherCard())
    }

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Needs attention")
            ForEach(Array(downloads.failures.prefix(20).enumerated()), id: \.offset) { _, failure in
                Text(failure).font(.system(size: 14, design: .serif))
            }
            if downloads.failures.count > 20 { note("And \(downloads.failures.count - 20) more issues. Check missing artwork below.") }
            note("Use Download missing artwork to retry. Already stored artwork is preserved.")
        }
        .modifier(TavernParchmentCard())
    }

    private var missingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !downloads.missingTokenNames.isEmpty {
                TavernDisclosure(title: "Missing tokens · \(downloads.missingTokenNames.count.formatted())") {
                    ForEach(Array(downloads.missingTokenNames.prefix(20).enumerated()), id: \.offset) { _, name in
                        Text(name).font(.system(size: 13, design: .serif))
                    }
                }
            }
            if !downloads.missingNames.isEmpty {
                TavernDisclosure(title: "Missing cards · \(downloads.missingNames.count.formatted())") {
                    ForEach(downloads.missingNames.prefix(20), id: \.self) { Text($0).font(.system(size: 13, design: .serif)) }
                    if downloads.missingNames.count > 20 { note("And \(downloads.missingNames.count - 20) more") }
                }
            }
        }
        .modifier(TavernLeatherCard())
    }

    private var infoCard: some View {
        TavernDisclosure(title: "More info") {
            status(engineReady ? "Local engine ready" : "Local engine not ready", ok: engineReady)
            status(catalogueIncluded ? "Card catalogue included" : "Card catalogue unavailable", ok: catalogueIncluded)
            status("Mana symbols included", ok: true)
            note("These downloads supply artwork for decks and games. Rules and the supported card catalogue are already included; artwork is optional.")
            note("Compact saves space. Standard balances clarity and size. High gives the sharpest inspection images. Higher-quality files already stored count toward lower-quality coverage.")
            note("Full catalogue covers this build’s supported cards, not every printing. Alternate faces are checked during download. Estimates use currently discovered missing images; more faces or tokens may be found while preparing. Actual download and storage vary. Check for missing artwork after app updates.")
            note("Full and token-only downloads use Scryfall’s bulk image index. Deck and on-demand requests share card names and your IP address. Stored artwork works offline.")
            note("Compact is fastest. Downloads use several direct image transfers at once and remember completed files. iOS controls background timing; force-quitting pauses transfers until you reopen the app. The initial image-list preparation may need the app open on a slow connection.")
            note("Storage is capped at 20 GB, with 1 GB of free space reserved. Unavailable or ambiguous token art remains a labeled placeholder. Use Download missing artwork to retry interruptions.")
        }
        .modifier(TavernLeatherCard())
        .accessibilityIdentifier("downloads.info")
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
            .foregroundStyle(BrandTheme.brassGradient)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold, design: .serif))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 14, design: .serif)).monospacedDigit().multilineTextAlignment(.trailing).opacity(0.85)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12, design: .serif)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(TavernPalette.brass)
            Text(text).font(.system(size: 14, design: .serif))
        }
    }

    private func status(_ text: String, ok: Bool) -> some View {
        Label {
            Text(text).font(.system(size: 14, design: .serif))
        } icon: {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? AnyShapeStyle(BrandTheme.brassGradient) : AnyShapeStyle(Color(red: 1, green: 0.55, blue: 0.45)))
        }
    }
}

/// A brass-rimmed groove filling with ember: a download's progress in the tavern.
struct BrassProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.5))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.32), TavernPalette.ember], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(10, proxy.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
            .overlay(Capsule().strokeBorder(BrandTheme.brassGradient, lineWidth: 1.5))
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Download progress"))
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded()))%")
    }
}

/// A section that opens and closes under a brass chevron, in place of the system disclosure group.
struct TavernDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title).font(.system(size: 15, weight: .heavy, design: .serif))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content }
                    .transition(.opacity)
            }
        }
    }
}
