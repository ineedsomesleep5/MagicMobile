import SwiftUI

/// Another player's profile (or your own, as others see it): their rank and its history, record, commanders, colors and
/// recent games with the names of who they played. Add friend, Challenge, Block and Report live here. Opponents' names
/// open their profiles in turn. Android's PublicProfileScreen matches it.
struct PublicProfileView: View {
    @ObservedObject var account: PlayerAccount
    let username: String
    /// Challenges a friend who is online to a Quick Match or a Ranked game (nil hides the button).
    var challenge: ((String, PlayMode) -> Void)? = nil
    /// Your ranked step this season: Ranked challenges need a friend in the same tier.
    var myRankStep: Int? = nil
    let close: () -> Void

    private enum Load: Equatable {
        case loading
        case loaded(PublicProfile)
        case notFound
        case unavailable
        case failed(String)
    }

    /// The profiles opened one from another (an opponent's name); back returns along them.
    @State private var stack: [String] = []
    @State private var load: Load = .loading
    @State private var confirmBlock = false
    @State private var confirmReport = false
    @State private var showAllGames = false

    private var shown: String { stack.last ?? username }

    var body: some View {
        ZStack(alignment: .bottom) {
            TavernLobbyPage(title: shown, backTitle: stack.count > 1 ? String(localized: "Back") : String(localized: "Friends"), back: goBack) {
                switch load {
                case .loading:
                    SocialWaiting(text: String(localized: "Opening \(shown)'s profile…")).modifier(TavernLeatherCard())
                case .notFound:
                    note(String(localized: "No player has that name, or you can't see them."), icon: "questionmark.circle")
                case .unavailable:
                    note(String(localized: "Player profiles arrive with the next server update. You can still add friends and play with them."), icon: "hourglass")
                case .failed(let message):
                    note(message, icon: "wifi.exclamationmark")
                    Button(String(localized: "Try again")) { Task { await reload() } }
                        .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                        .accessibilityIdentifier("publicProfile.retry")
                case .loaded(let profile):
                    if profile.restricted { restricted(profile) } else { content(profile) }
                }
            }
            if let notice = account.notice, account.phase == .ready {
                SocialNotice(text: notice) { account.notice = nil }
            }
        }
        .task(id: shown) { await reload() }
        .onAppear { if stack.isEmpty { stack = [username] } }
        .tavernConfirmation(active: true, title: String(localized: "Block \(shown)?"),
                            message: String(localized: "They're removed from your friends and can't send you requests. You can unblock them in Friends later."),
                            isPresented: $confirmBlock,
                            actions: [TavernDialogAction(title: String(localized: "Block"), destructive: true) {
                                Task { await account.block(shown); close() }
                            }])
        .tavernConfirmation(active: true, title: String(localized: "Report \(shown)?"),
                            message: String(localized: "The developer reviews reports of a name or a profile. You can also block them."),
                            isPresented: $confirmReport,
                            actions: [TavernDialogAction(title: String(localized: "Report"), destructive: true) {
                                Task { await account.report(shown, message: nil, context: "profile") }
                            }])
    }

    private func goBack() {
        if stack.count > 1 { stack.removeLast(); showAllGames = false } else { close() }
    }

    private func reload() async {
        load = .loading
        let result = await account.publicProfile(shown)
        guard !Task.isCancelled else { return }
        switch result {
        case .profile(let profile): load = .loaded(profile)
        case .notFound: load = .notFound
        case .unavailable: load = .unavailable
        case .failed(let message): load = .failed(message)
        }
    }

    // MARK: Pieces

    private func note(_ text: String, icon: String) -> some View {
        ProfileEmptyNote(text: text, systemImage: icon).modifier(TavernLeatherCard()).accessibilityIdentifier("publicProfile.note")
    }

