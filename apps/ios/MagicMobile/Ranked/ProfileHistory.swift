import SwiftUI

/// The detailed records behind the profile's recent games: Deck Studio's saved game history, found by the
/// engine's match id. A game without one still shows on the profile; it just has no dashboard to open.
@MainActor
final class ProfileGameDetails: ObservableObject {
    @Published private(set) var byMatch: [String: DeckStudioRecordedGame] = [:]
    @Published private(set) var notice: String?
    private var generation = UUID()

    func refresh() async {
        let token = generation
        #if DEBUG
        if DeckStudioPlaytestInsightsView.layoutFixtureActive {
            apply(DeckStudioPlaytestInsightsView.fixtureGames(playing: nil)); return
        }
        #endif
        do {
            let games = try await DeckStudioPlaytestStore.shared.summaries()
            let status = await DeckStudioPlaytestStore.shared.status()
            guard generation == token, !Task.isCancelled else { return }
            apply(games)
            notice = status
        } catch {
            guard generation == token else { return }
            notice = String(localized: "Saved game history could not be read. It is kept; clear it only to discard it on purpose.")
        }
    }

    func clear() async {
        generation = UUID()
        do {
            try await DeckStudioPlaytestStore.shared.clear()
            byMatch = [:]
            notice = nil
        } catch {
            notice = String(localized: "Could not remove the saved history. Existing data is kept.")
        }
    }

    private func apply(_ games: [DeckStudioRecordedGame]) {
        byMatch = Dictionary(games.map { ($0.matchID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Which games keep a detailed record, and what is kept. These are the choices Deck Studio's Playtest chapter
/// used to hold; they are local to this phone and apply to the next games against the AI.
struct ProfileHistorySettings: View {
    @ObservedObject var details: ProfileGameDetails
    @AppStorage(DeckStudioPlaytestStore.enabledKey) private var enabled = false
    @AppStorage(DeckStudioPlaytestStore.detailedEnabledKey) private var detailedEnabled = false
    @State private var open = false
    @State private var confirmClear = false

    private var status: String {
        enabled ? (detailedEnabled ? String(localized: "Detail on") : String(localized: "Summaries on")) : String(localized: "Saving off")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shield.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "History settings & privacy")).font(.system(size: 15, weight: .heavy, design: .serif))
                        Text(status).font(.system(size: 12, weight: .semibold, design: .serif)).opacity(0.7)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(open ? String(localized: "Expanded") : String(localized: "Collapsed"))
            .accessibilityIdentifier("deckHistory.settings")
            if let notice = details.notice {
                Text(notice).font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(ProfilePalette.win)
            }
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    TavernToggle(title: String(localized: "Save AI game summaries"), isOn: Binding(get: { enabled }, set: { value in
                        enabled = value
                        if !value { detailedEnabled = false }
                        Task { await DeckStudioPlaytestStore.shared.setEnabled(value) }
                    }))
                    TavernToggle(title: String(localized: "Save detailed public game history"), isOn: Binding(get: { detailedEnabled }, set: { value in
                        detailedEnabled = value
                        Task { await DeckStudioPlaytestStore.shared.setDetailedEnabled(value) }
                    }))
                    .disabled(!enabled)
                    Text(String(localized: "Both choices are local and apply to future AI matches. Detail saves sampled public life totals, battlefield counts, visible cards and recognized public notices. It never saves hands, opponent decks or raw game messages. Turning detail off keeps saved history until you delete it."))
                        .font(.system(size: 12, design: .serif)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(String(localized: "Refresh history")) { Task { await details.refresh() } }
                            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                            .accessibilityIdentifier("deckHistory.refresh")
                        Button(String(localized: "Clear all history")) { confirmClear = true }
                            .buttonStyle(TavernButtonStyle(kind: .danger, compact: true))
                            .accessibilityIdentifier("deckHistory.clear")
                    }
                    Text(String(localized: "Up to 100 recent sessions within 8 MB; oldest sessions are removed first."))
                        .font(.system(size: 11, design: .serif)).opacity(0.6)
                }
                .transition(.opacity)
            }
        }
        .tavernConfirmation(active: true, title: String(localized: "Delete all local game history?"),
                            message: String(localized: "Decks are not deleted. Games already in progress will not restore the cleared history."),
                            isPresented: $confirmClear,
                            actions: [TavernDialogAction(title: String(localized: "Delete history"), destructive: true) { Task { await details.clear() } }])
    }
}

/// The match dashboard to present for one game.
struct ProfileDashboardRequest: Identifiable {
    let game: DeckStudioRecordedGame
    var id: UUID { game.id }
    var fixture: Bool { ProfileDashboardRequest.fixtureActive }

    static var fixtureActive: Bool {
        #if DEBUG
        DeckStudioPlaytestInsightsView.layoutFixtureActive
        #else
        false
        #endif
    }
}
