import SwiftUI
import Combine
import UIKit
import GameKit
import MagicMobileOnDevice

/// Native setup and lifecycle wiring around the existing portrait/landscape board.
@MainActor
struct OnDeviceRootView: View {
    @AppStorage("magicmobile.playerDisplayName") private var playerDisplayName = ""
    @AppStorage(PortraitModePreference.key) private var portraitModeEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: OnDeviceSession
    @StateObject private var setup: OnDeviceSetupModel
    @StateObject private var library = DeckLibraryStore()
    @StateObject private var diagnostics = OnDeviceDiagnostics()
    @State private var selectedCard: ZoneCard?
    @State private var inspectedCard: ZoneCard?
    @State private var zone: InspectedZone?
    @AppStorage(OnDeviceSetupPreferences.deckKey) private var selectedDeckID = OnDeviceSetupPreferences.defaultDeckID
    @AppStorage(OnDeviceSetupPreferences.aiDeckKey) private var aiPreconID = OnDeviceSetupPreferences.defaultAIDeckID
    @AppStorage(OnDeviceSetupPreferences.aiCountKey) private var opponentCount = 1
    @AppStorage(OnDeviceSetupPreferences.humanCountKey) private var playerCount = 2
    @AppStorage(OnDeviceSetupPreferences.friendsKey) private var playWithFriends = false
    @State private var showSetup = false
    @State private var showAppearance = false
    @State private var showUpdates = false
    @State private var showImport = false
    @State private var confirmLeave = false
    @State private var showDiagnostics = false
    @State private var confirmDeleteReport = false

    init() {
        let session = OnDeviceSession()
        _session = StateObject(wrappedValue: session)
        _setup = StateObject(wrappedValue: OnDeviceSetupModel(session: session))
    }

    private var activeGame: Bool { session.matchID != nil }
    private var aiPrecon: PreconDeck? { PreconCatalog.all.first { $0.id == aiPreconID } }
    private var selectedDeck: DeckList? {
        if let precon = PreconCatalog.all.first(where: { "precon:\($0.id)" == selectedDeckID }) {
            return precon.deckList
        }
        return library.decks.first(where: { "local:\($0.id)" == selectedDeckID })?.deckList
    }
    private var validName: Bool { (try? OnDeviceSetupModel.playerName(playerDisplayName)) != nil }
    private var mayStart: Bool {
        validName && selectedDeck != nil && (playWithFriends || aiPrecon != nil) && setup.identity != nil && !setup.isBusy && !setup.needsLeave
    }

    private var turnControl: NativeTurnControl {
        NativeTurnControl(
            canEndTurn: session.canEndTurn, canSkipResponses: session.canEndTurnSkippingResponses,
            canSkipToMyTurn: session.canSkipToMyTurn, isAutoPassing: session.isAutoPassing,
            status: session.autoPassStatus, endTurn: { session.endTurn() },
            skipResponses: { session.endTurnSkippingResponses() }, skipToMyTurn: { session.skipToMyTurn() },
            stop: { session.stopAutoPass() }
        )
    }

