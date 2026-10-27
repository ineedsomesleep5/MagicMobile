import SwiftUI

// MARK: - Ranked Hall

/// Ranked's front room: your rank card, Play Ranked, the live leaderboard and your past seasons. Android's
/// RankedHallScreen matches it.
struct RankedHallView: View {
    @ObservedObject var account: PlayerAccount
    let rank: RankState
    let play: () -> Void
    let leaderboard: () -> Void
    let profile: () -> Void
    let back: () -> Void

    @State private var appeared = Date()
    @State private var shown = false
    /// The top three and your place, for the Leaderboard choice (nil offline).
    @State private var teaser: RankedLeaderboard?
    /// Compact height: the phone held sideways.
    @Environment(\.verticalSizeClass) private var verticalSize

    private var tier: RankTier { rank.position.tier }

    /// Arena's Season Rewards (the judge, 2026-10-22, against Arena's own): the title with the season's end in orange and the
    /// ways on as plaques beside it, a stair of tier plaques from Bronze to Mythic on the left (what each allows, and which
    /// you have reached), and your current rank in its own column on the right. Past seasons follow in the scroll. The
    /// Ranked tab's page, so no back chevron.
    var body: some View {
        let wide = verticalSize == .compact
        TavernLobbyPage(title: "", back: back, showsBack: false, contentWidth: wide ? 920 : nil, scrolls: false) {
            VStack(alignment: .leading, spacing: 12) {
                header(wide: wide).modifier(HallEntrance(shown: shown, delay: 0))
                if wide {
                    HStack(alignment: .top, spacing: 18) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                tierLadder(wide: true)
                                seasonStrip
                            }
                            .padding(.bottom, 28)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        .mask(ArenaScrollFade())
                        .accessibilityIdentifier("lobby.scroll")
                        currentRank(badge: 104)
                            .frame(width: 250)
                            .modifier(HallEntrance(shown: shown, delay: 0.08))
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            currentRank(badge: 120).modifier(HallEntrance(shown: shown, delay: 0.08))
                            tierLadder(wide: false)
                            seasonStrip
                        }
                        .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .mask(ArenaScrollFade())
                    .accessibilityIdentifier("lobby.scroll")
                }
            }
        }
        .onAppear { shown = true }
        .task { teaser = await account.rankedLeaderboard(.everyone, limit: 3) }
    }

    /// The page's head: "Ranked" in serif with the season's end in orange under it, and the ways on (Play Ranked as the
    /// ember plaque, then the leaderboard and your profile) beside it sideways, under it upright.
    @ViewBuilder private func header(wide: Bool) -> some View {
        let title = VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Ranked")).font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(ArenaMenuStyle.text)
                .accessibilityAddTraits(.isHeader)
            Text(seasonEnds).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.ember)
        }
        let ways = HStack(spacing: 8) {
            Button(String(localized: "Play Ranked")) { GameAudio.shared.play(.menuPlay); play() }
                .buttonStyle(ArenaPlayButtonStyle(fontSize: 16))
                .frame(width: 150, height: 40)
                .accessibilityIdentifier("ranked.hall.play")
            Button { GameAudio.shared.play(.uiOpen); leaderboard() } label: {
                HStack(spacing: 6) {
                    if let teaser, teaser.online > 0 { LeaderboardOnlineDot(size: 7) }
                    Text(String(localized: "Leaderboard"))
                }
            }
            .buttonStyle(ArenaPillButtonStyle())
            .accessibilityIdentifier("ranked.hall.leaderboard")
            profileButton
        }
        if wide {
            HStack(alignment: .center, spacing: 16) { title; Spacer(minLength: 8); ways }
                .padding(.top, 6)
        } else {
            VStack(alignment: .leading, spacing: 10) { title; ways }
                .padding(.top, 6)
        }
    }

    private var seasonEnds: String {
        guard let end = RankLadder.seasonEnd(rank.season) else { return RankLadder.seasonName(rank.season) }
        let days = max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
        if days <= 1 { return String(localized: "Season ends tomorrow") }
        return String(localized: "Season ends in \(days) days")
    }

    /// Arena's stair of reward plaques: each tier a step wider than the one before, its emblem, its name and the decks it
    /// allows; the tiers you've reached lit, yours edged in gold.
    private func tierLadder(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(RankTier.allCases.enumerated()), id: \.offset) { index, step in
                tierPlaque(step, width: (wide ? 300 : 250) + CGFloat(index) * (wide ? 26 : 22))
                    .modifier(HallEntrance(shown: shown, delay: 0.1 + Double(index) * 0.04))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ranked.hall.tiers")
    }

    private func tierPlaque(_ step: RankTier, width: CGFloat) -> some View {
        let reached = step <= tier
        let current = step == tier
        let shape = ArenaRewardPlaque()
        return HStack(spacing: 12) {
            RankEmblem(tier: step, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name).font(ArenaMenuStyle.font(15, .bold)).foregroundStyle(ArenaMenuStyle.text)
                Text(String(localized: "Decks up to Bracket \(step.maxDeckBracket)"))
                    .font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            }
            Spacer(minLength: 6)
            if current {
                ArenaCaps(text: String(localized: "You"), size: 9)
            } else if reached {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(ArenaMenuStyle.gold)
            }
        }
        .padding(.leading, 12).padding(.trailing, 26).padding(.vertical, 7)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            shape.fill(LinearGradient(colors: [ArenaGlass.top.opacity(0.95), ArenaGlass.bottom.opacity(0.95)], startPoint: .top, endPoint: .bottom))
                .frame(width: width)
        }
        .overlay(alignment: .leading) {
            shape.stroke(current ? AnyShapeStyle(ArenaMenuStyle.gold) : AnyShapeStyle(ArenaGlass.hairline), lineWidth: current ? 1.6 : 1)
                .frame(width: width)
                .shadow(color: current ? ArenaMenuStyle.gold.opacity(0.5) : .clear, radius: 6)
        }
        .opacity(reached ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    /// Arena's Current Rank column: the badge turning in its glow with its pips and title, then the season's record.
    private func currentRank(badge size: CGFloat) -> some View {
        VStack(spacing: 10) {
            ArenaCaps(text: String(localized: "Current rank"))
            badge(size: size, glow: size * 1.45)
            HStack(spacing: 18) { stats }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ranked.hall.standing")
    }

    private func badge(size: CGFloat, glow: CGFloat) -> some View {
        ZStack {
            RankGlow(tier: tier, size: glow)
            RankBadge(position: rank.position, size: size, showsPips: true, showsTitle: true,
                      spin: .init(start: appeared, turns: 1, duration: 1.2))
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var stats: some View {
        stat(String(localized: "Wins"), "\(rank.wins)")
        stat(String(localized: "Losses"), "\(rank.losses)")
        stat(String(localized: "Peak"), rank.peak.title)
        if let teaser, let me = teaser.me { stat(String(localized: "Place"), "#\(me.position)") }
    }

    private var profileButton: some View {
        Button(action: profile) { Text(String(localized: "Profile")).fixedSize() }
            .buttonStyle(ArenaPillButtonStyle())
            .accessibilityIdentifier("ranked.hall.profile")
    }

    private var seasonStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArenaCaps(text: String(localized: "Past seasons"))
            if rank.history.isEmpty {
                Text(String(localized: "First season"))
                    .font(ArenaMenuStyle.font(14, .regular)).opacity(0.8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(rank.history.prefix(6), id: \.season) { seasonChip($0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ranked.hall.seasons")
    }

    private func seasonChip(_ record: SeasonRecord) -> some View {
        VStack(spacing: 4) {
            RankEmblem(tier: record.final.tier, size: 44)
            Text(record.final.title).font(ArenaMenuStyle.font(12, .black)).lineLimit(1)
            Text(RankLadder.seasonName(record.season)).font(ArenaMenuStyle.font(10, .semibold)).opacity(0.75)
            Text("\(record.wins)–\(record.losses)").font(ArenaMenuStyle.font(11, .bold)).monospacedDigit().opacity(0.85)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 92)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.6))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black, design: .serif)).monospacedDigit()
            Text(title.uppercased()).font(ArenaMenuStyle.font(9, .heavy)).tracking(1.2).opacity(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    static func daysLeft(_ season: String) -> String {
        guard let end = RankLadder.seasonEnd(season) else { return "" }
        let days = max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
        return days == 1 ? String(localized: " · 1 day left") : String(localized: " · \(days) days left")
    }
}

/// Arena's reward plaque: a bar whose right end comes to a point, like an arrow along the stair.
private struct ArenaRewardPlaque: Shape {
    func path(in rect: CGRect) -> Path {
        let point = min(16, rect.height * 0.45)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 6, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 6), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 6))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 6, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The hall's cards rise into place one after another.
private struct HallEntrance: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 28)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.82).delay(delay), value: shown)
    }
}

