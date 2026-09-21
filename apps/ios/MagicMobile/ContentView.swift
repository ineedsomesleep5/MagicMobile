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

enum TargetingHelperVisibility {
    static func shouldShow(
        snapshot: GameSnapshot,
        pendingActionId: String?,
        mode: GameBoardInteractionMode,
        targetableIds: Set<String>
    ) -> Bool {
        guard case .targeting = mode, !targetableIds.isEmpty else {
            return false
        }
        guard !InlinePaymentPromptState.isActive(in: snapshot) else {
            return false
        }
        guard !CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId) else {
            let promptKind = snapshot.promptEnvelopeV2?.responseKind.lowercased()
            let hasButtonActions = !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty
            return promptKind == "target" && !hasButtonActions
        }
        return true
    }
}

struct ContentView: View {
    @AppStorage("magicmobile.playerDisplayName") private var playerDisplayName = ""
    @AppStorage("magicmobile.activeGameId") private var activeGameId = ""
    @AppStorage("magicmobile.activeGameServerURL") private var activeGameServerURL = ""
    @AppStorage("magicmobile.serverURL") private var serverURLText = ProcessInfo.processInfo.environment["MAGICMOBILE_SERVER_URL"] ?? "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud"
    @AppStorage(PortraitModePreference.key) private var portraitModeEnabled = true
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
    @State private var lastActionRejection: ActionRejectionNotice?
    @State private var manaPaymentWasActive = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var liveUpdateStatus = "Idle"
    @State private var cardCacheMetadata: CardCacheMetadata?
    @State private var isSyncingCardCache = false
    @State private var phoneImageCacheCount = 0
    @State private var phoneInspectionImageCacheCount = 0
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
                MenuBackgroundSurface(portraitModeEnabled: portraitModeEnabled)
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
                    lastActionRejection: lastActionRejection,
                    liveUpdateStatus: liveUpdateStatus,
                    onInteractionFeedback: { message in
                        status = message
                        liveUpdateStatus = message
                    },
                    runAction: { action in Task { await run(action: action) } },
                    runCommand: { command, label, pendingId in Task { await run(command: command, label: label, pendingId: pendingId) } },
                    refreshGame: { Task { await refreshCurrentSnapshot() } },
                    reconnectGame: { Task { await resumeCurrentGame() } },
                    checkBridgeHealth: { await bridgeHealth() },
                    newGame: { Task { await leaveCurrentGame(destination: .setup, reason: "start-new-game") } },
                    quitGame: { Task { await leaveCurrentGame(destination: .menu, reason: "quit-game") } },
                    loadProtocolDebug: loadProtocolDebug(gameId:),
                    portraitModeEnabled: $portraitModeEnabled,
                    viewZone: { title, cards in
                        inspectingZoneTitle = title
                        inspectingZoneCards = cards
                    }
                )
            } else {
                VStack(spacing: 10) {
                    if screen != .menu { HeaderBar(
                        screen: screen,
                        status: status,
                        isLoading: isLoading,
                        menu: { screen = .menu },
                        settings: { screen = .settings }
                    ) }

                    chromeScreen
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .top) {
            #if DEBUG
            if snapshot?.source == "design-preview", status.hasPrefix("Development fixture: captured") {
                Text(status).font(.caption2).padding(4).background(.black)
                    .accessibilityIdentifier("preview.captured-command")
                    .allowsHitTesting(false)
            }
            if snapshot?.source == "design-preview" {
                let fixture = ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"]
                if fixture == "phase-announcement" || fixture == "life-change" || fixture == "attached-permanents" {
                    Button(fixture == "phase-announcement" ? "Advance preview phase" : "Preview life change") {
                        if fixture == "phase-announcement" {
                            snapshot = GameBoardPreviewFixtures.snapshot(.phaseAnnouncement, step: "DECLARE_BLOCKERS")
                        } else if fixture == "attached-permanents" {
                            snapshot = GameBoardPreviewFixtures.snapshot(.attachedPermanents, specialStateAdvanced: true)
                        } else {
                            snapshot = GameBoardPreviewFixtures.snapshot(.lifeChange, life: snapshot?.human?.life == 37 ? 35 : 43)
                        }
                    }
                    .font(.caption).padding(8).background(.black)
                    .padding(.top, 24).accessibilityIdentifier("preview.advance")
                }
            }
            #endif
        }
        .holdInspectionScope()
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
        .onChange(of: portraitModeEnabled) { _, enabled in
            MagicMobileOrientationController.shared.setPortraitModeEnabled(enabled)
        }
        .onChange(of: serverURLText) { _, newValue in
            CardImageURL.setBaseURL(newValue)
        }
        .task {
            MagicMobileOrientationController.shared.setPortraitModeEnabled(portraitModeEnabled)
            if !activeGameId.isEmpty, !activeGameServerURL.isEmpty {
                serverURLText = activeGameServerURL
            }
            CardImageURL.setBaseURL(serverURLText)
            #if DEBUG
            if await maybeStartDesignPreviewForMagicPath() {
                return
            }
            #endif
            await checkBridge()
            await resumeSavedGameIfNeeded()
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
                openSettings: { screen = .settings },
                quickStart: { Task { await startGame() } },
                resumeGame: { Task { await resumeCurrentGame() } },
                playerDisplayName: $playerDisplayName,
                selectedHumanPrecon: $selectedHumanPrecon,
                deckSummary: deckSummary,
                difficulty: difficulty,
                hasActiveGame: !activeGameId.isEmpty,
                portraitModeEnabled: portraitModeEnabled,
                cardCacheMetadata: cardCacheMetadata,
                isSyncingCardCache: isSyncingCardCache,
                phoneImageCacheCount: phoneImageCacheCount,
                phoneInspectionImageCacheCount: phoneInspectionImageCacheCount,
                phoneSymbolCacheCount: phoneSymbolCacheCount,
                phoneImageDownloadProgress: phoneImageDownloadProgress
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
                portraitModeEnabled: portraitModeEnabled,
                cardCacheMetadata: cardCacheMetadata,
                isSyncingCardCache: isSyncingCardCache,
                phoneImageCacheCount: phoneImageCacheCount,
                phoneInspectionImageCacheCount: phoneInspectionImageCacheCount,
                phoneSymbolCacheCount: phoneSymbolCacheCount,
                phoneImageDownloadProgress: phoneImageDownloadProgress,
                syncCardCache: { Task { await syncCardCache() } },
                checkBridge: { Task { await checkBridge() } },
                openDecks: { screen = .decks },
                startGame: { Task { await startGame() } },
                startFixtureGame: { Task { await startFixtureGame() } }
            )
        case .decks:
            DeckLibraryView(
                serverURL: serverURLText,
                activeDeck: $importedDeck,
                selectedHumanPrecon: $selectedHumanPrecon,
                portraitModeEnabled: portraitModeEnabled
            )
        case .settings:
            SettingsView(
                serverURLText: $serverURLText,
                portraitModeEnabled: $portraitModeEnabled,
                status: status,
                cardCacheMetadata: cardCacheMetadata,
                isSyncingCardCache: isSyncingCardCache,
                phoneImageCacheCount: phoneImageCacheCount,
                phoneInspectionImageCacheCount: phoneInspectionImageCacheCount,
                phoneSymbolCacheCount: phoneSymbolCacheCount,
                phoneImageDownloadProgress: phoneImageDownloadProgress,
                syncCardCache: { Task { await syncCardCache() } },
                checkBridge: { Task { await checkBridge() } }
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

    private func bridgeHealth() async -> EngineHealth? {
        guard let api else { return nil }
        do {
            let health = try await api.health()
            await MainActor.run {
                status = "\(health.status): \(health.reason)"
            }
            return health
        } catch {
            await MainActor.run {
                status = error.localizedDescription
            }
            return nil
        }
    }

    private func loadProtocolDebug(gameId: String) async throws -> XmageProtocolDebug {
        guard let api else { throw MagicMobileError.invalidServerURL }
        return try await api.protocolDebug(gameId: gameId)
    }

    private func refreshCardCacheMetadata() async {
        guard let api else { return }
        cardCacheMetadata = try? await api.cardCacheMetadata()
    }

    private func refreshPhoneAssetCacheCounts() async {
        phoneImageCacheCount = CardImageURL.cachedImageCount(variant: .board)
        phoneInspectionImageCacheCount = CardImageURL.cachedImageCount(variant: .inspection)
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
            phoneImageDownloadProgress = "inspection 0/\(manifest.images.count)"
            let downloadedInspectionImages = try await CardImageURL.downloadAllImagesToPhone(images: manifest.images, variant: .inspection) { completed, total in
                await MainActor.run {
                    phoneImageDownloadProgress = "inspection \(completed)/\(total)"
                    if completed == total || completed % 25 == 0 {
                        status = "Downloading inspection images \(completed)/\(total)"
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
            status = "Assets ready: \(phoneImageCacheCount) cards, \(phoneInspectionImageCacheCount) inspection images, \(phoneSymbolCacheCount) symbols cached (\(downloaded) cards, \(downloadedInspectionImages) inspection, \(downloadedSymbols) symbols new)"
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
        activeGameId = ""
        activeGameServerURL = ""
        snapshot = nil
        selectedCard = nil
        inspectedCard = nil
        pendingActionId = nil
        pendingCardInstanceId = nil
        lastActionRejection = nil
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
        activeGameId = ""
        activeGameServerURL = ""
        selectedCard = nil
        inspectedCard = nil
        pendingActionId = nil
        pendingCardInstanceId = nil
        lastActionRejection = nil
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
        activeGameId = ""
        activeGameServerURL = ""
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
        if previewText == "menu" {
            screen = .menu
            status = "Development menu preview"
            return true
        }
        let state = GameBoardDesignPreviewState(rawValue: previewText) ?? .normalBattlefield
        let previewSnapshot = GameBoardPreviewFixtures.snapshot(state)
        snapshot = previewSnapshot
        selectedCard = GameBoardPreviewFixtures.selectedCard(for: state, snapshot: previewSnapshot)
        inspectedCard = state == .fullHandInspection ? previewSnapshot.human?.zones.hand.first : nil
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
                let deckError = current.deckErrors.flatMap { errors in
                    errors.isEmpty ? nil : CommanderDeckValidationError.summarizedMessage(for: errors)
                }
                throw MagicMobileError.server(deckError ?? current.error ?? "XMage game start failed.")
            }

            try await Task.sleep(nanoseconds: 650_000_000)
        }

        throw MagicMobileError.server("XMage took too long to create the table. Check the bridge and try again.")
    }

    private func run(action: LegalAction) async {
        #if DEBUG
        if snapshot?.source == "design-preview" {
            status = "Development fixture: captured \(action.label). No engine command sent."
            print(status)
            return
        }
        #endif
        guard pendingActionId == nil else { return }
        guard let api else {
            errorMessage = MagicMobileError.invalidServerURL.localizedDescription
            status = MagicMobileError.invalidServerURL.localizedDescription
            return
        }
        guard let currentSnapshot = snapshot else { return }
        guard !currentSnapshot.isCompleted else {
            GameHaptics.warning()
            status = "This game is complete. Start a new game to keep playing."
            return
        }

        let currentSignature = snapshotSignature(currentSnapshot)
        if lastSubmittedActionId == action.id, lastSubmittedSnapshotSignature == currentSignature {
            return
        }

        pendingActionId = action.id
        pendingCardInstanceId = action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId
        lastActionRejection = nil
        if ["cast_spell", "play_land"].contains(action.type) {
            pendingCastAction = action
            pendingCastBeforeSnapshot = currentSnapshot
        }
        lastSubmittedActionId = action.id
        lastSubmittedSnapshotSignature = currentSignature
        status = "Sending \(action.shortLabel ?? action.label)"
        GameHaptics.impact()

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
            logCastSubmissionError(action: action, before: currentSnapshot, error: error)
            handleCommandError(error)
        }
    }

    private func run(command: GameCommand, label: String, pendingId: String) async {
        #if DEBUG
        if snapshot?.source == "design-preview" {
            let identity = command.abilityId.map { " [\($0)]" } ?? ""
            status = "Development fixture: captured \(label)\(identity). No engine command sent."
            print(status)
            return
        }
        #endif
        guard pendingActionId == nil else { return }
        guard let api else {
            errorMessage = MagicMobileError.invalidServerURL.localizedDescription
            status = MagicMobileError.invalidServerURL.localizedDescription
            return
        }
        guard let currentSnapshot = snapshot else { return }
        guard !currentSnapshot.isCompleted else {
            GameHaptics.warning()
            status = "This game is complete. Start a new game to keep playing."
            return
        }

        let currentSignature = snapshotSignature(currentSnapshot)
        if lastSubmittedActionId == pendingId, lastSubmittedSnapshotSignature == currentSignature {
            return
        }

        pendingActionId = pendingId
        pendingCardInstanceId = command.cardInstanceId ?? command.sourceInstanceId
        lastActionRejection = nil
        lastSubmittedActionId = pendingId
        lastSubmittedSnapshotSignature = currentSignature
        status = "Sending \(label)"
        GameHaptics.impact()

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
            handleCommandError(error)
        }
    }

    private func handleCommandError(_ error: Error) {
        GameHaptics.warning()
        if case MagicMobileError.actionRejected(let rejection) = error {
            if let rejectedSnapshot = rejection.snapshot {
                applySnapshot(rejectedSnapshot)
            }
            let notice = ActionRejectionNotice(rejection: rejection)
            lastActionRejection = notice
            status = notice.message
            clearPendingAction()
            return
        }
        errorMessage = error.localizedDescription
        status = error.localizedDescription
        clearPendingAction()
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

    private func resumeSavedGameIfNeeded() async {
        guard snapshot == nil, !activeGameId.isEmpty else { return }
        await resumeGame(gameId: activeGameId, surfaceErrors: false)
    }

    private func resumeCurrentGame() async {
        let gameId = snapshot?.id ?? activeGameId
        guard !gameId.isEmpty else {
            status = "No active XMage game to reconnect"
            return
        }
        await resumeGame(gameId: gameId, surfaceErrors: true)
    }

    private func resumeGame(gameId: String, surfaceErrors: Bool) async {
        guard let api else {
            status = MagicMobileError.invalidServerURL.localizedDescription
            return
        }

        liveUpdateStatus = "Resuming"
        status = "Restoring the latest XMage game state"
        do {
            let resumed = try await api.resumeGame(gameId: gameId)
            applySnapshot(resumed)
            screen = .play
            status = "XMage game resumed"
            startWebSocket(gameId: resumed.id)
        } catch MagicMobileError.gameExpired(let message) {
            activeGameId = ""
            activeGameServerURL = ""
            liveUpdateStatus = "Game expired"
            status = message
            if surfaceErrors { errorMessage = message }
        } catch {
            liveUpdateStatus = "Reconnect available"
            status = error.localizedDescription
            if surfaceErrors { errorMessage = error.localizedDescription }
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
        MagicMobileWebSocketEndpoint.url(gameId: gameId, httpBaseURL: baseURL)
    }

    private func snapshotSignature(_ snapshot: GameSnapshot) -> String {
        let legalActionIds = snapshot.legalActions?.map(\.id).joined(separator: ",") ?? ""
        let handCounts = snapshot.players.map { "\($0.playerId):\($0.zones.visibleHandCount):\($0.zones.battlefield.count):\($0.zones.graveyard.count)" }.joined(separator: "|")
        return "\(snapshot.id)|\(snapshot.bridgeRevision ?? -1)|\(snapshot.xmageCycle ?? -1)|\(snapshot.turn)|\(snapshot.phase)|\(snapshot.step ?? "")|\(snapshot.priorityPlayerId ?? "")|\(snapshot.promptText ?? "")|\(handCounts)|\(legalActionIds)"
    }

    private func applySnapshot(_ nextSnapshot: GameSnapshot) {
        guard shouldAcceptSnapshot(nextSnapshot) else { return }
        let changedFromSubmittedSnapshot = lastSubmittedSnapshotSignature.map { snapshotSignature(nextSnapshot) != $0 } ?? false
        snapshot = nextSnapshot
        if !nextSnapshot.id.hasPrefix("design-preview-") {
            activeGameId = nextSnapshot.id
            activeGameServerURL = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        selectedCard = nil
        if let pendingCastAction, let pendingCastBeforeSnapshot,
           CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: pendingCastAction, before: pendingCastBeforeSnapshot, after: nextSnapshot) {
            return
        }
        if pendingActionId != nil && (nextSnapshot.pendingStatus != "waiting_for_xmage" || changedFromSubmittedSnapshot) {
            clearPendingAction()
        }
        maybeAutoResolveAfterPayment(nextSnapshot)
    }

    /// When the human finishes paying for a spell/ability (manaPayment goes from
    /// active to inactive), automatically pass priority so it resolves — no hunting
    /// for PASS. Manual PASS still works if this is skipped (e.g. a follow-up prompt).
    private func maybeAutoResolveAfterPayment(_ nextSnapshot: GameSnapshot) {
        let active = nextSnapshot.manaPayment?.active == true
        defer { manaPaymentWasActive = active }
        guard manaPaymentWasActive, !active else { return }
        guard pendingActionId == nil else { return }
        guard nextSnapshot.promptEnvelopeV2 == nil else { return }
        guard nextSnapshot.isViewer(nextSnapshot.priorityPlayerId) || nextSnapshot.isViewer(nextSnapshot.waitingOnPlayerId) else { return }
        guard let pass = (nextSnapshot.legalActions ?? []).first(where: { $0.type == "pass_priority" }) else { return }
        Task { await run(action: pass) }
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
        let handCount = snapshot.human?.zones.visibleHandCount ?? 0
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
    case settings = "Settings"
    case play = "Play"
}

struct HeaderBar: View {
    let screen: AppScreen
    let status: String
    let isLoading: Bool
    let menu: () -> Void
    let settings: () -> Void

    private var isHealthy: Bool {
        let value = status.lowercased()
        return value.contains("ready") || value.contains("healthy") || value.contains("connected") || value.contains("resumed") || value.hasPrefix("ok")
    }

    private var connectionLabel: String {
        if isLoading { return "Connecting" }
        return isHealthy ? "Connected" : "Server status"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: menu) {
                HStack(spacing: 9) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MagicPalette.antiqueGold)
                    Text("MagicMobile")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .lineLimit(1)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("MagicMobile home")

            Spacer()

            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MagicPalette.antiqueGold)
                } else {
                    Circle()
                        .fill(isHealthy ? MagicPalette.emerald : MagicPalette.warningAmber)
                        .frame(width: 8, height: 8)
                }
                Text(connectionLabel)
                    .lineLimit(1)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(.black.opacity(0.46), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.borderBronze.opacity(0.45)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connection status: \(status)")

            Button(action: settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(screen == .settings ? MagicPalette.antiqueGold : .white.opacity(0.88))
            }
            .buttonStyle(MagicIconButtonStyle(compact: true))
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
    }
}

/// Shared home presentation used by the native game and the development preview.
struct TavernMainMenu: View {
    let deckName: String
    let playerName: String
    let play: () -> Void
    let decks: () -> Void
    let settings: () -> Void
    var news: (() -> Void)? = nil
    var commanderName: String? = nil
    var commanderNamespace: Namespace.ID? = nil
    var downloads: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let horizontal = proxy.size.width > proxy.size.height && !dynamicTypeSize.isAccessibilitySize
            let cardWidth = horizontal ? min(190, proxy.size.height * 0.42) : min(210, proxy.size.width * 0.53)
            let layout = horizontal ? AnyLayout(HStackLayout(alignment: .center, spacing: 48)) : AnyLayout(VStackLayout(spacing: 28))
            ScrollView(.vertical, showsIndicators: false) {
                layout {
                    VStack(spacing: 18) {
                        if !horizontal { identity(compact: false) }
                        CommanderDeckPortrait(name: commanderName, namespace: commanderNamespace)
                            .frame(width: cardWidth, height: cardWidth / 0.716)
                            .rotationEffect(.degrees(reduceMotion ? 0 : -4))
                            .padding(.vertical, 8)
                        deckTile
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 12) {
                        if horizontal { identity(compact: true).padding(.bottom, 14) }
                        Button(action: play) {
                            HStack(spacing: 16) {
                                Text("Play Commander")
                                    .font(.title3.weight(.bold))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CommanderActionStyle())
                        .accessibilityIdentifier("menu.play")
                        Button(action: decks) {
                            HStack(spacing: 16) {
                                Image(systemName: "rectangle.stack")
                                Text("Decks")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CommanderActionStyle(primary: false))
                        .accessibilityIdentifier("menu.decks")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { utilityActions }
                            VStack(alignment: .leading, spacing: 0) { utilityActions }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: 400)
                }
                .padding(.horizontal, horizontal ? 36 : 26)
                .padding(.vertical, horizontal ? 24 : 28)
                .frame(maxWidth: 960, minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
            }
        }
        .background(CommanderPresentation.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { appeared = true }
        }
    }

    private func identity(compact: Bool) -> some View {
        VStack(alignment: compact ? .leading : .center, spacing: 8) {
            Text("MAGICMOBILE")
                .font(.caption.weight(.bold)).tracking(3)
                .foregroundStyle(CommanderPresentation.secondary)
            Text("Your next\ngreat game.")
                .font(.system(.largeTitle, design: .default, weight: .black))
                .tracking(-1)
                .foregroundStyle(CommanderPresentation.ink)
                .multilineTextAlignment(compact ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Welcome back, \(playerName)")
                    .font(.subheadline).foregroundStyle(CommanderPresentation.secondary)
                    .multilineTextAlignment(compact ? .leading : .center)
            }
        }
    }

    private var deckTile: some View {
        VStack(spacing: 5) {
            Text("YOUR DECK")
                .font(.caption2.weight(.bold)).tracking(2)
                .foregroundStyle(CommanderPresentation.accent)
            Text(deckName)
                .font(.title3.weight(.bold))
                .foregroundStyle(CommanderPresentation.ink)
            if let commanderName, !commanderName.isEmpty {
                Text(commanderName).font(.caption)
                    .foregroundStyle(CommanderPresentation.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(commanderName.map { "Your deck: \(deckName), commander \($0)" } ?? "Your deck: \(deckName)")
    }

    @ViewBuilder private var utilityActions: some View {
        Button(action: settings) {
            Label("Settings", systemImage: "gearshape")
                .font(.footnote).frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(CommanderPresentation.secondary)
        .accessibilityIdentifier("menu.settings")
        if let news {
            Button(action: news) {
                Label("Updates", systemImage: "arrow.down.circle")
                    .font(.footnote).frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CommanderPresentation.secondary)
            .accessibilityIdentifier("menu.updates")
        }
        if let downloads {
            Button(action: downloads) {
                Label("Downloads", systemImage: "externaldrive")
                    .font(.footnote).frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CommanderPresentation.secondary)
            .accessibilityIdentifier("menu.downloads")
        }
    }
}

/// One spelling for each stored appearance, with a deliberate fallback. An unrecognised
/// stored value previously fell through to "midnight" by accident rather than returning
/// to the real default.
enum BoardAppearancePreference {
    static let key = "magicmobile.boardAppearance"
    static let defaultValue = "arena"
    static let options = BattlefieldBackdrop.allCases.map(\.rawValue)
    static func normalized(_ value: String) -> String { options.contains(value) ? value : defaultValue }
}

enum MenuAppearancePreference {
    static let key = "magicmobile.menuAppearance"
    static let defaultValue = "tavern"
    static let options = ["tavern", "arena", "midnight"]
    static func normalized(_ value: String) -> String { options.contains(value) ? value : defaultValue }
}

struct BoardAppearancePicker: View {
    @AppStorage(BoardAppearancePreference.key) private var appearance = BoardAppearancePreference.defaultValue
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battlefield").font(.headline).foregroundStyle(MagicPalette.parchment)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(BattlefieldBackdrop.allCases) { theme in
                    choice(theme.title, value: theme.rawValue)
                }
            }
            Text("Works in portrait and landscape.")
                .font(.caption).foregroundStyle(MagicPalette.parchment.opacity(0.65))
        }
    }
    private func choice(_ title: String, value: String) -> some View {
        Button { appearance = value } label: {
            AppearanceSwatch(title: title, selected: appearance == value) {
                BoardAppearanceArt(value: value)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " battlefield")
        .accessibilityAddTraits(appearance == value ? .isSelected : [])
    }
}

/// The menu had no equivalent control: its background was hard-coded while the board's
/// was selectable, so the two surfaces could never be made to agree.
struct MenuAppearancePicker: View {
    @AppStorage(MenuAppearancePreference.key) private var appearance = MenuAppearancePreference.defaultValue
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu").font(.headline).foregroundStyle(MagicPalette.parchment)
            HStack(spacing: 12) {
                choice("Tavern", value: "tavern")
                choice("Stone Arena", value: "arena")
                choice("Midnight", value: "midnight")
            }
            Text("Saved on this device. The battlefield keeps its own setting.")
                .font(.caption).foregroundStyle(MagicPalette.parchment.opacity(0.65))
        }
    }
    private func choice(_ title: String, value: String) -> some View {
        Button { appearance = value } label: {
            AppearanceSwatch(title: title, selected: appearance == value) {
                MenuAppearanceArt(value: value)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " menu background")
        .accessibilityAddTraits(appearance == value ? .isSelected : [])
    }
}

private struct AppearanceSwatch<Art: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder let art: Art
    var body: some View {
        // Each swatch takes an equal share of the row. Aspect-filled artwork otherwise
        // claimed width from its neighbours, squeezing the gradient option to a sliver
        // and truncating the labels beside it.
        VStack(spacing: 8) {
            // A resizable image still reports a large ideal width, which wins the HStack's
            // space. Letting an empty container own the size and drawing the art inside it
            // keeps every swatch identical regardless of what it shows.
            Color.clear
                .frame(maxWidth: .infinity).frame(height: 68)
                .overlay { art }
                .clipped().clipShape(RoundedRectangle(cornerRadius: GameBoardDesignTokens.current.radius.panel))
            HStack(spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? MagicPalette.antiqueGold : .white.opacity(0.15), lineWidth: 2))
        .foregroundStyle(MagicPalette.parchment)
    }
}

/// Swatches render the same art the surfaces do, so a preview cannot drift from reality.
struct BoardAppearanceArt: View {
    let value: String
    var body: some View {
        BattlefieldBackdropArt(theme: .resolved(value))
    }
}

struct MenuAppearanceArt: View {
    let value: String
    var body: some View {
        switch value {
        case "arena": Image(MagicMobileAssetName.stoneArena).resizable().scaledToFill()
        case "midnight": MidnightSurfaceGradient()
        default: Image(MagicMobileAssetName.menuBackground).resizable().scaledToFill()
        }
    }
}

struct MidnightSurfaceGradient: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.055, green: 0.085, blue: 0.10), Color(red: 0.10, green: 0.16, blue: 0.16)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct AppearanceSettingsView: View {
    @Binding var portraitModeEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeTurnControl) private var nativeTurnControl
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if nativeTurnControl != nil { NativeArtworkPreferenceView() }
                    BoardAppearancePicker()
                    PortraitModeToggle(isOn: $portraitModeEnabled)
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.08, green: 0.07, blue: 0.065))
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct MenuView: View {
    @AppStorage(PortraitModePreference.key) private var autoRotate = true
    @State private var showAppearance = false
    let startSetup: () -> Void
    let openDecks: () -> Void
    let openSettings: () -> Void
    let quickStart: () -> Void
    let resumeGame: () -> Void
    @Binding var playerDisplayName: String
    @Binding var selectedHumanPrecon: PreconDeck
    let deckSummary: String
    let difficulty: AiDifficulty
    let hasActiveGame: Bool
    let portraitModeEnabled: Bool
    let cardCacheMetadata: CardCacheMetadata?
    let isSyncingCardCache: Bool
    let phoneImageCacheCount: Int
    let phoneInspectionImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let phoneImageDownloadProgress: String?

    var body: some View {
        TavernMainMenu(deckName: selectedHumanPrecon.name, playerName: playerDisplayName,
                       play: startSetup, decks: openDecks, settings: {
                           #if DEBUG
                           if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] == "menu" { showAppearance = true; return }
                           #endif
                           openSettings()
                       })
            .sheet(isPresented: $showAppearance) { AppearanceSettingsView(portraitModeEnabled: $autoRotate) }
    }

    private var playerNameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PLAYER")
                .font(.caption2.weight(.black))
                .foregroundStyle(MagicPalette.antiqueGold)
            TextField("Enter player name", text: $playerDisplayName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .textFieldStyle(GameTextFieldStyle())
                .accessibilityLabel("Player name")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var deckSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SELECTED DECK")
                .font(.caption2.weight(.black))
                .foregroundStyle(MagicPalette.antiqueGold)
            PreconPicker(title: "Commander deck", selection: $selectedHumanPrecon)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func playCommanderButton(compact: Bool) -> some View {
        Button(action: startSetup) {
            Label("PLAY COMMANDER", systemImage: "shield.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MagicPrimaryButtonStyle(fillsWidth: true, compact: compact))
        .accessibilityHint("Opens guided game setup")
    }

    private func quickBattleButton(compact: Bool) -> some View {
        Button(action: quickStart) {
            Label("Quick Battle", systemImage: "bolt.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: compact))
        .accessibilityHint("Starts immediately with the current selections")
    }

    private var assetSummary: some View {
        let status = CardAssetDownloadStatus(
            metadataStatus: cardCacheMetadata?.status,
            serverImageCount: cardCacheMetadata?.imageCount ?? 0,
            serverSymbolCount: cardCacheMetadata?.symbolCount ?? 0,
            phoneImageCount: phoneImageCacheCount,
            phoneInspectionImageCount: phoneInspectionImageCacheCount,
            phoneSymbolCount: phoneSymbolCacheCount,
            isSyncing: isSyncingCardCache,
            progress: phoneImageDownloadProgress
        )
        return Button(action: openSettings) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill")
                    .foregroundStyle(MagicPalette.antiqueGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GAME ASSETS")
                        .font(.caption.weight(.black))
                    Text(status.summary)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer()
                Text(status.stateLabel.capitalized)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(status.stateColor)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .frame(minHeight: 52)
            .magicPanel(.iron, prominence: .quiet, cornerRadius: 10, padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Game assets, \(status.stateLabel). \(status.summary)")
        .accessibilityHint("Opens asset settings")
    }
}

struct NavigationTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Text(title.uppercased())
                    .font(.system(.headline, design: .serif, weight: .bold))
                    .foregroundStyle(MagicPalette.parchment)
                Image(systemName: systemImage)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .magicPanel(.leather, prominence: .standard, cornerRadius: 12, padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct PortraitModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Rotate")
                    .font(.callout.weight(.black))
                    .foregroundStyle(.white)
                Text("Portrait and landscape")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
        }
        .toggleStyle(.switch)
        .tint(GameBoardTheme.current.emeraldPriority)
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 10)
    }
}

struct CardCachePanel: View {
    let metadata: CardCacheMetadata?
    let isSyncing: Bool
    let phoneImageCacheCount: Int
    let phoneInspectionImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let downloadProgress: String?
    let sync: () -> Void

    private var downloadStatus: CardAssetDownloadStatus {
        CardAssetDownloadStatus(
            metadataStatus: metadata?.status,
            serverImageCount: metadata?.imageCount ?? 0,
            serverSymbolCount: metadata?.symbolCount ?? 0,
            phoneImageCount: phoneImageCacheCount,
            phoneInspectionImageCount: phoneInspectionImageCacheCount,
            phoneSymbolCount: phoneSymbolCacheCount,
            isSyncing: isSyncing,
            progress: downloadProgress
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(GameBoardTheme.current.antiqueGold)
                Text("Game Assets")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text(downloadStatus.stateLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(downloadStatus.stateColor)
            }

            Text(downloadStatus.summary)
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
                    Text(downloadStatus.buttonTitle)
                }
            }
            .buttonStyle(MagicSecondaryButtonStyle(compact: true))
            .disabled(isSyncing || downloadStatus.isComplete)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .magicPanel(.leather, prominence: .standard, cornerRadius: 12, padding: 16)
    }
}

struct SettingsView: View {
    @Binding var serverURLText: String
    @Binding var portraitModeEnabled: Bool
    let status: String
    let cardCacheMetadata: CardCacheMetadata?
    let isSyncingCardCache: Bool
    let phoneImageCacheCount: Int
    let phoneInspectionImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let phoneImageDownloadProgress: String?
    let syncCardCache: () -> Void
    let checkBridge: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SETTINGS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                    Text("Your game, your table")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("Connection, orientation, and downloaded card assets live here so the home screen stays focused on play.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                }

                Panel(title: "XMage Server") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SERVER URL")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(MagicPalette.antiqueGold)
                        TextField("https://your-xmage-server.example", text: $serverURLText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textFieldStyle(GameTextFieldStyle())
                            .accessibilityLabel("XMage server URL")
                    }

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "network")
                            .foregroundStyle(MagicPalette.antiqueGold)
                        Text(status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }

                    Button(action: checkBridge) {
                        Label("Check XMage Bridge", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true))
                }

                Panel(title: "Display") {
                    MenuAppearancePicker()
                    BoardAppearancePicker()
                    PortraitModeToggle(isOn: $portraitModeEnabled)
                    Text("When enabled, gameplay and menus automatically adapt between portrait and landscape on iPhone.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                CardCachePanel(
                    metadata: cardCacheMetadata,
                    isSyncing: isSyncingCardCache,
                    phoneImageCacheCount: phoneImageCacheCount,
                    phoneInspectionImageCacheCount: phoneInspectionImageCacheCount,
                    phoneSymbolCacheCount: phoneSymbolCacheCount,
                    downloadProgress: phoneImageDownloadProgress,
                    sync: syncCardCache
                )
                .frame(minHeight: 178)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 18)
        }
    }
}

