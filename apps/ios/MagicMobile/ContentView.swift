import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @State private var serverURLText = "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud"
    @State private var status = "Not connected"
    @State private var screen: AppScreen = .menu
    @State private var difficulty: AiDifficulty = .normal
    @State private var selectedHumanPrecon = PreconCatalog.all[0]
    @State private var selectedAIPrecon = PreconCatalog.all[1]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var playerAvatarData: Data?
    @State private var deckText = ""
    @State private var deckSource = ""
    @State private var importedDeck: DeckList?
    @State private var snapshot: GameSnapshot?
    @State private var startupStatus: CommanderStartupResponse?
    @State private var selectedCard: ZoneCard?
    @State private var inspectedCard: ZoneCard?
    @State private var pendingActionId: String?
    @State private var pendingCardInstanceId: String?
    @State private var lastSubmittedActionId: String?
    @State private var lastSubmittedSnapshotSignature: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var liveUpdateStatus = "Idle"
    @State private var cardCacheMetadata: CardCacheMetadata?
    @State private var isSyncingCardCache = false
    @State private var phoneImageCacheCount = 0
    @State private var phoneSymbolCacheCount = 0
    @State private var phoneImageDownloadProgress: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.08), Color(red: 0.16, green: 0.25, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if screen == .play {
                ImmersivePlayShell(
                    snapshot: snapshot,
                    startupStatus: startupStatus,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    avatarData: playerAvatarData,
                    pendingActionId: pendingActionId,
                    pendingCardInstanceId: pendingCardInstanceId,
                    liveUpdateStatus: liveUpdateStatus,
                    runAction: { action in Task { await run(action: action) } },
                    runCommand: { command, label, pendingId in Task { await run(command: command, label: label, pendingId: pendingId) } },
                    newGame: { screen = .setup }
                )
            } else {
                VStack(spacing: 10) {
                    HeaderBar(screen: screen, status: status, isLoading: isLoading) {
                        screen = .menu
                    }

                    chromeScreen
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .alert("MagicMobile", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: selectedPhoto?.itemIdentifier) {
            await loadSelectedAvatar()
        }
        .onChange(of: screen) { _, newScreen in
            if newScreen != .play {
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                webSocketTask = nil
                liveUpdateStatus = "Idle"
            }
        }
        .onChange(of: serverURLText) { _, newValue in
            CardImageURL.setBaseURL(newValue)
        }
        .task {
            CardImageURL.setBaseURL(serverURLText)
            await checkBridge()
            await refreshCardCacheMetadata()
            await refreshPhoneAssetCacheCounts()
        }
    }

    @ViewBuilder
    private var chromeScreen: some View {
        switch screen {
        case .menu:
            MenuView(
                startSetup: { screen = .setup },
                openDecks: { screen = .decks },
                quickStart: { Task { await startGame() } },
                cardCacheMetadata: cardCacheMetadata,
                isSyncingCardCache: isSyncingCardCache,
                phoneImageCacheCount: phoneImageCacheCount,
                phoneSymbolCacheCount: phoneSymbolCacheCount,
                phoneImageDownloadProgress: phoneImageDownloadProgress,
                syncCardCache: { Task { await syncCardCache() } }
            )
        case .setup:
            SetupView(
                serverURLText: $serverURLText,
                difficulty: $difficulty,
                selectedHumanPrecon: $selectedHumanPrecon,
                selectedAIPrecon: $selectedAIPrecon,
                selectedPhoto: $selectedPhoto,
                avatarData: playerAvatarData,
                deckSummary: deckSummary,
                cardCacheMetadata: cardCacheMetadata,
                isSyncingCardCache: isSyncingCardCache,
                phoneImageCacheCount: phoneImageCacheCount,
                phoneSymbolCacheCount: phoneSymbolCacheCount,
                phoneImageDownloadProgress: phoneImageDownloadProgress,
                syncCardCache: { Task { await syncCardCache() } },
                checkBridge: { Task { await checkBridge() } },
                openDecks: { screen = .decks },
                startGame: { Task { await startGame() } }
            )
        case .decks:
            DeckBuilderView(
                deckText: $deckText,
                deckSource: $deckSource,
                deckSummary: deckSummary,
                importDeck: importDeck,
                selectedHumanPrecon: $selectedHumanPrecon
            )
        case .play:
            EmptyView()
        }
    }

    private var api: MagicMobileAPI? {
        guard let url = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return MagicMobileAPI(baseURL: url)
    }

    private var webPlayURL: URL {
        URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines) + "/play") ?? URL(string: "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud/play")!
    }

    private var deckSummary: String {
        let deck = importedDeck ?? selectedHumanPrecon.deckList
        return "\(deck.name) - \(deck.totalCards) cards - Commander: \(deck.commander?.cardName ?? "unknown")"
    }

    private func checkBridge() async {
        await perform {
            guard let api else { throw MagicMobileError.invalidServerURL }
            let health = try await api.health()
            status = "\(health.status): \(health.reason)"
        }
    }

    private func refreshCardCacheMetadata() async {
        guard let api else { return }
        cardCacheMetadata = try? await api.cardCacheMetadata()
    }

    private func refreshPhoneAssetCacheCounts() async {
        phoneImageCacheCount = CardImageURL.cachedImageCount()
        phoneSymbolCacheCount = CardImageURL.cachedSymbolCount()
    }

    private func syncCardCache() async {
        guard !isSyncingCardCache else { return }
        guard let api else {
            errorMessage = MagicMobileError.invalidServerURL.localizedDescription
            return
        }

        isSyncingCardCache = true
        phoneImageDownloadProgress = "Preparing index"
        status = "Preparing Scryfall card index"
        do {
            cardCacheMetadata = try await api.syncCardCache()
            async let imageManifestRequest = api.cardImageManifest()
            async let symbolManifestRequest = api.symbolManifest()
            let manifest = try await imageManifestRequest
            let symbolManifest = try await symbolManifestRequest
            cardCacheMetadata = manifest.metadata
            phoneImageDownloadProgress = "images 0/\(manifest.images.count)"
            status = "Downloading card images to iPhone"
            let downloaded = try await CardImageURL.downloadAllImagesToPhone(images: manifest.images) { completed, total in
                await MainActor.run {
                    phoneImageDownloadProgress = "images \(completed)/\(total)"
                    if completed == total || completed % 25 == 0 {
                        status = "Downloading card images \(completed)/\(total)"
                    }
                }
            }
            phoneImageDownloadProgress = "symbols 0/\(symbolManifest.symbols.count)"
            let downloadedSymbols = try await CardImageURL.downloadAllSymbolsToPhone(symbols: symbolManifest.symbols) { completed, total in
                await MainActor.run {
                    phoneImageDownloadProgress = "symbols \(completed)/\(total)"
                    if completed == total || completed % 10 == 0 {
                        status = "Downloading symbols \(completed)/\(total)"
                    }
                }
            }
            await refreshPhoneAssetCacheCounts()
            status = "Assets ready: \(phoneImageCacheCount) cards, \(phoneSymbolCacheCount) symbols cached (\(downloaded) cards, \(downloadedSymbols) symbols new)"
        } catch {
            lastSubmittedActionId = nil
            lastSubmittedSnapshotSignature = nil
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
        phoneImageDownloadProgress = nil
        isSyncingCardCache = false
    }

    private func importDeck() {
        guard let deck = DeckImporter.parse(text: deckText, source: deckSource.isEmpty ? "Imported Commander Deck" : deckSource) else {
            errorMessage = "Paste an Archidekt/Moxfield exported text list or a Commander text list."
            return
        }
        importedDeck = deck
        status = "Imported \(deck.name)"
    }

    private func startGame() async {
        guard let api else {
            errorMessage = MagicMobileError.invalidServerURL.localizedDescription
            status = MagicMobileError.invalidServerURL.localizedDescription
            return
        }

        isLoading = true
        snapshot = nil
        selectedCard = nil
        inspectedCard = nil
        pendingActionId = nil
        pendingCardInstanceId = nil
        lastSubmittedActionId = nil
        lastSubmittedSnapshotSignature = nil
        liveUpdateStatus = "Idle"
        startupStatus = CommanderStartupResponse(
            startupId: "pending",
            status: "starting",
            snapshot: nil,
            message: "Creating XMage table.",
            error: nil
        )
        screen = .play
        status = "Creating XMage table"

        do {
            let humanDeck = importedDeck ?? selectedHumanPrecon.deckList
            let aiDeck = selectedAIPrecon.deckList
            let startup = try await api.startCommanderStartup(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty)
            startupStatus = startup
            status = startup.message ?? "XMage table starting"

            try await pollStartup(api: api, startupId: startup.startupId, deckName: humanDeck.name)
        } catch {
            startupStatus = CommanderStartupResponse(
                startupId: startupStatus?.startupId ?? "failed",
                status: "failed",
                snapshot: nil,
                message: nil,
                error: error.localizedDescription
            )
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }

        isLoading = false
    }

    private func pollStartup(api: MagicMobileAPI, startupId: String, deckName: String) async throws {
        for _ in 0..<90 {
            let current = try await api.commanderStartupStatus(startupId: startupId)
            startupStatus = current

            if current.status == "ready", let nextSnapshot = current.snapshot {
                applySnapshot(nextSnapshot)
                startupStatus = nil
                selectedCard = nil
                inspectedCard = nil
                status = "Commander game started with \(deckName)"
                startWebSocket(gameId: nextSnapshot.id)
                return
            }

            if current.status == "failed" {
                throw MagicMobileError.server(current.error ?? "XMage game start failed.")
            }

            try await Task.sleep(nanoseconds: 650_000_000)
        }

        throw MagicMobileError.server("XMage took too long to create the table. Check the bridge and try again.")
    }

    private func run(action: LegalAction) async {
        guard pendingActionId == nil else { return }
        guard let api else {
            errorMessage = MagicMobileError.invalidServerURL.localizedDescription
            status = MagicMobileError.invalidServerURL.localizedDescription
            return
        }
        guard let currentSnapshot = snapshot else { return }

        let currentSignature = snapshotSignature(currentSnapshot)
        if lastSubmittedActionId == action.id, lastSubmittedSnapshotSignature == currentSignature {
            return
        }

        pendingActionId = action.id
        pendingCardInstanceId = action.cardInstanceId ?? action.sourceInstanceId
        lastSubmittedActionId = action.id
        lastSubmittedSnapshotSignature = currentSignature
        status = "Sending \(action.shortLabel ?? action.label)"

        do {
            let previousSignature = snapshotSignature(currentSnapshot)
            let nextSnapshot = try await api.submit(action: action, gameId: currentSnapshot.id)
            applySnapshot(nextSnapshot)
            status = nextSnapshot.pendingStatus == "waiting_for_xmage" ? "Waiting for XMage update" : "Action submitted"
            if nextSnapshot.pendingStatus == "waiting_for_xmage" {
                lastSubmittedActionId = nil
                lastSubmittedSnapshotSignature = nil
                await pollSnapshotAfterCommand(api: api, gameId: currentSnapshot.id, previousSignature: previousSignature)
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }

        pendingActionId = nil
        pendingCardInstanceId = nil
    }

    private func run(command: GameCommand, label: String, pendingId: String) async {
        guard pendingActionId == nil else { return }
        guard let api else {
            errorMessage = MagicMobileError.invalidServerURL.localizedDescription
            status = MagicMobileError.invalidServerURL.localizedDescription
            return
        }
        guard let currentSnapshot = snapshot else { return }

        let currentSignature = snapshotSignature(currentSnapshot)
        if lastSubmittedActionId == pendingId, lastSubmittedSnapshotSignature == currentSignature {
            return
        }

        pendingActionId = pendingId
        pendingCardInstanceId = command.cardInstanceId ?? command.sourceInstanceId
        lastSubmittedActionId = pendingId
        lastSubmittedSnapshotSignature = currentSignature
        status = "Sending \(label)"

        do {
            let previousSignature = snapshotSignature(currentSnapshot)
            let nextSnapshot = try await api.submit(command: command, gameId: currentSnapshot.id)
            applySnapshot(nextSnapshot)
            status = nextSnapshot.pendingStatus == "waiting_for_xmage" ? "Waiting for XMage update" : "Action submitted"
            if nextSnapshot.pendingStatus == "waiting_for_xmage" {
                lastSubmittedActionId = nil
                lastSubmittedSnapshotSignature = nil
                await pollSnapshotAfterCommand(api: api, gameId: currentSnapshot.id, previousSignature: previousSignature)
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }

        pendingActionId = nil
        pendingCardInstanceId = nil
    }

    private func startWebSocket(gameId: String) {
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        guard let api, let url = webSocketURL(gameId: gameId, baseURL: api.baseURL) else {
            liveUpdateStatus = "Live updates unavailable"
            return
        }

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        liveUpdateStatus = "Connecting"
        status = "Connecting real-time updates"

        Task {
            await listenWebSocket(task: task, gameId: gameId)
        }
    }

    private func listenWebSocket(task: URLSessionWebSocketTask, gameId: String) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        await MainActor.run {
                            do {
                                let nextSnapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
                                self.liveUpdateStatus = "Live"
                                self.status = "Connected (real-time)"
                                self.applySnapshot(nextSnapshot)
                            } catch {
                                self.liveUpdateStatus = "Update decode failed"
                                print("Error decoding snapshot: \(error)")
                            }
                        }
                    }
                case .data(let data):
                    await MainActor.run {
                        do {
                            let nextSnapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
                            self.liveUpdateStatus = "Live"
                            self.status = "Connected (real-time)"
                            self.applySnapshot(nextSnapshot)
                        } catch {
                            self.liveUpdateStatus = "Update decode failed"
                            print("Error decoding snapshot: \(error)")
                        }
                    }
                @unknown default:
                    break
                }
            } catch {
                print("WebSocket receive error: \(error.localizedDescription)")
                await MainActor.run {
                    self.liveUpdateStatus = "Reconnecting"
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.screen == .play && self.webSocketTask === task {
                    await MainActor.run {
                        self.startWebSocket(gameId: gameId)
                    }
                }
                break
            }
        }
    }

    private func webSocketURL(gameId: String, baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var allowedPathSegment = CharacterSet.urlPathAllowed
        allowedPathSegment.remove(charactersIn: "/")
        let encodedGameId = gameId.addingPercentEncoding(withAllowedCharacters: allowedPathSegment) ?? gameId
        components.percentEncodedPath = "/" + ([basePath, "ws", "games", encodedGameId].filter { !$0.isEmpty }.joined(separator: "/"))
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func snapshotSignature(_ snapshot: GameSnapshot) -> String {
        let legalActionIds = snapshot.legalActions?.map(\.id).joined(separator: ",") ?? ""
        let handCounts = snapshot.players.map { "\($0.playerId):\($0.zones.hand.count):\($0.zones.battlefield.count):\($0.zones.graveyard.count)" }.joined(separator: "|")
        return "\(snapshot.id)|\(snapshot.bridgeRevision ?? -1)|\(snapshot.xmageCycle ?? -1)|\(snapshot.turn)|\(snapshot.phase)|\(snapshot.step ?? "")|\(snapshot.priorityPlayerId ?? "")|\(snapshot.promptText ?? "")|\(handCounts)|\(legalActionIds)"
    }

    private func applySnapshot(_ nextSnapshot: GameSnapshot) {
        guard shouldAcceptSnapshot(nextSnapshot) else { return }
        snapshot = nextSnapshot
        selectedCard = nil
    }

    private func shouldAcceptSnapshot(_ nextSnapshot: GameSnapshot) -> Bool {
        guard let current = snapshot, current.id == nextSnapshot.id else { return true }
        let currentRevision = current.bridgeRevision ?? -1
        let nextRevision = nextSnapshot.bridgeRevision ?? -1
        if nextRevision != currentRevision {
            return nextRevision > currentRevision
        }
        return (nextSnapshot.xmageCycle ?? -1) >= (current.xmageCycle ?? -1)
    }

    private func pollSnapshotAfterCommand(api: MagicMobileAPI, gameId: String, previousSignature: String) async {
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let refreshed = try? await api.snapshot(gameId: gameId) else { continue }
            applySnapshot(refreshed)
            if snapshotSignature(refreshed) != previousSignature {
                status = "XMage board updated"
                return
            }
        }
        if let health = try? await api.health() {
            status = "\(health.status): \(health.reason)"
        } else {
            status = "XMage update delayed. Refresh or retry the action."
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
    }

    private func loadSelectedAvatar() async {
        guard let selectedPhoto else { return }
        playerAvatarData = try? await selectedPhoto.loadTransferable(type: Data.self)
    }
}