    private var presentedContent: some View {
        ZStack {
            if activeGame {
                game
            } else {
                MenuBackgroundSurface(portraitModeEnabled: portraitModeEnabled).ignoresSafeArea()
                if showSetup || setup.needsLeave {
                    setupContent
                } else {
                    TavernMainMenu(deckName: selectedDeck?.name ?? "Choose a deck", playerName: playerDisplayName,
                                   play: { showSetup = true }, decks: { showImport = true },
                                   settings: { showAppearance = true }, news: { showUpdates = true })
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAppearance) { AppearanceSettingsView(portraitModeEnabled: $portraitModeEnabled) }
        .sheet(isPresented: $showUpdates) { NativeUpdateNewsView(upstreamCommit: setup.identity?.upstreamCommit) }
        .overlay(alignment: .top) { recoveryBanner }
        .environment(\.nativeTurnControl, turnControl)
        .fullScreenCover(isPresented: $showImport) {
            NativeDeckLibraryView(library: library, selectedDeckID: $selectedDeckID)
        }
        .sheet(isPresented: $showDiagnostics) { diagnosticSheet }
        .background {
            if let multiplayer = setup.multiplayer {
                OnDeviceGameCenterPresentation(multiplayer: multiplayer)
            }
        }
        .confirmationDialog("Leave this game?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave game", role: .destructive) { closeGame() }
        } message: {
            Text(setup.multiplayer?.endpoint?.isHost == true
                 ? "You are hosting. Leaving ends this match for everyone; it cannot be resumed."
                 : "This closes the current match. It cannot be resumed after leaving.")
        }
    }

    private func preparePresentation() async {
        MagicMobileOrientationController.shared.setPortraitModeEnabled(portraitModeEnabled)
        restoreSetupPreferences()
        setup.prepare()
        setup.setSceneActive(scenePhase == .active)
    }

    private var lifecycleContent: some View {
        presentedContent.task { await preparePresentation() }
        .onChange(of: library.decks.map(\.id)) { _, _ in
            if !activeGame { restoreSetupPreferences() }
        }
        .onChange(of: portraitModeEnabled) { _, enabled in
            MagicMobileOrientationController.shared.setPortraitModeEnabled(enabled)
        }
        .onChange(of: scenePhase) { _, phase in setup.setSceneActive(phase == .active) }
        .onChange(of: session.errorMessage) { _, message in
            if message != nil { Task { await setup.captureDiagnostics(in: diagnostics) } }
        }
        .onChange(of: setup.errorMessage) { _, message in
            if message != nil { Task { await setup.captureDiagnostics(in: diagnostics) } }
        }
    }

    var body: some View {
        lifecycleContent
        .onChange(of: setup.multiplayer?.isConnected) { _, _ in setup.updateSessionForeground() }
        .onChange(of: setup.multiplayer?.isSuspended) { _, _ in setup.updateSessionForeground() }
        .onChange(of: setup.multiplayer?.endpoint?.matchID) { _, matchID in
            if matchID != nil { Task { await setup.attachMultiplayer() } }
        }
        .onChange(of: session.snapshot?.bridgeRevision) { _, _ in refreshInspections() }
    }

    private func refreshInspections() {
        guard let snapshot = session.snapshot else { zone = nil; inspectedCard = nil; return }
        let cards = PortraitInteractionPolicy.authorizedCards(snapshot)
        // Unscoped legacy callbacks must reopen after a state change rather than
        // keep a moved card under a stale zone heading. The board uses exact refs.
        zone = nil
        if let current = inspectedCard { inspectedCard = cards.first { $0.id == current.id } }
    }

    private var game: some View {
        ImmersivePlayShell(
            snapshot: session.snapshot, startupStatus: nil,
            selectedCard: $selectedCard, inspectedCard: $inspectedCard,
            playerDisplayName: playerDisplayName, avatarData: nil,
            pendingActionId: session.pendingActionID, pendingCardInstanceId: session.pendingCardID,
            lastActionRejection: nil, liveUpdateStatus: setup.liveStatus,
            onInteractionFeedback: { setup.feedback = $0 },
            runAction: { action in Task { await setup.perform { try await session.send(action: action) } } },
            runCommand: { command, label, id in
                Task { await setup.perform { try await session.send(command, label: label, actionID: id) } }
            },
            refreshGame: refresh, reconnectGame: refresh,
            checkBridgeHealth: { setup.localHealth() },
            newGame: requestLeave, quitGame: requestLeave,
            loadProtocolDebug: { _ in
                throw EngineError.invalidMessage("Protocol debug export is not available for this on-device session.")
            },
            portraitModeEnabled: $portraitModeEnabled,
            viewZone: { title, cards in zone = InspectedZone(title: title, cards: cards) }
        )
        .overlay { zoneOverlay }
        .disabled(setup.isBusy)
    }

    // The shell owns its normal board inspections. Its external zone callback (for
    // secondary details) uses the same inspector components and geometry here.
    @ViewBuilder
    private var zoneOverlay: some View {
        if let zone {
            GeometryReader { proxy in
                let rect = GameOrientationMode.isPortraitLayout(size: proxy.size, portraitEnabled: portraitModeEnabled)
                    ? PortraitBattlefieldLayoutMetrics(proxy: proxy).detailSheetRect
                    : BattlefieldLayoutMetrics(proxy: proxy).detailSheetRect
                CompactZoneInspectorOverlay(
                    title: zone.title, cards: zone.cards, legalActions: session.snapshot?.legalActions ?? [],
                    pendingActionId: session.pendingActionID, selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                    runAction: { action in Task { await setup.perform { try await session.send(action: action) } } },
                    closeAction: { self.zone = nil }
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                if let inspectedCard {
                    Color.black.opacity(0.01).ignoresSafeArea().onTapGesture { self.inspectedCard = nil }
                    CardInspector(card: inspectedCard)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    private var setupContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { showSetup = false } label: { Label("Main menu", systemImage: "chevron.left") }
                        .disabled(setup.isBusy || setup.needsLeave)
                    Spacer()
                    Button { showAppearance = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
                Text("Gather your table").font(.largeTitle.bold()).foregroundStyle(MagicPalette.parchment)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Player name", text: $playerDisplayName)
                        .textContentType(.nickname).autocorrectionDisabled()
                        .textFieldStyle(GameTextFieldStyle()).accessibilityIdentifier("ondevice.playerName")
                    Text("Choose a name with 1–24 characters.").font(.caption).foregroundStyle(.secondary)
                    PortraitModeToggle(isOn: $portraitModeEnabled)
                    Picker("Your deck", selection: $selectedDeckID) {
                        Section("Included precons") {
                            ForEach(PreconCatalog.all) { Text($0.name).tag("precon:\($0.id)") }
                        }
                        Section("Saved on this device") {
                            ForEach(library.decks) { Text($0.name).tag("local:\($0.id)") }
                        }
                    }
                    Button { showImport = true } label: { Label("Browse, import or edit decks", systemImage: "rectangle.stack.badge.plus") }
                        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                }
                .magicPanel(.leather, prominence: .elevated, cornerRadius: 14, padding: 16)
                .disabled(setup.isBusy || setup.needsLeave)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Players", selection: $playWithFriends) {
                        Text("Against AI").tag(false)
                        Text("Game Center").tag(true)
                    }.pickerStyle(.segmented).disabled(setup.isBusy || setup.needsLeave)
                    if playWithFriends {
                        Picker("Human players", selection: $playerCount) {
                            ForEach(2...4, id: \.self) { Text("\($0) players").tag($0) }
                        }.disabled(setup.isBusy || setup.needsLeave)
                        Text("Every player needs the same app version and must keep the app open during the match.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(setup.multiplayer?.status ?? setup.status).font(.callout)
                        if setup.multiplayer?.isAuthenticated != true {
                            Button("Sign in to Game Center") { setup.multiplayer?.authenticate() }
                                .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                                .disabled(setup.multiplayer == nil || setup.isBusy || setup.needsLeave)
                        }
                        Button("Find players") { startMatchmaking() }
                            .buttonStyle(MagicPrimaryButtonStyle())
                            .disabled(!mayStart || setup.multiplayer?.isAuthenticated != true)
                    } else {
                        Stepper("AI opponents: \(opponentCount)", value: $opponentCount, in: 1...3)
                            .disabled(setup.isBusy || setup.needsLeave)
                        Picker("AI deck", selection: $aiPreconID) {
                            ForEach(PreconCatalog.all) { Text($0.name).tag($0.id) }
                        }.disabled(setup.isBusy || setup.needsLeave)
                        Text("XMage AI · Normal").font(.caption).foregroundStyle(.secondary)
                        Button("Start game") { startAI() }
                            .buttonStyle(MagicPrimaryButtonStyle()).disabled(!mayStart)
                    }
                }
                .magicPanel(.iron, prominence: .standard, cornerRadius: 14, padding: 16)
                Text(setup.status).font(.caption).foregroundStyle(.secondary)
                if setup.needsLeave {
                    Button("Leave / retry closing", role: .destructive) { confirmLeave = true }
                        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                        .disabled(setup.isBusy || session.isWorking)
                }
                if setup.identity == nil {
                    Button("Retry loading local catalogue") { setup.prepare() }
                        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                }
                Button("Engine error report") { showDiagnostics = true }
                    .accessibilityIdentifier("ondevice.diagnostics")
            }
            .foregroundStyle(MagicPalette.parchment)
            .frame(maxWidth: 640).padding(16).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var recoveryBanner: some View {
        if setup.isBusy || setup.errorMessage != nil || session.errorMessage != nil ||
            (activeGame && (session.snapshot == nil || !setup.canUseSession)) {
            VStack(alignment: .leading, spacing: 8) {
                if setup.isBusy { ProgressView(setup.status) }
                if let message = setup.errorMessage ?? session.errorMessage {
                    Text(message).font(.caption.weight(.semibold))
                } else if activeGame && !setup.canUseSession {
                    Text(setup.liveStatus).font(.caption.weight(.semibold))
                } else if activeGame && session.snapshot == nil {
                    Text("Waiting for the first game update.").font(.caption.weight(.semibold))
                }
                if activeGame {
                    HStack {
                        Button("Refresh", action: refresh).disabled(!setup.canUseSession)
                        if session.pendingActionID != nil {
                            Button("Retry response") { Task { await setup.perform { try await session.retryPending() } } }
                                .disabled(!setup.canUseSession)
                        }
                        Button(setup.closeFailed ? "Retry closing" : "Leave") {
                            if setup.closeFailed { closeGame() } else { confirmLeave = true }
                        }
                    }
                    .disabled(setup.isBusy || session.isWorking)
                }
                if setup.errorMessage != nil || session.errorMessage != nil {
                    Button("Review engine error report") { showDiagnostics = true }
                        .accessibilityIdentifier("ondevice.failureReport")
                }
            }
            .foregroundStyle(MagicPalette.parchment)
            .magicPanel(.iron, prominence: .elevated, cornerRadius: 12, padding: 12)
            .padding(.horizontal, 12)
        }
    }

    private func startAI() {
        diagnostics.beginAttempt()
        guard let deck = selectedDeck, let aiPrecon else { return }
        Task {
            do { playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName) }
            catch { setup.errorMessage = error.localizedDescription; return }
            await setup.startAI(name: playerDisplayName, deck: deck, aiDeck: aiPrecon.deckList, opponents: opponentCount)
        }
    }

    private var diagnosticSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Only the latest engine error report is kept on this phone, excluded from backups. Error text may contain private card information. Nothing is uploaded automatically; review it before sharing.")
                    if let error = diagnostics.errorMessage { Text(error).foregroundStyle(.red) }
                    if let report = diagnostics.report {
                        Text(diagnostics.isHistorical ? "Saved report from an earlier session" : "Latest local incident")
                            .font(.headline)
                        ShareLink(item: report) { Label("Share report", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("ondevice.shareReport")
                    }
                    if diagnostics.report != nil || diagnostics.errorMessage != nil {
                        Button("Delete saved report", role: .destructive) { confirmDeleteReport = true }
                    }
                    if let report = diagnostics.report {
                        Text(report).font(.caption.monospaced()).textSelection(.enabled)
                    } else if diagnostics.errorMessage == nil {
                        Text("No engine exception has been captured yet. Try starting the match again, then return here if it stops.")
                    }
                }.padding()
            }
            .navigationTitle("Engine error report").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showDiagnostics = false } } }
            .task { await setup.captureDiagnostics(in: diagnostics) }
            .confirmationDialog("Delete the local engine report?", isPresented: $confirmDeleteReport, titleVisibility: .visible) {
                Button("Delete report", role: .destructive) {
                    Task { await setup.clearDiagnostics(in: diagnostics) }
                }
            } message: { Text("This removes the saved report and its in-memory copy. Reports you already shared are not removed.") }
        }
    }

    private func startMatchmaking() {
        guard let deck = selectedDeck else { return }
        do {
            playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName)
            diagnostics.beginAttempt()
            try setup.startMatchmaking(name: playerDisplayName, deck: deck, playerCount: playerCount)
        } catch { setup.errorMessage = error.localizedDescription }
    }

    private func refresh() {
        Task { await setup.perform { try await session.refresh(); setup.updateSessionForeground() } }
    }

    private func restoreSetupPreferences() {
        let selected = OnDeviceSetupPreferences.normalize(
            .init(deckID: selectedDeckID, aiDeckID: aiPreconID, aiOpponents: opponentCount,
                  humanPlayers: playerCount, friends: playWithFriends),
            deckIDs: Set(PreconCatalog.all.map { "precon:\($0.id)" } + library.decks.map { "local:\($0.id)" }),
            aiDeckIDs: PreconCatalog.all.map(\.id)
        )
        selectedDeckID = selected.deckID; aiPreconID = selected.aiDeckID
        opponentCount = selected.aiOpponents; playerCount = selected.humanPlayers
    }

    private func requestLeave() {
        guard !setup.isBusy, !session.isWorking else { return }
        confirmLeave = true
    }

    private func closeGame() {
        Task {
            if await setup.close() {
                selectedCard = nil; inspectedCard = nil; zone = nil
            }
        }
    }

    private struct InspectedZone {
        let title: String
        let cards: [ZoneCard]
    }
}