struct CardAssetDownloadStatus: Equatable {
    let metadataStatus: String?
    let serverImageCount: Int
    let serverSymbolCount: Int
    let phoneImageCount: Int
    let phoneInspectionImageCount: Int
    let phoneSymbolCount: Int
    let isSyncing: Bool
    let progress: String?

    var isComplete: Bool {
        guard metadataStatus == "ready", serverImageCount > 0 else { return false }
        return phoneImageCount >= serverImageCount &&
            phoneInspectionImageCount >= serverImageCount &&
            phoneSymbolCount >= serverSymbolCount
    }

    var hasNewAssets: Bool {
        guard metadataStatus == "ready", serverImageCount > 0 else { return false }
        return phoneImageCount < serverImageCount ||
            phoneInspectionImageCount < serverImageCount ||
            phoneSymbolCount < serverSymbolCount
    }

    var stateLabel: String {
        if isSyncing {
            return "DOWNLOADING"
        }
        if isComplete {
            return "ALL DOWNLOADED"
        }
        if hasNewAssets {
            return "NEW ASSETS"
        }
        return metadataStatus?.uppercased() ?? "EMPTY"
    }

    var buttonTitle: String {
        if isSyncing {
            let suffix = progress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return suffix.isEmpty ? "Downloading images" : "Downloading \(suffix)"
        }
        if isComplete {
            return "All assets downloaded"
        }
        if hasNewAssets {
            return "Download new assets"
        }
        return "Download cards + symbols"
    }

    var stateColor: Color {
        if isComplete {
            return .green
        }
        if hasNewAssets || isSyncing {
            return MagicPalette.warningAmber
        }
        return .orange
    }

    var summary: String {
        guard metadataStatus != nil else {
            return "Download the full Scryfall image pack onto this iPhone so gameplay renders cards locally."
        }
        if metadataStatus == "ready" {
            return "Phone cache: \(phoneImageCount)/\(serverImageCount) cards, \(phoneInspectionImageCount)/\(serverImageCount) inspection, \(phoneSymbolCount)/\(serverSymbolCount) symbols."
        }
        return "Phone cache: \(phoneImageCount) cards, \(phoneInspectionImageCount) inspection, \(phoneSymbolCount) symbols. Scryfall index status: \(metadataStatus ?? "unknown")."
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

enum CommanderSetupStep: Int, CaseIterable, Identifiable {
    case player
    case opponent
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .player: return "Player & Deck"
        case .opponent: return "Opponent"
        case .review: return "Review"
        }
    }

    var heading: String {
        switch self {
        case .player: return "Choose your deck"
        case .opponent: return "Choose your opponent"
        case .review: return "Ready for battle"
        }
    }

    var subtitle: String {
        switch self {
        case .player: return "Select the Commander deck you will lead into battle."
        case .opponent: return "Choose the AI deck and the challenge you want."
        case .review: return "Confirm the table before XMage begins the match."
        }
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
    let portraitModeEnabled: Bool
    let cardCacheMetadata: CardCacheMetadata?
    let isSyncingCardCache: Bool
    let phoneImageCacheCount: Int
    let phoneInspectionImageCacheCount: Int
    let phoneSymbolCacheCount: Int
    let phoneImageDownloadProgress: String?
    let syncCardCache: () -> Void
    let checkBridge: () -> Void
    let openDecks: () -> Void
    let startGame: () -> Void
    let startFixtureGame: () -> Void
    @State private var step: CommanderSetupStep = .player

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = GameOrientationMode.isPortraitLayout(size: proxy.size, portraitEnabled: portraitModeEnabled)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: isPortrait ? 14 : 10) {
                    HStack(spacing: 9) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(MagicPalette.antiqueGold)
                        Text("PLAY COMMANDER")
                            .font(.system(.headline, design: .serif, weight: .bold))
                            .foregroundStyle(MagicPalette.parchment)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    setupProgress

                    VStack(spacing: 14) {
                        VStack(spacing: 5) {
                            Text("STEP \(step.rawValue + 1) OF \(CommanderSetupStep.allCases.count)")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(MagicPalette.antiqueGold)
                            Text(step.heading)
                                .font(.system(size: isPortrait ? 28 : 25, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(step.subtitle)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.white.opacity(0.66))
                                .multilineTextAlignment(.center)
                        }

                        stepContent(isPortrait: isPortrait)
                        setupActions
                    }
                    .magicPanel(.leather, prominence: .elevated, cornerRadius: 14, padding: isPortrait ? 16 : 14)
                }
                .frame(maxWidth: isPortrait ? .infinity : 840)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 18)
            }
        }
    }

    private var setupProgress: some View {
        HStack(spacing: 0) {
            ForEach(CommanderSetupStep.allCases) { item in
                HStack(spacing: 0) {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(item.rawValue <= step.rawValue ? MagicPalette.antiqueGold.opacity(0.92) : MagicPalette.iron.opacity(0.92))
                                .frame(width: 34, height: 34)
                            Circle()
                                .stroke(item == step ? MagicPalette.parchment : MagicPalette.borderBronze.opacity(0.55), lineWidth: item == step ? 2 : 1)
                                .frame(width: 34, height: 34)
                            if item.rawValue < step.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(MagicPalette.iron)
                            } else {
                                Text("\(item.rawValue + 1)")
                                    .font(.callout.weight(.black))
                                    .foregroundStyle(item.rawValue <= step.rawValue ? MagicPalette.iron : .white.opacity(0.72))
                            }
                        }
                        Text(item.title)
                            .font(.caption2.weight(item == step ? .black : .semibold))
                            .foregroundStyle(item == step ? MagicPalette.antiqueGold : .white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Step \(item.rawValue + 1), \(item.title)\(item == step ? ", current" : "")")

                    if item != .review {
                        Rectangle()
                            .fill(item.rawValue < step.rawValue ? MagicPalette.antiqueGold : MagicPalette.borderIron)
                            .frame(height: 2)
                            .frame(maxWidth: 44)
                            .offset(y: -10)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func stepContent(isPortrait: Bool) -> some View {
        switch step {
        case .player:
            playerStep(isPortrait: isPortrait)
        case .opponent:
            opponentStep(isPortrait: isPortrait)
        case .review:
            reviewStep
        }
    }

    private func playerStep(isPortrait: Bool) -> some View {
        VStack(spacing: 12) {
            if isPortrait {
                VStack(spacing: 10) {
                    playerIdentity
                    PreconPicker(title: "Your Commander deck", selection: $selectedHumanPrecon)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    playerIdentity
                    PreconPicker(title: "Your Commander deck", selection: $selectedHumanPrecon)
                }
            }

            Text(deckSummary)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: openDecks) {
                Label("Import or build a deck", systemImage: "rectangle.stack.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true))
        }
    }

    private var playerIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PLAYER")
                .font(.caption2.weight(.black))
                .foregroundStyle(MagicPalette.antiqueGold)
            TextField("Enter player name", text: $playerDisplayName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .textFieldStyle(GameTextFieldStyle())
                .accessibilityLabel("Player name")
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                AvatarPreview(data: avatarData)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose player portrait")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func opponentStep(isPortrait: Bool) -> some View {
        VStack(spacing: 14) {
            PreconPicker(title: "AI Commander deck", selection: $selectedAIPrecon)

            VStack(alignment: .leading, spacing: 8) {
                Text("AI DIFFICULTY")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isPortrait ? 2 : 4), spacing: 8) {
                    ForEach(AiDifficulty.allCases) { option in
                        DifficultyTile(difficulty: option, isSelected: difficulty == option) {
                            difficulty = option
                        }
                    }
                }
            }
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                ReviewRow(label: "Player", value: playerDisplayName.isEmpty ? "Player" : playerDisplayName)
                ReviewRow(label: "Deck", value: selectedHumanPrecon.name)
                ReviewRow(label: "Commander", value: selectedHumanPrecon.commander)
                ReviewRow(label: "Opponent", value: "\(selectedAIPrecon.name) • \(difficulty.menuLabel)")
            }
            .padding(12)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10)))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 7)], spacing: 7) {
                SetupRuleChip(title: "Format", value: "Commander")
                SetupRuleChip(title: "Players", value: "1v1 AI")
                SetupRuleChip(title: "Life", value: "40")
                SetupRuleChip(title: "Mulligan", value: "XMage")
                SetupRuleChip(title: "Start", value: "Prompt")
            }

            HStack(spacing: 10) {
                Image(systemName: "network")
                    .foregroundStyle(MagicPalette.antiqueGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("XMAGE SERVER")
                        .font(.caption2.weight(.black))
                    Text(URL(string: serverURLText)?.host ?? "Server not configured")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer()
                Button("Check", action: checkBridge)
                    .buttonStyle(MagicSecondaryButtonStyle(compact: true))
            }
            .padding(10)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10)))

            #if DEBUG
            Button("Start XMage gauntlet fixture", action: startFixtureGame)
                .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
            Text("Debug only. Requires ENABLE_XMAGE_FIXTURES=true and a non-production gateway.")
                .font(.caption2.weight(.bold))
                .foregroundStyle(MagicPalette.antiqueGold.opacity(0.82))
                .lineLimit(2)
            #endif
        }
    }

    private var setupActions: some View {
        HStack(spacing: 10) {
            if step != .player {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        step = CommanderSetupStep(rawValue: step.rawValue - 1) ?? .player
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true))
            }

            Button {
                if step == .review {
                    startGame()
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        step = CommanderSetupStep(rawValue: step.rawValue + 1) ?? .review
                    }
                }
            } label: {
                Label(step == .review ? "Start Battle" : "Continue", systemImage: step == .review ? "shield.fill" : "chevron.right")
                    .labelStyle(SetupActionLabelStyle(isFinal: step == .review))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MagicPrimaryButtonStyle(fillsWidth: true))
            .accessibilityHint(step == .review ? "Starts the XMage Commander game" : "Moves to the next setup step")
        }
    }
}

struct SetupActionLabelStyle: LabelStyle {
    let isFinal: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            if isFinal { configuration.icon }
            configuration.title
            if !isFinal { configuration.icon }
        }
    }
}

struct DifficultyTile: View {
    let difficulty: AiDifficulty
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch difficulty {
        case .easy: return "shield.fill"
        case .normal: return "bolt.shield.fill"
        case .hard: return "flame.fill"
        case .expert: return "crown.fill"
        }
    }

    private var subtitle: String {
        switch difficulty {
        case .easy: return "Learn the game"
        case .normal: return "Balanced fight"
        case .hard: return "For veterans"
        case .expert: return "No mercy"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(isSelected ? MagicPalette.iron : MagicPalette.antiqueGold)
                Text(difficulty.menuLabel)
                    .font(.callout.weight(.black))
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? MagicPalette.iron.opacity(0.72) : .white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isSelected ? MagicPalette.iron : .white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 94)
            .background(isSelected ? MagicPalette.antiqueGold : Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? MagicPalette.parchment : MagicPalette.borderBronze.opacity(0.46), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(difficulty.menuLabel), \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(MagicPalette.parchment.opacity(0.78))
            Spacer()
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
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
        .frame(maxWidth: .infinity)
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 8, padding: 8)
    }
}

struct DeckBuilderView: View {
    @Binding var deckText: String
    @Binding var deckSource: String
    let deckSummary: String
    let importDeck: () -> Void
    @Binding var selectedHumanPrecon: PreconDeck
    let portraitModeEnabled: Bool

    var body: some View {
        GeometryReader { proxy in
            if GameOrientationMode.isPortraitLayout(size: proxy.size, portraitEnabled: portraitModeEnabled) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        deckBuilderHeader
                        deckUploadPanel(textEditorHeight: 260)
                        currentDeckPanel
                    }
                    .padding(.bottom, 18)
                }
            } else {
                landscapeBody
            }
        }
    }

    private var landscapeBody: some View {
        HStack(spacing: 12) {
            VStack(spacing: 12) {
                deckBuilderHeader
                deckUploadPanel(textEditorHeight: nil)
            }
            currentDeckPanel
            .frame(width: 330)
        }
    }

    private var deckBuilderHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DECKS")
                .font(.caption.weight(.black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text("Build your spellbook")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("Import a Commander list or choose a battle-ready precon.")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.64))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deckUploadPanel(textEditorHeight: CGFloat?) -> some View {
        Panel(title: "Import Deck") {
            Text("Paste an exported text list from Archidekt or Moxfield. The first Commander entry becomes your command-zone card.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            TextField("Deck name, Archidekt URL, or Moxfield URL", text: $deckSource)
                .textInputAutocapitalization(.never)
                .textFieldStyle(GameTextFieldStyle())
                .accessibilityLabel("Deck name or source URL")
            TextEditor(text: $deckText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(8)
                .frame(height: textEditorHeight)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
                .accessibilityLabel("Commander deck list")
            HStack {
                Link("Archidekt", destination: URL(string: "https://archidekt.com/")!)
                    .buttonStyle(MagicSecondaryButtonStyle(compact: true))
                Link("Moxfield", destination: URL(string: "https://www.moxfield.com/")!)
                    .buttonStyle(MagicSecondaryButtonStyle(compact: true))
                Button("Import text", action: importDeck)
                    .buttonStyle(MagicPrimaryButtonStyle(compact: true))
            }
        }
    }

    private var currentDeckPanel: some View {
        Panel(title: "Current Deck") {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text(deckSummary)
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Use exported plain text from Archidekt or Moxfield. Direct scraping is intentionally avoided.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            PreconPicker(title: "Fallback precon", selection: $selectedHumanPrecon)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 10)
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
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 9)
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
    let lastActionRejection: ActionRejectionNotice?
    let liveUpdateStatus: String
    let onInteractionFeedback: (String) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let refreshGame: () -> Void
    let reconnectGame: () -> Void
    let checkBridgeHealth: () async -> EngineHealth?
    let newGame: () -> Void
    let quitGame: () -> Void
    let loadProtocolDebug: (String) async throws -> XmageProtocolDebug
    @Binding var portraitModeEnabled: Bool
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
            lastActionRejection: lastActionRejection,
            liveUpdateStatus: liveUpdateStatus,
            onInteractionFeedback: onInteractionFeedback,
            runAction: runAction,
            runCommand: runCommand,
            refreshGame: refreshGame,
            reconnectGame: reconnectGame,
            checkBridgeHealth: checkBridgeHealth,
            newGame: newGame,
            quitGame: quitGame,
            loadProtocolDebug: loadProtocolDebug,
            portraitModeEnabled: $portraitModeEnabled,
            viewZone: viewZone
        )
    }
}

@MainActor
private enum GameHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

private struct OpponentFocusMenu: View {
    let snapshot: GameSnapshot
    let selectOpponent: (String) -> Void