enum AppScreen: String {
    case menu = "Menu"
    case setup = "Setup"
    case decks = "Decks"
    case play = "Play"
}

struct HeaderBar: View {
    let screen: AppScreen
    let status: String
    let isLoading: Bool
    let menu: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: menu) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MagicMobile")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Text(screen.rawValue.uppercased())
                        .font(.caption.weight(.black))
                        .foregroundStyle(.orange)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.orange)
                }
                Text(status)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
        }
        .foregroundStyle(.white)
    }
}

struct MenuView: View {
    let startSetup: () -> Void
    let openDecks: () -> Void
    let quickStart: () -> Void
    let cardCacheMetadata: CardCacheMetadata?
    let isSyncingCardCache: Bool
    let phoneImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let phoneImageDownloadProgress: String?
    let syncCardCache: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Commander")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("XMage rules, 100-card precons, real Scryfall card art, built for landscape iPhone play.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
                Spacer()
                HStack(spacing: 10) {
                    Button("Game setup", action: startSetup)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Quick battle", action: quickStart)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.black.opacity(0.64), .orange.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.24)))

            VStack(spacing: 12) {
                HeroCard(title: "Deck Builder", description: "Paste Archidekt or Moxfield export text, or pick an included Commander precon.", button: "Build deck", action: openDecks)
                CardCachePanel(
                    metadata: cardCacheMetadata,
                    isSyncing: isSyncingCardCache,
                    phoneImageCacheCount: phoneImageCacheCount,
                    phoneSymbolCacheCount: phoneSymbolCacheCount,
                    downloadProgress: phoneImageDownloadProgress,
                    sync: syncCardCache
                )
            }
            .frame(width: 360)
        }
    }
}

struct CardCachePanel: View {
    let metadata: CardCacheMetadata?
    let isSyncing: Bool
    let phoneImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let downloadProgress: String?
    let sync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.orange)
                Text("Game Assets")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text(metadata?.status.uppercased() ?? "EMPTY")
                    .font(.caption.weight(.black))
                    .foregroundStyle(metadata?.status == "ready" ? .green : .orange)
            }

            Text(cacheSummary)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(3)

            Button {
                sync()
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSyncing ? "Downloading \(downloadProgress ?? "")" : "Download cards + symbols")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isSyncing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }

    private var cacheSummary: String {
        guard let metadata else {
            return "Download the full Scryfall image pack onto this iPhone so gameplay renders cards locally."
        }
        if metadata.status == "ready" {
            return "Phone cache: \(phoneImageCacheCount) cards, \(phoneSymbolCacheCount) symbols. Scryfall index: \(metadata.cardCount) cards, \(metadata.symbolCount ?? 0) symbols."
        }
        return "Phone cache: \(phoneImageCacheCount) cards, \(phoneSymbolCacheCount) symbols. Scryfall index status: \(metadata.status)."
    }
}

struct HeroCard: View {
    let title: String
    let description: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(description)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button(button, action: action)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct SetupView: View {
    @Binding var serverURLText: String
    @Binding var difficulty: AiDifficulty
    @Binding var selectedHumanPrecon: PreconDeck
    @Binding var selectedAIPrecon: PreconDeck
    @Binding var selectedPhoto: PhotosPickerItem?
    let avatarData: Data?
    let deckSummary: String
    let cardCacheMetadata: CardCacheMetadata?
    let isSyncingCardCache: Bool
    let phoneImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let phoneImageDownloadProgress: String?
    let syncCardCache: () -> Void
    let checkBridge: () -> Void
    let openDecks: () -> Void
    let startGame: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 10
            let leftWidth = min(max(proxy.size.width * 0.32, 278), 330)
            let rightWidth = max(proxy.size.width - leftWidth - gap, 430)

            HStack(spacing: gap) {
                Panel(title: "Connection") {
                    TextField("Server URL", text: $serverURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textFieldStyle(GameTextFieldStyle())
                    Text("iPhone client. XMage, Docker, card cache, symbols, and rules bridge run on this server.")
                        .foregroundStyle(.white.opacity(0.68))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(3)
                    Button("Check XMage bridge", action: checkBridge)
                        .buttonStyle(SecondaryButtonStyle())
                    CardCachePanel(
                        metadata: cardCacheMetadata,
                        isSyncing: isSyncingCardCache,
                        phoneImageCacheCount: phoneImageCacheCount,
                        phoneSymbolCacheCount: phoneSymbolCacheCount,
                        downloadProgress: phoneImageDownloadProgress,
                        sync: syncCardCache
                    )
                }
                .frame(width: leftWidth)

                Panel(title: "Commander vs AI") {
                    HStack(alignment: .top, spacing: 10) {
                        PreconPicker(title: "Your precon", selection: $selectedHumanPrecon)
                        PreconPicker(title: "AI deck", selection: $selectedAIPrecon)
                    }

                    Text(deckSummary)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AI skill")
                                .font(.caption.weight(.black))
                                .foregroundStyle(MagicPalette.antiqueGold)
                            Picker("AI skill", selection: $difficulty) {
                                ForEach(AiDifficulty.allCases) { difficulty in
                                    Text(difficulty.menuLabel).tag(difficulty)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            AvatarPreview(data: avatarData)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 7) {
                        SetupRuleChip(title: "Format", value: "Commander")
                        SetupRuleChip(title: "Players", value: "1v1 AI")
                        SetupRuleChip(title: "Life", value: "40")
                        SetupRuleChip(title: "Mulligan", value: "XMage")
                        SetupRuleChip(title: "Start", value: "Prompt")
                    }

                    Text("XMage controls rules, mulligans, priority, mana, and legal actions.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)

                    HStack {
                        Button("Deck upload", action: openDecks)
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Start vs AI", action: startGame)
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .frame(width: rightWidth)
            }
        }
    }
}

struct SetupRuleChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.10)))
    }
}

struct DeckBuilderView: View {
    @Binding var deckText: String
    @Binding var deckSource: String
    let deckSummary: String
    let importDeck: () -> Void
    @Binding var selectedHumanPrecon: PreconDeck

