import SwiftUI
import WebKit

struct ContentView: View {
    @State private var serverURLText = "http://192.168.68.168:3000"
    @State private var status = "Not connected"
    @State private var screen: AppScreen = .menu
    @State private var difficulty: AiDifficulty = .normal
    @State private var deckText = ""
    @State private var deckSource = ""
    @State private var importedDeck: DeckList?
    @State private var generatedDeck: GeneratedDeckResponse?
    @State private var snapshot: GameSnapshot?
    @State private var selectedCard: ZoneCard?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.08), Color(red: 0.16, green: 0.25, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HeaderBar(screen: screen, status: status, isLoading: isLoading) {
                    screen = .menu
                }

                switch screen {
                case .menu:
                    MenuView(
                        startSetup: { screen = .setup },
                        openDecks: { screen = .decks },
                        quickStart: { Task { await startGame() } },
                        openArena: { screen = .arenaWeb }
                    )
                case .setup:
                    SetupView(
                        serverURLText: $serverURLText,
                        difficulty: $difficulty,
                        deckSummary: deckSummary,
                        checkBridge: { Task { await checkBridge() } },
                        generateDeck: { Task { await generateDeck() } },
                        openDecks: { screen = .decks },
                        startGame: { Task { await startGame() } }
                    )
                case .decks:
                    DeckBuilderView(
                        deckText: $deckText,
                        deckSource: $deckSource,
                        deckSummary: deckSummary,
                        importDeck: importDeck,
                        generateDeck: { Task { await generateDeck() } }
                    )
                case .play:
                    NativeGameView(
                        snapshot: snapshot,
                        selectedCard: $selectedCard,
                        runAction: { action in Task { await run(action: action) } },
                        newGame: { screen = .setup }
                    )
                case .arenaWeb:
                    ArenaWebContainer(url: webPlayURL)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .alert("MagicMobile", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var api: MagicMobileAPI? {
        guard let url = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return MagicMobileAPI(baseURL: url)
    }

    private var webPlayURL: URL {
        URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines) + "/play") ?? URL(string: "http://192.168.68.168:3000/play")!
    }

    private var deckSummary: String {
        let deck = importedDeck ?? generatedDeck?.deck
        guard let deck else {
            return "No deck selected. A legal bracket-3 Commander deck will be generated automatically."
        }
        return "\(deck.name) - \(deck.totalCards) cards - Commander: \(deck.commander?.cardName ?? "unknown")"
    }

    private func checkBridge() async {
        await perform {
            guard let api else { throw MagicMobileError.invalidServerURL }
            let health = try await api.health()
            status = "\(health.status): \(health.reason)"
        }
    }

    private func generateDeck() async {
        await perform {
            guard let api else { throw MagicMobileError.invalidServerURL }
            let deck = try await api.generateDeck(seed: "ios-\(Date().timeIntervalSince1970)", playerId: "human")
            generatedDeck = deck
            importedDeck = nil
            status = "Generated \(deck.deck.name)"
        }
    }

    private func importDeck() {
        guard let deck = DeckImporter.parse(text: deckText, source: deckSource.isEmpty ? "Imported Commander Deck" : deckSource) else {
            errorMessage = "Paste an Archidekt/Moxfield exported text list or a Commander text list."
            return
        }
        importedDeck = deck
        generatedDeck = nil
        status = "Imported \(deck.name)"
    }

    private func startGame() async {
        await perform {
            guard let api else { throw MagicMobileError.invalidServerURL }
            let humanDeck = try await selectedOrGeneratedHumanDeck(api: api)
            let aiDeck = try await api.generateDeck(seed: "ios-ai-\(Date().timeIntervalSince1970)", playerId: "ai-1").deck
            let nextSnapshot = try await api.startCommanderGame(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty)
            snapshot = nextSnapshot
            selectedCard = nil
            screen = .play
            status = "Commander game started"
        }
    }

    private func run(action: LegalAction) async {
        await perform {
            guard let api else { throw MagicMobileError.invalidServerURL }
            guard let gameId = snapshot?.id else { return }
            snapshot = try await api.submit(action: action, gameId: gameId)
            selectedCard = nil
            status = "Updated from XMage"
        }
    }

    private func selectedOrGeneratedHumanDeck(api: MagicMobileAPI) async throws -> DeckList {
        if let importedDeck {
            return importedDeck
        }
        if let generatedDeck {
            return generatedDeck.deck
        }
        return try await api.generateDeck(seed: "ios-human-\(Date().timeIntervalSince1970)", playerId: "human").deck
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
}

enum AppScreen: String {
    case menu = "Menu"
    case setup = "Setup"
    case decks = "Decks"
    case play = "Play"
    case arenaWeb = "Arena"
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
    let openArena: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HeroCard(title: "Commander vs AI", description: "Start a real XMage-backed 100-card Commander game.", button: "Game setup", action: startSetup)
            HeroCard(title: "Deck Builder", description: "Paste Archidekt or Moxfield export text, or generate a legal deck.", button: "Build deck", action: openDecks)
            HeroCard(title: "Quick Battle", description: "Generate both decks and jump into a 1v1 game against AI.", button: "Start now", action: quickStart)
            HeroCard(title: "Arena View", description: "Open the polished web battlefield inside this Swift app.", button: "Open arena", action: openArena)
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
    let deckSummary: String
    let checkBridge: () -> Void
    let generateDeck: () -> Void
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

            Panel(title: "Game Setup") {
                Picker("AI", selection: $difficulty) {
                    ForEach(AiDifficulty.allCases) { difficulty in
                        Text(difficulty.rawValue.capitalized).tag(difficulty)
                    }
                }
                .pickerStyle(.segmented)

                Text(deckSummary)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                HStack {
                    Button("Deck upload", action: openDecks)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Generate deck", action: generateDeck)
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
    let generateDeck: () -> Void

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
                Button("Generate bracket-3 deck", action: generateDeck)
                    .buttonStyle(PrimaryButtonStyle())
                Spacer()
            }
            .frame(width: 330)
        }
    }
}