@MainActor
private final class OnDeviceSetupModel: ObservableObject {
    @Published private(set) var identity: BuildIdentity?
    @Published private(set) var multiplayer: OnDeviceMultiplayer?
    @Published private(set) var isBusy = false
    @Published private(set) var usingMultiplayer = false
    @Published private(set) var closeFailed = false
    @Published private(set) var status = "Preparing local decks"
    @Published var errorMessage: String?
    @Published var feedback: String?
    private let session: OnDeviceSession
    private let runtime = OnDeviceRuntimeManager()
    private var resolver: OnDeviceDeckResolver?
    private var multiplayerObservation: AnyCancellable?
    private var aiClient: EngineClient?
    private var aiMatchID: String?
    private var sceneActive = true

    init(session: OnDeviceSession) { self.session = session }

    var needsLeave: Bool { usingMultiplayer || runtime.isOpen || session.matchID != nil || multiplayer?.needsCleanup == true }
    var canUseSession: Bool {
        sceneActive && (!usingMultiplayer || (multiplayer?.isConnected == true && multiplayer?.isSuspended == false))
    }
    var liveStatus: String {
        if usingMultiplayer, let multiplayer, !multiplayer.isConnected || multiplayer.isSuspended { return multiplayer.status }
        return feedback ?? session.status
    }

