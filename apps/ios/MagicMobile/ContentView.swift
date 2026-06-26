import SwiftUI
import PhotosUI
import UIKit

enum UniversalPromptResponseCommandBuilder {
    static func command(
        gameId: String,
        bridgeRevision: Int?,
        promptEnvelope: PromptEnvelopeV2?,
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        amount: Int? = nil,
        amounts: [Int]? = nil,
        pile: Int? = nil,
        useCommandZone: Bool? = nil,
        manaType: String? = nil,
        pay: Bool? = nil
    ) -> GameCommand? {
        guard let command = PromptCommandBuilder.command(
            gameId: gameId,
            promptEnvelope: promptEnvelope,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            amount: amount,
            amounts: amounts,
            pile: pile,
            useCommandZone: useCommandZone,
            manaType: manaType,
            pay: pay
        ) else { return nil }
        return MagicMobileAPI.withExpectedBridgeRevision(command, expectedBridgeRevision: bridgeRevision)
    }
}

enum PromptSelectionRules {
    static func isValidSelectedCount(_ count: Int, minChoices: Int?, maxChoices: Int?) -> Bool {
        guard let minChoices, let maxChoices else { return false }
        return count >= minChoices && count <= maxChoices
    }

    static func selectedPromptCardId(selectedCard: ZoneCard?, validCards: [ZoneCard]) -> String? {
        guard let selectedCard else { return nil }
        let validIds = Set(validCards.flatMap { [$0.id, $0.instanceId] })
        guard validIds.contains(selectedCard.id) || validIds.contains(selectedCard.instanceId) else {
            return nil
        }
        return selectedCard.instanceId
    }

    static func boundsText(minChoices: Int?, maxChoices: Int?) -> String {
        guard let minChoices, let maxChoices else { return "min/max unavailable" }
        return "min \(minChoices) / max \(maxChoices)"
    }
}

struct ContentView: View {
    @AppStorage("magicmobile.playerDisplayName") private var playerDisplayName = ""
    @State private var serverURLText = ProcessInfo.processInfo.environment["MAGICMOBILE_SERVER_URL"] ?? "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud"
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
    @State private var inspectingZoneTitle: String? = nil
    @State private var inspectingZoneCards: [ZoneCard] = []

    @State private var pendingActionId: String?
    @State private var pendingCardInstanceId: String?
    @State private var pendingCastAction: LegalAction?
    @State private var pendingCastBeforeSnapshot: GameSnapshot?
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
    #if DEBUG
    @State private var didAutoStartFixtureForVisualQA = false
    #endif