struct NativeGameView: View {
    let snapshot: GameSnapshot?
    @Binding var selectedCard: ZoneCard?
    let runAction: (LegalAction) -> Void
    let newGame: () -> Void

    var body: some View {
        guard let snapshot, let human = snapshot.human, let opponent = snapshot.opponent else {
            return AnyView(LoadingGameView())
        }

        let actions = selectedActions(in: snapshot).isEmpty ? promptActions(in: snapshot) : selectedActions(in: snapshot)

        return AnyView(
            HStack(spacing: 10) {
                VStack(spacing: 8) {
                    PlayerStrip(name: "Noaddrag", player: opponent)
                    CardLane(title: "Opponent Battlefield", cards: opponent.zones.battlefield, selectedCard: $selectedCard)
                    PromptBand(snapshot: snapshot)
                    CardLane(title: "Your Battlefield", cards: human.zones.battlefield, selectedCard: $selectedCard)
                    HandFan(cards: human.zones.hand, selectedCard: $selectedCard)
                    PlayerStrip(name: "TabletopPolish", player: human, active: true)
                }
                .padding(10)
                .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green.opacity(0.25)))

                SideGamePanel(snapshot: snapshot, selectedCard: selectedCard, actions: actions, runAction: runAction, newGame: newGame)
                    .frame(width: 310)
            }
        )
    }

    private func selectedActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard let selectedCard else { return [] }
        return snapshot.legalActions?.filter { $0.cardInstanceId == selectedCard.instanceId || $0.sourceInstanceId == selectedCard.instanceId } ?? []
    }

    private func promptActions(in snapshot: GameSnapshot) -> [LegalAction] {
        snapshot.legalActions?.filter { ["keep_hand", "mulligan", "resolve_choice", "pass_priority", "pass_until_response", "concede"].contains($0.type) } ?? []
    }
}

