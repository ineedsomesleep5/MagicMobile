import SwiftUI

struct DeckStudioPlaytestInsightsView: View {
    let signature: DeckStudioDeckSignature?
    @AppStorage(DeckStudioPlaytestStore.enabledKey) private var enabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var games: [DeckStudioRecordedGame] = []
    @State private var error: String?
    @State private var clearConfirmation = false
    @State private var generation = UUID()
    @State private var allDecks = false
    @State private var result = "All results"
    private var layoutFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--deck-history-layout-ui-test") &&
        ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_PREFERENCES"] != nil
        #else
        false
        #endif
    }
    private let results = ["All results", "Wins", "Not won", "Completed", "Unfinished"]
    private var selected: [DeckStudioRecordedGame] {
        allDecks || signature == nil ? games : games.filter { $0.deck == signature }
    }
    private var visible: [DeckStudioRecordedGame] {
        selected.filter { game in
            switch result {
            case "Wins": game.end == .completed && game.won == true
            case "Not won": game.end == .completed && game.won == false
            case "Completed": game.end == .completed
            case "Unfinished": game.end != .completed
            default: true
            }
        }
    }
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Game history").font(.title2.weight(.semibold))
                if layoutFixture {
                    Text("Development fixture · not saved").font(.caption.weight(.semibold))
                        .foregroundStyle(DeckStudioPalette.warning)
                }
                Toggle("Save AI game summaries", isOn: Binding(get: { enabled }, set: { value in
                    enabled = value
                    Task { await DeckStudioPlaytestStore.shared.setEnabled(value) }
                }))
                Text("Stored on this device. Only public opponent names and commanders are saved; hands and opponent decks are not.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                if signature == nil {
                    Text("Resolve this deck’s card names to filter by its exact playing cards. All saved sessions remain available.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                }
                HStack {
                    Picker("Deck history", selection: $allDecks) {
                        Text("This exact deck").tag(false)
                        Text("All decks").tag(true)
                    }.disabled(signature == nil)
                    Picker("Game result", selection: $result) {
                        ForEach(results, id: \.self) { Text($0).tag($0) }
                    }
                }.pickerStyle(.menu)
                if games.isEmpty {
                    Text("No saved sessions yet. Turn on summaries before starting your next AI game.").font(.subheadline)
                } else {
                    let completed = selected.filter { $0.end == .completed }
                    Text("\(selected.count) sessions · \(completed.count) completed · \(completed.filter { $0.won == true }.count) confirmed wins")
                        .font(.subheadline.weight(.semibold))
                    if visible.isEmpty { Text("No sessions match these filters.").font(.subheadline) }
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visible) { game in
                            MatchHistoryRow(game: game, exactDeck: signature == game.deck, reduceMotion: reduceMotion)
                        }
                    }
                    DisclosureGroup("What these summaries measure") {
                        Text("Exact deck means the same playing cards and quantities, not the same title. Completed games alone contribute results and turn/commander metrics. Duration includes pauses. Unknown outcomes are not losses; older sessions may lack opponent names. App, engine and catalogue versions are retained per session. No draws, mulligans or mana payments are inferred.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }.font(.caption)
                    if let json = export {
                        ShareLink(item: json) { Label("Export filtered summaries", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    }
                }
                HStack {
                    Button("Refresh history") { Task { await refresh() } }.frame(minHeight: 44)
                    Spacer()
                    Button("Clear all history", role: .destructive) { clearConfirmation = true }.frame(minHeight: 44)
                }
                Text("Keeps the 100 most recent sessions. Older sessions beyond that limit are not retained.")
                    .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
        }
        .task {
            if signature == nil { allDecks = true }
            if layoutFixture { games = fixtureGames() } else { await refresh() }
        }
        .onChange(of: signature) { _, value in if value == nil { allDecks = true } }
        .confirmationDialog("Delete all local playtest summaries?", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("Delete summaries", role: .destructive) {
                generation = UUID()
                Task {
                    do { try await DeckStudioPlaytestStore.shared.clear(); games = []; error = nil }
                    catch { self.error = "Could not remove the saved summaries. Existing data is preserved." }
                }
            }
        } message: { Text("Decks are not deleted. Games already in progress will not restore the cleared history.") }
    }
    private var export: String? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(visible) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func fixtureGames() -> [DeckStudioRecordedGame] {
        guard let playingDeck = signature ?? (try? DeckStudioDeckSignature(rows: [
            .init(name: "Isamaru, Hound of Konda", count: 1, section: "commanders")
        ])) else { return [] }
        return (0..<18).map { index in
            let start = Date(timeIntervalSince1970: 1_780_000_000 - Double(index * 86_400))
            var game = DeckStudioRecordedGame(id: UUID(), matchID: UUID().uuidString, seatID: "fixture-human",
                deck: playingDeck, title: "Fixture match \(index + 1)", upstream: "fixture", catalogue: "fixture",
                appBuild: "fixture", aiOpponents: 1, startedAt: start, observedAt: start.addingTimeInterval(1_800))
            game.end = .completed
            game.finishedAt = game.observedAt
            game.won = index.isMultiple(of: 2)
            game.observedTurn = 8
            game.opponents = [.init(playerID: UUID().uuidString, name: "Fixture rival", commanders: ["Aurelia, the Warleader"])]
            return game
        }
    }
    private func refresh() async {
        let token = generation
        do {
            let values = try await DeckStudioPlaytestStore.shared.summaries()
            let notice = await DeckStudioPlaytestStore.shared.status()
            guard generation == token, !Task.isCancelled else { return }
            games = values; error = notice
        } catch {
            guard generation == token else { return }
            self.error = "Saved playtest history could not be read. It is preserved; use Clear all history only to deliberately discard it."
        }
    }
}

private struct MatchHistoryRow: View {
    let game: DeckStudioRecordedGame
    let exactDeck: Bool
    let reduceMotion: Bool
    @State private var expanded = false
    private var commander: String? { game.deck.rows.first { $0.section == "commanders" }?.name }
    private var result: String {
        switch game.end {
        case .completed: game.won.map { $0 ? "Won" : "Completed · not won" } ?? "Completed · result unknown"
        case .inProgress: "In progress"
        case .left: "Left game"
        case .interrupted: "Interrupted"
        case .engineFailed: "Engine stopped"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    if let commander {
                        DeckStudioArtwork(name: commander).frame(width: 44, height: 60).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text("\(result) · \(game.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        Text("\(Int(game.elapsedSeconds / 60)) min recorded · \(game.aiOpponents) AI")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).frame(minHeight: 60)
                .accessibilityLabel("\(game.title), \(result), \(game.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityHint(expanded ? "Collapse match details" : "Expand match details")
            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    Text(exactDeck ? "Exact current playing deck" : "Historical playing deck · may differ from current draft")
                    Text("Your commanders: \(game.deck.rows.filter { $0.section == "commanders" }.map(\.name).joined(separator: " · "))")
                    Text("\(game.deck.rows.reduce(0) { $0 + $1.count }) playing cards · \(game.deck.rows.count) distinct entries")
                    if let opponents = game.opponents, !opponents.isEmpty {
                        ForEach(opponents, id: \.playerID) { opponent in
                            HStack(spacing: 8) {
                                if let name = opponent.commanders.first {
                                    DeckStudioArtwork(name: name).frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Text("\(opponent.name) · \(opponent.commanders.isEmpty ? "commander unknown" : opponent.commanders.joined(separator: " / "))")
                            }
                        }
                    } else { Text("Opponent identities were not recorded for this session.") }
                    if game.end == .completed {
                        Text("Final observed turn: \(game.observedTurn)")
                        ForEach(game.commandZoneCasts.keys.sorted(), id: \.self) { name in
                            Text("\(name): \(game.commandZoneCasts[name, default: 0]) observed command-zone casts")
                        }
                    } else { Text("Unfinished session · no result or completed-game metrics") }
                    Text("App \(game.appBuild) · XMage \(game.upstream) · catalogue \(game.catalogue)")
                        .font(.caption2).textSelection(.enabled)
                }.font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }.padding(12).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