    var body: some View {
        ZStack {
            if screen == .play {
                LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.08), Color(red: 0.16, green: 0.25, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            } else {
                MenuBackgroundSurface()
                    .ignoresSafeArea()
            }
            if screen == .play {
                ImmersivePlayShell(
                    snapshot: snapshot,
                    startupStatus: startupStatus,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    playerDisplayName: playerDisplayName,
                    avatarData: playerAvatarData,
                    pendingActionId: pendingActionId,
                    pendingCardInstanceId: pendingCardInstanceId,
                    liveUpdateStatus: liveUpdateStatus,
                    onInteractionFeedback: { message in
                        status = message
                        liveUpdateStatus = message
                    },
                    runAction: { action in Task { await run(action: action) } },
                    runCommand: { command, label, pendingId in Task { await run(command: command, label: label, pendingId: pendingId) } },
                    refreshGame: { Task { await refreshCurrentSnapshot() } },
                    reconnectGame: { reconnectLiveUpdates() },
                    newGame: { Task { await leaveCurrentGame(destination: .setup, reason: "start-new-game") } },
                    quitGame: { Task { await leaveCurrentGame(destination: .menu, reason: "quit-game") } },
                    viewZone: { title, cards in
                        inspectingZoneTitle = title
                        inspectingZoneCards = cards
                    }
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
            #if DEBUG
            if await maybeStartDesignPreviewForMagicPath() {
                return
            }
            #endif
            await checkBridge()
            await refreshCardCacheMetadata()
            await refreshPhoneAssetCacheCounts()
            #if DEBUG
            await maybeAutoStartFixtureForVisualQA()
            #endif
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
                        playerDisplayName: $playerDisplayName,
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
                        playerDisplayName: $playerDisplayName,
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
                startGame: { Task { await startGame() } },
                startFixtureGame: { Task { await startFixtureGame() } }
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
            let startup = try await api.startCommanderStartup(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty, humanDisplayName: playerDisplayName)
            startupStatus = startup
            status = startup.message ?? "XMage table starting"

            if startup.status == "ready", let nextSnapshot = startup.snapshot {
                applySnapshot(nextSnapshot)
                startupStatus = nil
                selectedCard = nil
                inspectedCard = nil
                status = "Commander game started with \(humanDeck.name)"
                startWebSocket(gameId: nextSnapshot.id)
                isLoading = false
                return
            }

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

    private func startFixtureGame(scenario: String = "commander-gauntlet") async {
        #if DEBUG
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
            startupId: "dev-fixture",
            status: "starting",
            snapshot: nil,
            message: "Requesting dev-only XMage \(scenario) fixture.",
            error: nil
        )
        screen = .play
        status = "Requesting dev-only XMage fixture"

        do {
            let nextSnapshot = try await api.startCommanderFixture(scenario: scenario)
            applySnapshot(nextSnapshot)
            startupStatus = nil
            status = "Dev XMage fixture started"
            startWebSocket(gameId: nextSnapshot.id)
        } catch {
            startupStatus = CommanderStartupResponse(
                startupId: "dev-fixture",
                status: "failed",
                snapshot: nil,
                message: nil,
                error: error.localizedDescription
            )
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
        isLoading = false
        #else
        errorMessage = "XMage fixtures are only available in debug builds."
        status = "XMage fixtures are debug-only"
        #endif
    }

    private func leaveCurrentGame(destination: AppScreen, reason: String) async {
        let gameId = snapshot?.id
        stopWebSocket()
        if let api, let gameId {
            do {
                _ = try await api.cleanupGame(gameId: gameId, reason: reason)
            } catch {
                status = "Left local game view. Server cleanup needs retry: \(error.localizedDescription)"
            }
        }
        snapshot = nil
        startupStatus = nil
        selectedCard = nil
        inspectedCard = nil
        pendingActionId = nil
        pendingCardInstanceId = nil
        lastSubmittedActionId = nil
        lastSubmittedSnapshotSignature = nil
        liveUpdateStatus = "Idle"
        screen = destination
        if status.isEmpty || !status.contains("cleanup needs retry") {
            status = destination == .menu ? "Returned to menu" : "Ready for a new Commander game"
        }
    }

    #if DEBUG
    private func maybeStartDesignPreviewForMagicPath() async -> Bool {
        guard let previewText = ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"], !previewText.isEmpty else {
            return false
        }
        let state = GameBoardDesignPreviewState(rawValue: previewText) ?? .normalBattlefield
        let previewSnapshot = GameBoardPreviewFixtures.snapshot(state)
        snapshot = previewSnapshot
        selectedCard = GameBoardPreviewFixtures.selectedCard(for: state, snapshot: previewSnapshot)
        inspectedCard = nil
        pendingActionId = nil
        pendingCardInstanceId = nil
        startupStatus = nil
        liveUpdateStatus = "Design Preview"
        status = "Design preview: \(state.title). Not gameplay proof."
        screen = .play
        return true
    }

    private func maybeAutoStartFixtureForVisualQA() async {
        guard !didAutoStartFixtureForVisualQA else { return }
        guard ProcessInfo.processInfo.environment["MAGICMOBILE_AUTO_START_FIXTURE"] == "true" else { return }
        didAutoStartFixtureForVisualQA = true
        let scenario = ProcessInfo.processInfo.environment["MAGICMOBILE_AUTO_START_FIXTURE_SCENARIO"] ?? "commander-gauntlet"
        await startFixtureGame(scenario: scenario)
    }
    #endif

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
        pendingCardInstanceId = action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId
        if ["cast_spell", "play_land"].contains(action.type) {
            pendingCastAction = action
            pendingCastBeforeSnapshot = currentSnapshot
        }
        lastSubmittedActionId = action.id
        lastSubmittedSnapshotSignature = currentSignature
        status = "Sending \(action.shortLabel ?? action.label)"

        do {
            let previousSignature = snapshotSignature(currentSnapshot)
            let preparedCommand = try api.preparedCommand(
                for: action,
                gameId: currentSnapshot.id,
                expectedBridgeRevision: currentSnapshot.bridgeRevision
            )
            logCastSubmission(
                phase: "submit",
                action: action,
                command: preparedCommand,
                before: currentSnapshot,
                after: nil,
                outcome: nil
            )
            let nextSnapshot = try await api.submit(action: action, gameId: currentSnapshot.id, expectedBridgeRevision: currentSnapshot.bridgeRevision)
            let submittedOutcome = CastSubmissionClassifier.classify(action: action, before: currentSnapshot, after: nextSnapshot)
            let shouldPollDelayedOutcome = CastSubmissionClassifier.shouldPollForDelayedOutcome(action: action, before: currentSnapshot, after: nextSnapshot)
            logCastSubmission(
                phase: "response",
                action: action,
                command: preparedCommand,
                before: currentSnapshot,
                after: nextSnapshot,
                outcome: submittedOutcome
            )
            applySnapshot(nextSnapshot)
            if shouldPollDelayedOutcome {
                pendingActionId = action.id
                pendingCardInstanceId = action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId
                status = action.requiresPayment == true || action.manaCost?.isEmpty == false
                    ? "Waiting for XMage payment"
                    : "Waiting for XMage cast result"
            } else {
                status = submittedOutcome.statusMessage
            }
            if nextSnapshot.pendingStatus == "waiting_for_xmage" || shouldPollDelayedOutcome {
                let updated = shouldPollDelayedOutcome
                    ? await pollCastOutcomeAfterCommand(api: api, gameId: currentSnapshot.id, action: action, before: currentSnapshot)
                    : await pollSnapshotAfterCommand(api: api, gameId: currentSnapshot.id, previousSignature: previousSignature)
                if let latestSnapshot = snapshot {
                    let finalOutcome = CastSubmissionClassifier.classify(action: action, before: currentSnapshot, after: latestSnapshot)
                    logCastSubmission(
                        phase: "final",
                        action: action,
                        command: preparedCommand,
                        before: currentSnapshot,
                        after: latestSnapshot,
                        outcome: finalOutcome
                    )
                    status = finalOutcome.statusMessage
                    if finalOutcome == .rejectedStillInHand && updated {
                        errorMessage = castFailureMessage(action: action, before: currentSnapshot, after: latestSnapshot, reason: finalOutcome.statusMessage)
                    }
                }
                if !updated {
                    if let latestSnapshot = snapshot, ["cast_spell", "play_land"].contains(action.type) {
                        errorMessage = castFailureMessage(
                            action: action,
                            before: currentSnapshot,
                            after: latestSnapshot,
                            reason: "Cast did not progress before the XMage watchdog timed out."
                        )
                    }
                    clearPendingAction()
                }
            } else {
                if submittedOutcome == .rejectedStillInHand {
                    errorMessage = castFailureMessage(action: action, before: currentSnapshot, after: nextSnapshot, reason: submittedOutcome.statusMessage)
                }
                clearPendingAction()
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
            logCastSubmissionError(action: action, before: currentSnapshot, error: error)
            clearPendingAction()
        }
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
            let nextSnapshot = try await api.submit(command: command, gameId: currentSnapshot.id, expectedBridgeRevision: currentSnapshot.bridgeRevision)
            applySnapshot(nextSnapshot)
            status = nextSnapshot.pendingStatus == "waiting_for_xmage" ? "Waiting for XMage update" : "Action submitted"
            if nextSnapshot.pendingStatus == "waiting_for_xmage" {
                let updated = await pollSnapshotAfterCommand(api: api, gameId: currentSnapshot.id, previousSignature: previousSignature)
                if !updated {
                    clearPendingAction()
                }
            } else {
                clearPendingAction()
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
            clearPendingAction()
        }
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

    private func stopWebSocket() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        liveUpdateStatus = "Idle"
    }

    private func refreshCurrentSnapshot() async {
        guard let api, let gameId = snapshot?.id else {
            status = "No active XMage game to refresh"
            return
        }
        status = "Refreshing XMage snapshot"
        do {
            let refreshed = try await api.snapshot(gameId: gameId)
            applySnapshot(refreshed)
            status = "Latest XMage snapshot applied"
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
    }

    private func reconnectLiveUpdates() {
        guard let gameId = snapshot?.id else {
            status = "No active XMage game to reconnect"
            return
        }
        liveUpdateStatus = "Reconnecting"
        status = "Reconnecting live updates"
        startWebSocket(gameId: gameId)
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
        MagicMobileWebSocketEndpoint.url(gameId: gameId, httpBaseURL: baseURL)
    }

    private func snapshotSignature(_ snapshot: GameSnapshot) -> String {
        let legalActionIds = snapshot.legalActions?.map(\.id).joined(separator: ",") ?? ""
        let handCounts = snapshot.players.map { "\($0.playerId):\($0.zones.hand.count):\($0.zones.battlefield.count):\($0.zones.graveyard.count)" }.joined(separator: "|")
        return "\(snapshot.id)|\(snapshot.bridgeRevision ?? -1)|\(snapshot.xmageCycle ?? -1)|\(snapshot.turn)|\(snapshot.phase)|\(snapshot.step ?? "")|\(snapshot.priorityPlayerId ?? "")|\(snapshot.promptText ?? "")|\(handCounts)|\(legalActionIds)"
    }

    private func applySnapshot(_ nextSnapshot: GameSnapshot) {
        guard shouldAcceptSnapshot(nextSnapshot) else { return }
        let changedFromSubmittedSnapshot = lastSubmittedSnapshotSignature.map { snapshotSignature(nextSnapshot) != $0 } ?? false
        snapshot = nextSnapshot
        selectedCard = nil
        if let pendingCastAction, let pendingCastBeforeSnapshot,
           CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: pendingCastAction, before: pendingCastBeforeSnapshot, after: nextSnapshot) {
            return
        }
        if pendingActionId != nil && (nextSnapshot.pendingStatus != "waiting_for_xmage" || changedFromSubmittedSnapshot) {
            clearPendingAction()
        }
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

    @discardableResult
    private func pollSnapshotAfterCommand(api: MagicMobileAPI, gameId: String, previousSignature: String) async -> Bool {
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let refreshed = try? await api.snapshot(gameId: gameId) else { continue }
            let changed = snapshotSignature(refreshed) != previousSignature
            applySnapshot(refreshed)
            if changed {
                status = "XMage board updated"
                return true
            }
        }
        if let health = try? await api.health() {
            status = "\(health.status): \(health.reason)"
        } else {
            status = "XMage update delayed. Refresh or retry the action."
        }
        return false
    }

    @discardableResult
    private func pollCastOutcomeAfterCommand(api: MagicMobileAPI, gameId: String, action: LegalAction, before: GameSnapshot) async -> Bool {
        for _ in 0..<18 {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let refreshed = try? await api.snapshot(gameId: gameId) else { continue }
            applySnapshot(refreshed)
            if !CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: action, before: before, after: refreshed) {
                status = CastSubmissionClassifier.classify(action: action, before: before, after: refreshed).statusMessage
                return true
            }
            status = "Waiting for XMage cast result"
        }
        status = "XMage cast result delayed. Refresh or try again."
        return false
    }

    private func clearPendingAction() {
        pendingActionId = nil
        pendingCardInstanceId = nil
        pendingCastAction = nil
        pendingCastBeforeSnapshot = nil
        lastSubmittedActionId = nil
        lastSubmittedSnapshotSignature = nil
    }

    private func castFailureMessage(action: LegalAction, before: GameSnapshot, after: GameSnapshot, reason: String) -> String {
        """
        \(reason)

        Card: \(action.cardName ?? action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId ?? "unknown")
        Action: \(action.type) / \(action.id)
        Source: \(action.effectiveSourceInstanceId ?? "nil")
        Card ID: \(action.effectiveCardInstanceId ?? "nil")
        Zone: \(action.effectiveSourceZone ?? action.effectiveFromZone ?? "nil")
        Ability: \(action.effectiveAbilityId ?? "nil")
        Before: \(castDebugSummary(before))
        After: \(castDebugSummary(after))
        """
    }

    private func logCastSubmission(
        phase: String,
        action: LegalAction,
        command: GameCommand,
        before: GameSnapshot,
        after: GameSnapshot?,
        outcome: CastSubmissionOutcome?
    ) {
        guard ["cast_spell", "play_land"].contains(action.type) else { return }
        let payload = (try? JSONEncoder.magicMobile.encode(command))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "<unencodable>"
        print(
            """
            [DragCast] \(phase) card=\(action.cardName ?? action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId ?? "unknown") actionId=\(action.id) type=\(action.type) source=\(action.effectiveSourceInstanceId ?? "nil") cardId=\(action.effectiveCardInstanceId ?? "nil") abilityId=\(action.effectiveAbilityId ?? "nil") before=\(castDebugSummary(before)) after=\(after.map(castDebugSummary) ?? "nil") outcome=\(outcome?.statusMessage ?? "pending") command=\(payload)
            """
        )
    }

    private func logCastSubmissionError(action: LegalAction, before: GameSnapshot, error: Error) {
        guard ["cast_spell", "play_land"].contains(action.type) else { return }
        print(
            "[DragCast] error card=\(action.cardName ?? action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId ?? "unknown") actionId=\(action.id) before=\(castDebugSummary(before)) failureReason=\(error.localizedDescription)"
        )
    }

    private func castDebugSummary(_ snapshot: GameSnapshot) -> String {
        let handCount = snapshot.human?.zones.hand.count ?? 0
        let stackCount = snapshot.xmage?.stack.count ?? snapshot.human?.zones.stack.count ?? 0
        let mana = snapshot.human?.manaPool.map { "W\($0.W) U\($0.U) B\($0.B) R\($0.R) G\($0.G) C\($0.C)" } ?? "nil"
        let prompt = snapshot.promptEnvelopeV2.map { "\($0.method)|\($0.responseCommand?.type ?? $0.responseKind)" } ?? "nil"
        return "rev=\(snapshot.bridgeRevision ?? -1) cycle=\(snapshot.xmageCycle ?? -1) hand=\(handCount) stack=\(stackCount) mana=\(mana) prompt=\(prompt) pending=\(snapshot.pendingStatus ?? "nil")"
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

enum MagicMobileWebSocketEndpoint {
    static func url(
        gameId: String,
        httpBaseURL: URL,
        overrideBaseText: String? = ProcessInfo.processInfo.environment["MAGICMOBILE_XMAGE_WS_URL"]
            ?? ProcessInfo.processInfo.environment["MAGICMOBILE_WEBSOCKET_URL"]
    ) -> URL? {
        let base = overrideBaseText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
            ?? httpBaseURL

        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var allowedPathSegment = CharacterSet.urlPathAllowed
        allowedPathSegment.remove(charactersIn: "/")
        let encodedGameId = gameId.addingPercentEncoding(withAllowedCharacters: allowedPathSegment) ?? gameId
        components.percentEncodedPath = "/" + ([basePath, "ws", "games", encodedGameId].filter { !$0.isEmpty }.joined(separator: "/"))
        components.query = nil
        components.fragment = nil
        return components.url
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
    @Binding var playerDisplayName: String
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Player name")
                        .font(.caption.weight(.black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                    TextField("Enter name", text: $playerDisplayName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .textFieldStyle(GameTextFieldStyle())
                    Text("Used for the in-game HUD and XMage table seat.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
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
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
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
    @Binding var playerDisplayName: String
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
    let startFixtureGame: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 10
            let leftWidth = min(max(proxy.size.width * 0.32, 278), 330)
            let rightWidth = max(proxy.size.width - leftWidth - gap, 430)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(spacing: gap) {
                    Panel(title: "Connection") {
                        TextField("Enter name", text: $playerDisplayName)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .textFieldStyle(GameTextFieldStyle())
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

                        #if DEBUG
                        Button("Start XMage gauntlet fixture", action: startFixtureGame)
                            .buttonStyle(SecondaryButtonStyle())
                        Text("Debug only. Requires ENABLE_XMAGE_FIXTURES=true and a non-production gateway.")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MagicPalette.antiqueGold.opacity(0.82))
                            .lineLimit(2)
                        #endif
                    }
                    .frame(width: rightWidth)
                }
                .frame(maxWidth: .infinity, alignment: .top)
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
    let playerDisplayName: String
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let liveUpdateStatus: String
    let onInteractionFeedback: (String) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let refreshGame: () -> Void
    let reconnectGame: () -> Void
    let newGame: () -> Void
    let quitGame: () -> Void
    let viewZone: (String, [ZoneCard]) -> Void

    var body: some View {
        NativeGameView(
            snapshot: snapshot,
            startupStatus: startupStatus,
            selectedCard: $selectedCard,
            inspectedCard: $inspectedCard,
            playerDisplayName: playerDisplayName,
            avatarData: avatarData,
            pendingActionId: pendingActionId,
            pendingCardInstanceId: pendingCardInstanceId,
            liveUpdateStatus: liveUpdateStatus,
            onInteractionFeedback: onInteractionFeedback,
            runAction: runAction,
            runCommand: runCommand,
            refreshGame: refreshGame,
            reconnectGame: reconnectGame,
            newGame: newGame,
            quitGame: quitGame,
            viewZone: viewZone
        )
    }
}

struct NativeGameView: View {
    let snapshot: GameSnapshot?
    let startupStatus: CommanderStartupResponse?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let playerDisplayName: String
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let liveUpdateStatus: String
    let onInteractionFeedback: (String) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let refreshGame: () -> Void
    let reconnectGame: () -> Void
    let newGame: () -> Void
    let quitGame: () -> Void
    let viewZone: (String, [ZoneCard]) -> Void
    @State private var isLogOpen = false
    @State private var isGameMenuOpen = false
    @State private var gameMenuConfirmation: GameMenuConfirmation?
    @State private var isOverPlayerDropZone = false
    @State private var interactionState = GameBoardInteractionState.idle
    @State private var inspectingZoneTitle: String? = nil
    @State private var inspectingZoneCards: [ZoneCard] = []
    @State private var isPromptDetailOpen = false
    @State private var dragActionChoice: DragActionChoice?
    @State private var aiWaitBeganAt = Date()
    @State private var aiWaitKey = ""

    private func localViewZone(title: String, cards: [ZoneCard]) {
        inspectingZoneTitle = title
        inspectingZoneCards = cards
    }

    @ViewBuilder
    var body: some View {
        if let snapshot, let human = snapshot.human, let opponent = snapshot.opponent {
            let humanName = human.displayName ?? MagicMobileAPI.cleanPlayerName(playerDisplayName) ?? "You"
            let opponentName = opponent.displayName ?? "Ashen Sage"
            ZStack {
                BattlefieldSurface()
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    // LEFT COLUMN
                    VStack(alignment: .leading, spacing: 0) {
                        OpponentVerticalHUD(name: opponentName, player: opponent, active: snapshot.activePlayerId == opponent.playerId, opponentId: human.playerId)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)

                        Spacer()

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.vertical, 8)

                        HStack(alignment: .bottom, spacing: 4) {
                            ManaPoolHUD(manaPool: human.manaPool, vertical: true)
                            PlayerVerticalHUD(name: humanName, player: human, active: snapshot.activePlayerId == human.playerId, opponentId: opponent.playerId, viewZone: { localViewZone(title: $0, cards: $1) })
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 4)
                    .frame(width: 136)
                    .background(MagicPalette.iron.opacity(0.85))

                    // CENTER COLUMN
                    GeometryReader { proxy in
                        let metrics = BattlefieldLayoutMetrics(proxy: proxy)
                        let targetableIds = targetableCardIds(in: snapshot)
                        let shouldShowCompactPrompt = CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId)
                        let derivedInteractionMode = GameBoardInteractionState.mode(
                            for: snapshot,
                            pendingActionId: pendingActionId,
                            selectedCard: selectedCard
                        )

                        ZStack {
                            BattlefieldRow(title: "Opponent board", cards: nonLandPermanents(opponent.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.boardColumnRect.width, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) })
                                .frame(width: metrics.opponentBattlefieldRect.width, height: metrics.opponentBattlefieldRect.height)
                                .position(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)

                            BattlefieldRow(title: "Opponent lands", cards: landPermanents(opponent.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.boardColumnRect.width, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) })
                                .frame(width: metrics.opponentLandsRect.width, height: metrics.opponentLandsRect.height)
                                .position(x: metrics.opponentLandsRect.midX, y: metrics.opponentLandsRect.midY)

                            Rectangle()
                                .fill(.white.opacity(0.13))
                                .frame(width: max(metrics.centerStripRect.width - 28, 80), height: 1.5)
                                .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

                            BattlefieldRow(title: "Your board", cards: nonLandPermanents(human.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.boardColumnRect.width, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) })
                                .frame(width: metrics.playerBattlefieldRect.width, height: metrics.playerBattlefieldRect.height)
                                .position(x: metrics.playerBattlefieldRect.midX, y: metrics.playerBattlefieldRect.midY)

                            BattlefieldRow(title: "Your lands", cards: landPermanents(human.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.boardColumnRect.width, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) })
                                .frame(width: metrics.playerLandsRect.width, height: metrics.playerLandsRect.height)
                                .position(x: metrics.playerLandsRect.midX, y: metrics.playerLandsRect.midY)

                            HStack(spacing: 8) {
                                PromptPill(snapshot: snapshot)
                                    .frame(maxWidth: .infinity)
                                
                                let revealedCards = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
                                let lookedAtCards = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
                                if !revealedCards.isEmpty {
                                    FloatingZoneChip(title: "Revealed", count: revealedCards.count, icon: "eye") {
                                        localViewZone(title: "Revealed", cards: revealedCards)
                                    }
                                }
                                if !lookedAtCards.isEmpty {
                                    FloatingZoneChip(title: "Looked", count: lookedAtCards.count, icon: "eye.trianglebadge.exclamationmark") {
                                        localViewZone(title: "Looked", cards: lookedAtCards)
                                    }
                                }
                            }
                            .frame(width: metrics.centerStripRect.width, height: metrics.centerStripRect.height)
                            .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

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
                                interactionState: $interactionState,
                                metrics: metrics,
                                isOverPlayerDropZone: $isOverPlayerDropZone,
                                onDropFeedback: onInteractionFeedback,
                                onActionChoice: { actions, message in
                                    dragActionChoice = DragActionChoice(message: message, actions: actions)
                                },
                                runAction: runAction
                            )
                                .frame(width: metrics.handRect.width, height: metrics.handRect.height)
                                .position(x: metrics.handRect.midX, y: metrics.handRect.midY)
                                .onChange(of: derivedInteractionMode) { _, mode in
                                    interactionState.mode = mode
                                }



                            if case .targeting = derivedInteractionMode, !targetableIds.isEmpty {
                                TargetingStatusPill(count: targetableIds.count)
                                    .position(x: metrics.bottomActionRect.midX, y: metrics.bottomActionRect.midY)
                                    .allowsHitTesting(false)
                            }

                            // Floating Zone Inspector overlay
                            if let inspectingZoneTitle {
                                CompactZoneInspectorOverlay(
                                    title: inspectingZoneTitle,
                                    cards: inspectingZoneCards,
                                    selectedCard: $selectedCard,
                                    inspectedCard: $inspectedCard,
                                    closeAction: {
                                        self.inspectingZoneTitle = nil
                                        self.inspectingZoneCards = []
                                    }
                                )
                                .position(x: metrics.size.width / 2, y: metrics.size.height / 2)
                                .transition(.scale.combined(with: .opacity))
                            }
                            if let inspectedCard {
                                Color.black.opacity(0.01)
                                    .ignoresSafeArea()
                                    .onTapGesture { self.inspectedCard = nil }
                                    .zIndex(99)
                                
                                CardInspector(card: inspectedCard)
                                    .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                                    .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                                    .zIndex(100)
                            }

                            if shouldShowCompactPrompt {
                                CompactPromptPopup(
                                    snapshot: snapshot,
                                    pendingActionId: pendingActionId,
                                    runAction: runAction,
                                    runCommand: runCommand,
                                    openDetails: {
                                        isPromptDetailOpen = true
                                    }
                                )
                                .frame(
                                    width: min(max(metrics.size.width * 0.30, 260), 340),
                                    height: min(max(metrics.size.height * 0.20, 98), 178)
                                )
                                .position(x: metrics.boardColumnRect.midX, y: metrics.compactPromptRect.midY)
                                .transition(.scale.combined(with: .opacity))
                                .zIndex(20)
                            }

                            if let dragActionChoice {
                                DragActionChoicePopup(
                                    choice: dragActionChoice,
                                    pendingActionId: pendingActionId,
                                    runAction: { action in
                                        self.dragActionChoice = nil
                                        runAction(action)
                                    },
                                    cancel: {
                                        self.dragActionChoice = nil
                                    }
                                )
                                .frame(width: min(max(metrics.size.width * 0.30, 260), 340))
                                .position(x: metrics.boardColumnRect.midX, y: metrics.compactPromptRect.midY)
                                .transition(.scale.combined(with: .opacity))
                                .zIndex(21)
                            }
                        }
                        .onAppear {
                            interactionState.mode = derivedInteractionMode
                        }
                    }

                    // RIGHT COLUMN
                    VStack(alignment: .trailing, spacing: 8) {
                        MagicPathPhaseRail(
                            snapshot: snapshot,
                            passAction: passAction(in: snapshot.legalActions ?? []),
                            skipAction: skipAction(in: snapshot.legalActions ?? []),
                            logAction: { isLogOpen.toggle() },
                            settingsAction: { isGameMenuOpen = true },
                            runAction: runAction,
                            onlyPhases: true
                        )
                        .padding(.top, 12)

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("LOG")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(MagicPalette.antiqueGold)
                                Spacer()
                            }
                            ScrollViewReader { logProxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        ForEach(snapshot.log) { entry in
                                            Text(entry.message)
                                                .font(.system(size: 7.5, weight: .bold))
                                                .foregroundStyle(MagicPalette.parchment.opacity(0.72))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(.trailing, 4)
                                }
                                .onChange(of: snapshot.log.count) { _, _ in
                                    if let lastId = snapshot.log.last?.id {
                                        withAnimation {
                                            logProxy.scrollTo(lastId, anchor: .bottom)
                                        }
                                    }
                                }
                                .onAppear {
                                    if let lastId = snapshot.log.last?.id {
                                        logProxy.scrollTo(lastId, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        if let xmageStack = snapshot.xmage?.stack, !xmageStack.isEmpty {
                            XmageStackPeek(
                                objects: xmageStack,
                                legalActions: snapshot.legalActions ?? [],
                                promptText: snapshot.promptEnvelopeV2?.message ?? snapshot.promptText,
                                selectedCard: $selectedCard,
                                inspectedCard: $inspectedCard
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                        } else if !human.zones.stack.isEmpty {
                            StackPeek(cards: human.zones.stack, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                        }

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.horizontal, 8)

                        VStack(spacing: 6) {
                            let promptActions = snapshot.legalActions?.filter { $0.type == "prompt" || $0.type == "prompt_action" } ?? []
                            if !promptActions.isEmpty {
                                ForEach(promptActions.prefix(2)) { action in
                                    Button {
                                        runAction(action)
                                    } label: {
                                        Text(action.label.uppercased())
                                            .font(.system(size: 12, weight: .black, design: .serif))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                                }
                            } else {
                                let passAct = passAction(in: snapshot.legalActions ?? [])
                                Button {
                                    if let passAct {
                                        runAction(passAct)
                                    }
                                } label: {
                                    Text(passAct == nil ? "WAIT" : "PASS")
                                        .font(.system(size: 12, weight: .black, design: .serif))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                                .disabled(passAct == nil)
                            }

                            let skipAct = skipAction(in: snapshot.legalActions ?? [])
                            Button {
                                if let skipAct {
                                    runAction(skipAct)
                                }
                            } label: {
                                Text(MagicPathPhaseRail.skipButtonLabel(snapshot: snapshot, action: skipAct))
                                    .font(.system(size: 8, weight: .black, design: .serif))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                            .disabled(skipAct == nil)

                            HStack(spacing: 8) {
                                Button {
                                    isLogOpen.toggle()
                                } label: {
                                    Image(systemName: "list.bullet.rectangle")
                                }
                                .buttonStyle(IconButtonStyle(small: true))

                                Button {
                                    isGameMenuOpen = true
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                }
                                .buttonStyle(IconButtonStyle(small: true))
                            }
                            .padding(.top, 2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                    }
                    .overlay(alignment: .center) {
                        if snapshot.isWaitingOnAIOrStalled {
                            AIWaitFallbackControls(
                                snapshot: snapshot,
                                beganAt: aiWaitBeganAt,
                                refreshAction: refreshGame,
                                reconnectAction: reconnectGame
                            )
                            .padding(.horizontal, 10)
                        }
                    }
                    .frame(width: 128)
                    .background(MagicPalette.iron.opacity(0.85))
                }
                .sheet(isPresented: $isPromptDetailOpen) {
                    UniversalPromptActionPanel(
                        snapshot: snapshot,
                        selectedCardActions: [],
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        pendingActionId: pendingActionId,
                        runAction: runAction,
                        runCommand: runCommand,
                        viewZone: viewZone,
                        showsGameSurfaceSections: false
                    )
                    .padding(14)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isGameMenuOpen) {
                    GameManagementMenu(
                        concedeAction: concedeAction(in: snapshot.legalActions ?? []),
                        runAction: runAction,
                        confirmStartNew: {
                            gameMenuConfirmation = .startNew
                        },
                        confirmQuit: {
                            gameMenuConfirmation = .quit
                        }
                    )
                    .presentationDetents([.height(250)])
                    .presentationDragIndicator(.visible)
                }
                .confirmationDialog(
                    gameMenuConfirmation?.title ?? "Leave game?",
                    isPresented: Binding(
                        get: { gameMenuConfirmation != nil },
                        set: { if !$0 { gameMenuConfirmation = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if gameMenuConfirmation == .startNew {
                        Button("Start New Game", role: .destructive) {
                            gameMenuConfirmation = nil
                            isGameMenuOpen = false
                            newGame()
                        }
                    } else if gameMenuConfirmation == .quit {
                        Button("Quit to Menu", role: .destructive) {
                            gameMenuConfirmation = nil
                            isGameMenuOpen = false
                            quitGame()
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        gameMenuConfirmation = nil
                    }
                } message: {
                    Text(gameMenuConfirmation?.message ?? "")
                }
            }
            .onAppear {
                updateAIWaitStart(for: snapshot)
            }
            .onChange(of: snapshot.aiWaitSignature) { _, _ in
                updateAIWaitStart(for: snapshot)
            }
        } else {
            LoadingGameView(startupStatus: startupStatus)
        }
    }

    private func updateAIWaitStart(for snapshot: GameSnapshot) {
        let key = snapshot.aiWaitSignature
        if key != aiWaitKey {
            aiWaitKey = key
            aiWaitBeganAt = Date()
        }
    }

    private func passAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { ["pass_priority", "pass_until_response"].contains($0.type) }
    }

    private func skipAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { $0.type == "pass_until_next_turn" }
    }

    private func concedeAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { $0.type == "concede" }
    }

    private func selectedActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard let selectedCard else { return [] }
        return snapshot.legalActions?.filter { $0.cardInstanceId == selectedCard.instanceId || $0.sourceInstanceId == selectedCard.instanceId } ?? []
    }

    private func targetableCardIds(in snapshot: GameSnapshot) -> Set<String> {
        guard let prompt = snapshot.promptEnvelopeV2 else { return [] }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        let isTargetPrompt = type == "choose_target" ||
            prompt.responseKind.lowercased() == "target" ||
            prompt.method.localizedCaseInsensitiveContains("TARGET")
        guard isTargetPrompt else { return [] }
        return GameBoardInteractionState.validTargetIds(from: prompt, actions: snapshot.legalActions ?? [])
    }

    private func submitTarget(_ card: ZoneCard, snapshot: GameSnapshot) {
        guard targetableCardIds(in: snapshot).contains(card.instanceId) || targetableCardIds(in: snapshot).contains(card.id) else {
            onInteractionFeedback("\(card.card.name) is not an exposed XMage target")
            return
        }
        guard let prompt = snapshot.promptEnvelopeV2 else {
            onInteractionFeedback("XMage target prompt is no longer active")
            return
        }
        let promptId = prompt.responseCommand?.promptId ?? prompt.id
        guard let command = UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: prompt,
            type: "choose_target",
            promptId: promptId,
            playerId: prompt.playerId,
            ids: [card.instanceId]
        ) else {
            onInteractionFeedback("XMage did not expose a mobile-safe target command")
            return
        }
        runCommand(command, "Target \(card.card.name)", "\(promptId)-\(card.instanceId)")
    }

    private func designPreviewState(from snapshot: GameSnapshot) -> GameBoardDesignPreviewState {
        let raw = snapshot.id.replacingOccurrences(of: "design-preview-", with: "")
        return GameBoardDesignPreviewState(rawValue: raw) ?? .normalBattlefield
    }

    private func landPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { $0.card.isLand }
    }

    private func nonLandPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { !$0.card.isLand }
    }
}

struct BattlefieldLayoutMetrics {
    static let magicCardHeightToWidth: CGFloat = 88.0 / 63.0

    let size: CGSize
    let safeArea: EdgeInsets

    init(proxy: GeometryProxy) {
        size = proxy.size
        safeArea = proxy.safeAreaInsets
    }

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.safeArea = safeArea
    }

    var safeFrame: CGRect {
        let margin: CGFloat = 10
        let x = safeArea.leading + margin
        let y = safeArea.top + 8
        let width = max(size.width - safeArea.leading - safeArea.trailing - margin * 2, 320)
        let height = max(size.height - safeArea.top - safeArea.bottom - 16, 300)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var topStatusRect: CGRect {
        CGRect(x: safeFrame.minX, y: safeFrame.minY, width: safeFrame.width, height: 40)
    }

    var rightDockRect: CGRect {
        let width = min(max(safeFrame.width * 0.20, 210), 268)
        let top = topStatusRect.maxY + 8
        return CGRect(x: safeFrame.maxX - width, y: top, width: width, height: max(safeFrame.maxY - top, 220))
    }

    var boardColumnRect: CGRect {
        let top = topStatusRect.maxY + 4
        return CGRect(
            x: safeFrame.minX,
            y: top,
            width: max(safeFrame.maxX - safeFrame.minX, 320),
            height: max(safeFrame.maxY - top, 260)
        )
    }

    var handRect: CGRect {
        CGRect(
            x: boardColumnRect.minX,
            y: boardColumnRect.maxY - handFrameHeight,
            width: boardColumnRect.width,
            height: handFrameHeight
        )
    }

    var opponentBattlefieldRect: CGRect {
        laneRects[0]
    }

    var opponentLandsRect: CGRect {
        laneRects[1]
    }

    var centerStripRect: CGRect {
        laneRects[2]
    }

    var playerBattlefieldRect: CGRect {
        laneRects[3]
    }

    var playerLandsRect: CGRect {
        laneRects[4]
    }

    var bottomActionRect: CGRect {
        let width = min(max(boardColumnRect.width * 0.58, 320), 460)
        let height: CGFloat = 38
        return CGRect(
            x: boardColumnRect.midX - width / 2,
            y: handRect.minY - height - 8,
            width: width,
            height: height
        )
    }

    var compactPromptRect: CGRect {
        let width = min(max(boardColumnRect.width * 0.30, 260), 340)
        let height = min(max(size.height * 0.20, 98), 178)
        return CGRect(
            x: boardColumnRect.midX - width / 2,
            y: max(centerStripRect.maxY + 6, playerBattlefieldRect.minY + 3),
            width: width,
            height: height
        )
    }

    var rightActionPanelRect: CGRect {
        let top = phaseRailRect.maxY + 8
        return CGRect(
            x: rightDockRect.minX,
            y: top,
            width: rightDockRect.width,
            height: max(rightDockRect.maxY - top, 190)
        )
    }

    var detailSheetRect: CGRect {
        let width = min(max(boardColumnRect.width * 0.45, 260), 340)
        let height = min(max(safeFrame.height * 0.60, 240), 320)
        return CGRect(
            x: boardColumnRect.minX + 8,
            y: max(topStatusRect.maxY + 12, centerStripRect.maxY - height * 0.34),
            width: width,
            height: height
        )
    }

    var phaseRailRect: CGRect {
        let top = diagnosticsY + 28
        let height: CGFloat = 36
        return CGRect(
            x: rightDockRect.minX + 8,
            y: top,
            width: max(rightDockRect.width - 16, 190),
            height: height
        )
    }

    var playWidth: CGFloat {
        boardColumnRect.width
    }

    var playCenterX: CGFloat {
        boardColumnRect.midX
    }

    var leftInset: CGFloat {
        boardColumnRect.minX
    }

    var railWidth: CGFloat {
        min(max(rightDockRect.width * 0.34, 64), 82)
    }

    var hudWidth: CGFloat {
        min(boardColumnRect.width * 0.34, 230)
    }

    var opponentHUDWidth: CGFloat {
        min(boardColumnRect.width * 0.24, 168)
    }

    var turnBadgeWidth: CGFloat {
        min(max(boardColumnRect.width * 0.24, 180), 220)
    }

    var turnBadgeX: CGFloat {
        boardColumnRect.minX + turnBadgeWidth / 2
    }

    var liveStatusX: CGFloat {
        min(boardColumnRect.maxX - 92, rightDockRect.minX - 92)
    }

    var opponentHUDX: CGFloat {
        boardColumnRect.midX
    }

    var playerHUDX: CGFloat {
        boardColumnRect.minX + hudWidth / 2 + 8
    }

    var bottomHUDY: CGFloat {
        max(handRect.minY - 12, playerLandsRect.maxY + 22)
    }

    var manaHUDX: CGFloat {
        boardColumnRect.minX + 102
    }

    var manaHUDY: CGFloat {
        playerLandsRect.minY - 14
    }

    var topHUDY: CGFloat {
        topStatusRect.midY
    }

    var diagnosticsY: CGFloat {
        rightDockRect.minY + 28
    }

    var stackPeekWidth: CGFloat {
        min(max(centerStripRect.width * 0.32, 190), 330)
    }

    var promptY: CGFloat {
        centerStripRect.midY
    }

    var playerDropZone: CGRect {
        playerPlayAreaRect
    }

    var playerPlayAreaRect: CGRect {
        CGRect(
            x: boardColumnRect.minX,
            y: playerBattlefieldRect.minY - 6,
            width: boardColumnRect.width,
            height: playerLandsRect.maxY - playerBattlefieldRect.minY + 14
        )
    }

    var inspectorX: CGFloat {
        detailSheetRect.midX
    }

    var inspectorY: CGFloat {
        detailSheetRect.midY
    }

    var logX: CGFloat {
        detailSheetRect.maxX + 22
    }

    var logY: CGFloat {
        min(size.height * 0.44, 210)
    }

    var stackRect: CGRect {
        let w: CGFloat = 200
        let h: CGFloat = 86
        return CGRect(
            x: size.width - w - 8,
            y: size.height - h - 8,
            width: w,
            height: h
        )
    }

    var handCardWidth: CGFloat {
        let horizontalFit = boardColumnRect.width / 7.7
        let verticalScale = safeFrame.height < 360 ? 0.24 : 0.30
        let verticalFit = max((safeFrame.height * verticalScale) / Self.magicCardHeightToWidth, 58)
        let minimumWidth: CGFloat = boardColumnRect.width < 540 ? 60 : 68
        return min(max(horizontalFit, minimumWidth), min(verticalFit, 90))
    }

    var handCardHeight: CGFloat {
        handCardWidth * Self.magicCardHeightToWidth
    }

    var handFrameHeight: CGFloat {
        handCardHeight + 14
    }

    var handY: CGFloat {
        handRect.midY
    }

    var handVisualTopY: CGFloat {
        handRect.minY - 24
    }

    var permanentCardWidth: CGFloat {
        min(max(boardColumnRect.width / 9.4, 52), 76) * battlefieldScale
    }

    var permanentCardHeight: CGFloat {
        permanentCardWidth * Self.magicCardHeightToWidth
    }

    var landCardWidth: CGFloat {
        min(max(boardColumnRect.width / 12.4, 46), 62) * landScale
    }

    var landCardHeight: CGFloat {
        max(44, landCardWidth * Self.magicCardHeightToWidth)
    }

    var landRowHeight: CGFloat {
        landCardHeight + 8
    }

    var compactRowHeight: CGFloat {
        permanentCardHeight + 8
    }

    var rowHeight: CGFloat {
        compactRowHeight
    }

    var battlefieldRowsHeight: CGFloat {
        compactRowHeight * 2 + landRowHeight * 2 + centerStripHeight + laneGap * 4
    }

    private var battlefieldRect: CGRect {
        let top = boardColumnRect.minY + 2
        let bottom = handRect.minY - 4
        return CGRect(x: boardColumnRect.minX, y: top, width: boardColumnRect.width, height: max(bottom - top, 190))
    }

    private var laneRects: [CGRect] {
        let totalGap = laneGap * 4
        let available = max(battlefieldRect.height - centerStripHeight - totalGap, 160)
        let landHeight = min(max(available * 0.18, 44), 58)
        let battleHeight = max((available - landHeight * 2) / 2, 52)
        var y = battlefieldRect.minY
        let opponentBattle = CGRect(x: battlefieldRect.minX, y: y, width: battlefieldRect.width, height: battleHeight)
        y += battleHeight + laneGap
        let opponentLands = CGRect(x: battlefieldRect.minX, y: y, width: battlefieldRect.width, height: landHeight)
        y += landHeight + laneGap
        let center = CGRect(x: battlefieldRect.minX, y: y, width: battlefieldRect.width, height: centerStripHeight)
        y += centerStripHeight + laneGap
        let playerBattle = CGRect(x: battlefieldRect.minX, y: y, width: battlefieldRect.width, height: battleHeight)
        y += battleHeight + laneGap
        let playerLands = CGRect(x: battlefieldRect.minX, y: y, width: battlefieldRect.width, height: landHeight)
        return [opponentBattle, opponentLands, center, playerBattle, playerLands]
    }

    private var laneGap: CGFloat {
        3
    }

    private var centerStripHeight: CGFloat {
        min(max(battlefieldRect.height * 0.11, 24), 38)
    }

    private var battlefieldScale: CGFloat {
        min(1, max(0.88, (opponentBattlefieldRect.height - 8) / max(naturalPermanentCardHeight, 1)))
    }

    private var landScale: CGFloat {
        1
    }

    private var naturalPermanentCardHeight: CGFloat {
        min(max(boardColumnRect.width / 9.4, 52), 76) * 1.40
    }

    private var naturalLandCardHeight: CGFloat {
        max(44, min(max(boardColumnRect.width / 12.4, 46), 62) * 1.12)
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
                .ignoresSafeArea()

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
        .ignoresSafeArea()
    }
}

enum MagicPalette {
    static let antiqueGold = Color(red: 0.82, green: 0.62, blue: 0.27)
    static let brass = Color(red: 0.62, green: 0.44, blue: 0.18)
    static let warningAmber = Color(red: 0.95, green: 0.63, blue: 0.20)
    static let moss = Color(red: 0.16, green: 0.25, blue: 0.14)
    static let deepMoss = Color(red: 0.04, green: 0.10, blue: 0.07)
    static let iron = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let parchment = Color(red: 0.84, green: 0.75, blue: 0.57)
    static let parchmentShadow = Color(red: 0.46, green: 0.34, blue: 0.20)
    static let oxblood = Color(red: 0.39, green: 0.08, blue: 0.06)
    static let leather = Color(red: 0.23, green: 0.13, blue: 0.08)
    static let carvedWood = Color(red: 0.30, green: 0.17, blue: 0.09)
    static let emerald = Color(red: 0.18, green: 0.56, blue: 0.34)
    static let arcaneBlue = Color(red: 0.22, green: 0.57, blue: 0.78)
    static let legalEmerald = emerald
    static let priorityArcane = arcaneBlue
    static let panelParchment = Color(red: 0.70, green: 0.57, blue: 0.36)
    static let borderBronze = Color(red: 0.58, green: 0.39, blue: 0.15)
    static let borderIron = Color(red: 0.20, green: 0.18, blue: 0.15)
    static let laneWood = Color(red: 0.22, green: 0.13, blue: 0.07)
}

struct BattlefieldSurface: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("mage-mobile-board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .black.opacity(0.34),
                                .black.opacity(0.05),
                                .black.opacity(0.08),
                                .black.opacity(0.38)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RadialGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.22),
                        .black.opacity(0.52)
                    ],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.20,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.62
                )
            }
        }
    }
}

