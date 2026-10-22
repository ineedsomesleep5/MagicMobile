import SwiftUI
import UIKit

struct NativeDownloadDeck: Identifiable {
    let id: String
    let name: String
    let cardNames: [String]
    /// The printings whose art the player chose in this deck.
    let chosenArt: [NativeChosenArt]

    init(id: String, deck: DeckList) {
        self.id = id
        name = deck.name
        cardNames = Array(Set(deck.entries.map(\.cardName) + [deck.commander?.cardName].compactMap { $0 })).sorted()
        chosenArt = NativeChosenArt.choices(in: deck)
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
    /// The art chosen in Deck Studio always comes with a download of cards: this deck's for One deck,
    /// every saved deck's otherwise (the full catalogue included), and none for tokens alone.
    private var chosenArt: [NativeChosenArt] {
        if scope == "tokens" { return [] }
        let source = scope == "deck" ? (decks.first { $0.id == selectedDeckID }?.chosenArt ?? []) : decks.flatMap(\.chosenArt)
        var seen = Set<String>()
        return source.filter { seen.insert($0.printing.key).inserted }
    }
    private struct ScanSelection: Equatable {
        let scope: String
        let deck: String
        let quality: NativeArtworkQuality
        let catalogueCount: Int
        let chosen: [String]
    }
    @State private var scannedSelection: ScanSelection?
    private var scanSelection: ScanSelection {
        ScanSelection(scope: scope, deck: selectedDeckID, quality: quality, catalogueCount: catalogueNames.count,
                      chosen: chosenArt.map { $0.printing.key })
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
                           quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens", chosen: chosenArt)
    }
    private var catalogueIncluded: Bool {
        BundledCatalogueData.url(in: .main) != nil
    }

    var body: some View {
        // Arena's panel (Caleb, 2026-10-22): what is on this phone and the Download plaque first, then what to download,
        // chosen from diamond rows and a tab strip; the technical notes fold away at the foot.
        VStack(spacing: 0) {
            ArenaPanelHeader(title: String(localized: "Downloads"), closeIdentifier: "downloads.close")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    optionsCard
                    if !downloads.failures.isEmpty { failuresCard }
                    if !downloads.missingTokenNames.isEmpty || !downloads.missingNames.isEmpty { missingCard }
                    infoCard
                }
                .padding(16)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .mask(ArenaScrollFade(depth: 48))
        }
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
            await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens", chosen: chosenArt)
            if selection == scanSelection && !downloads.isScanning && downloads.scanSucceeded { scannedSelection = selection }
        }
        .onChange(of: remoteArtwork) { _, enabled in if !enabled { downloads.cancel() } }
        .onChange(of: selectedDeckID) { _, deck in
            MagicMobilePreferences.current.set(deck, forKey: "magicmobile.artworkDownloadDeck")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Cards

    /// The readout at the head of the status card (the judge, 2026-10-22: one count, never a sentence that contradicts
    /// it): how many images this phone holds of how many, or how far a download has come, with its gold bar.
    private var readout: (count: String, fraction: Double?) {
        if downloads.isRunning && !preparingDownload {
            return (String(localized: "\(downloads.completed.formatted()) of \(downloads.total.formatted()) downloaded"),
                    Double(downloads.completed) / Double(max(1, downloads.total)))
        }
        let tokensOnly = scope == "tokens"
        let stored = tokensOnly ? downloads.tokenStored : downloads.cardStored
        let total = tokensOnly ? downloads.tokenTotal : downloads.cardTotal
        guard total > 0, !scanPending else { return (String(localized: "Artwork on this phone"), nil) }
        return (String(localized: "\(stored.formatted()) of \(total.formatted()) stored"), Double(stored) / Double(total))
    }

    /// Where things stand, once, in small type under the readout.
    private var stateLine: String {
        if downloads.isRunning { return preparingDownload ? String(localized: "Preparing image list…") : downloads.status }
        if downloads.isScanning { return String(localized: "Checking local files…") }
        if loadingCatalogue && scope == "catalogue" { return String(localized: "Reading the installed catalogue…") }
        if scanPending { return String(localized: "Checking needed") }
        let missing = missingCardCount + missingTokenCount
        if missing == 0 && !discoveryIncomplete { return String(localized: "All artwork stored") }
        // Still counting says nothing the readout's spinner doesn't (the judge, 2026-10-22).
        if discoveryIncomplete { return "" }
        return String(localized: "\(missing.formatted()) missing · about \(estimatedAdditionalSize.replacingOccurrences(of: "≈ ", with: "")) at \(quality.label.lowercased()) quality")
    }

    /// The rest of what this phone holds: the tokens (beside cards) and the space it takes.
    private var coverage: String {
        let stored = ByteCountFormatter.string(fromByteCount: Int64(downloads.storedBytes), countStyle: .file)
        var parts: [String] = []
        if scope != "tokens", !scanPending, downloads.tokenDiscoveryRemaining == 0, downloads.tokenTotal > 0 {
            parts.append(String(localized: "Tokens \(downloads.tokenStored.formatted()) of \(downloads.tokenTotal.formatted())"))
        }
        // Nothing stored yet is not worth a line ("Zero KB on this phone", the judge, 2026-10-22).
        if downloads.storedBytes > 0 { parts.append(String(localized: "\(stored) on this phone")) }
        return parts.joined(separator: " · ")
    }

    private var checkButton: some View {
        Button("Check") {
            Task { await downloads.scan(names: names, quality: quality, fullCatalogue: scope == "catalogue" || scope == "tokens", tokenOnly: scope == "tokens", chosen: chosenArt) }
        }
        .buttonStyle(ArenaPillButtonStyle())
        .disabled(downloads.isRunning || downloads.isScanning)
        .accessibilityLabel(String(localized: "Check for missing artwork"))
        .accessibilityIdentifier("downloads.check")
    }

    /// First: what is on this phone, what is missing, the consent and the Download plaque.
    private var statusCard: some View {
        let current = readout
        return VStack(alignment: .leading, spacing: 10) {
            // Check stands on the readout's line (the judge, 2026-10-22: not alone in a band of its own).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(current.count).font(ArenaMenuStyle.font(22, .bold)).foregroundStyle(ArenaMenuStyle.text).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("downloads.summary")
                Spacer(minLength: 6)
                checkButton
            }
            if let fraction = current.fraction { BrassProgressBar(fraction: fraction, gold: !downloads.isRunning) }
            HStack(spacing: 8) {
                if downloads.isScanning || preparingDownload || (loadingCatalogue && scope == "catalogue") {
                    ProgressView().tint(ArenaMenuStyle.gold).controlSize(.small)
                }
                if !stateLine.isEmpty {
                    Text(stateLine).font(ArenaMenuStyle.font(12, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("downloads.status")
                }
            }
            if !coverage.isEmpty {
                Text(coverage).font(ArenaMenuStyle.font(13, .medium)).foregroundStyle(ArenaMenuStyle.dim).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("downloads.cards")
            }
            if let catalogueError, scope == "catalogue" {
                Text(catalogueError).font(ArenaMenuStyle.font(13, .medium)).foregroundStyle(ArenaMenuStyle.loss)
            }
            // The consent, named for what it allows so it doesn't repeat the Download plaque under it; what it shares stays
            // in view because it is the consent's terms, not help.
            TavernToggle(title: "Online card art", isOn: $remoteArtwork, identifier: "nativeArtwork.downloads",
                         subtitle: "Uses Scryfall. Online requests share your IP and card names, including your hand.")
            Text("Shares your IP and card names with Scryfall.")
                .font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            if downloads.isRunning {
                Button(String(localized: "Cancel download")) { downloads.cancel() }
                    .buttonStyle(ArenaPlayButtonStyle(cancel: true, fontSize: 16))
                    .frame(height: 46)
                    .accessibilityIdentifier("downloads.cancel")
            } else {
                if downloads.total > 0 && !downloads.status.isEmpty {
                    note(downloads.status)
                }
                Button(String(localized: "Download missing artwork")) {
                    if scope == "catalogue" || scope == "tokens" { confirmFullDownload = true }
                    else { startDownload() }
                }
                .buttonStyle(ArenaPlayButtonStyle(fontSize: 17))
                .frame(height: 46)
                .disabled(!remoteArtwork || (names.isEmpty && scope != "tokens") || downloads.isScanning || (scope == "catalogue" && loadingCatalogue))
                .accessibilityIdentifier("downloads.start")
            }
        }
        .arenaCard()
    }

    /// Each scope by its name alone (the judge, 2026-10-22: no subline under every option).
    private struct ScopeOption: Identifiable {
        let title: String
        let value: String
        var id: String { value }
    }
    private static let scopes = [
        ScopeOption(title: "Full catalogue", value: "catalogue"),
        ScopeOption(title: "Tokens only", value: "tokens"),
        ScopeOption(title: "All my decks", value: "decks"),
        ScopeOption(title: "One deck", value: "deck"),
    ]
    @State private var choosingDeck = false

    /// Then what to download: the scope as diamond rows, the deck when it is one deck, the quality as a tab strip.
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArenaCaps(text: "What to download")
            VStack(spacing: 0) {
                ForEach(Self.scopes) { option in
                    ArenaOptionRow(title: option.title, selected: scope == option.value,
                                   identifier: "downloads.scope.\(option.value)") {
                        scope = option.value
                        if option.value != "deck" { choosingDeck = false }
                    }
                }
            }
            .disabled(downloads.isRunning)
            if scope == "deck" { deckChooser }
            ArenaCaps(text: "Image quality").padding(.top, 4)
            ArenaSegmented(options: NativeArtworkQuality.allCases.map { ($0.label, $0) }, selection: $quality,
                           identifier: "downloads.quality", stretch: true)
                .disabled(downloads.isRunning)
            if scope != "tokens" {
                TavernToggle(title: "Include tokens", isOn: $includeTokens).disabled(downloads.isRunning)
            }
        }
        .arenaCard()
    }