    var body: some View {
        HStack(spacing: 12) {
            Panel(title: "Deck Upload") {
                TextField("Deck name, Archidekt URL, or Moxfield URL", text: $deckSource)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(GameTextFieldStyle())
                TextEditor(text: $deckText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
                HStack {
                    Link("Archidekt", destination: URL(string: "https://archidekt.com/")!)
                        .buttonStyle(SecondaryButtonStyle())
                    Link("Moxfield", destination: URL(string: "https://www.moxfield.com/")!)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Import text", action: importDeck)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }

            Panel(title: "Current Deck") {
                Text(deckSummary)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Text("Use exported plain text from Archidekt or Moxfield. Direct scraping is intentionally avoided.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                PreconPicker(title: "Fallback precon", selection: $selectedHumanPrecon)
                Spacer()
            }
            .frame(width: 330)
        }
    }
}

struct PreconPicker: View {
    let title: String
    @Binding var selection: PreconDeck

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Picker(title, selection: $selection) {
                ForEach(PreconCatalog.all) { precon in
                    Text("\(precon.name) (\(precon.colors))").tag(precon)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.65)

            Text(selection.subtitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            Text(selection.commander)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct AvatarPreview: View {
    let data: Data?

    var body: some View {
        HStack(spacing: 10) {
            PlayerAvatar(data: data, size: 46, active: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Player icon")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                Text("Choose photo")
                    .font(.callout.weight(.black))
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct ImmersivePlayShell: View {
    let snapshot: GameSnapshot?
    let startupStatus: CommanderStartupResponse?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let liveUpdateStatus: String
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let newGame: () -> Void

    var body: some View {
        NativeGameView(
            snapshot: snapshot,
            startupStatus: startupStatus,
            selectedCard: $selectedCard,
            inspectedCard: $inspectedCard,
            avatarData: avatarData,
            pendingActionId: pendingActionId,
            pendingCardInstanceId: pendingCardInstanceId,
            liveUpdateStatus: liveUpdateStatus,
            runAction: runAction,
            runCommand: runCommand,
            newGame: newGame
        )
    }
}

struct NativeGameView: View {
    let snapshot: GameSnapshot?
    let startupStatus: CommanderStartupResponse?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let liveUpdateStatus: String
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let newGame: () -> Void
    @State private var isLogOpen = false
    @State private var isOverPlayerDropZone = false

    @ViewBuilder
    var body: some View {
        if let snapshot, let human = snapshot.human, let opponent = snapshot.opponent {
            GeometryReader { proxy in
                let metrics = BattlefieldLayoutMetrics(proxy: proxy)
                let selectedCardActions = selectedActions(in: snapshot)
                let allActions = snapshot.legalActions ?? []

                ZStack {
                    BattlefieldSurface()
                        .ignoresSafeArea()

                    BattlefieldRow(title: "Opponent board", cards: nonLandPermanents(opponent.zones.battlefield), legalActions: snapshot.legalActions ?? [], selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.permanentCardWidth, rowWidth: metrics.playWidth, runAction: runAction)
                        .frame(width: metrics.playWidth, height: metrics.compactRowHeight)
                        .position(x: metrics.playCenterX, y: metrics.opponentBoardY)

                    BattlefieldRow(title: "Opponent lands", cards: landPermanents(opponent.zones.battlefield), legalActions: snapshot.legalActions ?? [], selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.landCardWidth, rowWidth: metrics.playWidth, runAction: runAction)
                        .frame(width: metrics.playWidth, height: metrics.landRowHeight)
                        .position(x: metrics.playCenterX, y: metrics.opponentLandsY)

                    Rectangle()
                        .fill(.white.opacity(0.13))
                        .frame(width: max(metrics.playWidth - 28, 80), height: 1.5)
                        .position(x: metrics.playCenterX, y: metrics.centerLineY)

                    BattlefieldRow(title: "Your board", cards: nonLandPermanents(human.zones.battlefield), legalActions: snapshot.legalActions ?? [], selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.permanentCardWidth, rowWidth: metrics.playWidth, runAction: runAction)
                        .frame(width: metrics.playWidth, height: metrics.compactRowHeight)
                        .position(x: metrics.playCenterX, y: metrics.playerBoardY)

                    BattlefieldRow(title: "Your lands", cards: landPermanents(human.zones.battlefield), legalActions: snapshot.legalActions ?? [], selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.landCardWidth, rowWidth: metrics.playWidth, runAction: runAction)
                        .frame(width: metrics.playWidth, height: metrics.landRowHeight)
                        .position(x: metrics.playCenterX, y: metrics.playerLandsY)

                    if let xmageStack = snapshot.xmage?.stack, !xmageStack.isEmpty {
                        XmageStackPeek(objects: xmageStack, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                            .frame(width: min(metrics.playWidth * 0.40, 320), height: 92)
                            .position(x: metrics.stackX, y: metrics.stackY)
                    } else if !human.zones.stack.isEmpty {
                        StackPeek(cards: human.zones.stack, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                            .frame(width: min(metrics.playWidth * 0.36, 280), height: 74)
                            .position(x: metrics.stackX, y: metrics.stackY)
                    }

                    PromptPill(snapshot: snapshot)
                        .frame(width: min(metrics.playWidth * 0.82, 560))
                        .position(x: metrics.playCenterX, y: metrics.promptY)

                    if isOverPlayerDropZone {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(MagicPalette.antiqueGold.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MagicPalette.antiqueGold.opacity(0.72), lineWidth: 2))
                            .frame(width: metrics.playerDropZone.width, height: metrics.playerDropZone.height)
                            .position(x: metrics.playerDropZone.midX, y: metrics.playerDropZone.midY)
                            .allowsHitTesting(false)
                    }

                    HandFan(
                        cards: human.zones.hand,
                        legalActions: snapshot.legalActions ?? [],
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        pendingCardInstanceId: pendingCardInstanceId,
                        metrics: metrics,
                        isOverPlayerDropZone: $isOverPlayerDropZone,
                        runAction: runAction
                    )
                        .frame(width: metrics.playWidth, height: metrics.handFrameHeight)
                        .position(x: metrics.playCenterX, y: metrics.handY)

                    TurnStatusBadge(snapshot: snapshot, human: human, opponent: opponent)
                        .frame(width: metrics.turnBadgeWidth, height: 34)
                        .position(x: metrics.playCenterX, y: metrics.topHUDY)

                    LiveUpdateBadge(status: liveUpdateStatus)
                        .frame(width: min(metrics.turnBadgeWidth * 0.46, 170), height: 28)
                        .position(x: metrics.liveStatusX, y: metrics.topHUDY + 40)

                    PlayerHeroHUD(name: "Noaddrag", player: opponent, avatarData: nil, active: snapshot.activePlayerId == opponent.playerId, opponentId: human.playerId, compact: true, tiny: true)
                        .frame(width: metrics.opponentHUDWidth, height: 38)
                        .position(x: metrics.opponentHUDX, y: metrics.topHUDY)

                    PlayerHeroHUD(name: "TabletopPolish", player: human, avatarData: avatarData, active: snapshot.activePlayerId == human.playerId, opponentId: opponent.playerId, compact: true)
                        .frame(width: metrics.hudWidth, height: 48)
                        .position(x: metrics.playerHUDX, y: metrics.bottomHUDY)

                    ManaPoolHUD(manaPool: human.manaPool)
                        .position(x: metrics.manaHUDX, y: metrics.manaHUDY)

                    VStack(spacing: 8) {
                        CompactPhaseRail(snapshot: snapshot)
                        Button {
                            isLogOpen.toggle()
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .buttonStyle(IconButtonStyle())

                        Button(action: newGame) {
                            Image(systemName: "gearshape.fill")
                        }
                        .buttonStyle(IconButtonStyle())
                    }
                    .frame(width: metrics.railWidth)
                    .position(x: metrics.railCenterX, y: metrics.railY)

                    if !allActions.isEmpty || snapshot.choicePrompt != nil || snapshot.promptEnvelope != nil || snapshot.promptEnvelopeV2 != nil {
                        UniversalPromptActionPanel(
                            snapshot: snapshot,
                            selectedCardActions: selectedCardActions,
                            selectedCard: $selectedCard,
                            inspectedCard: $inspectedCard,
                            pendingActionId: pendingActionId,
                            runAction: runAction,
                            runCommand: runCommand
                        )
                            .frame(width: metrics.actionDockWidth)
                            .frame(maxHeight: metrics.actionPanelHeight)
                            .position(x: metrics.actionDockX, y: metrics.actionY)
                    }

                    if let inspectedCard {
                        CardInspector(card: inspectedCard)
                            .frame(width: min(metrics.playWidth * 0.36, 250), height: min(metrics.size.height * 0.43, 220))
                            .position(x: metrics.inspectorX, y: metrics.inspectorY)
                    }

                    if isLogOpen {
                        GameLogDrawer(log: snapshot.log) {
                            isLogOpen = false
                        }
                        .frame(width: min(metrics.playWidth * 0.42, 320), height: min(metrics.size.height * 0.55, 260))
                        .position(x: metrics.logX, y: metrics.logY)
                    }
                }
            }
        } else {
            LoadingGameView(startupStatus: startupStatus)
        }
    }

    private func selectedActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard let selectedCard else { return [] }
        return snapshot.legalActions?.filter { $0.cardInstanceId == selectedCard.instanceId || $0.sourceInstanceId == selectedCard.instanceId } ?? []
    }

    private func landPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { $0.card.isLand }
    }

    private func nonLandPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { !$0.card.isLand }
    }
}

struct BattlefieldLayoutMetrics {
    let size: CGSize
    let safeArea: EdgeInsets

    init(proxy: GeometryProxy) {
        size = proxy.size
        safeArea = proxy.safeAreaInsets
    }

    var railWidth: CGFloat {
        min(max(size.width * 0.075, 64), 92)
    }

    var leftInset: CGFloat {
        max(safeArea.leading + 54, 64)
    }

    var railLeftX: CGFloat {
        size.width - safeArea.trailing - 8 - railWidth
    }

    var actionDockWidth: CGFloat {
        min(max(size.width * 0.16, 220), 292)
    }

    var actionPanelHeight: CGFloat {
        min(max(size.height * 0.54, 250), 390)
    }

    var actionDockRightX: CGFloat {
        railLeftX - 12
    }

    var playRightX: CGFloat {
        actionDockRightX - actionDockWidth - 16
    }

    var playWidth: CGFloat {
        max(playRightX - leftInset, 280)
    }

    var playCenterX: CGFloat {
        leftInset + playWidth / 2
    }

    var railCenterX: CGFloat {
        railLeftX + railWidth / 2
    }

    var railY: CGFloat {
        max(safeArea.top + 112, 112)
    }

    var hudWidth: CGFloat {
        min(playWidth * 0.36, 230)
    }

    var opponentHUDWidth: CGFloat {
        min(playWidth * 0.23, 154)
    }

    var turnBadgeWidth: CGFloat {
        min(playWidth * 0.40, 310)
    }

    var liveStatusX: CGFloat {
        min(playCenterX + turnBadgeWidth * 0.42, actionDockX - actionDockWidth / 2 - 82)
    }

    var opponentHUDX: CGFloat {
        leftInset + opponentHUDWidth / 2
    }

    var playerHUDX: CGFloat {
        leftInset + hudWidth / 2
    }

    var manaHUDX: CGFloat {
        leftInset + 102
    }

    var manaHUDY: CGFloat {
        playerLandsY - landRowHeight / 2 - 18
    }

    var topHUDY: CGFloat {
        max(safeArea.top + 24, 24)
    }

    var bottomHUDY: CGFloat {
        min(handVisualTopY - 30, size.height - max(safeArea.bottom + handFrameHeight + 18, handFrameHeight + 20))
    }

    var battlefieldTopY: CGFloat {
        max(safeArea.top + 58, topHUDY + 42)
    }

    var battlefieldBottomY: CGFloat {
        handVisualTopY - 14
    }

    var battlefieldAvailableHeight: CGFloat {
        max(battlefieldBottomY - battlefieldTopY, 180)
    }

    var rowsTopY: CGFloat {
        battlefieldTopY + max((battlefieldAvailableHeight - battlefieldRowsHeight) / 2, 0)
    }

    var laneGap: CGFloat {
        5
    }

    var centerGap: CGFloat {
        12
    }

    var opponentBoardY: CGFloat {
        rowsTopY + compactRowHeight / 2
    }

    var opponentLandsY: CGFloat {
        opponentBoardY + compactRowHeight / 2 + laneGap + landRowHeight / 2
    }

    var centerLineY: CGFloat {
        opponentLandsY + landRowHeight / 2 + centerGap / 2
    }

    var playerBoardY: CGFloat {
        centerLineY + centerGap / 2 + compactRowHeight / 2
    }

    var playerLandsY: CGFloat {
        playerBoardY + compactRowHeight / 2 + laneGap + landRowHeight / 2
    }

    var promptY: CGFloat {
        centerLineY
    }

    var stackX: CGFloat {
        playCenterX + min(playWidth * 0.18, 150)
    }

    var stackY: CGFloat {
        max(opponentLandsY + landRowHeight / 2 + 20, centerLineY - 34)
    }

    var choicePanelX: CGFloat {
        actionDockX - actionDockWidth / 2 - min(playWidth * 0.23, 180)
    }

    var choicePanelY: CGFloat {
        min(actionY - 88, handVisualTopY - 78)
    }

    var promptBadgeX: CGFloat {
        max(leftInset + 140, min(playCenterX + playWidth * 0.25, actionDockX - actionDockWidth / 2 - 150))
    }

    var promptBadgeY: CGFloat {
        max(promptY - 44, battlefieldTopY + 34)
    }

    var handY: CGFloat {
        size.height - max(safeArea.bottom + handFrameHeight / 2 + 2, handFrameHeight / 2 + 4)
    }

    var handVisualTopY: CGFloat {
        handY - handFrameHeight / 2 - 38
    }

    var actionY: CGFloat {
        size.height - max(safeArea.bottom + 92, 96)
    }

    var actionDockX: CGFloat {
        actionDockRightX - actionDockWidth / 2
    }

    var playerDropZone: CGRect {
        CGRect(
            x: leftInset,
            y: playerBoardY - compactRowHeight / 2 - 10,
            width: playWidth,
            height: compactRowHeight + landRowHeight + laneGap + 24
        )
    }

    var inspectorX: CGFloat {
        leftInset + min(playWidth * 0.18, 158)
    }

    var inspectorY: CGFloat {
        min(handVisualTopY - 96, size.height * 0.56)
    }

    var logX: CGFloat {
        railCenterX - railWidth / 2 - min(playWidth * 0.21, 160) - 10
    }

    var logY: CGFloat {
        min(size.height * 0.44, 210)
    }

    var handCardWidth: CGFloat {
        min(max(playWidth / 10.8, 50), 74)
    }

    var handCardHeight: CGFloat {
        handCardWidth * 1.40
    }

    var handFrameHeight: CGFloat {
        handCardHeight + 38
    }

    var permanentCardWidth: CGFloat {
        basePermanentCardWidth * battlefieldScale
    }

    var landCardWidth: CGFloat {
        baseLandCardWidth * battlefieldScale
    }

    var landRowHeight: CGFloat {
        landCardWidth * 1.40 + rowPadding
    }

    var compactRowHeight: CGFloat {
        permanentCardWidth * 1.40 + rowPadding
    }

    var rowHeight: CGFloat {
        permanentCardWidth * 1.40 + rowPadding
    }

    var battlefieldRowsHeight: CGFloat {
        compactRowHeight * 2 + landRowHeight * 2 + laneGap * 3 + centerGap
    }

    private var basePermanentCardWidth: CGFloat {
        min(max(playWidth / 15.5, 40), 58)
    }

    private var baseLandCardWidth: CGFloat {
        min(max(playWidth / 19.5, 32), 48)
    }

    private var naturalPermanentRowHeight: CGFloat {
        basePermanentCardWidth * 1.40 + rowPadding
    }

    private var naturalLandRowHeight: CGFloat {
        baseLandCardWidth * 1.40 + rowPadding
    }

    private var naturalRowsHeight: CGFloat {
        naturalPermanentRowHeight * 2 + naturalLandRowHeight * 2 + laneGap * 3 + centerGap
    }

    private var rowPadding: CGFloat {
        12
    }

    private var battlefieldScale: CGFloat {
        let fixedHeight = rowPadding * 4 + laneGap * 3 + centerGap
        let scalableHeight = basePermanentCardWidth * 1.40 * 2 + baseLandCardWidth * 1.40 * 2
        return min(1, max(0.42, (battlefieldAvailableHeight - fixedHeight) / max(scalableHeight, 1)))
    }
}

typealias BattlefieldBoardLayout = BattlefieldLayoutMetrics

struct BattlefieldLane {
    let name: String
    let frame: CGRect
}

struct LoadingGameView: View {
    let startupStatus: CommanderStartupResponse?

    var body: some View {
        ZStack {
            BattlefieldSurface()

            VStack(spacing: 12) {
                if startupStatus?.status == "failed" {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title.weight(.black))
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .tint(.orange)
                }

                Text(startupStatus?.status == "failed" ? "XMage start failed" : "Creating XMage table")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)

                Text(startupStatus?.error ?? startupStatus?.message ?? "The battlefield is ready while the rules engine finishes seating players.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MagicPalette {
    static let antiqueGold = Color(red: 0.78, green: 0.58, blue: 0.24)
    static let moss = Color(red: 0.18, green: 0.27, blue: 0.15)
    static let deepMoss = Color(red: 0.06, green: 0.14, blue: 0.08)
    static let iron = Color(red: 0.10, green: 0.09, blue: 0.08)
    static let parchment = Color(red: 0.82, green: 0.73, blue: 0.55)
    static let oxblood = Color(red: 0.38, green: 0.08, blue: 0.06)
    static let leather = Color(red: 0.25, green: 0.14, blue: 0.07)
}

struct BattlefieldSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MagicPalette.deepMoss,
                    MagicPalette.moss,
                    MagicPalette.leather
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [MagicPalette.antiqueGold.opacity(0.24), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 420)
            RadialGradient(colors: [MagicPalette.oxblood.opacity(0.18), .clear], center: .topLeading, startRadius: 20, endRadius: 390)
            VStack {
                Spacer()
                Capsule()
                    .fill(MagicPalette.iron.opacity(0.34))
                    .frame(height: 54)
                    .padding(.horizontal, 42)
                    .blur(radius: 18)
                Spacer()
            }
        }
    }
}

struct PlayerStrip: View {
    let name: String
    let player: PlayerGameState
    let avatarData: Data?
    var active = false

    var body: some View {
        HStack(spacing: 8) {
            PlayerAvatar(data: avatarData, size: 40, active: active)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(player.life)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.75), in: Circle())
                        .offset(x: 5, y: 5)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(player.zones.command.first?.card.name ?? "Commander hidden")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            ZoneCounter(label: "Lib", value: player.zones.library.count)
            ZoneCounter(label: "Hand", value: player.zones.hand.count)
            ZoneCounter(label: "Grave", value: player.zones.graveyard.count)
            ZoneCounter(label: "Exile", value: player.zones.exile.count)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.28), in: Capsule())
    }
}

struct PlayerHeroHUD: View {
    let name: String
    let player: PlayerGameState
    let avatarData: Data?
    var active = false
    var opponentId: String?
    var compact = false
    var tiny = false

    var body: some View {
        HStack(spacing: tiny ? 4 : (compact ? 6 : 8)) {
            PlayerAvatar(data: avatarData, size: tiny ? 30 : (compact ? 36 : 42), active: active)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(player.life)")
                        .font(.system(size: tiny ? 9 : (compact ? 11 : 12), weight: .black))
                        .foregroundStyle(.white)
                        .padding(tiny ? 3 : 4)
                        .background(.black.opacity(0.78), in: Circle())
                        .offset(x: tiny ? 4 : 5, y: tiny ? 4 : 5)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: tiny ? 10 : (compact ? 14 : 16), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(player.zones.command.first?.card.name ?? "Commander")
                    .font(.system(size: tiny ? 7 : (compact ? 9 : 10), weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 2)
            if !tiny {
                CommanderBadge(tax: player.commanderTax, damage: opponentId.flatMap { player.commanderDamage?[$0] } ?? 0)
            }
            ZoneCounter(label: "Lib", value: player.zones.library.count, compact: compact || tiny, tiny: tiny)
            ZoneCounter(label: "Hand", value: player.zones.hand.count, compact: compact || tiny, tiny: tiny)
            if !tiny {
                ZoneCounter(label: "Grave", value: player.zones.graveyard.count, compact: compact)
                ZoneCounter(label: "Exile", value: player.zones.exile.count, compact: compact)
            }
        }
        .padding(.horizontal, tiny ? 6 : (compact ? 8 : 10))
        .padding(.vertical, tiny ? 3 : (compact ? 4 : 5))
        .background(.black.opacity(active ? 0.58 : 0.34), in: Capsule())
        .overlay(Capsule().stroke(active ? MagicPalette.antiqueGold.opacity(0.9) : MagicPalette.parchment.opacity(0.14), lineWidth: active ? 2 : 1))
        .shadow(color: active ? MagicPalette.antiqueGold.opacity(0.34) : .black.opacity(0.22), radius: active ? 14 : 12, y: 5)
    }
}

struct CommanderBadge: View {
    let tax: Int
    let damage: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("+\(tax)")
                .font(.system(size: 9, weight: .black))
            Text("CMD \(damage)")
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(MagicPalette.antiqueGold)
        .frame(width: 38, height: 28)
        .background(MagicPalette.iron.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(MagicPalette.antiqueGold.opacity(0.28)))
    }
}

struct TurnStatusBadge: View {
    let snapshot: GameSnapshot
    let human: PlayerGameState
    let opponent: PlayerGameState

    private var isHumanTurn: Bool {
        snapshot.activePlayerId == human.playerId || snapshot.activePlayerId == "human"
    }

    private var activeName: String {
        isHumanTurn ? "Your Turn" : "Opponent Turn"
    }

    private var detail: String {
        if snapshot.priorityPlayerId == human.playerId || snapshot.waitingOnPlayerId == human.playerId {
            return "Your priority"
        }
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" {
            return "Your priority"
        }
        if snapshot.priorityPlayerId == opponent.playerId || snapshot.waitingOnPlayerId == opponent.playerId || snapshot.priorityPlayerId?.hasPrefix("ai") == true {
            return "AI thinking"
        }
        return (snapshot.step ?? snapshot.phase).phaseTitle
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isHumanTurn ? MagicPalette.antiqueGold : MagicPalette.oxblood)
                .frame(width: 9, height: 9)
                .shadow(color: (isHumanTurn ? MagicPalette.antiqueGold : MagicPalette.oxblood).opacity(0.8), radius: 7)
            Text(activeName.uppercased())
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(isHumanTurn ? MagicPalette.antiqueGold : MagicPalette.parchment)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.54), in: Capsule())
        .overlay(Capsule().stroke((isHumanTurn ? MagicPalette.antiqueGold : MagicPalette.oxblood).opacity(0.55), lineWidth: 1))
    }
}

struct LiveUpdateBadge: View {
    let status: String

    private var isLive: Bool {
        status.lowercased().contains("live")
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isLive ? Color.green : MagicPalette.antiqueGold)
                .frame(width: 7, height: 7)
                .shadow(color: (isLive ? Color.green : MagicPalette.antiqueGold).opacity(0.75), radius: 5)
            Text(status.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke((isLive ? Color.green : MagicPalette.antiqueGold).opacity(0.36), lineWidth: 1))
    }
}

struct PlayerAvatar: View {
    let data: Data?
    let size: CGFloat
    var active = false

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("N")
                    .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.10))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(active ? MagicPalette.antiqueGold : MagicPalette.parchment.opacity(0.52), lineWidth: active ? 3 : 2))
        .shadow(color: active ? MagicPalette.antiqueGold.opacity(0.35) : .clear, radius: 10)
    }
}