    var body: some View {
        if BoardOpponentFocus.opponents(in: snapshot).count > 1 {
            Menu {
                ForEach(BoardOpponentFocus.opponents(in: snapshot)) { player in
                    Button {
                        selectOpponent(player.playerId)
                    } label: {
                        Label(snapshot.playerLabel(player.playerId), systemImage: snapshot.opponent?.playerId == player.playerId ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .frame(width: 44, height: 44)
                    .background(MagicPalette.iron.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Choose opponent to view")
            .accessibilityValue(snapshot.playerLabel(snapshot.opponent?.playerId))
            .accessibilityHint("Changes the displayed opponent battlefield")
            .accessibilityIdentifier("board.opponentFocus")
        }
    }
}

struct NativeGameView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: GameSnapshot?
    let startupStatus: CommanderStartupResponse?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let playerDisplayName: String
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let lastActionRejection: ActionRejectionNotice?
    let liveUpdateStatus: String
    let onInteractionFeedback: (String) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let refreshGame: () -> Void
    let reconnectGame: () -> Void
    let checkBridgeHealth: () async -> EngineHealth?
    let newGame: () -> Void
    let quitGame: () -> Void
    let loadProtocolDebug: (String) async throws -> XmageProtocolDebug
    @Binding var portraitModeEnabled: Bool
    let viewZone: (String, [ZoneCard]) -> Void
    @State private var isLogOpen = false
    @State private var isGameMenuOpen = false
    @State private var isPromptInspectorOpen = false
    @State private var protocolDebug: XmageProtocolDebug?
    @State private var protocolDebugError: String?
    @State private var isProtocolDebugLoading = false
    @State private var gameMenuConfirmation: GameMenuConfirmation?
    @State private var isOverPlayerDropZone = false
    @State private var interactionState = GameBoardInteractionState.idle
    @State private var inspectingZoneTitle: String? = nil
    @State private var inspectingZoneCards: [ZoneCard] = []
    @State private var isPromptDetailOpen = false
    @State private var isCardChoiceOpen = false
    @State private var isLandscapeStackOpen = false
    @State private var inspectingZoneReference: BoardZoneReference?
    @State private var dragActionChoice: DragActionChoice?
    @State private var combatSelection = CombatSelectionState()
    @State private var combatPreviewArrows: [CombatArrow] = []
    @State private var focusedOpponentId: String?
    @State private var lastTurnCueKey: String?
    @State private var showsTurnCue = false
    @State private var aiWaitBeganAt = Date()
    @State private var aiWaitKey = ""
    @State private var didAutoRefreshAIWaitKey: String?
    @State private var didAutoReconnectAIWaitKey: String?
    @State private var didAutoDiagnoseAIWaitKey: String?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private func openPromptDetails() {
        if let snapshot, PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil {
            isCardChoiceOpen = true
        } else {
            isPromptDetailOpen = true
        }
    }

    private func localViewZone(title: String, cards: [ZoneCard]) {
        if title.hasPrefix("Enchanting "), let snapshot,
           let playerID = snapshot.players.first(where: { player in
               Set(ZoneCard.enchanting(playerID: player.playerId, cards: snapshot.players.flatMap { $0.zones.battlefield }).map(\.id)) == Set(cards.map(\.id))
           })?.playerId, !cards.isEmpty {
            inspectBoardZone(.playerEnchantments(playerID: playerID))
            return
        }
        inspectingZoneReference = nil
        inspectingZoneTitle = title
        inspectingZoneCards = cards
    }

    private func inspectBoardZone(_ reference: BoardZoneReference) {
        guard let snapshot else { return }
        inspectingZoneReference = reference
        inspectingZoneTitle = reference.title(in: snapshot)
        inspectingZoneCards = reference.cards(in: snapshot)
        inspectedCard = nil
    }

    private var boardOverlayTransition: AnyTransition {
        GameBoardMotion.reduced(accessibilityReduceMotion) ? .opacity : .scale.combined(with: .opacity)
    }

    private func clearBoardSelection() {
        guard selectedCard != nil || inspectedCard != nil else { return }
        selectedCard = nil
        inspectedCard = nil
        GameHaptics.selection()
        onInteractionFeedback("Selection cleared")
    }

    private func recover(from rejection: ActionRejectionNotice) {
        GameHaptics.impact()
        if rejection.category == .bridgeDisconnected {
            reconnectGame()
        } else {
            refreshGame()
        }
    }

    private func refreshProtocolDebug() async {
        guard let gameId = snapshot?.id else { return }
        isProtocolDebugLoading = true
        protocolDebugError = nil
        do {
            protocolDebug = try await loadProtocolDebug(gameId)
        } catch {
            protocolDebugError = error.localizedDescription
        }
        isProtocolDebugLoading = false
    }

    @ViewBuilder
    var body: some View {
        if let snapshot = snapshot.map({ BoardOpponentFocus.snapshot($0, selecting: focusedOpponentId) }),
           let human = snapshot.human, let opponent = snapshot.opponent {
            let humanName = snapshot.playerLabel(human.playerId)
            let opponentName = snapshot.playerLabel(opponent.playerId)
            let sideCombatHighlights = CombatHighlightSet(
                selection: combatSelection,
                actions: snapshot.legalActions ?? [],
                combatGroups: snapshot.xmage?.combat ?? []
            )
            GeometryReader { rootProxy in
                ZStack {
                    BattlefieldSurface(portraitModeEnabled: portraitModeEnabled)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: clearBoardSelection)

                    if GameOrientationMode.isPortraitLayout(size: rootProxy.size, portraitEnabled: portraitModeEnabled) {
                        portraitGameContent(
                            snapshot: snapshot,
                            human: human,
                            opponent: opponent,
                            humanName: humanName,
                            opponentName: opponentName,
                            sideCombatHighlights: sideCombatHighlights
                        )
                    } else {
                    HStack(spacing: 0) {
                    // LEFT COLUMN
                    VStack(alignment: .leading, spacing: 0) {
                        LandscapePlayerSummary(
                            name: opponentName,
                            player: opponent,
                            active: snapshot.activePlayerId == opponent.playerId,
                            opponentId: human.playerId,
                            combatTargetable: CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: sideCombatHighlights.defenderIds) != nil,
                            combatTargetAction: {
                                if let defenderId = CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: sideCombatHighlights.defenderIds) {
                                    submitAttackers(defenderId: defenderId, snapshot: snapshot)
                                }
                            }
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)

                        HStack(spacing: 4) {
                            PlayerZoneMenu(player: opponent, viewZone: localViewZone)
                            BoardPlayerEffects(player: opponent, attachments: BattlefieldAttachments.enchanting(playerID: opponent.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: localViewZone,
                                opponents: BoardOpponentFocus.opponents(in: snapshot), selectOpponent: { focusedOpponentId = $0 })
                        }

                        Spacer()

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 4) {
                            ManaPoolHUD(manaPool: human.manaPool, compact: true, grid: true,
                                payableSymbols: GameplayAffordances.floatingManaSymbols(in: snapshot, pendingActionID: pendingActionId),
                                payMana: { symbol in
                                    if pendingActionId == nil, let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                                        runCommand(command, "Spend floating {\(symbol)}", "floating-\(snapshot.promptEnvelopeV2?.id ?? "")-\(symbol)")
                                    }
                                })
                            LandscapePlayerSummary(name: humanName, player: human, active: snapshot.activePlayerId == human.playerId, opponentId: opponent.playerId)
                            HStack(spacing: 4) {
                                PlayerZoneMenu(player: human, viewZone: localViewZone, snapshot: snapshot, pendingActionID: pendingActionId)
                                BoardPlayerEffects(player: human, attachments: BattlefieldAttachments.enchanting(playerID: human.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: localViewZone)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 88)
                    .background(
                        LinearGradient(
                            colors: [MagicPalette.iron.opacity(0.96), MagicPalette.leather.opacity(0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(MagicPalette.antiqueGold.opacity(0.28))
                            .frame(width: 1)
                    }

                    // CENTER COLUMN
                    GeometryReader { proxy in
                        let metrics = BattlefieldLayoutMetrics(proxy: proxy,
                            centerControlsVisible: BoardDecisionPresentation.needsCenterSpace(snapshot, hasRejection: lastActionRejection != nil))
                        let targetableIds = GameBoardInteractionState.boardTargetableIds(for: snapshot)
                        let combatHighlights = CombatHighlightSet(
                            selection: combatSelection,
                            actions: snapshot.legalActions ?? [],
                            combatGroups: snapshot.xmage?.combat ?? []
                        )
                        let shouldShowCompactPrompt = CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId)
                        let derivedInteractionMode = GameBoardInteractionState.mode(
                            for: snapshot,
                            pendingActionId: pendingActionId,
                            selectedCard: selectedCard
                        )

                        ZStack {
                            BattlefieldRow(title: "Opponent board", cards: nonLandPermanents(opponent.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.opponentBattlefieldRect.width, adaptsToDensity: true, availableHeight: metrics.opponentBattlefieldRect.height, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                                .frame(width: metrics.opponentBattlefieldRect.width, height: metrics.opponentBattlefieldRect.height)
                                .position(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)

                            BattlefieldRow(title: "Opponent lands", cards: landPermanents(opponent.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.opponentLandsRect.width, adaptsToDensity: true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                                .frame(width: metrics.opponentLandsRect.width, height: metrics.opponentLandsRect.height)
                                .position(x: metrics.opponentLandsRect.midX, y: metrics.opponentLandsRect.midY)

                            Rectangle()
                                .fill(.white.opacity(0.13))
                                .frame(width: max(metrics.centerStripRect.width - 28, 80), height: 1.5)
                                .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

                            BattlefieldRow(title: "Your board", cards: nonLandPermanents(human.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.playerBattlefieldRect.width, adaptsToDensity: true, availableHeight: metrics.playerBattlefieldRect.height, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                                .frame(width: metrics.playerBattlefieldRect.width, height: metrics.playerBattlefieldRect.height)
                                .position(x: metrics.playerBattlefieldRect.midX, y: metrics.playerBattlefieldRect.midY)

                            BattlefieldRow(title: "Your lands", cards: landPermanents(human.zones.battlefield), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.playerLandsRect.width, adaptsToDensity: true, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                                .frame(width: metrics.playerLandsRect.width, height: metrics.playerLandsRect.height)
                                .position(x: metrics.playerLandsRect.midX, y: metrics.playerLandsRect.midY)

                            VStack(spacing: 4) {
                                HStack(spacing: 8) {
                                    if InlinePaymentPromptState.isActive(in: snapshot) {
                                        InlinePaymentPromptBar(
                                            snapshot: snapshot,
                                            pendingActionId: pendingActionId,
                                            runAction: runAction,
                                            runCommand: runCommand,
                                            openDetails: openPromptDetails
                                        )
                                        .frame(maxWidth: .infinity)
                                    } else if BoardDecisionPresentation.showsGuidance(snapshot) {
                                        PromptPill(snapshot: snapshot, combatSelection: combatSelection)
                                            .frame(maxWidth: .infinity)
                                    }

                                    let revealedCards = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
                                    let lookedAtCards = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
                                    if !revealedCards.isEmpty {
                                        FloatingZoneChip(title: "Revealed", count: revealedCards.count, icon: "eye") {
                                            inspectBoardZone(.collection(.revealed))
                                        }
                                    }
                                    if !lookedAtCards.isEmpty {
                                        FloatingZoneChip(title: "Looked", count: lookedAtCards.count, icon: "eye.trianglebadge.exclamationmark") {
                                            inspectBoardZone(.collection(.lookedAt))
                                        }
                                    }
                                }
                                if let lastActionRejection {
                                    ActionRejectionInlineView(notice: lastActionRejection) {
                                        recover(from: lastActionRejection)
                                    }
                                }
                            }
                            .frame(width: metrics.centerStripRect.width, height: max(InlinePaymentPromptState.isActive(in: snapshot) ? 52 : metrics.centerStripRect.height, lastActionRejection == nil ? metrics.centerStripRect.height : 66))
                            .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

                            if isOverPlayerDropZone {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(MagicPalette.antiqueGold.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(MagicPalette.antiqueGold.opacity(0.72), lineWidth: 2))
                                    .frame(width: metrics.playerDropZone.width, height: metrics.playerDropZone.height)
                                    .position(x: metrics.playerDropZone.midX, y: metrics.playerDropZone.midY)
                                    .allowsHitTesting(false)
                            }

                            PortraitHandRow(
                                cards: human.zones.hand,
                                legalActions: snapshot.legalActions ?? [],
                                selectedCard: $selectedCard,
                                inspectedCard: $inspectedCard,
                                pendingCardInstanceId: pendingCardInstanceId,
                                interactionState: $interactionState,
                                playerDropZone: metrics.playerDropZone,
                                isOverPlayerDropZone: $isOverPlayerDropZone,
                                cardWidth: metrics.handCardWidth,
                                cardHeight: metrics.handCardHeight,
                                rowWidth: metrics.handRect.width,
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



                            if TargetingHelperVisibility.shouldShow(snapshot: snapshot, pendingActionId: pendingActionId, mode: derivedInteractionMode, targetableIds: targetableIds) {
                                TargetingStatusPill(count: targetableIds.count)
                                    .position(x: metrics.bottomActionRect.midX, y: metrics.bottomActionRect.midY)
                                    .allowsHitTesting(false)
                            }

                            if CombatSelectionState.isDeclareAttackers(snapshot) {
                                let declaredAttackCount = snapshot.xmage?.combat.flatMap(\.attackers).count ?? 0
                                let hasPendingAttacker = !combatSelection.selectedAttackerIds.isEmpty
                                CombatSubmitPill(
                                    title: hasPendingAttacker ? "Cancel Selection" : (declaredAttackCount == 0 ? "No Attacks" : "Done Attacking"),
                                    count: max(declaredAttackCount, combatSelection.selectedAttackerIds.count)
                                ) {
                                    if hasPendingAttacker {
                                        combatSelection.clearAttackers()
                                    } else {
                                        finishAttackers(snapshot: snapshot)
                                    }
                                }
                                .position(x: metrics.bottomActionRect.midX, y: metrics.centerStripRect.maxY + 18)
                                .zIndex(19)
                            } else if CombatSelectionState.isDeclareBlockers(snapshot) {
                                let declaredBlockCount = snapshot.xmage?.combat.flatMap(\.blockers).count ?? 0
                                let hasPendingBlocker = combatSelection.selectedBlockerId != nil
                                CombatSubmitPill(
                                    title: hasPendingBlocker ? "Cancel Selection" : (declaredBlockCount == 0 ? "No Blocks" : "Done Blocking"),
                                    count: max(declaredBlockCount, combatSelection.blockerPairCount)
                                ) {
                                    if hasPendingBlocker {
                                        combatSelection.clearBlockers()
                                    } else if combatSelection.hasPendingBlockers {
                                        submitBlockers(snapshot: snapshot)
                                    } else {
                                        finishBlockers(snapshot: snapshot)
                                    }
                                }
                                .position(x: metrics.bottomActionRect.midX, y: metrics.centerStripRect.maxY + 18)
                                .zIndex(19)
                            }

                            // Floating Zone Inspector overlay
                            if let inspectingZoneTitle {
                                CompactZoneInspectorOverlay(
                                    title: inspectingZoneReference?.title(in: snapshot) ?? inspectingZoneTitle,
                                    cards: inspectingZoneReference?.cards(in: snapshot) ?? inspectingZoneCards,
                                    legalActions: snapshot.legalActions ?? [],
                                    pendingActionId: pendingActionId,
                                    selectedCard: $selectedCard,
                                    inspectedCard: $inspectedCard,
                                    runAction: runAction,
                                    closeAction: {
                                        self.inspectingZoneTitle = nil
                                        self.inspectingZoneCards = []
                                        self.inspectingZoneReference = nil
                                    },
                                    targetableIDs: targetableIds,
                                    runTargetAction: { submitTarget($0, snapshot: snapshot) },
                                    availableHeight: metrics.safeFrame.height
                                )
                                .position(x: metrics.safeFrame.midX, y: metrics.safeFrame.midY)
                                .transition(boardOverlayTransition)
                            }
                            if let inspectedCard {
                                Color.black.opacity(0.01)
                                    .ignoresSafeArea()
                                    .onTapGesture { self.inspectedCard = nil }
                                    .inspectionTouchPassthrough()
                                    .zIndex(99)
                                
                                CardInspector(card: inspectedCard)
                                    .inspectionTouchPassthrough()
                                    .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                                    .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                                    .zIndex(100)
                            }

                            if shouldShowCompactPrompt && !isPromptDetailOpen && CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty {
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
                                .transition(boardOverlayTransition)
                                .zIndex(20)
                            }

                            if let dragActionChoice {
                                DragActionChoicePopup(
                                    choice: dragActionChoice,
                                    pendingActionId: pendingActionId,
                                runAction: { action in
                                    self.dragActionChoice = nil
                                    selectedCard = nil
                                    runAction(action)
                                    },
                                cancel: {
                                    self.dragActionChoice = nil
                                    selectedCard = nil
                                    }
                                )
                                .frame(width: min(max(metrics.size.width * 0.30, 260), 340))
                                .position(x: metrics.boardColumnRect.midX, y: metrics.compactPromptRect.midY)
                                .transition(boardOverlayTransition)
                                .zIndex(21)
                            }
                        }
                        .coordinateSpace(name: "portrait-board")
                        .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
                            GeometryReader { geometry in
                                let bounds = anchors.mapValues { geometry[$0] }
                                if inspectingZoneTitle == nil && inspectedCard == nil {
                                    CombatArrowOverlay(snapshot: snapshot, groups: snapshot.xmage?.combat ?? [],
                                        previewArrows: combatPreviewArrows, metrics: metrics,
                                        humanBattlefield: human.zones.battlefield,
                                        opponentBattlefield: opponent.zones.battlefield, renderedBounds: bounds)
                                        .allowsHitTesting(false)
                                    CombatEdgeIndicators(cards: human.zones.battlefield + opponent.zones.battlefield,
                                        combatIDs: Set(CombatArrowModel.arrows(from: snapshot.xmage?.combat ?? [], previewArrows: combatPreviewArrows).flatMap { [$0.fromId, $0.toId] }),
                                        bounds: bounds,
                                        viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect],
                                        laneIndices: CombatViewportAnchors.laneIndices(human: human.zones.battlefield, opponent: opponent.zones.battlefield),
                                        inspect: { inspectedCard = $0 })
                                }
                            }
                        }
                        .onAppear {
                            interactionState.mode = derivedInteractionMode
                        }
                        .onChange(of: snapshot.combatSelectionResetKey) { _, _ in
                            combatSelection.resetIfInactive(snapshot)
                            combatPreviewArrows = []
                        }
                        .onChange(of: pendingActionId) { _, newValue in
                            if newValue == nil {
                                combatPreviewArrows = []
                            }
                        }
                    }

                    // RIGHT COLUMN
                    VStack(alignment: .trailing, spacing: 8) {
                        ScrollView(.vertical) {
                        VStack(spacing: 8) {
                        MagicPathPhaseRail(
                            snapshot: snapshot,
                            passAction: passAction(in: snapshot.legalActions ?? []),
                            yieldActions: GameplayActionPresentation.yieldActions(in: snapshot.legalActions ?? []),
                            logAction: { isLogOpen.toggle() },
                            settingsAction: { isGameMenuOpen = true },
                            runAction: runAction,
                            onlyPhases: true
                        )
                        .padding(.top, 12)

                        if pendingActionId == nil, let cue = BoardResponseCue.make(snapshot) {
                            BoardResponseBanner(cue: cue)
                        }

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.horizontal, 8)

                        GameLogAccessButton(entryCount: snapshot.log.count, openLog: { isLogOpen = true })
                            .padding(.horizontal, 8)

                        Button {
                            isLandscapeStackOpen = true
                        } label: {
                            Label("Stack · \(snapshot.stackTopFirst.count)", systemImage: "square.stack.3d.up")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel("Inspect stack")

                        if let xmageStack = snapshot.xmage?.stack, !xmageStack.isEmpty {
                            XmageStackPeek(
                                objects: snapshot.source == "xmage-ondevice" ? Array(xmageStack.reversed()) : xmageStack,
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
                        }
                        }

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.horizontal, 8)

                        GameplayActionDock(
                            snapshot: snapshot,
                            passAction: passAction(in: snapshot.legalActions ?? []),
                            yieldActions: GameplayActionPresentation.yieldActions(in: snapshot.legalActions ?? []),
                            pendingActionId: pendingActionId,
                            compact: true,
                            landscapeSidebar: true,
                            openPromptDetails: openPromptDetails,
                            openLog: { isLogOpen = true },
                            openSettings: { isGameMenuOpen = true },
                            runAction: runAction
                        )
                        .padding(.horizontal, LandscapeActionDockLayout.horizontalPadding)
                        .padding(.bottom, LandscapeActionDockLayout.bottomPadding)
                    }
                    .overlay(alignment: .center) {
                        if snapshot.isWaitingOnAIOrStalled {
                            AIWaitFallbackControls(
                                snapshot: snapshot,
                                pendingActionId: pendingActionId,
                                liveUpdateStatus: liveUpdateStatus,
                                beganAt: aiWaitBeganAt,
                                didRefresh: didAutoRefreshAIWaitKey == aiWaitKey,
                                didReconnect: didAutoReconnectAIWaitKey == aiWaitKey,
                                didDiagnose: didAutoDiagnoseAIWaitKey == aiWaitKey,
                                refreshAction: refreshGame,
                                reconnectAction: reconnectGame
                            )
                            .padding(.horizontal, 10)
                        }
                    }
                    .frame(width: LandscapeActionDockLayout.sidebarWidth(hasStack: !snapshot.stackTopFirst.isEmpty))
                    .background(
                        LinearGradient(
                            colors: [MagicPalette.iron.opacity(0.96), MagicPalette.leather.opacity(0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(MagicPalette.antiqueGold.opacity(0.28))
                            .frame(width: 1)
                    }
                }
                }

                if snapshot.isCompleted {
                    GameCompletionOverlay(
                        snapshot: snapshot,
                        newGame: newGame,
                        quitGame: quitGame
                    )
                    .transition(boardOverlayTransition)
                    .zIndex(500)
                }
                }
            }
                .background(Color(red: 0.055, green: 0.085, blue: 0.10).ignoresSafeArea())
                .preferredColorScheme(.dark)
                .overlay(alignment: .top) {
                    #if DEBUG
                    if snapshot.source == "design-preview" {
                        Text("DEVELOPMENT FIXTURE · NO ENGINE")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.yellow, in: Capsule()).allowsHitTesting(false)
                    }
                    #endif
                }
                .sheet(isPresented: $isLogOpen) {
                    GameLogDrawer(
                        log: snapshot.log,
                        close: { isLogOpen = false }
                    )
                    .padding(14)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isLandscapeStackOpen) {
                    BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                }
                .sheet(isPresented: $isPromptDetailOpen) {
                    UniversalPromptActionPanel(
                        snapshot: snapshot,
                        selectedCardActions: selectedCard.map { GameBoardInteractionState.cardActions(for: $0, actions: snapshot.legalActions ?? []) } ?? [],
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        pendingActionId: pendingActionId,
                        runAction: runAction,
                        runCommand: runCommand,
                        viewZone: { title, cards in
                            isPromptDetailOpen = false
                            localViewZone(title: title, cards: cards)
                        },
                        showsGameSurfaceSections: snapshot.promptEnvelopeV2 == nil
                    )
                    .id("\(snapshot.promptEnvelopeV2?.id ?? ""):\(snapshot.promptEnvelopeV2?.messageId ?? 0)")
                    .padding(14)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isGameMenuOpen) {
                    GameManagementMenu(
                        concedeAction: concedeAction(in: snapshot.legalActions ?? []),
                        runAction: runAction,
                        portraitModeEnabled: $portraitModeEnabled,
                        openPromptInspector: {
                            isGameMenuOpen = false
                            isPromptInspectorOpen = true
                        },
                        confirmStartNew: {
                            gameMenuConfirmation = .startNew
                        },
                        confirmQuit: {
                            gameMenuConfirmation = .quit
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isPromptInspectorOpen) {
                    PromptDebugInspector(
                        snapshot: snapshot,
                        liveUpdateStatus: liveUpdateStatus,
                        lastActionRejection: lastActionRejection,
                        protocolDebug: protocolDebug,
                        protocolDebugError: protocolDebugError,
                        isProtocolDebugLoading: isProtocolDebugLoading,
                        refreshProtocolDebug: { Task { await refreshProtocolDebug() } }
                    )
                        .task(id: snapshot.id) {
                            await refreshProtocolDebug()
                        }
                        .presentationDetents([.medium, .large])
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
            .environment(\.boardZoneInspectionAction, inspectBoardZone)
            .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: inspectingZoneTitle)
            .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: inspectedCard?.id)
            .onAppear {
                updateAIWaitStart(for: snapshot)
                isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil
                isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
            }
            .onChange(of: snapshot.id) { _, _ in
                focusedOpponentId = nil
                lastTurnCueKey = nil
                inspectingZoneTitle = nil
                inspectingZoneCards = []
                inspectingZoneReference = nil
                selectedCard = nil
                inspectedCard = nil
            }
            .onChange(of: snapshot.bridgeRevision) { _, _ in
                let cards = PortraitInteractionPolicy.authorizedCards(snapshot)
                if let card = inspectedCard { inspectedCard = cards.first { $0.id == card.id } }
                if let card = selectedCard { selectedCard = cards.first { $0.id == card.id } }
                if let reference = inspectingZoneReference, inspectingZoneTitle != nil {
                    inspectingZoneCards = reference.cards(in: snapshot)
                    inspectingZoneTitle = reference.title(in: snapshot)
                } else if inspectingZoneTitle != nil {
                    // Unscoped legacy inspections cannot safely infer zone membership.
                    inspectingZoneCards = []
                    inspectingZoneTitle = nil
                }
                if let choice = dragActionChoice, !choice.actions.allSatisfy({ old in
                    snapshot.legalActions?.contains(where: { $0.id == old.id && $0.messageId == old.messageId }) == true
                }) { dragActionChoice = nil }
            }
            .onChange(of: snapshot.promptEnvelopeV2?.id) { _, _ in
                isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
            }
            .onChange(of: PortraitInteractionPolicy.detailChoiceKey(snapshot)) { _, key in
                isPromptDetailOpen = key != nil
            }
            .onChange(of: PortraitInteractionPolicy.cardChoiceKey(snapshot)) { _, key in
                isCardChoiceOpen = key != nil
                inspectedCard = nil
                selectedCard = nil
                if key != nil { isPromptDetailOpen = false; isLandscapeStackOpen = false }
            }
            .accessibilityHidden(isCardChoiceOpen)
            .overlay {
                if isCardChoiceOpen, let key = PortraitInteractionPolicy.cardChoiceKey(snapshot), let prompt = snapshot.promptEnvelopeV2 {
                    BoardCardChoiceView(snapshot: snapshot, prompt: prompt, pendingActionId: pendingActionId,
                                        runCommand: runCommand, runAction: runAction, close: { isCardChoiceOpen = false })
                        .id(key)
                }
            }
            .onChange(of: selectedCard?.id) { _, _ in
                guard let card = selectedCard, pendingActionId == nil,
                      GameBoardInteractionState.boardTargetableIds(for: snapshot).isEmpty else { return }
                let actions = GameBoardInteractionState.cardActions(for: card, actions: snapshot.legalActions ?? [])
                if !actions.isEmpty {
                    dragActionChoice = DragActionChoice(message: card.card.name, actions: actions)
                }
            }
            .overlay {
                if showsTurnCue, let cue = BoardPhaseAnnouncement.make(snapshot), !isCardChoiceOpen, !isPromptDetailOpen {
                    VStack(spacing: 8) {
                        Text(cue.owner.uppercased()).font(.headline.weight(.semibold))
                            .foregroundStyle(MagicPalette.antiqueGold)
                        Text(cue.title).font(.system(size: 36, weight: .bold, design: .serif))
                            .multilineTextAlignment(.center).minimumScaleFactor(0.7)
                    }
                        .foregroundStyle(MagicPalette.parchment)
                        .padding(.horizontal, 28).padding(.vertical, 22)
                        .background(MagicPalette.iron.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(MagicPalette.antiqueGold.opacity(0.8), lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 20)
                        .padding(.horizontal, 24)
                        .transition(GameBoardMotion.reduced(accessibilityReduceMotion) ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("board.phase.announcement")
                }
            }
            .task(id: BoardPhaseAnnouncement.make(snapshot)?.key) {
                guard let key = BoardPhaseAnnouncement.make(snapshot)?.key, key != lastTurnCueKey else {
                    showsTurnCue = false
                    return
                }
                lastTurnCueKey = key
                withAnimation(.easeOut(duration: 0.2)) { showsTurnCue = true }
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                withAnimation(.easeOut(duration: 0.2)) { showsTurnCue = false }
            }
            .onChange(of: snapshot.aiWaitSignature) { _, _ in
                updateAIWaitStart(for: snapshot)
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { now in
                handleAIWaitRecovery(for: snapshot, now: now)
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
            didAutoRefreshAIWaitKey = nil
            didAutoReconnectAIWaitKey = nil
            didAutoDiagnoseAIWaitKey = nil
        }
    }

    private func handleAIWaitRecovery(for snapshot: GameSnapshot, now: Date) {
        let key = snapshot.aiWaitSignature
        guard key == aiWaitKey else { return }
        let action = AIWaitRecoveryPolicy.action(
            for: snapshot,
            elapsedSeconds: now.timeIntervalSince(aiWaitBeganAt),
            didRefresh: didAutoRefreshAIWaitKey == key,
            didReconnect: didAutoReconnectAIWaitKey == key,
            didDiagnose: didAutoDiagnoseAIWaitKey == key
        )
        switch action {
        case .none:
            return
        case .refresh:
            didAutoRefreshAIWaitKey = key
            onInteractionFeedback("Refreshing player wait")
            refreshGame()
        case .reconnect:
            didAutoReconnectAIWaitKey = key
            onInteractionFeedback("Reconnecting player wait")
            reconnectGame()
        case .diagnose:
            didAutoDiagnoseAIWaitKey = key
            onInteractionFeedback("Checking bridge health")
            Task {
                _ = await checkBridgeHealth()
                await refreshProtocolDebug()
            }
        }
    }

    @ViewBuilder
    private func portraitGameContent(
        snapshot: GameSnapshot,
        human: PlayerGameState,
        opponent: PlayerGameState,
        humanName: String,
        opponentName: String,
        sideCombatHighlights: CombatHighlightSet
    ) -> some View {
        GeometryReader { proxy in
            let metrics = PortraitBattlefieldLayoutMetrics(proxy: proxy, paymentActive: InlinePaymentPromptState.isActive(in: snapshot), largeText: GameBoardMotion.largeText(dynamicTypeSize),
                centerControlsVisible: BoardDecisionPresentation.needsCenterSpace(snapshot, hasRejection: lastActionRejection != nil))
            let actions = snapshot.legalActions ?? []
            let targetableIds = GameBoardInteractionState.boardTargetableIds(for: snapshot)
            let combatHighlights = CombatHighlightSet(
                selection: combatSelection,
                actions: actions,
                combatGroups: snapshot.xmage?.combat ?? []
            )
            let shouldShowCompactPrompt = CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId)
            let derivedInteractionMode = GameBoardInteractionState.mode(
                for: snapshot,
                pendingActionId: pendingActionId,
                selectedCard: selectedCard
            )

            ZStack {
                PortraitOpponentStatusBar(
                    snapshot: snapshot,
                    opponentName: opponentName,
                    opponent: opponent,
                    humanId: human.playerId,
                    combatTargetable: CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: combatHighlights.defenderIds) != nil,
                    combatTargetAction: {
                        if let defenderId = CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: combatHighlights.defenderIds) {
                            submitAttackers(defenderId: defenderId, snapshot: snapshot)
                        }
                    },
                    openLog: { isLogOpen = true },
                    viewZone: { localViewZone(title: $0, cards: $1) },
                    selectOpponent: { focusedOpponentId = $0 }
                )
                .frame(width: metrics.topHUDRect.width, height: metrics.topHUDRect.height)
                .position(x: metrics.topHUDRect.midX, y: metrics.topHUDRect.midY)

                PortraitBattlefieldPermanentGroup(title: "Opponent board", cards: nonLandPermanents(opponent.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.opponentBattlefieldRect.width, availableHeight: metrics.opponentBattlefieldRect.height, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.opponentBattlefieldRect.width, height: metrics.opponentBattlefieldRect.height)
                    .position(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)

                BattlefieldRow(title: "Opponent lands", cards: landPermanents(opponent.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.opponentLandsRect.width, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.opponentLandsRect.width, height: metrics.opponentLandsRect.height)
                    .position(x: metrics.opponentLandsRect.midX, y: metrics.opponentLandsRect.midY)

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        if InlinePaymentPromptState.isActive(in: snapshot) {
                            InlinePaymentPromptBar(
                                snapshot: snapshot,
                                pendingActionId: pendingActionId,
                                runAction: runAction,
                                runCommand: runCommand,
                                openDetails: openPromptDetails
                            )
                            .frame(maxWidth: .infinity)
                        } else if BoardDecisionPresentation.showsGuidance(snapshot) {
                            PromptPill(snapshot: snapshot, combatSelection: combatSelection)
                                .frame(maxWidth: .infinity)
                        }

                        let revealedCards = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
                        let lookedAtCards = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
                        if !revealedCards.isEmpty {
                            FloatingZoneChip(title: "Revealed", count: revealedCards.count, icon: "eye") {
                                inspectBoardZone(.collection(.revealed))
                            }
                        }
                        if !lookedAtCards.isEmpty {
                            FloatingZoneChip(title: "Looked", count: lookedAtCards.count, icon: "eye.trianglebadge.exclamationmark") {
                                inspectBoardZone(.collection(.lookedAt))
                            }
                        }
                    }
                    if let lastActionRejection {
                        ActionRejectionInlineView(notice: lastActionRejection) {
                            recover(from: lastActionRejection)
                        }
                    }
                }
                .frame(width: metrics.centerStripRect.width, height: metrics.centerStripRect.height)
                .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

                PortraitBattlefieldPermanentGroup(title: "Your board", cards: nonLandPermanents(human.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.playerBattlefieldRect.width, availableHeight: metrics.playerBattlefieldRect.height, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.playerBattlefieldRect.width, height: metrics.playerBattlefieldRect.height)
                    .position(x: metrics.playerBattlefieldRect.midX, y: metrics.playerBattlefieldRect.midY)

                BattlefieldRow(title: "Your lands", cards: landPermanents(human.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.playerLandsRect.width, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.playerLandsRect.width, height: metrics.playerLandsRect.height)
                    .position(x: metrics.playerLandsRect.midX, y: metrics.playerLandsRect.midY)

                PortraitHandRow(
                    cards: human.zones.hand,
                    legalActions: actions,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    pendingCardInstanceId: pendingCardInstanceId,
                    interactionState: $interactionState,
                    playerDropZone: metrics.playerDropZone,
                    isOverPlayerDropZone: $isOverPlayerDropZone,
                    cardWidth: metrics.handCardWidth,
                    cardHeight: metrics.handCardHeight,
                    rowWidth: metrics.handRect.width,
                    onDropFeedback: onInteractionFeedback,
                    onActionChoice: { choiceActions, message in
                        dragActionChoice = DragActionChoice(message: message, actions: choiceActions)
                    },
                    runAction: runAction
                )
                .frame(width: metrics.handRect.width, height: metrics.handRect.height)
                .position(x: metrics.handRect.midX, y: metrics.handRect.midY)
                .onChange(of: derivedInteractionMode) { _, mode in
                    interactionState.mode = mode
                }

                if isOverPlayerDropZone {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(MagicPalette.antiqueGold.opacity(0.13))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MagicPalette.antiqueGold.opacity(0.70), lineWidth: 2))
                        .frame(width: metrics.playerDropZone.width, height: metrics.playerDropZone.height)
                        .position(x: metrics.playerDropZone.midX, y: metrics.playerDropZone.midY)
                        .allowsHitTesting(false)
                }

                PortraitBottomCommandBar(
                    humanName: humanName,
                    human: human,
                    opponentId: opponent.playerId,
                    manaPool: human.manaPool,
                    passAction: passAction(in: actions),
                    yieldActions: GameplayActionPresentation.yieldActions(in: actions),
                    pendingActionId: pendingActionId,
                    snapshot: snapshot,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    openLog: { isLogOpen = true },
                    openSettings: { isGameMenuOpen = true },
                    openPromptDetails: openPromptDetails,
                    viewZone: { localViewZone(title: $0, cards: $1) },
                    runAction: runAction,
                    runCommand: runCommand
                )
                .frame(width: metrics.bottomControlsRect.width, height: metrics.bottomControlsRect.height)
                .position(x: metrics.bottomControlsRect.midX, y: metrics.bottomControlsRect.midY)

                if CombatSelectionState.isDeclareAttackers(snapshot) {
                    let declaredAttackCount = snapshot.xmage?.combat.flatMap(\.attackers).count ?? 0
                    let hasPendingAttacker = !combatSelection.selectedAttackerIds.isEmpty
                    CombatSubmitPill(
                        title: hasPendingAttacker ? "Cancel Selection" : (declaredAttackCount == 0 ? "No Attacks" : "Done Attacking"),
                        count: max(declaredAttackCount, combatSelection.selectedAttackerIds.count)
                    ) {
                        if hasPendingAttacker {
                            combatSelection.clearAttackers()
                        } else {
                            finishAttackers(snapshot: snapshot)
                        }
                    }
                    .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.maxY + 20)
                    .zIndex(19)
                } else if CombatSelectionState.isDeclareBlockers(snapshot) {
                    let declaredBlockCount = snapshot.xmage?.combat.flatMap(\.blockers).count ?? 0
                    let hasPendingBlocker = combatSelection.selectedBlockerId != nil
                    CombatSubmitPill(
                        title: hasPendingBlocker ? "Cancel Selection" : (declaredBlockCount == 0 ? "No Blocks" : "Done Blocking"),
                        count: max(declaredBlockCount, combatSelection.blockerPairCount)
                    ) {
                        if hasPendingBlocker {
                            combatSelection.clearBlockers()
                        } else if combatSelection.hasPendingBlockers {
                            submitBlockers(snapshot: snapshot)
                        } else {
                            finishBlockers(snapshot: snapshot)
                        }
                    }
                    .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.maxY + 20)
                    .zIndex(19)
                }

                if let inspectingZoneTitle {
                    CompactZoneInspectorOverlay(
                        title: inspectingZoneReference?.title(in: snapshot) ?? inspectingZoneTitle,
                        cards: inspectingZoneReference?.cards(in: snapshot) ?? inspectingZoneCards,
                        legalActions: actions,
                        pendingActionId: pendingActionId,
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        runAction: runAction,
                        closeAction: {
                            self.inspectingZoneTitle = nil
                            self.inspectingZoneCards = []
                            self.inspectingZoneReference = nil
                        },
                        targetableIDs: targetableIds,
                        runTargetAction: { submitTarget($0, snapshot: snapshot) }
                    )
                    .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                    .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(70)
                }

                if let inspectedCard {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { self.inspectedCard = nil }
                        .inspectionTouchPassthrough()
                        .zIndex(99)

                    CardInspector(card: inspectedCard)
                        .inspectionTouchPassthrough()
                        .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                        .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                        .zIndex(100)
                }

                if shouldShowCompactPrompt && !isPromptDetailOpen && (targetableIds.isEmpty || targetableIds.contains(where: { id in snapshot.players.contains { CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot).contains(id) } })) {
                    CompactPromptPopup(
                        snapshot: snapshot,
                        pendingActionId: pendingActionId,
                        runAction: runAction,
                        runCommand: runCommand,
                        openDetails: {
                            isPromptDetailOpen = true
                        }
                    )
                    .frame(width: metrics.compactPromptRect.width, height: metrics.compactPromptRect.height)
                    .position(x: metrics.compactPromptRect.midX, y: metrics.compactPromptRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(20)
                }

                if let dragActionChoice {
                    DragActionChoicePopup(
                        choice: dragActionChoice,
                        pendingActionId: pendingActionId,
                        runAction: { action in
                            self.dragActionChoice = nil
                            selectedCard = nil
                            runAction(action)
                        },
                        cancel: {
                            self.dragActionChoice = nil
                            selectedCard = nil
                        }
                    )
                    .frame(width: metrics.compactPromptRect.width)
                    .position(x: metrics.compactPromptRect.midX, y: metrics.compactPromptRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(21)
                }

                if snapshot.isWaitingOnAIOrStalled {
                    AIWaitFallbackControls(
                        snapshot: snapshot,
                        pendingActionId: pendingActionId,
                        liveUpdateStatus: liveUpdateStatus,
                        beganAt: aiWaitBeganAt,
                        didRefresh: didAutoRefreshAIWaitKey == aiWaitKey,
                        didReconnect: didAutoReconnectAIWaitKey == aiWaitKey,
                        didDiagnose: didAutoDiagnoseAIWaitKey == aiWaitKey,
                        refreshAction: refreshGame,
                        reconnectAction: reconnectGame
                    )
                    .frame(width: min(metrics.safeFrame.width - 28, 360))
                    .position(x: metrics.safeFrame.midX, y: metrics.safeFrame.midY)
                    .zIndex(80)
                }
            }
            #if DEBUG
            .dynamicTypeSize(snapshot.id == "design-preview-large-text" ? .accessibility2 : dynamicTypeSize)
            #endif
            .preferredColorScheme(.dark)
            .coordinateSpace(name: "portrait-board")
            .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
                GeometryReader { geometry in
                    let bounds = anchors.mapValues { geometry[$0] }
                    if inspectingZoneTitle == nil && inspectedCard == nil {
                        PortraitCombatArrowOverlay(snapshot: snapshot, groups: snapshot.xmage?.combat ?? [],
                            previewArrows: combatPreviewArrows, metrics: metrics,
                            humanBattlefield: human.zones.battlefield,
                            opponentBattlefield: opponent.zones.battlefield, renderedBounds: bounds,
                            focusedOpponentID: opponent.playerId)
                            .allowsHitTesting(false)
                        CombatEdgeIndicators(cards: human.zones.battlefield + opponent.zones.battlefield,
                            combatIDs: Set(CombatArrowModel.arrows(from: snapshot.xmage?.combat ?? [], previewArrows: combatPreviewArrows).flatMap { [$0.fromId, $0.toId] }),
                            bounds: bounds,
                            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect],
                            laneIndices: CombatViewportAnchors.laneIndices(human: human.zones.battlefield, opponent: opponent.zones.battlefield),
                            inspect: { inspectedCard = $0 })
                    }
                }
            }
            .onAppear {
                interactionState.mode = derivedInteractionMode
                #if DEBUG
                if snapshot.id == "design-preview-zone-inspection" { inspectBoardZone(.player(playerID: snapshot.viewerID, zone: .graveyard)) }
                #endif
            }
            .onChange(of: snapshot.combatSelectionResetKey) { _, _ in
                combatSelection.resetIfInactive(snapshot)
                combatPreviewArrows = []
            }
            .onChange(of: pendingActionId) { _, newValue in
                if newValue == nil {
                    combatPreviewArrows = []
                }
            }
        }
    }

    private func passAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { $0.type == "pass_priority" }
            ?? actions.first { $0.type == "pass_until_response" }
    }

    private func concedeAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { $0.type == "concede" }
    }

    private func selectedActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard let selectedCard else { return [] }
        return GameBoardInteractionState.cardActions(for: selectedCard, actions: snapshot.legalActions ?? [])
    }

    private func targetableCardIds(in snapshot: GameSnapshot) -> Set<String> {
        GameBoardInteractionState.boardTargetableIds(for: snapshot)
    }

    private func submitTarget(_ card: ZoneCard, snapshot: GameSnapshot) {
        guard targetableCardIds(in: snapshot).contains(card.instanceId) || targetableCardIds(in: snapshot).contains(card.id) else {
            GameHaptics.warning()
            onInteractionFeedback("\(card.card.name) is not an exposed XMage target")
            return
        }
        guard let prompt = snapshot.promptEnvelopeV2 else {
            GameHaptics.warning()
            onInteractionFeedback("XMage target prompt is no longer active")
            return
        }
        if (prompt.maxChoices ?? 1) > 1 || (prompt.minChoices ?? 1) > 1 {
            selectedCard = card
            isPromptDetailOpen = true
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
            GameHaptics.warning()
            onInteractionFeedback("XMage did not expose a mobile-safe target command")
            return
        }
        GameHaptics.success()
        runCommand(command, "Target \(card.card.name)", "\(promptId)-\(card.instanceId)")
    }

    private func handleCombatCardTap(_ card: ZoneCard, snapshot: GameSnapshot) -> Bool {
        let actions = snapshot.legalActions ?? []
        if CombatSelectionState.isDeclareAttackers(snapshot) {
            if let attackerId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.attackerHighlightIds(actions: actions)) {
                let defenders = combatSelection.defenderIds(forAttackerId: attackerId, actions: actions)
                combatSelection.selectAttacker(attackerId)
                if defenders.count == 1, let defenderId = defenders.first {
                    submitAttackers(defenderId: defenderId, snapshot: snapshot)
                    onInteractionFeedback("Combat selection sent")
                } else {
                    onInteractionFeedback("Choose who to attack")
                }
                return true
            }
            if let defenderId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.defenderHighlightIds(actions: actions)) {
                guard combatSelection.selectedAttackerId != nil else {
                    onInteractionFeedback("Select an attacker first")
                    return true
                }
                submitAttackers(defenderId: defenderId, snapshot: snapshot)
                return true
            }
        }

        if CombatSelectionState.isDeclareBlockers(snapshot) {
            if let blockerId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.blockerHighlightIds(actions: actions)) {
                let attackers = combatSelection.attackingCreatureIds(forBlockerId: blockerId, actions: actions, combatGroups: snapshot.xmage?.combat ?? [])
                combatSelection.selectBlocker(blockerId)
                if attackers.count == 1, let attackerId = attackers.first {
                    combatSelection.pairSelectedBlocker(withAttackerId: attackerId)
                    submitBlockers(snapshot: snapshot)
                    onInteractionFeedback("Block selection sent")
                } else {
                    onInteractionFeedback("Choose attacker to block")
                }
                return true
            }
            if let attackerId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.attackingCreatureHighlightIds(actions: actions, combatGroups: snapshot.xmage?.combat ?? [])) {
                guard combatSelection.selectedBlockerId != nil else {
                    onInteractionFeedback("Select a blocker first")
                    return true
                }
                combatSelection.pairSelectedBlocker(withAttackerId: attackerId)
                submitBlockers(snapshot: snapshot)
                onInteractionFeedback("Block selection sent")
                return true
            }
        }

        return false
    }

    private func submitAttackers(defenderId: String, snapshot: GameSnapshot) {
        let actions = snapshot.legalActions ?? []
        guard !combatSelection.selectedAttackerIds.isEmpty else {
            onInteractionFeedback("Select at least one attacker first")
            return
        }
        guard combatSelection.defenderHighlightIds(actions: actions).contains(defenderId) else {
            onInteractionFeedback("XMage did not expose that defender")
            return
        }
        guard let human = snapshot.human else { return }
        guard let command = combatSelection.attackCommand(
            gameId: snapshot.id,
            playerId: human.playerId,
            defenderId: defenderId,
            actions: actions,
            expectedBridgeRevision: snapshot.bridgeRevision
        ) else {
            onInteractionFeedback("XMage did not expose mobile-safe attacker data")
            return
        }
        let removesExistingAttack = command.attackers?.allSatisfy { pair in
            guard let defenderId = pair.defenderId else { return false }
            return (snapshot.xmage?.combat ?? []).contains { group in
                group.defenderId == defenderId && group.attackers.contains { card in
                    card.instanceId == pair.attackerId || card.id == pair.attackerId
                }
            }
        } == true
        combatPreviewArrows = removesExistingAttack ? [] : command.attackers?.compactMap { pair in
            guard let defenderId = pair.defenderId else { return nil }
            return CombatArrow(kind: .previewAttack, fromId: pair.attackerId, toId: defenderId, toKind: combatSelection.defenderKind(forDefenderId: defenderId, actions: actions))
        } ?? []
        runCommand(command, removesExistingAttack ? "Remove attacker" : "Declare attacker", "declare-attacker-\(snapshot.bridgeRevision ?? snapshot.turn)-\(defenderId)")
        combatSelection.clearAttackers()
    }

    private func submitBlockers(snapshot: GameSnapshot) {
        guard let human = snapshot.human else { return }
        guard let command = combatSelection.pendingBlockActionPayload(
            playerId: human.playerId,
            gameId: snapshot.id,
            expectedBridgeRevision: snapshot.bridgeRevision
        ) else {
            onInteractionFeedback("Select a blocker and the attacker it blocks")
            return
        }
        combatPreviewArrows = command.blockers?.compactMap { pair in
            guard let attackerId = pair.attackerId else { return nil }
            return CombatArrow(kind: .previewBlock, fromId: pair.blockerId, toId: attackerId, toKind: nil)
        } ?? []
        runCommand(command, "Declare blocker", "declare-blocker-\(snapshot.bridgeRevision ?? snapshot.turn)")
        combatSelection.clearBlockers()
    }

    private func finishAttackers(snapshot: GameSnapshot) {
        guard let human = snapshot.human else { return }
        let command = CombatSelectionState.finishAttackCommand(
            gameId: snapshot.id,
            playerId: human.playerId,
            expectedBridgeRevision: snapshot.bridgeRevision
        )
        runCommand(command, "Finish attackers", "declare-attackers-finish-\(snapshot.bridgeRevision ?? snapshot.turn)")
        combatSelection.clearAttackers()
    }

    private func finishBlockers(snapshot: GameSnapshot) {
        guard let human = snapshot.human else { return }
        let command = CombatSelectionState.finishBlockCommand(
            gameId: snapshot.id,
            playerId: human.playerId,
            expectedBridgeRevision: snapshot.bridgeRevision
        )
        runCommand(command, "Finish blockers", "declare-blockers-finish-\(snapshot.bridgeRevision ?? snapshot.turn)")
        combatSelection.clearBlockers()
    }

    private func designPreviewState(from snapshot: GameSnapshot) -> GameBoardDesignPreviewState {
        let raw = snapshot.id.replacingOccurrences(of: "design-preview-", with: "")
        return GameBoardDesignPreviewState(rawValue: raw) ?? .normalBattlefield
    }

    private func landPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        BattlefieldAttachments.lane(ownedCards: cards, allCards: snapshot?.players.flatMap { $0.zones.battlefield } ?? cards, lands: true, playerIDs: Set(snapshot?.players.map(\.playerId) ?? []))
    }

    private func nonLandPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        BattlefieldAttachments.lane(ownedCards: cards, allCards: snapshot?.players.flatMap { $0.zones.battlefield } ?? cards, lands: false, playerIDs: Set(snapshot?.players.map(\.playerId) ?? []))
    }
}

struct BattlefieldLayoutMetrics {
    static let magicCardHeightToWidth: CGFloat = 88.0 / 63.0

    let size: CGSize
    let safeArea: EdgeInsets
    var centerControlsVisible = true

    init(proxy: GeometryProxy, centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        size = proxy.size
        // The center column already lives inside SwiftUI's safe-area proposal.
        // Its local bounds must not lose the window insets a second time.
        safeArea = EdgeInsets()
    }

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets(), centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        self.size = size
        self.safeArea = safeArea
    }

    var safeFrame: CGRect {
        let margin: CGFloat = 10
        let x = safeArea.leading + margin
        let y = safeArea.top + 8
        let width = max(size.width - safeArea.leading - safeArea.trailing - margin * 2, 320)
        // The hand finishes at the safe bottom edge; retain only the top gutter.
        let height = max(size.height - safeArea.top - safeArea.bottom - 8, 300)
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
        let top = safeFrame.minY
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
        let width = min(safeFrame.width, 560)
        let height = safeFrame.height - 12
        return CGRect(x: safeFrame.midX - width / 2, y: safeFrame.midY - height / 2,
                      width: width, height: height)
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
        ArenaHandLayout.restingHeight(cardHeight: handCardHeight)
    }

    var handY: CGFloat {
        handRect.midY
    }

    var handVisualTopY: CGFloat {
        handRect.minY - 24
    }

    var permanentCardWidth: CGFloat {
        min(88, max(44, (opponentBattlefieldRect.height - 12) / 1.08))
    }

    var permanentCardHeight: CGFloat { permanentCardWidth * 1.08 }

    var landCardWidth: CGFloat { min(48, permanentCardWidth) }

    var landCardHeight: CGFloat { landCardWidth * 1.08 }

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
        // Lands share each player's row, leaving vertical space for readable cards and hand.
        let rowHeight = max((battlefieldRect.height - centerStripHeight - 12) / 2, 44)
        let landWidth = battlefieldRect.width * 0.32
        let creatureWidth = battlefieldRect.width - landWidth - 10
        let top = battlefieldRect.minY
        let centerY = top + rowHeight + 6
        let playerY = centerY + centerStripHeight + 6
        func creatures(_ y: CGFloat) -> CGRect {
            CGRect(x: battlefieldRect.minX, y: y, width: creatureWidth, height: rowHeight)
        }
        func lands(_ y: CGFloat) -> CGRect {
            CGRect(x: battlefieldRect.maxX - landWidth, y: y, width: landWidth, height: rowHeight)
        }
        return [creatures(top), lands(top),
                CGRect(x: battlefieldRect.minX, y: centerY, width: battlefieldRect.width, height: centerStripHeight),
                creatures(playerY), lands(playerY)]
    }

    private var laneGap: CGFloat {
        3
    }

    private var centerStripHeight: CGFloat {
        centerControlsVisible ? 56 : 0
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

struct PortraitBattlefieldLayoutMetrics {
    static let magicCardHeightToWidth = BattlefieldLayoutMetrics.magicCardHeightToWidth

    let size: CGSize
    let safeArea: EdgeInsets
    var largeText = false
    var paymentActive = false
    var centerControlsVisible = true
    var centerStripHeight: CGFloat { paymentActive ? 60 : centerControlsVisible ? 36 : 0 }

    init(proxy: GeometryProxy, paymentActive: Bool = false, largeText: Bool = false, centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        self.largeText = largeText
        self.paymentActive = paymentActive
        size = proxy.size
        // This reader is inside the safe-area-constrained game root. Only the
        // battlefield background ignores those insets; controls stay inside it.
        safeArea = EdgeInsets()
    }

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets(), paymentActive: Bool = false, centerControlsVisible: Bool = true) {
        self.centerControlsVisible = centerControlsVisible
        self.paymentActive = paymentActive
        self.size = size
        self.safeArea = safeArea
    }

    var safeFrame: CGRect {
        let margin: CGFloat = 8
        return CGRect(
            x: safeArea.leading + margin,
            y: safeArea.top + 8,
            width: max(size.width - safeArea.leading - safeArea.trailing - margin * 2, 300),
            height: max(size.height - safeArea.top - safeArea.bottom - 16, 0)
        )
    }

    var topHUDRect: CGRect {
        CGRect(x: safeFrame.minX, y: safeFrame.minY, width: safeFrame.width, height: largeText ? 84 : 54)
    }

    var opponentBattlefieldRect: CGRect {
        CGRect(x: safeFrame.minX + 10, y: topHUDRect.maxY + 10, width: creatureLaneWidth, height: permanentGroupHeight)
    }

    var opponentLandsRect: CGRect {
        if usesCompactLanes {
            return CGRect(x: opponentBattlefieldRect.maxX + 8, y: opponentBattlefieldRect.minY,
                          width: safeFrame.maxX - 10 - opponentBattlefieldRect.maxX - 8, height: permanentGroupHeight)
        }
        return CGRect(x: safeFrame.minX + 10, y: opponentBattlefieldRect.maxY + 5, width: safeFrame.width - 20, height: landCardHeight + 8)
    }

    var centerStripRect: CGRect {
        CGRect(x: safeFrame.minX + 8, y: opponentLandsRect.maxY + 10, width: safeFrame.width - 16, height: centerStripHeight)
    }

    var playerBattlefieldRect: CGRect {
        CGRect(x: safeFrame.minX + 10, y: centerStripRect.maxY + 10, width: creatureLaneWidth, height: permanentGroupHeight)
    }

    var playerLandsRect: CGRect {
        if usesCompactLanes {
            return CGRect(x: playerBattlefieldRect.maxX + 8, y: playerBattlefieldRect.minY,
                          width: safeFrame.maxX - 10 - playerBattlefieldRect.maxX - 8, height: permanentGroupHeight)
        }
        return CGRect(x: safeFrame.minX + 10, y: playerBattlefieldRect.maxY + 5, width: safeFrame.width - 20, height: landCardHeight + 8)
    }

    var bottomControlsRect: CGRect {
        let height: CGFloat = 110
        return CGRect(x: safeFrame.minX, y: safeFrame.maxY - height, width: safeFrame.width, height: height)
    }

    var handRect: CGRect {
        let top = playerLandsRect.maxY + 8
        let bottom = bottomControlsRect.minY - 8
        return CGRect(x: safeFrame.minX, y: top, width: safeFrame.width, height: max(bottom - top, 0))
    }

    var bottomHUDRect: CGRect {
        CGRect(x: bottomControlsRect.minX, y: bottomControlsRect.minY, width: min(max(bottomControlsRect.width * 0.34, 132), 146), height: bottomControlsRect.height)
    }

    var bottomActionPanelRect: CGRect {
        let x = bottomHUDRect.maxX + 10
        return CGRect(
            x: x,
            y: bottomControlsRect.minY + 8,
            width: max(stackPanelRect.minX - x - 10, 118),
            height: bottomControlsRect.height - 16
        )
    }

    var passButtonRect: CGRect {
        CGRect(
            x: bottomActionPanelRect.minX,
            y: bottomActionPanelRect.minY + 18,
            width: bottomActionPanelRect.width,
            height: 44
        )
    }

    var skipButtonRect: CGRect {
        CGRect(
            x: passButtonRect.minX,
            y: passButtonRect.maxY + 10,
            width: passButtonRect.width,
            height: 34
        )
    }

    var bottomNavRect: CGRect {
        CGRect(
            x: bottomActionPanelRect.minX,
            y: skipButtonRect.maxY + 6,
            width: bottomActionPanelRect.width,
            height: max(bottomActionPanelRect.maxY - skipButtonRect.maxY - 6, 34)
        )
    }

    var stackPanelRect: CGRect {
        let width = min(max(bottomControlsRect.width * 0.28, 108), 126)
        return CGRect(
            x: bottomControlsRect.maxX - width - 8,
            y: bottomControlsRect.minY + 8,
            width: width,
            height: bottomControlsRect.height - 16
        )
    }

    var settingsButtonRect: CGRect {
        let size: CGFloat = 34
        return CGRect(
            x: bottomNavRect.minX,
            y: bottomNavRect.midY - size / 2,
            width: size,
            height: size
        )
    }

    var handScrubberRect: CGRect {
        CGRect(
            x: handRect.minX + 24,
            y: handRect.maxY - 12,
            width: max(handRect.width - 48, 120),
            height: 8
        )
    }

    var compactPromptRect: CGRect {
        CGRect(x: safeFrame.minX + 16, y: safeFrame.midY - 95, width: safeFrame.width - 32, height: 190)
    }

    var detailSheetRect: CGRect {
        CGRect(
            x: safeFrame.minX + 18,
            y: safeFrame.midY - min(safeFrame.height * 0.38, 290),
            width: safeFrame.width - 36,
            height: min(safeFrame.height * 0.76, 580)
        )
    }

    var playerPlayAreaRect: CGRect {
        CGRect(x: safeFrame.minX, y: playerBattlefieldRect.minY - 8, width: safeFrame.width, height: playerLandsRect.maxY - playerBattlefieldRect.minY + 16)
    }

    var playerDropZone: CGRect {
        playerPlayAreaRect
    }

    var permanentCardWidth: CGFloat {
        min(92, max(50, (permanentGroupHeight - 12) / 1.08))
    }

    var permanentCardHeight: CGFloat {
        permanentCardWidth * 1.08
    }

    var permanentRowHeight: CGFloat {
        permanentCardHeight + 8
    }

    var permanentGroupHeight: CGFloat {
        max(80, (safeFrame.height - topHUDRect.height - bottomControlsRect.height - ArenaHandLayout.restingHeight(cardHeight: handCardHeight) - 6 - centerStripHeight - (usesCompactLanes ? 0 : 2 * (landCardHeight + 8)) - 56) / 2)
    }

    // Preserve readable hand height on short phones by putting lands beside
    // permanents, using the same independently scrolling lanes as landscape.
    var usesCompactLanes: Bool {
        safeFrame.height < topHUDRect.height + bottomControlsRect.height + handCardHeight + 36 + centerStripHeight + 2 * (landCardHeight + 8) + 56 + 160
    }

    private var creatureLaneWidth: CGFloat {
        (safeFrame.width - 20) * (usesCompactLanes ? 0.68 : 1)
    }

    var landCardWidth: CGFloat {
        45
    }

    var landCardHeight: CGFloat {
        landCardWidth * 1.08
    }

    var handCardWidth: CGFloat {
        min(max(safeFrame.width / 4.8, 78), 88)
    }

    var handCardHeight: CGFloat {
        handCardWidth * Self.magicCardHeightToWidth
    }
}

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

/// Names kept for the many call sites that use them, but every value now resolves through
/// GameBoardTheme so the app has one palette rather than two near-identical ones. This
/// previously held its own gold (0.82/0.62/0.27) alongside the theme's (0.84/0.65/0.25),
/// which is why the menu and the board never quite matched. Prefer GameBoardTheme.current
/// in new code; DESIGN.md treats it as canonical.
enum MagicPalette {
    private static let theme = GameBoardTheme.current
    static let antiqueGold = theme.antiqueGold
    static let brass = theme.brass
    static let warningAmber = theme.warningAmber
    static let moss = theme.mossMid
    static let deepMoss = theme.backgroundDeepMoss
    static let iron = theme.iron
    static let parchment = theme.whiteReadable
    static let parchmentShadow = theme.parchmentShadow
    static let oxblood = theme.dangerOxblood
    static let leather = theme.leatherMid
    static let carvedWood = theme.carvedWood
    static let emerald = theme.emeraldPriority
    static let arcaneBlue = theme.arcaneBlue
    static let legalEmerald = emerald
    static let priorityArcane = arcaneBlue
    static let panelParchment = theme.agedParchment
    static let borderBronze = theme.brass
    static let borderIron = theme.borderIron
    static let laneWood = theme.oak
}

enum MagicMobileAssetName {
    static let stoneArena = "commander-stone-arena"
    static let portraitStoneArena = "commander-stone-arena-portrait"
    static let boardBackground = "mage-mobile-board-background"
    static let menuBackground = "mage-mobile-menu-background"
    static let portraitBoardBackground = "mage-mobile-board-background-portrait"
    static let portraitMenuBackground = "mage-mobile-menu-background-portrait"
}

struct BattlefieldSurface: View {
    var portraitModeEnabled = false
    @AppStorage(BoardAppearancePreference.key) private var appearance = BoardAppearancePreference.defaultValue

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BattlefieldBackdropArt(theme: .resolved(appearance))
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
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
                        .black.opacity(0.10),
                        .black.opacity(0.24)
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
    var portraitModeEnabled = false
    @AppStorage(MenuAppearancePreference.key) private var appearance = MenuAppearancePreference.defaultValue

    var body: some View {
        GeometryReader { proxy in
            let portrait = GameOrientationMode.isPortraitLayout(size: proxy.size, portraitEnabled: portraitModeEnabled)
            ZStack {
                Group {
                    switch MenuAppearancePreference.normalized(appearance) {
                    case "arena":
                        Image(portrait ? MagicMobileAssetName.portraitStoneArena : MagicMobileAssetName.stoneArena)
                            .resizable().scaledToFill()
                    case "midnight":
                        MidnightSurfaceGradient()
                    default:
                        Image(portrait ? MagicMobileAssetName.portraitMenuBackground : MagicMobileAssetName.menuBackground)
                            .resizable().scaledToFill()
                    }
                }
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
    let pendingActionId: String?
    let liveUpdateStatus: String
    let beganAt: Date
    let didRefresh: Bool
    let didReconnect: Bool
    let didDiagnose: Bool
    let refreshAction: () -> Void
    let reconnectAction: () -> Void

    var body: some View {
        TimelineView(.periodic(from: beganAt, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(beganAt)
            let wait = XmageWaitPresentation.make(
                snapshot: snapshot,
                pendingActionId: pendingActionId,
                liveUpdateStatus: liveUpdateStatus,
                elapsedSeconds: elapsed,
                didRefresh: didRefresh,
                didReconnect: didReconnect,
                didDiagnose: didDiagnose
            )
            VStack(spacing: 7) {
                Text(wait.title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(wait.kind == .snapshotStale || wait.kind == .manualReconnectAvailable ? MagicPalette.warningAmber : MagicPalette.arcaneBlue)
                Text("\(Int(elapsed))s")
                    .font(.system(size: 18, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text(wait.detail)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button("REFRESH", action: refreshAction)
                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                Button("RECONNECT", action: reconnectAction)
                    .buttonStyle(CompactActionButtonStyle(isPrimary: false))
            }
            .padding(8)
            .background(MagicPalette.iron.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke((wait.kind == .snapshotStale || wait.kind == .manualReconnectAvailable ? MagicPalette.warningAmber : MagicPalette.arcaneBlue).opacity(0.46), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
    }
}

struct GameCompletionOverlay: View {
    let snapshot: GameSnapshot
    let newGame: () -> Void
    let quitGame: () -> Void

    private var title: String {
        guard let winners = snapshot.winnerPlayerIds, !winners.isEmpty else { return "Game Over" }
        return winners.contains(snapshot.viewerID) ? "Victory" : "Defeat"
    }

    private var winnerText: String {
        let names = snapshot.winnerDisplayNames
        if names.isEmpty { return "XMage has completed the match." }
        if names == ["You"] { return "You won the match." }
        return "Winner: \(names.joined(separator: ", "))"
    }

    private var reasonText: String? {
        guard let reason = snapshot.endReason, !reason.isEmpty else { return nil }
        return reason.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: snapshot.winnerPlayerIds?.contains(snapshot.viewerID) == true ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)

                Text(title.uppercased())
                    .font(.system(size: 26, weight: .black, design: .serif))
                    .foregroundStyle(.white)

                Text(winnerText)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(MagicPalette.parchment)
                    .multilineTextAlignment(.center)

                if let reasonText {
                    Text(reasonText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button("New Game", action: newGame)
                        .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                    Button("Main Menu", action: quitGame)
                        .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                }
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(MagicPalette.iron.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MagicPalette.antiqueGold.opacity(0.58), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.48), radius: 18, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game completed. \(title). \(winnerText)")
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
                Text(player.zones.command.first?.card.name ?? (player.hasKnownCommanderTax ? "Commander hidden" : "Command zone"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            ZoneCounter(label: "Lib", value: player.zones.visibleLibraryCount)
            ZoneCounter(label: "Hand", value: player.zones.visibleHandCount)
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
    let commanderTax: Int?
    let handCount: Int
    let libraryCount: Int
    let graveyardCount: Int
    let exileCount: Int
    let commanderDamage: Int?

    var commanderTaxLabel: String { commanderTax.map(String.init) ?? "—" }
    var commanderDamageLabel: String { commanderDamage.map(String.init) ?? "—" }
    var commandZoneLabel: String { commanderTax.map { "Command (\($0))" } ?? "Command" }

    init(player: PlayerGameState, opponentId: String?) {
        life = player.life
        commanderTax = player.hasKnownCommanderTax ? player.commanderTax : nil
        handCount = player.zones.visibleHandCount
        libraryCount = player.zones.visibleLibraryCount
        graveyardCount = player.zones.graveyard.count
        exileCount = player.zones.exile.count
        commanderDamage = player.commanderDamage.map { damage in opponentId.flatMap { damage[$0] } ?? 0 }
    }
}

/// Fits the narrow landscape rail without intruding into the battlefield.
private struct LandscapePlayerSummary: View {
    let name: String
    let player: PlayerGameState
    var active = false
    var opponentId: String?
    var combatTargetable = false
    var combatTargetAction: (() -> Void)?

    var body: some View {
        let summary = CommanderHudSummary(player: player, opponentId: opponentId)
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 11, weight: .bold)).lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 16))
                BoardLifeTotal(life: summary.life).id(player.playerId)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
                .foregroundStyle(MagicPalette.antiqueGold)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(summary.life) life")
            Text("Hand \(summary.handCount) · Lib \(summary.libraryCount)")
                .font(.system(size: 9, weight: .semibold)).lineLimit(1)
            Text("Tax \(summary.commanderTaxLabel) · Dmg \(summary.commanderDamageLabel)")
                .font(.system(size: 9, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(
            combatTargetable ? MagicPalette.oxblood : MagicPalette.antiqueGold.opacity(active ? 0.8 : 0.3),
            lineWidth: combatTargetable ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { if combatTargetable { combatTargetAction?() } }
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
                InteractiveHudMiniStat(label: "CMD", value: summary.commanderTaxLabel) {
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
                HudMiniStat(label: "Dmg", value: summary.commanderDamageLabel)
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
    var combatTargetable = false
    var combatTargetAction: (() -> Void)?

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
                HudMiniStat(label: "CMD", value: summary.commanderTaxLabel)
                HudMiniStat(label: "Hand", value: "\(summary.handCount)")
                HudMiniStat(label: "Lib", value: "\(summary.libraryCount)")
                HudMiniStat(label: "GY", value: "\(summary.graveyardCount)")
                HudMiniStat(label: "Ex", value: "\(summary.exileCount)")
                HudMiniStat(label: "Dmg", value: summary.commanderDamageLabel)
            }
        }
        .padding(6)
        .frame(width: 84, alignment: .leading)
        .background(MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor.opacity(combatTargetable ? 0.92 : active ? 0.68 : 0.30), lineWidth: combatTargetable ? 2.2 : active ? 1.4 : 1))
        .shadow(color: combatTargetable ? MagicPalette.oxblood.opacity(0.55) : active ? MagicPalette.antiqueGold.opacity(0.18) : .black.opacity(0.20), radius: combatTargetable ? 13 : 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture {
            if combatTargetable {
                combatTargetAction?()
            }
        }
    }

    private var borderColor: Color {
        combatTargetable ? MagicPalette.oxblood : MagicPalette.antiqueGold
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
        snapshot.isViewer(snapshot.activePlayerId)
    }

    private var priorityText: String {
        snapshot.playerLabel(snapshot.priorityPlayerId)
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
                .foregroundStyle(snapshot.isViewer(snapshot.priorityPlayerId) ? MagicPalette.legalEmerald : (snapshot.priorityPlayerId != nil ? MagicPalette.warningAmber : .white.opacity(0.4)))
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
        XmageWaitPresentation.make(snapshot: snapshot, pendingActionId: nil, liveUpdateStatus: liveUpdateStatus).title
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

private struct GameLogMessageRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(MagicPalette.parchment.opacity(0.72))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LatestGameEventButton: View {
    let entry: GameLogEntry
    let openLog: () -> Void

    var body: some View {
        Button(action: openLog) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("LATEST")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)

                GameLogText(message: entry.message, usesDarkBackground: true)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.30)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open game log. Latest event: \(GameLogPresentation(entry.message).plainText)")
    }
}

private struct GameLogAccessButton: View {
    var entryCount = 0
    let openLog: () -> Void

    var body: some View {
        Button(action: openLog) {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("\(entryCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(MagicPalette.parchment.opacity(0.58))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.black.opacity(0.30), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.borderBronze.opacity(0.28)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open game log")
        .accessibilityValue("\(entryCount) actions")
    }
}

struct ActionRejectionInlineView: View {
    let notice: ActionRejectionNotice
    let recoveryAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.category == .staleSnapshot ? "arrow.clockwise.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .black))
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 9, weight: .black))
                Text(notice.message)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
            }
            Spacer(minLength: 2)
            if let recoveryTitle = notice.recoveryTitle {
                Button(recoveryTitle, action: recoveryAction)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(MagicPalette.warningAmber.opacity(0.22), in: Capsule())
            }
        }
        .foregroundStyle(MagicPalette.warningAmber)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(MagicPalette.iron.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MagicPalette.warningAmber.opacity(0.42), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notice.title). \(notice.message)")
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

enum GameplayAffordances {
    static func dismissesZone(action: LegalAction) -> Bool { action.type == "cast_spell" }

    static func commanderCastAvailable(player: PlayerGameState, snapshot: GameSnapshot, pendingActionID: String?) -> Bool {
        guard pendingActionID == nil, snapshot.human?.playerId == player.playerId else { return false }
        return player.zones.command.contains { card in
            GameBoardInteractionState.cardActions(for: card, actions: snapshot.legalActions ?? []).contains {
                $0.type == "cast_spell" && $0.playerId == player.playerId
            }
        }
    }

    static func floatingManaSymbols(in snapshot: GameSnapshot, pendingActionID: String?) -> Set<String> {
        guard pendingActionID == nil else { return [] }
        return Set(["W", "U", "B", "R", "G", "C"].filter { floatingManaCommand(symbol: $0, in: snapshot) != nil })
    }

    static func floatingManaCommand(symbol: String, in snapshot: GameSnapshot) -> GameCommand? {
        guard let human = snapshot.human, let pool = human.manaPool,
              let prompt = snapshot.promptEnvelopeV2, prompt.playerId == human.playerId,
              CompactPromptPopup.isManaPaymentPrompt(prompt),
              let choice = prompt.manaChoices?.first(where: { ($0.manaType ?? $0.id) == symbol }),
              snapshot.source != "xmage-ondevice" || (choice.amount ?? 0) > 0 else { return nil }
        let counts = ["W": pool.W, "U": pool.U, "B": pool.B, "R": pool.R, "G": pool.G, "C": pool.C]
        guard (counts[symbol] ?? 0) > 0 else { return nil }
        return UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision, promptEnvelope: prompt,
            type: snapshot.source == "xmage-ondevice" ? "play_mana" : prompt.responseCommand?.type ?? "play_mana",
            promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId,
            ids: [symbol], manaType: symbol
        )
    }
}

struct ManaPoolHUD: View {
    let manaPool: ManaPool?
    var vertical = false
    var compact = false
    var grid = false
    var payableSymbols: Set<String> = []
    var payMana: ((String) -> Void)? = nil

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
            if grid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 5) {
                    manaContent
                }
                .padding(5)
            } else if vertical {
                VStack(spacing: 5) {
                    manaContent
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 9)
            } else {
                HStack(spacing: compact ? 2 : 5) {
                    manaContent
                }
                .padding(.horizontal, compact ? 4 : 9)
                .padding(.vertical, payableSymbols.isEmpty ? 6 : 4)
            }
        }
        .background(MagicPalette.iron.opacity(0.76), in: RoundedRectangle(cornerRadius: vertical ? 12 : 16))
        .overlay(RoundedRectangle(cornerRadius: vertical ? 12 : 16).stroke(MagicPalette.antiqueGold.opacity(0.38), lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
    }

    @ViewBuilder
    private var manaContent: some View {
        ForEach(values, id: \.0) { symbol, count in
            if payableSymbols.contains(symbol), !grid, let payMana {
                Button { payMana(symbol) } label: {
                    manaValue(symbol: symbol, count: count)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(MagicPalette.antiqueGold.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.9), lineWidth: 1.5))
                        .shadow(color: MagicPalette.antiqueGold.opacity(0.65), radius: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spend floating \(symbol) mana, \(count) available")
                .accessibilityIdentifier("board.mana.spend.\(symbol)")
            } else {
                manaValue(symbol: symbol, count: count)
                    .opacity(count > 0 ? 1 : 0.45)
                    .background(payableSymbols.contains(symbol) ? MagicPalette.antiqueGold.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: payableSymbols.contains(symbol) ? MagicPalette.antiqueGold : .clear, radius: 4)
            }
        }
    }

    private func manaValue(symbol: String, count: Int) -> some View {
        HStack(spacing: 2) {
                ManaSymbolView(symbol: symbol, size: compact ? 13 : 18)
                Text("\(count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .frame(minWidth: 8)
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
                            .onCardHold(inspect: {
                                inspectedCard = card
                            }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
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

    private var topDisplayCard: ZoneCard? {
        topObject?.displaySourceCard
    }

    private var passAvailable: Bool {
        legalActions.contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("STACK")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("\(objects.count)")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer(minLength: 0)
                Text(passAvailable ? "RESPOND" : "WAIT")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(passAvailable ? MagicPalette.legalEmerald : .white.opacity(0.55))
            }

            HStack(spacing: 9) {
                if let card = topDisplayCard {
                    CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: "Stack", width: 128, height: 179, ignoreTappedRotation: true, imageVariant: .inspection)
                        .onTapGesture {
                            selectedCard = nil
                            inspectedCard = card
                        }
                        .onCardHold(inspect: {
                            inspectedCard = card
                        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                } else {
                    SyntheticStackObjectTile(object: topObject, width: 128, height: 179)
                }

                Spacer(minLength: 0)
            }

            if let topObject {
                Text(topObject.displayName).font(.caption.bold()).foregroundStyle(MagicPalette.parchment)
                if let rules = topObject.rulesText, !rules.isEmpty {
                    GameRulesText(source: rules, cardName: topObject.displayName).font(.caption)
                        .foregroundStyle(MagicPalette.parchment.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(MagicPalette.iron.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30)))
    }
}

struct SyntheticStackObjectTile: View {
    let object: XmageStackObject?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text(object?.syntheticTileSubtitle.uppercased() ?? "STACK")
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text(object?.syntheticTileTitle ?? "Ability")
                .font(.system(size: 7.5, weight: .black))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.50)
            Text(object?.syntheticTileDetail ?? "Source card image unavailable")
                .font(.system(size: 5.8, weight: .bold))
                .foregroundStyle(MagicPalette.parchment.opacity(0.70))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.48)
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: height)
        .background(
            LinearGradient(
                colors: [MagicPalette.leather.opacity(0.78), MagicPalette.iron.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(MagicPalette.antiqueGold.opacity(0.55), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Text("STACK")
                .font(.system(size: 5.5, weight: .black))
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(MagicPalette.antiqueGold.opacity(0.88), in: Capsule())
                .padding(3)
        }
    }
}

enum BoardDecisionPresentation {
    static func showsGuidance(_ snapshot: GameSnapshot) -> Bool {
        PromptGuidance(snapshot: snapshot, isWaitingOnHuman: snapshot.isViewer(snapshot.waitingOnPlayerId)).isUrgent
    }

    static func needsCenterSpace(_ snapshot: GameSnapshot, hasRejection: Bool = false) -> Bool {
        showsGuidance(snapshot) || hasRejection ||
        snapshot.xmage?.revealed.contains(where: { !$0.cards.isEmpty }) == true ||
        snapshot.xmage?.lookedAt.contains(where: { !$0.cards.isEmpty }) == true
    }
}

struct PromptPill: View {
    let snapshot: GameSnapshot
    var combatSelection = CombatSelectionState()

    private var isWaitingOnHuman: Bool {
        snapshot.isViewer(snapshot.waitingOnPlayerId)
            || (snapshot.waitingOnPlayerId == nil && snapshot.isViewer(snapshot.priorityPlayerId))
            || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty
    }

    private var guidance: PromptGuidance {
        PromptGuidance(snapshot: snapshot, isWaitingOnHuman: isWaitingOnHuman, combatSelection: combatSelection)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(guidance.color)
                .frame(width: 8, height: 8)
                .shadow(color: guidance.color.opacity(0.8), radius: 5)

            Text(guidance.label)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(guidance.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(guidance.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Text(guidance.message)
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
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(guidance.color.opacity(guidance.isUrgent ? 0.72 : 0.5), lineWidth: 1.5))
    }
}

enum InlinePaymentPromptState {
    static func isActive(in snapshot: GameSnapshot) -> Bool {
        paymentPrompt(in: snapshot) != nil
    }

    static func paymentPrompt(in snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        if let prompt = snapshot.promptEnvelopeV2, CompactPromptPopup.isManaPaymentPrompt(prompt) {
            return prompt
        }
        if CompactPromptPopup.shouldShowStackPaymentTray(in: snapshot) {
            return CompactPromptPopup.syntheticStackPaymentPrompt(in: snapshot)
        }
        return nil
    }
}

struct InlinePaymentPromptBar: View {
    let snapshot: GameSnapshot
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let openDetails: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(MagicPalette.antiqueGold)
                .frame(width: 8, height: 8)
                .shadow(color: MagicPalette.antiqueGold.opacity(0.8), radius: 5)

            Text("PAY COST")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MagicPalette.antiqueGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            if let prompt = InlinePaymentPromptState.paymentPrompt(in: snapshot) {
                ManaPaymentTray(
                    snapshot: snapshot,
                    prompt: prompt,
                    pendingActionId: pendingActionId,
                    runAction: runAction,
                    runCommand: runCommand,
                    compact: true
                )
            } else {
                Text("Tap mana sources")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)
            if snapshot.source == "xmage-ondevice" {
                Button(action: openDetails) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(IconButtonStyle(small: true))
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Payment choices")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(MagicPalette.iron.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.72), lineWidth: 1.5))
    }
}

private struct PromptGuidance {
    let label: String
    let message: String
    let color: Color
    let isUrgent: Bool

    init(snapshot: GameSnapshot, isWaitingOnHuman: Bool, combatSelection: CombatSelectionState = CombatSelectionState()) {
        let promptType = snapshot.promptEnvelopeV2?.responseCommand?.type?.lowercased()
            ?? snapshot.promptEnvelopeV2?.responseKind.lowercased()
            ?? ""
        let method = snapshot.promptEnvelopeV2?.method.uppercased() ?? ""
        if snapshot.manaPayment?.active == true || snapshot.promptEnvelopeV2.map(CompactPromptPopup.isManaPaymentPrompt) == true {
            label = "PAY COST"
            message = snapshot.manaPayment?.remainingText ?? "Tap mana sources"
            color = MagicPalette.antiqueGold
            isUrgent = true
        } else if promptType == "choose_target" || method.contains("TARGET") {
            label = "SELECT TARGET"
            message = snapshot.promptText ?? "Choose a highlighted target"
            color = MagicPalette.oxblood
            isUrgent = true
        } else if CombatSelectionState.isDeclareAttackers(snapshot) {
            let selectableAttackers = combatSelection.attackerHighlightIds(actions: snapshot.legalActions ?? [])
            label = combatSelection.selectedAttackerIds.isEmpty ? "SELECT ATTACKERS" : "SELECT DEFENDER"
            message = combatSelection.selectedAttackerIds.isEmpty
                ? (selectableAttackers.isEmpty ? "No creatures can attack — choose No Attacks" : "Choose a highlighted attacker")
                : "Choose who to attack"
            color = MagicPalette.oxblood
            isUrgent = true
        } else if CombatSelectionState.isDeclareBlockers(snapshot) {
            let selectableBlockers = combatSelection.blockerHighlightIds(actions: snapshot.legalActions ?? [])
            label = combatSelection.selectedBlockerId == nil ? "SELECT BLOCKERS" : "SELECT ATTACKER"
            message = combatSelection.selectedBlockerId == nil
                ? (selectableBlockers.isEmpty ? "No creatures can block — choose No Blocks" : "Choose a highlighted blocker")
                : "Choose attacker to block"
            color = MagicPalette.warningAmber
            isUrgent = true
        } else if isWaitingOnHuman {
            label = "YOUR DECISION"
            message = snapshot.promptText ?? "Play spells and abilities"
            color = MagicPalette.emerald
            isUrgent = false
        } else {
            label = "\(snapshot.playerLabel(snapshot.waitingOnPlayerId ?? snapshot.priorityPlayerId).uppercased()) DECISION"
            message = snapshot.promptText ?? "Waiting for XMage"
            color = MagicPalette.arcaneBlue
            isUrgent = false
        }
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

/// UIKit arbitrates the hold before selection, including inside a scrolling sheet.
/// A recognized hold can never also invoke the tap action.
private struct AbilityChoiceTouchSurface: UIViewRepresentable {
    let enabled: Bool
    let choose: () -> Void
    let inspect: () -> Void
    let releaseInspection: () -> Void
    @Environment(\.holdCardInspection) private var inspection

    func makeUIView(context: Context) -> TouchView { TouchView() }
    func updateUIView(_ view: TouchView, context: Context) {
        view.isUserInteractionEnabled = enabled
        view.choose = choose
        view.inspect = { inspection?.begin(dismiss: releaseInspection); inspect() }
        view.releaseInspection = { if let inspection { inspection.end() } else { releaseInspection() } }
    }

    static func dismantleUIView(_ view: TouchView, coordinator: ()) { view.finishInspection() }

    final class TouchView: UIView {
        var choose: (() -> Void)?
        var inspect: (() -> Void)?
        var releaseInspection: (() -> Void)?
        private var inspecting = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.35
            hold.allowableMovement = 8
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.require(toFail: hold)
            addGestureRecognizer(hold)
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func tapped() { choose?() }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: inspecting = true; inspect?()
            case .ended, .cancelled, .failed: finishInspection()
            default: break
            }
        }
        func finishInspection() {
            guard inspecting else { return }
            inspecting = false
            releaseInspection?()
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { finishInspection() }
        }
    }
}

struct UniversalPromptActionPanel: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    @Environment(\.dismiss) private var dismiss
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let viewZone: (String, [ZoneCard]) -> Void
    var showsGameSurfaceSections = true

    private var passActions: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase"].contains($0.type)
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
        let types = ["pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase",
                     "play_land", "cast_spell",
                     "activate_ability", "make_mana", "play_mana", "choose_mana", "choose_ability"]
        return (snapshot.legalActions ?? []).filter {
            !types.contains($0.type)
        }
    }

    private var promptPresentation: MobilePromptPresentation? {
        MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text(promptPresentation?.title.uppercased() ?? "PROMPT")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Spacer(minLength: 4)
                Text(priorityLabel)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Group {
                    Button {
                        GameHaptics.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    .accessibilityLabel("Cancel prompt details")
                    .accessibilityHint("Returns to the battlefield without submitting a choice")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let promptPresentation, snapshot.promptEnvelopeV2 == nil, snapshot.promptEnvelope == nil {
                        PromptPanelSection(title: "Choose", detail: "", isHighlighted: promptPresentation.isUnsupported) {
                            Text(promptPresentation.message)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(promptPresentation.isUnsupported ? MagicPalette.warningAmber : .white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

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
            .accessibilityIdentifier("prompt.details.scroll")
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
        .overlay {
            if let inspectedCard {
                CardInspector(card: inspectedCard)
                    .overlay(alignment: .topTrailing) {
                        Button("Close card") { self.inspectedCard = nil }
                            .frame(minHeight: 44).padding(8)
                    }
                    .inspectionTouchPassthrough()
            }
        }
    }

    private var priorityLabel: String {
        if snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) {
            return "YOUR PRIORITY"
        }
        return snapshot.playerLabel(snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId)
    }

    @ViewBuilder
    private func promptEnvelopeV2Section(_ prompt: PromptEnvelopeV2) -> some View {
        PromptPanelSection(title: promptPresentation?.title ?? "Choose", detail: "", isHighlighted: true,
                           isEmbedded: prompt.abilities?.isEmpty == false) {
            Text(prompt.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

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
                optionGrid(snapshot.players.map { ($0.playerId, snapshot.playerLabel($0.playerId)) }, prompt: prompt, fallbackType: prompt.responseCommand?.type ?? "choose_player", icon: "person.crop.circle")
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
        PromptPanelSection(title: "Choose", detail: "", isHighlighted: true) {
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
                                title: GameplayActionPresentation.title(for: action, snapshot: snapshot),
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
                                    if selectedCard?.instanceId == card.instanceId {
                                        selectedCard = nil
                                    } else {
                                        selectedCard = card
                                    }
                                    inspectedCard = nil
                                    GameHaptics.selection()
                                }
                                .onCardHold(inspect: {
                                    inspectedCard = card
                                    GameHaptics.impact()
                                }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
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
            HStack(spacing: 7) {
                if selectedPromptCardId != nil {
                    Button {
                        selectedCard = nil
                        GameHaptics.selection()
                    } label: {
                        PromptButtonLabel(title: "Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(PanelActionButtonStyle())
                    .disabled(pendingActionId != nil)
                    .accessibilityHint("Clears the selected card")
                }

                promptButton(
                    label: "Confirm Card",
                    subtitle: selectedPromptCardId == nil ? "Select a card first" : selectedCard?.card.name,
                    systemImage: "checkmark.circle",
                    pendingId: "\(prompt.id)-choose-card",
                    command: hasValidSelection && selectedPromptCardId != nil
                        ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [selectedPromptCardId!])
                        : nil
                )
            }
        }
    }

    @ViewBuilder
    private func searchSelectionPicker(cards: [ZoneCard], prompt: PromptEnvelopeV2) -> some View {
        let selectableIds = cards.filter(\.isPromptSelectable).map(\.instanceId)
        let selectedIds = currentSearchSelection(promptId: prompt.id, validIds: selectableIds)
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
                if selectedCount > 0 {
                    Button("Clear") {
                        selectedSearchPromptId = prompt.id
                        selectedSearchCardIds = []
                        GameHaptics.selection()
                    }
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(MagicPalette.parchment)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(pendingActionId != nil)
                    .accessibilityHint("Clears all selected cards")
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 7)], spacing: 7) {
                    ForEach(cards) { card in
                        let selectable = card.isPromptSelectable
                        let isSelected = selectedIds.contains(card.instanceId)
                        Button {
                            guard selectable else { return }
                            toggleSearchSelection(promptId: prompt.id, cardId: card.instanceId, validIds: selectableIds, maxChoices: prompt.maxChoices)
                            GameHaptics.selection()
                        } label: {
                            CardTile(
                                card: card,
                                selected: isSelected,
                                legal: selectable,
                                targetable: selectable,
                                zoneName: searchZoneName(for: prompt),
                                width: 50,
                                height: 70
                            )
                            .opacity(selectable ? 1 : 0.34)
                            .overlay(alignment: .bottom) {
                                if !selectable {
                                    Text(card.disabledReason ?? "Not valid")
                                        .font(.system(size: 6, weight: .black))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 2)
                                        .background(.black.opacity(0.72), in: Capsule())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                        .padding(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(pendingActionId != nil || !selectable)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 154)

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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            // Occurrences are distinct rows even if XMage repeats an ability UUID.
            // Only presentation identity changes; answers retain the engine UUID.
            ForEach(Array(abilities.enumerated()), id: \.offset) { _, ability in
                let choiceCommand = command(type: "choose_ability", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [ability.id])
                VStack(alignment: .leading, spacing: 8) {
                    if let source = ability.sourceCard {
                        let selectAbility = {
                            guard pendingActionId == nil, let choiceCommand else { return }
                            inspectedCard = nil
                            runCommand(choiceCommand, "Choose ability", "\(prompt.id)-\(ability.id)")
                        }
                        CardTile(card: source, selected: false, legal: false,
                                 zoneName: "Ability source",
                                 width: verticalSizeClass == .compact ? 80 : 100,
                                 height: verticalSizeClass == .compact ? 112 : 140)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .disabled(pendingActionId != nil || choiceCommand == nil)
                        .overlay {
                            AbilityChoiceTouchSurface(
                                enabled: pendingActionId == nil && choiceCommand != nil,
                                choose: selectAbility,
                                inspect: { inspectedCard = source },
                                releaseInspection: { if inspectedCard?.id == source.id { inspectedCard = nil } }
                            ).accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Choose \(source.card.name) ability")
                        .accessibilityHint("Tap to choose. Hold to inspect the source card.")
                        .accessibilityAction { selectAbility() }
                        .accessibilityAction(named: Text("Inspect card")) {
                            guard pendingActionId == nil else { return }
                            inspectedCard = source
                        }
                    }
                    Text(ability.sourceName ?? "Ability")
                        .font(.subheadline.bold()).foregroundStyle(MagicPalette.parchment)
                    GameRulesText(source: ability.rulesText ?? ability.label, cardName: ability.sourceName)
                        .font(.callout).foregroundStyle(MagicPalette.parchment)
                        .fixedSize(horizontal: false, vertical: true)
                    if ability.sourceCard == nil {
                        Text(ability.sourceUnavailableReason ?? "Source details unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                promptButton(
                    label: "Choose ability",
                    subtitle: nil,
                    systemImage: "bolt.fill",
                    pendingId: "\(prompt.id)-\(ability.id)",
                    command: choiceCommand
                )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(MagicPalette.iron.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func pilePicker(piles: [XmagePromptPile], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Piles")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(piles) { pile in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(pile.label) · \(pile.cards.count) cards")
                        .font(.subheadline.bold())
                        .foregroundStyle(MagicPalette.parchment)
                    if pile.cards.isEmpty {
                        Text("This pile is empty.")
                            .font(.caption)
                            .foregroundStyle(MagicPalette.parchment.opacity(0.7))
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(pile.cards) { card in
                                    Button {
                                        inspectedCard = card
                                    } label: {
                                        VStack(spacing: 6) {
                                            CardTile(card: card, selected: false, legal: false, zoneName: pile.label, width: 76, height: 106)
                                            Text(card.card.name)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                            Text("Inspect")
                                                .font(.caption.bold())
                                                .frame(minHeight: 44)
                                        }
                                        .frame(width: 96)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(MagicPalette.parchment)
                                    .accessibilityLabel("Inspect \(card.card.name) in \(pile.label)")
                                }
                            }
                        }
                    }
                    promptButton(
                        label: "Choose \(pile.label)",
                        subtitle: "\(pile.cards.count) cards",
                        systemImage: "tray.full",
                        pendingId: "\(prompt.id)-pile-\(pile.id)",
                        command: command(type: "choose_pile", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, pile: pile.explicitPileNumber)
                    )
                }
                .padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
                .frame(width: 44, height: 44)
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Pay with \(mana) mana")
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
                    if let command = command(type: snapshot.source == "xmage-ondevice" ? "play_mana" : prompt.responseCommand?.type ?? "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol) {
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
                .frame(width: 44, height: 44)
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Pay with \(choice.label)")
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
        let bounds = PromptAmountBounds(minimum: prompt.minChoices, maximum: prompt.maxChoices)
        let currentValue = bounds.clamp(manualAmountValues[prompt.id] ?? 0)
        PromptMiniLabel(type == "play_x_mana" ? "X Amount" : "Amount")
        
        HStack(spacing: 7) {
            Button {
                manualAmountValues[prompt.id] = bounds.stepping(currentValue, by: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24, weight: .black))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(currentValue <= bounds.minimum ? .white.opacity(0.24) : MagicPalette.parchment)
            .disabled(pendingActionId != nil || currentValue <= bounds.minimum)

            TextField("Amount", value: Binding(get: { currentValue }, set: { manualAmountValues[prompt.id] = bounds.clamp($0) }), format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(minWidth: 70, minHeight: 44)
                .accessibilityLabel("Amount, from \(bounds.minimum) to \(bounds.maximum)")
                .disabled(pendingActionId != nil)

            Button {
                manualAmountValues[prompt.id] = bounds.stepping(currentValue, by: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .black))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(MagicPalette.parchment)
            .disabled(pendingActionId != nil || currentValue >= bounds.maximum)

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
        PromptCommandBuilder.isCommanderReplacement(prompt)
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
        if snapshot.waitingOnPlayerId != nil && !snapshot.isViewer(snapshot.waitingOnPlayerId) {
            return "Waiting on \(snapshot.playerLabel(snapshot.waitingOnPlayerId)). XMage has not exposed a cast/play action for this card."
        }
        if snapshot.priorityPlayerId != nil && !snapshot.isViewer(snapshot.priorityPlayerId) {
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
                if let companions = snapshot.xmage?.companion, !companions.isEmpty {
                    zoneButton(title: "Companion", value: "\(companions.flatMap(\.cards).count)", systemImage: "person.crop.square", cards: companions.flatMap(\.cards))
                }
                SurfaceChip(title: "Priority", value: priorityOwner, systemImage: "hand.raised")
                SurfaceChip(title: "Actions", value: "\((snapshot.legalActions ?? []).count)", systemImage: "bolt")
            }

            if snapshot.source == "xmage-ondevice" {
                ForEach(namedInspectionZones) { group in
                    if !group.cards.isEmpty {
                        Button("\(group.name) (\(group.cards.count))") { viewZone(group.name, group.cards) }
                            .frame(minHeight: 44).buttonStyle(.plain)
                    }
                }
                DisclosureGroup("Commander tax and damage") {
                    ForEach(snapshot.players) { player in
                        ForEach(player.commanders ?? []) { commander in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(player.displayName ?? player.playerId) · \(commander.name ?? "Commander \(commander.id.prefix(8))")").font(.caption.bold())
                                Text("Command-zone casts: \(commander.castsFromCommandZone.map(String.init) ?? "unknown") · Next tax: \(commander.commanderTax.map { "{\($0)}" } ?? "unknown")").font(.caption)
                                if let damage = commander.damageToPlayers {
                                    ForEach(snapshot.players) { recipient in
                                        Text("Damage to \(snapshot.playerLabel(recipient.playerId)): \(damage[recipient.playerId] ?? 0)").font(.caption)
                                    }
                                } else { Text("Commander damage unavailable").font(.caption) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }
                    }
                }
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
        if snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty {
            return "You"
        }
        return snapshot.playerLabel(snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId)
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
        uniqueCards(snapshot.players.flatMap(\.zones.command) + (snapshot.xmage?.players.flatMap(\.command) ?? []))
    }

    private var graveyardCards: [ZoneCard] {
        uniqueCards(snapshot.players.flatMap(\.zones.graveyard) + (snapshot.xmage?.players.flatMap(\.zones.graveyard) ?? []))
    }

    private var exileCards: [ZoneCard] {
        uniqueCards(snapshot.players.flatMap(\.zones.exile) + (snapshot.xmage?.players.flatMap(\.zones.exile) ?? []) + (snapshot.xmage?.exileZones.flatMap(\.cards) ?? []))
    }

    private func uniqueCards(_ cards: [ZoneCard]) -> [ZoneCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.instanceId).inserted }
    }

    private var namedInspectionZones: [XmageNamedZone] {
        guard let xmage = snapshot.xmage else { return [] }
        return xmage.exileZones + xmage.revealed + xmage.lookedAt
    }

    private var libraryCount: Int {
        snapshot.players.map { $0.zones.visibleLibraryCount }.reduce(0, +)
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
    var isEmbedded = false
    @ViewBuilder let content: Content

    var body: some View {
        if isEmbedded {
            VStack(alignment: .leading, spacing: 7) { content }
        } else {
            framedSection
        }
    }

    private var framedSection: some View {
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
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                            .onCardHold(inspect: {
                                inspectedCard = card
                            }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
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
    private var presentation: MobilePromptPresentation? {
        MobilePromptPresentation.make(snapshot: snapshot, legalActions: legalActions)
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

            if let prompt = paymentPrompt {
                ManaPaymentTray(
                    snapshot: snapshot,
                    prompt: prompt,
                    pendingActionId: pendingActionId,
                    runAction: runAction,
                    runCommand: runCommand
                )
            } else if pendingActionId != nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(MagicPalette.arcaneBlue)
                        .scaleEffect(0.66)
                    Text("Waiting for XMage")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.arcaneBlue)
                }
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
        if InlinePaymentPromptState.isActive(in: snapshot) {
            return false
        }
        if pendingActionId != nil {
            return true
        }

        if let prompt = snapshot.promptEnvelopeV2 {
            let presentation = MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? [])
            if presentation?.kind == .payment || isManaPaymentPrompt(prompt) {
                return false
            }
            if isPassivePriorityPrompt(prompt, snapshot: snapshot) {
                return false
            }
            if !compactLegalPromptActions(in: snapshot).isEmpty {
                return true
            }
            if presentation?.requiresDetail == true || needsDetails(snapshot) {
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
        // Authoritative: the bridge reports manaPayment.active only while the human
        // is actually paying for a spell/ability on the stack. This intentionally
        // does NOT fire for plain response windows (an ability on the stack you may
        // respond to but are not paying for).
        if snapshot.manaPayment?.active == true {
            return true
        }
        guard snapshot.isViewer(snapshot.waitingOnPlayerId) || snapshot.isViewer(snapshot.priorityPlayerId) else {
            return false
        }
        let actions = snapshot.legalActions ?? []
        let sourceManaActions = actions.filter { $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil) }
        guard !sourceManaActions.isEmpty else {
            return false
        }
        let allowedPaymentWindowTypes = Set(["make_mana", "undo_mana", "cancel_payment", "cancel_mana_payment", "concede"])
        guard actions.allSatisfy({ allowedPaymentWindowTypes.contains($0.type) }) else {
            return false
        }
        return snapshot.xmage?.stack.isEmpty == false || snapshot.human?.zones.stack.isEmpty == false
    }

    static func syntheticStackPaymentPrompt(in snapshot: GameSnapshot) -> PromptEnvelopeV2 {
        PromptEnvelopeV2(
            id: "xmage-stack-payment-\(snapshot.bridgeRevision ?? snapshot.turn)",
            method: "GAME_PLAY_MANA",
            messageId: -1,
            playerId: snapshot.viewerID,
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
        if snapshot.source == "xmage-ondevice", let prompt = snapshot.promptEnvelopeV2 {
            if prompt.cards?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false { return true }
            if prompt.piles?.isEmpty == false || prompt.abilities?.isEmpty == false || prompt.modes?.isEmpty == false { return true }
            if prompt.amounts?.isEmpty == false || prompt.multiAmounts?.isEmpty == false || prompt.orderedItems?.isEmpty == false { return true }
            if (prompt.choices?.count ?? 0) > 3 || prompt.responseCommand?.type == "choose_amount" { return true }
        }
        if !compactLegalPromptActions(in: snapshot).isEmpty {
            return false
        }
        if let presentation = MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? []) {
            return presentation.requiresDetail
        }
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

        return PortraitInteractionPolicy.dockActions(legalActions)
            .filter { action in
                if action.type == "concede" { return false }
                // The card-backed picker owns these choices. Keep separate
                // cancel/confirmation actions, but do not repeat abilities as
                // a second compact text chooser underneath it.
                if snapshot.source == "xmage-ondevice", snapshot.promptEnvelopeV2?.abilities?.isEmpty == false,
                   action.type == "choose_ability" { return false }
                if let promptId, action.promptId == promptId { return true }
                if let responseType, action.type == responseType { return true }
                return allowedTypes.contains(action.type)
            }
            .sorted { lhs, rhs in
                compactActionPriority(lhs) < compactActionPriority(rhs)
            }
    }

    private var isManaPayment: Bool {
        if presentation?.kind == .payment {
            return true
        }
        if let prompt = promptV2 {
            return Self.isManaPaymentPrompt(prompt)
        }
        return false
    }

    private var borderColor: Color {
        isManaPayment ? MagicPalette.arcaneBlue : MagicPalette.borderBronze
    }

    private var priorityLabel: String {
        if snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) {
            return "YOUR DECISION"
        }
        return "WAITING"
    }

    private var messageText: String {
        presentation?.message
            ?? promptV2?.message
            ?? snapshot.choicePrompt?.message
            ?? snapshot.promptEnvelope?.message
            ?? snapshot.promptText
            ?? "XMage is waiting"
    }

    @ViewBuilder
    private func compactPromptControls(_ prompt: PromptEnvelopeV2) -> some View {
        let options = (prompt.targets ?? []).filter { option in
            !snapshot.players.flatMap({ $0.zones.battlefield }).contains { $0.instanceId == option.id }
        }
        if !options.isEmpty && prompt.maxChoices == 1 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 8) {
                ForEach(options) { option in
                    compactCommandButton(option.label, systemImage: "person.crop.circle", pendingId: "\(prompt.id)-\(option.id)", command: command(type: prompt.responseCommand?.type ?? "choose_target", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [option.id]))
                }
            }
        } else if isCommanderReplacement(prompt) {
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
            let extraActions = Self.supplementalChoiceActions(in: snapshot)
            if !extraActions.isEmpty {
                compactActionButtons(extraActions)
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

    static func supplementalChoiceActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard snapshot.source == "xmage-ondevice", let prompt = snapshot.promptEnvelopeV2,
              let choices = prompt.choices, !choices.isEmpty, choices.count <= 3 else { return [] }
        let choiceIDs = Set(choices.map(\.id))
        return compactLegalPromptActions(in: snapshot).filter { action in
            guard action.promptId == (prompt.responseCommand?.promptId ?? prompt.id),
                  action.messageId == (prompt.responseCommand?.messageId ?? prompt.messageId),
                  action.playerId == prompt.playerId else { return false }
            return !(action.type == "resolve_choice" && action.choiceIds?.count == 1 && choiceIDs.contains(action.choiceIds?.first ?? ""))
        }
    }

    private func compactActionButtons(_ actions: [LegalAction]) -> some View {
        HStack(spacing: 7) {
            ForEach(actions.prefix(3)) { action in
                let title = compactActionLabel(action)
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
            if actions.count > 3 || (snapshot.source == "xmage-ondevice" && Self.needsDetails(snapshot)) {
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

    static func isManaPaymentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
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
            return action.compactPromptTitle
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
        PromptCommandBuilder.isCommanderReplacement(prompt)
    }

    private static func isPassivePriorityPrompt(_ prompt: PromptEnvelopeV2, snapshot: GameSnapshot) -> Bool {
        guard prompt.method == "GAME_SELECT" else { return false }
        if prompt.responseKind == "priority", prompt.responseCommand?.type == "pass_priority" {
            return true
        }
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
                .frame(width: 44, height: 44)
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Cancel action choice")
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
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    var compact = false

    private var remainingPips: ManaPips? { snapshot.manaPayment?.remaining }

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Pay cost")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                paymentPipRow
                Spacer(minLength: 0)
            }

            if let choices = prompt.manaChoices, !choices.isEmpty {
                HStack(spacing: 7) {
                    Text("Use floating mana")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.72))
                    ForEach(choices.prefix(6)) { choice in
                        let symbol = choice.manaType ?? choice.id
                        paymentManaButton(symbol: symbol, label: choice.label, pendingId: "\(prompt.id)-mana-choice-\(choice.id)", size: 24)
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
                            PromptButtonLabel(title: Self.paymentCancelTitle(for: action), systemImage: action.type == "resolve_choice" ? "sparkles" : "arrow.uturn.backward", isPending: pendingActionId == action.id)
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

            if !hasBattlefieldManaSources && prompt.manaChoices?.isEmpty != false {
                Text("Waiting for XMage mana options")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.arcaneBlue)
            }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
            paymentPipRow
            if let choices = prompt.manaChoices, !choices.isEmpty {
                Divider().frame(height: 24)
                Text("Use floating mana").font(.caption2.bold()).foregroundStyle(MagicPalette.parchment)
                // Keep every supplied payment choice reachable while cancel stays fixed.
                ForEach(choices) { choice in
                    let symbol = choice.manaType ?? choice.id
                    paymentManaButton(symbol: symbol, label: choice.label, pendingId: "\(prompt.id)-mana-choice-\(choice.id)", size: 22)
                }
            } else {
                Text(hasBattlefieldManaSources ? "Tap sources" : "Waiting for mana options")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(hasBattlefieldManaSources ? MagicPalette.parchment.opacity(0.78) : MagicPalette.arcaneBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            }
            }
            .frame(minWidth: 48, minHeight: 44)
            .accessibilityLabel("Remaining cost and mana choices; swipe to view")

            ForEach(Self.compactPaymentActions(in: snapshot)) { action in
                Button {
                    runAction(action)
                } label: {
                    Image(systemName: action.type == "resolve_choice" ? "sparkles" : "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .black))
                }
                .buttonStyle(IconButtonStyle(small: true))
                .disabled(pendingActionId != nil)
                .accessibilityLabel(Self.paymentCancelTitle(for: action))
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var paymentPipRow: some View {
        if let pips = remainingPips, pips.total > 0 {
            HStack(spacing: 3) {
                if pips.generic > 0 {
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.55))
                        Text("\(pips.generic)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)
                }
                ForEach(Array(pips.orderedColors.enumerated()), id: \.offset) { entry in
                    ForEach(0..<entry.element.count, id: \.self) { _ in
                        paymentManaButton(
                            symbol: entry.element.symbol,
                            label: "Pay {\(entry.element.symbol)}",
                            pendingId: "\(prompt.id)-pip-\(entry.element.symbol)-\(entry.offset)",
                            size: 18
                        )
                    }
                }
            }
        } else if !requiredManaSymbols.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(requiredManaSymbols.enumerated()), id: \.offset) { _, symbol in
                    if let amount = Int(symbol) {
                        Text("\(amount)").font(.caption.bold()).frame(width: 24, height: 24).background(.gray, in: Circle())
                    } else {
                        ManaSymbolView(symbol: symbol, size: 24)
                    }
                }
            }
            .accessibilityLabel(requiredManaText)
        } else {
            Text(requiredManaText)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var requiredManaSymbols: [String] {
        let text = snapshot.manaPayment?.remainingText ?? prompt.message
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9WUBRGC/XP]+)\\}") else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range(at: 1)) }
    }

    static func manaUndoActions(in snapshot: GameSnapshot) -> [LegalAction] {
        let undoTypes = Set(["undo_mana", "cancel_payment", "cancel_mana_payment"])
        return (snapshot.legalActions ?? [])
            .filter { action in
                if undoTypes.contains(action.type) { return true }
                guard snapshot.source == "xmage-ondevice", let prompt = snapshot.promptEnvelopeV2,
                      CompactPromptPopup.isManaPaymentPrompt(prompt) else { return false }
                return action.type == "resolve_choice" && action.choiceIds == ["special"]
                    && action.promptId == (prompt.responseCommand?.promptId ?? prompt.id)
                    && action.messageId == (prompt.responseCommand?.messageId ?? prompt.messageId)
                    && action.playerId == prompt.playerId
            }
    }

    static func compactPaymentActions(in snapshot: GameSnapshot) -> [LegalAction] {
        Array(manaUndoActions(in: snapshot).prefix(snapshot.source == "xmage-ondevice" ? 2 : 1))
    }

    static func paymentCancelTitle(for action: LegalAction) -> String {
        switch action.type {
        case "resolve_choice" where action.choiceIds == ["special"]:
            return action.label
        case "cancel_payment", "cancel_mana_payment":
            return "Cancel cast"
        case "undo_mana":
            return "Undo mana"
        default:
            return action.shortLabel ?? action.displayLabel
        }
    }

    static func payableManaChoiceSymbols(in snapshot: GameSnapshot, prompt: PromptEnvelopeV2) -> [String] {
        (prompt.manaChoices ?? [])
            .map { $0.manaType ?? $0.id }
            .filter { canPay(symbol: $0, in: snapshot) }
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

    static func canPay(symbol: String, in snapshot: GameSnapshot) -> Bool {
        if manaPoolValue(symbol, in: snapshot) > 0 { return true }
        return symbol == "C" && ["W", "U", "B", "R", "G", "C"].contains { manaPoolValue($0, in: snapshot) > 0 }
    }

    private static func manaPoolValue(_ symbol: String, in snapshot: GameSnapshot) -> Int {
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

    private var requiredManaText: String {
        let message = prompt.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Tap for mana"
        }
        return message.count > 28 ? "Pay mana" : message
    }

    private var hasBattlefieldManaSources: Bool {
        (snapshot.legalActions ?? []).contains {
            $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil)
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

    private func paymentManaButton(symbol: String, label: String, pendingId: String, size: CGFloat) -> some View {
        let type = snapshot.source == "xmage-ondevice" ? "play_mana" : prompt.responseCommand?.type ?? "play_mana"
        let paymentCommand = command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol)
        return Button {
            if let command = paymentCommand {
                runCommand(command, label, pendingId)
            }
        } label: {
            ManaSymbolView(symbol: symbol, size: size)
                .opacity(canPay(symbol) && promptExposesManaChoice(symbol) ? 1 : 0.42)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(pendingActionId != nil || !canPay(symbol) || !promptExposesManaChoice(symbol) || paymentCommand == nil)
    }

    private func canPay(_ symbol: String) -> Bool {
        if snapshot.source == "xmage-ondevice" {
            // The prompt can belong to a controlled player's pool, not the viewer's.
            return (prompt.manaChoices?.first { ($0.manaType ?? $0.id) == symbol }?.amount ?? 0) > 0
        }
        return Self.canPay(symbol: symbol, in: snapshot)
    }

    private func promptExposesManaChoice(_ symbol: String) -> Bool {
        guard let choices = prompt.manaChoices, !choices.isEmpty else { return false }
        return choices.contains { ($0.manaType ?? $0.id) == symbol }
    }

}

struct CombatSubmitPill: View {
    let title: String
    let count: Int
    let submit: () -> Void

    var body: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .black))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                Text("\(count)")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.28), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(MagicPalette.oxblood.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.45), lineWidth: 1.2))
            .shadow(color: MagicPalette.oxblood.opacity(0.42), radius: 10)
        }
        .buttonStyle(.plain)
    }
}

struct CombatHighlightSet {
    let cardIds: Set<String>
    let defenderIds: Set<String>

    init(selection: CombatSelectionState, actions: [LegalAction], combatGroups: [XmageCombatGroup]) {
        var cards = Set<String>()
        cards.formUnion(selection.attackerHighlightIds(actions: actions))
        cards.formUnion(selection.blockerHighlightIds(actions: actions))
        cards.formUnion(selection.attackingCreatureHighlightIds(actions: actions, combatGroups: combatGroups))
        cards.formUnion(selection.selectedAttackerIds)
        if let blocker = selection.selectedBlockerId {
            cards.insert(blocker)
        }
        let defenders = selection.defenderHighlightIds(actions: actions)
        cards.formUnion(defenders)
        self.cardIds = cards
        self.defenderIds = defenders
    }

    func matches(card: ZoneCard) -> Bool {
        CombatSelectionState.matchingCardId(for: card, in: cardIds) != nil
    }

    func matches(id: String) -> Bool {
        cardIds.contains(id) || defenderIds.contains(id)
    }
}

struct CombatSelectionState: Equatable {
    var selectedAttackerIds: Set<String> = []
    var selectedBlockerId: String?
    private(set) var blockerPairs: [BlockDeclaration] = []

    var hasPendingBlockers: Bool { !blockerPairs.isEmpty }
    var blockerPairCount: Int { blockerPairs.count }
    var selectedAttackerId: String? { selectedAttackerIds.count == 1 ? selectedAttackerIds.first : nil }

    static func matchingCardId(for card: ZoneCard, in ids: Set<String>) -> String? {
        if ids.contains(card.instanceId) {
            return card.instanceId
        }
        if ids.contains(card.id) {
            return card.id
        }
        return nil
    }

    mutating func toggleAttacker(_ id: String) {
        if selectedAttackerIds.contains(id) {
            selectedAttackerIds.remove(id)
        } else {
            selectedAttackerIds.insert(id)
        }
    }

    mutating func selectAttacker(_ id: String) {
        selectedAttackerIds = [id]
    }

    mutating func selectBlocker(_ id: String) {
        selectedBlockerId = id
    }

    mutating func pairSelectedBlocker(withAttackerId attackerId: String) {
        guard let blockerId = selectedBlockerId else { return }
        let pair = BlockDeclaration(blockerId: blockerId, attackerId: attackerId)
        if !blockerPairs.contains(pair) {
            blockerPairs.append(pair)
        }
        selectedBlockerId = nil
    }

    mutating func clearAttackers() {
        selectedAttackerIds.removeAll()
    }

    mutating func clearBlockers() {
        selectedBlockerId = nil
        blockerPairs.removeAll()
    }

    mutating func resetIfInactive(_ snapshot: GameSnapshot) {
        if !Self.isDeclareAttackers(snapshot) {
            clearAttackers()
        }
        if !Self.isDeclareBlockers(snapshot) {
            clearBlockers()
        }
    }

    func attackerHighlightIds(actions: [LegalAction]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_attackers" }
            .flatMap { Self.attackers(in: $0).map(\.attackerId) })
        ids.formUnion(actions
            .filter { $0.type == "declare_attackers" }
            .compactMap { $0.effectiveCardInstanceId ?? $0.effectiveSourceInstanceId })
        return ids
    }

    func defenderHighlightIds(actions: [LegalAction]) -> Set<String> {
        Set(actions
            .filter { $0.type == "declare_attackers" }
            .flatMap { action in
                var ids = Self.attackers(in: action).compactMap(\.defenderId)
                ids.append(contentsOf: action.validTargetIds ?? [])
                ids.append(contentsOf: action.validPlayerIds ?? [])
                ids.append(contentsOf: action.playerIds ?? [])
                ids.append(contentsOf: action.targetIds ?? [])
                return ids
            })
    }

    func defenderIds(forAttackerId attackerId: String, actions: [LegalAction]) -> Set<String> {
        Set(actions
            .filter { $0.type == "declare_attackers" }
            .flatMap { action -> [String] in
                let attackerIds = Set(Self.attackers(in: action).map(\.attackerId))
                let actionCardId = action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId
                guard attackerIds.contains(attackerId) || actionCardId == attackerId else { return [] }
                var ids = Self.attackers(in: action).compactMap(\.defenderId)
                ids.append(contentsOf: action.validTargetIds ?? [])
                ids.append(contentsOf: action.validPlayerIds ?? [])
                ids.append(contentsOf: action.playerIds ?? [])
                ids.append(contentsOf: action.targetIds ?? [])
                return ids
            })
    }

    func defenderKind(forDefenderId defenderId: String, actions: [LegalAction]) -> String? {
        actions.first { action in
            action.type == "declare_attackers" &&
                Self.attackers(in: action).contains { $0.defenderId == defenderId }
        }?.defenderKind
    }

    func blockerHighlightIds(actions: [LegalAction]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_blockers" }
            .flatMap { Self.blockers(in: $0).map(\.blockerId) })
        ids.formUnion(actions
            .filter { $0.type == "declare_blockers" }
            .compactMap { $0.effectiveCardInstanceId ?? $0.effectiveSourceInstanceId })
        return ids
    }

    func attackingCreatureHighlightIds(actions: [LegalAction], combatGroups: [XmageCombatGroup]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_blockers" }
            .flatMap { Self.blockers(in: $0).compactMap(\.attackerId) })
        ids.formUnion(combatGroups.flatMap { $0.attackers.map(\.instanceId) })
        return ids
    }

    func attackingCreatureIds(forBlockerId blockerId: String, actions: [LegalAction], combatGroups: [XmageCombatGroup]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_blockers" }
            .flatMap { action in
                Self.blockers(in: action)
                    .filter { $0.blockerId == blockerId }
                    .compactMap(\.attackerId)
            })
        if ids.isEmpty {
            ids.formUnion(combatGroups.flatMap { $0.attackers.map(\.instanceId) })
        }
        return ids
    }

    func attackAction(forDefenderId defenderId: String, actions: [LegalAction]) -> LegalAction? {
        guard selectedAttackerIds.count == 1, let attackerId = selectedAttackerIds.first else { return nil }
        return actions.first { action in
            guard action.type == "declare_attackers" else { return false }
            return Self.attackers(in: action).contains { $0.attackerId == attackerId && $0.defenderId == defenderId }
        }
    }

    func attackCommand(gameId: String, playerId: String, defenderId: String, actions: [LegalAction], expectedBridgeRevision: Int?) -> GameCommand? {
        let legalAttackers = attackerHighlightIds(actions: actions)
        guard !selectedAttackerIds.isEmpty, selectedAttackerIds.isSubset(of: legalAttackers) else { return nil }
        return GameCommand(
            type: "declare_attackers",
            gameId: gameId,
            playerId: playerId,
            attackers: selectedAttackerIds.sorted().map { AttackDeclaration(attackerId: $0, defenderId: defenderId) },
            combatComplete: false,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    func pendingBlockActionPayload(playerId: String, gameId: String, expectedBridgeRevision: Int? = nil) -> GameCommand? {
        guard !blockerPairs.isEmpty else { return nil }
        return GameCommand(
            type: "declare_blockers",
            gameId: gameId,
            playerId: playerId,
            blockers: blockerPairs,
            combatComplete: false,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    static func finishAttackCommand(gameId: String, playerId: String, expectedBridgeRevision: Int?) -> GameCommand {
        GameCommand(
            type: "declare_attackers",
            gameId: gameId,
            playerId: playerId,
            attackers: [],
            combatComplete: true,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    static func finishBlockCommand(gameId: String, playerId: String, expectedBridgeRevision: Int?) -> GameCommand {
        GameCommand(
            type: "declare_blockers",
            gameId: gameId,
            playerId: playerId,
            blockers: [],
            combatComplete: true,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    static func isDeclareAttackers(_ snapshot: GameSnapshot) -> Bool {
        snapshot.legalActions?.contains(where: { $0.type == "declare_attackers" }) == true
    }

    static func isDeclareBlockers(_ snapshot: GameSnapshot) -> Bool {
        snapshot.legalActions?.contains(where: { $0.type == "declare_blockers" }) == true
    }

    private static func attackers(in action: LegalAction) -> [AttackDeclaration] {
        if let attackers = action.attackers, !attackers.isEmpty {
            return attackers
        }
        guard case .array(let values)? = action.commandTemplate?["attackers"] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value,
                  let attackerId = object["attackerId"]?.stringValue
            else { return nil }
            return AttackDeclaration(attackerId: attackerId, defenderId: object["defenderId"]?.stringValue)
        }
    }

    private static func blockers(in action: LegalAction) -> [BlockDeclaration] {
        if let blockers = action.blockers, !blockers.isEmpty {
            return blockers
        }
        guard case .array(let values)? = action.commandTemplate?["blockers"] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value,
                  let blockerId = object["blockerId"]?.stringValue
            else { return nil }
            return BlockDeclaration(blockerId: blockerId, attackerId: object["attackerId"]?.stringValue)
        }
    }
}

enum CombatArrowKind: Equatable {
    case attack
    case blockedAttack
    case block
    case previewAttack
    case previewBlock
}

struct CombatArrow: Equatable {
    let kind: CombatArrowKind
    let fromId: String
    let toId: String
    let toKind: String?
}

enum CombatArrowModel {
    static func arrows(from groups: [XmageCombatGroup]) -> [CombatArrow] {
        groups.flatMap { group in
            let attackKind: CombatArrowKind = group.blocked ? .blockedAttack : .attack
            let attacks = group.attackers.map {
                CombatArrow(kind: attackKind, fromId: $0.instanceId, toId: group.defenderId, toKind: group.defenderKind)
            }
            let blocks = group.blockers.flatMap { blocker in
                group.attackers.map { attacker in
                    CombatArrow(kind: .block, fromId: blocker.instanceId, toId: attacker.instanceId, toKind: nil)
                }
            }
            return attacks + blocks
        }
    }

    static func arrows(from groups: [XmageCombatGroup], previewArrows: [CombatArrow]) -> [CombatArrow] {
        arrows(from: groups) + previewArrows
    }
}

struct CombatArrowOverlay: View {
    let snapshot: GameSnapshot
    let groups: [XmageCombatGroup]
    let previewArrows: [CombatArrow]
    let metrics: BattlefieldLayoutMetrics
    let humanBattlefield: [ZoneCard]
    let opponentBattlefield: [ZoneCard]
    var renderedBounds: [String: CGRect] = [:]

    var body: some View {
        let anchors = cardAnchors()
        Canvas { context, _ in
            for arrow in CombatArrowModel.arrows(from: groups, previewArrows: previewArrows) {
                guard let start = anchors[arrow.fromId] else { continue }
                guard let end = anchors[arrow.toId] ?? defenderAnchor(for: arrow.toId, kind: arrow.toKind) else { continue }
                drawArrow(arrow, from: start, to: end, in: &context)
            }
        }
    }

    private func cardAnchors() -> [String: CGPoint] {
        CombatViewportAnchors.resolve(bounds: renderedBounds,
            authorizedIDs: Set((humanBattlefield + opponentBattlefield).map(\.instanceId)),
            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect,
                        metrics.playerBattlefieldRect, metrics.playerLandsRect],
            laneIndices: CombatViewportAnchors.laneIndices(human: humanBattlefield, opponent: opponentBattlefield)).mapValues(\.point)
    }

    private func defenderAnchor(for defenderId: String, kind: String?) -> CGPoint? {
        CombatPlayerIdentity.defenderAnchor(for: defenderId, kind: kind, metrics: metrics, snapshot: snapshot)
    }

    private func drawArrow(_ arrow: CombatArrow, from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let color: Color
        switch arrow.kind {
        case .attack:
            color = MagicPalette.oxblood
        case .blockedAttack:
            color = .gray
        case .block:
            color = MagicPalette.arcaneBlue
        case .previewAttack:
            color = MagicPalette.warningAmber
        case .previewBlock:
            color = MagicPalette.arcaneBlue
        }
        let isPreview = arrow.kind == .previewAttack || arrow.kind == .previewBlock
        context.stroke(path, with: .color(color.opacity(isPreview ? 0.48 : 0.82)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round, dash: isPreview ? [6, 5] : []))

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 9
        let left = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.move(to: end)
        head.addLine(to: right)
        context.stroke(head, with: .color(color.opacity(isPreview ? 0.56 : 0.92)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round))
    }

    private func nonLandCards(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { !$0.card.isLand }
    }

    private func landCards(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { $0.card.isLand }
    }
}

private enum GameBoardMotion {
    static func largeText(_ preference: DynamicTypeSize) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" { return true }
        #endif
        return preference.isAccessibilitySize
    }

    static func reduced(_ systemPreference: Bool) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" { return true }
        #endif
        return systemPreference
    }
}

private struct PortraitCardBoundsKey: PreferenceKey {
    // Resolve anchors in the current board layout, never a stored rectangle from
    // the previous orientation or a delayed preference callback.
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum VisibleCombatAnchors {
    static func resolve(bounds: [String: CGRect], authorizedIDs: Set<String>, viewports: [CGRect]) -> [String: CGPoint] {
        bounds.filter { id, rect in
            authorizedIDs.contains(id) && !rect.isEmpty && viewports.contains { $0.contains(rect) }
        }.mapValues { CGPoint(x: $0.midX, y: $0.midY) }
    }
}

private struct HandCardBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PortraitCombatArrowOverlay: View {
    let snapshot: GameSnapshot
    let groups: [XmageCombatGroup]
    let previewArrows: [CombatArrow]
    let metrics: PortraitBattlefieldLayoutMetrics
    let humanBattlefield: [ZoneCard]
    let opponentBattlefield: [ZoneCard]

    var renderedBounds: [String: CGRect] = [:]
    var focusedOpponentID: String?

    var body: some View {
        let anchors = CombatViewportAnchors.resolve(bounds: renderedBounds,
            authorizedIDs: Set((humanBattlefield + opponentBattlefield).map(\.instanceId)),
            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect],
            laneIndices: CombatViewportAnchors.laneIndices(human: humanBattlefield, opponent: opponentBattlefield)).mapValues(\.point)
        Canvas { context, _ in
            for arrow in CombatArrowModel.arrows(from: groups, previewArrows: previewArrows) {
                guard let start = anchors[arrow.fromId] else { continue }
                guard let end = anchors[arrow.toId] ?? playerAnchor(arrow.toId, kind: arrow.toKind) else { continue }
                drawArrow(arrow, from: start, to: end, in: &context)
            }
        }
    }

    private func playerAnchor(_ id: String, kind: String?) -> CGPoint? {
        guard kind == nil || kind?.lowercased() == "player" else { return nil }
        let rect: CGRect
        if CombatPlayerIdentity.ids(for: snapshot.viewerID, in: snapshot).contains(id) { rect = metrics.bottomControlsRect }
        else if let focusedOpponentID, CombatPlayerIdentity.ids(for: focusedOpponentID, in: snapshot).contains(id) { rect = metrics.topHUDRect }
        else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func drawArrow(_ arrow: CombatArrow, from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let color: Color
        switch arrow.kind {
        case .attack:
            color = MagicPalette.oxblood
        case .blockedAttack:
            color = .gray
        case .block:
            color = MagicPalette.arcaneBlue
        case .previewAttack:
            color = MagicPalette.warningAmber
        case .previewBlock:
            color = MagicPalette.arcaneBlue
        }
        let isPreview = arrow.kind == .previewAttack || arrow.kind == .previewBlock
        context.stroke(path, with: .color(color.opacity(isPreview ? 0.48 : 0.82)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round, dash: isPreview ? [6, 5] : []))

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 9
        let left = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.move(to: end)
        head.addLine(to: right)
        context.stroke(head, with: .color(color.opacity(isPreview ? 0.56 : 0.92)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round))
    }
}

enum CombatPlayerIdentity {
    enum Side { case viewer, opponent }
    enum DefenderKind: String { case player, planeswalker, battle }

    static func ids(for playerID: String, in snapshot: GameSnapshot) -> [String] {
        let engineIDs = snapshot.xmage?.players.filter { $0.playerId == playerID }.compactMap(\.xmagePlayerId) ?? []
        return [playerID] + engineIDs
    }

    static func targetID(for playerID: String, in snapshot: GameSnapshot, candidates: Set<String>) -> String? {
        ids(for: playerID, in: snapshot).first { candidates.contains($0) }
    }

    static func side(for defenderID: String, kind: String?, in snapshot: GameSnapshot) -> Side? {
        // A permanent must use its card anchor, even if its ID resembles a seat ID.
        guard kind == nil || kind.flatMap({ DefenderKind(rawValue: $0.lowercased()) }) == .player else { return nil }
        if ids(for: snapshot.viewerID, in: snapshot).contains(defenderID) { return .viewer }
        if let opponentID = snapshot.opponent?.playerId,
           ids(for: opponentID, in: snapshot).contains(defenderID) { return .opponent }
        // Other seats have no HUD anchor in the current two-sided board projection.
        return nil
    }

    static func defenderAnchor(for defenderID: String, kind: String?, metrics: BattlefieldLayoutMetrics, snapshot: GameSnapshot) -> CGPoint? {
        guard let side = side(for: defenderID, kind: kind, in: snapshot) else { return nil }
        let rect = side == .viewer ? metrics.playerBattlefieldRect : metrics.opponentBattlefieldRect
        return CGPoint(x: metrics.boardColumnRect.minX + 10, y: rect.midY)
    }
}

enum PortraitCombatAnchorResolver {
    static func cardAnchors(metrics: PortraitBattlefieldLayoutMetrics, humanBattlefield: [ZoneCard], opponentBattlefield: [ZoneCard]) -> [String: CGPoint] {
        var anchors: [String: CGPoint] = [:]
        addAnchors(for: opponentBattlefield.filter { !$0.card.isLand }, rect: metrics.opponentBattlefieldRect, cardWidth: metrics.permanentCardWidth, into: &anchors)
        addAnchors(for: opponentBattlefield.filter { $0.card.isLand }, rect: metrics.opponentLandsRect, cardWidth: metrics.landCardWidth, into: &anchors)
        addAnchors(for: humanBattlefield.filter { !$0.card.isLand }, rect: metrics.playerBattlefieldRect, cardWidth: metrics.permanentCardWidth, into: &anchors)
        addAnchors(for: humanBattlefield.filter { $0.card.isLand }, rect: metrics.playerLandsRect, cardWidth: metrics.landCardWidth, into: &anchors)
        return anchors
    }

    static func defenderAnchor(for defenderId: String, kind: String?, metrics: PortraitBattlefieldLayoutMetrics) -> CGPoint {
        // Preserve the legacy helper surface for existing callers and geometry tests.
        if (kind == nil || kind?.lowercased() == "player"), ["human", "ai", "ai-1"].contains(defenderId) {
            let rect = defenderId == "human" ? metrics.bottomHUDRect : metrics.topHUDRect
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return CGPoint(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)
    }

    static func defenderAnchor(for defenderId: String, kind: String?, metrics: PortraitBattlefieldLayoutMetrics, snapshot: GameSnapshot) -> CGPoint? {
        guard let side = CombatPlayerIdentity.side(for: defenderId, kind: kind, in: snapshot) else { return nil }
        let rect = side == .viewer ? metrics.bottomHUDRect : metrics.topHUDRect
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func addAnchors(for cards: [ZoneCard], rect: CGRect, cardWidth: CGFloat, into anchors: inout [String: CGPoint]) {
        guard !cards.isEmpty else { return }
        let spacing: CGFloat = 4
        let totalWidth = CGFloat(cards.count) * cardWidth + CGFloat(max(cards.count - 1, 0)) * spacing
        let startX = rect.midX - totalWidth / 2 + cardWidth / 2
        for (index, card) in cards.enumerated() {
            anchors[card.instanceId] = CGPoint(x: startX + CGFloat(index) * (cardWidth + spacing), y: rect.midY)
        }
    }
}

struct PortraitOpponentStatusBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: GameSnapshot
    let opponentName: String
    let opponent: PlayerGameState
    let humanId: String
    let combatTargetable: Bool
    let combatTargetAction: () -> Void
    let openLog: () -> Void
    var viewZone: ((String, [ZoneCard]) -> Void)? = nil
    var selectOpponent: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Button { if combatTargetable { combatTargetAction() } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(opponentName).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    BoardLifeTotal(life: opponent.life, suffix: " life").id(opponent.playerId)
                        .font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(MagicPalette.antiqueGold)
                }
            }
            .buttonStyle(.plain)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 100 : 80)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(combatTargetable ? Color.red : .clear, lineWidth: 2))
            .accessibilityLabel("\(opponentName), \(opponent.life) life")
            VStack(alignment: .leading, spacing: 3) {
                Text((snapshot.step ?? snapshot.phase).arenaPhaseTitle).font(.caption.bold())
                Text(BoardResponseCue.make(snapshot)?.title ?? (snapshot.isViewer(snapshot.priorityPlayerId) ? "Your priority" : "\(snapshot.playerLabel(snapshot.priorityPlayerId)) priority"))
                    .font(.caption2.bold()).foregroundStyle(BoardResponseCue.make(snapshot) == nil ? MagicPalette.parchment : MagicPalette.antiqueGold).lineLimit(2).minimumScaleFactor(0.75)
                    .accessibilityIdentifier("board.response.status")
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let selectOpponent { OpponentFocusMenu(snapshot: snapshot, selectOpponent: selectOpponent) }
            BoardPlayerEffects(player: opponent, attachments: BattlefieldAttachments.enchanting(playerID: opponent.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: viewZone)
            if let viewZone { PlayerZoneMenu(player: opponent, viewZone: viewZone) }
            Button(action: openLog) { Image(systemName: "text.book.closed").frame(width: 44, height: 44) }
                .accessibilityLabel("Game log")
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(.horizontal, 5)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(MagicPalette.antiqueGold.opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.34), radius: 10, y: 5)
    }
}

private struct PortraitOpponentCommanderHUD: View {
    let name: String
    let player: PlayerGameState
    var active = false
    var opponentId: String?
    var combatTargetable = false
    var combatTargetAction: (() -> Void)?

    private var summary: CommanderHudSummary {
        CommanderHudSummary(player: player, opponentId: opponentId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PlayerAvatar(data: nil, size: 28, active: active)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 9, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(summary.life) LIFE")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(MagicPalette.antiqueGold)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(31), spacing: 3), count: 3), spacing: 3) {
                CompactCommanderStat(label: "CMD", value: summary.commanderTax)
                CompactCommanderStat(label: "HAND", value: summary.handCount)
                CompactCommanderStat(label: "LIB", value: summary.libraryCount)
                CompactCommanderStat(label: "GY", value: summary.graveyardCount)
                CompactCommanderStat(label: "EX", value: summary.exileCount)
                CompactCommanderStat(label: "DMG", value: summary.commanderDamage)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MagicPalette.iron.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(combatTargetable ? MagicPalette.oxblood : MagicPalette.antiqueGold.opacity(active ? 0.72 : 0.28), lineWidth: combatTargetable ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if combatTargetable {
                combatTargetAction?()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(summary.life) life, \(summary.handCount) cards in hand, \(summary.libraryCount) cards in library")
        .accessibilityHint(combatTargetable ? "Double tap to attack this player" : "")
    }
}

private struct CompactCommanderStat: View {
    let label: String
    let value: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 5.5, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold.opacity(0.78))
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 7.5, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 31, height: 18)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct PhaseStatusTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .black))
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MagicPalette.antiqueGold, MagicPalette.brass],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
    }
}

struct PortraitBattlefieldRowPlan: Equatable {
    let rows: [[ZoneCard]]
    let cardsPerRow: Int
    let overflowsHorizontally: Bool
}

enum PortraitBattlefieldRowPlanner {
    static func plan(cards: [ZoneCard], rowWidth: CGFloat, cardWidth: CGFloat, maxRows: Int = 3) -> PortraitBattlefieldRowPlan {
        guard !cards.isEmpty else {
            return PortraitBattlefieldRowPlan(rows: [[]], cardsPerRow: 1, overflowsHorizontally: false)
        }
        let visibleCards = Array(cards.prefix(10))
        let rowCount: Int
        if visibleCards.count <= 4 {
            rowCount = 1
        } else if visibleCards.count <= 7 {
            rowCount = min(maxRows, 2)
        } else {
            rowCount = min(maxRows, 3)
        }
        let baseRowCount = max(rowCount, 1)
        let baseSize = visibleCards.count / baseRowCount
        let remainder = visibleCards.count % baseRowCount
        var rows: [[ZoneCard]] = []
        var index = 0
        for rowIndex in 0..<baseRowCount {
            let size = baseSize + (rowIndex < remainder ? 1 : 0)
            guard size > 0 else { continue }
            rows.append(Array(visibleCards[index..<(index + size)]))
            index += size
        }
        if cards.count > 10, !rows.isEmpty {
            rows[rows.count - 1].append(contentsOf: cards.dropFirst(10))
        }
        return PortraitBattlefieldRowPlan(
            rows: rows,
            cardsPerRow: rows.map(\.count).max() ?? 1,
            overflowsHorizontally: cards.count > 10
        )
    }
}

struct PortraitOverlapLayoutPlan: Equatable {
    let count: Int
    let cardWidth: CGFloat
    let containerWidth: CGFloat
    let visibleLimit: Int
    let stride: CGFloat
    let contentWidth: CGFloat
    let needsScrolling: Bool

    func xOffset(for index: Int) -> CGFloat {
        let effectiveIndex = CGFloat(max(index, 0))
        let start = contentWidth > containerWidth ? 8 : max((containerWidth - visibleContentWidth) / 2, 0)
        return start + effectiveIndex * stride
    }

    private var visibleContentWidth: CGFloat {
        guard count > 0 else { return 0 }
        let visibleCount = CGFloat(min(count, visibleLimit))
        return cardWidth + max(visibleCount - 1, 0) * stride
    }
}

enum PortraitOverlapLayout {
    static func plan(
        count: Int,
        containerWidth: CGFloat,
        cardWidth: CGFloat,
        visibleLimit: Int = 10,
        minVisibleWidth: CGFloat = 30,
        spacing: CGFloat = 6
    ) -> PortraitOverlapLayoutPlan {
        guard count > 0 else {
            return PortraitOverlapLayoutPlan(
                count: 0,
                cardWidth: cardWidth,
                containerWidth: containerWidth,
                visibleLimit: visibleLimit,
                stride: cardWidth + spacing,
                contentWidth: max(containerWidth, 0),
                needsScrolling: false
            )
        }
        let visibleCount = min(count, max(visibleLimit, 1))
        let naturalStride = cardWidth + spacing
        let fittingStride = visibleCount > 1 ? max((containerWidth - cardWidth) / CGFloat(visibleCount - 1), 1) : naturalStride
        let stride = min(naturalStride, max(fittingStride, minVisibleWidth))
        let visibleContentWidth = cardWidth + CGFloat(max(visibleCount - 1, 0)) * stride
        let needsScrolling = count > visibleLimit || visibleContentWidth > containerWidth
        let contentWidth = needsScrolling && count > visibleLimit
            ? cardWidth + CGFloat(max(count - 1, 0)) * stride
            : min(max(visibleContentWidth, cardWidth), max(containerWidth, cardWidth))
        return PortraitOverlapLayoutPlan(
            count: count,
            cardWidth: cardWidth,
            containerWidth: containerWidth,
            visibleLimit: visibleLimit,
            stride: stride,
            contentWidth: contentWidth,
            needsScrolling: needsScrolling
        )
    }
}

struct PortraitBattlefieldPermanentGroup: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let targetableIds: Set<String>
    let combatHighlightIds: Set<String>
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    let availableHeight: CGFloat
    var allowsManaUndo = false
    var manaPaymentActive = false
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void
    let runCombatCardAction: (ZoneCard) -> Bool

    var body: some View {
        BattlefieldRow(
            title: title, cards: cards, legalActions: legalActions,
            targetableIds: targetableIds, combatHighlightIds: combatHighlightIds,
            selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: flipped,
            cardWidth: cardWidth, cardHeight: cardHeight, rowWidth: rowWidth, adaptsToDensity: true,
            availableHeight: availableHeight,
            allowsManaUndo: allowsManaUndo, manaPaymentActive: manaPaymentActive,
            runAction: runAction, runTargetAction: runTargetAction, runCombatCardAction: runCombatCardAction
        )
    }
}

struct PortraitOverlappingBattlefieldRow: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let targetableIds: Set<String>
    let combatHighlightIds: Set<String>
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    var allowsManaUndo = false
    var manaPaymentActive = false
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void
    let runCombatCardAction: (ZoneCard) -> Bool

    var body: some View {
        let plan = PortraitOverlapLayout.plan(
            count: cards.count,
            containerWidth: rowWidth,
            cardWidth: cardHeight,
            visibleLimit: 3,
            minVisibleWidth: cardHeight,
            spacing: 4
        )
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: plan.needsScrolling) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        let action = legalAction(for: card)
                        let targetable = targetableIds.contains(card.instanceId) || targetableIds.contains(card.id)
                        let combatHighlighted = combatHighlightIds.contains(card.instanceId) || combatHighlightIds.contains(card.id)
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: action != nil, targetable: targetable || combatHighlighted, zoneName: title, width: cardWidth, height: cardHeight)
                            .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
                            .onCardHold(inspect: {
                                selectedCard = nil
                                inspectedCard = card
                            }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                            .offset(x: plan.xOffset(for: index) + (cardHeight - cardWidth) / 2, y: 4)
                            .zIndex(zIndex(for: index, card: card))
                            .onTapGesture {
                                        if targetable {
                                            runTargetAction(card)
                                        } else if !targetableIds.isEmpty {
                                            GameHaptics.warning()
                                        } else if combatHighlighted, runCombatCardAction(card) {
                                            return
                                        } else if let immediate = PortraitInteractionPolicy.automaticCardAction(GameBoardInteractionState.cardActions(for: card, actions: legalActions)), Self.tapRunnableActionTypes.contains(immediate.type) {
                                            runAction(immediate)
                                        } else {
                                            selectedCard = card
                                            inspectedCard = nil
                                        }
                            }
                    }
                }
                .frame(width: max(plan.contentWidth, rowWidth), height: max(cardHeight + 8, 44), alignment: .topLeading)
            }


        }
    }

    private func zIndex(for index: Int, card: ZoneCard) -> Double {
        if inspectedCard?.id == card.id || selectedCard?.id == card.id {
            return 1000
        }
        return flipped ? Double(cards.count - index) : Double(index)
    }

    private func legalAction(for card: ZoneCard) -> LegalAction? {
        if allowsManaUndo, manaPaymentActive, card.tapped == true, let undo = manaUndoAction,
           undo.sourceInstanceId == card.instanceId || undo.cardInstanceId == card.instanceId {
            return undo
        }
        return legalActions.first {
            $0.cardInstanceId == card.instanceId || $0.sourceInstanceId == card.instanceId
        }
    }

    private var manaUndoAction: LegalAction? {
        legalActions.first { Self.manaUndoActionTypes.contains($0.type) }
    }

    private static let tapRunnableActionTypes: Set<String> = [
        "activate_ability", "make_mana", "pay_mana", "undo_mana", "play_land"
    ]
    private static let manaUndoActionTypes: Set<String> = ["undo_mana"]
}

struct PortraitScrollScrubber: View {
    let progress: CGFloat
    let visible: Bool
    let drag: (CGFloat) -> Void
    @GestureState private var dragStartProgress: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 1)
            let thumbWidth = HandScrubberGeometry.thumbWidth(trackWidth: trackWidth)
            let travel = max(trackWidth - thumbWidth, 1)
            Capsule()
                .fill(.white.opacity(visible ? 0.14 : 0.0))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(MagicPalette.antiqueGold.opacity(visible ? 0.78 : 0.0))
                        .frame(width: thumbWidth)
                        .offset(x: travel * min(max(progress, 0), 1))
                }
                .frame(height: 8)
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragStartProgress) { _, start, _ in
                            if start == nil { start = progress }
                        }
                        .onChanged { value in
                            guard visible else { return }
                            let thumbStart = travel * min(max(dragStartProgress ?? progress, 0), 1)
                            let withinThumb = value.startLocation.x - thumbStart
                            let grabOffset = (0...thumbWidth).contains(withinThumb) ? withinThumb : thumbWidth / 2
                            drag(HandScrubberGeometry.progress(location: value.location.x, trackWidth: trackWidth,
                                                               grabOffset: grabOffset))
                        }
                )
        }
        .frame(height: 44)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scroll hand")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
        .accessibilityIdentifier("board.hand.scrubber")
        .accessibilityHidden(!visible)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: drag(min(1, progress + 0.1))
            case .decrement: drag(max(0, progress - 0.1))
            @unknown default: break
            }
        }
    }
}

private struct HandViewportKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct PortraitHandRow: View {
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let pendingCardInstanceId: String?
    @Binding var interactionState: GameBoardInteractionState
    let playerDropZone: CGRect
    @Binding var isOverPlayerDropZone: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    let onDropFeedback: (String) -> Void
    let onActionChoice: ([LegalAction], String) -> Void
    let runAction: (LegalAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingCardId: String?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartCenter: CGPoint = .zero
    @State private var handCardBounds: [String: CGRect] = [:]
    @State private var handViewport = CGRect.zero
    @State private var handExpanded = false
    @StateObject private var handScroll = HandScrollController()

    private var handSpacing: CGFloat { ArenaHandLayout.spacing(count: cards.count, width: rowWidth, cardWidth: cardWidth, expanded: handExpanded) }
    private var contentWidth: CGFloat { CGFloat(cards.count) * cardWidth + CGFloat(max(cards.count - 1, 0)) * handSpacing }

    var body: some View {
        let layout = handExpanded
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(ZStackLayout(alignment: .bottom))
        Group {
            layout {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: handSpacing) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            let playableActions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
                            let selected = selectedCard?.id == card.id
                            let isDragging = draggingCardId == card.id
                            CardTile(
                                card: card,
                                selected: selected,
                                pending: pendingCardInstanceId == card.instanceId,
                                legal: playableActions.contains { $0.type == "play_land" },
                                castOffered: playableActions.contains { $0.type == "cast_spell" },
                                zoneName: "Hand",
                                width: cardWidth,
                                height: cardHeight
                            )
                            .overlay(alignment: .topTrailing) {
                                HandManaCost(cost: card.card.manaCost ?? playableActions.first?.manaCost)
                                    .offset(y: -15).allowsHitTesting(false).accessibilityHidden(true)
                            }
                            .id(card.id)
                            .background { GeometryReader { geometry in
                                Color.clear.preference(key: HandCardBoundsKey.self,
                                    value: [card.id: geometry.frame(in: .named("portrait-board"))])
                            } }
                            .scaleEffect(selected ? 1.05 : 1.0)
                            .offset(y: selected ? -10 : 0)
                            .opacity(isDragging ? 0 : 1)
                            .zIndex(isDragging ? 1000 : selected ? 900 : Double(index))
                            .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: isDragging)
                            .accessibilityHint("Tap to expand your hand. Hold to inspect. Drag upward to your battlefield to play.")
                            .accessibilityAction { selectedCard = nil; inspectedCard = card }
                            .accessibilityAction(named: "Inspect card") { selectedCard = nil; inspectedCard = card }
                            .accessibilityAction(named: "Play card") {
                                switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: true) {
                                case let .submit(action): runAction(action)
                                case let .requiresChoice(actions, message): onActionChoice(actions, message)
                                case let .rejected(message): onDropFeedback(message)
                                case .ignored: break
                                }
                            }
                            .overlay {
                                HandCardPan(changed: { translation, start in
                                        if draggingCardId == nil {
                                            guard let bounds = handCardBounds[card.id] else { return }
                                            dragStartCenter = CGPoint(x: bounds.midX, y: bounds.midY)
                                        }
                                        selectedCard = nil
                                        inspectedCard = nil
                                        draggingCardId = card.id
                                        dragOffset = translation
                                        let point = CGPoint(x: dragStartCenter.x - cardWidth / 2 + start.x + translation.width,
                                                            y: dragStartCenter.y - cardHeight / 2 + start.y + translation.height)
                                        isOverPlayerDropZone = playerDropZone.contains(point)
                                        interactionState.mode = .draggingCard(
                                            cardId: card.instanceId,
                                            legalActionIds: playableActions.map(\.id)
                                        )
                                    }, ended: { translation, start, cancelled in
                                        guard draggingCardId == card.id else { return }
                                        selectedCard = nil
                                        let point = CGPoint(x: dragStartCenter.x - cardWidth / 2 + start.x + translation.width,
                                                            y: dragStartCenter.y - cardHeight / 2 + start.y + translation.height)
                                        let shouldPlay = !cancelled && playerDropZone.contains(point)
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
                                    }, inspect: { selectedCard = nil; inspectedCard = card }, tap: {
                                        if handExpanded { selectedCard = nil; inspectedCard = card }
                                        else { withAnimation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2)) { handExpanded = true } }
                                    }, releaseInspection: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                            }
                        }
                    }
                    .padding(.top, 18)
                    .frame(height: cardHeight + 20, alignment: .topLeading)
                    .padding(.horizontal, 4)
                    .background(HandScrollConnection(controller: handScroll))
                }
                .frame(height: handExpanded ? cardHeight + 20 : ArenaHandLayout.restingHeight(cardHeight: cardHeight), alignment: .top)
                .clipped()
                .accessibilityIdentifier("board.hand.scroll")
                .background { GeometryReader { geometry in
                    Color.clear.preference(key: HandViewportKey.self, value: geometry.frame(in: .named("portrait-board")))
                } }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2)) { handExpanded.toggle() }
                    } label: {
                        Label("Hand · \(cards.count)", systemImage: handExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2.bold()).padding(.horizontal, 12)
                            .frame(minHeight: 44).background(.black.opacity(0.75), in: Capsule())
                    }
                    .accessibilityLabel(handExpanded ? "Tuck hand" : "Expand hand")
                    .accessibilityIdentifier("board.hand.expand")
                    PortraitScrollScrubber(progress: handScroll.progress, visible: contentWidth + 8 > rowWidth + 1,
                                           drag: handScroll.scroll)
                }
            }
            .frame(height: ArenaHandLayout.restingHeight(cardHeight: cardHeight), alignment: .bottom)
            .onPreferenceChange(HandCardBoundsKey.self) { handCardBounds = $0; handScroll.refreshProgress() }
            .onPreferenceChange(HandViewportKey.self) { handViewport = $0; handScroll.refreshProgress() }
            .overlay {
                GeometryReader { geometry in
                    if let draggingCardId, let card = cards.first(where: { $0.id == draggingCardId }) {
                        let origin = geometry.frame(in: .named("portrait-board")).origin
                        let actions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
                        CardTile(card: card, selected: false, pending: pendingCardInstanceId == card.instanceId,
                                 legal: actions.contains { $0.type == "play_land" }, castOffered: actions.contains { $0.type == "cast_spell" },
                                 zoneName: "Hand", width: cardWidth, height: cardHeight)
                            .position(x: dragStartCenter.x + dragOffset.width - origin.x,
                                      y: dragStartCenter.y + dragOffset.height - origin.y)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: cards.map(\.id)) { _, ids in
                if let draggingCardId, !ids.contains(draggingCardId) {
                    self.draggingCardId = nil
                    dragOffset = .zero
                    isOverPlayerDropZone = false
                }
            }
            .onDisappear {
                draggingCardId = nil
                dragOffset = .zero
                isOverPlayerDropZone = false
            }
        }
    }
}