    /// One deck: the chosen deck's name, which opens the list of decks in place.
    private var deckChooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArenaOptionRow(title: "Deck", value: decks.first { $0.id == selectedDeckID }?.name ?? "—", chevron: true,
                           identifier: "downloads.deck") {
                withAnimation(.easeOut(duration: 0.18)) { choosingDeck.toggle() }
            }
            if choosingDeck {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(decks) { deck in
                            ArenaOptionRow(title: deck.name, selected: deck.id == selectedDeckID,
                                           identifier: "downloads.deck.\(deck.id)") {
                                selectedDeckID = deck.id
                                withAnimation(.easeOut(duration: 0.18)) { choosingDeck = false }
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
                .frame(maxHeight: 220)
                .transition(.opacity)
            }
        }
        .disabled(downloads.isRunning)
    }

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArenaCaps(text: "Needs attention")
            ForEach(Array(downloads.failures.prefix(20).enumerated()), id: \.offset) { _, failure in
                Text(failure).font(ArenaMenuStyle.font(13, .medium))
            }
            if downloads.failures.count > 20 { note("And \(downloads.failures.count - 20) more issues. Check missing artwork below.") }
        }
        .arenaCard()
    }

    private var missingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !downloads.missingTokenNames.isEmpty {
                TavernDisclosure(title: "Missing tokens · \(downloads.missingTokenNames.count.formatted())") {
                    ForEach(Array(downloads.missingTokenNames.prefix(20).enumerated()), id: \.offset) { _, name in
                        Text(name).font(ArenaMenuStyle.font(13, .medium))
                    }
                }
            }
            if !downloads.missingNames.isEmpty {
                TavernDisclosure(title: "Missing cards · \(downloads.missingNames.count.formatted())") {
                    ForEach(downloads.missingNames.prefix(20), id: \.self) { Text($0).font(ArenaMenuStyle.font(13, .medium)) }
                    if downloads.missingNames.count > 20 { note("And \(downloads.missingNames.count - 20) more") }
                }
            }
        }
        .arenaCard()
    }

    private var infoCard: some View {
        TavernDisclosure(title: "More info") {
            status(engineReady ? "Local engine ready" : "Local engine not ready", ok: engineReady)
            status(catalogueIncluded ? "Card catalogue included" : "Card catalogue unavailable", ok: catalogueIncluded)
            status("Mana symbols included", ok: true)
            note("These downloads supply artwork for decks and games. Rules and the supported card catalogue are already included; artwork is optional.")
            note("Compact saves space. Standard balances clarity and size. High gives the sharpest inspection images. Higher-quality files already stored count toward lower-quality coverage.")
            note("Full catalogue covers this build’s supported cards, not every printing. Alternate faces are checked during download. Estimates use currently discovered missing images; more faces or tokens may be found while preparing. Actual download and storage vary. Check for missing artwork after app updates.")
            note("Art you chose in Deck Studio is saved as its own image beside the card’s default one, so a card shows the printing you picked even offline. It comes with every download of cards.")
            note("Full and token-only downloads use Scryfall’s bulk image index. Deck and on-demand requests share card names and your IP address. Stored artwork works offline.")
            note("Compact is fastest. Downloads use several direct image transfers at once and remember completed files. iOS controls background timing; force-quitting pauses transfers until you reopen the app. The initial image-list preparation may need the app open on a slow connection.")
            note("Storage is capped at 20 GB, with 1 GB of free space reserved. Unavailable or ambiguous token art remains a labeled placeholder. Use Download missing artwork to retry interruptions.")
        }
        .arenaCard()
        .accessibilityIdentifier("downloads.info")
    }

    // MARK: Pieces

    private func note(_ text: String) -> some View {
        Text(text).font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).fixedSize(horizontal: false, vertical: true)
    }

    private func status(_ text: String, ok: Bool) -> some View {
        Label {
            Text(text).font(ArenaMenuStyle.font(13, .medium))
        } icon: {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? ArenaMenuStyle.gold : ArenaMenuStyle.loss)
        }
    }
}

/// A brass-rimmed groove filling with ember: a download's progress in the tavern.
struct BrassProgressBar: View {
    let fraction: Double
    /// Gold for what is stored (Arena's progress bars), ember for a download under way.
    var gold = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.5))
                Capsule()
                    .fill(LinearGradient(colors: gold ? [Color(red: 1, green: 0.88, blue: 0.56), ArenaMenuStyle.gold]
                                                       : [Color(red: 1, green: 0.62, blue: 0.32), TavernPalette.ember],
                                         startPoint: .top, endPoint: .bottom))
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

/// A section that opens and closes under a gold chevron, in place of the system disclosure group.
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
                    Text(title).font(ArenaMenuStyle.font(15, .bold)).foregroundStyle(ArenaMenuStyle.text)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(ArenaMenuStyle.gold)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 36)
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
