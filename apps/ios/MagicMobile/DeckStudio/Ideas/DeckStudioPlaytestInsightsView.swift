import SwiftUI

struct DeckStudioPlaytestInsightsView: View {
    let signature: DeckStudioDeckSignature?
    @AppStorage(DeckStudioPlaytestStore.enabledKey) private var enabled = false
    @State private var games: [DeckStudioRecordedGame] = []
    @State private var error: String?
    @State private var clearConfirmation = false
    @State private var generation = UUID()
    private var matching: [DeckStudioRecordedGame] { games.filter { $0.deck == signature } }
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Game history").font(.title2.weight(.semibold))
                Toggle("Save AI game summaries", isOn: Binding(get: { enabled }, set: { value in
                    enabled = value
                    Task { await DeckStudioPlaytestStore.shared.setEnabled(value) }
                }))
                Text("Stored on this device. Your hand and opponents’ decks are not recorded.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                if signature == nil { Text("Resolve the playing deck's card names to match its history.").font(.caption) }
                else if matching.isEmpty {
                    Text("No games recorded for this deck yet.").font(.subheadline)
                    Text("Turn on summaries before starting your next game.").font(.caption)
                } else {
                    let completed = matching.filter { $0.end == .completed }
                    Text("\(matching.count) recorded sessions · \(completed.count) completed").font(.subheadline.weight(.semibold))
                    ForEach(matching.prefix(12)) { game in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(game.startedAt, format: .dateTime.month().day().hour().minute()); Spacer(); Text(label(game)) }
                                .font(.subheadline.weight(.medium))
                            Text("\(game.aiOpponents) AI · highest observed turn \(game.observedTurn) · \(Int(game.elapsedSeconds / 60)) min recorded elapsed").font(.caption)
                            ForEach(game.commandZoneCasts.keys.sorted(), id: \.self) { name in
                                Text("\(name): \(game.commandZoneCasts[name, default: 0]) observed command-zone casts").font(.caption)
                            }
                            Text("App \(game.appBuild) · XMage \(game.upstream.prefix(8))").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }.padding(.vertical, 8)
                    }
                    DisclosureGroup("What these summaries measure") {
                        Text("History matches these exact playing cards and quantities. Time includes pauses; turns and commander casts are the last observed values. Interrupted games are not losses. These summaries do not measure every draw, mulligan or mana payment. App and engine versions are shown for each game.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }.font(.caption)
                    if let json = export {
                        ShareLink(item: json) { Label("Export this deck's summaries", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    }
                }
                HStack {
                    Button("Refresh history") { Task { await refresh() } }.frame(minHeight: 44)
                    Spacer()
                    Button("Clear all history", role: .destructive) { clearConfirmation = true }.frame(minHeight: 44)
                }
                Text("Keeps the 100 most recent sessions.")
                    .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
        }
        .task { await refresh() }
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
        guard let data = try? encoder.encode(matching) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func label(_ game: DeckStudioRecordedGame) -> String {
        switch game.end {
        case .completed: return game.won.map { $0 ? "Won" : "Completed — not won" } ?? "Completed"
        case .inProgress: return "In progress"
        case .left: return "Left game"
        case .interrupted: return "Interrupted"
        case .engineFailed: return "Engine stopped"
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