struct MenuBackgroundSurface: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("mage-mobile-menu-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .black.opacity(0.46),
                                .black.opacity(0.20),
                                .black.opacity(0.52)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RadialGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.30,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.70
                )
            }
        }
    }
}

struct AIWaitFallbackControls: View {
    let snapshot: GameSnapshot
    let beganAt: Date
    let refreshAction: () -> Void
    let reconnectAction: () -> Void

    var body: some View {
        TimelineView(.periodic(from: beganAt, by: 1)) { context in
            VStack(spacing: 7) {
                Text(snapshot.isStalled ? "XMAGE STALLED" : "AI THINKING")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(snapshot.isStalled ? MagicPalette.warningAmber : MagicPalette.arcaneBlue)
                Text("\(Int(context.date.timeIntervalSince(beganAt)))s")
                    .font(.system(size: 18, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Button("REFRESH", action: refreshAction)
                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                Button("RECONNECT", action: reconnectAction)
                    .buttonStyle(CompactActionButtonStyle(isPrimary: false))
            }
            .padding(8)
            .background(MagicPalette.iron.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke((snapshot.isStalled ? MagicPalette.warningAmber : MagicPalette.arcaneBlue).opacity(0.46), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
    }
}

struct RightDockBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [
                        MagicPalette.iron.opacity(0.58),
                        MagicPalette.leather.opacity(0.46),
                        MagicPalette.carvedWood.opacity(0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [
                                MagicPalette.borderBronze.opacity(0.62),
                                MagicPalette.borderIron.opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(MagicPalette.antiqueGold.opacity(0.18))
                    .frame(width: 1)
                    .padding(.vertical, 8)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, x: -6, y: 8)
    }
}

struct EdgeCanopy: View {
    let height: CGFloat
    let flipped: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MagicPalette.deepMoss.opacity(0.92),
                    MagicPalette.carvedWood.opacity(0.50),
                    .clear
                ],
                startPoint: flipped ? .bottom : .top,
                endPoint: flipped ? .top : .bottom
            )
            HStack(spacing: 18) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule()
                        .fill((index.isMultiple(of: 2) ? MagicPalette.moss : MagicPalette.carvedWood).opacity(0.22))
                        .frame(width: CGFloat(18 + (index % 3) * 8), height: height * CGFloat(0.52 + Double(index % 4) * 0.08))
                        .rotationEffect(.degrees(Double(index * 9 - 30)))
                        .blur(radius: 1.2)
                }
            }
            .offset(y: flipped ? -height * 0.22 : height * 0.22)
        }
        .frame(height: height)
        .scaleEffect(y: flipped ? -1 : 1)
        .allowsHitTesting(false)
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

struct FloatingZoneChip: View {
    let title: String
    let count: Int
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text("\(title) (\(count))")
                    .font(.system(size: 10, weight: .black))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MagicPalette.iron.opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.5), lineWidth: 1.5))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct HudMiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 5.8, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold.opacity(0.85))
            Text(value)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: 34, height: 22)
        .background(MagicPalette.iron.opacity(0.42), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MagicPalette.borderBronze.opacity(0.4), lineWidth: 0.8))
    }
}

struct InteractiveHudMiniStat: View {
    let label: String
    let value: String
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                VStack(spacing: 0) {
                    Text(label)
                        .font(.system(size: 5.8, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold.opacity(0.85))
                    Text(value)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 22)
                .background(MagicPalette.arcaneBlue.opacity(0.34), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(MagicPalette.antiqueGold.opacity(0.4), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        } else {
            HudMiniStat(label: label, value: value)
        }
    }
}

struct CommanderHudSummary: Equatable {
    let life: Int
    let commanderTax: Int
    let handCount: Int
    let libraryCount: Int
    let graveyardCount: Int
    let exileCount: Int
    let commanderDamage: Int

    init(player: PlayerGameState, opponentId: String?) {
        life = player.life
        commanderTax = player.commanderTax
        handCount = player.zones.hand.count
        libraryCount = player.zones.library.count
        graveyardCount = player.zones.graveyard.count
        exileCount = player.zones.exile.count
        commanderDamage = opponentId.flatMap { player.commanderDamage?[$0] } ?? 0
    }
}

struct PlayerVerticalHUD: View {
    let name: String
    let player: PlayerGameState
    var active = false
    var opponentId: String?
    let viewZone: (String, [ZoneCard]) -> Void

    private var summary: CommanderHudSummary {
        CommanderHudSummary(player: player, opponentId: opponentId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 5) {
                Text("YOU")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .frame(width: 26, height: 34)
                    .background(MagicPalette.arcaneBlue.opacity(0.82), in: Capsule())
                    .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(active ? 0.82 : 0.48), lineWidth: 1.2))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 9, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(summary.life)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                }
            }

            LazyVGrid(columns: [GridItem(.fixed(34)), GridItem(.fixed(34))], spacing: 3) {
                InteractiveHudMiniStat(label: "CMD", value: "\(summary.commanderTax)") {
                    viewZone("Command", player.zones.command)
                }
                HudMiniStat(label: "Hand", value: "\(summary.handCount)")
                HudMiniStat(label: "Lib", value: "\(summary.libraryCount)")
                InteractiveHudMiniStat(label: "GY", value: "\(summary.graveyardCount)") {
                    viewZone("Graveyard", player.zones.graveyard)
                }
                InteractiveHudMiniStat(label: "Ex", value: "\(summary.exileCount)") {
                    viewZone("Exile", player.zones.exile)
                }
                HudMiniStat(label: "Dmg", value: "\(summary.commanderDamage)")
            }
        }
        .padding(6)
        .frame(width: 84, alignment: .leading)
        .background(MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(MagicPalette.antiqueGold.opacity(active ? 0.68 : 0.30), lineWidth: active ? 1.4 : 1))
        .shadow(color: active ? MagicPalette.antiqueGold.opacity(0.18) : .black.opacity(0.20), radius: 10, y: 5)
    }
}

struct OpponentVerticalHUD: View {
    let name: String
    let player: PlayerGameState
    var active = false
    var opponentId: String?

    private var summary: CommanderHudSummary {
        CommanderHudSummary(player: player, opponentId: opponentId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 5) {
                PlayerAvatar(data: nil, size: 26, active: active)
                    .frame(width: 26, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 9, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(summary.life)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                }
            }

            LazyVGrid(columns: [GridItem(.fixed(34)), GridItem(.fixed(34))], spacing: 3) {
                HudMiniStat(label: "CMD", value: "\(summary.commanderTax)")
                HudMiniStat(label: "Hand", value: "\(summary.handCount)")
                HudMiniStat(label: "Lib", value: "\(summary.libraryCount)")
                HudMiniStat(label: "GY", value: "\(summary.graveyardCount)")
                HudMiniStat(label: "Ex", value: "\(summary.exileCount)")
                HudMiniStat(label: "Dmg", value: "\(summary.commanderDamage)")
            }
        }
        .padding(6)
        .frame(width: 84, alignment: .leading)
        .background(MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(MagicPalette.antiqueGold.opacity(active ? 0.68 : 0.30), lineWidth: active ? 1.4 : 1))
        .shadow(color: active ? MagicPalette.antiqueGold.opacity(0.18) : .black.opacity(0.20), radius: 10, y: 5)
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
        .background(MagicPalette.iron.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(MagicPalette.antiqueGold.opacity(0.38)))
    }
}