struct ZoneCounter: View {
    let label: String
    let value: Int
    var compact = false
    var tiny = false

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: tiny ? 8 : (compact ? 10 : 12), weight: .black))
            Text(label)
                .font(.system(size: tiny ? 6 : (compact ? 7 : 8), weight: .black))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .frame(width: tiny ? 24 : (compact ? 30 : 36), height: tiny ? 22 : (compact ? 26 : 30))
        .background(.white.opacity(tiny ? 0.06 : 0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct ManaPoolHUD: View {
    let manaPool: ManaPool?

    private var values: [(String, Int)] {
        [
            ("W", manaPool?.W ?? 0),
            ("U", manaPool?.U ?? 0),
            ("B", manaPool?.B ?? 0),
            ("R", manaPool?.R ?? 0),
            ("G", manaPool?.G ?? 0),
            ("C", manaPool?.C ?? 0)
        ]
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(values, id: \.0) { symbol, count in
                HStack(spacing: 2) {
                    ManaSymbolView(symbol: symbol, size: 18)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(minWidth: 8)
                }
                .opacity(count > 0 ? 1 : 0.45)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(MagicPalette.iron.opacity(0.68), in: Capsule())
        .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.30), lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
    }
}

struct ManaSymbolView: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        if let url = CardImageURL.symbol("{\(symbol)}"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(symbol)
                .font(.system(size: size * 0.58, weight: .black))
                .foregroundStyle(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundColor, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 1))
        }
    }

    private var backgroundColor: Color {
        switch symbol {
        case "W": return Color(red: 0.92, green: 0.86, blue: 0.66)
        case "U": return Color(red: 0.32, green: 0.55, blue: 0.78)
        case "B": return Color(red: 0.18, green: 0.16, blue: 0.15)
        case "R": return Color(red: 0.78, green: 0.25, blue: 0.16)
        case "G": return Color(red: 0.25, green: 0.52, blue: 0.25)
        default: return Color(red: 0.60, green: 0.57, blue: 0.50)
        }
    }

    private var foregroundColor: Color {
        symbol == "B" ? .white : .black
    }
}