struct LoadingGameView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.orange)
            Text("Starting Commander table...")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerStrip: View {
    let name: String
    let player: PlayerGameState
    var active = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(player.life)")
                .font(.title2.weight(.black))
                .frame(width: 48, height: 48)
                .background(active ? Color.cyan.opacity(0.4) : Color.white.opacity(0.16), in: Circle())
                .overlay(Circle().stroke(active ? .cyan : .white.opacity(0.55), lineWidth: 2))
            Text(name)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 130, alignment: .leading)
            Text("Library \(player.zones.library.count)   Grave \(player.zones.graveyard.count)   Exile \(player.zones.exile.count)")
                .font(.callout.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))
            Text("Commander: \(player.zones.command.first?.card.name ?? "none")")
                .font(.callout.weight(.bold))
                .foregroundStyle(.orange)
            Spacer()
        }
    }
}

struct PromptBand: View {
    let snapshot: GameSnapshot

    var body: some View {
        VStack(spacing: 4) {
            Text(snapshot.step ?? snapshot.phase)
                .font(.headline.weight(.black))
                .foregroundStyle(.orange)
                .textCase(.uppercase)
            Text(snapshot.promptText ?? "Waiting for XMage")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("Turn \(snapshot.turn) - Priority \(snapshot.priorityPlayerId ?? "none")")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CardLane: View {
    let title: String
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(.orange)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if cards.isEmpty {
                        Text("No permanents")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    ForEach(cards) { card in
                        CardTile(card: card, selected: selectedCard?.id == card.id)
                            .onTapGesture { selectedCard = card }
                    }
                }
                .frame(minHeight: 96)
            }
        }
    }
}

struct HandFan: View {
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let center = Double(cards.count - 1) / 2
                CardTile(card: card, selected: selectedCard?.id == card.id)
                    .rotationEffect(.degrees((Double(index) - center) * 3.5))
                    .offset(y: selectedCard?.id == card.id ? -18 : abs(Double(index) - center) * 2)
                    .zIndex(selectedCard?.id == card.id ? 10 : Double(index))
                    .onTapGesture { selectedCard = card }
            }
        }
        .frame(height: 118)
    }
}

struct CardTile: View {
    let card: ZoneCard
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.card.name)
                .font(.caption.weight(.black))
                .foregroundStyle(.black)
                .lineLimit(2)
            Spacer()
            Text(card.card.typeLine)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .lineLimit(2)
            if card.power != nil || card.toughness != nil {
                Text("\(card.power ?? 0)/\(card.toughness ?? 0)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(7)
        .frame(width: 82, height: 112)
        .background(Color(red: 0.86, green: 0.78, blue: 0.62), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? .cyan : .black.opacity(0.55), lineWidth: selected ? 3 : 1))
        .rotationEffect(card.tapped == true ? .degrees(8) : .zero)
        .shadow(color: selected ? .cyan.opacity(0.65) : .clear, radius: 10)
    }
}

struct SideGamePanel: View {
    let snapshot: GameSnapshot
    let selectedCard: ZoneCard?
    let actions: [LegalAction]
    let runAction: (LegalAction) -> Void
    let newGame: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(title: "Stages") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 5)], spacing: 5) {
                    ForEach(stageLabels, id: \.self) { stage in
                        Text(stage.replacingOccurrences(of: "-", with: " "))
                            .font(.system(size: 10, weight: .black))
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(stage == snapshot.step ? Color.orange.opacity(0.55) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Panel(title: "Actions") {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(actions) { action in
                            Button(action.label) { runAction(action) }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        Button("New game", action: newGame)
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .frame(maxHeight: 130)
            }

            Panel(title: "Selected") {
                Text(selectedCard?.card.name ?? "Tap a card")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Text(selectedCard?.card.typeLine ?? "Inspect hand, battlefield, command, graveyard, or exile cards.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(selectedCard?.card.oracleText ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(6)
            }

            Panel(title: "Log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(snapshot.log.suffix(10)) { entry in
                            Text(entry.message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

struct ArenaWebContainer: View {
    let url: URL

    var body: some View {
        WebView(url: url)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
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