/// A slow breathing glow of the tier's metal behind the badge.
private struct RankGlow: View {
    let tier: RankTier
    let size: CGFloat
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [tier.tint.opacity(0.55), tier.tint.opacity(0.12), .clear], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .scaleEffect(breathe ? 1.06 : 0.9)
            .opacity(breathe ? 1 : 0.7)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Leaderboard

/// The season's standings from the server (mm_ranked_leaderboard): everyone or friends, a podium for the top three, rows
/// that slide when places change, a pulsing dot for who's online, a shimmer on Mythic rows and your own row pinned when
/// it's off the list. Refreshes every 20 seconds while open. Android's RankedLeaderboardScreen matches it.
struct RankedLeaderboardView: View {
    @ObservedObject var account: PlayerAccount
    let back: () -> Void

    static let refreshSeconds: UInt64 = 20

    private enum Load: Equatable {
        case loading
        case loaded(RankedLeaderboard)
        case offline
    }

    private struct ProfileTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    /// Everyone, friends, or last season's champions (from the everyone board).
    private enum Tab: Hashable { case everyone, friends, champions }
    @State private var tab: Tab = .everyone
    private var scope: RankedLeaderboard.Scope { tab == .friends ? .friends : .everyone }
    @State private var load: Load = .loading
    @State private var lastPositions: [String: Int] = [:]
    /// Places gained (positive) or lost since the last refresh.
    @State private var moves: [String: Int] = [:]
    @State private var podiumUp = false
    @State private var active = true
    @State private var profile: ProfileTarget?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.joinFriendTable) private var joinFriendTable
    /// Compact height: the phone held sideways.
    @Environment(\.verticalSizeClass) private var verticalSize