struct StackPeek: View {
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        HStack(spacing: 8) {
            Text("STACK")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .rotationEffect(.degrees(-90))
                .frame(width: 24)

            HStack(spacing: -14) {
                ForEach(Array(cards.suffix(4).enumerated()), id: \.element.id) { index, card in
                    CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, width: 38, height: 54)
                        .zIndex(Double(index))
                        .onTapGesture {
                            selectedCard = card
                            inspectedCard = nil
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            inspectedCard = card
                        }
                }
            }

            Text(cards.last?.card.name ?? "Resolving")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.24)))
    }
}

struct XmageStackPeek: View {
    let objects: [XmageStackObject]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        HStack(spacing: 8) {
            Text("STACK")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .rotationEffect(.degrees(-90))
                .frame(width: 24)

            HStack(spacing: -12) {
                ForEach(Array(objects.suffix(3).enumerated()), id: \.element.id) { index, object in
                    if let card = object.sourceCard {
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, width: 38, height: 54)
                            .zIndex(Double(index))
                            .onTapGesture {
                                selectedCard = card
                                inspectedCard = nil
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                inspectedCard = card
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(objects.last?.name ?? "Resolving")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let text = objects.last?.rulesText, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
                }
                if let paid = objects.last?.paid {
                    Text(paid ? "Paid" : "Pending payment")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(paid ? MagicPalette.parchment.opacity(0.7) : MagicPalette.antiqueGold)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(MagicPalette.iron.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30)))
    }
}

struct PromptPill: View {
    let snapshot: GameSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Text((snapshot.step ?? snapshot.phase).phaseTitle)
                .font(.caption.weight(.black))
                .foregroundStyle(.orange)
            Text(snapshot.promptText ?? "Waiting for XMage")
                .font(.callout.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text("Turn \(snapshot.turn)")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.48), in: Capsule())
    }
}

struct PromptChoicePanel: View {
    let prompt: ChoicePrompt
    let actions: [LegalAction]
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("XMAGE PROMPT")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text(prompt.message)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.68)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(prompt.choices.prefix(8)) { choice in
                        Button {
                            if let action = action(for: choice) {
                                runAction(action)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if pendingActionId == action(for: choice)?.id {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.62)
                                }
                                Text(choice.label)
                            }
                        }
                        .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                        .disabled(pendingActionId != nil || action(for: choice) == nil)
                    }
                }
            }
        }
        .padding(9)
        .background(MagicPalette.iron.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.32)))
    }

    private func action(for choice: ChoicePromptOption) -> LegalAction? {
        actions.first { action in
            action.targetIds?.contains(choice.id) == true ||
            action.validTargetIds?.contains(choice.id) == true ||
            action.id.hasSuffix(choice.id)
        }
    }
}

struct PromptEnvelopeBadge: View {
    let prompt: PromptEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(prompt.method.replacingOccurrences(of: "GAME_", with: ""))
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Spacer(minLength: 6)
                Text(prompt.responseKind.uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(MagicPalette.iron.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.25)))
        .allowsHitTesting(false)
    }
}

struct PromptEnvelopeV2Badge: View {
    let prompt: PromptEnvelopeV2

    private var detail: String {
        var parts: [String] = []
        if let count = prompt.targets?.count, count > 0 { parts.append("\(count) targets") }
        if let count = prompt.cards?.count, count > 0 { parts.append("\(count) cards") }
        if let count = prompt.abilities?.count, count > 0 { parts.append("\(count) abilities") }
        if let count = prompt.amounts?.count, count > 0 { parts.append("\(count) amounts") }
        return parts.isEmpty ? (prompt.responseCommand?.type ?? prompt.responseKind) : parts.joined(separator: " | ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(prompt.method.replacingOccurrences(of: "GAME_", with: ""))
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Spacer(minLength: 6)
                Text((prompt.responseCommand?.type ?? prompt.responseKind).uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(MagicPalette.parchment.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(MagicPalette.iron.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.28)))
        .allowsHitTesting(false)
    }
}

struct UniversalPromptActionPanel: View {
    let snapshot: GameSnapshot
    let selectedCardActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void