    private func restricted(_ profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(profile)
            VStack(spacing: 10) {
                Image(systemName: "hand.raised.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                Text(profile.visibility == .friends ? String(localized: "Only friends can open this profile.") : String(localized: "This profile is private."))
                    .font(.system(size: 15, weight: .semibold, design: .serif)).multilineTextAlignment(.center)
                if !profile.isFriend {
                    Text(String(localized: "You can still send \(profile.username) a friend request."))
                        .font(.system(size: 12, design: .serif)).opacity(0.7).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .modifier(TavernLeatherCard())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("publicProfile.restricted")
            actions(profile)
        }
    }

    @ViewBuilder
    private func content(_ profile: PublicProfile) -> some View {
        header(profile)
        if profile.isSelf {
            ProfileEmptyNote(text: String(localized: "This is how other players see your profile. It is \(profile.visibility.title.lowercased())."), systemImage: "eye")
                .modifier(TavernLeatherCard())
                .accessibilityIdentifier("publicProfile.selfNote")
        } else {
            actions(profile)
        }
        rankCard(profile)
        recordCard(profile)
        weeksCard(profile)
        if !profile.summary.commanders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionTitle(text: String(localized: "Most played commanders"))
                CommanderTiles(shares: profile.summary.commanders)
            }.modifier(TavernLeatherCard())
        }
        if !profile.summary.colors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionTitle(text: String(localized: "Color identity"))
                ColorPie(shares: profile.summary.colors)
            }.modifier(TavernLeatherCard())
        }
        gamesCard(profile)
    }

    private func header(_ profile: PublicProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            CommanderArtMedallion(name: profile.favoriteCommander ?? profile.summary.commanders.first?.id, diameter: 78)
                .frame(width: 106, height: 106)
                .accessibilityIdentifier("publicProfile.picture")
            VStack(alignment: .leading, spacing: 7) {
                Text(profile.username).font(.system(size: 24, weight: .black, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("publicProfile.name")
                HStack(spacing: 6) {
                    if let title = profile.title { TavernTag(text: title, leather: true, accent: TavernPalette.ember) }
                    TavernTag(text: relationText(profile), leather: true)
                }
                if let online = profile.online {
                    HStack(spacing: 6) {
                        Circle().fill(online ? Color(red: 0.4, green: 0.85, blue: 0.4) : Color.gray.opacity(0.6)).frame(width: 9, height: 9)
                        Text(online ? String(localized: "Online") : String(localized: "Offline")).font(.system(size: 12, weight: .semibold, design: .serif)).opacity(0.8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publicProfile.header")
    }

    private func relationText(_ profile: PublicProfile) -> String {
        switch profile.relation {
        case "self": return String(localized: "YOU")
        case "friend": return String(localized: "FRIEND")
        case "outgoing": return String(localized: "REQUESTED")
        case "incoming": return String(localized: "WANTS TO BE FRIENDS")
        default: return profile.visibility == .public ? String(localized: "PUBLIC PROFILE") : String(localized: "FRIENDS ONLY")
        }
    }

    @ViewBuilder
    private func actions(_ profile: PublicProfile) -> some View {
        if !profile.isSelf {
            HStack(spacing: 10) {
                switch profile.relation {
                case "friend":
                    if let challenge, profile.online == true { challengeMenu(profile, challenge) }
                case "outgoing":
                    Button(String(localized: "Request sent")) {}.buttonStyle(TavernButtonStyle(kind: .secondary, compact: true)).disabled(true)
                        .accessibilityIdentifier("publicProfile.requested")
                case "incoming":
                    Button(String(localized: "Accept request")) { respond(profile, accept: true) }
                        .buttonStyle(TavernButtonStyle(kind: .primary, compact: true)).accessibilityIdentifier("publicProfile.accept")
                    Button(String(localized: "Decline")) { respond(profile, accept: false) }
                        .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true)).accessibilityIdentifier("publicProfile.decline")
                default:
                    Button(String(localized: "Add friend")) { addFriend(profile) }
                        .buttonStyle(TavernButtonStyle(kind: .primary, compact: true)).accessibilityIdentifier("publicProfile.add")
                }
                Spacer(minLength: 0)
                TavernMenu(arrowEdge: .top) {
                    TavernMenuItem(title: String(localized: "Report player"), systemImage: "exclamationmark.bubble", destructive: true) { confirmReport = true }
                    TavernMenuItem(title: String(localized: "Block player"), systemImage: "hand.raised", destructive: true) { confirmBlock = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .black)).foregroundStyle(BrandTheme.brassGradient)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "More about \(profile.username)"))
                .accessibilityIdentifier("publicProfile.more")
            }
        }
    }

    private func challengeMenu(_ profile: PublicProfile, _ challenge: @escaping (String, PlayMode) -> Void) -> some View {
        let mayRank = myRankStep.map { FriendChallengeRules.mayRank(myStep: $0, friendStep: profile.rank?.position?.step) } ?? false
        return TavernMenu(arrowEdge: .top) {
            TavernMenuItem(title: String(localized: "Quick Match"), systemImage: "bolt.fill") { challenge(profile.username, .quick); close() }
            TavernMenuItem(title: mayRank ? String(localized: "Ranked") : String(localized: "Ranked · same tier only"), systemImage: "shield.lefthalf.filled") {
                if mayRank { challenge(profile.username, .ranked); close() }
            }
        } label: {
            Text(String(localized: "Challenge")).font(.system(size: 14, weight: .heavy, design: .serif))
                .foregroundStyle(Color(red: 1, green: 0.91, blue: 0.66))
                .padding(.horizontal, 22).frame(minHeight: 44)
                .background { TavernFill(material: .ember).clipShape(Capsule()).padding(3) }
                .overlay { TavernCapsuleRim() }
        }
        .accessibilityLabel(String(localized: "Challenge \(profile.username)"))
        .accessibilityIdentifier("publicProfile.challenge")
    }

    private func addFriend(_ profile: PublicProfile) {
        Task { await account.addFriend(profile.username); await reload() }
    }

    private func respond(_ profile: PublicProfile, accept: Bool) {
        guard let friend = account.friends.first(where: { $0.username == profile.username }) else { return }
        Task { await account.respond(to: friend, accept: accept); await reload() }
    }

    // MARK: Cards

    private func rankCard(_ profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let rank = profile.rank, let position = rank.position {
                ProfileRankSummary(position: position, seasonName: RankLadder.seasonName(rank.season), wins: rank.wins, losses: rank.losses,
                                   peak: RankPosition.atStep(rank.peakStep))
                Divider().overlay(TavernPalette.brass.opacity(0.4))
            } else {
                ProfileSectionTitle(text: String(localized: "Rank"))
                ProfileEmptyNote(text: String(localized: "\(profile.username) hasn't played ranked this season."), systemImage: "shield.lefthalf.filled")
            }
            ProfileSectionTitle(text: String(localized: "Rank history"))
            if profile.summary.rankPoints.isEmpty {
                ProfileEmptyNote(text: String(localized: "No ranked games to chart yet."), systemImage: "chart.bar.fill")
            } else {
                RankHistoryChart(points: profile.summary.rankPoints)
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publicProfile.rank")
    }

    private func recordCard(_ profile: PublicProfile) -> some View {
        let summary = profile.summary
        return VStack(alignment: .leading, spacing: 14) {
            ProfileSectionTitle(text: String(localized: "Record"), trailing: String(localized: "\(summary.games) games"))
            if summary.games == 0 {
                ProfileEmptyNote(text: String(localized: "No games to show yet."))
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
        .accessibilityIdentifier("publicProfile.stats")
    }

    private func weeksCard(_ profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Games over time"), trailing: String(localized: "last 8 weeks"))
            if profile.summary.weeks.allSatisfy({ $0.games == 0 }) {
                ProfileEmptyNote(text: String(localized: "Nothing played in the last eight weeks."), systemImage: "hourglass")
            } else {
                WeeklyBars(weeks: profile.summary.weeks)
            }
        }
        .modifier(TavernLeatherCard())
    }

    private func gamesCard(_ profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Recent games"), trailing: String(localized: "\(profile.games.count) shown"))
            if profile.games.isEmpty { ProfileEmptyNote(text: String(localized: "No recent games to show.")) }
            ForEach(profile.games.prefix(showAllGames ? 30 : 6)) { game in
                ProfileGameCard(game: game, identifier: "publicProfile.game.\(game.id)",
                                openPlayer: { name in stack.append(name); showAllGames = false }, onOpenDetail: nil)
            }
            if profile.games.count > 6 {
                Button(showAllGames ? String(localized: "Show fewer") : String(localized: "Show more")) { withAnimation { showAllGames.toggle() } }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("publicProfile.games.more")
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publicProfile.history")
    }
}
