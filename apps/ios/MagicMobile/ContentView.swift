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
    @State private var pendingActionId: String?
    @State private var pendingCardInstanceId: String?
    @State private var lastSubmittedActionId: String?
    @State private var lastSubmittedSnapshotSignature: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var webSocketTask: URLSessionWebSocketTask?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.08), Color(red: 0.16, green: 0.25, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if screen == .play {
                ImmersivePlayShell(
                    snapshot: snapshot,
                    startupStatus: startupStatus,
                    selectedCard: $selectedCard,
                    avatarData: playerAvatarData,
                    pendingActionId: pendingActionId,
                    pendingCardInstanceId: pendingCardInstanceId,
                    runAction: { action in Task { await run(action: action) } },
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
            }
        }
        .task {
            await checkBridge()
        }
    }

    @ViewBuilder
    private var chromeScreen: some View {
        switch screen {
        case .menu:
            MenuView(
                startSetup: { screen = .setup },
                openDecks: { screen = .decks },
                quickStart: { Task { await startGame() } }
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
        pendingActionId = nil
        pendingCardInstanceId = nil
        lastSubmittedActionId = nil
        lastSubmittedSnapshotSignature = nil
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
                snapshot = nextSnapshot
                startupStatus = nil
                selectedCard = nil
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
            let nextSnapshot = try await api.submit(action: action, gameId: currentSnapshot.id)
            snapshot = nextSnapshot
            selectedCard = nil
            status = "Action submitted"
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }

        pendingActionId = nil
        pendingCardInstanceId = nil
    }

    private func startWebSocket(gameId: String) {
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        guard let api,
              let urlComponents = URLComponents(url: api.baseURL, resolvingAgainstBaseURL: false) else { return }

        let wsScheme = urlComponents.scheme == "https" ? "wss" : "ws"
        let wsHost = urlComponents.host ?? "localhost"
        let wsPort = urlComponents.port != nil ? ":\(urlComponents.port!)" : ""
        let wsURLString = "\(wsScheme)://\(wsHost)\(wsPort)/ws/games/\(gameId)"

        guard let url = URL(string: wsURLString) else { return }

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        status = "Connected (real-time)"

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
                                self.snapshot = nextSnapshot
                                self.selectedCard = nil
                            } catch {
                                print("Error decoding snapshot: \(error)")
                            }
                        }
                    }
                case .data(let data):
                    await MainActor.run {
                        do {
                            let nextSnapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
                            self.snapshot = nextSnapshot
                            self.selectedCard = nil
                        } catch {
                            print("Error decoding snapshot: \(error)")
                        }
                    }
                @unknown default:
                    break
                }
            } catch {
                print("WebSocket receive error: \(error.localizedDescription)")
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

    private func snapshotSignature(_ snapshot: GameSnapshot) -> String {
        let legalActionIds = snapshot.legalActions?.map(\.id).joined(separator: ",") ?? ""
        let handCounts = snapshot.players.map { "\($0.playerId):\($0.zones.hand.count):\($0.zones.battlefield.count):\($0.zones.graveyard.count)" }.joined(separator: "|")
        return "\(snapshot.id)|\(snapshot.turn)|\(snapshot.phase)|\(snapshot.step ?? "")|\(snapshot.priorityPlayerId ?? "")|\(snapshot.promptText ?? "")|\(handCounts)|\(legalActionIds)"
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

    var body: some View {
        HStack(spacing: 12) {
            HeroCard(title: "Commander vs AI", description: "Start a real XMage-backed 100-card Commander game.", button: "Game setup", action: startSetup)
            HeroCard(title: "Deck Builder", description: "Paste Archidekt or Moxfield export text, or pick an included Commander precon.", button: "Build deck", action: openDecks)
            HeroCard(title: "Quick Battle", description: "Use your selected precon and jump into a 1v1 game against AI.", button: "Start now", action: quickStart)
        }
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
    let checkBridge: () -> Void
    let openDecks: () -> Void
    let startGame: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Panel(title: "Server") {
                TextField("http://your-mac-ip:3000", text: $serverURLText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(GameTextFieldStyle())
                Text("Your iPhone is the client. XMage, Docker, and the rules bridge stay on the Mac or server.")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.callout.weight(.semibold))
                Button("Check XMage bridge", action: checkBridge)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(width: 330)

            Panel(title: "Game Setup") {
                HStack(alignment: .top, spacing: 12) {
                    PreconPicker(title: "Your precon", selection: $selectedHumanPrecon)
                    PreconPicker(title: "AI deck", selection: $selectedAIPrecon)
                }

                Text(deckSummary)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI level")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.orange)
                        Picker("AI level", selection: $difficulty) {
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

                HStack {
                    Button("Deck upload", action: openDecks)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Start vs AI", action: startGame)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
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
                .foregroundStyle(.orange)
            Picker(title, selection: $selection) {
                ForEach(PreconCatalog.all) { precon in
                    Text("\(precon.name) (\(precon.colors))").tag(precon)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            Text(selection.subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            Text(selection.commander)
                .font(.footnote.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(10)
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
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let runAction: (LegalAction) -> Void
    let newGame: () -> Void

    var body: some View {
        NativeGameView(
            snapshot: snapshot,
            startupStatus: startupStatus,
            selectedCard: $selectedCard,
            avatarData: avatarData,
            pendingActionId: pendingActionId,
            pendingCardInstanceId: pendingCardInstanceId,
            runAction: runAction,
            newGame: newGame
        )
        .ignoresSafeArea()
    }
}

struct NativeGameView: View {
    let snapshot: GameSnapshot?
    let startupStatus: CommanderStartupResponse?
    @Binding var selectedCard: ZoneCard?
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let runAction: (LegalAction) -> Void
    let newGame: () -> Void
    @State private var isLogOpen = false

    @ViewBuilder
    var body: some View {
        if let snapshot, let human = snapshot.human, let opponent = snapshot.opponent {
            GeometryReader { proxy in
                let metrics = BattlefieldLayoutMetrics(proxy: proxy)
                let actions = selectedActions(in: snapshot).isEmpty ? promptActions(in: snapshot) : selectedActions(in: snapshot)

                ZStack {
                    BattlefieldSurface()

                    VStack(spacing: 8) {
                        BattlefieldRow(title: "Opponent", cards: opponent.zones.battlefield, selectedCard: $selectedCard, flipped: true, cardWidth: metrics.permanentCardWidth)
                            .frame(width: metrics.playWidth, height: metrics.rowHeight)

                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(height: 1.5)
                            .padding(.horizontal, 30)

                        BattlefieldRow(title: "You", cards: human.zones.battlefield, selectedCard: $selectedCard, cardWidth: metrics.permanentCardWidth)
                            .frame(width: metrics.playWidth, height: metrics.rowHeight)
                    }
                    .frame(width: metrics.playWidth, height: metrics.rowHeight * 2 + 16)
                    .position(x: metrics.playCenterX, y: (metrics.opponentRowY + metrics.playerRowY) / 2)
                    .rotation3DEffect(.degrees(46), axis: (x: 1, y: 0, z: 0), anchor: .center, anchorZ: 0, perspective: 0.85)

                    PromptPill(snapshot: snapshot)
                        .frame(width: min(metrics.playWidth * 0.82, 560))
                        .position(x: metrics.playCenterX, y: metrics.promptY)

                    HandFan(
                        cards: human.zones.hand,
                        legalActions: snapshot.legalActions ?? [],
                        selectedCard: $selectedCard,
                        pendingCardInstanceId: pendingCardInstanceId,
                        metrics: metrics,
                        runAction: runAction
                    )
                        .frame(width: metrics.playWidth, height: metrics.handFrameHeight)
                        .position(x: metrics.playCenterX, y: metrics.handY)

                    PlayerHeroHUD(name: "Noaddrag", player: opponent, avatarData: nil, active: snapshot.activePlayerId == opponent.playerId)
                        .frame(width: metrics.hudWidth, height: 48)
                        .position(x: metrics.opponentHUDX, y: metrics.topHUDY)

                    PlayerHeroHUD(name: "TabletopPolish", player: human, avatarData: avatarData, active: true, compact: true)
                        .frame(width: metrics.hudWidth, height: 48)
                        .position(x: metrics.playerHUDX, y: metrics.bottomHUDY)

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

                    if !actions.isEmpty {
                        ContextActionTray(actions: actions, pendingActionId: pendingActionId, runAction: runAction)
                            .frame(width: metrics.actionDockWidth)
                            .position(x: metrics.actionDockX, y: metrics.actionY)
                    }

                    if let selectedCard {
                        CardInspector(card: selectedCard)
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

    private func promptActions(in snapshot: GameSnapshot) -> [LegalAction] {
        snapshot.legalActions?.filter { ["keep_hand", "mulligan", "resolve_choice", "pass_priority", "pass_until_response", "pass_until_next_turn", "concede"].contains($0.type) } ?? []
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
        max(safeArea.leading + 42, 52)
    }

    var rightInset: CGFloat {
        max(safeArea.trailing + railWidth + 12, railWidth + 16)
    }

    var playWidth: CGFloat {
        max(size.width - leftInset - rightInset, 320)
    }

    var playCenterX: CGFloat {
        leftInset + playWidth / 2
    }

    var railCenterX: CGFloat {
        size.width - max(safeArea.trailing + 6, 8) - railWidth / 2
    }

    var railY: CGFloat {
        max(safeArea.top + 104, 104)
    }

    var hudWidth: CGFloat {
        min(playWidth * 0.42, 250)
    }

    var opponentHUDX: CGFloat {
        leftInset + hudWidth / 2
    }

    var playerHUDX: CGFloat {
        leftInset + hudWidth / 2
    }

    var topHUDY: CGFloat {
        max(safeArea.top + 28, 28)
    }

    var bottomHUDY: CGFloat {
        size.height - safeArea.bottom - 32
    }

    var opponentRowY: CGFloat {
        size.height * 0.28
    }

    var promptY: CGFloat {
        size.height * 0.47
    }

    var playerRowY: CGFloat {
        size.height * 0.61
    }

    var handY: CGFloat {
        size.height - max(safeArea.bottom + handFrameHeight / 2 + 2, handFrameHeight / 2 + 4)
    }

    var actionY: CGFloat {
        size.height - safeArea.bottom - 80
    }

    var actionDockWidth: CGFloat {
        min(max(playWidth * 0.26, 230), 320)
    }

    var actionDockX: CGFloat {
        size.width - safeArea.trailing - actionDockWidth / 2 - 16
    }

    var inspectorX: CGFloat {
        leftInset + min(playWidth * 0.18, 158)
    }

    var inspectorY: CGFloat {
        min(size.height - max(safeArea.bottom + handFrameHeight + 96, handFrameHeight + 98), size.height * 0.58)
    }

    var logX: CGFloat {
        railCenterX - railWidth / 2 - min(playWidth * 0.21, 160) - 10
    }

    var logY: CGFloat {
        min(size.height * 0.44, 210)
    }

    var handCardWidth: CGFloat {
        min(max(playWidth / 11.6, 54), 76)
    }

    var handCardHeight: CGFloat {
        handCardWidth * 1.40
    }

    var handFrameHeight: CGFloat {
        handCardHeight + 38
    }

    var permanentCardWidth: CGFloat {
        min(max(playWidth / 15.5, 46), 60)
    }

    var rowHeight: CGFloat {
        permanentCardWidth * 1.40 + 24
    }
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

struct BattlefieldSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.22, blue: 0.13),
                    Color(red: 0.18, green: 0.31, blue: 0.16),
                    Color(red: 0.26, green: 0.16, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.orange.opacity(0.22), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 420)
            RadialGradient(colors: [.cyan.opacity(0.20), .clear], center: .bottomLeading, startRadius: 20, endRadius: 390)
            VStack {
                Spacer()
                Capsule()
                    .fill(.black.opacity(0.20))
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
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            PlayerAvatar(data: avatarData, size: compact ? 36 : 42, active: active)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(player.life)")
                        .font(.system(size: compact ? 11 : 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.78), in: Circle())
                        .offset(x: 5, y: 5)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: compact ? 14 : 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(player.zones.command.first?.card.name ?? "Commander")
                    .font(.system(size: compact ? 9 : 10, weight: .black))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 2)
            ZoneCounter(label: "Lib", value: player.zones.library.count, compact: compact)
            ZoneCounter(label: "Hand", value: player.zones.hand.count, compact: compact)
            ZoneCounter(label: "Grave", value: player.zones.graveyard.count, compact: compact)
            ZoneCounter(label: "Exile", value: player.zones.exile.count, compact: compact)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(.black.opacity(0.38), in: Capsule())
        .overlay(Capsule().stroke(active ? .cyan.opacity(0.45) : .white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
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
        .overlay(Circle().stroke(active ? .cyan : .white.opacity(0.52), lineWidth: active ? 3 : 2))
        .shadow(color: active ? .cyan.opacity(0.45) : .clear, radius: 10)
    }
}

struct ZoneCounter: View {
    let label: String
    let value: Int
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: compact ? 10 : 12, weight: .black))
            Text(label)
                .font(.system(size: compact ? 7 : 8, weight: .black))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .frame(width: compact ? 30 : 36, height: compact ? 26 : 30)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
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

struct BattlefieldRow: View {
    let title: String
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                            .foregroundStyle(.white.opacity(0.38))
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: cardWidth * 1.40, alignment: .leading)
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, width: cardWidth, height: cardWidth * 1.40)
                            .rotationEffect(.degrees(flipped ? 180 : 0))
                            .offset(y: card.tapped == true ? 5 : 0)
                            .zIndex(Double(index))
                            .onTapGesture { selectedCard = card }
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            }
        }
    }
}

struct HandFan: View {
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    let pendingCardInstanceId: String?
    let metrics: BattlefieldLayoutMetrics
    let runAction: (LegalAction) -> Void

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let center = CGFloat(cards.count - 1) / 2
                let distance = CGFloat(index) - center
                let maxSpread = max((metrics.playWidth - metrics.handCardWidth) / CGFloat(max(cards.count - 1, 1)), 0)
                let spread = min(metrics.handCardWidth * 0.56, maxSpread)
                let selected = selectedCard?.id == card.id
                let action = legalHandAction(for: card)

                CardTile(
                    card: card,
                    selected: selected,
                    pending: pendingCardInstanceId == card.instanceId,
                    width: metrics.handCardWidth,
                    height: metrics.handCardHeight
                )
                    .scaleEffect(selected ? 1.16 : 1.0)
                    .rotationEffect(.degrees(Double(distance) * 5.2))
                    .offset(x: distance * spread, y: selected ? -30 : abs(distance) * 4 + 10)
                    .zIndex(selectedCard?.id == card.id ? 10 : Double(index))
                    .onTapGesture { selectedCard = card }
                    .gesture(
                        DragGesture(minimumDistance: 16)
                            .onEnded { value in
                                selectedCard = card
                                guard value.translation.height < -42, let action else { return }
                                runAction(action)
                            }
                    )
            }
        }
        .frame(width: metrics.playWidth, height: metrics.handFrameHeight)
    }

    private func legalHandAction(for card: ZoneCard) -> LegalAction? {
        legalActions.first {
            ($0.cardInstanceId == card.instanceId || $0.sourceInstanceId == card.instanceId) &&
            ["play_land", "cast_spell"].contains($0.type)
        }
    }
}

struct CardTile: View {
    let card: ZoneCard
    let selected: Bool
    var pending = false
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
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: selected || pending ? 3 : 1))
        .rotationEffect(card.tapped == true ? .degrees(12) : .zero)
        .shadow(color: pending ? .orange.opacity(0.75) : selected ? .cyan.opacity(0.65) : .clear, radius: 10)
    }

    private var strokeColor: Color {
        if pending {
            return .orange
        }
        if selected {
            return .cyan
        }
        return .black.opacity(0.55)
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
    static func normal(_ name: String) -> URL? {
        if name == "Hidden card" {
            return URL(string: "https://gatherer.wizards.com/Images/CardBack.jpg")
        }
        var components = URLComponents(string: "https://api.scryfall.com/cards/named")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "image"),
            URLQueryItem(name: "version", value: "normal"),
            URLQueryItem(name: "exact", value: name)
        ]
        return components?.url
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

private let stageLabels = [
    "untap",
    "upkeep",
    "draw",
    "precombat-main",
    "begin-combat",
    "declare-attackers",
    "declare-blockers",
    "combat-damage",
    "postcombat-main",
    "end",
    "cleanup"
]

#Preview {
    ContentView()
}
