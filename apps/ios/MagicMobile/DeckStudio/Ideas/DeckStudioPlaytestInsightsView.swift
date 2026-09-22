import SwiftUI
import Charts

struct DeckStudioPlaytestInsightsView: View {
    let signature: DeckStudioDeckSignature?
    let metadata: NativeDeckMetadataCatalogue?
    let openMatch: (DeckStudioRecordedGame, Bool) -> Void
    @AppStorage(DeckStudioPlaytestStore.enabledKey) private var enabled = false
    @AppStorage(DeckStudioPlaytestStore.detailedEnabledKey) private var detailedEnabled = false
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Game history").font(.title2.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(enabled ? (detailedEnabled ? "Detail on" : "Summaries on") : "Saving off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DeckStudioPalette.secondaryInk)
                }
                if layoutFixture {
                    Text("Development fixture · not saved").font(.caption.weight(.semibold))
                        .foregroundStyle(DeckStudioPalette.warning)
                }
                DisclosureGroup {
                    Toggle("Save AI game summaries", isOn: Binding(get: { enabled }, set: { value in
                        enabled = value
                        if !value { detailedEnabled = false }
                        Task { await DeckStudioPlaytestStore.shared.setEnabled(value) }
                    }))
                    Toggle("Save detailed public game history", isOn: Binding(get: { detailedEnabled }, set: { value in
                        detailedEnabled = value
                        Task { await DeckStudioPlaytestStore.shared.setDetailedEnabled(value) }
                    }))
                    .disabled(!enabled)
                    Text("Both choices are local and apply to future AI matches. Detail saves sampled public life totals, battlefield counts, visible cards and recognized public notices. It never saves hands, opponent decks or raw game messages. Turning detail off keeps saved history until you delete it.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    HStack {
                        Button("Refresh history") { Task { await refresh() } }.frame(minHeight: 44)
                        Spacer()
                        Button("Clear all history", role: .destructive) { clearConfirmation = true }.frame(minHeight: 44)
                    }
                    Text("Up to 100 recent sessions within 8 MB; oldest sessions are removed first.")
                        .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                } label: {
                    Label("History settings & privacy", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("deckHistory.settings")
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                if signature == nil {
                    Text("Showing all decks · exact deck filter unavailable")
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
                    Text(enabled ? "No saved matches yet." : "No saved matches. Enable summaries in History settings for future AI games.")
                        .font(.subheadline)
                } else {
                    let completed = selected.filter { $0.end == .completed }
                    Text("\(selected.count) matches · \(completed.filter { $0.won == true }.count) confirmed wins")
                        .font(.subheadline.weight(.semibold))
                    if visible.isEmpty { Text("No sessions match these filters.").font(.subheadline) }
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visible) { game in
                            MatchHistoryRow(game: game) { openMatch($0, layoutFixture) }
                        }
                    }
                    DisclosureGroup("About these numbers") {
                        Text("Exact deck means the same playing cards and quantities, not the title. Only confirmed outcomes count as wins or not-won. Life changes are not damage dealt; a visible card is not proof of a cast. Observations are not an engine replay. Older matches may lack detail or opponent names. Duration includes pauses.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }.font(.caption)
                    if let json = export {
                        ShareLink(item: json) { Label("Export filtered history", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    }
                }
            }
        }
        .task {
            if signature == nil { allDecks = true }
            if layoutFixture { games = fixtureGames() } else { await refresh() }
        }
        .onChange(of: signature) { _, value in if value == nil { allDecks = true } }
        .confirmationDialog("Delete all local game history?", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) {
                generation = UUID()
                Task {
                    do { try await DeckStudioPlaytestStore.shared.clear(); games = []; error = nil }
                    catch { self.error = "Could not remove the saved history. Existing data is preserved." }
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
            let match = "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))"
            let viewer = "00000000-0000-0000-0001-000000000001"
            let rival = "00000000-0000-0000-0002-000000000001"
            var game = DeckStudioRecordedGame(id: UUID(uuidString: match)!, matchID: match, seatID: "fixture-human",
                deck: playingDeck, title: "Token Triumph", upstream: "fixture", catalogue: "fixture",
                appBuild: "fixture", aiOpponents: 1, startedAt: start, observedAt: start.addingTimeInterval(1_800))
            game.end = .completed
            game.finishedAt = game.observedAt
            game.won = index.isMultiple(of: 2)
            game.observedTurn = 8
            game.viewerPlayerID = viewer
            game.opponents = [.init(playerID: rival, name: "Fixture rival", commanders: ["Aurelia, the Warleader"])]
            if index == 0 {
                game.lastRevision = 4
                let values = [(1, 1, 40, 40, 0, 0), (2, 3, 37, 40, 1, 2),
                              (3, 5, 32, 36, 3, 3), (4, 8, 32, 0, 4, 1)]
                var timeline = DeckStudioPublicTimeline()
                timeline.samples = values.map { revision, turn, yourLife, rivalLife, yourBoard, rivalBoard in
                    .init(revision: revision, turn: turn,
                          observedAt: start.addingTimeInterval(Double(revision * 300)), players: [
                            .init(id: viewer, name: "You", life: yourLife, battlefieldCount: yourBoard),
                            .init(id: rival, name: "Fixture rival", life: rivalLife, battlefieldCount: rivalBoard)
                          ])
                }
                var damage = DeckStudioPublicTimeline.Event(revision: 3, turn: 5, kind: .damage,
                    playerID: viewer, cardName: "Lightning Bolt", typeLine: nil, outcome: nil)
                damage.amount = 3; damage.sourceEventRevision = 3
                timeline.events = [
                    .init(revision: 2, turn: 3, kind: .battlefieldAppearance, playerID: rival,
                          cardName: "Sol Ring", typeLine: "Artifact", outcome: nil),
                    damage,
                    .init(revision: 4, turn: 8, kind: .outcome, playerID: nil,
                          cardName: nil, typeLine: nil, outcome: "won")
                ]
                game.timeline = timeline
            }
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
    let onOpen: (DeckStudioRecordedGame) -> Void
    private var opponentCommanders: [String] { MatchHistoryText.commanders(game) }
    private var opponentName: String { MatchHistoryText.opponentName(game) }
    private var commanderLabel: String {
        guard let first = opponentCommanders.first else { return opponentName }
        return opponentCommanders.count == 1 ? first : "\(first) +\(opponentCommanders.count - 1)"
    }
    private var result: String { MatchHistoryText.result(game) }
    private var duration: String { MatchHistoryText.duration(game) }
    private var turnDescription: String {
        game.observedTurn > 0 ? "turn \(game.observedTurn) observed" : "turn not observed"
    }
    var body: some View {
        Button { onOpen(game) } label: {
            HStack(alignment: .top, spacing: 12) {
                if opponentCommanders.isEmpty {
                    Image(systemName: "person.crop.rectangle.stack").font(.title2)
                        .frame(width: 52, height: 70).background(DeckStudioPalette.background)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)
                } else {
                    HStack(spacing: -18) {
                        ForEach(Array(opponentCommanders.prefix(3).enumerated()), id: \.offset) { item in
                            DeckStudioArtwork(name: item.element)
                                .frame(width: 52, height: 70).clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DeckStudioPalette.surface, lineWidth: 2))
                        }
                    }.accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(commanderLabel)
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("\(opponentName) · vs your deck: \(game.title)")
                        .font(.caption).lineLimit(2)
                    Text(game.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    HStack(spacing: 5) {
                        statTile("Result", value: result)
                        statTile("Duration", value: duration)
                        statTile("Turn", value: game.observedTurn > 0 ? "\(game.observedTurn)" : "—")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DeckStudioPalette.secondaryInk)
            }
            .contentShape(Rectangle())
            .padding(12)
            .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 70)
        .accessibilityIdentifier("deckHistory.match.\(game.id.uuidString).expand")
        .accessibilityLabel("\(commanderLabel), \(opponentName), versus your deck \(game.title), \(result), \(duration), \(turnDescription), \(game.startedAt.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Open full-screen match dashboard")
    }

    private func statTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .padding(.horizontal, 5)
        .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}

private enum MatchHistoryText {
    static func commanders(_ game: DeckStudioRecordedGame) -> [String] {
        game.opponents?.flatMap(\.commanders) ?? []
    }
    static func opponentName(_ game: DeckStudioRecordedGame) -> String {
        let name = game.opponents?.map(\.name).joined(separator: " · ") ?? ""
        return name.isEmpty ? "AI opponent" : name
    }
    static func result(_ game: DeckStudioRecordedGame) -> String {
        switch game.end {
        case .completed: game.won.map { $0 ? "Won" : "Not won" } ?? "Unknown"
        case .inProgress: "In progress"
        case .left: "Left game"
        case .interrupted: "Interrupted"
        case .engineFailed: "Engine stopped"
        }
    }
    static func duration(_ game: DeckStudioRecordedGame) -> String {
        let minutes = Int(game.elapsedSeconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

struct MatchHistoryDashboard: View {
    let game: DeckStudioRecordedGame
    let exactDeck: Bool
    let layoutFixture: Bool
    let metadata: NativeDeckMetadataCatalogue?
    @Environment(\.dismiss) private var dismiss
    @State private var sampleIndex = 0
    @State private var didSelectLatestSample = false
    @State private var inspectedCard: InspectedCard?

    private struct InspectedCard: Identifiable { let id: String; let name: String }

    private var ownCommanders: [String] { game.deck.rows.filter { $0.section == "commanders" }.map(\.name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        statTile("Result", value: MatchHistoryText.result(game))
                        statTile("Duration", value: MatchHistoryText.duration(game))
                        statTile("Turn", value: game.observedTurn > 0 ? "\(game.observedTurn) observed" : "Not observed")
                    }
                    if let timeline = game.timeline, !timeline.samples.isEmpty {
                        DeckStudioObservedTimelineView(timeline: timeline, viewerPlayerID: game.viewerPlayerID,
                                                       sampleIndex: $sampleIndex) { id, name in
                            inspectedCard = .init(id: id, name: name)
                        }
                    } else {
                        Text(game.timeline == nil ? "Detailed history was not recorded for this match." :
                                "No public game state was observed for detailed history.")
                            .font(.subheadline)
                            .foregroundStyle(DeckStudioPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    DisclosureGroup("Match info") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(exactDeck ? "Exact current playing deck" : "Historical playing deck · may differ from current draft")
                            Text("Your commander: \(ownCommanders.isEmpty ? "Not recorded" : ownCommanders.joined(separator: " · "))")
                            Text("\(game.deck.rows.reduce(0) { $0 + $1.count }) playing cards · \(game.deck.rows.count) distinct entries")
                            if game.opponents == nil { Text("Opponent identity was not recorded.") }
                            if game.end != .completed { Text("Unfinished session · no confirmed result") }
                            ForEach(game.commandZoneCasts.keys.sorted(), id: \.self) { name in
                                Text("\(name): \(game.commandZoneCasts[name, default: 0]) observed command-zone casts")
                            }
                            Text("App \(game.appBuild) · XMage \(game.upstream) · catalogue \(game.catalogue)")
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                        .foregroundStyle(DeckStudioPalette.secondaryInk)
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(16)
                    .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 960)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("deckHistory.dashboard.scroll")
            .background(DeckStudioPalette.background)
            .navigationTitle("Match history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Back to history", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("deckHistory.dashboard.close")
                }
            }
        }
        .onAppear {
            guard !didSelectLatestSample else { return }
            didSelectLatestSample = true
            sampleIndex = max(0, (game.timeline?.samples.count ?? 1) - 1)
        }
        .sheet(item: $inspectedCard) { card in
            DeckStudioCardInspector(name: card.name, metadata: metadata?.card(named: card.name))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let opponents = game.opponents, !opponents.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                    ForEach(Array(opponents.enumerated()), id: \.offset) { item in
                        opponentCard(item.element, number: item.offset + 1)
                    }
                }
            } else {
                Label("Opponent identity and commander not recorded", systemImage: "person.crop.rectangle.stack")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DeckStudioPalette.secondaryInk)
            }
            Text("vs your deck · \(game.title.isEmpty ? "Untitled deck" : game.title)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DeckStudioPalette.ink)
                .lineLimit(2)
            Text(game.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(DeckStudioPalette.secondaryInk)
            if layoutFixture {
                Text("Development fixture · not saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DeckStudioPalette.warning)
                    .accessibilityIdentifier("deckHistory.dashboard.fixture")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func opponentCard(_ opponent: DeckStudioRecordedGame.Opponent, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Opponent \(number) · \(opponent.name)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DeckStudioPalette.ink)
                .lineLimit(2)
            HStack(alignment: .top, spacing: 9) {
                if opponent.commanders.isEmpty {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.title3)
                        .frame(width: 50, height: 70)
                        .background(DeckStudioPalette.background)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)
                } else {
                    HStack(spacing: -20) {
                        ForEach(Array(opponent.commanders.prefix(2).enumerated()), id: \.offset) { item in
                            DeckStudioArtwork(name: item.element)
                                .frame(width: 50, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DeckStudioPalette.surface, lineWidth: 2))
                        }
                    }
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if opponent.commanders.isEmpty {
                        Text("Commander not recorded")
                            .foregroundStyle(DeckStudioPalette.secondaryInk)
                    } else {
                        ForEach(Array(opponent.commanders.prefix(2).enumerated()), id: \.offset) { item in
                            Text(item.element).lineLimit(2)
                        }
                        if opponent.commanders.count > 2 {
                            DisclosureGroup("\(opponent.commanders.count - 2) more commanders") {
                                ForEach(Array(opponent.commanders.dropFirst(2).enumerated()), id: \.offset) { item in
                                    Text(item.element).padding(.top, 3)
                                }
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(DeckStudioPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
    }

    private func statTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            Text(value).font(.headline).foregroundStyle(DeckStudioPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(12)
        .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Samples advance when a public metric or structured observation changes.
/// Scrubbing reviews the sampled evidence; it cannot reconstruct intervening play.
private struct DeckStudioObservedTimelineView: View {
    let timeline: DeckStudioPublicTimeline
    let viewerPlayerID: String?
    @Binding var sampleIndex: Int
    let onInspect: (String, String) -> Void
    @State private var showAllEvents = false

    private struct Point: Identifiable {
        let id: String
        let observation: Int
        let playerID: String
        let life: Int
        let battlefield: Int
    }
    private struct PlayerSeries: Identifiable {
        let id: String
        let label: String
        let color: Color
    }
    private var playerSeries: [PlayerSeries] {
        guard let players = timeline.samples.last?.players else { return [] }
        let viewer = players.filter { $0.id == viewerPlayerID }
        let opponents = players.filter { $0.id != viewerPlayerID }
        let colors: [Color] = [.blue, .orange, .green, .purple]
        return (viewer + opponents).enumerated().map { position, player in
            let label = player.id == viewerPlayerID ? "You" :
                "Opponent \(position - viewer.count + 1) · \(player.name)"
            return PlayerSeries(id: player.id, label: label, color: colors[position % colors.count])
        }
    }
    private var points: [Point] {
        let step = max(1, timeline.samples.count / 240)
        let chartSamples = timeline.samples.enumerated().compactMap { position, sample -> (Int, DeckStudioPublicTimeline.Sample)? in
            position.isMultiple(of: step) || position == timeline.samples.count - 1 ? (position, sample) : nil
        }
        return chartSamples.flatMap { position, sample in
            sample.players.map { player in
                Point(id: "\(position):\(player.id)",
                      observation: position + 1,
                      playerID: player.id, life: player.life,
                      battlefield: player.battlefieldCount)
            }
        }
    }
    private var index: Int { min(max(sampleIndex, 0), timeline.samples.count - 1) }
    private var sample: DeckStudioPublicTimeline.Sample { timeline.samples[index] }
    private var events: [DeckStudioPublicTimeline.Event] {
        timeline.events.filter { event in
            (event.revision <= sample.revision ||
             (index == timeline.samples.count - 1 && event.kind == .outcome)) &&
            (showAllEvents || event.turn == sample.turn ||
             (index == timeline.samples.count - 1 && event.kind == .outcome))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Turn review").font(.headline).foregroundStyle(DeckStudioPalette.ink)
                .accessibilityIdentifier("deckHistory.timeline.dashboard")
            Text("Public state observations · gaps between samples are unknown")
                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            if timeline.samplesTruncated || timeline.eventsTruncated {
                Text("History trimmed · earlier observations may be missing")
                    .font(.caption).foregroundStyle(DeckStudioPalette.warning)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    chart(title: "Observed life", value: \.life)
                        .frame(minWidth: 280)
                        .accessibilityIdentifier("deckHistory.chart.life")
                    chart(title: "Battlefield count", value: \.battlefield)
                        .frame(minWidth: 280)
                        .accessibilityIdentifier("deckHistory.chart.battlefield")
                }
                VStack(spacing: 12) {
                    chart(title: "Observed life", value: \.life)
                        .accessibilityIdentifier("deckHistory.chart.life")
                    chart(title: "Battlefield count", value: \.battlefield)
                        .accessibilityIdentifier("deckHistory.chart.battlefield")
                }
            }
            reviewCard
            eventsCard
            DisclosureGroup("About this review") {
                Text("These are sampled public states and recognized public events, not a full engine replay. The charts follow successful observations; gaps are unknown. Life changes are not damage dealt. A card appearing on the battlefield or stack is not proof of a cast. Observation numbers are not turns.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .padding(.top, 8)
            }
            .font(.caption.weight(.medium))
            .padding(14)
            .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(sample.turn > 0 ? "Turn \(sample.turn)" : "Turn not observed") · observation \(index + 1)/\(timeline.samples.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { sampleIndex = max(0, index - 1) } label: {
                    Label("Previous observation", systemImage: "chevron.left").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }.disabled(index == 0).accessibilityIdentifier("deckHistory.timeline.previous")
                Slider(value: Binding(get: { Double(index) }, set: { sampleIndex = Int($0.rounded()) }),
                       in: 0...Double(max(0, timeline.samples.count - 1)), step: 1)
                    .disabled(timeline.samples.count < 2)
                    .accessibilityLabel("Game observation")
                    .accessibilityValue("Turn \(sample.turn), observation \(index + 1) of \(timeline.samples.count)")
                    .accessibilityIdentifier("deckHistory.timeline.scrubber")
                Button { sampleIndex = min(timeline.samples.count - 1, index + 1) } label: {
                    Label("Next observation", systemImage: "chevron.right").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }.disabled(index == timeline.samples.count - 1)
                    .accessibilityIdentifier("deckHistory.timeline.next")
            }
            ForEach(sample.players, id: \.id) { player in
                HStack {
                    Text(player.id == viewerPlayerID ? "You" : player.name)
                    Spacer(minLength: 8)
                    Text("\(player.life) life · \(player.battlefieldCount) permanents")
                }.font(.caption).foregroundStyle(DeckStudioPalette.ink)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("All events so far", isOn: $showAllEvents)
                .font(.caption).tint(DeckStudioPalette.accent)
                .accessibilityIdentifier("deckHistory.timeline.allEvents")
            Text(showAllEvents ? "Public events so far" : "This turn’s public events")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DeckStudioPalette.ink)
            if events.isEmpty {
                Text("No recorded public events here.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            } else {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(events.enumerated()), id: \.offset) { item in
                        eventRow(item.element, position: item.offset)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func chart(title: String, value: KeyPath<Point, Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DeckStudioPalette.ink)
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Observation", point.observation), y: .value(title, point[keyPath: value]))
                        .foregroundStyle(by: .value("Player ID", point.playerID))
                    PointMark(x: .value("Observation", point.observation), y: .value(title, point[keyPath: value]))
                        .foregroundStyle(by: .value("Player ID", point.playerID))
                        .symbolSize(14)
                }
                RuleMark(x: .value("Selected observation", index + 1))
                    .foregroundStyle(DeckStudioPalette.accent.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .frame(height: 170)
            .chartForegroundStyleScale(domain: playerSeries.map(\.id), range: playerSeries.map(\.color))
            .chartXScale(domain: 1...max(2, timeline.samples.count))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("Observation")
            .chartLegend(.hidden)
            .accessibilityLabel("\(title) trend over \(timeline.samples.count) observed states")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 5) {
                ForEach(playerSeries) { series in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Circle().fill(series.color).frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text(series.label).font(.caption2).lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(series.label)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func eventRow(_ event: DeckStudioPublicTimeline.Event, position: Int) -> some View {
        let identifier = "deckHistory.event.\(event.revision).\(event.kind.rawValue).\(position)"
        return HStack(alignment: .top, spacing: 9) {
            if let card = event.cardName {
                DeckStudioArtwork(name: card).frame(width: 36, height: 49)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "flag.checkered").frame(width: 36, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(eventTitle(event)).font(.caption.weight(.semibold))
                    .accessibilityIdentifier(identifier)
                    .foregroundStyle(DeckStudioPalette.ink)
                if let type = event.typeLine { Text(type).font(.caption2) }
                Text("Turn \(event.turn)").font(.caption2)
            }
            Spacer(minLength: 0)
            if let card = event.cardName {
                Button {
                    onInspect(identifier, card)
                } label: {
                    Label("Inspect \(card)", systemImage: "rectangle.portrait.and.arrow.right")
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier(identifier + ".inspect")
            }
        }
        .frame(minHeight: 49)
    }

    private func eventTitle(_ event: DeckStudioPublicTimeline.Event) -> String {
        switch event.kind {
        case .battlefieldAppearance:
            let owner = sample.players.first(where: { $0.id == event.playerID })
            return "\(event.cardName ?? "Card") seen on \(owner?.id == viewerPlayerID ? "your" : "an opponent's") battlefield"
        case .spellOnStack: return "\(event.cardName ?? "Spell") seen on stack"
        case .cast:
            let actor = sample.players.first(where: { $0.id == event.playerID })
            return "\(actor?.id == viewerPlayerID ? "You" : actor?.name ?? "Opponent") cast \(event.cardName ?? "a card")"
        case .damage:
            let target = sample.players.first(where: { $0.id == event.playerID })
            return "\(event.cardName ?? "A card") dealt \(event.amount ?? 0) damage to \(target?.id == viewerPlayerID ? "you" : target?.name ?? "an opponent")"
        case .lifeChange:
            let player = sample.players.first(where: { $0.id == event.playerID })
            return "\(player?.id == viewerPlayerID ? "You" : player?.name ?? "Opponent") \((event.amount ?? 0) < 0 ? "lost" : "gained") \(abs(event.amount ?? 0)) life"
        case .turnStarted: return "Turn \(event.turn) began"
        case .phase: return "\(event.phaseName?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Phase") phase"
        case .outcome:
            switch event.outcome {
            case "won": return "Confirmed win"
            case "notWon": return "Game ended · you did not win"
            default: return "Game ended · result unknown"
            }
        }
    }
}