struct TurnStatusBadge: View {
    let snapshot: GameSnapshot
    let human: PlayerGameState
    let opponent: PlayerGameState

    private var isHumanTurn: Bool {
        snapshot.activePlayerId == human.playerId || snapshot.activePlayerId == "human"
    }

    private var priorityText: String {
        if let priority = snapshot.priorityPlayerId {
            return priority == "human" ? "YOU" : "AI"
        }
        return "None"
    }

    private var phaseText: String {
        let phase = (snapshot.step ?? snapshot.phase).arenaPhaseTitle
        return phase
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("T\(snapshot.turn)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            Divider()
                .frame(height: 16)
                .background(.white.opacity(0.2))

            Text(phaseText.uppercased())
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Divider()
                .frame(height: 16)
                .background(.white.opacity(0.2))

            Text(priorityText)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(snapshot.priorityPlayerId == "human" ? MagicPalette.legalEmerald : (snapshot.priorityPlayerId != nil ? MagicPalette.warningAmber : .white.opacity(0.4)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.64), in: Capsule())
        .overlay(Capsule().stroke(isHumanTurn ? MagicPalette.antiqueGold.opacity(0.55) : MagicPalette.oxblood.opacity(0.55), lineWidth: 1.5))
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
                .fill(isLive ? MagicPalette.legalEmerald : MagicPalette.antiqueGold)
                .frame(width: 7, height: 7)
                .shadow(color: (isLive ? MagicPalette.legalEmerald : MagicPalette.antiqueGold).opacity(0.75), radius: 5)
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
        .overlay(Capsule().stroke((isLive ? MagicPalette.legalEmerald : MagicPalette.antiqueGold).opacity(0.36), lineWidth: 1))
    }
}

struct GameDiagnosticsBadge: View {
    let snapshot: GameSnapshot
    let liveUpdateStatus: String

    private var source: String {
        snapshot.source ?? (snapshot.xmage == nil ? "xmage" : "xmage-java-bridge")
    }

    private var phaseStep: String {
        let phase = (snapshot.step ?? snapshot.phase).arenaPhaseTitle
        return "T\(snapshot.turn) \(phase)"
    }

    private var waitState: String {
        if snapshot.pendingStatus == "stalled" || snapshot.engineHealth?.status == "stalled" {
            return "XMage stalled"
        }
        if snapshot.pendingStatus == "waiting_for_xmage" {
            return "Waiting for XMage"
        }
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty {
            return "Your priority"
        }
        if snapshot.priorityPlayerId != nil || snapshot.waitingOnPlayerId != nil {
            return "AI thinking"
        }
        return "Waiting for XMage"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(waitState == "Your priority" ? MagicPalette.legalEmerald : (waitState.contains("stalled") ? MagicPalette.warningAmber : MagicPalette.priorityArcane))
                    .frame(width: 7, height: 7)
                    .shadow(color: MagicPalette.priorityArcane.opacity(0.45), radius: 5)
                Text(waitState.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(waitState == "Your priority" ? MagicPalette.legalEmerald : (waitState.contains("stalled") ? MagicPalette.warningAmber : MagicPalette.priorityArcane))
                Spacer(minLength: 4)
                Text("REV \(snapshot.bridgeRevision.map(String.init) ?? "n/a")")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.72))
            }

            HStack(spacing: 5) {
                DiagnosticsChip(title: "SRC", value: source)
                DiagnosticsChip(title: "CYCLE", value: snapshot.xmageCycle.map(String.init) ?? "n/a")
                DiagnosticsChip(title: "WS", value: liveUpdateStatus)
            }

            Text("\(snapshot.engineHealth?.status ?? "bridge") · \(snapshot.pendingStatus ?? "none") · \(phaseStep)")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MagicPalette.iron.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.38), lineWidth: 1))
    }
}

