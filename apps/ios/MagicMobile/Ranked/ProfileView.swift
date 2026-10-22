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
    /// The title or portrait being chosen, in a panel over the page.
    @State private var choosing: Chooser?
    /// Arena's tab strip along the profile's foot: the player, or what they show.
    @State private var tab: ProfileTab = .overview
    /// Compact height: the phone held sideways.
    @Environment(\.verticalSizeClass) private var verticalSize

    enum Chooser { case title, picture }
    enum ProfileTab: Hashable { case overview, customization }

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

    /// Arena's profile (the judge, 2026-10-22, against Arena's own Profile): the player's name as the headline, the season
    /// rank and the progression under it, the chosen commander as full-height hero art on the right with the cosmetics
    /// pills at its foot, and Arena's Overview / Customization strip along the bottom. Upright the hero leads the page.
    /// Everything else (the season's chart, record, trophies, games, account and privacy) follows in the scroll.
    var body: some View {
        let scoped = deckFilter.map { id in record.matches.filter { $0.deckID == id } } ?? record.matches
        var summary = ProfileSummary(matches: scoped)
        // The rank history is the ranked standings, whatever deck the totals are narrowed to.
        if deckFilter != nil { summary.rankPoints = ProfileSummary(matches: record.matches).rankPoints }
        let wide = verticalSize == .compact
        return TavernLobbyPage(title: "", back: back, showsBack: false, contentWidth: wide ? 940 : nil, scrolls: false) {
            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .overview: overview(summary, scoped: scoped, wide: wide)
                    case .customization: customization(wide: wide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                ArenaSegmented(options: [(String(localized: "Overview"), ProfileTab.overview),
                                         (String(localized: "Customization"), ProfileTab.customization)],
                               selection: $tab, identifier: "profile.tab")
                    .padding(.top, 4)
            }
        }
        .arenaPanel(isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), maxWidth: 620) {
            chooserPanel
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

    /// Overview: sideways the player's column scrolls on the left beside the hero; upright the hero comes first.
    @ViewBuilder private func overview(_ summary: ProfileSummary, scoped: [MatchRecord], wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        nameBlock(size: 34)
                        identity
                        playerStory(summary, scoped: scoped)
                    }
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .mask(ArenaScrollFade())
                .accessibilityIdentifier("lobby.scroll")
                hero(wide: true)
                    .frame(width: 330)
                    .padding(.bottom, 4)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero(wide: false).frame(height: 300)
                    identity
                    playerStory(summary, scoped: scoped)
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .mask(ArenaScrollFade())
            .accessibilityIdentifier("lobby.scroll")
        }
    }

    /// The rest of the player's story, under the season rank: the season's chart and past seasons, the record and its
    /// charts, trophies, games, then the account and who can see it all.
    @ViewBuilder private func playerStory(_ summary: ProfileSummary, scoped: [MatchRecord]) -> some View {
        seasonCard(summary)
        if record.stats.decks.count > 1 { deckFilterRow }
        recordCard(summary, scoped: scoped)
        weeksCard(summary)
        if !summary.commanders.isEmpty { commandersCard(summary) }
        if !summary.colors.isEmpty { colorsCard(summary) }
        trophyCard
        gamesCard(scoped)
        AccountSignInCard(account: account)
        privacyCard
        ProfileHistorySettings(details: details).modifier(TavernLeatherCard())
    }

    // MARK: Privacy

    /// Who may open this profile: Public (the default), Friends only or Private. The server enforces it.
    private var privacyCard: some View {
        let signedIn = account.phase == .ready && account.username != nil
        return VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Who can see your profile"))
            ProfilePrivacyTabs(selection: Binding(get: { account.visibility }, set: { value in Task { await account.setVisibility(value) } }))
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

    fileprivate static func icon(_ visibility: ProfileVisibility) -> String {
        switch visibility {
        case .public: return "globe"
        case .friends: return "person.2.fill"
        case .private: return "hand.raised"
        }
    }

    // MARK: The player

    /// The name, large in serif as Arena writes it, with the chosen title in gold capitals under it.
    private func nameBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playerName.isEmpty ? String(localized: "Player") : playerName)
                .font(.system(size: size, weight: .bold, design: .serif))
                .foregroundStyle(ArenaMenuStyle.text)
                .shadow(color: .black.opacity(0.8), radius: 4)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profile.name")
            if let title = record.title { ArenaCaps(text: title.title) }
        }
    }

    /// Arena's two rows under the name: the season's rank (the emblem with its pips, the record and the peak), then the
    /// progression (games, win rate and trophies) as emblem tiles.
    private var identity: some View {
        let rank = record.rank
        let all = ProfileSummary(matches: record.matches)
        return VStack(alignment: .leading, spacing: 10) {
            ArenaCaps(text: String(localized: "\(RankLadder.seasonName(rank.season)) · Season rank"))
            HStack(alignment: .center, spacing: 14) {
                RankBadge(position: rank.position, size: 64, showsPips: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rank.position.title).font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(ArenaMenuStyle.text)
                    if rank.position.tier != .mythic { RankPips(filled: rank.position.pips, tier: rank.position.tier, size: 10) }
                    Text("\(rank.wins)–\(rank.losses)").font(.system(size: 13, weight: .bold, design: .serif)).monospacedDigit()
                        .foregroundStyle(ArenaMenuStyle.gold)
                    if rank.peak != rank.position {
                        Text(String(localized: "Peak \(rank.peak.title)")).font(.system(size: 11.5, weight: .semibold, design: .serif))
                            .foregroundStyle(ArenaMenuStyle.dim)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .arenaCard(padding: 0)
            ArenaCaps(text: String(localized: "Progression")).padding(.top, 4)
            HStack(spacing: 10) {
                progressTile("\(all.games)", String(localized: "Games"), symbol: "gamecontroller.fill")
                progressTile(all.games == 0 ? "–" : "\(Int((Double(all.wins) / Double(all.games) * 100).rounded()))%", String(localized: "Win rate"),
                             symbol: "chart.pie.fill")
                progressTile("\(unlocked.count)", String(localized: "Trophies"), symbol: "trophy.fill")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile.career")
        }
    }

    /// One of the progression's emblem tiles: a gold emblem over its number and name.
    private func progressTile(_ value: String, _ label: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            ArenaEmblem(symbol: symbol, size: 18, lit: true)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(ArenaMenuStyle.metal, lineWidth: 1.4))
            Text(value).font(.system(size: 19, weight: .bold, design: .serif)).monospacedDigit()
                .foregroundStyle(ArenaMenuStyle.text).lineLimit(1).minimumScaleFactor(0.7)
            ArenaCaps(text: label, size: 8.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .arenaCard(padding: 0)
        .accessibilityElement(children: .combine)
    }

    /// The chosen commander as Arena's avatar art: full height beside the player sideways, across the top upright with the
    /// name over it. Its name sits at the foot, with the cosmetics pills at the bottom right, as Arena's Avatars pills do.
    /// A tap on the art chooses another portrait.
    private func hero(wide: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack(alignment: .bottom) {
            Button { choose(.picture) } label: {
                ArenaArt(name: record.shownCommander ?? "", colors: [])
                    .contentShape(Rectangle())
            }
            .buttonStyle(BrandPressStyle())
            .accessibilityLabel(record.shownCommander.map { String(localized: "Profile picture: \($0)") } ?? String(localized: "Profile picture"))
            .accessibilityHint(String(localized: "Choose a portrait"))
            .accessibilityIdentifier("profile.picture")
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 10) {
                if !wide { nameBlock(size: 30) }
                HStack(alignment: .bottom, spacing: 8) {
                    if let commander = record.shownCommander {
                        Text(commander).font(.system(size: 13, weight: .semibold, design: .serif)).italic()
                            .foregroundStyle(ArenaMenuStyle.text.opacity(0.85)).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 6)
                    titleButton
                    portraitButton
                }
            }
            .padding(14)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
    }

    // MARK: Customization

    /// Arena's Customization board: a tile for each thing the player shows, the portrait large, the title beside it. A tap
    /// opens its chooser.
    private func customization(wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
        return layout {
            customizationTile(String(localized: "Portrait"), identifier: "profile.customize.picture", action: { choose(.picture) }) {
                ArenaArt(name: record.shownCommander ?? "", colors: [])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            customizationTile(String(localized: "Title"), identifier: "profile.customize.title", action: { choose(.title) }) {
                ZStack {
                    Color.black.opacity(0.35)
                    Text(record.title?.title ?? String(localized: "No title"))
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(record.title == nil ? ArenaMenuStyle.dim : ArenaMenuStyle.gold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).frame(minHeight: 50)
                        .background(Capsule().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                        .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                }
            }
            .frame(maxWidth: wide ? 300 : .infinity, maxHeight: wide ? .infinity : 180)
        }
        .padding(.bottom, 10)
    }

    private func customizationTile<Face: View>(_ title: String, identifier: String, action: @escaping () -> Void,
                                               @ViewBuilder face: () -> Face) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            GameAudio.shared.play(.uiOpen)
            action()
        } label: {
            ZStack(alignment: .bottom) {
                face()
                LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: .black.opacity(0.85), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                Text(title).font(.system(size: 16, weight: .bold, design: .serif)).foregroundStyle(ArenaMenuStyle.text)
                    .padding(.bottom, 12)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var titleButton: some View {
        Button { choose(.title) } label: { Text(String(localized: "Title")).fixedSize() }
            .buttonStyle(ArenaPillButtonStyle())
            .accessibilityLabel(String(localized: "Choose a title"))
            .accessibilityIdentifier("profile.title")
    }

    private var portraitButton: some View {
        // One word, sized to it: a pill is never cut short (the judge, 2026-10-22).
        Button { choose(.picture) } label: { Text(String(localized: "Portrait")).fixedSize() }
            .buttonStyle(ArenaPillButtonStyle())
            .accessibilityLabel(String(localized: "Choose a portrait"))
            .accessibilityIdentifier("profile.commander")
    }

    private func choose(_ chooser: Chooser) {
        GameAudio.shared.play(.uiOpen)
        choosing = chooser
    }

    // MARK: Choosers

    /// Arena's cosmetics choosers: the titles as plaques, the portraits as arched art tiles; a tap chooses and closes.
    private var chooserPanel: some View {
        VStack(spacing: 0) {
            ArenaPanelHeader(title: choosing == .title ? String(localized: "Choose a title") : String(localized: "Choose a portrait"),
                             closeIdentifier: "profile.chooser.close")
            ScrollView {
                Group {
                    if choosing == .title { titleGrid } else { pictureGrid }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var titleGrid: some View {
        let earned = Achievement.allCases.filter(unlocked.contains)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                titleTile(nil)
                ForEach(earned, id: \.self) { titleTile($0) }
            }
        }
    }

    private func titleTile(_ value: Achievement?) -> some View {
        let on = record.title == value
        return Button {
            GameAudio.shared.play(.uiConfirm)
            record.title = value
            choosing = nil
        } label: {
            Text(value?.title ?? String(localized: "No title"))
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(on ? ArenaMenuStyle.gold : ArenaMenuStyle.text)
                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(ArenaMenuStyle.gold) : AnyShapeStyle(ArenaGlass.hairline), lineWidth: on ? 2 : 1))
                .shadow(color: on ? ArenaMenuStyle.gold.opacity(0.45) : .clear, radius: 8)
                .contentShape(Capsule())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("profile.title.\(value?.rawValue ?? "none")")
    }

    private var pictureGrid: some View {
        let choices = pictureChoices
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 12) {
                pictureTile(nil, art: record.stats.commanders.first?.label)
                ForEach(choices.played, id: \.self) { pictureTile($0, art: $0) }
            }
            if !choices.decks.isEmpty {
                ArenaCaps(text: String(localized: "Your decks"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 12) {
                    ForEach(choices.decks, id: \.self) { pictureTile($0, art: $0) }
                }
            }
        }
    }

    /// One portrait: the commander's art in the profile's arch, its name under it; "Most played" (nil) follows the games.
    private func pictureTile(_ value: String?, art: String?) -> some View {
        let on = record.favoriteCommander == value
        return Button {
            GameAudio.shared.play(.uiConfirm)
            record.favoriteCommander = value
            choosing = nil
        } label: {
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    let arch = UnevenRoundedRectangle(topLeadingRadius: proxy.size.width / 2, bottomLeadingRadius: 8, bottomTrailingRadius: 8,
                                                      topTrailingRadius: proxy.size.width / 2, style: .continuous)
                    ArenaArt(name: art ?? "", colors: [])
                        .clipShape(arch)
                        .overlay(arch.strokeBorder(on ? AnyShapeStyle(ArenaMenuStyle.gold) : AnyShapeStyle(ArenaGlass.hairline), lineWidth: on ? 2.5 : 1))
                        .shadow(color: on ? ArenaMenuStyle.gold.opacity(0.5) : .black.opacity(0.5), radius: on ? 9 : 5, y: on ? 0 : 3)
                }
                .aspectRatio(0.74, contentMode: .fit)
                Text(value ?? String(localized: "Most played"))
                    .font(.system(size: 11, weight: on ? .bold : .semibold, design: .serif))
                    .foregroundStyle(on ? ArenaMenuStyle.gold : ArenaMenuStyle.text)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityLabel(value ?? String(localized: "Most played"))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// The portrait choices besides "Most played": commanders played most, then the player's decks' commanders, and a
    /// choice from a deck since deleted, which stays selectable.
    private var pictureChoices: (played: [String], decks: [String]) {
        var played = Array(record.stats.commanders.prefix(12).map(\.label))
        var seen = Set(played)
        let decks = deckCommanders.filter { !$0.isEmpty && seen.insert($0).inserted }
        if let current = record.favoriteCommander, !seen.contains(current) { played.append(current) }
        return (played, decks)
    }

    // MARK: Rank

    private func seasonCard(_ summary: ProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
                        // Where the season finished, as the Ranked Hall shows it (the judge, 2026-10-22: one answer).
                        RankEmblem(tier: past.final.tier, size: 22)
                        Text("\(RankLadder.seasonName(past.season)): \(past.final.title)")
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
        // A row that runs on fades at its right edge instead of stopping short (the judge, 2026-10-22).
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
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
            // A row that runs on fades at its right edge instead of stopping short (the judge, 2026-10-22).
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
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

/// Who may see the profile, as Arena's tab strip (Caleb, 2026-10-22: no ember pills in the menus): each choice with its
/// symbol, the chosen one bright over a glowing gold bar. Each keeps its identifier, `profile.privacy.<visibility>`.
private struct ProfilePrivacyTabs: View {
    @Binding var selection: ProfileVisibility

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileVisibility.allCases, id: \.self) { option in
                let on = option == selection
                Button {
                    guard !on else { return }
                    GameAudio.shared.play(.uiTap)
                    selection = option
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: PlayerProfileView.icon(option)).font(.system(size: 12, weight: .bold))
                        Text(option.title).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(ArenaMenuStyle.font(13.5, on ? .bold : .semibold))
                    .foregroundStyle(on ? ArenaMenuStyle.text : ArenaMenuStyle.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(alignment: .bottom) { ArenaTabBar(on: on) }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BrandPressStyle())
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("profile.privacy.\(option.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.35).offset(y: -2) }
        .animation(.easeOut(duration: 0.16), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.privacy")
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