struct NativeTurnControl {
    let canEndTurn: Bool
    let canSkipResponses: Bool
    let canSkipToMyTurn: Bool
    let isAutoPassing: Bool
    let status: String?
    let endTurn: () -> Void
    let skipResponses: () -> Void
    let skipToMyTurn: () -> Void
    let stop: () -> Void
}

private struct BoardZoneInspectionActionKey: EnvironmentKey {
    static let defaultValue: ((BoardZoneReference) -> Void)? = nil
}

private struct NativeTurnControlKey: EnvironmentKey {
    static let defaultValue: NativeTurnControl? = nil
}

extension EnvironmentValues {
    var boardZoneInspectionAction: ((BoardZoneReference) -> Void)? {
        get { self[BoardZoneInspectionActionKey.self] }
        set { self[BoardZoneInspectionActionKey.self] = newValue }
    }
    var nativeTurnControl: NativeTurnControl? {
        get { self[NativeTurnControlKey.self] }
        set { self[NativeTurnControlKey.self] = newValue }
    }
}

enum LandscapeActionDockLayout {
    static let horizontalPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 4
    static let controlSpacing: CGFloat = 4
    static let primaryLineLimit = 1
    static func sidebarWidth(hasStack: Bool) -> CGFloat { hasStack ? 176 : 160 }
}