struct DiagnosticsChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 5.5, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold.opacity(0.74))
            Text(value)
                .font(.system(size: 6.5, weight: .black))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.48)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
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
    var vertical = false

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
        Group {
            if vertical {
                VStack(spacing: 5) {
                    manaContent
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 9)
            } else {
                HStack(spacing: 5) {
                    manaContent
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
        }
        .background(MagicPalette.iron.opacity(0.76), in: RoundedRectangle(cornerRadius: vertical ? 12 : 16))
        .overlay(RoundedRectangle(cornerRadius: vertical ? 12 : 16).stroke(MagicPalette.antiqueGold.opacity(0.38), lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
    }

    @ViewBuilder
    private var manaContent: some View {
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
        } else if let assetName = CardImageURL.bundledSymbolAssetName(for: symbol),
                  let image = UIImage(named: assetName) {
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
        VStack(alignment: .leading, spacing: 5) {
            Text("STACK")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)

            HStack(spacing: 8) {
                HStack(spacing: -14) {
                    ForEach(Array(cards.suffix(4).enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: "Stack", width: 38, height: 54)
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
        }
        .padding(8)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.24)))
    }
}

struct XmageStackPeek: View {
    let objects: [XmageStackObject]
    let legalActions: [LegalAction]
    let promptText: String?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    private var topObject: XmageStackObject? {
        objects.last
    }

    private var passAvailable: Bool {
        legalActions.contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STACK")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)

            HStack(spacing: 8) {
                HStack(spacing: -12) {
                    ForEach(Array(objects.suffix(3).enumerated()), id: \.element.id) { index, object in
                        if let card = object.displaySourceCard {
                            CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: "Stack", width: 38, height: 54)
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
                    HStack(spacing: 5) {
                        Text("TOP \(objects.count)")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(MagicPalette.antiqueGold)
                        Text(passAvailable ? "RESPOND/PASS" : "WAIT")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(passAvailable ? .green : .white.opacity(0.62))
                    }
                    Text(topObject?.displayName ?? "Resolving")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if let source = topObject?.displaySourceCard?.card.name, source != topObject?.name {
                        Text("Source: \(source)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    } else if let source = topObject?.sourceName, !source.isEmpty, source != topObject?.name {
                        Text("Source: \(source)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    } else if let detail = topObject?.compactFallbackDetail {
                        Text(detail)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MagicPalette.antiqueGold.opacity(0.82))
                            .lineLimit(2)
                            .minimumScaleFactor(0.58)
                    }
                    if let metadata = topObject?.displayMetadata {
                        Text(metadata)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                    if let text = topObject?.rulesText, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                    }
                    if let promptText, !promptText.isEmpty {
                        Text("Prompt: \(promptText)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MagicPalette.antiqueGold.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    } else if let paid = topObject?.paid {
                        Text(paid ? "Paid" : "Pending payment")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(paid ? MagicPalette.parchment.opacity(0.7) : MagicPalette.antiqueGold)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(MagicPalette.iron.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30)))
    }
}

struct PromptPill: View {
    let snapshot: GameSnapshot

    private var isWaitingOnHuman: Bool {
        snapshot.waitingOnPlayerId == "human"
            || (snapshot.waitingOnPlayerId == nil && snapshot.priorityPlayerId == "human")
            || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isWaitingOnHuman ? MagicPalette.emerald : MagicPalette.arcaneBlue)
                .frame(width: 8, height: 8)
                .shadow(color: (isWaitingOnHuman ? MagicPalette.emerald : MagicPalette.arcaneBlue).opacity(0.8), radius: 5)

            Text(isWaitingOnHuman ? "YOUR DECISION" : "AI DECISION")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(isWaitingOnHuman ? MagicPalette.emerald : MagicPalette.arcaneBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isWaitingOnHuman ? MagicPalette.emerald : MagicPalette.arcaneBlue).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Text(snapshot.promptText ?? "Waiting for XMage")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(MagicPalette.iron.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isWaitingOnHuman ? MagicPalette.emerald.opacity(0.5) : MagicPalette.arcaneBlue.opacity(0.26), lineWidth: 1.5))
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
    @State private var orderPromptId: String?
    @State private var orderedIds: [String] = []
    @State private var multiAmountPromptId: String?
    @State private var multiAmountValues: [String: Int] = [:]
    @State private var manualAmountValues: [String: Int] = [:]
    @State private var selectedSearchPromptId: String?
    @State private var selectedSearchCardIds: [String] = []
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let viewZone: (String, [ZoneCard]) -> Void
    var showsGameSurfaceSections = true

    private var passActions: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["pass_priority", "pass_until_response", "pass_until_next_turn", "advance_phase"].contains($0.type)
        }
    }

    private var spellsAndLands: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["play_land", "cast_spell"].contains($0.type)
        }
    }

    private var abilitiesAndMana: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["activate_ability", "make_mana", "play_mana", "choose_mana", "choose_ability"].contains($0.type)
        }
    }

    private var sourceManaActions: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil)
        }
    }

    private var otherActions: [LegalAction] {
        let types = ["pass_priority", "pass_until_response", "pass_until_next_turn", "advance_phase",
                     "play_land", "cast_spell",
                     "activate_ability", "make_mana", "play_mana", "choose_mana", "choose_ability"]
        return (snapshot.legalActions ?? []).filter {
            !types.contains($0.type)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                VStack(alignment: .leading, spacing: 8) {
                    if let prompt = snapshot.promptEnvelopeV2 {
                        promptEnvelopeV2Section(prompt)
                    } else if let prompt = snapshot.promptEnvelope {
                        promptEnvelopeSection(prompt)
                    }

                    if let prompt = snapshot.choicePrompt {
                        choicePromptSection(prompt)
                    }

                    if showsGameSurfaceSections {
                        if !selectedCardActions.isEmpty, let selectedCard {
                            actionSection(
                                title: "Selected",
                                detail: selectedCard.card.name,
                                actions: selectedCardActions
                            )
                        } else if let selectedCard, selectedCardIsInHumanHand(selectedCard) {
                            selectedCardUnavailableSection(selectedCard)
                        }

                        if !spellsAndLands.isEmpty {
                            actionSection(title: "Spells & Lands", detail: "\(spellsAndLands.count)", actions: spellsAndLands)
                        }
                        if !abilitiesAndMana.isEmpty {
                            actionSection(title: "Abilities & Mana", detail: "\(abilitiesAndMana.count)", actions: abilitiesAndMana)
                        }
                        if !passActions.isEmpty {
                            actionSection(title: "Pass / Steps", detail: "\(passActions.count)", actions: passActions, compact: !spellsAndLands.isEmpty || !abilitiesAndMana.isEmpty || !selectedCardActions.isEmpty)
                        }
                        if !otherActions.isEmpty {
                            actionSection(title: "Other Actions", detail: "\(otherActions.count)", actions: otherActions)
                        }

                        MobileSurfacesPanel(
                            snapshot: snapshot,
                            selectedCard: $selectedCard,
                            inspectedCard: $inspectedCard,
                            viewZone: viewZone
                        )
                    }
                }
                .padding(.vertical, 1)
                .padding(.bottom, 10)
            }
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.80), MagicPalette.laneWood.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.46), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 8, x: -3, y: 4)
    }

    private var priorityLabel: String {
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" {
            return "YOUR PRIORITY"
        }
        return snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId ?? "WAITING"
    }

    @ViewBuilder
    private func promptEnvelopeV2Section(_ prompt: PromptEnvelopeV2) -> some View {
        PromptPanelSection(title: prompt.method.replacingOccurrences(of: "GAME_", with: ""), detail: prompt.responseCommand?.type ?? prompt.responseKind, isHighlighted: true) {
            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.68)

            if isManaOrPaymentPrompt(prompt), !sourceManaActions.isEmpty {
                sourceManaActionSection(prompt)
            }

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
                if isSearchPrompt(prompt) {
                    searchSelectionPicker(cards: cards, prompt: prompt)
                } else {
                    cardPicker(cards: cards, prompt: prompt)
                }
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
            } else if let multiAmounts = prompt.multiAmounts, !multiAmounts.isEmpty {
                multiAmountPicker(slots: multiAmounts, prompt: prompt)
            } else if isAmountPrompt(prompt) {
                manualAmountPicker(prompt: prompt)
            }

            if let orderedItems = prompt.orderedItems, !orderedItems.isEmpty {
                orderPicker(
                    title: "Order",
                    prompt: prompt,
                    type: "order_items",
                    options: orderedItems.map { ($0.id, $0.label) }
                )
            }

            if let manaChoices = prompt.manaChoices, !manaChoices.isEmpty {
                manaChoicePicker(choices: manaChoices, prompt: prompt)
            }

            if prompt.manaChoices?.isEmpty != false && isChooseColorPrompt(prompt) {
                colorChoicePicker(prompt: prompt)
            } else if prompt.manaChoices?.isEmpty != false && isManaPrompt(prompt) && !availableManaSymbols.isEmpty {
                manaPicker(prompt: prompt)
            }

            if isTriggerOrderPrompt(prompt) {
                orderPicker(
                    title: "Trigger order",
                    prompt: prompt,
                    type: "order_triggers",
                    options: orderOptions(for: prompt)
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
            } else if isCardSelectionPrompt(prompt), prompt.cards?.isEmpty != false, prompt.targets?.isEmpty != false {
                placeholderSubmit(
                    title: "Select card on battlefield",
                    button: "Submit selected card",
                    prompt: prompt,
                    type: prompt.responseCommand?.type ?? "choose_card",
                    ids: selectedCard.map { [$0.id] } ?? prompt.targetIds ?? []
                )
            }

            if isPlayerSelectionPrompt(prompt), prompt.players?.isEmpty != false {
                optionGrid(snapshot.players.map { ($0.playerId, $0.playerId == "human" ? "You" : "AI") }, prompt: prompt, fallbackType: prompt.responseCommand?.type ?? "choose_player", icon: "person.crop.circle")
            }

            if isDamageAssignmentPrompt(prompt), prompt.multiAmounts?.isEmpty != false {
                unsupportedDamageAssignment(prompt)
            }

            if !hasRenderablePromptControls(prompt) {
                Text("Unsupported prompt/action: XMage has not exposed a mobile-safe control for this route yet.")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.warningAmber.opacity(0.90))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    @ViewBuilder
    private func promptEnvelopeSection(_ prompt: PromptEnvelope) -> some View {
        PromptPanelSection(title: prompt.method.replacingOccurrences(of: "GAME_", with: ""), detail: prompt.responseKind, isHighlighted: true) {
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

            if prompt.choices?.isEmpty != false && prompt.targetIds?.isEmpty != false {
                unsupportedPromptFallback(method: prompt.method, responseKind: prompt.responseKind)
            }
        }
    }

    @ViewBuilder
    private func choicePromptSection(_ prompt: ChoicePrompt) -> some View {
        PromptPanelSection(title: "Choice", detail: "\(prompt.minChoices)-\(prompt.maxChoices)", isHighlighted: true) {
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
    private func actionSection(title: String, detail: String, actions: [LegalAction], compact: Bool = false) -> some View {
        PromptPanelSection(title: title, detail: detail) {
            if actions.isEmpty {
                Text("No exposed actions")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 72 : 98), spacing: 6)], spacing: 6) {
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
                        .buttonStyle(PanelActionButtonStyle(isDanger: action.type == "concede", isPrimary: action.isPrimary == true || isCastOrPlay(action), compact: compact))
                        .disabled(pendingActionId != nil || !directlyRunnable)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectedCardUnavailableSection(_ card: ZoneCard) -> some View {
        PromptPanelSection(title: "Selected", detail: card.card.name) {
            Text(selectedCardBlockedReason(card))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(3)
                .minimumScaleFactor(0.72)
            Button {
                inspectedCard = card
            } label: {
                PromptButtonLabel(title: "Inspect", subtitle: "Long press cards also opens this", systemImage: "doc.text.magnifyingglass", isPending: false)
            }
            .buttonStyle(PanelActionButtonStyle())
            .disabled(pendingActionId != nil)
        }
    }

    @ViewBuilder
    private func sourceManaActionSection(_ prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel(prompt.responseCommand?.type?.lowercased() == "pay_cost" ? "Pay with sources" : "Available mana sources")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
            ForEach(sourceManaActions) { action in
                Button {
                    runAction(action)
                } label: {
                    PromptButtonLabel(
                        title: "Tap \(sourceCardName(for: action))",
                        subtitle: producedManaLabel(for: action),
                        systemImage: "sparkles",
                        isPending: pendingActionId == action.id
                    )
                }
                .buttonStyle(PanelActionButtonStyle(isPrimary: true))
                .disabled(pendingActionId != nil)
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
        let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: isSearchPrompt(prompt) ? "search_select" : "choose_card")
        let selectedPromptCardId = PromptSelectionRules.selectedPromptCardId(selectedCard: selectedCard, validCards: cards)
        let hasValidSelection = selectedPromptCardId != nil && PromptSelectionRules.isValidSelectedCount(1, minChoices: prompt.minChoices ?? 1, maxChoices: prompt.maxChoices ?? 1)
        PromptMiniLabel("Cards")
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(cards) { card in
                        VStack(spacing: 4) {
                            CardTile(card: card, selected: selectedCard?.id == card.id || selectedCard?.instanceId == card.instanceId, legal: true, zoneName: "Prompt", width: 42, height: 59)
                                .onTapGesture {
                                    selectedCard = card
                                    inspectedCard = nil
                                }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    inspectedCard = card
                                }
                            Text(card.card.name)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.white.opacity(0.74))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: 70)
                        }
                    }
                }
            }
            promptButton(
                label: "Done",
                subtitle: selectedPromptCardId == nil ? "Select a card first" : selectedCard?.card.name,
                systemImage: "checkmark.circle",
                pendingId: "\(prompt.id)-choose-card",
                command: hasValidSelection && selectedPromptCardId != nil
                    ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [selectedPromptCardId!])
                    : nil
            )
        }
    }

    @ViewBuilder
    private func searchSelectionPicker(cards: [ZoneCard], prompt: PromptEnvelopeV2) -> some View {
        let selectedIds = currentSearchSelection(promptId: prompt.id, validIds: cards.map(\.instanceId))
        let selectedCount = selectedIds.count
        let valid = PromptSelectionRules.isValidSelectedCount(selectedCount, minChoices: prompt.minChoices, maxChoices: prompt.maxChoices)
        let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: "search_select")

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                PromptMiniLabel(searchZoneName(for: prompt))
                Spacer(minLength: 4)
                Text("\(selectedCount) selected · \(PromptSelectionRules.boundsText(minChoices: prompt.minChoices, maxChoices: prompt.maxChoices))")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(valid ? MagicPalette.legalEmerald.opacity(0.86) : MagicPalette.warningAmber.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(cards) { card in
                    let isSelected = selectedIds.contains(card.instanceId)
                    Button {
                        toggleSearchSelection(promptId: prompt.id, cardId: card.instanceId, validIds: cards.map(\.instanceId), maxChoices: prompt.maxChoices)
                    } label: {
                        HStack(spacing: 7) {
                            CardTile(card: card, selected: isSelected, legal: true, zoneName: searchZoneName(for: prompt), width: 30, height: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.card.name)
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white.opacity(0.90))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.66)
                                Text(card.card.typeLine)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(isSelected ? MagicPalette.legalEmerald : .white.opacity(0.34))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(isSelected ? MagicPalette.legalEmerald.opacity(0.12) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? MagicPalette.legalEmerald.opacity(0.34) : .white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(pendingActionId != nil)
                }
            }

            promptButton(
                label: "Submit selection",
                subtitle: valid ? "\(selectedCount) cards from \(searchZoneName(for: prompt))" : "Select \(PromptSelectionRules.boundsText(minChoices: prompt.minChoices, maxChoices: prompt.maxChoices))",
                systemImage: "checkmark.circle",
                pendingId: "\(prompt.id)-search-select",
                command: valid ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: selectedIds) : nil
            )
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
                    command: command(type: "choose_pile", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, pile: pile.explicitPileNumber)
                )
            }
        }
    }

    @ViewBuilder
    private func amountPicker(amounts: [Int], prompt: PromptEnvelopeV2) -> some View {
        let type = amountCommandType(preferred: prompt.responseCommand?.type)
        if type == "choose_multi_amount" {
            if let slots = prompt.multiAmounts, !slots.isEmpty {
                multiAmountPicker(slots: slots, prompt: prompt)
            } else {
                PromptMiniLabel("Multi Amount")
                Text("Unsupported prompt/action: XMage did not expose slot metadata for this multi-amount prompt.")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.warningAmber.opacity(0.90))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        } else {
            PromptMiniLabel("Amount")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                ForEach(amounts, id: \.self) { amount in
                    promptButton(
                        label: "\(amount)",
                        systemImage: "number",
                        pendingId: "\(prompt.id)-amount-\(amount)",
                        command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amount: amount, amounts: [amount])
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func multiAmountPicker(slots: [XmagePromptMultiAmount], prompt: PromptEnvelopeV2) -> some View {
        let values = multiAmountArray(for: slots, promptId: prompt.id)
        let total = values.reduce(0, +)
        let valid = PromptCommandBuilder.isValidMultiAmountValues(values, slots: slots, totalMin: prompt.totalMin, totalMax: prompt.totalMax)
        let isDamageAllocation = isDamageAssignmentPrompt(prompt)

        PromptMiniLabel(isDamageAllocation ? "Damage Assignment" : "Multi Amount")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let value = values[index]
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.label)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(slot.min)-\(slot.max)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer(minLength: 4)
                    Button {
                        adjustMultiAmount(promptId: prompt.id, slots: slots, slot: slot, delta: -1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18, weight: .black))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(value <= slot.min ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || value <= slot.min)

                    Text("\(value)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28)

                    Button {
                        adjustMultiAmount(promptId: prompt.id, slots: slots, slot: slot, delta: 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .black))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(value >= slot.max ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || value >= slot.max)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            }

            promptButton(
                label: isDamageAllocation ? "Assign damage" : "Submit amounts",
                subtitle: multiAmountSummary(total: total, prompt: prompt, valid: valid),
                systemImage: "number",
                pendingId: "\(prompt.id)-choose-multi-amount",
                command: valid ? command(type: "choose_multi_amount", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amounts: values) : nil
            )
        }
    }

    @ViewBuilder
    private func manaPicker(prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Mana")
        HStack(spacing: 6) {
            ForEach(availableManaSymbols, id: \.self) { mana in
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
    private func colorChoicePicker(prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Choose Color")
        HStack(spacing: 6) {
            ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { mana in
                Button {
                    if let command = command(type: prompt.responseCommand?.type ?? "choose_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, manaType: mana) {
                        runCommand(command, mana, "\(prompt.id)-choose-color-\(mana)")
                    }
                } label: {
                    ManaSymbolView(symbol: mana, size: 26)
                        .overlay {
                            if pendingActionId == "\(prompt.id)-choose-color-\(mana)" {
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
    private func manualAmountPicker(prompt: PromptEnvelopeV2) -> some View {
        let type = amountCommandType(preferred: prompt.responseCommand?.type)
        let currentValue = manualAmountValues[prompt.id] ?? 0
        PromptMiniLabel(type == "play_x_mana" ? "X Amount" : "Amount")
        
        HStack(spacing: 7) {
            Button {
                manualAmountValues[prompt.id] = max(0, currentValue - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24, weight: .black))
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentValue <= 0 ? .white.opacity(0.24) : MagicPalette.parchment)
            .disabled(pendingActionId != nil || currentValue <= 0)

            Text("\(currentValue)")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 40)

            Button {
                manualAmountValues[prompt.id] = currentValue + 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .black))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MagicPalette.parchment)
            .disabled(pendingActionId != nil)

            Spacer()

            promptButton(
                label: "Submit \(currentValue)",
                systemImage: "number",
                pendingId: "\(prompt.id)-amount-\(currentValue)",
                command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amount: currentValue, amounts: [currentValue])
            )
        }
    }
    @ViewBuilder
    private func confirmationPicker(confirmation: XmagePromptConfirmation, prompt: PromptEnvelopeV2) -> some View {
        let yesCommand = explicitConfirmationCommand(confirmation.yesCommand, prompt: prompt)
        let noCommand = explicitConfirmationCommand(confirmation.noCommand, prompt: prompt)
        HStack(spacing: 6) {
            promptButton(
                label: confirmation.yesLabel ?? "Yes",
                systemImage: "checkmark.circle",
                pendingId: "\(prompt.id)-yes",
                command: yesCommand
            )
            promptButton(
                label: confirmation.noLabel ?? "No",
                systemImage: "xmark.circle",
                pendingId: "\(prompt.id)-no",
                command: noCommand
            )
        }
        if yesCommand == nil || noCommand == nil {
            Text("XMage did not expose explicit yes/no command metadata for every option, so missing choices stay disabled.")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MagicPalette.warningAmber.opacity(0.82))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
    }

    private func explicitConfirmationCommand(_ confirmationCommand: XmageResponseCommand?, prompt: PromptEnvelopeV2) -> GameCommand? {
        guard let confirmationCommand,
              let type = confirmationCommand.type,
              let promptId = confirmationCommand.promptId,
              let confirmed = confirmationCommand.confirmed ?? confirmationCommand.pay
        else {
            return nil
        }
        return command(
            type: type,
            promptId: promptId,
            playerId: prompt.playerId,
            ids: [confirmed ? "true" : "false"],
            pay: confirmationCommand.pay ?? confirmed
        )
    }

    private func unsupportedPromptFallback(method: String, responseKind: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Unsupported prompt/action")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.warningAmber)
            Text("No default answer will be sent. Refresh or reconnect after the bridge exposes a mobile-safe response.")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text("\(method) | \(responseKind)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(MagicPalette.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.warningAmber.opacity(0.24)))
    }

    @ViewBuilder
    private func placeholderSubmit(title: String, button: String, prompt: PromptEnvelopeV2, type: String, ids: [String]) -> some View {
        let canSubmit = isOrderCommand(type) ? PromptCommandBuilder.canSubmitShownOrder(ids: ids) : !ids.isEmpty
        PromptMiniLabel(title)
        promptButton(
            label: button,
            subtitle: placeholderSubmitSubtitle(type: type, ids: ids),
            systemImage: type == "order_triggers" ? "arrow.up.arrow.down" : "magnifyingglass",
            pendingId: "\(prompt.id)-\(type)",
            command: canSubmit ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: ids) : nil
        )
    }

    @ViewBuilder
    private func unsupportedDamageAssignment(_ prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Damage Assignment")
        VStack(alignment: .leading, spacing: 5) {
            Text("Unsupported prompt/action: damage assignment is not mobile-safe yet.")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text("No default damage split will be submitted. Refresh or reconnect after the bridge exposes attacker/blocker allocation choices.")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text("\(prompt.method) | \(prompt.responseKind)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.22)))
    }

    @ViewBuilder
    private func orderPicker(title: String, prompt: PromptEnvelopeV2, type: String, options: [(String, String)]) -> some View {
        let defaultIds = options.map(\.0)
        let currentIds = currentOrder(promptId: prompt.id, defaultIds: defaultIds)
        let labelById = Dictionary(uniqueKeysWithValues: options)
        let canSubmit = !currentIds.isEmpty && Set(currentIds) == Set(defaultIds) && currentIds.count == defaultIds.count

        PromptMiniLabel(title)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(currentIds.enumerated()), id: \.element) { index, id in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .frame(width: 18, height: 24)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    Text(labelById[id] ?? id)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    Button {
                        moveOrder(promptId: prompt.id, defaultIds: defaultIds, from: index, delta: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == 0 ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || index == 0)

                    Button {
                        moveOrder(promptId: prompt.id, defaultIds: defaultIds, from: index, delta: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == currentIds.count - 1 ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || index == currentIds.count - 1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            }

            promptButton(
                label: "Submit order",
                subtitle: canSubmit ? "\(currentIds.count) items" : "Order incomplete",
                systemImage: "arrow.up.arrow.down",
                pendingId: "\(prompt.id)-\(type)-ordered",
                command: canSubmit ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: currentIds) : nil
            )
        }
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
        let actions = snapshot.legalActions ?? []
        let choiceId = choice.id
        let suffixTarget = "-\(choiceId)"
        let composedId = "\(promptId)-\(choiceId)"
        return actions.first { action in
            if action.id == choiceId { return true }
            if action.id == composedId { return true }
            if action.targetIds?.contains(choiceId) == true { return true }
            if action.validTargetIds?.contains(choiceId) == true { return true }
            if action.id.hasSuffix(suffixTarget) { return true }
            return false
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
        manaType: String? = nil,
        pay: Bool? = nil
    ) -> GameCommand? {
        UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: snapshot.promptEnvelopeV2,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            amount: amount,
            amounts: amounts,
            pile: pile,
            useCommandZone: useCommandZone,
            manaType: manaType,
            pay: pay
        )
    }

    private func idCommandType(preferred: String?, fallback: String) -> String {
        PromptCommandBuilder.idCommandType(preferred: preferred, fallback: fallback)
    }

    private func amountCommandType(preferred: String?) -> String {
        PromptCommandBuilder.amountCommandType(preferred: preferred)
    }

    private func playerPromptLabel(_ player: XmagePromptPlayer) -> String {
        if let life = player.life {
            return "\(player.label) (\(life))"
        }
        return player.label
    }

    private func isManaPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "play_mana" || type == "choose_mana" || type == "mana" || type == "pay_cost" || type == "cost"
    }

    private func isManaOrPaymentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        return isManaPrompt(prompt)
            || ["pay_cost", "choose_mana", "play_x_mana"].contains(type)
            || ["pay_cost", "cost", "mana", "x_mana"].contains(kind)
            || prompt.message.localizedCaseInsensitiveContains("pay")
            || prompt.message.localizedCaseInsensitiveContains("mana")
    }

    private func isConfirmationPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        if prompt.confirmation != nil { return true }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "answer_yes_no" || type == "confirmation" || type == "pay_cost"
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

    private func isCardSelectionPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_card" || type == "card" || type == "choose_target" || type == "target"
    }

    private func isPlayerSelectionPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_player" || type == "player"
    }

    private func isChooseColorPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_mana" || type == "choose_color"
    }

    private func isAmountPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "play_x_mana" || type == "choose_amount"
    }

    private func isDamageAssignmentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, phase: snapshot.phase, step: snapshot.step)
    }

    private func hasRenderablePromptControls(_ prompt: PromptEnvelopeV2) -> Bool {
        if isManaOrPaymentPrompt(prompt) { return true }
        if isDamageAssignmentPrompt(prompt) { return true }
        if isCommanderReplacement(prompt) || isConfirmationPrompt(prompt) || isManaPrompt(prompt) || isTriggerOrderPrompt(prompt) || isSearchPrompt(prompt) { return true }
        if isCardSelectionPrompt(prompt) || isPlayerSelectionPrompt(prompt) || isChooseColorPrompt(prompt) || isAmountPrompt(prompt) { return true }
        if prompt.choices?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false { return true }
        if prompt.cards?.isEmpty == false || prompt.modes?.isEmpty == false || prompt.abilities?.isEmpty == false { return true }
        if prompt.piles?.isEmpty == false || prompt.amounts?.isEmpty == false || prompt.multiAmounts?.isEmpty == false || prompt.orderedItems?.isEmpty == false || prompt.manaChoices?.isEmpty == false { return true }
        if prompt.method == "GAME_SELECT" { return true }
        return false
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
        case "declare_attackers":
            return PromptCommandBuilder.hasPrebuiltCombatPayload(action)
        case "declare_blockers":
            return PromptCommandBuilder.hasPrebuiltCombatPayload(action)
        case "choose_multi_amount", "order_triggers", "order_items":
            return false
        default:
            return true
        }
    }

    private var availableManaSymbols: [String] {
        let pool = snapshot.human?.manaPool
        return ["W", "U", "B", "R", "G", "C"].filter { symbol in
            manaPoolValue(pool, symbol: symbol) > 0
        }
    }

    private func manaPoolValue(_ pool: ManaPool?, symbol: String) -> Int {
        switch symbol {
        case "W": return pool?.W ?? 0
        case "U": return pool?.U ?? 0
        case "B": return pool?.B ?? 0
        case "R": return pool?.R ?? 0
        case "G": return pool?.G ?? 0
        case "C": return pool?.C ?? 0
        default: return 0
        }
    }

    private func isOrderCommand(_ type: String) -> Bool {
        type == "order_triggers" || type == "order_items"
    }

    private func orderOptions(for prompt: PromptEnvelopeV2) -> [(String, String)] {
        if let cards = prompt.cards, !cards.isEmpty {
            return cards.map { ($0.id, $0.card.name) }
        }
        if let targets = prompt.targets, !targets.isEmpty {
            return targets.map { ($0.id, $0.label) }
        }
        if let choices = prompt.choices, !choices.isEmpty {
            return choices.map { ($0.id, $0.label) }
        }
        return []
    }

    private func currentSearchSelection(promptId: String, validIds: [String]) -> [String] {
        guard selectedSearchPromptId == promptId else { return [] }
        let validIdSet = Set(validIds)
        return selectedSearchCardIds.filter { validIdSet.contains($0) }
    }

    private func toggleSearchSelection(promptId: String, cardId: String, validIds: [String], maxChoices: Int?) {
        if selectedSearchPromptId != promptId {
            selectedSearchPromptId = promptId
            selectedSearchCardIds = []
        } else {
            let validIdSet = Set(validIds)
            selectedSearchCardIds = selectedSearchCardIds.filter { validIdSet.contains($0) }
        }

        if selectedSearchCardIds.contains(cardId) {
            selectedSearchCardIds.removeAll { $0 == cardId }
            return
        }

        if let maxChoices, selectedSearchCardIds.count >= maxChoices {
            return
        }
        selectedSearchCardIds.append(cardId)
    }

    private func searchZoneName(for prompt: PromptEnvelopeV2) -> String {
        if case .string(let zone)? = prompt.options?["zone"], !zone.isEmpty {
            return zone.capitalized
        }
        return "Library"
    }

    private func currentOrder(promptId: String, defaultIds: [String]) -> [String] {
        orderPromptId == promptId && !orderedIds.isEmpty ? orderedIds : defaultIds
    }

    private func moveOrder(promptId: String, defaultIds: [String], from index: Int, delta: Int) {
        if orderPromptId != promptId || orderedIds.isEmpty {
            orderPromptId = promptId
            orderedIds = defaultIds
        }
        orderedIds = PromptCommandBuilder.movedOrder(ids: orderedIds, from: index, to: index + delta)
    }

    private func multiAmountArray(for slots: [XmagePromptMultiAmount], promptId: String) -> [Int] {
        if multiAmountPromptId == promptId {
            return slots.map { multiAmountValues[$0.id] ?? PromptCommandBuilder.defaultMultiAmountValue(for: $0) }
        }
        return slots.map(PromptCommandBuilder.defaultMultiAmountValue)
    }

    private func adjustMultiAmount(promptId: String, slots: [XmagePromptMultiAmount], slot: XmagePromptMultiAmount, delta: Int) {
        if multiAmountPromptId != promptId {
            multiAmountPromptId = promptId
            multiAmountValues = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, PromptCommandBuilder.defaultMultiAmountValue(for: $0)) })
        }
        let current = multiAmountValues[slot.id] ?? PromptCommandBuilder.defaultMultiAmountValue(for: slot)
        multiAmountValues[slot.id] = PromptCommandBuilder.adjustedMultiAmountValue(current, delta: delta, slot: slot)
    }

    private func multiAmountSummary(total: Int, prompt: PromptEnvelopeV2, valid: Bool) -> String {
        var bounds: [String] = []
        if let totalMin = prompt.totalMin {
            bounds.append("min \(totalMin)")
        }
        if let totalMax = prompt.totalMax {
            bounds.append("max \(totalMax)")
        }
        let suffix = bounds.isEmpty ? "" : " · \(bounds.joined(separator: ", "))"
        return valid ? "total \(total)\(suffix)" : "invalid total \(total)\(suffix)"
    }

    private func placeholderSubmitSubtitle(type: String, ids: [String]) -> String {
        if ids.isEmpty {
            return "Waiting for exposed ids"
        }
        if isOrderCommand(type), !PromptCommandBuilder.canSubmitShownOrder(ids: ids) {
            return "No auto-order"
        }
        return "\(ids.count) ids"
    }

    private func singleCount(_ values: [String]?) -> Bool {
        values?.count == 1
    }

    private func isCastOrPlay(_ action: LegalAction) -> Bool {
        action.type == "cast_spell" || action.type == "play_land"
    }

    private func selectedCardIsInHumanHand(_ card: ZoneCard) -> Bool {
        snapshot.human?.zones.hand.contains { $0.instanceId == card.instanceId } == true
    }

    private func selectedCardBlockedReason(_ card: ZoneCard) -> String {
        if pendingActionId != nil {
            return "Action sent. Waiting for XMage to confirm the next game state."
        }
        if snapshot.waitingOnPlayerId != nil && snapshot.waitingOnPlayerId != "human" {
            return "Waiting on \(snapshot.waitingOnPlayerId ?? "another player"). XMage has not exposed a cast/play action for this card."
        }
        if snapshot.priorityPlayerId != nil && snapshot.priorityPlayerId != "human" {
            return "Not your priority. XMage will expose cast/play actions when this card is legal."
        }
        if snapshot.promptEnvelopeV2 != nil || snapshot.promptEnvelope != nil || snapshot.choicePrompt != nil {
            return "Answer the current XMage prompt first. This card remains inspectable, but XMage is not accepting a cast/play action for it right now."
        }
        return "XMage did not expose a cast/play action for \(card.card.name). It may need mana, timing, a target, or another required choice."
    }

    private func sourceCardName(for action: LegalAction) -> String {
        if let cardName = action.cardName, !cardName.isEmpty {
            return cardName
        }
        let id = action.sourceInstanceId ?? action.cardInstanceId
        if let id, let card = snapshot.human?.zones.battlefield.first(where: { $0.instanceId == id }) {
            return card.card.name
        }
        return action.label
    }

    private func producedManaLabel(for action: LegalAction) -> String? {
        guard let producedMana = action.producedMana, !producedMana.isEmpty else {
            return action.actionDetail
        }
        return producedMana.map { "{\($0)}" }.joined(separator: " ")
    }
}

