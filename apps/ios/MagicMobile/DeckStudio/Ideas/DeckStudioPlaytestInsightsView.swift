import SwiftUI
import Charts

struct DeckStudioPlaytestInsightsView: View {
    let signature: DeckStudioDeckSignature?
    @AppStorage(DeckStudioPlaytestStore.enabledKey) private var enabled = false
    @AppStorage(DeckStudioPlaytestStore.detailedEnabledKey) private var detailedEnabled = false
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
                    if !value { detailedEnabled = false }
                    Task { await DeckStudioPlaytestStore.shared.setEnabled(value) }
                }))
                Toggle("Save detailed public game history", isOn: Binding(get: { detailedEnabled }, set: { value in
                    detailedEnabled = value
                    Task { await DeckStudioPlaytestStore.shared.setDetailedEnabled(value) }
                }))
                .disabled(!enabled)
                Text("Both choices are local and apply to future AI matches. Detail records sampled public life totals, battlefield counts, visible card appearances and recognized public game notices. It never saves hands, opponent decks or raw game messages. Turning detail off keeps previously saved history until you delete it.")
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
                        Text("Exact deck means the same playing cards and quantities, not the same title. Only confirmed outcomes count as wins or not-won; unknown outcomes are excluded. Life changes do not measure damage dealt. A card seen on the battlefield or stack is not proof that it was cast. Samples are observed states, not a full replay. Older sessions may lack detail or opponent names. Duration includes pauses.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }.font(.caption)
                    if let json = export {
                        ShareLink(item: json) { Label("Export filtered history", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    }
                }
                HStack {
                    Button("Refresh history") { Task { await refresh() } }.frame(minHeight: 44)
                    Spacer()
                    Button("Clear all history", role: .destructive) { clearConfirmation = true }.frame(minHeight: 44)
                }
                Text("Keeps up to 100 recent sessions within an 8 MB local limit. Older sessions are removed first when full.")
                    .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
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
                deck: playingDeck, title: "Fixture match \(index + 1)", upstream: "fixture", catalogue: "fixture",
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
    let exactDeck: Bool
    let reduceMotion: Bool
    @State private var expanded = false
    private var opponentCommanders: [String] { game.opponents?.flatMap(\.commanders) ?? [] }
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
                    if opponentCommanders.isEmpty {
                        Image(systemName: "person.crop.rectangle.stack").font(.title2)
                            .frame(width: 44, height: 60).background(DeckStudioPalette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityHidden(true)
                    } else {
                        HStack(spacing: -13) {
                            ForEach(Array(opponentCommanders.prefix(3).enumerated()), id: \.offset) { item in
                                DeckStudioArtwork(name: item.element)
                                    .frame(width: 44, height: 60).clipShape(RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(DeckStudioPalette.surface, lineWidth: 2))
                            }
                        }.accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.opponents?.map(\.name).joined(separator: " · ") ?? "AI opponents")
                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(game.title).font(.caption).lineLimit(1)
                        Text("\(result) · \(game.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        Text("\(Int(game.elapsedSeconds / 60)) min recorded · \(game.aiOpponents) AI")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).frame(minHeight: 60)
                .accessibilityIdentifier("deckHistory.match.\(game.id.uuidString).expand")
                .accessibilityLabel("\(game.title), versus \(game.opponents?.map(\.name).joined(separator: ", ") ?? "AI opponents"), \(result), \(game.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityHint(expanded ? "Collapse match details" : "Expand match details")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
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
                    if let timeline = game.timeline, !timeline.samples.isEmpty {
                        DeckStudioObservedTimelineView(timeline: timeline, viewerPlayerID: game.viewerPlayerID)
                    } else {
                        Text(game.timeline == nil ? "Detailed history was not recorded." : "No public game state was observed for detailed history.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                    Text("App \(game.appBuild) · XMage \(game.upstream) · catalogue \(game.catalogue)")
                        .font(.caption2).textSelection(.enabled)
                }.font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }.padding(12).background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Samples advance when a public metric or structured observation changes.
/// Scrubbing reviews the sampled evidence; it cannot reconstruct intervening play.
private struct DeckStudioObservedTimelineView: View {
    let timeline: DeckStudioPublicTimeline
    let viewerPlayerID: String?
    @State private var sampleIndex = 0
    @State private var showAllEvents = false
    @State private var inspectedCard: InspectedCard?
    private struct InspectedCard: Identifiable { let id: String; let name: String }

    private struct Point: Identifiable {
        let id: String
        let turn: Int
        let revision: Int
        let player: String
        let life: Int
        let battlefield: Int
    }
    private var points: [Point] {
        let step = max(1, timeline.samples.count / 240)
        let chartSamples = timeline.samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: step) || index == timeline.samples.count - 1 ? sample : nil
        }
        return chartSamples.flatMap { sample in
            sample.players.map { player in
                Point(id: "\(sample.revision):\(player.id)", turn: sample.turn,
                      revision: sample.revision, player: player.name, life: player.life,
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Observed game dashboard").font(.headline).foregroundStyle(DeckStudioPalette.ink)
                .accessibilityIdentifier("deckHistory.timeline.dashboard")
            Text("Life totals and public battlefield size at sampled polls. Gaps between samples are unknown.")
                .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            if timeline.samplesTruncated || timeline.eventsTruncated {
                Text("Earlier observations or events were trimmed to keep this history on the device.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.warning)
            }
            chart(title: "Life totals", value: \.life)
            chart(title: "Battlefield permanents", value: \.battlefield)
            HStack {
                Text("Turn \(sample.turn) · observation \(index + 1) of \(timeline.samples.count)")
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
                    Text("\(player.life) life · \(player.battlefieldCount) on battlefield")
                }.font(.caption).foregroundStyle(DeckStudioPalette.ink)
            }
            Toggle("Show all events through this observation", isOn: $showAllEvents)
                .font(.caption).tint(DeckStudioPalette.accent)
                .accessibilityIdentifier("deckHistory.timeline.allEvents")
            Text(showAllEvents ? "Public events seen so far" : "Public events on this turn")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DeckStudioPalette.ink)
            if events.isEmpty {
                Text("No structured public card events in this selection.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
            } else {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(events.enumerated()), id: \.offset) { item in
                        eventRow(item.element, position: item.offset)
                    }
                }
            }
            Text("A visible card appearance does not establish a cast. Life changes may come from many effects, so no damage dealt is inferred.")
                .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
        }
        .padding(12)
        .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { sampleIndex = max(0, timeline.samples.count - 1) }
        .sheet(item: $inspectedCard) { card in
            DeckStudioCardInspector(name: card.name, metadata: nil)
        }
    }

    private func chart(title: String, value: KeyPath<Point, Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(DeckStudioPalette.ink)
            Chart(points) { point in
                LineMark(x: .value("Turn", point.turn), y: .value(title, point[keyPath: value]))
                    .foregroundStyle(by: .value("Player", point.player))
                PointMark(x: .value("Turn", point.turn), y: .value(title, point[keyPath: value]))
                    .foregroundStyle(by: .value("Player", point.player))
            }
            .frame(height: 145)
            .chartXAxisLabel("Turn")
            .accessibilityLabel("\(title) trend over \(timeline.samples.count) observed states")
        }
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
                Text("Turn \(event.turn) · poll \(event.revision)").font(.caption2)
            }
            Spacer(minLength: 0)
            if let card = event.cardName {
                Button {
                    inspectedCard = .init(id: identifier, name: card)
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