struct GameplayActionDock: View {
    @Environment(\.nativeTurnControl) private var nativeTurnControl
    let snapshot: GameSnapshot
    let passAction: LegalAction?
    let yieldActions: [LegalAction]
    let pendingActionId: String?
    var compact = false
    var landscapeSidebar = false
    var horizontal = false
    let openPromptDetails: () -> Void
    let openLog: () -> Void
    let openSettings: () -> Void
    let runAction: (LegalAction) -> Void

    private var promptActions: [LegalAction] {
        CompactPromptPopup.compactLegalPromptActions(in: snapshot)
    }

    private var hasPromptDecision: Bool {
        CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil)
    }

    private var model: GameActionDockModel {
        GameActionDockModel.make(
            snapshot: snapshot,
            passAction: passAction,
            promptActions: promptActions,
            decisionRequired: hasPromptDecision,
            pendingActionId: pendingActionId
        )
    }

    var body: some View {
        if horizontal {
            HStack(spacing: 6) {
                secondaryControl.frame(width: 44)
                controlsMenu
                primaryButton
            }
        } else {
            VStack(spacing: landscapeSidebar ? LandscapeActionDockLayout.controlSpacing : 8) {
                primaryButton
                HStack(spacing: 6) { secondaryControl; controlsMenu }
            }
        }
    }

    private var primaryButton: some View {
        VStack(spacing: 2) {
        Button {
                    if let primaryAction = model.primaryAction {
                        runAction(primaryAction)
                    } else if model.mode == .prompt {
                        openPromptDetails()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.mode == .prompt ? "sparkles" : "forward.end.fill")
                            .font(.system(size: compact ? 10 : 11, weight: .black))
                        Text(model.primaryTitle)
                            .font(.system(size: compact ? 13 : 15, weight: .bold, design: .serif))
                            .lineLimit(landscapeSidebar ? LandscapeActionDockLayout.primaryLineLimit : 2)
                            .minimumScaleFactor(0.62)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameplayDockButtonStyle(isPrimary: true))
                .disabled(!model.isPrimaryEnabled)
                .accessibilityIdentifier("board.action.primary")
                .accessibilityHint(showsPriorityHelp ? GameplayActionPresentation.priorityHint(hasStack: hasStackForPriority) : "")
            if showsPriorityHelp {
                Text(GameplayActionPresentation.priorityDetail(hasStack: hasStackForPriority))
                    .font(.caption2)
                    .foregroundStyle(MagicPalette.parchment.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
            }
        }
    }

    private var showsPriorityHelp: Bool {
        model.mode == .priority && model.isPrimaryEnabled && model.primaryAction?.type == "pass_priority"
    }

    private var hasStackForPriority: Bool {
        !snapshot.stackTopFirst.isEmpty || snapshot.players.contains { !$0.zones.stack.isEmpty }
    }

    private var controlsMenu: some View {
        Menu {
                    if model.mode == .prompt {
                        ForEach(Array(model.promptActions.dropFirst())) { action in
                            Button(action.label) {
                                runAction(action)
                            }
                            .disabled(pendingActionId != nil)
                        }
                        Button("All Choices", action: openPromptDetails)
                        Divider()
                    }
                    Button(action: openLog) {
                        Label("Game Log", systemImage: "list.bullet.rectangle")
                    }
                    if snapshot.source == "xmage-ondevice", model.mode != .prompt {
                        Button("More actions", action: openPromptDetails)
                    }
                    Button(action: openSettings) {
                        Label("Game Settings", systemImage: "gearshape.fill")
                    }
                } label: {
                    Image(systemName: model.mode == .prompt && model.promptActions.count > 1 ? "ellipsis.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 14, weight: .black))
                }
                .buttonStyle(GameplayDockMenuButtonStyle())
                .accessibilityLabel(model.mode == .prompt && model.promptActions.count > 1 ? "More choices and game controls" : "Game controls")
    }

    @ViewBuilder private var secondaryControl: some View {
            if let control = nativeTurnControl {
                if control.isAutoPassing {
                    Button(action: control.stop) {
                        secondaryLabel("Stop skipping", icon: "stop.fill")
                    }
                    .buttonStyle(GameplayDockButtonStyle(isPrimary: false))
                    .accessibilityLabel("Stop skipping")
                    .accessibilityHint(control.status ?? "Stops future automatic passes")
                } else {
                    Menu {
                        Button("End turn — skip stack responses", action: control.skipResponses)
                            .disabled(!control.canSkipResponses)
                        Button("Skip to my turn — skip stack responses", action: control.skipToMyTurn)
                            .disabled(!control.canSkipToMyTurn)
                        Button("End turn — stop for responses", action: control.endTurn)
                            .disabled(!control.canEndTurn)
                    } label: {
                        secondaryLabel("Skip…", icon: "forward.end")
                    }
                    .buttonStyle(GameplayDockButtonStyle(isPrimary: false))
                    .disabled(!control.canEndTurn && !control.canSkipResponses && !control.canSkipToMyTurn)
                    .accessibilityLabel("Skip options")
                    .accessibilityHint("Choose how long to skip responses. Required choices always stop skipping.")
                }
            } else if model.showsPromptDetails {
                Button(action: openPromptDetails) {
                    secondaryLabel("Choices", icon: "list.bullet.rectangle.portrait")
                }
                .buttonStyle(GameplayDockButtonStyle(isPrimary: false))
                .accessibilityLabel("View all choices")
            } else {
                YieldActionsControl(
                    snapshot: snapshot,
                    actions: yieldActions,
                    fontSize: compact ? 8 : 10,
                    iconOnly: horizontal,
                    runAction: runAction
                )
            }
    }

    private func secondaryLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if !horizontal { Text(title).lineLimit(2) }
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct GameplayDockButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? Color.white : MagicPalette.parchment)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                LinearGradient(
                    colors: backgroundColors(isPressed: configuration.isPressed),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isPrimary ? Color(red: 1, green: 0.79, blue: 0.39) : MagicPalette.parchment.opacity(0.25), lineWidth: isPrimary ? 1.5 : 1))
            .shadow(color: isPrimary && isEnabled ? Color.orange.opacity(0.35) : .clear, radius: 8, y: 2)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundColors(isPressed: Bool) -> [Color] {
        if isPrimary {
            return isPressed
                ? [Color(red: 0.66, green: 0.28, blue: 0.08), Color(red: 0.40, green: 0.12, blue: 0.03)]
                : [Color(red: 0.78, green: 0.31, blue: 0.065), Color(red: 0.64, green: 0.20, blue: 0.05)]
        }
        return [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.76)]
    }
}