    private var allActions: [LegalAction] {
        (snapshot.legalActions ?? []).sorted { lhs, rhs in
            if lhs.actionPriority != rhs.actionPriority {
                return lhs.actionPriority < rhs.actionPriority
            }
            return lhs.label < rhs.label
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("PROMPT")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Spacer(minLength: 4)
                Text(priorityLabel)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    MobileSurfacesPanel(
                        snapshot: snapshot,
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard
                    )

                    if let prompt = snapshot.promptEnvelopeV2 {
                        promptEnvelopeV2Section(prompt)
                    } else if let prompt = snapshot.promptEnvelope {
                        promptEnvelopeSection(prompt)
                    }

                    if let prompt = snapshot.choicePrompt {
                        choicePromptSection(prompt)
                    }

                    if !selectedCardActions.isEmpty, let selectedCard {
                        actionSection(
                            title: "Selected",
                            detail: selectedCard.card.name,
                            actions: selectedCardActions
                        )
                    }

                    actionSection(title: "All Actions", detail: "\(allActions.count)", actions: allActions)
                }
                .padding(.vertical, 1)
            }
        }
        .padding(9)
        .background(MagicPalette.iron.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30)))
    }

    private var priorityLabel: String {
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" {
            return "YOUR PRIORITY"
        }
        return snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId ?? "WAITING"
    }

    @ViewBuilder
    private func promptEnvelopeV2Section(_ prompt: PromptEnvelopeV2) -> some View {
        PromptPanelSection(title: prompt.method.replacingOccurrences(of: "GAME_", with: ""), detail: prompt.responseCommand?.type ?? prompt.responseKind) {
            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.68)

            if isCommanderReplacement(prompt) {
                HStack(spacing: 6) {
                    promptButton(
                        label: "Command zone",
                        pendingId: "\(prompt.id)-command-zone",
                        command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: true)
                    )
                    promptButton(
                        label: "Original zone",
                        pendingId: "\(prompt.id)-original-zone",
                        command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: false)
                    )
                }
            }

            if let confirmation = prompt.confirmation, isConfirmationPrompt(prompt) {
                confirmationPicker(confirmation: confirmation, prompt: prompt)
            }

            if let choices = prompt.choices, !choices.isEmpty {
                optionGrid(choices.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "resolve_choice", icon: "checkmark.circle")
            }

            if let targets = prompt.targets, !targets.isEmpty {
                optionGrid(targets.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "choose_target", icon: "scope")
            }

            if let players = prompt.players, !players.isEmpty {
                optionGrid(players.map { ($0.playerId, playerPromptLabel($0)) }, prompt: prompt, fallbackType: "choose_player", icon: "person.crop.circle")
            }

            if let cards = prompt.cards, !cards.isEmpty {
                cardPicker(cards: cards, prompt: prompt)
            }

            if let modes = prompt.modes, !modes.isEmpty {
                optionGrid(modes.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "choose_mode", icon: "square.stack.3d.up")
            }

            if let abilities = prompt.abilities, !abilities.isEmpty {
                abilityPicker(abilities: abilities, prompt: prompt)
            }

            if let piles = prompt.piles, !piles.isEmpty {
                pilePicker(piles: piles, prompt: prompt)
            }

            if let amounts = prompt.amounts, !amounts.isEmpty {
                amountPicker(amounts: amounts, prompt: prompt)
            }

            if let orderedItems = prompt.orderedItems, !orderedItems.isEmpty {
                placeholderSubmit(
                    title: "Order",
                    button: "Submit shown order",
                    prompt: prompt,
                    type: "order_items",
                    ids: orderedItems.map(\.id)
                )
            }

            if let manaChoices = prompt.manaChoices, !manaChoices.isEmpty {
                manaChoicePicker(choices: manaChoices, prompt: prompt)
            }

            if prompt.manaChoices?.isEmpty != false && isManaPrompt(prompt) {
                manaPicker(prompt: prompt)
            }

            if isTriggerOrderPrompt(prompt) {
                placeholderSubmit(
                    title: "Trigger order",
                    button: "Submit shown order",
                    prompt: prompt,
                    type: "order_triggers",
                    ids: prompt.cards?.map(\.id) ?? prompt.targets?.map(\.id) ?? prompt.choices?.map(\.id) ?? []
                )
            }

            if isSearchPrompt(prompt), prompt.cards?.isEmpty != false, prompt.targets?.isEmpty != false {
                placeholderSubmit(
                    title: "Search/select",
                    button: "Submit exposed selection",
                    prompt: prompt,
                    type: "search_select",
                    ids: prompt.targetIds ?? []
                )
            }
        }
    }

    @ViewBuilder
    private func promptEnvelopeSection(_ prompt: PromptEnvelope) -> some View {
        PromptPanelSection(title: prompt.method.replacingOccurrences(of: "GAME_", with: ""), detail: prompt.responseKind) {
            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.68)

            if let choices = prompt.choices, !choices.isEmpty {
                legacyOptionGrid(choices.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "resolve_choice")
            }

            if let targetIds = prompt.targetIds, !targetIds.isEmpty {
                legacyOptionGrid(targetIds.map { ($0, $0) }, prompt: prompt, fallbackType: "choose_target")
            }
        }
    }

    @ViewBuilder
    private func choicePromptSection(_ prompt: ChoicePrompt) -> some View {
        PromptPanelSection(title: "Choice", detail: "\(prompt.minChoices)-\(prompt.maxChoices)") {
            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.68)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(prompt.choices) { choice in
                    let action = action(for: choice, promptId: prompt.id)
                    Button {
                        if let action {
                            runAction(action)
                        } else if let command = command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) {
                            runCommand(command, choice.label, "\(prompt.id)-\(choice.id)")
                        }
                    } label: {
                        PromptButtonLabel(
                            title: choice.label,
                            systemImage: yesNoIcon(choice.label),
                            isPending: pendingActionId == action?.id || pendingActionId == "\(prompt.id)-\(choice.id)"
                        )
                    }
                    .buttonStyle(PanelActionButtonStyle(isPrimary: action?.isPrimary == true))
                    .disabled(pendingActionId != nil || (action == nil && command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) == nil))
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(title: String, detail: String, actions: [LegalAction]) -> some View {
        PromptPanelSection(title: title, detail: detail) {
            if actions.isEmpty {
                Text("No exposed actions")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 6)], spacing: 6) {
                    ForEach(actions) { action in
                        let directlyRunnable = isDirectlyRunnable(action)
                        Button {
                            if directlyRunnable {
                                runAction(action)
                            }
                        } label: {
                            PromptButtonLabel(
                                title: action.displayLabel,
                                subtitle: directlyRunnable ? action.actionDetail : "Use prompt picker",
                                systemImage: action.systemImage,
                                isPending: pendingActionId == action.id
                            )
                        }
                        .buttonStyle(PanelActionButtonStyle(isDanger: action.type == "concede", isPrimary: action.isPrimary == true))
                        .disabled(pendingActionId != nil || !directlyRunnable)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionGrid(_ options: [(String, String)], prompt: PromptEnvelopeV2, fallbackType: String, icon: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(options, id: \.0) { option in
                let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: fallbackType)
                promptButton(
                    label: option.1,
                    systemImage: yesNoIcon(option.1) ?? icon,
                    pendingId: "\(prompt.id)-\(option.0)",
                    command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [option.0])
                )
            }
        }
    }

    @ViewBuilder
    private func legacyOptionGrid(_ options: [(String, String)], prompt: PromptEnvelope, fallbackType: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(options, id: \.0) { option in
                promptButton(
                    label: option.1,
                    systemImage: yesNoIcon(option.1),
                    pendingId: "\(prompt.id)-\(option.0)",
                    command: command(type: fallbackType, promptId: prompt.id, playerId: prompt.playerId, ids: [option.0])
                )
            }
        }
    }

    @ViewBuilder
    private func cardPicker(cards: [ZoneCard], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Cards")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(cards) { card in
                    let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: isSearchPrompt(prompt) ? "search_select" : "choose_card")
                    VStack(spacing: 4) {
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: true, width: 38, height: 53)
                            .onTapGesture {
                                selectedCard = card
                                inspectedCard = nil
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                inspectedCard = card
                            }
                        promptButton(
                            label: "Choose",
                            subtitle: card.card.name,
                            systemImage: "checkmark.circle",
                            pendingId: "\(prompt.id)-\(card.instanceId)",
                            command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [card.instanceId])
                        )
                        .frame(width: 74)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func abilityPicker(abilities: [XmagePromptAbility], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Abilities")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
            ForEach(abilities) { ability in
                promptButton(
                    label: ability.label,
                    subtitle: ability.rulesText,
                    systemImage: "bolt.fill",
                    pendingId: "\(prompt.id)-\(ability.id)",
                    command: command(type: "choose_ability", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [ability.id])
                )
            }
        }
    }

    @ViewBuilder
    private func pilePicker(piles: [XmagePromptPile], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Piles")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
            ForEach(piles) { pile in
                promptButton(
                    label: pile.label,
                    subtitle: "\(pile.cards.count) cards",
                    systemImage: "tray.full",
                    pendingId: "\(prompt.id)-pile-\(pile.id)",
                    command: command(type: "choose_pile", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, pile: Int(pile.id) ?? 1)
                )
            }
        }
    }

    @ViewBuilder
    private func amountPicker(amounts: [Int], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Amount")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
            ForEach(amounts, id: \.self) { amount in
                let type = amountCommandType(preferred: prompt.responseCommand?.type)
                promptButton(
                    label: "\(amount)",
                    systemImage: "number",
                    pendingId: "\(prompt.id)-amount-\(amount)",
                    command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amount: amount, amounts: [amount])
                )
            }
        }
    }

    @ViewBuilder
    private func manaPicker(prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Mana")
        HStack(spacing: 6) {
            ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { mana in
                Button {
                    if let command = command(type: "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, manaType: mana) {
                        runCommand(command, mana, "\(prompt.id)-mana-\(mana)")
                    }
                } label: {
                    ManaSymbolView(symbol: mana, size: 26)
                        .overlay {
                            if pendingActionId == "\(prompt.id)-mana-\(mana)" {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(pendingActionId != nil)
            }
        }
    }

    @ViewBuilder
    private func manaChoicePicker(choices: [XmagePromptManaChoice], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Mana")
        HStack(spacing: 6) {
            ForEach(choices) { choice in
                let symbol = choice.manaType ?? choice.id
                Button {
                    if let command = command(type: prompt.responseCommand?.type ?? "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol) {
                        runCommand(command, choice.label, "\(prompt.id)-mana-choice-\(choice.id)")
                    }
                } label: {
                    VStack(spacing: 2) {
                        ManaSymbolView(symbol: symbol, size: 24)
                        if let amount = choice.amount {
                            Text("x\(amount)")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                    }
                    .overlay {
                        if pendingActionId == "\(prompt.id)-mana-choice-\(choice.id)" {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(pendingActionId != nil)
            }
        }
    }

    @ViewBuilder
    private func confirmationPicker(confirmation: XmagePromptConfirmation, prompt: PromptEnvelopeV2) -> some View {
        HStack(spacing: 6) {
            promptButton(
                label: confirmation.yesLabel ?? "Yes",
                systemImage: "checkmark.circle",
                pendingId: "\(prompt.id)-yes",
                command: command(
                    type: confirmation.yesCommand?.type ?? prompt.responseCommand?.type ?? "answer_yes_no",
                    promptId: confirmation.yesCommand?.promptId ?? prompt.responseCommand?.promptId ?? prompt.id,
                    playerId: prompt.playerId,
                    ids: [(confirmation.yesCommand?.confirmed ?? true) ? "true" : "false"]
                )
            )
            promptButton(
                label: confirmation.noLabel ?? "No",
                systemImage: "xmark.circle",
                pendingId: "\(prompt.id)-no",
                command: command(
                    type: confirmation.noCommand?.type ?? prompt.responseCommand?.type ?? "answer_yes_no",
                    promptId: confirmation.noCommand?.promptId ?? prompt.responseCommand?.promptId ?? prompt.id,
                    playerId: prompt.playerId,
                    ids: [(confirmation.noCommand?.confirmed ?? false) ? "true" : "false"]
                )
            )
        }
    }

    @ViewBuilder
    private func placeholderSubmit(title: String, button: String, prompt: PromptEnvelopeV2, type: String, ids: [String]) -> some View {
        PromptMiniLabel(title)
        promptButton(
            label: button,
            subtitle: ids.isEmpty ? "Waiting for exposed ids" : "\(ids.count) ids",
            systemImage: type == "order_triggers" ? "arrow.up.arrow.down" : "magnifyingglass",
            pendingId: "\(prompt.id)-\(type)",
            command: ids.isEmpty ? nil : command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: ids)
        )
    }

    @ViewBuilder
    private func promptButton(label: String, subtitle: String? = nil, systemImage: String? = nil, pendingId: String, command: GameCommand?) -> some View {
        Button {
            if let command {
                runCommand(command, label, pendingId)
            }
        } label: {
            PromptButtonLabel(title: label, subtitle: subtitle, systemImage: systemImage, isPending: pendingActionId == pendingId)
        }
        .buttonStyle(PanelActionButtonStyle(isPrimary: true))
        .disabled(pendingActionId != nil || command == nil)
    }

    private func action(for choice: ChoicePromptOption, promptId: String) -> LegalAction? {
        allActions.first { action in
            action.id == choice.id ||
            action.id == "\(promptId)-\(choice.id)" ||
            action.targetIds?.contains(choice.id) == true ||
            action.validTargetIds?.contains(choice.id) == true ||
            action.id.hasSuffix(choice.id)
        }
    }

    private func command(
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        amount: Int? = nil,
        amounts: [Int]? = nil,
        pile: Int? = nil,
        useCommandZone: Bool? = nil,
        manaType: String? = nil
    ) -> GameCommand? {
        let type = rawType.lowercased()
        let promptMessageId = resolvedMessageId(for: promptId)
        switch type {
        case "resolve_choice":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, choiceIds: ids)
        case "choose_target":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, targetIds: ids)
        case "choose_card":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, cardInstanceIds: ids)
        case "choose_player":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, playerIds: ids)
        case "choose_mode":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, modeIds: ids)
        case "choose_ability":
            guard let abilityId = ids.first else { return nil }
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, abilityId: abilityId, promptId: promptId, messageId: promptMessageId)
        case "choose_pile":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, pile: pile ?? Int(ids.first ?? "1") ?? 1)
        case "choose_amount", "play_x_mana":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, amount: amount ?? Int(ids.first ?? "0") ?? 0)
        case "choose_multi_amount":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, amounts: amounts ?? ids.compactMap(Int.init))
        case "play_mana":
            guard let manaType else { return nil }
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, manaType: manaType)
        case "choose_mana":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, manaTypes: manaType.map { [$0] } ?? ids)
        case "search_select":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, cardInstanceIds: ids)
        case "order_triggers", "order_items":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, orderedIds: ids)
        case "commander_replacement":
            guard let useCommandZone else { return nil }
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, useCommandZone: useCommandZone)
        case "answer_yes_no":
            return GameCommand(type: type, gameId: snapshot.id, playerId: playerId, promptId: promptId, messageId: promptMessageId, confirmed: ids.first != "false")
        default:
            return nil
        }
    }

    private func resolvedMessageId(for promptId: String) -> Int? {
        guard let prompt = snapshot.promptEnvelopeV2 else { return nil }
        if prompt.id == promptId || prompt.responseCommand?.promptId == promptId {
            return prompt.responseCommand?.messageId ?? prompt.messageId
        }
        return nil
    }

    private func idCommandType(preferred: String?, fallback: String) -> String {
        guard let preferred = preferred?.lowercased() else { return fallback }
        if ["resolve_choice", "choose_target", "choose_card", "choose_player", "choose_mode", "choose_ability", "search_select", "order_triggers", "order_items", "answer_yes_no"].contains(preferred) {
            return preferred
        }
        return fallback
    }

    private func amountCommandType(preferred: String?) -> String {
        guard let preferred = preferred?.lowercased() else { return "choose_amount" }
        return ["choose_amount", "choose_multi_amount", "play_x_mana"].contains(preferred) ? preferred : "choose_amount"
    }

    private func playerPromptLabel(_ player: XmagePromptPlayer) -> String {
        if let life = player.life {
            return "\(player.label) (\(life))"
        }
        return player.label
    }

    private func isManaPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        prompt.responseCommand?.type?.lowercased() == "play_mana" || ["mana", "play_mana"].contains(prompt.responseKind.lowercased())
    }

    private func isConfirmationPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        prompt.responseCommand?.type?.lowercased() == "answer_yes_no" || prompt.responseKind.lowercased() == "confirmation"
    }

    private func isCommanderReplacement(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "commander_replacement" || prompt.message.localizedCaseInsensitiveContains("command zone")
    }

    private func isTriggerOrderPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        (prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()) == "order_triggers"
    }

    private func isSearchPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "search_select" || prompt.method.localizedCaseInsensitiveContains("search")
    }

    private func yesNoIcon(_ label: String) -> String? {
        let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "ok", "accept"].contains(lower) { return "checkmark.circle" }
        if ["no", "cancel", "decline"].contains(lower) { return "xmark.circle" }
        return nil
    }

    private func isDirectlyRunnable(_ action: LegalAction) -> Bool {
        switch action.type {
        case "choose_target":
            return singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_card", "search_select":
            return singleCount(action.cardInstanceIds) || singleCount(action.validCardInstanceIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_player":
            return singleCount(action.playerIds) || singleCount(action.validPlayerIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_mode":
            return singleCount(action.modeIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "resolve_choice":
            return singleCount(action.choiceIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_multi_amount", "order_triggers", "order_items", "declare_attackers", "declare_blockers":
            return false
        default:
            return true
        }
    }

    private func singleCount(_ values: [String]?) -> Bool {
        values?.count == 1
    }
}

struct MobileSurfacesPanel: View {
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        PromptPanelSection(title: "Surfaces", detail: surfaceSummary) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 5)], spacing: 5) {
                SurfaceChip(title: "Stack", value: "\(stackCards.count)")
                SurfaceChip(title: "Command", value: "\(commandCards.count)")
                SurfaceChip(title: "Grave", value: "\(graveyardCards.count)")
                SurfaceChip(title: "Exile", value: "\(exileCards.count)")
                SurfaceChip(title: "Priority", value: priorityOwner)
                SurfaceChip(title: "Actions", value: "\((snapshot.legalActions ?? []).count)")
            }

            if !stackCards.isEmpty {
                MiniZoneRow(title: "Stack", cards: stackCards, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
            }
            if !commandCards.isEmpty {
                MiniZoneRow(title: "Command", cards: commandCards, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
            }
            if !graveyardCards.isEmpty {
                MiniZoneRow(title: "Graveyard", cards: Array(graveyardCards.suffix(8)), selectedCard: $selectedCard, inspectedCard: $inspectedCard)
            }
            if !exileCards.isEmpty {
                MiniZoneRow(title: "Exile", cards: Array(exileCards.suffix(8)), selectedCard: $selectedCard, inspectedCard: $inspectedCard)
            }
        }
    }

    private var surfaceSummary: String {
        if snapshot.xmage?.panels.search == true {
            return "search"
        }
        return priorityOwner
    }

    private var priorityOwner: String {
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" {
            return "You"
        }
        return snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId ?? "-"
    }

    private var stackCards: [ZoneCard] {
        let xmageCards = snapshot.xmage?.stack.compactMap(\.sourceCard) ?? []
        if !xmageCards.isEmpty { return xmageCards }
        return snapshot.players.flatMap(\.zones.stack)
    }

    private var commandCards: [ZoneCard] {
        snapshot.players.flatMap(\.zones.command) + (snapshot.xmage?.players.flatMap(\.command) ?? [])
    }

    private var graveyardCards: [ZoneCard] {
        snapshot.players.flatMap(\.zones.graveyard) + (snapshot.xmage?.players.flatMap(\.zones.graveyard) ?? [])
    }

    private var exileCards: [ZoneCard] {
        snapshot.players.flatMap(\.zones.exile) + (snapshot.xmage?.players.flatMap(\.zones.exile) ?? []) + (snapshot.xmage?.exileZones.flatMap(\.cards) ?? [])
    }
}

