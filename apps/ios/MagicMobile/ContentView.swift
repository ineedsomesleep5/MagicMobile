import SwiftUI
import WebKit
import PhotosUI
import UIKit

struct ContentView: View {
    @State private var serverURLText = "http://192.168.68.168:3000"
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
                    NativeGameView(
                        snapshot: snapshot,
                        selectedCard: $selectedCard,
                        avatarData: playerAvatarData,
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
        .task(id: selectedPhoto?.itemIdentifier) {
            await loadSelectedAvatar()
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
        await perform {
            guard let api else { throw MagicMobileError.invalidServerURL }
            let humanDeck = importedDeck ?? selectedHumanPrecon.deckList
            let aiDeck = selectedAIPrecon.deckList
            let nextSnapshot = try await api.startCommanderGame(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty)
            snapshot = nextSnapshot
            selectedCard = nil
            screen = .play
            status = "Commander game started with \(humanDeck.name)"
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
            HeroCard(title: "Deck Builder", description: "Paste Archidekt or Moxfield export text, or pick an included Commander precon.", button: "Build deck", action: openDecks)
            HeroCard(title: "Quick Battle", description: "Use your selected precon and jump into a 1v1 game against AI.", button: "Start now", action: quickStart)
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

struct NativeGameView: View {
    let snapshot: GameSnapshot?
    @Binding var selectedCard: ZoneCard?
    let avatarData: Data?
    let runAction: (LegalAction) -> Void
    let newGame: () -> Void

    @ViewBuilder
    var body: some View {
        if let snapshot, let human = snapshot.human, let opponent = snapshot.opponent {
            GeometryReader { proxy in
                let railWidth = min(max(proxy.size.width * 0.18, 132), 180)
                let actions = selectedActions(in: snapshot).isEmpty ? promptActions(in: snapshot) : selectedActions(in: snapshot)

                ZStack(alignment: .trailing) {
                    BattlefieldSurface()

                    VStack(spacing: 0) {
                        PlayerStrip(name: "Noaddrag", player: opponent, avatarData: nil)
                            .padding(.horizontal, 10)

                        VStack(spacing: 6) {
                            BattlefieldRow(title: "Opponent", cards: opponent.zones.battlefield, selectedCard: $selectedCard, flipped: true)
                            PromptPill(snapshot: snapshot)
                            BattlefieldRow(title: "You", cards: human.zones.battlefield, selectedCard: $selectedCard)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity)

                        HandFan(cards: human.zones.hand, selectedCard: $selectedCard)
                            .padding(.bottom, 2)

                        PlayerStrip(name: "TabletopPolish", player: human, avatarData: avatarData, active: true)
                            .padding(.horizontal, 10)
                    }
                    .padding(.trailing, railWidth + 8)
                    .padding(.vertical, 4)

                    VStack(spacing: 8) {
                        CompactPhaseRail(snapshot: snapshot)
                        MiniLog(log: snapshot.log)
                        Button("Setup", action: newGame)
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(8)
                    .frame(width: railWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(.black.opacity(0.34))
                    .overlay(Rectangle().fill(.white.opacity(0.10)).frame(width: 1), alignment: .leading)

                    if !actions.isEmpty {
                        ContextActionTray(actions: actions, runAction: runAction)
                            .frame(width: min(260, proxy.size.width * 0.34))
                            .padding(.trailing, railWidth + 12)
                            .padding(.bottom, 58)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }

                    if let selectedCard {
                        CardInspector(card: selectedCard)
                            .frame(width: min(260, proxy.size.width * 0.34), height: min(230, proxy.size.height * 0.46))
                            .padding(.leading, 10)
                            .padding(.bottom, 56)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
            }
        } else {
            LoadingGameView()
        }
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

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.caption.weight(.black))
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .frame(width: 38, height: 32)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange.opacity(0.95))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: -10) {
                    if cards.isEmpty {
                        Text("No permanents")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, width: 58, height: 81)
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
    @Binding var selectedCard: ZoneCard?

    var body: some View {
        HStack(spacing: -18) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let center = Double(cards.count - 1) / 2
                CardTile(card: card, selected: selectedCard?.id == card.id, width: 66, height: 92)
                    .rotationEffect(.degrees((Double(index) - center) * 5.0))
                    .offset(x: CGFloat((Double(index) - center) * 1.5), y: selectedCard?.id == card.id ? -28 : abs(Double(index) - center) * 3)
                    .zIndex(selectedCard?.id == card.id ? 10 : Double(index))
                    .onTapGesture { selectedCard = card }
            }
        }
        .frame(height: 116)
    }
}

struct CardTile: View {
    let card: ZoneCard
    let selected: Bool
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
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? .cyan : .black.opacity(0.55), lineWidth: selected ? 3 : 1))
        .rotationEffect(card.tapped == true ? .degrees(12) : .zero)
        .shadow(color: selected ? .cyan.opacity(0.65) : .clear, radius: 10)
    }
}

struct CompactPhaseRail: View {
    let snapshot: GameSnapshot

    var body: some View {
        let current = snapshot.step ?? snapshot.phase
        let index = stageLabels.firstIndex(of: current) ?? 0
        let previous = stageLabels[max(index - 1, 0)]
        let next = stageLabels[min(index + 1, stageLabels.count - 1)]

        VStack(alignment: .leading, spacing: 6) {
            Text("PHASE")
                .font(.caption.weight(.black))
                .foregroundStyle(.orange)
            PhaseChip(label: "Prev", phase: previous, active: false)
            PhaseChip(label: "Now", phase: current, active: true)
            PhaseChip(label: "Next", phase: next, active: false)
            Text(snapshot.priorityPlayerId == "human" ? "Your priority" : "AI priority")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(9)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
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
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(active ? .black.opacity(0.7) : .white.opacity(0.55))
            Text(phase.phaseTitle)
                .font(.caption.weight(.black))
                .foregroundStyle(active ? .black : .white)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Color.orange : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct ContextActionTray: View {
    let actions: [LegalAction]
    let runAction: (LegalAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIONS")
                .font(.caption.weight(.black))
                .foregroundStyle(.orange)
            ForEach(actions.prefix(4)) { action in
                Button(action.label) { runAction(action) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
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

enum CardImageURL {
    static func normal(_ name: String) -> URL? {
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