private struct GameplayDockMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MagicPalette.parchment)
            .frame(width: 44, height: 44)
            .background(configuration.isPressed ? MagicPalette.brass.opacity(0.62) : MagicPalette.iron.opacity(0.84), in: Circle())
            .overlay(Circle().stroke(MagicPalette.parchment.opacity(0.25), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct PortraitPlayerCommanderHUD: View {
    let name: String
    let player: PlayerGameState
    let opponentId: String
    let active: Bool
    let viewZone: (String, [ZoneCard]) -> Void

    private var summary: CommanderHudSummary {
        CommanderHudSummary(player: player, opponentId: opponentId)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 9, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.trailing, 36)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("YOU")
                        .font(.system(size: 6, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MagicPalette.arcaneBlue.opacity(0.80), in: Capsule())
                    Text("\(summary.life)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("\(summary.life) life")
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    CompactCommanderStat(label: "CMD", value: summary.commanderTax)
                    CompactCommanderStat(label: "HAND", value: summary.handCount)
                    CompactCommanderStat(label: "LIB", value: summary.libraryCount)
                    CompactCommanderStat(label: "GY", value: summary.graveyardCount)
                    CompactCommanderStat(label: "EX", value: summary.exileCount)
                    CompactCommanderStat(label: "DMG", value: summary.commanderDamage)
                }
            }

            Menu {
                Button(summary.commandZoneLabel) { viewZone("Command", player.zones.command) }
                Button("Graveyard (\(summary.graveyardCount))") { viewZone("Graveyard", player.zones.graveyard) }
                Button("Exile (\(summary.exileCount))") { viewZone("Exile", player.zones.exile) }
            } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(MagicPalette.parchment)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Open your zones")
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MagicPalette.iron.opacity(0.60), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(active ? 0.62 : 0.26), lineWidth: active ? 1.4 : 1))
    }
}