    static func playerName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...24).contains(name.count), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw EngineError.invalidMessage("Enter a player name with 1–24 characters and no line breaks.")
        }
        return name
    }

    func prepare() {
        guard identity == nil else { return }
        do {
            let resolver = try OnDeviceDeckResolver.bundled()
            guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  !version.isEmpty, !build.isEmpty else {
                throw EngineError.invalidMessage("This app is missing its build identity. Install a complete app build.")
            }
            let identity = BuildIdentity(upstreamCommit: resolver.upstreamCommit, catalogueHash: resolver.catalogueHash,
                                         adapterVersion: "ondevice-0.1/app-\(version)/build-\(build)")
            let multiplayer = OnDeviceMultiplayer(identity: identity,
                makeHostEngine: { [runtime] in try await runtime.makeClient(identity: identity) },
                closeHostEngine: { [runtime] _ in try await runtime.close() })
            multiplayerObservation = multiplayer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            self.resolver = resolver; self.identity = identity; self.multiplayer = multiplayer
            errorMessage = nil; status = "Choose your deck and players."
        } catch { errorMessage = error.localizedDescription; status = "Local setup unavailable" }
    }

    func startAI(name: String, deck: DeckList, aiDeck: DeckList, opponents: Int) async {
        guard !isBusy, !needsLeave, let resolver, let identity else { return }
        isBusy = true; errorMessage = nil; feedback = nil; status = "Starting XMage"
        defer { isBusy = false }
        do {
            let name = try Self.playerName(name)
            guard (1...3).contains(opponents) else { throw EngineError.invalidMessage("Choose 1–3 AI opponents.") }
            let humanDeck = try resolver.resolve(deck), opponentDeck = try resolver.resolve(aiDeck)
            var seats: [MagicMobileOnDevice.JSONValue] = [.object([
                "seatId": .string("player1"), "name": .string(name), "controller": .string("human"), "deck": humanDeck
            ])]
            for index in 1...opponents {
                seats.append(.object(["seatId": .string("player\(index + 1)"), "name": .string("AI \(index)"),
                                      "controller": .string("ai"), "deck": opponentDeck]))
            }
            let client = try await runtime.makeClient(identity: identity)
            aiClient = client
            let created = try await runtime.create(client: client, configuration: .object(["seats": .array(seats)]))
            guard let matchID = created["matchId"]?.string, !matchID.isEmpty else {
                throw EngineError.invalidMessage("XMage did not return a match ID. Close the runtime before trying again.")
            }
            aiMatchID = matchID
            updateSessionForeground()
            try await session.attach(client: client, matchID: matchID, seatID: "player1", allowsLocalAutoYield: true, close: { [self] in try await closeAI() })
            status = "Game started"
        } catch {
            errorMessage = error.localizedDescription
            if !runtime.isOpen, aiMatchID == nil { aiClient = nil }
            status = needsLeave ? "Game startup interrupted. Refresh or leave before starting again." : "Unable to start local game"
        }
    }

    func startMatchmaking(name: String, deck: DeckList, playerCount: Int) throws {
        guard !isBusy, !needsLeave, let resolver, let multiplayer else {
            throw EngineError.invalidMessage("Close the current match before finding players.")
        }
        let name = try Self.playerName(name)
        _ = try multiplayer.makeMatchmaker(playerCount: playerCount, name: name, deck: resolver.resolve(deck))
        usingMultiplayer = true; errorMessage = nil; feedback = nil
        status = "Connecting Game Center players"
        updateSessionForeground()
    }

    func attachMultiplayer() async {
        guard usingMultiplayer, !isBusy, session.matchID == nil,
              let multiplayer, let endpoint = multiplayer.endpoint else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            updateSessionForeground()
            try await session.attach(client: endpoint.client, matchID: endpoint.matchID, seatID: endpoint.seatID,
                                     close: { try await multiplayer.leave() })
            status = "Game Center match connected"
        } catch { errorMessage = error.localizedDescription }
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { multiplayer?.onResumed() } else { multiplayer?.onSuspended() }
        updateSessionForeground()
    }

    func updateSessionForeground() { session.setForeground(canUseSession) }

    func perform(_ operation: @MainActor () async throws -> Void) async {
        guard !isBusy, !session.isWorking, canUseSession else { return }
        errorMessage = nil; feedback = nil
        do { try await operation() } catch { errorMessage = error.localizedDescription }
    }

    func close() async -> Bool {
        guard !isBusy, !session.isWorking else { return false }
        isBusy = true; status = "Closing game"; errorMessage = nil
        defer { isBusy = false }
        do {
            if session.matchID != nil { try await session.close() }
            else if usingMultiplayer { try await multiplayer?.leave() }
            else { try await closeAI() }
            // A failed host factory can retain its handle before Game Center owns
            // an EngineClient. Leave succeeds in that case; the root still owns cleanup.
            if runtime.isOpen { try await runtime.close() }
            usingMultiplayer = false; closeFailed = false; feedback = nil
            status = "Game closed"; updateSessionForeground()
            return true
        } catch {
            closeFailed = true; errorMessage = error.localizedDescription
            status = "Closing failed. Retry closing to release the current game."
            return false
        }
    }

    private func closeAI() async throws {
        if let client = aiClient, let matchID = aiMatchID {
            try await runtime.closeMatch(client: client, matchID: matchID)
            aiMatchID = nil
        } else {
            try await runtime.close()
        }
        aiClient = nil
    }

    func localHealth() -> EngineHealth {
        let connected = usingMultiplayer
            ? multiplayer?.isConnected == true && multiplayer?.isSuspended == false
            : runtime.isOpen
        let reason = usingMultiplayer
            ? "Game Center connection: \(multiplayer?.status ?? "unavailable")"
            : "Local runtime \(runtime.isOpen ? "open" : "closed"); capabilities \(runtime.capabilities == nil ? "unavailable" : "loaded")."
        return EngineHealth(status: connected ? "ok" : "unavailable", reason: reason,
                            checkedAt: ISO8601DateFormatter().string(from: Date()), recoveryAction: nil)
    }

    func captureDiagnostics(in store: OnDeviceDiagnostics) async {
        await store.capture(status: session.status) { try await runtime.diagnosticReport() }
    }

    func clearDiagnostics(in store: OnDeviceDiagnostics) async {
        do {
            try await store.clear(engine: { try await runtime.clearDiagnostics() })
        } catch { store.errorMessage = "Could not delete the local engine report: \(error.localizedDescription)" }
    }
}