struct MobileSurfacesPanel: View {
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let viewZone: (String, [ZoneCard]) -> Void

    var body: some View {
        PromptPanelSection(title: "Zones", detail: surfaceSummary) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 5)], spacing: 5) {
                zoneButton(title: "Stack", value: "\(stackObjectCount)", systemImage: "sparkles", cards: stackCards)
                zoneButton(title: "Command", value: "\(commandCards.count)", systemImage: "crown", cards: commandCards)
                zoneButton(title: "Grave", value: "\(graveyardCards.count)", systemImage: "archivebox", cards: graveyardCards)
                zoneButton(title: "Exile", value: "\(exileCards.count)", systemImage: "moon.stars", cards: exileCards)
                SurfaceChip(title: "Library", value: "\(libraryCount)", systemImage: "books.vertical")
                if !revealedCards.isEmpty || snapshot.xmage?.panels.revealed == true {
                    zoneButton(title: "Revealed", value: "\(revealedCards.count)", systemImage: "eye", cards: revealedCards)
                }
                if !lookedAtCards.isEmpty || snapshot.xmage?.panels.lookedAt == true {
                    zoneButton(title: "Looked", value: "\(lookedAtCards.count)", systemImage: "eye.trianglebadge.exclamationmark", cards: lookedAtCards)
                }
                SurfaceChip(title: "Priority", value: priorityOwner, systemImage: "hand.raised")
                SurfaceChip(title: "Actions", value: "\((snapshot.legalActions ?? []).count)", systemImage: "bolt")
            }

            if let topStackObject = stackObjectNames.first {
                Text("Stack top: \(topStackObject)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.priorityArcane.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
        }
    }

    private func zoneButton(title: String, value: String, systemImage: String, cards: [ZoneCard]) -> some View {
        Button {
            viewZone(title == "Grave" ? "Graveyard" : title, cards)
        } label: {
            SurfaceChip(title: title, value: value, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) zone, \(value) cards")
    }

    private var surfaceSummary: String {
        if snapshot.xmage?.panels.search == true {
            return "search"
        }
        if snapshot.xmage?.panels.revealed == true {
            return "revealed"
        }
        if snapshot.xmage?.panels.lookedAt == true {
            return "looked"
        }
        return priorityOwner
    }

    private var priorityOwner: String {
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty {
            return "You"
        }
        return snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId ?? "-"
    }

    private var stackCards: [ZoneCard] {
        let xmageCards = snapshot.xmage?.stack.compactMap(\.displaySourceCard) ?? []
        if !xmageCards.isEmpty { return xmageCards }
        return snapshot.players.flatMap(\.zones.stack)
    }

    private var stackObjectCount: Int {
        let xmageCount = snapshot.xmage?.stack.count ?? 0
        return max(xmageCount, stackCards.count)
    }

    private var stackObjectNames: [String] {
        snapshot.xmage?.stack.map(\.displayName).filter { !$0.isEmpty } ?? []
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

    private var libraryCount: Int {
        snapshot.players.map { $0.zones.library.count }.reduce(0, +)
    }

    private var revealedCards: [ZoneCard] {
        snapshot.xmage?.revealed.flatMap(\.cards) ?? []
    }

    private var lookedAtCards: [ZoneCard] {
        snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
    }
}

struct PromptPanelSection<Content: View>: View {
    let title: String
    let detail: String
    var isHighlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(isHighlighted ? MagicPalette.warningAmber : MagicPalette.antiqueGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 3)
                Text(detail.uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(isHighlighted ? MagicPalette.warningAmber.opacity(0.86) : MagicPalette.parchment.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            content
        }
        .padding(7)
        .background(
            isHighlighted ? MagicPalette.warningAmber.opacity(0.10) : MagicPalette.iron.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isHighlighted ? MagicPalette.warningAmber.opacity(0.48) : MagicPalette.borderBronze.opacity(0.28), lineWidth: isHighlighted ? 1.5 : 1))
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
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 4 : 5)
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 32, alignment: .leading)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(isPrimary ? 0.18 : 0.10)))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isDanger {
            return isPressed ? MagicPalette.oxblood.opacity(0.68) : MagicPalette.oxblood.opacity(0.86)
        }
        if isPrimary {
            return isPressed ? MagicPalette.brass.opacity(0.70) : MagicPalette.antiqueGold.opacity(0.82)
        }
        return isPressed ? MagicPalette.panelParchment.opacity(0.18) : MagicPalette.iron.opacity(0.58)
    }
}

struct SurfaceChip: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold.opacity(0.86))
                    .frame(width: 10)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(MagicPalette.parchment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title.uppercased())
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.56))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(MagicPalette.iron.opacity(0.54), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(MagicPalette.borderBronze.opacity(0.34), lineWidth: 1))
    }
}

struct MiniZoneRow: View {
    let title: String
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var onViewAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                PromptMiniLabel(title)
                Spacer()
                if let onViewAll {
                    Button("View All (\(cards.count))") {
                        onViewAll()
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.cyan)
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -7) {
                    ForEach(cards) { card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: title, width: 28, height: 39)
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

struct CompactPromptPopup: View {
    let snapshot: GameSnapshot
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let openDetails: () -> Void

    private var promptV2: PromptEnvelopeV2? { snapshot.promptEnvelopeV2 }
    private var legalActions: [LegalAction] { snapshot.legalActions ?? [] }
    private var sourceManaActions: [LegalAction] {
        legalActions.filter { $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil) }
    }
    private var compactPromptActions: [LegalAction] {
        Self.compactLegalPromptActions(in: snapshot)
    }
    private var paymentPrompt: PromptEnvelopeV2? {
        if let prompt = promptV2, Self.isManaPaymentPrompt(prompt) {
            return prompt
        }
        if Self.shouldShowStackPaymentTray(in: snapshot) {
            return Self.syntheticStackPaymentPrompt(in: snapshot)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(messageText)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                Spacer(minLength: 4)
                Text(priorityLabel)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            if pendingActionId != nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(MagicPalette.arcaneBlue)
                        .scaleEffect(0.66)
                    Text("Waiting for XMage")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.arcaneBlue)
                }
            } else if let prompt = paymentPrompt {
                ManaPaymentTray(
                    snapshot: snapshot,
                    prompt: prompt,
                    sourceManaActions: sourceManaActions,
                    pendingActionId: pendingActionId,
                    runAction: runAction,
                    runCommand: runCommand
                )
            } else if let prompt = promptV2 {
                compactPromptControls(prompt)
            } else if let prompt = snapshot.choicePrompt {
                compactChoicePrompt(prompt)
            } else if let prompt = snapshot.promptEnvelope {
                compactLegacyPrompt(prompt)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.92), MagicPalette.leather.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor.opacity(0.60), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 5)
    }

    static func shouldShow(for snapshot: GameSnapshot, pendingActionId: String?) -> Bool {
        if pendingActionId != nil {
            return true
        }
        if shouldShowStackPaymentTray(in: snapshot) {
            return true
        }

        if let prompt = snapshot.promptEnvelopeV2 {
            if isManaPaymentPrompt(prompt) {
                return true
            }
            if isPassivePriorityPrompt(prompt, snapshot: snapshot) {
                return false
            }
            if !compactLegalPromptActions(in: snapshot).isEmpty {
                return true
            }
            if needsDetails(snapshot) {
                return true
            }
            if prompt.confirmation != nil || isCommanderReplacementPrompt(prompt) {
                return true
            }
            if prompt.choices?.isEmpty == false {
                return true
            }
            return prompt.required == true && !isPassivePriorityMessage(prompt.message)
        }

        if let choicePrompt = snapshot.choicePrompt {
            return !choicePrompt.choices.isEmpty || !compactLegalPromptActions(in: snapshot).isEmpty
        }

        if let prompt = snapshot.promptEnvelope {
            return prompt.choices?.isEmpty == false || !compactLegalPromptActions(in: snapshot).isEmpty
        }

        return false
    }

    static func shouldShowStackPaymentTray(in snapshot: GameSnapshot) -> Bool {
        guard snapshot.promptEnvelopeV2 == nil else { return false }
        guard snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" else { return false }
        let hasStackObject = !(snapshot.xmage?.stack.isEmpty ?? true) || !(snapshot.human?.zones.stack.isEmpty ?? true)
        guard hasStackObject else { return false }
        return (snapshot.legalActions ?? []).contains { action in
            action.type == "make_mana" && (action.sourceInstanceId != nil || action.cardInstanceId != nil)
        }
    }

    static func syntheticStackPaymentPrompt(in snapshot: GameSnapshot) -> PromptEnvelopeV2 {
        PromptEnvelopeV2(
            id: "xmage-stack-payment-\(snapshot.bridgeRevision ?? snapshot.turn)",
            method: "GAME_PLAY_MANA",
            messageId: -1,
            playerId: snapshot.human?.playerId ?? "human",
            responseKind: "mana",
            message: stackPaymentMessage(in: snapshot),
            required: false,
            minChoices: nil,
            maxChoices: nil,
            totalMin: nil,
            totalMax: nil,
            targetIds: nil,
            choices: nil,
            responseCommand: nil,
            cards: nil,
            targets: nil,
            players: nil,
            piles: nil,
            abilities: nil,
            modes: nil,
            amounts: nil,
            multiAmounts: nil,
            manaChoices: nil,
            orderedItems: nil,
            confirmation: nil,
            options: nil
        )
    }

    private static func stackPaymentMessage(in snapshot: GameSnapshot) -> String {
        if let top = snapshot.xmage?.stack.first {
            return "Tap mana for \(top.displayName)"
        }
        if let top = snapshot.human?.zones.stack.first {
            return "Tap mana for \(top.card.name)"
        }
        return "Tap mana for the spell"
    }

    static func needsDetails(_ snapshot: GameSnapshot) -> Bool {
        guard let prompt = snapshot.promptEnvelopeV2 else { return false }
        if prompt.cards?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false { return true }
        if prompt.piles?.isEmpty == false || prompt.abilities?.isEmpty == false || prompt.modes?.isEmpty == false { return true }
        if prompt.amounts?.isEmpty == false || prompt.multiAmounts?.isEmpty == false || prompt.orderedItems?.isEmpty == false { return true }
        return (prompt.choices?.count ?? 0) > 3
    }

    static func compactLegalPromptActions(in snapshot: GameSnapshot) -> [LegalAction] {
        let legalActions = snapshot.legalActions ?? []
        let promptId = snapshot.promptEnvelopeV2?.responseCommand?.promptId
            ?? snapshot.promptEnvelopeV2?.id
            ?? snapshot.promptEnvelope?.id
            ?? snapshot.choicePrompt?.id
        let responseType = snapshot.promptEnvelopeV2?.responseCommand?.type?.lowercased()
        let responseKind = snapshot.promptEnvelopeV2?.responseKind.lowercased()
            ?? snapshot.promptEnvelope?.responseKind.lowercased()
        let message = (
            snapshot.promptEnvelopeV2?.message
                ?? snapshot.promptEnvelope?.message
                ?? snapshot.choicePrompt?.message
                ?? snapshot.promptText
                ?? ""
        ).lowercased()

        var allowedTypes = Set(["resolve_choice", "answer_yes_no", "pay_cost", "commander_replacement"])
        if message.contains("mulligan") {
            allowedTypes.formUnion(["keep_hand", "mulligan"])
        }
        if message.contains("starting player") || message.contains("starts") || responseKind == "player" {
            allowedTypes.insert("choose_player")
        }
        if responseType == "resolve_choice" || responseKind == "choice" {
            allowedTypes.insert("resolve_choice")
        }

        return legalActions
            .filter { action in
                if action.type == "concede" { return false }
                if let promptId, action.promptId == promptId { return true }
                if let responseType, action.type == responseType { return true }
                return allowedTypes.contains(action.type)
            }
            .sorted { lhs, rhs in
                compactActionPriority(lhs) < compactActionPriority(rhs)
            }
    }

    private var isManaPayment: Bool {
        if let prompt = promptV2 {
            return Self.isManaPaymentPrompt(prompt)
        }
        return false
    }

    private var borderColor: Color {
        isManaPayment ? MagicPalette.arcaneBlue : MagicPalette.borderBronze
    }

    private var priorityLabel: String {
        if snapshot.priorityPlayerId == "human" || snapshot.waitingOnPlayerId == "human" {
            return "YOUR DECISION"
        }
        return "WAITING"
    }

    private var messageText: String {
        promptV2?.message
            ?? snapshot.choicePrompt?.message
            ?? snapshot.promptEnvelope?.message
            ?? snapshot.promptText
            ?? "XMage is waiting"
    }

    @ViewBuilder
    private func compactPromptControls(_ prompt: PromptEnvelopeV2) -> some View {
        if isCommanderReplacement(prompt) {
            HStack(spacing: 7) {
                compactCommandButton("Command zone", systemImage: "crown.fill", pendingId: "\(prompt.id)-command-zone", command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: true))
                compactCommandButton("Original", systemImage: "arrow.uturn.backward", pendingId: "\(prompt.id)-original-zone", command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: false))
            }
        } else if let confirmation = prompt.confirmation, isConfirmationPrompt(prompt) {
            HStack(spacing: 7) {
                compactCommandButton(confirmation.yesLabel ?? "Yes", systemImage: "checkmark.circle", pendingId: "\(prompt.id)-yes", command: explicitConfirmationCommand(confirmation.yesCommand, prompt: prompt))
                compactCommandButton(confirmation.noLabel ?? "No", systemImage: "xmark.circle", pendingId: "\(prompt.id)-no", command: explicitConfirmationCommand(confirmation.noCommand, prompt: prompt))
            }
        } else if Self.shouldPreferCompactActionsBeforeRawChoices(for: snapshot) {
            compactActionButtons(compactPromptActions)
        } else if let choices = prompt.choices, !choices.isEmpty, choices.count <= 3 {
            HStack(spacing: 7) {
                ForEach(choices) { choice in
                    compactCommandButton(
                        choice.label,
                        systemImage: yesNoIcon(choice.label),
                        pendingId: "\(prompt.id)-\(choice.id)",
                        command: command(type: PromptCommandBuilder.idCommandType(preferred: prompt.responseCommand?.type, fallback: "resolve_choice"), promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [choice.id])
                    )
                }
            }
        } else if !compactPromptActions.isEmpty {
            compactActionButtons(compactPromptActions)
        } else if CompactPromptPopup.needsDetails(snapshot) {
            detailButton()
        } else {
            unsupportedFallback()
        }
    }

    @ViewBuilder
    private func compactChoicePrompt(_ prompt: ChoicePrompt) -> some View {
        HStack(spacing: 7) {
            ForEach(prompt.choices.prefix(3)) { choice in
                let action = action(for: choice, promptId: prompt.id)
                Button {
                    if let action {
                        runAction(action)
                    } else if let command = command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) {
                        runCommand(command, choice.label, "\(prompt.id)-\(choice.id)")
                    }
                } label: {
                    PromptButtonLabel(title: choice.label, systemImage: yesNoIcon(choice.label), isPending: pendingActionId == action?.id || pendingActionId == "\(prompt.id)-\(choice.id)")
                }
                .buttonStyle(PanelActionButtonStyle(isPrimary: action?.isPrimary == true))
                .disabled(pendingActionId != nil || (action == nil && command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) == nil))
            }
            if prompt.choices.count > 3 {
                detailButton()
            }
        }
    }

    static func shouldPreferCompactActionsBeforeRawChoices(for snapshot: GameSnapshot) -> Bool {
        let actions = compactLegalPromptActions(in: snapshot)
        guard actions.contains(where: { $0.type == "choose_player" }) else {
            return false
        }
        let responseType = snapshot.promptEnvelopeV2?.responseCommand?.type?.lowercased()
        let responseKind = snapshot.promptEnvelopeV2?.responseKind.lowercased()
            ?? snapshot.promptEnvelope?.responseKind.lowercased()
        let message = (
            snapshot.promptEnvelopeV2?.message
                ?? snapshot.promptEnvelope?.message
                ?? snapshot.choicePrompt?.message
                ?? snapshot.promptText
                ?? ""
        ).lowercased()
        return responseType == "choose_player" ||
            responseKind == "player" ||
            message.contains("starting player")
    }

    @ViewBuilder
    private func compactLegacyPrompt(_ prompt: PromptEnvelope) -> some View {
        if let choices = prompt.choices, !choices.isEmpty {
            HStack(spacing: 7) {
                ForEach(choices.prefix(3)) { choice in
                    compactCommandButton(choice.label, systemImage: yesNoIcon(choice.label), pendingId: "\(prompt.id)-\(choice.id)", command: command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]))
                }
            }
        } else if !compactPromptActions.isEmpty {
            compactActionButtons(compactPromptActions)
        } else {
            unsupportedFallback()
        }
    }

    private func compactActionButtons(_ actions: [LegalAction]) -> some View {
        HStack(spacing: 7) {
            ForEach(actions.prefix(3)) { action in
                let title = action.shortLabel ?? compactActionLabel(action)
                Button {
                    runAction(action)
                } label: {
                    PromptButtonLabel(
                        title: title,
                        systemImage: action.systemImage,
                        isPending: pendingActionId == action.id
                    )
                }
                .buttonStyle(PanelActionButtonStyle(isPrimary: action.isPrimary == true || action.type == "keep_hand", compact: true))
                .disabled(pendingActionId != nil)
            }
            if actions.count > 3 {
                detailButton()
            }
        }
    }

    private func detailButton() -> some View {
        Button(action: openDetails) {
            PromptButtonLabel(title: "Open choices", subtitle: "XMage prompt controls", systemImage: "list.bullet.rectangle", isPending: false)
        }
        .buttonStyle(PanelActionButtonStyle())
        .disabled(pendingActionId != nil)
    }

    private func compactCommandButton(_ label: String, systemImage: String? = nil, pendingId: String, command: GameCommand?) -> some View {
        Button {
            if let command {
                runCommand(command, label, pendingId)
            }
        } label: {
            PromptButtonLabel(title: label, systemImage: systemImage, isPending: pendingActionId == pendingId)
        }
        .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
        .disabled(pendingActionId != nil || command == nil)
    }

    private func unsupportedFallback() -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.warningAmber)
            Text("Needs app support")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
            Spacer(minLength: 2)
            detailButton()
        }
    }

    private func action(for choice: ChoicePromptOption, promptId: String) -> LegalAction? {
        let choiceId = choice.id
        let composedId = "\(promptId)-\(choiceId)"
        return legalActions.first { action in
            action.id == choiceId ||
                action.id == composedId ||
                action.targetIds?.contains(choiceId) == true ||
                action.validTargetIds?.contains(choiceId) == true ||
                action.id.hasSuffix("-\(choiceId)")
        }
    }

    private func command(
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        useCommandZone: Bool? = nil,
        manaType: String? = nil,
        pay: Bool? = nil
    ) -> GameCommand? {
        UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: snapshot.promptEnvelopeV2,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            useCommandZone: useCommandZone,
            manaType: manaType,
            pay: pay
        )
    }

    private func explicitConfirmationCommand(_ confirmationCommand: XmageResponseCommand?, prompt: PromptEnvelopeV2) -> GameCommand? {
        guard let confirmationCommand,
              let type = confirmationCommand.type,
              let promptId = confirmationCommand.promptId,
              let confirmed = confirmationCommand.confirmed ?? confirmationCommand.pay
        else {
            return nil
        }
        return command(
            type: type,
            promptId: promptId,
            playerId: prompt.playerId,
            ids: [confirmed ? "true" : "false"],
            pay: confirmationCommand.pay ?? confirmed
        )
    }

    private static func isManaPaymentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        return type == "play_mana" || type == "choose_mana" || type == "pay_cost" || type == "play_x_mana" ||
            kind == "mana" || kind == "pay_cost" || kind == "cost" || kind == "x_mana" ||
            prompt.method == "GAME_PLAY_MANA" || prompt.method == "GAME_PLAY_XMANA"
    }

    private func isConfirmationPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        prompt.responseCommand?.type?.lowercased() == "answer_yes_no" || prompt.responseKind.lowercased() == "confirmation"
    }

    private func isCommanderReplacement(_ prompt: PromptEnvelopeV2) -> Bool {
        return Self.isCommanderReplacementPrompt(prompt)
    }

    private func sourceCardName(for action: LegalAction) -> String {
        action.cardName ?? action.label.replacingOccurrences(of: "Tap ", with: "")
    }

    private func compactActionLabel(_ action: LegalAction) -> String {
        switch action.type {
        case "keep_hand":
            return "Keep"
        case "mulligan":
            return "Mulligan"
        default:
            return action.label
        }
    }

    private func yesNoIcon(_ label: String) -> String? {
        let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "ok", "accept", "keep"].contains(lower) { return "checkmark.circle" }
        if ["no", "cancel", "decline", "mulligan"].contains(lower) { return "xmark.circle" }
        return nil
    }

    private static func compactActionPriority(_ action: LegalAction) -> Int {
        if action.isPrimary == true { return 0 }
        switch action.type {
        case "keep_hand":
            return 1
        case "mulligan":
            return 2
        case "choose_player":
            return 3
        case "resolve_choice", "answer_yes_no":
            return 4
        case "pay_cost", "commander_replacement":
            return 5
        default:
            return 8
        }
    }

    private static func isCommanderReplacementPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "commander_replacement" || prompt.message.localizedCaseInsensitiveContains("command zone")
    }

    private static func isPassivePriorityPrompt(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> Bool {
        guard prompt.method == "GAME_SELECT" else { return false }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        guard type == "choose_card" || type == "card" else { return false }
        if prompt.cards?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false {
            return false
        }
        if prompt.choices?.isEmpty == false || prompt.modes?.isEmpty == false || prompt.abilities?.isEmpty == false {
            return false
        }
        return isPassivePriorityMessage(prompt.message) || isPassivePriorityMessage(snapshot.promptText ?? "")
    }

    private static func isPassivePriorityMessage(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "play spells and abilities" ||
            normalized == "play instants and activated abilities" ||
            normalized == "play spells or abilities" ||
            normalized == "select a card"
    }
}