struct PortraitBottomCommandBar: View {
    let humanName: String
    let human: PlayerGameState
    let opponentId: String
    let manaPool: ManaPool?
    let passAction: LegalAction?
    let yieldActions: [LegalAction]
    let pendingActionId: String?
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let openLog: () -> Void
    let openSettings: () -> Void
    let openPromptDetails: () -> Void
    let viewZone: (String, [ZoneCard]) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    @State private var isStackOpen = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    PlayerZoneMenu(player: human, viewZone: viewZone, snapshot: snapshot, pendingActionID: pendingActionId)
                    BoardPlayerEffects(player: human, attachments: BattlefieldAttachments.enchanting(playerID: human.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: viewZone)
                    ScrollView(.horizontal, showsIndicators: false) {
                        ManaPoolHUD(manaPool: manaPool, compact: true,
                            payableSymbols: GameplayAffordances.floatingManaSymbols(in: snapshot, pendingActionID: pendingActionId),
                            payMana: { symbol in
                                if pendingActionId == nil, let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                                    runCommand(command, "Spend floating {\(symbol)}", "floating-\(snapshot.promptEnvelopeV2?.id ?? "")-\(symbol)")
                                }
                            })
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Floating mana; swipe to view all colors")
                    Button { isStackOpen = true } label: {
                        Label("\(snapshot.xmage?.stack.count ?? human.zones.stack.count)", systemImage: "square.stack.3d.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Inspect stack")
                }
                HStack(spacing: 8) {
                    VStack(spacing: 0) {
                        Image(systemName: "heart.fill").font(.system(size: 9))
                            .foregroundStyle(MagicPalette.antiqueGold)
                        BoardLifeTotal(life: human.life).id(human.playerId)
                            .font(.system(size: 23, weight: .bold, design: .serif))
                            .foregroundStyle(.white).monospacedDigit()
                    }
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(MagicPalette.antiqueGold.opacity(0.65), lineWidth: 2))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your life: \(human.life)")
                    GameplayActionDock(
                        snapshot: snapshot,
                        passAction: passAction,
                        yieldActions: yieldActions,
                        pendingActionId: pendingActionId,
                        horizontal: true,
                        openPromptDetails: openPromptDetails,
                        openLog: openLog,
                        openSettings: openSettings,
                        runAction: runAction
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            .onAppear {
                #if DEBUG
                isStackOpen = snapshot.id == "design-preview-stack-response-prompt"
                #endif
            }
            .sheet(isPresented: $isStackOpen) {
                BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
            }
        }
    }
}

private struct BoardStackInspector: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeTurnControl) private var turnControl
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            HStack {
                Text("Stack").font(.headline)
                Spacer()
                if let turnControl, turnControl.isAutoPassing {
                    Button("Stop skipping", action: turnControl.stop)
                        .frame(minHeight: 44)
                }
                Button("Done") { inspectedCard = nil; dismiss() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("board.stack.done")
            }
            PortraitStackLane(snapshot: snapshot, humanStack: snapshot.human?.zones.stack ?? [],
                              legalActions: snapshot.legalActions ?? [],
                              selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                              horizontal: geometry.size.width > geometry.size.height)
                .overlay {
                    if let inspectedCard {
                        CardInspector(card: inspectedCard)
                            .overlay(alignment: .topTrailing) {
                                Button("Close card") { self.inspectedCard = nil }
                                    .frame(minHeight: 44).padding(8)
                            }
                            .inspectionTouchPassthrough()
                    }
                }
        }
        .padding(12)
        }
        .presentationDetents([.height(460), .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }
}

/// Only the engine's authorized zone projection is ever presented.
private struct PlayerZoneMenu: View {
    @Environment(\.boardZoneInspectionAction) private var inspectZone
    let player: PlayerGameState
    let viewZone: (String, [ZoneCard]) -> Void
    var snapshot: GameSnapshot? = nil
    var pendingActionID: String? = nil

    private var commanderReady: Bool {
        snapshot.map { GameplayAffordances.commanderCastAvailable(player: player, snapshot: $0, pendingActionID: pendingActionID) } ?? false
    }

    var body: some View {
        Menu {
            Button(commanderReady ? "Command · Cast available" : "Command · \(player.zones.command.count)") { open(.command, player.zones.command) }
            Button("Graveyard · \(player.zones.graveyard.count)") { open(.graveyard, player.zones.graveyard) }
            Button("Exile · \(player.zones.exile.count)") { open(.exile, player.zones.exile) }
            Button("Hand · \(player.zones.visibleHandCount)") { open(.hand, player.zones.hand) }
            Button("Library · \(player.zones.visibleLibraryCount)") { open(.library, player.zones.library) }
            Button("Battlefield · \(player.zones.battlefield.count)") { open(.battlefield, player.zones.battlefield) }
            if let snapshot {
                Divider()
                ForEach(BoardZoneReference.namedReferences(in: snapshot), id: \.self) { reference in
                    Button("\(reference.title(in: snapshot)) · \(reference.cards(in: snapshot).count)") {
                        if let inspectZone { inspectZone(reference) }
                        else { viewZone(reference.title(in: snapshot), reference.cards(in: snapshot)) }
                    }
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(commanderReady ? .white : MagicPalette.parchment)
                .background(commanderReady ? MagicPalette.antiqueGold.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(commanderReady ? .white.opacity(0.9) : .clear, lineWidth: 1.5))
                .shadow(color: commanderReady ? MagicPalette.antiqueGold.opacity(0.75) : .clear, radius: 7)
        }
        .accessibilityLabel("\(player.displayName ?? player.playerId) zones\(commanderReady ? ", commander cast available" : "")")
        .accessibilityIdentifier("board.zones.\(player.playerId)")
    }

    private func open(_ zone: BoardZoneReference.PlayerZone, _ cards: [ZoneCard]) {
        if let inspectZone { inspectZone(.player(playerID: player.playerId, zone: zone)) }
        else { viewZone("\(player.displayName ?? player.playerId) · \(zone.rawValue.capitalized)", cards) }
    }
}

enum StackTargetPresentation {
    static func labels(for ids: [String], in snapshot: GameSnapshot) -> [String] {
        let cards = PortraitInteractionPolicy.authorizedCards(snapshot)
        return ids.map { id in
            if let player = snapshot.players.first(where: { CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot).contains(id) }) {
                return snapshot.playerLabel(player.playerId)
            }
            if let card = cards.first(where: { $0.id == id }) {
                return NativeCardArtworkPolicy.permitsLookup(card: card) ? card.card.name : "Hidden card"
            }
            if let object = snapshot.xmage?.stack.first(where: { $0.id == id || $0.objectId == id }) {
                return object.displayName
            }
            return "Unavailable target"
        }
    }
}

struct PortraitStackLane: View {
    let snapshot: GameSnapshot
    let humanStack: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var horizontal = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text("STACK")
                    .font(.headline)
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("\(stackCount)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))
                Spacer(minLength: 0)
                Text(responseLabel)
                    .font(.caption.bold())
                    .foregroundStyle(responseColor)
            }
            .padding(.horizontal, 2)

            Divider()
                .background(MagicPalette.antiqueGold.opacity(0.22))

            if stackCount == 0 {
                VStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold.opacity(0.76))
                    Text("No stack")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                    Text("Spells and abilities appear here")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(Array(xmageObjects.enumerated()), id: \.element.id) { _, object in
                            stackObjectView(object)
                        }
                        if xmageObjects.isEmpty {
                            ForEach(Array(humanStack.reversed().enumerated()), id: \.element.id) { _, card in
                                stackCardView(card)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("board.stack.items")
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MagicPalette.iron.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30), lineWidth: 1))
    }

    @ViewBuilder
    private func stackObjectView(_ object: XmageStackObject) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            if horizontal { stackArtwork(object) }
            VStack(alignment: .leading, spacing: 8) {
            Text(object.displayName).font(.headline).foregroundStyle(MagicPalette.parchment)
            Text("Source: \(object.displaySourceName)").font(.caption).foregroundStyle(.secondary)
            if let targets = object.targetIds, !targets.isEmpty {
                Text("Targets: \(StackTargetPresentation.labels(for: targets, in: snapshot).joined(separator: ", "))")
                    .font(.subheadline).foregroundStyle(MagicPalette.parchment)
            }
            if !horizontal { stackArtwork(object) }
            if let rules = object.rulesText {
                GameRulesText(source: rules,
                              cardName: object.displaySourceCard?.card.name ?? object.sourceName,
                              isHidden: object.displaySourceCard.map { !NativeCardArtworkPolicy.permitsLookup(card: $0) } ?? false)
                    .font(.body).foregroundStyle(MagicPalette.parchment)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stackArtwork(_ object: XmageStackObject) -> some View {
        if let card = object.displaySourceCard {
            stackCardView(card)
        } else {
            SyntheticStackObjectTile(object: object, width: horizontal ? 150 : 180, height: horizontal ? 210 : 252)
        }
    }

    private func stackCardView(_ card: ZoneCard) -> some View {
        CardTile(card: card, selected: false, legal: false, zoneName: "Stack", width: horizontal ? 150 : 180, height: horizontal ? 210 : 252, ignoreTappedRotation: true, imageVariant: .inspection)
            .onTapGesture { inspectedCard = card }
            .accessibilityHint("Tap to inspect source card")
    }

    private var xmageObjects: [XmageStackObject] {
        snapshot.stackTopFirst
    }

    private var stackCount: Int {
        if let count = snapshot.xmage?.stack.count, count > 0 {
            return count
        }
        return humanStack.count
    }

    private var responseLabel: String {
        legalActions.contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) } ? "RESPOND" : "WAIT"
    }

    private var responseColor: Color {
        responseLabel == "RESPOND" ? MagicPalette.legalEmerald : .white.opacity(0.55)
    }

}

extension GameSnapshot {
    var combatSelectionResetKey: String {
        "\(id)|\(bridgeRevision ?? -1)|\(turn)|\(phase)|\(step ?? "")"
    }
}