@MainActor
private struct OnDeviceGameCenterPresentation: View {
    @ObservedObject var multiplayer: OnDeviceMultiplayer
    @State private var presentation: ControllerPresentation?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(multiplayer.$authenticationController) { controller in
                if let controller { presentation = ControllerPresentation(controller: controller) }
                else if presentation?.controller is GKMatchmakerViewController == false { presentation = nil }
            }
            .onReceive(multiplayer.$matchmakerController) { controller in
                if let controller { presentation = ControllerPresentation(controller: controller) }
                else if presentation?.controller is GKMatchmakerViewController { presentation = nil }
            }
            .sheet(item: $presentation) { item in
                OnDeviceControllerView(controller: item.controller).interactiveDismissDisabled()
            }
    }

    private struct ControllerPresentation: Identifiable {
        let controller: UIViewController
        var id: ObjectIdentifier { ObjectIdentifier(controller) }
    }
}

private struct OnDeviceControllerView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@MainActor
private struct OnDeviceTextImportView: View {
    @ObservedObject var library: DeckLibraryStore
    @Binding var selectedDeckID: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Imported Commander Deck"
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck name", text: $name)
                    TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 220)
                        .accessibilityLabel("Deck list text")
                } header: {
                    Text("Deck")
                } footer: {
                    Text("Use Commander, Deck, and Companion headings, then one card per line, such as 1 Sol Ring. Card names must match this app’s local catalogue.")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) } }
                Button("Import and use deck") {
                    do {
                        let resolver = try OnDeviceDeckResolver.bundled()
                        let deck = try resolver.importDeck(text: text, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        let record = try library.addLocalDurably(deck)
                        selectedDeckID = "local:\(record.id)"
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .scrollContentBackground(.hidden)
            .background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Import deck text").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}
