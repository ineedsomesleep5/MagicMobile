import SwiftUI

/// The player's own profile, made to be looked at: rank and its history, the record as a ring, games over
/// time, the commanders played most (as art), color identity, streaks, a shelf of trophies and the latest games
/// as cards. A game with a saved detailed record opens the match dashboard. Android's PlayerProfileScreen matches it.
struct PlayerProfileView: View {
    @ObservedObject var record: PlayerRecordStore
    @ObservedObject var account: PlayerAccount
    let playerName: String
    /// Commanders of the player's own decks (saved, then included), offered as the profile picture.
    var deckCommanders: [String] = []
    let back: () -> Void
    @StateObject private var details = ProfileGameDetails()
    @State private var deckFilter: String?
    @State private var resultFilter: ResultFilter = .all
    @State private var showAllGames = false
    @State private var review: ProfileDashboardRequest?
    @State private var metadata: NativeDeckMetadataCatalogue?
    @State private var previewAsOthers = false

    enum ResultFilter: String, CaseIterable, Identifiable {
        case all, wins, losses, draws
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .wins: return String(localized: "Wins")
            case .losses: return String(localized: "Losses")
            case .draws: return String(localized: "Draws")
            }
        }
        func includes(_ outcome: RankOutcome) -> Bool {
            switch self {
            case .all: return true
            case .wins: return outcome == .win
            case .losses: return outcome == .loss
            case .draws: return outcome == .draw
            }
        }
    }

    private var unlocked: Set<Achievement> { record.achievements }

    var body: some View {
        let scoped = deckFilter.map { id in record.matches.filter { $0.deckID == id } } ?? record.matches
        var summary = ProfileSummary(matches: scoped)
        // The rank history is the ranked standings, whatever deck the totals are narrowed to.
        if deckFilter != nil { summary.rankPoints = ProfileSummary(matches: record.matches).rankPoints }
        return TavernLobbyPage(title: String(localized: "Profile"), back: back) {
            header
            seasonCard(summary)
            if record.stats.decks.count > 1 { deckFilterRow }
            recordCard(summary, scoped: scoped)
            weeksCard(summary)
            if !summary.commanders.isEmpty { commandersCard(summary) }
            if !summary.colors.isEmpty { colorsCard(summary) }
            trophyCard
            gamesCard(scoped)
            privacyCard
            ProfileHistorySettings(details: details).modifier(TavernLeatherCard())
        }
        .onAppear { record.refreshSeason() }
        .task { await details.refresh() }
        .fullScreenCover(item: $review) { request in
            MatchHistoryDashboard(game: request.game, exactDeck: false, layoutFixture: request.fixture, metadata: metadata)
        }
        .fullScreenCover(isPresented: $previewAsOthers) {
            if let name = account.username {
                PublicProfileView(account: account, username: name, challenge: nil) { previewAsOthers = false }
            }
        }
    }

    // MARK: Privacy

    /// Who may open this profile: Public (the default), Friends only or Private. The server enforces it.
    private var privacyCard: some View {
        let signedIn = account.phase == .ready && account.username != nil
        return VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Who can see your profile"))
            ProfileSegmented(options: ProfileVisibility.allCases.map { visibility in
                .init(value: visibility, title: visibility.title, icon: Self.icon(visibility), identifier: "profile.privacy.\(visibility.rawValue)")
            }, selection: Binding(get: { account.visibility }, set: { value in Task { await account.setVisibility(value) } }),
                             identifier: "profile.privacy")
            .disabled(!signedIn || !account.visibilityKnown)
            .opacity(signedIn && account.visibilityKnown ? 1 : 0.55)
            Text(privacyNote(signedIn: signedIn))
                .font(.system(size: 12, design: .serif)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("profile.privacy.note")
            if signedIn && account.profilesAvailable {
                Button(String(localized: "See it as others do")) { previewAsOthers = true }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("profile.privacy.preview")
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.privacyCard")
    }

    private func privacyNote(signedIn: Bool) -> String {
        if !signedIn { return String(localized: "Choose your player name in Friends to share a profile with other players.") }
        if !account.visibilityKnown { return String(localized: "Privacy settings arrive with the next server update. Until then your profile stays as it is.") }
        return account.visibility.detail
    }

    private static func icon(_ visibility: ProfileVisibility) -> String {
        switch visibility {
        case .public: return "globe"
        case .friends: return "person.2.fill"
        case .private: return "hand.raised"
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            CommanderArtMedallion(name: record.shownCommander, diameter: 78)
                .frame(width: 106, height: 106)
                .accessibilityIdentifier("profile.picture")
            VStack(alignment: .leading, spacing: 6) {
                Text(playerName.isEmpty ? String(localized: "Player") : playerName)
                    .font(.system(size: 24, weight: .black, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("profile.name")
                TavernPicker(title: String(localized: "Title"), selection: $record.title, sections: [
                    .init(options: [(String(localized: "No title"), nil)]
                          + Achievement.allCases.filter(unlocked.contains).map { ($0.title, Optional($0)) })
                ], identifier: "profile.title")
                TavernPicker(title: String(localized: "Profile picture"), selection: $record.favoriteCommander,
                             sections: commanderSections, identifier: "profile.commander")
            }
            Spacer(minLength: 0)
        }
        .modifier(TavernLeatherCard())
    }

    /// The profile picture choices: most played (the default), commanders played, then the player's decks.
    private var commanderSections: [TavernPicker<String?>.Section] {
        let played = record.stats.commanders.prefix(12).map(\.label)
        var seen = Set(played)
        let decks = deckCommanders.filter { !$0.isEmpty && seen.insert($0).inserted }
        var sections: [TavernPicker<String?>.Section] = [
            .init(options: [(String(localized: "Most played"), nil)] + played.map { ($0, Optional($0)) })
        ]
        if !decks.isEmpty { sections.append(.init(title: String(localized: "Your decks"), options: decks.map { ($0, Optional($0)) })) }
        // A choice from a deck since deleted stays selectable.
        if let current = record.favoriteCommander, !seen.contains(current) {
            sections.append(.init(options: [(current, Optional(current))]))
        }
        return sections
    }

    // MARK: Rank

    private func seasonCard(_ summary: ProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileRankSummary(position: record.rank.position, seasonName: RankLadder.seasonName(record.rank.season),
                               wins: record.rank.wins, losses: record.rank.losses, peak: record.rank.peak)
            Divider().overlay(TavernPalette.brass.opacity(0.4))
            ProfileSectionTitle(text: String(localized: "Rank history"))
            if summary.rankPoints.isEmpty {
                ProfileEmptyNote(text: String(localized: "Play ranked games to chart your climb."), systemImage: "chart.line.uptrend.xyaxis")
            } else {
                RankHistoryChart(points: summary.rankPoints)
            }
            if !record.rank.history.isEmpty {
                Divider().overlay(TavernPalette.brass.opacity(0.4))
                ForEach(record.rank.history.prefix(4), id: \.season) { past in
                    HStack(spacing: 8) {
                        RankEmblem(tier: past.peak.tier, size: 22)
                        Text("\(RankLadder.seasonName(past.season)): \(past.peak.title)")
                            .font(.system(size: 13, design: .serif))
                        Spacer(minLength: 0)
                        Text("\(past.wins)–\(past.losses)").font(.system(size: 12, design: .serif)).monospacedDigit().opacity(0.7)
                    }
                }
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.season")
    }

    // MARK: Filters

    /// All decks, or one: the totals, charts and games below follow it.
    private var deckFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ProfileChip(title: String(localized: "All decks"), detail: "\(record.matches.count)", selected: deckFilter == nil,
                            identifier: "profile.filter.deck.all") { deckFilter = nil; showAllGames = false }
                ForEach(record.stats.decks.prefix(8)) { deck in
                    ProfileChip(title: deck.label, detail: "\(deck.games)", selected: deckFilter == deck.id,
                                identifier: "profile.filter.deck.\(deck.id)") { deckFilter = deck.id; showAllGames = false }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("profile.filter.decks")
    }

    // MARK: Record

    private func recordCard(_ summary: ProfileSummary, scoped: [MatchRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionTitle(text: deckFilter.flatMap { id in record.stats.decks.first { $0.id == id }?.label } ?? String(localized: "Record"),
                                trailing: String(localized: "\(summary.games) games"))
            if summary.games == 0 {
                ProfileEmptyNote(text: String(localized: "Your games show here after you play."))
            } else {
                HStack(alignment: .center, spacing: 14) {
                    WinRateRing(wins: summary.wins, losses: summary.losses, draws: summary.draws, size: 118)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ProfileStatTile(title: String(localized: "Wins"), value: "\(summary.wins)")
                        ProfileStatTile(title: String(localized: "Losses"), value: "\(summary.losses)")
                        ProfileStatTile(title: String(localized: "Draws"), value: "\(summary.draws)")
                        ProfileStatTile(title: String(localized: "Avg. turns"), value: summary.averageTurns.map { String(format: "%.1f", $0) } ?? "–")
                    }
                }
                StreakRow(current: summary.currentStreak, best: summary.bestStreak)
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.stats")
    }

    private func weeksCard(_ summary: ProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Games over time"), trailing: String(localized: "last 8 weeks"))
            if summary.weeks.allSatisfy({ $0.games == 0 }) {
                ProfileEmptyNote(text: String(localized: "Nothing played in the last eight weeks."), systemImage: "calendar")
            } else {
                WeeklyBars(weeks: summary.weeks)
                HStack(spacing: 14) {
                    legend(ProfilePalette.win, String(localized: "Won"))
                    legend(ProfilePalette.loss, String(localized: "Not won"))
                }
            }
        }
        .modifier(TavernLeatherCard())
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: 11, weight: .semibold, design: .serif)).opacity(0.75)
        }
        .accessibilityHidden(true)
    }

    private func commandersCard(_ summary: ProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Most played commanders"))
            CommanderTiles(shares: summary.commanders)
        }
        .modifier(TavernLeatherCard())
    }

    private func colorsCard(_ summary: ProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Color identity"))
            ColorPie(shares: summary.colors)
        }
        .modifier(TavernLeatherCard())
    }

    // MARK: Trophies

    private var trophyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Trophies"), trailing: "\(unlocked.count)/\(Achievement.allCases.count)")
            TrophyShelf(unlocked: unlocked)
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.achievements")
    }

    // MARK: Games

    private func gamesCard(_ scoped: [MatchRecord]) -> some View {
        let visible = scoped.filter { resultFilter.includes($0.outcome) }
        let shown = Array(visible.prefix(showAllGames ? 40 : 6))
        return VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Recent games"), trailing: String(localized: "\(visible.count) shown"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ResultFilter.allCases) { filter in
                        ProfileChip(title: filter.title, selected: resultFilter == filter, identifier: "profile.filter.result.\(filter.rawValue)") {
                            resultFilter = filter; showAllGames = false
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(minHeight: 44)
            if record.matches.isEmpty {
                ProfileEmptyNote(text: String(localized: "Your games show here after you play."))
            } else if visible.isEmpty {
                ProfileEmptyNote(text: String(localized: "No games match these filters."), systemImage: "line.3.horizontal.decrease")
            }
            ForEach(shown) { match in gameCard(match) }
            if visible.count > 6 {
                Button(showAllGames ? String(localized: "Show fewer") : String(localized: "Show more")) {
                    withAnimation { showAllGames.toggle() }
                }
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                .accessibilityIdentifier("profile.games.more")
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.history")
    }

    @ViewBuilder
    private func gameCard(_ match: MatchRecord) -> some View {
        let recorded = match.engineMatchID.flatMap { details.byMatch[$0] }
        ProfileGameCard(game: ProfileGame(match),
                        identifier: recorded.map { "deckHistory.match.\($0.id.uuidString).expand" } ?? "profile.game.\(match.id.uuidString)",
                        openPlayer: nil,
                        onOpenDetail: recorded.map { game in { openDashboard(game) } })
    }

    private func openDashboard(_ game: DeckStudioRecordedGame) {
        review = ProfileDashboardRequest(game: game)
        guard metadata == nil else { return }
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { try? NativeDeckMetadataCatalogue.bundled() }.value
            metadata = loaded
        }
    }
}

/// A profile picture: the commander's illustration alone (no card frame) in the table's brass ring.
struct CommanderArtMedallion: View {
    let name: String?
    var diameter: CGFloat = 78

    var body: some View {
        TavernMedallion(diameter: diameter, life: nil) {
            ZStack {
                LinearGradient(colors: [MagicPalette.iron, MagicPalette.leather], startPoint: .top, endPoint: .bottom)
                if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NativeCardArtworkView(name: name, variant: .board, contentMode: .fill, artOnly: true) { _, _ in placeholder }
                } else {
                    placeholder
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(name.map { String(localized: "Profile picture: \($0)") } ?? String(localized: "Profile picture"))
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: diameter * 0.42, weight: .bold))
            .foregroundStyle(TavernPalette.parchment.opacity(0.55))
    }
}