struct PromptPanelSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 3)
                Text(detail.uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            content
        }
        .padding(7)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.10)))
    }
}

struct PromptMiniLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(.white.opacity(0.54))
    }
}

struct PromptButtonLabel: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var isPending = false

    var body: some View {
        HStack(spacing: 5) {
            if isPending {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.58)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .black))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct PanelActionButtonStyle: ButtonStyle {
    var isDanger = false
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(isPrimary ? 0.18 : 0.10)))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isDanger {
            return isPressed ? Color.red.opacity(0.58) : Color.red.opacity(0.72)
        }
        if isPrimary {
            return isPressed ? Color.orange.opacity(0.64) : Color.orange.opacity(0.82)
        }
        return isPressed ? Color.white.opacity(0.16) : Color.white.opacity(0.08)
    }
}

struct SurfaceChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title.uppercased())
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct MiniZoneRow: View {
    let title: String
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PromptMiniLabel(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -7) {
                    ForEach(cards) { card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, width: 28, height: 39)
                            .onTapGesture {
                                selectedCard = card
                                inspectedCard = nil
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                inspectedCard = card
                            }
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 7)
            }
        }
    }
}

struct BattlefieldRow: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat
    let rowWidth: CGFloat
    let runAction: (LegalAction) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.orange.opacity(0.78))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: -10) {
                    if cards.isEmpty {
                        Text("No permanents")
                            .font(.caption.weight(.black))
                            .foregroundStyle(MagicPalette.parchment.opacity(0.42))
                            .padding(.horizontal, 12)
                            .frame(minWidth: rowWidth, minHeight: cardWidth * 1.40, alignment: .center)
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        let action = legalAction(for: card)
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: action != nil, width: cardWidth, height: cardWidth * 1.40)
                            .offset(y: card.tapped == true ? 5 : 0)
                            .zIndex(Double(index))
                            .onTapGesture {
                                if let action, action.type == "make_mana" {
                                    runAction(action)
                                } else {
                                    selectedCard = card
                                    inspectedCard = nil
                                }
                        }
                        .onLongPressGesture(minimumDuration: 0.35) { inspectedCard = card }
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: rowWidth, minHeight: cardWidth * 1.40 + 6, alignment: .center)
            }
        }
    }

    private func legalAction(for card: ZoneCard) -> LegalAction? {
        legalActions.first {
            $0.cardInstanceId == card.instanceId || $0.sourceInstanceId == card.instanceId
        }
    }
}

struct HandFan: View {
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let pendingCardInstanceId: String?
    let metrics: BattlefieldLayoutMetrics
    @Binding var isOverPlayerDropZone: Bool
    let runAction: (LegalAction) -> Void
    @State private var draggingCardId: String?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let center = CGFloat(cards.count - 1) / 2
                let distance = CGFloat(index) - center
                let maxSpread = max((metrics.playWidth - metrics.handCardWidth) / CGFloat(max(cards.count - 1, 1)), 0)
                let spread = min(metrics.handCardWidth * 0.56, maxSpread)
                let selected = selectedCard?.id == card.id
                let action = legalHandAction(for: card)
                let isDragging = draggingCardId == card.id

                CardTile(
                    card: card,
                    selected: selected,
                    pending: pendingCardInstanceId == card.instanceId,
                    legal: action != nil,
                    width: metrics.handCardWidth,
                    height: metrics.handCardHeight
                )
                    .scaleEffect(selected ? 1.16 : 1.0)
                    .rotationEffect(.degrees(Double(distance) * 5.2))
                    .offset(
                        x: distance * spread + (isDragging ? dragOffset.width : 0),
                        y: (selected ? -30 : abs(distance) * 4 + 10) + (isDragging ? dragOffset.height : 0)
                    )
                    .zIndex(isDragging || selectedCard?.id == card.id ? 10 : Double(index))
                    .onTapGesture {
                        selectedCard = card
                        inspectedCard = nil
                    }
                    .onLongPressGesture(minimumDuration: 0.35) { inspectedCard = card }
            }
        }
        .frame(width: metrics.playWidth, height: metrics.handFrameHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if let card = draggingCard ?? card(at: value.location.x) {
                        selectedCard = card
                        inspectedCard = nil
                        draggingCardId = card.id
                        dragOffset = value.translation
                        isOverPlayerDropZone = metrics.playerDropZone.contains(globalPoint(for: value.location))
                    }
                }
                .onEnded { value in
                    guard let card = draggingCard ?? selectedCard else { return }
                    selectedCard = card
                    let shouldPlay = metrics.playerDropZone.contains(globalPoint(for: value.location))
                    draggingCardId = nil
                    dragOffset = .zero
                    isOverPlayerDropZone = false
                    guard shouldPlay, let action = legalHandAction(for: card) else { return }
                    runAction(action)
                }
        )
    }

    private func legalHandAction(for card: ZoneCard) -> LegalAction? {
        legalActions.first {
            ($0.cardInstanceId == card.instanceId || $0.sourceInstanceId == card.instanceId) &&
            ["play_land", "cast_spell"].contains($0.type)
        }
    }

    private func card(at x: CGFloat) -> ZoneCard? {
        guard !cards.isEmpty else { return nil }
        guard cards.count > 1 else { return cards.first }
        let center = CGFloat(cards.count - 1) / 2
        let maxSpread = max((metrics.playWidth - metrics.handCardWidth) / CGFloat(max(cards.count - 1, 1)), 0)
        let spread = min(metrics.handCardWidth * 0.56, maxSpread)
        let index = Int(round((x - metrics.playWidth / 2) / max(spread, 1) + center))
        return cards[min(max(index, 0), cards.count - 1)]
    }

    private func globalPoint(for localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: metrics.playCenterX - metrics.playWidth / 2 + localPoint.x,
            y: metrics.handY - metrics.handFrameHeight / 2 + localPoint.y
        )
    }

    private var draggingCard: ZoneCard? {
        guard let draggingCardId else { return nil }
        return cards.first { $0.id == draggingCardId }
    }
}

struct CardTile: View {
    let card: ZoneCard
    let selected: Bool
    var pending = false
    var legal = false
    var width: CGFloat = 82
    var height: CGFloat = 112

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: CardImageURL.normal(card.card.name)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.card.name)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.black)
                            .lineLimit(3)
                        Spacer()
                        Text(card.card.typeLine)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black.opacity(0.75))
                            .lineLimit(2)
                    }
                    .padding(6)
                    .background(Color(red: 0.86, green: 0.78, blue: 0.62))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if card.power != nil || card.toughness != nil {
                Text("\(card.power ?? 0)/\(card.toughness ?? 0)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.92), in: Capsule())
                    .padding(3)
            }

            if card.tapped == true {
                Text("TAP")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(MagicPalette.oxblood.opacity(0.88), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: selected || pending || legal ? 3 : 1))
        .shadow(color: shadowColor, radius: legal || selected || pending ? 10 : 0)
    }

    private var strokeColor: Color {
        if pending {
            return .orange
        }
        if selected {
            return MagicPalette.antiqueGold
        }
        if legal {
            return Color(red: 0.55, green: 0.28, blue: 0.72)
        }
        return .black.opacity(0.55)
    }

    private var shadowColor: Color {
        if pending {
            return .orange.opacity(0.75)
        }
        if selected {
            return MagicPalette.antiqueGold.opacity(0.55)
        }
        if legal {
            return Color(red: 0.55, green: 0.28, blue: 0.72).opacity(0.55)
        }
        return .clear
    }
}

struct CompactPhaseRail: View {
    let snapshot: GameSnapshot