    /// Sideways the podium stands on its own glass on the left and the standings run down the right (Caleb, 2026-10-22),
    /// with your own row at the head of the list when it's off it; upright the podium leads and your row is pinned below.
    var body: some View {
        let wide = verticalSize == .compact
        ZStack(alignment: .bottom) {
            TavernLobbyPage(title: String(localized: "Leaderboard"), backTitle: String(localized: "Ranked Hall"), back: back,
                            contentWidth: wide ? 900 : nil) {
                if wide {
                    HStack(spacing: 16) {
                        scopePicker.frame(width: 240)
                        if case .loaded(let board) = load { liveStrip(board) }
                    }
                } else {
                    scopePicker
                }
                switch load {
                case .loading:
                    SocialWaiting(text: String(localized: "Gathering the standings…")).modifier(TavernLeatherCard())
                case .offline:
                    note(String(localized: "The leaderboard needs your profile and a connection. Sign in from your profile, then come back."),
                         icon: "wifi.exclamationmark", identifier: "leaderboard.offline")
                case .loaded(let board):
                    if !wide { liveStrip(board) }
                    if tab == .champions {
                        champions(board, compact: wide)
                    } else if board.entries.isEmpty {
                        note(scope == .friends
                             ? String(localized: "None of your friends has played ranked this season yet. Challenge one from Friends.")
                             : String(localized: "Nobody has played ranked this season yet. Win a game to take the top spot."),
                             icon: "trophy", identifier: "leaderboard.empty")
                    } else if wide {
                        HStack(alignment: .top, spacing: 16) {
                            podium(Array(board.entries.prefix(3)), compact: true)
                                .frame(width: 330)
                            VStack(spacing: 8) {
                                if let me = board.pinnedMe { row(me, pinned: true) }
                                rows(Array(board.entries.dropFirst(3)))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        podium(Array(board.entries.prefix(3)), compact: false)
                        rows(Array(board.entries.dropFirst(3)))
                    }
                    if board.pinnedMe != nil && !wide { Color.clear.frame(height: 72) }
                }
            }
            if !wide, tab != .champions, case .loaded(let board) = load, let me = board.pinnedMe {
                row(me, pinned: true)
                    .frame(maxWidth: 608)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: scenePhase) { _, phase in active = phase == .active }
        .task(id: scope) {
            lastPositions = [:]
            moves = [:]
            if case .loaded(let board) = load, board.scope != scope.rawValue { load = .loading }
            while !Task.isCancelled {
                if active { await refresh() }
                try? await Task.sleep(nanoseconds: Self.refreshSeconds * 1_000_000_000)
            }
        }
        .fullScreenCover(item: $profile) { target in
            PublicProfileView(account: account, username: target.name) { profile = nil }
                .environment(\.joinFriendTable, joinFriendTable)
        }
    }

    private func refresh() async {
        let board = await account.rankedLeaderboard(scope)
        guard !Task.isCancelled else { return }
        guard let board else {
            if case .loaded = load { return }  // keep the last standings through a dropped connection
            load = .offline
            return
        }
        let now = Dictionary(board.entries.map { ($0.username, $0.position) }, uniquingKeysWith: { first, _ in first })
        var changed: [String: Int] = [:]
        for (name, position) in now {
            if let before = lastPositions[name], before != position { changed[name] = before - position }
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.82)) {
            moves = changed
            lastPositions = now
            load = .loaded(board)
        }
    }

    private func open(_ entry: RankedLeaderboard.Entry) {
        GameAudio.shared.play(.uiOpen)
        profile = ProfileTarget(name: entry.username)
    }

    // MARK: Scope

    /// Everyone, friends or last season's champions, as Arena's tab strip.
    private var scopePicker: some View {
        ArenaSegmented(options: [(String(localized: "Everyone"), Tab.everyone), (String(localized: "Friends"), Tab.friends),
                                 (String(localized: "Champions"), Tab.champions)],
                       selection: $tab, identifier: "leaderboard.scope")
    }

    // MARK: Champions
    /// Last season's top three on their podium, or when the first are crowned.
    @ViewBuilder
    private func champions(_ board: RankedLeaderboard, compact: Bool) -> some View {
        if let champions = board.champions, !champions.entries.isEmpty {
            VStack(spacing: 10) {
                ArenaCaps(text: String(localized: "\(RankLadder.seasonName(champions.season)) champions"))
                podium(champions.entries.map(\.row), compact: compact)
                    .frame(maxWidth: compact ? 420 : nil)
            }
            .accessibilityIdentifier("leaderboard.champions")
        } else {
            note(String(localized: "The first champions are crowned when \(RankLadder.seasonName(board.season)) ends."),
                 icon: "crown", identifier: "leaderboard.champions.empty")
        }
    }

    // MARK: Live strip

    private func liveStrip(_ board: RankedLeaderboard) -> some View {
        HStack(spacing: 10) {
            LeaderboardOnlineDot(size: 10)
            Text(board.online == 1 ? String(localized: "1 player online") : String(localized: "\(board.online) players online"))
                .font(ArenaMenuStyle.font(14, .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text([String(localized: "\(board.total) ranked"), RankLadder.seasonName(board.season), RankLadder.seasonCountdown(board.season)]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(ArenaMenuStyle.font(12, .semibold)).opacity(0.75)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Capsule().fill(LinearGradient(colors: [ArenaGlass.top.opacity(0.92), ArenaGlass.bottom.opacity(0.92)],
                                                  startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
        .foregroundStyle(ArenaMenuStyle.text)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("leaderboard.live")
    }

    // MARK: Podium

    /// The top three on their steps, on a glass panel of their own. `compact` (sideways) makes the steps and emblems
    /// shorter so the names always show.
    private func podium(_ top: [RankedLeaderboard.Entry], compact: Bool) -> some View {
        let order = top.count == 3 ? [top[1], top[0], top[2]] : (top.count == 2 ? [top[1], top[0]] : top)
        return HStack(alignment: .bottom, spacing: compact ? 8 : 10) {
            ForEach(order) { podiumStep($0, compact: compact) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .arenaCard(padding: 12)
        .onAppear { podiumUp = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leaderboard.podium")
    }

    private func podiumStep(_ entry: RankedLeaderboard.Entry, compact: Bool) -> some View {
        let place = entry.position
        let height: CGFloat = compact ? (place == 1 ? 72 : (place == 2 ? 56 : 44)) : (place == 1 ? 112 : (place == 2 ? 84 : 66))
        let emblem: CGFloat = compact ? (place == 1 ? 58 : 46) : (place == 1 ? 74 : 58)
        let slab = UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
        return Button { open(entry) } label: {
            VStack(spacing: compact ? 4 : 6) {
                if place == 1 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: compact ? 18 : 22, weight: .black))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .shadow(color: TavernPalette.ember.opacity(0.7), radius: 6)
                }
                ZStack {
                    if place == 1 { RankGlow(tier: entry.rank.tier, size: compact ? 86 : 110) }
                    RankEmblem(tier: entry.rank.tier, size: emblem)
                        .overlay(alignment: .bottomTrailing) {
                            if entry.online { LeaderboardOnlineDot(size: 12).padding(4) }
                        }
                }
                Text(entry.username)
                    .font(.system(size: place == 1 ? (compact ? 14 : 15) : (compact ? 12 : 13), weight: .black, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(entry.title ?? entry.rank.title)
                    .font(.system(size: compact ? 10 : 11, design: .serif)).italic().opacity(0.8)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // The step: dark glass lit with gold from its top edge, its place in gold.
                ZStack(alignment: .top) {
                    LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)
                        .overlay(LinearGradient(colors: [ArenaMenuStyle.gold.opacity(place == 1 ? 0.24 : 0.13), .clear],
                                                startPoint: .top, endPoint: .bottom))
                    Text("\(place)")
                        .font(.system(size: place == 1 ? (compact ? 28 : 34) : (compact ? 22 : 26), weight: .black, design: .serif))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .padding(.top, compact ? 6 : 8)
                }
                .frame(height: podiumUp || reduceMotion ? height : 14)
                .clipShape(slab)
                // The same even rim on every step (the judge, 2026-10-22: the Mythic sweep left a one-sided smear on #1).
                .overlay(slab.stroke(entry.you ? AnyShapeStyle(ArenaMenuStyle.gold) : AnyShapeStyle(ArenaGlass.hairline),
                                     lineWidth: entry.you ? 2.5 : 1.2))
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.72).delay(place == 1 ? 0.3 : (place == 2 ? 0.15 : 0)),
                           value: podiumUp)
            }
            .foregroundStyle(ArenaMenuStyle.text)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(entry))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("leaderboard.row.\(entry.username)")
    }

    // MARK: Rows

    /// The standings below the podium, a tier's name over its first row.
    private func rows(_ entries: [RankedLeaderboard.Entry]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index == 0 || entries[index - 1].rank.tier != entry.rank.tier { tierHeader(entry.rank.tier) }
                row(entry, pinned: false)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
    }

    private func tierHeader(_ tier: RankTier) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(ArenaMenuStyle.gold.opacity(0.35)).frame(height: 1)
            Text(tier.name.uppercased()).font(ArenaMenuStyle.font(11, .heavy)).tracking(1.2).foregroundStyle(ArenaMenuStyle.gold)
                .fixedSize()
            Rectangle().fill(ArenaMenuStyle.gold.opacity(0.35)).frame(height: 1)
        }
        .padding(.top, 4)
        .accessibilityAddTraits(.isHeader)
    }

    /// Three straight wins or more: a flame with the count.
    private func streakMark(_ streak: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill").font(.system(size: 10, weight: .black))
            Text("\(streak)").font(ArenaMenuStyle.font(11, .heavy)).monospacedDigit()
        }
        .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.25))
        .accessibilityLabel(String(localized: "\(streak) wins in a row"))
    }

    private func row(_ entry: RankedLeaderboard.Entry, pinned: Bool) -> some View {
        let rank = entry.rank
        let mythic = rank.tier == .mythic
        return Button { open(entry) } label: {
            HStack(spacing: 12) {
                Text("\(entry.position)")
                    .font(.system(size: 17, weight: .black, design: .serif)).monospacedDigit()
                    .foregroundStyle(BrandTheme.brassGradient)
                    .frame(minWidth: 34)
                // Their commander's art, their rank's emblem on its rim.
                ZStack(alignment: .bottomTrailing) {
                    CommanderArtMedallion(name: entry.commander, diameter: 40).frame(width: 44, height: 44)
                    RankEmblem(tier: rank.tier, size: 20).offset(x: 4, y: 4)
                }
                .overlay(alignment: .topTrailing) { if entry.online { LeaderboardOnlineDot(size: 9) } }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.username).font(ArenaMenuStyle.font(16, .black)).lineLimit(1)
                        if entry.you { TavernTag(text: String(localized: "YOU"), leather: true) }
                    }
                    Text([rank.title, entry.title, entry.winRate.map { String(localized: "\($0)% wins") }].compactMap { $0 }.joined(separator: " · "))
                        .font(ArenaMenuStyle.font(12, .regular)).opacity(0.75).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    if let move = moves[entry.username] { moveMark(move) }
                    else if let streak = entry.streak, streak >= 3 { streakMark(streak) }
                    Text("\(entry.wins)–\(entry.losses)")
                        .font(ArenaMenuStyle.font(13, .bold)).monospacedDigit().opacity(0.85)
                    if !mythic { RankPips(filled: rank.pips, tier: rank.tier, size: 7) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                LinearGradient(colors: [ArenaGlass.top.opacity(0.94), ArenaGlass.bottom.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                    .overlay(LinearGradient(colors: [ArenaMenuStyle.gold.opacity(entry.you ? 0.16 : 0.04), .clear], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(entry.you ? ArenaMenuStyle.gold : Color.white.opacity(0.12), lineWidth: entry.you ? 2 : 1)
            }
            .modifier(MythicShimmer(active: mythic, cornerRadius: 10))
            .shadow(color: mythic ? ArenaMenuStyle.gold.opacity(0.3) : .black.opacity(pinned ? 0.6 : 0.35), radius: pinned ? 10 : 5, y: 3)
            .foregroundStyle(ArenaMenuStyle.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(entry))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(pinned ? "leaderboard.me" : "leaderboard.row.\(entry.username)")
    }

    private func moveMark(_ move: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: move > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8, weight: .black))
            Text("\(abs(move))").font(ArenaMenuStyle.font(11, .heavy)).monospacedDigit()
        }
        .foregroundStyle(move > 0 ? ArenaMenuStyle.win : ArenaMenuStyle.loss)
        .transition(.scale.combined(with: .opacity))
    }

    private func accessibilityText(_ entry: RankedLeaderboard.Entry) -> String {
        var parts = [String(localized: "Number \(entry.position)"), entry.username, entry.rank.title]
        if let title = entry.title { parts.append(title) }
        if entry.online { parts.append(String(localized: "online")) }
        parts.append(String(localized: "\(entry.wins) wins, \(entry.losses) losses"))
        if let streak = entry.streak, streak >= 3 { parts.append(String(localized: "\(streak) wins in a row")) }
        if entry.you { parts.append(String(localized: "you")) }
        return parts.joined(separator: ", ")
    }

    private func note(_ text: String, icon: String, identifier: String) -> some View {
        Label(text, systemImage: icon)
            .font(ArenaMenuStyle.font(14, .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .modifier(TavernLeatherCard())
            .accessibilityIdentifier(identifier)
    }
}

/// A glowing green dot with a slow ring pulsing out of it: this player is online now.
struct LeaderboardOnlineDot: View {
    static let color = Color(red: 0.45, green: 0.92, blue: 0.45)
    var size: CGFloat = 8
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Self.color.opacity(0.5))
                .scaleEffect(pulse ? 2.4 : 1)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(RadialGradient(colors: [.white, Self.color], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(color: Self.color, radius: 3)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A band of gold light that sweeps across Mythic rows every few seconds.
private struct MythicShimmer: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 10
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, ArenaMenuStyle.gold.opacity(0.22), .white.opacity(0.22), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.4)
                            .offset(x: sweep ? geo.size.width * 1.1 : -geo.size.width * 0.5)
                            .blendMode(.screen)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).delay(0.6).repeatForever(autoreverses: false)) { sweep = true }
                }
        } else {
            content
        }
    }
}