struct DragActionChoice: Identifiable {
    let id = UUID()
    let message: String
    let actions: [LegalAction]
}

struct DragActionChoicePopup: View {
    let choice: DragActionChoice
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(choice.message)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
                .disabled(pendingActionId != nil)
            }

            HStack(spacing: 7) {
                ForEach(choice.actions.prefix(3)) { action in
                    Button {
                        runAction(action)
                    } label: {
                        PromptButtonLabel(
                            title: action.shortLabel ?? action.label,
                            systemImage: action.systemImage,
                            isPending: pendingActionId == action.id
                        )
                    }
                    .buttonStyle(PanelActionButtonStyle(isPrimary: action.isPrimary == true, compact: true))
                    .disabled(pendingActionId != nil)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.94), MagicPalette.leather.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MagicPalette.antiqueGold.opacity(0.62), lineWidth: 1.2))
        .shadow(color: MagicPalette.antiqueGold.opacity(0.18), radius: 14, x: 0, y: 0)
    }
}

struct ManaPaymentTray: View {
    let snapshot: GameSnapshot
    let prompt: PromptEnvelopeV2
    let sourceManaActions: [LegalAction]
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(requiredManaText)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                manaPoolPips
            }

            if !sourceManaActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sourceManaActions.prefix(8)) { action in
                            Button {
                                runAction(action)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9, weight: .black))
                                    Text(sourceCardName(for: action))
                                        .font(.system(size: 10, weight: .black))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.62)
                                    producedManaSymbols(for: action)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(MagicPalette.legalEmerald.opacity(0.20), in: Capsule())
                                .overlay(Capsule().stroke(MagicPalette.legalEmerald.opacity(0.54), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(pendingActionId != nil)
                        }
                    }
                }
            }

            if let choices = prompt.manaChoices, !choices.isEmpty {
                HStack(spacing: 7) {
                    Text("Pay")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.72))
                    ForEach(choices.prefix(6)) { choice in
                        let symbol = choice.manaType ?? choice.id
                        Button {
                            if let command = command(type: prompt.responseCommand?.type ?? "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol) {
                                runCommand(command, choice.label, "\(prompt.id)-mana-choice-\(choice.id)")
                            }
                        } label: {
                            ManaSymbolView(symbol: symbol, size: 24)
                                .opacity(canPay(symbol) ? 1 : 0.42)
                        }
                        .buttonStyle(.plain)
                        .disabled(pendingActionId != nil || !canPay(symbol) || command(type: prompt.responseCommand?.type ?? "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol) == nil)
                    }
                }
            }

            let undoActions = Self.manaUndoActions(in: snapshot)
            if !undoActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(undoActions.prefix(2)) { action in
                        Button {
                            runAction(action)
                        } label: {
                            PromptButtonLabel(title: action.shortLabel ?? "Undo Mana", systemImage: "arrow.uturn.backward", isPending: pendingActionId == action.id)
                        }
                        .buttonStyle(PanelActionButtonStyle(compact: true))
                        .disabled(pendingActionId != nil)
                    }
                }
            } else if let undoText = Self.manaUndoUnavailableText(in: snapshot) {
                Text(undoText)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if sourceManaActions.isEmpty && prompt.manaChoices?.isEmpty != false {
                Text("Waiting for XMage mana options")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.arcaneBlue)
            }
        }
    }

    static func manaUndoActions(in snapshot: GameSnapshot) -> [LegalAction] {
        let undoTypes = Set(["undo_mana", "cancel_payment", "cancel_mana_payment"])
        return (snapshot.legalActions ?? [])
            .filter { undoTypes.contains($0.type) }
    }

    static func manaUndoUnavailableText(in snapshot: GameSnapshot) -> String? {
        guard hasFloatingMana(in: snapshot), manaUndoActions(in: snapshot).isEmpty else {
            return nil
        }
        return "XMage has not exposed mana undo"
    }

    private static func hasFloatingMana(in snapshot: GameSnapshot) -> Bool {
        guard let pool = snapshot.human?.manaPool else { return false }
        return pool.W + pool.U + pool.B + pool.R + pool.G + pool.C > 0
    }

    private var requiredManaText: String {
        let message = prompt.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Tap for mana"
        }
        return message.count > 28 ? "Pay mana" : message
    }

    private var manaPoolPips: some View {
        HStack(spacing: 3) {
            ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { symbol in
                let count = manaPoolValue(symbol)
                if count > 0 {
                    HStack(spacing: 1) {
                        ManaSymbolView(symbol: symbol, size: 16)
                        Text("\(count)")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
            }
        }
    }

    private func producedManaSymbols(for action: LegalAction) -> some View {
        HStack(spacing: -2) {
            ForEach((action.producedMana ?? []).prefix(3), id: \.self) { symbol in
                ManaSymbolView(symbol: symbol, size: 16)
            }
        }
    }

    private func command(
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        manaType: String? = nil
    ) -> GameCommand? {
        UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: snapshot.promptEnvelopeV2,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            manaType: manaType
        )
    }

    private func canPay(_ symbol: String) -> Bool {
        if manaPoolValue(symbol) > 0 { return true }
        return symbol == "C" && ["W", "U", "B", "R", "G", "C"].contains { manaPoolValue($0) > 0 }
    }

    private func manaPoolValue(_ symbol: String) -> Int {
        let pool = snapshot.human?.manaPool
        switch symbol {
        case "W": return pool?.W ?? 0
        case "U": return pool?.U ?? 0
        case "B": return pool?.B ?? 0
        case "R": return pool?.R ?? 0
        case "G": return pool?.G ?? 0
        case "C": return pool?.C ?? 0
        default: return 0
        }
    }

    private func sourceCardName(for action: LegalAction) -> String {
        action.cardName ?? action.label.replacingOccurrences(of: "Tap ", with: "")
    }
}

struct BattlefieldRow: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let targetableIds: Set<String>
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: showsOverflowIndicator) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        let action = legalAction(for: card)
                        let targetable = targetableIds.contains(card.instanceId) || targetableIds.contains(card.id)
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: action != nil, targetable: targetable, zoneName: title, width: cardWidth, height: cardHeight)
                            .offset(y: card.tapped == true ? 5 : 0)
                            .zIndex(Double(index))
                            .onTapGesture {
                                if targetable {
                                    runTargetAction(card)
                                } else if let action, action.type == "make_mana" {
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
                .frame(minWidth: rowWidth, minHeight: max(cardHeight + 6, 44), alignment: .center)
            }

            if showsOverflowIndicator {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 7, weight: .black))
                    Text("Scroll")
                        .font(.system(size: 7, weight: .black))
                }
                .foregroundStyle(MagicPalette.parchment.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MagicPalette.iron.opacity(0.62), in: Capsule())
                .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.28), lineWidth: 0.8))
                .padding(.leading, 7)
                .padding(.top, 3)
                .allowsHitTesting(false)
            }
        }
    }

    private var showsOverflowIndicator: Bool {
        let contentWidth = CGFloat(cards.count) * cardWidth + CGFloat(max(cards.count - 1, 0)) * 4 + 16
        return contentWidth > rowWidth
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
    @Binding var interactionState: GameBoardInteractionState
    let metrics: BattlefieldLayoutMetrics
    @Binding var isOverPlayerDropZone: Bool
    let onDropFeedback: (String) -> Void
    let onActionChoice: ([LegalAction], String) -> Void
    let runAction: (LegalAction) -> Void
    @State private var draggingCardId: String?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let frame = HandFanLayout.cardFrame(
                    index: index,
                    card: card,
                    cards: cards,
                    metrics: metrics,
                    selectedCardId: selectedCard?.id,
                    draggingCardId: draggingCardId,
                    dragOffset: dragOffset
                )
                let selected = selectedCard?.id == card.id
                let playableActions = legalHandActions(for: card)
                let isDragging = draggingCardId == card.id

                CardTile(
                    card: card,
                    selected: selected,
                    pending: pendingCardInstanceId == card.instanceId,
                    legal: !playableActions.isEmpty,
                    zoneName: "Hand",
                    width: metrics.handCardWidth,
                    height: metrics.handCardHeight
                )
                    .scaleEffect(selected ? 1.16 : 1.0)
                    .offset(
                        x: frame.midX - metrics.playWidth / 2,
                        y: frame.midY - metrics.handFrameHeight / 2
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
                    if let card = draggingCard ?? card(at: value.location) {
                        selectedCard = card
                        inspectedCard = nil
                        draggingCardId = card.id
                        dragOffset = value.translation
                        isOverPlayerDropZone = metrics.playerPlayAreaRect.contains(boardPoint(for: value.location))
                        interactionState.mode = .draggingCard(
                            cardId: card.instanceId,
                            legalActionIds: legalHandActions(for: card).map(\.id)
                        )
                    }
                }
                .onEnded { value in
                    guard let card = draggingCard ?? selectedCard else { return }
                    selectedCard = card
                    let shouldPlay = metrics.playerPlayAreaRect.contains(boardPoint(for: value.location))
                    draggingCardId = nil
                    dragOffset = .zero
                    isOverPlayerDropZone = false
                    guard shouldPlay else {
                        interactionState.mode = .selectedCard(cardId: card.instanceId)
                        return
                    }
                    switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: shouldPlay) {
                    case .ignored:
                        interactionState.mode = .selectedCard(cardId: card.instanceId)
                    case let .rejected(message):
                        onDropFeedback(message)
                        interactionState.mode = .selectedCard(cardId: card.instanceId)
                    case let .requiresChoice(actions, message):
                        onDropFeedback(message)
                        onActionChoice(actions, message)
                        interactionState.mode = .selectedCard(cardId: card.instanceId)
                    case let .submit(action):
                        interactionState.mode = .awaitingCastSnapshot(actionId: action.id)
                        runAction(action)
                    }
                }
        )
    }

    private func legalHandActions(for card: ZoneCard) -> [LegalAction] {
        GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
    }

    private func card(at point: CGPoint) -> ZoneCard? {
        HandFanLayout.card(
            at: point,
            cards: cards,
            metrics: metrics,
            selectedCardId: selectedCard?.id,
            draggingCardId: draggingCardId,
            dragOffset: dragOffset
        )
    }

    private func boardPoint(for localPoint: CGPoint) -> CGPoint {
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

enum HandFanLayout {
    static func card(
        at point: CGPoint,
        cards: [ZoneCard],
        metrics: BattlefieldLayoutMetrics,
        selectedCardId: String?,
        draggingCardId: String?,
        dragOffset: CGSize
    ) -> ZoneCard? {
        guard !cards.isEmpty else { return nil }
        for (index, card) in cards.enumerated().reversed() {
            let frame = cardFrame(
                index: index,
                card: card,
                cards: cards,
                metrics: metrics,
                selectedCardId: selectedCardId,
                draggingCardId: draggingCardId,
                dragOffset: dragOffset
            )
            if frame.insetBy(dx: -8, dy: -8).contains(point) {
                return card
            }
        }
        return cards.last
    }

    static func cardFrame(
        index: Int,
        card: ZoneCard,
        cards: [ZoneCard],
        metrics: BattlefieldLayoutMetrics,
        selectedCardId: String?,
        draggingCardId: String?,
        dragOffset: CGSize
    ) -> CGRect {
        let center = CGFloat(cards.count - 1) / 2
        let distance = CGFloat(index) - center
        let maxSpread = max((metrics.playWidth - metrics.handCardWidth) / CGFloat(max(cards.count - 1, 1)), 0)
        let spread = min(metrics.handCardWidth * 0.56, maxSpread)
        let isSelected = selectedCardId == card.id
        let isDragging = draggingCardId == card.id
        let midX = metrics.playWidth / 2 + distance * spread + (isDragging ? dragOffset.width : 0)
        let midY = metrics.handFrameHeight / 2 + (isSelected ? -30 : 10) + (isDragging ? dragOffset.height : 0)
        return CGRect(
            x: midX - metrics.handCardWidth / 2,
            y: midY - metrics.handCardHeight / 2,
            width: metrics.handCardWidth,
            height: metrics.handCardHeight
        )
    }
}

struct CardTile: View {
    let card: ZoneCard
    let selected: Bool
    var pending = false
    var legal = false
    var targetable = false
    var zoneName: String? = nil
    var width: CGFloat = 82
    var height: CGFloat = 112
    var ignoreTappedRotation: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: CardImageURL.normal(card.card.name)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .empty:
                    CardArtPlaceholder(card: card, width: width, height: height, loading: true)
                case .failure, _:
                    CardArtPlaceholder(card: card, width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            XmageCardIconStrip(icons: card.visibleXmageIcons, cardWidth: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .allowsHitTesting(false)

            if card.showsPowerToughness, let power = card.power, let toughness = card.toughness {
                Text("\(power)/\(toughness)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.92), in: Capsule())
                    .padding(3)
            }

            if card.tapped == true {
                Text("TAPPED")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(MagicPalette.oxblood.opacity(0.88), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }

            if card.isCreature && card.summoningSickness == true {
                Image(systemName: "hourglass")
                    .font(.system(size: max(width * 0.105, 7), weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .frame(width: max(width * 0.22, 13), height: max(width * 0.22, 13))
                    .background(MagicPalette.warningAmber.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.32), lineWidth: 0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
            }

            if !card.counterBadges.isEmpty {
                CardCounterBadgeStrip(badges: Array(card.counterBadges.prefix(3)), cardWidth: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: strokeWidth))
        .overlay {
            if legal && !selected && !pending && !targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MagicPalette.antiqueGold.opacity(0.92), lineWidth: max(width * 0.030, 2.1))
                    .shadow(
                        color: MagicPalette.legalEmerald.opacity(0.85),
                        radius: Self.playableGlowRadius(legal: legal, selected: selected, pending: pending, targetable: targetable, width: width)
                    )
                    .padding(-3)
            }
            if targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MagicPalette.antiqueGold.opacity(0.88), lineWidth: 2.5)
                    .shadow(color: MagicPalette.legalEmerald.opacity(0.72), radius: 9)
                    .padding(-3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if legal && !selected && !pending && !targetable {
                Circle()
                    .fill(MagicPalette.legalEmerald)
                    .frame(width: max(width * 0.11, 6), height: max(width * 0.11, 6))
                    .shadow(color: MagicPalette.legalEmerald.opacity(0.45), radius: 4)
                    .padding(max(width * 0.04, 3))
            }
        }
        .shadow(color: shadowColor, radius: shadowRadius)
        .rotationEffect(.degrees(card.tapped == true && !ignoreTappedRotation ? 90 : 0))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: card.tapped)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel(zoneName: zoneName, selected: selected, legal: legal, pending: pending))
        .accessibilityIdentifier(card.accessibilityIdentifier(zoneName: zoneName))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to select. Long press to inspect.")
    }

    private var strokeColor: Color {
        if pending {
            return MagicPalette.warningAmber
        }
        if selected {
            return MagicPalette.antiqueGold
        }
        if targetable {
            return MagicPalette.legalEmerald
        }
        if legal {
            return MagicPalette.legalEmerald.opacity(0.72)
        }
        return .black.opacity(0.55)
    }

    private var strokeWidth: CGFloat {
        if selected || pending || targetable { return 3 }
        if legal { return 2.2 }
        return 1
    }

    private var shadowColor: Color {
        if pending {
            return MagicPalette.warningAmber.opacity(0.75)
        }
        if selected {
            return MagicPalette.antiqueGold.opacity(0.55)
        }
        if targetable {
            return MagicPalette.legalEmerald.opacity(0.58)
        }
        if legal {
            return MagicPalette.legalEmerald.opacity(0.38)
        }
        return .clear
    }

    private var shadowRadius: CGFloat {
        if selected || pending {
            return 11
        }
        return Self.playableGlowRadius(legal: legal, selected: selected, pending: pending, targetable: targetable, width: width)
    }

    static func playableGlowRadius(legal: Bool, selected: Bool, pending: Bool, targetable: Bool, width: CGFloat) -> CGFloat {
        guard legal && !selected && !pending && !targetable else { return 0 }
        return max(width * 0.13, 7)
    }
}

struct CardCounterBadgeStrip: View {
    let badges: [CardCounterBadge]
    let cardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: max(cardWidth * 0.012, 1)) {
            ForEach(badges, id: \.self) { badge in
                HStack(spacing: 2) {
                    Text(badge.label)
                        .font(.system(size: max(cardWidth * 0.065, 5.5), weight: .black))
                    Text("\(badge.count)")
                        .font(.system(size: max(cardWidth * 0.083, 6.5), weight: .black))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, max(cardWidth * 0.035, 2.5))
                .padding(.vertical, max(cardWidth * 0.015, 1))
                .background(counterColor(for: badge).opacity(0.90), in: Capsule())
                .overlay(Capsule().stroke(.black.opacity(0.38), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
        }
    }

    private func counterColor(for badge: CardCounterBadge) -> Color {
        let label = badge.label
        if label == "+1/+1" { return MagicPalette.legalEmerald }
        if label == "-1/-1" { return MagicPalette.oxblood }
        if label == "LOY" { return MagicPalette.arcaneBlue }
        if label == "SHD" { return MagicPalette.antiqueGold }
        return MagicPalette.leather
    }
}

struct XmageCardIconStrip: View {
    let icons: [XmageCardIcon]
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: max(cardWidth * 0.018, 1)) {
            ForEach(visibleIcons, id: \.self) { icon in
                if let assetName = CardImageURL.xmageIconAssetName(for: icon.iconType),
                   let image = UIImage(named: assetName) {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(MagicPalette.parchment)
                        .frame(width: iconSize, height: iconSize)
                        .padding(max(cardWidth * 0.025, 1.5))
                        .background(MagicPalette.iron.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(MagicPalette.antiqueGold.opacity(0.45), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .accessibilityLabel(icon.displayText ?? icon.iconType)
                }
            }
            if icons.count > visibleIcons.count {
                Text("+\(icons.count - visibleIcons.count)")
                    .font(.system(size: max(cardWidth * 0.08, 6), weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .frame(width: iconSize, height: iconSize)
                    .background(MagicPalette.antiqueGold.opacity(0.9), in: Circle())
            }
        }
    }

    private var visibleIcons: [XmageCardIcon] {
        Array(icons.prefix(5))
    }

    private var iconSize: CGFloat {
        max(cardWidth * 0.18, 11)
    }
}

struct TargetingStatusPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .black))
            VStack(alignment: .leading, spacing: 1) {
                Text("Choose a glowing target")
                    .font(.system(size: 11, weight: .black))
                Text("\(count) XMage-valid target\(count == 1 ? "" : "s") exposed")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.75)
            }
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(MagicPalette.iron.opacity(0.90), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.legalEmerald.opacity(0.56), lineWidth: 1.3))
        .shadow(color: MagicPalette.legalEmerald.opacity(0.24), radius: 14, y: 5)
    }
}