struct BattlefieldRow: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let targetableIds: Set<String>
    let combatHighlightIds: Set<String>
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    var adaptsToDensity = false
    var availableHeight: CGFloat? = nil
    var allowsManaUndo = false
    var manaPaymentActive = false
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void
    let runCombatCardAction: (ZoneCard) -> Bool
    @State private var expandedGroupIds: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleCards: [ZoneCard] {
        cardGroups.flatMap { group in
            isExpanded(group) ? group.cards : [group.representative]
        }
    }

    private func isExpanded(_ group: BattlefieldCardGroup) -> Bool {
        !group.id.hasPrefix("attachment:") && (expandedGroupIds.contains(group.id) ||
        group.cards.contains { targetableIds.contains($0.instanceId) || targetableIds.contains($0.id) } ||
        Self.requiresIndividualCombatCards(group, highlightedIDs: combatHighlightIds))
    }

    static func requiresIndividualCombatCards(_ group: BattlefieldCardGroup, highlightedIDs: Set<String>) -> Bool {
        group.cards.contains {
            $0.isAttacking == true || $0.blocking?.isEmpty == false ||
            highlightedIDs.contains($0.instanceId) || highlightedIDs.contains($0.id)
        }
    }

    private var renderedCardWidth: CGFloat {
        if let permanentLayout { return permanentLayout.cardWidth }
        guard adaptsToDensity else { return cardWidth }
        return BattlefieldAdaptiveSizing.cardWidth(
            availableRowWidth: rowWidth, maxCardWidth: cardWidth,
            heightRatio: 1,
            tappedSlots: Array(repeating: false, count: min(5, visibleCards.count)))
    }

    private var renderedCardHeight: CGFloat {
        cardHeight * renderedCardWidth / max(cardWidth, 1)
    }

    private var permanentLayout: ArenaPermanentLayout? {
        availableHeight.map { ArenaPermanentLayout(count: visibleCardCount, width: rowWidth,
            height: $0, maxCardWidth: cardWidth, ratio: cardHeight / max(cardWidth, 1)) }
    }

    private var renderedGroups: [BattlefieldCardGroup] {
        cardGroups.flatMap { group in
            isExpanded(group) ? group.cards.map { BattlefieldCardGroup(id: "card:" + $0.instanceId, cards: [$0]) } : [group]
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: showsOverflowIndicator) {
                let groups = renderedGroups
                let rows = permanentLayout?.rows ?? 1
                let columns = max(1, (groups.count + rows - 1) / rows)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(Array(groups.dropFirst(row * columns).prefix(columns))) { group in
                                if group.id.hasPrefix("attachment:") { attachmentGroupTile(group) }
                                else if group.count > 1 { collapsedGroupTile(group) }
                                else { battlefieldCardTile(group.representative) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, availableHeight == nil ? 0 : 8)
                .frame(minWidth: rowWidth, minHeight: availableHeight ?? max(cardHeight + 6, 44), alignment: .center)
            }
            .accessibilityIdentifier("board.battlefield.\(title)")

        }
        .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2), value: renderedCardWidth)
    }

    private var cardGroups: [BattlefieldCardGroup] {
        BattlefieldAttachments.groups(cards)
    }

    private var visibleCardCount: Int {
        cardGroups.reduce(0) { count, group in
            count + (isExpanded(group) ? group.count : 1)
        }
    }

    @ViewBuilder
    private func attachmentGroupTile(_ group: BattlefieldCardGroup) -> some View {
        HStack(spacing: -max(0, renderedCardWidth - 44)) {
            ForEach(Array(group.cards.dropFirst())) { card in
                battlefieldCardTile(card)
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "link").font(.caption.bold())
                            .foregroundStyle(.white).padding(4).background(.black.opacity(0.9), in: Capsule())
                            .allowsHitTesting(false)
                    }
                    .accessibilityHint("Attached to \(group.representative.card.name). Tap to select; hold to inspect.")
            }
            battlefieldCardTile(group.representative)
        }
        .padding(.horizontal, 3)
        .background(MagicPalette.antiqueGold.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MagicPalette.antiqueGold.opacity(0.5), lineWidth: 1).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func collapsedGroupTile(_ group: BattlefieldCardGroup) -> some View {
        let card = group.representative
        let groupIds = Set(group.cards.flatMap { [$0.instanceId, $0.id] })
        let targetable = !targetableIds.isDisjoint(with: groupIds)
        let combatHighlighted = !combatHighlightIds.isDisjoint(with: groupIds)
        let legal = group.cards.contains { legalAction(for: $0) != nil }

        ArenaBattlefieldCard(
            card: card,
            selected: false,
            legal: legal,
            targetable: targetable || combatHighlighted,
            zoneName: title,
            width: renderedCardWidth,
            height: renderedCardHeight
        )
        .frame(width: renderedCardWidth, height: renderedCardHeight)
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
        .opacity(!targetableIds.isEmpty && !targetable ? 0.54 : 1)
        .overlay(alignment: .bottomLeading) {
            Text("×\(group.count)")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(MagicPalette.iron.opacity(0.94), in: Capsule())
                .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.58), lineWidth: 1))
                .padding(3)
                .allowsHitTesting(false)
        }
        .onTapGesture {
            expandedGroupIds.insert(group.id)
            selectedCard = nil
            inspectedCard = nil
            GameHaptics.selection()
        }
        .onCardHold(inspect: {
            inspectedCard = card
            GameHaptics.impact()
        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
        .offset(y: card.tapped == true && (permanentLayout?.rows ?? 1) == 1 ? 5 : 0)
        .accessibilityLabel("\(group.count) grouped \(card.card.name) cards in \(title)")
        .accessibilityHint("Tap to expand the group. Long press to inspect a card.")
        .accessibilityAction(named: Text("Expand group")) {
            expandedGroupIds.insert(group.id)
        }
        .accessibilityAction(named: Text("Inspect")) {
            inspectedCard = card
        }
    }

    @ViewBuilder
    private func battlefieldCardTile(_ card: ZoneCard) -> some View {
        let action = legalAction(for: card)
        let targetable = !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id))
        let combatHighlighted = combatHighlightIds.contains(card.instanceId) || combatHighlightIds.contains(card.id)

        ArenaBattlefieldCard(
            card: card,
            selected: selectedCard?.id == card.id,
            legal: action != nil,
            targetable: targetable || combatHighlighted,
            zoneName: title,
            width: renderedCardWidth,
            height: renderedCardHeight
        )
        .frame(width: renderedCardWidth, height: renderedCardHeight)
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
        .opacity(!targetableIds.isEmpty && !targetable ? 0.54 : 1)
        .onTapGesture {
            handleCardTap(card, action: action, targetable: targetable, combatHighlighted: combatHighlighted)
        }
        .onCardHold(inspect: {
            inspectedCard = card
            GameHaptics.impact()
        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
        .offset(y: card.tapped == true && (permanentLayout?.rows ?? 1) == 1 ? 5 : 0)
        .accessibilityAction(named: Text(targetable ? "Choose target" : "Select")) {
            handleCardTap(card, action: action, targetable: targetable, combatHighlighted: combatHighlighted)
        }
        .accessibilityAction(named: Text("Inspect")) {
            inspectedCard = card
        }
    }

    private func handleCardTap(_ card: ZoneCard, action: LegalAction?, targetable: Bool, combatHighlighted: Bool) {
        guard !card.isPhasedOut else { return }
        if targetable {
            runTargetAction(card)
        } else if !targetableIds.isEmpty {
            GameHaptics.warning()
        } else if combatHighlighted, runCombatCardAction(card) {
            GameHaptics.selection()
        } else if let immediate = PortraitInteractionPolicy.automaticCardAction(GameBoardInteractionState.cardActions(for: card, actions: legalActions)), Self.tapRunnableActionTypes.contains(immediate.type) {
            runAction(immediate)
        } else {
            selectedCard = selectedCard?.instanceId == card.instanceId ? nil : card
            inspectedCard = nil
            GameHaptics.selection()
        }
    }

    private var showsOverflowIndicator: Bool {
        if cardGroups.contains(where: { $0.id.hasPrefix("attachment:") }) { return true }
        if let permanentLayout { return permanentLayout.contentWidth > rowWidth }
        let contentWidth = 16 + CGFloat(visibleCards.count) * renderedCardWidth + CGFloat(max(visibleCardCount - 1, 0)) * 4
        return contentWidth > rowWidth
    }

    private func legalAction(for card: ZoneCard) -> LegalAction? {
        guard !card.isPhasedOut else { return nil }
        if allowsManaUndo, manaPaymentActive, card.tapped == true, let undo = manaUndoAction,
           undo.sourceInstanceId == card.instanceId || undo.cardInstanceId == card.instanceId {
            return undo
        }
        return legalActions.first {
            $0.cardInstanceId == card.instanceId || $0.sourceInstanceId == card.instanceId
        }
    }

    private var manaUndoAction: LegalAction? {
        legalActions.first { Self.manaUndoActionTypes.contains($0.type) }
    }

    private static let tapRunnableActionTypes = Set(["make_mana", "undo_mana"])
    private static let manaUndoActionTypes = Set(["undo_mana"])
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
                    .onCardHold(inspect: { inspectedCard = card }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
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
    // An engine offer permits starting a cast, not a promise of affordability.
    var castOffered = false
    var targetable = false
    var zoneName: String? = nil
    var width: CGFloat = 82
    var height: CGFloat = 112
    var ignoreTappedRotation: Bool = false
    var imageVariant: CardImageCacheVariant = .board
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.nativeTurnControl) private var nativeTurnControl

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if !NativeCardArtworkPolicy.permitsLookup(card: card) {
                    CardArtPlaceholder(card: card, width: width, height: height)
                } else if nativeTurnControl != nil {
                    NativeCardArtworkView(name: card.card.name, variant: imageVariant,
                                          tokenTypeLine: card.card.isToken == true ? card.card.typeLine : nil,
                                          tokenOracleText: card.card.isToken == true ? card.card.oracleText : nil,
                                          tokenPower: card.card.isToken == true ? card.displayPower : nil,
                                          tokenToughness: card.card.isToken == true ? card.displayToughness : nil,
                                          tokenColors: card.card.isToken == true ? card.card.tokenColors : nil) { loading, _ in
                        CardArtPlaceholder(card: card, width: width, height: height, loading: loading)
                    }
                } else {
                    AsyncImage(url: CardImageURL.image(card.card.name, variant: imageVariant)) { phase in
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
                }
            }
            .saturation(card.tapped == true && !ignoreTappedRotation ? 0.3 : 1)
            .brightness(card.tapped == true && !ignoreTappedRotation ? -0.12 : 0)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            XmageCardIconStrip(icons: ignoreTappedRotation ? [] : card.visibleXmageIcons, cardWidth: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .allowsHitTesting(false)

            if !ignoreTappedRotation && card.showsPowerToughness, let power = card.displayPower, let toughness = card.displayToughness {
                Text("\(power)/\(toughness)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.92), in: Capsule())
                    .padding(3)
            }

            if card.tapped == true && !ignoreTappedRotation {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: max(10, width * 0.15), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.72), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(3)
                    .allowsHitTesting(false)
            }

            if !ignoreTappedRotation && card.isCreature && card.summoningSickness == true {
                Image(systemName: "hourglass")
                    .font(.system(size: max(width * 0.105, 7), weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .frame(width: max(width * 0.22, 13), height: max(width * 0.22, 13))
                    .background(MagicPalette.warningAmber.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.32), lineWidth: 0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(3)
            }

            if !ignoreTappedRotation && !card.counterBadges.isEmpty {
                CardCounterBadgeStrip(badges: Array(card.counterBadges.prefix(3)), cardWidth: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: strokeWidth))
        .overlay(alignment: .topLeading) {
            if castOffered && !pending {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(4).background(.black.opacity(0.85), in: Circle()).padding(3)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay {
            if castOffered && !selected && !pending && !targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.98), lineWidth: 2.8)
                    .shadow(color: .white.opacity(0.85), radius: 7)
                    .shadow(color: .white.opacity(0.45), radius: 14)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
            if legal && !selected && !pending && !targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MagicPalette.legalEmerald.opacity(0.92), lineWidth: max(width * 0.030, 2.1))
                    .shadow(
                        color: MagicPalette.legalEmerald.opacity(0.85),
                        radius: Self.playableGlowRadius(legal: legal, selected: selected, pending: pending, targetable: targetable, width: width)
                    )
                    .padding(-3)
            }
            if targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.94), lineWidth: 2.8)
                    .shadow(color: Color.red.opacity(0.78), radius: 11)
                    .padding(-3)
            }
        }
        .shadow(color: shadowColor, radius: shadowRadius)
        .rotationEffect(.degrees(card.tapped == true && !ignoreTappedRotation ? 90 : 0))
        .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: card.tapped)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel(zoneName: zoneName, selected: selected, legal: legal, pending: pending))
        .accessibilityIdentifier(card.accessibilityIdentifier(zoneName: zoneName))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(castOffered ? "Drag upward to start casting. The engine will ask for payment and choices. Hold to inspect." : "Tap to select. Long press to inspect.")
    }

    private var strokeColor: Color {
        if pending {
            return MagicPalette.warningAmber
        }
        if selected {
            return MagicPalette.antiqueGold
        }
        if targetable {
            return Color.red
        }
        if legal {
            return MagicPalette.legalEmerald.opacity(0.72)
        }
        if castOffered { return .white }
        return .black.opacity(0.55)
    }

    private var strokeWidth: CGFloat {
        if selected || pending || targetable { return 3 }
        if legal || castOffered { return 2.2 }
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
            return Color.red.opacity(0.64)
        }
        if legal {
            return MagicPalette.legalEmerald.opacity(0.58)
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
        return max(width * 0.18, 10)
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
                if icon.textBadge == "Menace" {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: iconSize * 0.75, weight: .bold))
                        .foregroundStyle(MagicPalette.parchment)
                        .frame(width: iconSize + 4, height: iconSize + 4)
                        .background(MagicPalette.iron.opacity(0.9), in: Circle())
                        .accessibilityLabel("Menace: requires two or more blockers")
                } else if let assetName = CardImageURL.xmageIconAssetName(for: icon.iconType),
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
                Text("\(count) eligible target\(count == 1 ? "" : "s")")
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
    let yieldActions: [LegalAction]
    let logAction: () -> Void
    let settingsAction: () -> Void
    let runAction: (LegalAction) -> Void
    var onlyPhases: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if onlyPhases {
                HStack(spacing: 7) {
                    PhaseChip(label: "Phase", phase: (snapshot.step ?? snapshot.phase).arenaPhaseTitle, active: true)
                    PhaseChip(label: "Priority", phase: snapshot.playerLabel(snapshot.priorityPlayerId), active: snapshot.isViewer(snapshot.priorityPlayerId))
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
                        Text(GameplayActionPresentation.title(for: passAction, snapshot: snapshot))
                            .font(.system(size: 12, weight: .black, design: .serif))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                    .disabled(passAction == nil)

                    YieldActionsControl(
                        snapshot: snapshot,
                        actions: yieldActions,
                        fontSize: 8,
                        runAction: runAction
                    )
                }

                HStack(spacing: 6) {
                    Button(action: logAction) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    .accessibilityLabel("Open game log")
                    Button(action: settingsAction) {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    .accessibilityLabel("Open game settings")
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
        GameplayActionPresentation.title(for: action, snapshot: snapshot)
    }
}

struct YieldActionsControl: View {
    let snapshot: GameSnapshot
    let actions: [LegalAction]
    let fontSize: CGFloat
    var iconOnly = false
    let runAction: (LegalAction) -> Void

    var body: some View {
        Group {
            if actions.count == 1, let action = actions.first {
                Button {
                    runAction(action)
                } label: {
                    actionLabel(GameplayActionPresentation.title(for: action, snapshot: snapshot), showsDisclosure: false)
                }
                .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                .accessibilityLabel(GameplayActionPresentation.title(for: action, snapshot: snapshot))
            } else {
                Menu {
                    ForEach(actions) { action in
                        Button(GameplayActionPresentation.title(for: action, snapshot: snapshot)) {
                            runAction(action)
                        }
                    }
                } label: {
                    actionLabel("Timing Options", showsDisclosure: true)
                }
                .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                .disabled(actions.isEmpty)
                .accessibilityLabel(actions.isEmpty ? "No timing options available" : "Open timing options")
                .accessibilityHint(actions.isEmpty ? "" : "Choose how far XMage should yield priority")
            }
        }
        .frame(minHeight: 44)
    }

    private func actionLabel(_ title: String, showsDisclosure: Bool) -> some View {
        HStack(spacing: 5) {
            if iconOnly {
                Image(systemName: "forward.end").font(.system(size: 16, weight: .semibold))
            } else {
            Text(title)
                .font(.system(size: fontSize, weight: .black, design: .serif))
                .multilineTextAlignment(.center)
            if showsDisclosure {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: max(fontSize - 2, 7), weight: .bold))
            }
            }
        }
        .frame(maxWidth: .infinity)
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

struct PromptDebugInspector: View {
    let snapshot: GameSnapshot
    let liveUpdateStatus: String
    let lastActionRejection: ActionRejectionNotice?
    let protocolDebug: XmageProtocolDebug?
    let protocolDebugError: String?
    let isProtocolDebugLoading: Bool
    let refreshProtocolDebug: () -> Void

    private var prompt: PromptEnvelopeV2? { snapshot.promptEnvelopeV2 }
    private var presentation: MobilePromptPresentation? {
        MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt Debug")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("XMage prompt and bridge state")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))

                HStack {
                    Text(isProtocolDebugLoading ? "Loading gateway protocol..." : "Gateway protocol")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                    Spacer()
                    Button(action: refreshProtocolDebug) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .black))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                }

                if let protocolDebugError {
                    Text(protocolDebugError)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MagicPalette.warningAmber)
                }

                if let protocolDebug {
                    debugGrid([
                        ("Debug game", protocolDebug.gameId ?? "none"),
                        ("Debug source", protocolDebug.source ?? "none"),
                        ("Debug revision", protocolDebug.bridgeRevision.map(String.init) ?? "n/a"),
                        ("Debug cycle", protocolDebug.xmageCycle.map(String.init) ?? "n/a"),
                        ("Debug pending", protocolDebug.pendingStatus ?? "none"),
                        ("Debug priority", protocolDebug.priorityPlayerId ?? "none"),
                        ("Debug waiting", protocolDebug.waitingOnPlayerId ?? "none"),
                        ("Debug legal", protocolDebug.legalActionCount.map(String.init) ?? "n/a"),
                        ("Debug types", protocolDebug.legalActionTypes?.joined(separator: ", ") ?? "none"),
                        ("Debug prompt", protocolDebug.promptSummary?.id ?? "none"),
                        ("Debug method", protocolDebug.promptSummary?.method ?? "none"),
                        ("Debug response", protocolDebug.promptSummary?.responseKind ?? "none"),
                        ("Debug command", protocolDebug.promptSummary?.responseCommandType ?? "none")
                    ])
                }

                debugGrid([
                    ("Kind", presentation?.kind.rawValue ?? "none"),
                    ("Method", prompt?.method ?? "none"),
                    ("Response", prompt?.responseKind ?? "none"),
                    ("Command", prompt?.responseCommand?.type ?? "none"),
                    ("Prompt ID", prompt?.id ?? "none"),
                    ("Message", prompt?.messageId.description ?? "none"),
                    ("Revision", snapshot.bridgeRevision.map(String.init) ?? "n/a"),
                    ("Cycle", snapshot.xmageCycle.map(String.init) ?? "n/a"),
                    ("Pending", snapshot.pendingStatus ?? "none"),
                    ("Priority", snapshot.priorityPlayerId ?? "none"),
                    ("Waiting", snapshot.waitingOnPlayerId ?? "none"),
                    ("Legal", "\(snapshot.legalActions?.count ?? 0)"),
                    ("WS", liveUpdateStatus)
                ])

                if let lastActionRejection {
                    PromptPanelSection(title: "Last rejection", detail: lastActionRejection.category.rawValue, isHighlighted: true) {
                        Text(lastActionRejection.message)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MagicPalette.warningAmber)
                    }
                }

                if let actions = snapshot.legalActions, !actions.isEmpty {
                    PromptPanelSection(title: "Legal action types", detail: "\(actions.count)", isHighlighted: false) {
                        Text(Array(Set(actions.map(\.type))).sorted().joined(separator: ", "))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
            .padding(18)
        }
        .background(BattlefieldSurface().ignoresSafeArea())
    }

    private func debugGrid(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.0.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .frame(width: 76, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .background(MagicPalette.iron.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.35), lineWidth: 1))
    }
}

struct GameManagementMenu: View {
    @Environment(\.dismiss) private var dismiss
    let concedeAction: LegalAction?
    let runAction: (LegalAction) -> Void
    @Binding var portraitModeEnabled: Bool
    let openPromptInspector: () -> Void
    let confirmStartNew: () -> Void
    let confirmQuit: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
            Text("Game Menu")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button("Done") { dismiss() }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("board.menu.done")
            }

            BoardAppearancePicker()
            PortraitModeToggle(isOn: $portraitModeEnabled)

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
                .accessibilityIdentifier("board.menu.quit")
            }

            Button(action: openPromptInspector) {
                Label("Prompt Debug", systemImage: "ladybug.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactActionButtonStyle(isPrimary: false))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("board.menu.scroll")
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
        case "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn":
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
            return "Pass Priority"
        case "pass_until_response":
            return "Pass Until Response"
        case "resolve_stack", "pass_until_stack_resolved":
            return "Resolve Stack"
        case "end_turn":
            return "End Turn"
        case "pass_until_end_of_turn":
            return "Yield Until End Step"
        case "yield_until_next_turn", "pass_until_next_turn":
            return "Yield Until Next Turn"
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

    private var currentDetails: [String] {
        var details: [String] = []
        if card.showsPowerToughness, let power = card.displayPower, let toughness = card.displayToughness {
            details.append("Current power/toughness: \(power)/\(toughness)")
        }
        if let tapped = card.tapped { details.append(tapped ? "Tapped" : "Untapped") }
        if card.isCreature && card.summoningSickness == true { details.append("Summoning sickness") }
        if card.isAttacking == true { details.append("Attacking") }
        if let blocking = card.blocking, !blocking.isEmpty { details.append("Blocking \(blocking.count)") }
        if let damage = card.damage, damage > 0 { details.append("Damage marked: \(damage)") }
        if card.attachedToInstanceId != nil { details.append("Attached") }
        if card.isPhasedOut { details.append("Phased out") }
        details += card.counterBadges.map { "\($0.label) counters: \($0.count)" }
        details += card.visibleXmageIcons.compactMap(\.displayText)
        return details
    }

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(proxy.size.height - 18, 1)
            let availableWidth = max(proxy.size.width - 18, 1)
            let rules = card.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasFooter = !currentDetails.isEmpty || !rules.isEmpty
            let horizontal = availableWidth > availableHeight
            let footerHeight = hasFooter ? min(150, availableHeight * 0.30) : 0
            let spacing: CGFloat = hasFooter ? 8 : 0
            let cardHeight = horizontal ? min(availableHeight, availableWidth * 0.55 * BattlefieldLayoutMetrics.magicCardHeightToWidth) : max(1, min(availableHeight - footerHeight - spacing, availableWidth * BattlefieldLayoutMetrics.magicCardHeightToWidth))
            let cardWidth = cardHeight / BattlefieldLayoutMetrics.magicCardHeightToWidth

            let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: spacing))
            layout {
                CardTile(card: card, selected: false, zoneName: "Inspector",
                         width: cardWidth, height: cardHeight,
                         ignoreTappedRotation: true, imageVariant: .inspection)
                    .frame(width: horizontal ? cardWidth : availableWidth)
                if hasFooter {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !currentDetails.isEmpty {
                                Text(currentDetails.joined(separator: " · "))
                                    .font(.subheadline.weight(.semibold))
                            }
                            if !rules.isEmpty {
                                GameRulesText(source: rules, cardName: card.card.name,
                                              isHidden: !NativeCardArtworkPolicy.permitsLookup(card: card))
                                    .font(.subheadline).lineSpacing(4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    }
                    .frame(height: horizontal ? availableHeight : footerHeight)
                    .foregroundStyle(MagicPalette.parchment)
                }
            }
            .frame(width: availableWidth, height: availableHeight, alignment: .top)
            .padding(9)
        }
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.cyan.opacity(0.35)))
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
                GameLogText(message: entry.message, usesDarkBackground: true)
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

private struct GameLogBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct GameLogDrawer: View {
    let log: [GameLogEntry]
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var followingLatest = true
    @State private var inspectedLogCard: ZoneCard?

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
                .accessibilityLabel("Close game log")
            }

            ScrollViewReader { proxy in
                GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if log.isEmpty {
                            Text("No public game actions yet.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(log) { entry in
                            GameLogText(message: entry.message, usesDarkBackground: true, onInspect: { reference in
                                // The public log authorizes the printed identity, not a lookup
                                // of this object's current (possibly hidden) game state.
                                guard NativeCardArtworkPolicy.permitsLookup(name: reference.name) else { return }
                                inspectedLogCard = ZoneCard(instanceId: reference.objectID.uuidString,
                                    card: CardIdentity(name: reference.name, typeLine: "Card referenced in game log",
                                                       oracleText: "Loading local card text…"),
                                    tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil,
                                    power: nil, toughness: nil, isCreaturePermanent: nil, damage: nil,
                                    isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
                                Task { @MainActor in
                                    // Disk-only catalogue lookup off the UI thread. Never resolve
                                    // the historical object UUID against live/private game state.
                                    let printed = await Task.detached(priority: .userInitiated) {
                                        (try? NativeDeckMetadataCatalogue.bundled())?.card(named: reference.name)
                                    }.value
                                    guard inspectedLogCard?.instanceId == reference.objectID.uuidString,
                                          inspectedLogCard?.card.name == reference.name else { return }
                                    inspectedLogCard = ZoneCard(instanceId: reference.objectID.uuidString,
                                        card: CardIdentity(name: reference.name,
                                            typeLine: printed?.typeLine ?? "Card referenced in game log",
                                            oracleText: printed?.oracleText ?? "Rules unavailable in the local catalogue.",
                                            manaCost: printed?.manaCost),
                                        tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil,
                                        power: nil, toughness: nil, isCreaturePermanent: nil, damage: nil,
                                        isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
                                }
                            })
                                .font(.subheadline)
                                .padding(.top, GameLogPresentation(entry.message).plainText.hasPrefix("TURN ") ? 12 : 0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("log-bottom")
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: GameLogBottomKey.self, value: geometry.frame(in: .named("game-log-scroll")).maxY)
                            })
                    }
                }
                .coordinateSpace(name: "game-log-scroll")
                .onPreferenceChange(GameLogBottomKey.self) { bottom in
                    followingLatest = bottom > 0 && bottom < viewport.size.height + 80
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followingLatest {
                        Button("Latest actions ↓") {
                            proxy.scrollTo("log-bottom", anchor: .bottom)
                            followingLatest = true
                        }.buttonStyle(.borderedProminent).padding(8)
                    }
                }
                .onAppear {
                    if let lastId = log.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onChange(of: log.last?.id) { _, _ in
                    if followingLatest, let lastId = log.last?.id {
                        if GameBoardMotion.reduced(accessibilityReduceMotion) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)))
        .sheet(item: $inspectedLogCard) { card in
            VStack(spacing: 8) {
                HStack {
                    Text("From the game log").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { inspectedLogCard = nil }.frame(minHeight: 44)
                }
                CardInspector(card: card)
            }
            .padding(12).presentationDetents([.large])
        }
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
            .frame(minHeight: 44)
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
            .frame(minHeight: 44)
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
            .frame(minWidth: isPrimary ? 112 : 94, minHeight: 44, alignment: .center)
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
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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

enum CardImageCacheVariant {
    case board
    case inspection

    var queryVersion: String {
        switch self {
        case .board: return "small"
        case .inspection: return "large"
        }
    }

    var cacheDirectoryName: String {
        switch self {
        case .board: return "MagicMobileCardImages"
        case .inspection: return "MagicMobileInspectionImages"
        }
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
        image(name, variant: .board, forcePlaceholder: forcePlaceholder)
    }

    static func inspection(_ name: String, forcePlaceholder: Bool = shouldForcePlaceholders) -> URL? {
        image(name, variant: .inspection, forcePlaceholder: forcePlaceholder)
    }

    static func image(_ name: String, variant: CardImageCacheVariant, forcePlaceholder: Bool = shouldForcePlaceholders) -> URL? {
        if forcePlaceholder {
            return nil
        }
        if name == "Hidden card" {
            return URL(string: "https://gatherer.wizards.com/Images/CardBack.jpg")
        }
        #if DEBUG
        // Explicit design-preview assets only; never a production image or engine fallback.
        if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] != nil,
           name != "Unknown Preview Card" {
            var preview = URLComponents(string: "https://api.scryfall.com/cards/named")!
            preview.queryItems = [URLQueryItem(name: "exact", value: name), URLQueryItem(name: "format", value: "image"), URLQueryItem(name: "version", value: "normal")]
            return preview.url
        }
        #endif
        let localURL = cacheURL(for: name, variant: variant)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        let baseURL = UserDefaults.standard.string(forKey: baseURLKey) ?? "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud"
        var components = URLComponents(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/card-image")
        components?.queryItems = [
            URLQueryItem(name: "version", value: variant.queryVersion),
            URLQueryItem(name: "name", value: name)
        ]
        return components?.url
    }

    static func cachedImageCount(variant: CardImageCacheVariant = .board) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory(for: variant),
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
        XmageCardIcon.assetName(for: iconType)
    }

    static func downloadAllImagesToPhone(
        images: [CardImageManifestEntry],
        variant: CardImageCacheVariant = .board,
        progress: @escaping (_ completed: Int, _ total: Int) async -> Void
    ) async throws -> Int {
        let directory = cacheDirectory(for: variant)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
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
                        await downloadImage(entry, variant: variant)
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

    private static func downloadImage(_ entry: CardImageManifestEntry, variant: CardImageCacheVariant) async -> Bool {
        let destination = cacheURL(for: entry.name, variant: variant)
        if FileManager.default.fileExists(atPath: destination.path) {
            return false
        }
        let source = variant == .inspection ? (entry.inspectionUrl ?? entry.normalUrl ?? entry.url) : entry.url
        guard let sourceURL = URL(string: source) else {
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

    private static func cacheDirectory(for variant: CardImageCacheVariant) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(variant.cacheDirectoryName, isDirectory: true)
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

    private static func cacheURL(for name: String, variant: CardImageCacheVariant) -> URL {
        cacheDirectory(for: variant).appendingPathComponent(fileName(for: name))
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
        switch lowercased().replacingOccurrences(of: "_", with: "-") {
        case "beginning":
            return "BEGIN"
        case "untap":
            return "UNTAP"
        case "upkeep":
            return "UPKEEP"
        case "draw":
            return "DRAW"
        case "precombat-main":
            return "MAIN 1"
        case "postcombat-main":
            return "MAIN 2"
        case "combat", "begin-combat":
            return "COMBAT"
        case "declare-attackers":
            return "ATTACK"
        case "declare-blockers":
            return "BLOCK"
        case "first-combat-damage", "first-strike-damage", "combat-damage":
            return "DAMAGE"
        case "end-combat":
            return "END C"
        case "ending", "end", "end-turn":
            return "END"
        case "cleanup":
            return "CLEANUP"
        default:
            return EngineDisplayText.phaseLabel(self)
        }
    }
}



private extension LegalAction {
    var displayLabel: String {
        if type == "choose_ability" || type == "activate_ability" {
            return compactPromptTitle
        }
        if let shortLabel, !shortLabel.isEmpty {
            return shortLabel
        }
        switch type {
        case "pass_priority":
            return "Pass Priority"
        case "pass_until_response":
            return "Pass Until Response"
        case "resolve_stack", "pass_until_stack_resolved":
            return "Resolve Stack"
        case "end_turn":
            return "End Turn"
        case "pass_until_end_of_turn":
            return "Yield Until End Step"
        case "yield_until_next_turn", "pass_until_next_turn":
            return "Yield Until Next Turn"
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
        case "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase":
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
        case "pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase":
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
    var legalActions: [LegalAction] = []
    var pendingActionId: String?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var runAction: ((LegalAction) -> Void)?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 9)], spacing: 10) {
                    ForEach(cards) { card in
                        let playActions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
                        VStack(spacing: 5) {
                            CardTile(card: card, selected: selectedCard?.id == card.id, legal: !playActions.isEmpty, zoneName: title, width: 70, height: 98)
                                .onTapGesture {
                                    selectedCard = card
                                    inspectedCard = nil
                                }
                                .onCardHold(inspect: {
                                    inspectedCard = card
                                }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                            if let action = playActions.first, playActions.count == 1 {
                                Button {
                                    runAction?(action)
                                } label: {
                                    PromptButtonLabel(title: action.displayLabel, systemImage: action.systemImage, isPending: pendingActionId == action.id)
                                }
                                .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
                                .disabled(pendingActionId != nil || runAction == nil)
                            }
                            if playActions.count > 1 {
                                Text("Select for actions")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(MagicPalette.antiqueGold)
                                    .lineLimit(1)
                            }
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
    let legalActions: [LegalAction]
    let pendingActionId: String?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let runAction: (LegalAction) -> Void
    let closeAction: () -> Void
    var targetableIDs: Set<String> = []
    var runTargetAction: ((ZoneCard) -> Void)? = nil
    var availableHeight: CGFloat = 410

    private func perform(_ action: LegalAction) {
        guard pendingActionId == nil, legalActions.contains(where: { $0.id == action.id }) else { return }
        if GameplayAffordances.dismissesZone(action: action) {
            selectedCard = nil
            inspectedCard = nil
            closeAction()
        }
        runAction(action)
    }

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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()
                .background(MagicPalette.antiqueGold.opacity(0.18))

            // Scrollable Grid of Cards
            ScrollView {
                if cards.isEmpty {
                    Text("No cards in this zone.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.78))
                        .padding(.top, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                        ForEach(cards) { card in
                            let cardActions = GameBoardInteractionState.cardActions(for: card, actions: legalActions)
                            let targetable = runTargetAction != nil && (targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id))
                            VStack(spacing: 8) {
                                CardTile(card: card, selected: selectedCard?.id == card.id, legal: !cardActions.isEmpty || targetable, zoneName: title, width: 76, height: 106)
                                    .onTapGesture {
                                        selectedCard = card
                                        inspectedCard = nil
                                    }
                                    .onCardHold(inspect: {
                                        inspectedCard = card
                                    }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                                if targetable {
                                    Button {
                                        guard pendingActionId == nil,
                                              targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id) else { return }
                                        runTargetAction?(card)
                                    } label: {
                                        Label("Target", systemImage: "scope")
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
                                    .disabled(pendingActionId != nil)
                                    .accessibilityLabel("Target \(card.card.name)")
                                }
                                if let action = cardActions.first, cardActions.count == 1 {
                                    Button {
                                        perform(action)
                                    } label: {
                                        Text(action.displayLabel)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                    .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
                                    .disabled(pendingActionId != nil)
                                }
                                if cardActions.count > 1 {
                                    Menu {
                                        ForEach(cardActions) { action in
                                            Button(action.displayLabel) { perform(action) }
                                        }
                                    } label: {
                                        Text("Actions")
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .disabled(pendingActionId != nil)
                                }
                                Button {
                                    inspectedCard = card
                                } label: {
                                    Text("Inspect")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Inspect \(card.card.name)")
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: 360)
        .frame(height: min(availableHeight, cards.isEmpty ? 150 : (cards.count <= 3 ? 290 : 410)))
        .background(MagicPalette.iron.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MagicPalette.antiqueGold.opacity(0.38), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