    var body: some View {
        let current = snapshot.step ?? snapshot.phase
        let index = stageLabels.firstIndex(of: current) ?? 0
        let previous = stageLabels[max(index - 1, 0)]
        let next = stageLabels[min(index + 1, stageLabels.count - 1)]

        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
            PhaseChip(label: "Prev", phase: previous, active: false)
            PhaseChip(label: "Now", phase: current, active: true)
            PhaseChip(label: "Next", phase: next, active: false)
            Text(snapshot.priorityPlayerId == "human" ? "YOU" : "AI")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct PhaseChip: View {
    let label: String
    let phase: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(active ? .black.opacity(0.7) : .white.opacity(0.55))
            Text(phase.phaseTitle)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(active ? .black : .white)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Color.orange : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct ContextActionTray: View {
    let actions: [LegalAction]
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ForEach(orderedActions.prefix(4)) { action in
                Button {
                    runAction(action)
                } label: {
                    HStack(spacing: 7) {
                        if pendingActionId == action.id {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.74)
                        }
                        Text(action.shortLabel ?? shortActionLabel(action))
                    }
                }
                .buttonStyle(CompactActionButtonStyle(isDanger: action.type == "concede", isPrimary: action.isPrimary == true || ["keep_hand", "pass_priority"].contains(action.type)))
                .disabled(pendingActionId != nil)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
    }

    private var orderedActions: [LegalAction] {
        actions.sorted { lhs, rhs in
            priority(lhs) < priority(rhs)
        }
    }

    private func priority(_ action: LegalAction) -> Int {
        if action.isPrimary == true { return 0 }
        switch action.type {
        case "keep_hand", "resolve_choice", "play_land", "cast_spell":
            return 1
        case "pass_priority":
            return 2
        case "pass_until_response":
            return 3
        case "pass_until_next_turn":
            return 4
        case "concede":
            return 9
        default:
            return 5
        }
    }

    private func shortActionLabel(_ action: LegalAction) -> String {
        switch action.type {
        case "pass_priority":
            return "Done"
        case "pass_until_response":
            return "Pass"
        case "pass_until_next_turn":
            return "Skip turn"
        case "play_land":
            return "Play"
        case "cast_spell":
            return "Cast"
        default:
            return action.label
        }
    }
}

struct CardInspector: View {
    let card: ZoneCard

    var body: some View {
        HStack(spacing: 9) {
            CardTile(card: card, selected: true, width: 82, height: 114)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.card.name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(card.card.typeLine)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                ScrollView {
                    Text(card.card.oracleText ?? "XMage has not exposed rules text for this card yet.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.35)))
    }
}

struct MiniLog: View {
    let log: [GameLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LOG")
                .font(.caption.weight(.black))
                .foregroundStyle(.orange)
            ForEach(log.suffix(5)) { entry in
                Text(entry.message)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct GameLogDrawer: View {
    let log: [GameLogEntry]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOG")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(small: true))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(log.suffix(16)) { entry in
                        Text(entry.message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)))
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(.orange)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .frame(minHeight: 42)
            .background(configuration.isPressed ? Color.orange.opacity(0.65) : Color.orange, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .frame(minHeight: 42)
            .background(configuration.isPressed ? Color.white.opacity(0.18) : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
    }
}

struct CompactActionButtonStyle: ButtonStyle {
    var isDanger = false
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isPrimary ? 15 : 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, isPrimary ? 15 : 12)
            .padding(.vertical, isPrimary ? 10 : 8)
            .frame(minWidth: isPrimary ? 112 : 94, alignment: .center)
            .background(backgroundColor(isPressed: configuration.isPressed), in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isDanger {
            return isPressed ? Color.red.opacity(0.62) : Color.red.opacity(0.78)
        }
        if isPrimary {
            return isPressed ? Color.orange.opacity(0.68) : Color.orange
        }
        return isPressed ? Color.white.opacity(0.18) : Color.black.opacity(0.52)
    }
}

struct IconButtonStyle: ButtonStyle {
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 16, weight: .black))
            .foregroundStyle(.white)
            .frame(width: small ? 28 : 42, height: small ? 28 : 42)
            .background(configuration.isPressed ? Color.white.opacity(0.18) : Color.black.opacity(0.45), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.16)))
    }
}

struct GameTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

enum CardImageURL {
    private static let baseURLKey = "MagicMobile.cardImageBaseURL"

    static func setBaseURL(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey)
    }

    static func normal(_ name: String) -> URL? {
        if name == "Hidden card" {
            return URL(string: "https://gatherer.wizards.com/Images/CardBack.jpg")
        }
        let localURL = cacheURL(for: name)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        let baseURL = UserDefaults.standard.string(forKey: baseURLKey) ?? "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud"
        var components = URLComponents(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/card-image")
        components?.queryItems = [
            URLQueryItem(name: "version", value: "small"),
            URLQueryItem(name: "name", value: name)
        ]
        return components?.url
    }

    static func cachedImageCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return files.filter { $0.pathExtension.lowercased() == "jpg" }.count
    }

    static func cachedSymbolCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: symbolCacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return files.filter { $0.pathExtension.lowercased() == "png" }.count
    }

    static func symbol(_ symbol: String) -> URL? {
        let localURL = symbolCacheURL(for: symbol)
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }

    static func downloadAllImagesToPhone(
        images: [CardImageManifestEntry],
        progress: @escaping (_ completed: Int, _ total: Int) async -> Void
    ) async throws -> Int {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try excludeFromBackup(cacheDirectory)
        let uniqueImages = uniqueManifestEntries(images)
        let total = uniqueImages.count
        var completed = 0
        var downloaded = 0
        let batchSize = 8

        await progress(completed, total)

        for startIndex in stride(from: 0, to: uniqueImages.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, uniqueImages.count)
            let batch = Array(uniqueImages[startIndex..<endIndex])

            downloaded += await withTaskGroup(of: Bool.self) { group in
                for entry in batch {
                    group.addTask {
                        await downloadImage(entry)
                    }
                }

                var batchDownloaded = 0
                for await didDownload in group where didDownload {
                    batchDownloaded += 1
                }
                return batchDownloaded
            }

            completed += batch.count
            await progress(completed, total)
        }

        return downloaded
    }

    static func downloadAllSymbolsToPhone(
        symbols: [SymbolManifestEntry],
        progress: @escaping (_ completed: Int, _ total: Int) async -> Void
    ) async throws -> Int {
        try FileManager.default.createDirectory(at: symbolCacheDirectory, withIntermediateDirectories: true)
        try excludeFromBackup(symbolCacheDirectory)
        let uniqueSymbols = uniqueSymbolEntries(symbols)
        let total = uniqueSymbols.count
        var completed = 0
        var downloaded = 0
        let batchSize = 12

        await progress(completed, total)

        for startIndex in stride(from: 0, to: uniqueSymbols.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, uniqueSymbols.count)
            let batch = Array(uniqueSymbols[startIndex..<endIndex])

            downloaded += await withTaskGroup(of: Bool.self) { group in
                for entry in batch {
                    group.addTask {
                        await downloadSymbol(entry)
                    }
                }

                var batchDownloaded = 0
                for await didDownload in group where didDownload {
                    batchDownloaded += 1
                }
                return batchDownloaded
            }

            completed += batch.count
            await progress(completed, total)
        }

        return downloaded
    }

    private static func downloadImage(_ entry: CardImageManifestEntry) async -> Bool {
        let destination = cacheURL(for: entry.name)
        if FileManager.default.fileExists(atPath: destination.path) {
            return false
        }
        guard let sourceURL = URL(string: entry.url) else {
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: sourceURL)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                try data.write(to: destination, options: .atomic)
                return true
            }
        } catch {
            print("Card image download failed for \(entry.name): \(error.localizedDescription)")
        }

        return false
    }

    private static func downloadSymbol(_ entry: SymbolManifestEntry) async -> Bool {
        let destination = symbolCacheURL(for: entry.symbol)
        if FileManager.default.fileExists(atPath: destination.path) {
            return false
        }
        guard let source = entry.pngUrl,
              let sourceURL = URL(string: source) else {
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: sourceURL)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                try data.write(to: destination, options: .atomic)
                return true
            }
        } catch {
            print("Symbol download failed for \(entry.symbol): \(error.localizedDescription)")
        }

        return false
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobileCardImages", isDirectory: true)
    }

    private static var symbolCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobileSymbols", isDirectory: true)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private static func cacheURL(for name: String) -> URL {
        cacheDirectory.appendingPathComponent(fileName(for: name))
    }

    private static func symbolCacheURL(for symbol: String) -> URL {
        symbolCacheDirectory.appendingPathComponent(symbolFileName(for: symbol))
    }

    private static func fileName(for name: String) -> String {
        let slug = name
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "\(slug.isEmpty ? "card" : slug).jpg"
    }

    private static func symbolFileName(for symbol: String) -> String {
        let cleaned = symbol
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "∞", with: "infinity")
        let slug = cleaned
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(slug.isEmpty ? "symbol" : slug).png"
    }

    private static func uniqueManifestEntries(_ images: [CardImageManifestEntry]) -> [CardImageManifestEntry] {
        var seen = Set<String>()
        var unique: [CardImageManifestEntry] = []

        for image in images.sorted(by: { $0.name < $1.name }) {
            let key = image.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(image)
        }

        return unique
    }

    private static func uniqueSymbolEntries(_ symbols: [SymbolManifestEntry]) -> [SymbolManifestEntry] {
        var seen = Set<String>()
        var unique: [SymbolManifestEntry] = []
        for symbol in symbols {
            let key = symbol.symbol
            if seen.insert(key).inserted {
                unique.append(symbol)
            }
        }
        return unique
    }
}

extension AiDifficulty {
    var menuLabel: String {
        switch self {
        case .easy:
            return "Easy"
        case .normal:
            return "Normal"
        case .hard:
            return "Hard"
        case .expert:
            return "Expert"
        }
    }
}

extension String {
    var phaseTitle: String {
        split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private extension CardIdentity {
    var isLand: Bool {
        typeLine.localizedCaseInsensitiveContains("land")
    }
}

private extension LegalAction {
    var displayLabel: String {
        if let shortLabel, !shortLabel.isEmpty {
            return shortLabel
        }
        switch type {
        case "pass_priority":
            return "Done"
        case "pass_until_response":
            return "Pass"
        case "pass_until_next_turn":
            return "Skip turn"
        case "play_land":
            return "Play"
        case "cast_spell":
            return "Cast"
        case "activate_ability":
            return "Ability"
        case "make_mana":
            return "Mana"
        default:
            return label
        }
    }

    var actionDetail: String? {
        if let zoneContext, !zoneContext.isEmpty {
            return zoneContext
        }
        if let sourceZone, !sourceZone.isEmpty {
            return sourceZone
        }
        let count = validTargetIds?.count ?? targetIds?.count ?? 0
        return count > 0 ? "\(count) choices" : nil
    }

    var actionPriority: Int {
        if isPrimary == true { return 0 }
        switch type {
        case "keep_hand", "resolve_choice", "play_land", "cast_spell":
            return 1
        case "choose_target", "choose_card", "choose_mode", "choose_ability", "choose_amount", "play_mana":
            return 2
        case "make_mana", "activate_ability", "pay_cost":
            return 3
        case "pass_priority":
            return 4
        case "pass_until_response", "pass_until_next_turn", "advance_phase":
            return 5
        case "concede":
            return 9
        default:
            return 6
        }
    }

    var systemImage: String {
        switch type {
        case "keep_hand":
            return "hand.thumbsup.fill"
        case "mulligan":
            return "arrow.counterclockwise"
        case "play_land":
            return "leaf.fill"
        case "cast_spell":
            return "sparkles"
        case "activate_ability", "choose_ability":
            return "bolt.fill"
        case "make_mana", "play_mana", "play_x_mana":
            return "circle.hexagongrid.fill"
        case "choose_target":
            return "scope"
        case "choose_card", "search_select":
            return "rectangle.stack.fill"
        case "choose_mode":
            return "square.stack.3d.up"
        case "choose_amount", "choose_multi_amount":
            return "number"
        case "order_triggers":
            return "arrow.up.arrow.down"
        case "commander_replacement":
            return "crown.fill"
        case "pass_priority", "pass_until_response", "pass_until_next_turn", "advance_phase":
            return "forward.fill"
        case "concede":
            return "flag.fill"
        default:
            return "circle.fill"
        }
    }
}

private let stageLabels = [
    "untap",
    "upkeep",
    "draw",
    "precombat-main",
    "begin-combat",
    "declare-attackers",
    "declare-blockers",
    "combat-damage",
    "end-combat",
    "postcombat-main",
    "end",
    "cleanup"
]

#Preview {
    ContentView()
}