struct CardArtPlaceholder: View {
    let card: ZoneCard
    let width: CGFloat
    let height: CGFloat
    var loading = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MagicPalette.parchment,
                    Color(red: 0.72, green: 0.59, blue: 0.38),
                    MagicPalette.parchmentShadow
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: max(height * 0.025, 2)) {
                HStack(alignment: .top, spacing: 3) {
                    Text(card.card.name)
                        .font(.system(size: max(width * 0.115, 6), weight: .black, design: .serif))
                        .foregroundStyle(MagicPalette.iron)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, max(width * 0.03, 2))
                .padding(.vertical, max(height * 0.018, 1.5))
                .background(MagicPalette.parchment.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))

                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MagicPalette.leather.opacity(0.78),
                                    MagicPalette.moss.opacity(0.62),
                                    MagicPalette.iron.opacity(0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: loading ? "hourglass" : "sparkles")
                        .font(.system(size: max(width * 0.18, 10), weight: .semibold))
                        .foregroundStyle(MagicPalette.antiqueGold.opacity(loading ? 0.34 : 0.42))
                }
                .frame(height: max(height * 0.38, 22))

                Text(card.card.typeLine.isEmpty ? "Card" : card.card.typeLine)
                    .font(.system(size: max(width * 0.075, 5), weight: .bold, design: .serif))
                    .foregroundStyle(MagicPalette.iron.opacity(0.78))
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, max(width * 0.035, 2))
                    .padding(.vertical, max(height * 0.012, 1))
                    .background(MagicPalette.parchmentShadow.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))

                Spacer(minLength: 0)
            }
            .padding(max(width * 0.07, 3.5))

            if loading {
                ProgressView()
                    .tint(MagicPalette.antiqueGold)
                    .scaleEffect(0.58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(max(width * 0.07, 4))
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    LinearGradient(
                        colors: [MagicPalette.borderBronze.opacity(0.70), MagicPalette.borderIron.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(width * 0.035, 1)
                )
        )
    }
}

struct MagicPathPhaseRail: View {
    let snapshot: GameSnapshot
    let passAction: LegalAction?
    let skipAction: LegalAction?
    let logAction: () -> Void
    let settingsAction: () -> Void
    let runAction: (LegalAction) -> Void
    var onlyPhases: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if onlyPhases {
                HStack(spacing: 7) {
                    PhaseChip(label: "Phase", phase: (snapshot.step ?? snapshot.phase).arenaPhaseTitle, active: true)
                    PhaseChip(label: "Priority", phase: snapshot.priorityPlayerId == "human" ? "YOU" : "AI", active: snapshot.priorityPlayerId == "human")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    Button {
                        if let passAction {
                            runAction(passAction)
                        }
                    } label: {
                        Text(passAction == nil ? "WAIT" : "PASS")
                            .font(.system(size: 12, weight: .black, design: .serif))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                    .disabled(passAction == nil)

                    Button {
                        if let skipAction {
                            runAction(skipAction)
                        }
                    } label: {
                        Text(Self.skipButtonLabel(snapshot: snapshot, action: skipAction))
                            .font(.system(size: 8, weight: .black, design: .serif))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                    .disabled(skipAction == nil)
                }

                HStack(spacing: 6) {
                    Button(action: logAction) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    Button(action: settingsAction) {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                }
            }
        }
        .padding(onlyPhases ? 0 : 8)
        .background(onlyPhases ? Color.clear : MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if !onlyPhases {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MagicPalette.antiqueGold.opacity(0.26), lineWidth: 1)
            }
        }
    }

    static func skipButtonLabel(snapshot: GameSnapshot, action: LegalAction?) -> String {
        "SKIP"
    }
}

enum GameMenuConfirmation: Equatable {
    case startNew
    case quit

    var title: String {
        switch self {
        case .startNew: return "Start a new game?"
        case .quit: return "Quit this game?"
        }
    }

    var message: String {
        switch self {
        case .startNew: return "MagicMobile will ask XMage to clean up the current game, then open setup."
        case .quit: return "MagicMobile will ask XMage to clean up the current game, then return to the main menu."
        }
    }
}

struct GameManagementMenu: View {
    let concedeAction: LegalAction?
    let runAction: (LegalAction) -> Void
    let confirmStartNew: () -> Void
    let confirmQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Menu")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("XMage remains the source of truth. Leaving a game asks the bridge to clean up the table.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)

            HStack(spacing: 10) {
                Button {
                    if let concedeAction {
                        runAction(concedeAction)
                    }
                } label: {
                    Label("Concede", systemImage: "flag.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactActionButtonStyle(isDanger: true, isPrimary: false))
                .disabled(concedeAction == nil)

                Button(action: confirmStartNew) {
                    Label("Start New", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactActionButtonStyle(isPrimary: true))

                Button(action: confirmQuit) {
                    Label("Quit", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactActionButtonStyle(isPrimary: false))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BattlefieldSurface().ignoresSafeArea())
    }
}

struct PhaseChip: View {
    let label: String
    let phase: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(active ? .black.opacity(0.7) : .white.opacity(0.55))
            Text(phase.compactPhaseTitle)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(active ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? MagicPalette.antiqueGold : MagicPalette.iron.opacity(0.50), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? MagicPalette.brass.opacity(0.55) : MagicPalette.borderBronze.opacity(0.20)))
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

    private var badges: [BadgeItem] {
        var items: [BadgeItem] = []
        if card.tapped == true {
            items.append(BadgeItem(text: "TAPPED", color: MagicPalette.oxblood))
        }
        if card.isAttacking == true {
            items.append(BadgeItem(text: "ATTACKING", color: Color.red))
        }
        if let blocking = card.blocking, !blocking.isEmpty {
            items.append(BadgeItem(text: "BLOCKING", color: Color.green))
        }
        if let damage = card.damage, damage > 0 {
            items.append(BadgeItem(text: "DAMAGE: \(damage)", color: Color(red: 0.7, green: 0.1, blue: 0.1)))
        }
        if card.showsPowerToughness, let power = card.power, let toughness = card.toughness {
            items.append(BadgeItem(text: "P/T: \(power)/\(toughness)", color: MagicPalette.antiqueGold))
        }
        if let counters = card.counters {
            for (name, val) in counters where val > 0 {
                items.append(BadgeItem(text: "\(name): \(val)", color: Color.purple))
            }
        }
        if card.attachedToInstanceId != nil {
            items.append(BadgeItem(text: "ATTACHED", color: Color.blue))
        }
        return items
    }

    var body: some View {
        HStack(spacing: 9) {
            CardTile(card: card, selected: true, zoneName: "Inspector", width: 82, height: 114, ignoreTappedRotation: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.card.name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(card.card.typeLine)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                    .lineLimit(2)

                if !badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(badges, id: \.text) { badge in
                                Text(badge.text)
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(badge.color, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .frame(height: 16)
                }

                ScrollView {
                    Text(card.card.oracleText ?? "Rules text unavailable.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.35)))
    }
}

struct BadgeItem {
    let text: String
    let color: Color
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
            .background(configuration.isPressed ? MagicPalette.brass.opacity(0.70) : MagicPalette.antiqueGold.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.50)))
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
            return isPressed ? MagicPalette.oxblood.opacity(0.66) : MagicPalette.oxblood.opacity(0.84)
        }
        if isPrimary {
            return isPressed ? MagicPalette.brass.opacity(0.70) : MagicPalette.antiqueGold.opacity(0.88)
        }
        return isPressed ? MagicPalette.panelParchment.opacity(0.18) : MagicPalette.iron.opacity(0.58)
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
    private static var shouldForcePlaceholders: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] == "true"
        #else
        false
        #endif
    }

    static func setBaseURL(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey)
    }

    static func normal(_ name: String, forcePlaceholder: Bool = shouldForcePlaceholders) -> URL? {
        if forcePlaceholder {
            return nil
        }
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

    static func bundledSymbolAssetName(for symbol: String) -> String? {
        switch cleanedSymbolCode(symbol) {
        case "w": return "mana-w"
        case "u": return "mana-u"
        case "b": return "mana-b"
        case "r": return "mana-r"
        case "g": return "mana-g"
        case "c": return "mana-c"
        default: return nil
        }
    }

    static func xmageIconAssetName(for iconType: String) -> String? {
        switch iconType.uppercased() {
        case "PLAYABLE_COUNT": return "xmage-icon-playable-count"
        case "ABILITY_FLYING": return "xmage-icon-flying"
        case "ABILITY_DEFENDER": return "xmage-icon-defender"
        case "ABILITY_DEATHTOUCH": return "xmage-icon-deathtouch"
        case "ABILITY_LIFELINK": return "xmage-icon-lifelink"
        case "ABILITY_DOUBLE_STRIKE": return "xmage-icon-double-strike"
        case "ABILITY_FIRST_STRIKE": return "xmage-icon-first-strike"
        case "ABILITY_CREW": return "xmage-icon-crew"
        case "ABILITY_TRAMPLE": return "xmage-icon-trample"
        case "ABILITY_HEXPROOF": return "xmage-icon-hexproof"
        case "ABILITY_INFECT": return "xmage-icon-infect"
        case "ABILITY_INDESTRUCTIBLE": return "xmage-icon-indestructible"
        case "ABILITY_VIGILANCE": return "xmage-icon-vigilance"
        case "ABILITY_CLASS_LEVEL": return "xmage-icon-class-level"
        case "ABILITY_REACH": return "xmage-icon-reach"
        case "OTHER_FACEDOWN": return "xmage-icon-facedown"
        case "OTHER_COST_X": return "xmage-icon-cost-x"
        case "OTHER_HAS_RESTRICTIONS": return "xmage-icon-restrictions"
        case "OTHER_HAS_TARGETS": return "xmage-icon-targets"
        case "RINGBEARER": return "xmage-icon-ringbearer"
        case "COMMANDER": return "xmage-icon-commander"
        case "SYSTEM_COMBINED": return "xmage-icon-combined"
        default: return nil
        }
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
        let cleaned = cleanedSymbolCode(symbol)
        let slug = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(slug.isEmpty ? "symbol" : slug).png"
    }

    private static func cleanedSymbolCode(_ symbol: String) -> String {
        symbol
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "∞", with: "infinity")
            .lowercased()
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

    var compactPhaseTitle: String {
        switch lowercased() {
        case "beginning", "untap", "upkeep", "draw":
            return capitalized
        case "precombat-main":
            return "Main 1"
        case "postcombat-main":
            return "Main 2"
        case "combat", "begin-combat":
            return "Combat"
        case "declare-attackers":
            return "Attackers"
        case "declare-blockers":
            return "Blockers"
        case "first-strike-damage":
            return "First Damage"
        case "combat-damage":
            return "Damage"
        case "end-combat":
            return "End Combat"
        case "ending", "end", "cleanup":
            return capitalized
        default:
            return phaseTitle
        }
    }

    var arenaPhaseTitle: String {
        switch lowercased() {
        case "beginning":
            return "BEGIN"
        case "untap":
            return "UNTAP"
        case "upkeep":
            return "UPKEEP"
        case "draw":
            return "DRAW"
        case "precombat-main", "postcombat-main":
            return "MAIN"
        case "combat", "begin-combat":
            return "COMBAT"
        case "declare-attackers":
            return "ATTACK"
        case "declare-blockers":
            return "BLOCK"
        case "first-strike-damage", "combat-damage":
            return "DAMAGE"
        case "end-combat":
            return "END C"
        case "ending", "end", "cleanup":
            return "END"
        default:
            return compactPhaseTitle.uppercased()
        }
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
        if type == "cast_spell" {
            if let manaCost, !manaCost.isEmpty {
                return requiresPayment == true ? "\(manaCost) · XMage will ask for payment" : manaCost
            }
            if requiresPayment == true {
                return "XMage will ask for payment"
            }
        }
        if type == "make_mana", let producedMana, !producedMana.isEmpty {
            return producedMana.map { "{\($0)}" }.joined(separator: " ")
        }
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

struct ZoneInspectorData: Identifiable {
    var id: String { title }
    let title: String
    let cards: [ZoneCard]
}

struct ZoneInspectorSheet: View {
    let title: String
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 9)], spacing: 10) {
                    ForEach(cards) { card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: title, width: 70, height: 98)
                            .onTapGesture {
                                selectedCard = card
                                inspectedCard = card
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                inspectedCard = card
                            }
                    }
                }
                .padding(18)
                .background(MagicPalette.iron.opacity(0.30), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(MagicPalette.borderBronze.opacity(0.32), lineWidth: 1.2))
                .padding(14)
            }
            .navigationTitle("\(title) · \(cards.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .background(BattlefieldSurface().ignoresSafeArea())
            .toolbarBackground(MagicPalette.iron, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct CompactZoneInspectorOverlay: View {
    let title: String
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let closeAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Title Bar
            HStack {
                Text("\(title) · \(cards.count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Spacer()
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()
                .background(MagicPalette.antiqueGold.opacity(0.18))

            // Scrollable Grid of Cards
            ScrollView {
                if cards.isEmpty {
                    Text("No cards in this zone.")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.4))
                        .padding(.top, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 8)], spacing: 8) {
                        ForEach(cards) { card in
                            CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: title, width: 44, height: 62)
                                .onTapGesture {
                                    selectedCard = card
                                    inspectedCard = card
                                }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    inspectedCard = card
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 320, height: 210)
        .background(MagicPalette.iron.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MagicPalette.antiqueGold.opacity(0.38), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
