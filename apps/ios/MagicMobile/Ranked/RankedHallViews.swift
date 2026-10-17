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

    private var tier: RankTier { rank.position.tier }

    var body: some View {
        TavernLobbyPage(title: String(localized: "Ranked Hall"), backTitle: String(localized: "Play"), back: back) {
            rankCard.modifier(HallEntrance(shown: shown, delay: 0))
            playChoice.modifier(HallEntrance(shown: shown, delay: 0.08))
            leaderboardChoice.modifier(HallEntrance(shown: shown, delay: 0.16))
            seasonStrip.modifier(HallEntrance(shown: shown, delay: 0.24))
        }
        .onAppear { shown = true }
        .task { teaser = await account.rankedLeaderboard(.everyone, limit: 3) }
    }

    private var rankCard: some View {
        VStack(spacing: 10) {
            ZStack {
                RankGlow(tier: tier, size: 190)
                RankBadge(position: rank.position, size: 132, showsPips: true, showsTitle: true,
                          spin: .init(start: appeared, turns: 1, duration: 1.2))
            }
            .padding(.top, 4)
            Text(String(localized: "Season: \(RankLadder.seasonName(rank.season))") + RankedHallView.daysLeft(rank.season))
                .font(.system(size: 13, weight: .semibold, design: .serif)).opacity(0.8)
            HStack(spacing: 18) {
                stat(String(localized: "Wins"), "\(rank.wins)")
                stat(String(localized: "Losses"), "\(rank.losses)")
                stat(String(localized: "Peak"), rank.peak.title)
                if let teaser, let me = teaser.me { stat(String(localized: "Place"), "#\(me.position)") }
            }
            Button(action: profile) { Label(String(localized: "Your profile"), systemImage: "person.crop.circle") }
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                .accessibilityIdentifier("ranked.hall.profile")
        }
        .frame(maxWidth: .infinity)
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ranked.hall.standing")
    }

    private var playChoice: some View {
        choice(title: String(localized: "Play Ranked"),
               detail: String(localized: "Pick your deck, then face a player near your rank or an AI. \(tier.name) allows decks up to Bracket \(tier.maxDeckBracket)."),
               identifier: "ranked.hall.play", sound: .menuPlay, action: play) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 26, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
        } footer: { EmptyView() }
    }

    private var leaderboardChoice: some View {
        choice(title: String(localized: "Leaderboard"),
               detail: String(localized: "This season's top players, live, with who's online now."),
               identifier: "ranked.hall.leaderboard", sound: .uiOpen, action: leaderboard) {
            Image(systemName: "trophy.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
        } footer: {
            if let teaser, !teaser.entries.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: -10) {
                        ForEach(teaser.entries) { RankEmblem(tier: $0.rank.tier, size: 30) }
                    }
                    if teaser.online > 0 {
                        LeaderboardOnlineDot(size: 8)
                        Text(teaser.online == 1 ? String(localized: "1 online now") : String(localized: "\(teaser.online) online now"))
                            .font(.system(size: 12, weight: .bold, design: .serif))
                    }
                    Text(String(localized: "\(teaser.total) ranked")).font(.system(size: 12, design: .serif)).opacity(0.7)
                }
            }
        }
    }

    private var seasonStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "PAST SEASONS")).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
                .foregroundStyle(BrandTheme.brassGradient)
            if rank.history.isEmpty {
                Text(String(localized: "This is your first season. Where you finish it starts your history here."))
                    .font(.system(size: 14, design: .serif)).opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(rank.history.prefix(6), id: \.season) { seasonChip($0) }
                    }
                }
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ranked.hall.seasons")
    }

    private func seasonChip(_ record: SeasonRecord) -> some View {
        VStack(spacing: 4) {
            RankEmblem(tier: record.final.tier, size: 44)
            Text(record.final.title).font(.system(size: 12, weight: .black, design: .serif)).lineLimit(1)
            Text(RankLadder.seasonName(record.season)).font(.system(size: 10, weight: .semibold, design: .serif)).opacity(0.75)
            Text("\(record.wins)–\(record.losses)").font(.system(size: 11, weight: .bold, design: .serif)).monospacedDigit().opacity(0.85)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 92)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TavernPalette.brass.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func choice<Icon: View, Footer: View>(title: String, detail: String, identifier: String, sound: GameSound,
                                                  action: @escaping () -> Void, @ViewBuilder icon: () -> Icon,
                                                  @ViewBuilder footer: () -> Footer) -> some View {
        Button {
            GameAudio.shared.play(sound)
            action()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                icon()
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(TavernPalette.leather.opacity(0.9)).overlay(Circle().strokeBorder(TavernPalette.brass, lineWidth: 2)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 21, weight: .black, design: .serif))
                    Text(detail).font(.system(size: 14, weight: .medium, design: .serif)).opacity(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                    footer()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(DeckStudioPalette.accent)
            }
            .multilineTextAlignment(.leading)
            .modifier(TavernParchmentCard())
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black, design: .serif)).monospacedDigit()
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1.2).opacity(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    static func daysLeft(_ season: String) -> String {
        guard let end = RankLadder.seasonEnd(season) else { return "" }
        let days = max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
        return days == 1 ? String(localized: " · 1 day left") : String(localized: " · \(days) days left")
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

    @State private var scope: RankedLeaderboard.Scope = .everyone
    @State private var load: Load = .loading
    @State private var lastPositions: [String: Int] = [:]
    /// Places gained (positive) or lost since the last refresh.
    @State private var moves: [String: Int] = [:]
    @State private var podiumUp = false
    @State private var active = true
    @State private var profile: ProfileTarget?
    @Namespace private var scopeSlider
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            TavernLobbyPage(title: String(localized: "Leaderboard"), backTitle: String(localized: "Ranked Hall"), back: back) {
                scopePicker
                switch load {
                case .loading:
                    SocialWaiting(text: String(localized: "Gathering the standings…")).modifier(TavernLeatherCard())
                case .offline:
                    note(String(localized: "The leaderboard needs your profile and a connection. Sign in from your profile, then come back."),
                         icon: "wifi.exclamationmark", identifier: "leaderboard.offline")
                case .loaded(let board):
                    liveStrip(board)
                    if board.entries.isEmpty {
                        note(scope == .friends
                             ? String(localized: "None of your friends has played ranked this season yet. Challenge one from Friends.")
                             : String(localized: "Nobody has played ranked this season yet. Win a game to take the top spot."),
                             icon: "trophy", identifier: "leaderboard.empty")
                    } else {
                        podium(Array(board.entries.prefix(3)))
                        rows(Array(board.entries.dropFirst(3)))
                    }
                    if board.pinnedMe != nil { Color.clear.frame(height: 72) }
                }
            }
            if case .loaded(let board) = load, let me = board.pinnedMe {
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

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(RankedLeaderboard.Scope.allCases, id: \.self) { option in
                let selected = scope == option
                Button {
                    guard !selected else { return }
                    GameAudio.shared.play(.uiTap)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { scope = option }
                } label: {
                    Text(option == .everyone ? String(localized: "Everyone") : String(localized: "Friends"))
                        .font(.system(size: 15, weight: .heavy, design: .serif))
                        .foregroundStyle(selected ? Color(red: 0.25, green: 0.12, blue: 0.04) : TavernPalette.parchment.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                Capsule().fill(BrandTheme.brassGradient)
                                    .matchedGeometryEffect(id: "scope", in: scopeSlider)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("leaderboard.scope.\(option.rawValue)")
            }
        }
        .padding(4)
        .background(TavernFill(material: .leather).clipShape(Capsule()))
        .overlay(TavernCapsuleRim(thin: true))
    }

    // MARK: Live strip

    private func liveStrip(_ board: RankedLeaderboard) -> some View {
        HStack(spacing: 10) {
            LeaderboardOnlineDot(size: 10)
            Text(board.online == 1 ? String(localized: "1 player online") : String(localized: "\(board.online) players online"))
                .font(.system(size: 14, weight: .bold, design: .serif))
            Spacer(minLength: 6)
            Text(String(localized: "\(board.total) ranked · \(RankLadder.seasonName(board.season))"))
                .font(.system(size: 12, weight: .semibold, design: .serif)).opacity(0.75)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(TavernFill(material: .leather).clipShape(Capsule()))
        .overlay(TavernCapsuleRim(thin: true))
        .foregroundStyle(TavernPalette.parchment)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("leaderboard.live")
    }

    // MARK: Podium

    private func podium(_ top: [RankedLeaderboard.Entry]) -> some View {
        let order = top.count == 3 ? [top[1], top[0], top[2]] : (top.count == 2 ? [top[1], top[0]] : top)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(order) { podiumStep($0) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .onAppear { podiumUp = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leaderboard.podium")
    }

    private func podiumStep(_ entry: RankedLeaderboard.Entry) -> some View {
        let place = entry.position
        let height: CGFloat = place == 1 ? 112 : (place == 2 ? 84 : 66)
        let mythic = entry.rank.tier == .mythic
        return Button { open(entry) } label: {
            VStack(spacing: 6) {
                if place == 1 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .shadow(color: TavernPalette.ember.opacity(0.7), radius: 6)
                }
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        if place == 1 { RankGlow(tier: entry.rank.tier, size: 110) }
                        RankEmblem(tier: entry.rank.tier, size: place == 1 ? 74 : 58)
                    }
                    if entry.online { LeaderboardOnlineDot(size: 12).padding(4) }
                }
                Text(entry.username)
                    .font(.system(size: place == 1 ? 15 : 13, weight: .black, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(entry.title ?? entry.rank.title)
                    .font(.system(size: 11, design: .serif)).italic().opacity(0.8)
                    .lineLimit(1).minimumScaleFactor(0.7)
                ZStack(alignment: .top) {
                    TavernFill(material: .leather)
                        .overlay(LinearGradient(colors: [entry.rank.tier.tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    Text("\(place)")
                        .font(.system(size: place == 1 ? 34 : 26, weight: .black, design: .serif))
                        .foregroundStyle(BrandTheme.brassGradient)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .padding(.top, 8)
                }
                .frame(height: podiumUp || reduceMotion ? height : 14)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                    .stroke(entry.you ? TavernPalette.brass : TavernPalette.brass.opacity(0.6), lineWidth: entry.you ? 2.5 : 1.5))
                .modifier(MythicShimmer(active: mythic, cornerRadius: 10))
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.72).delay(place == 1 ? 0.3 : (place == 2 ? 0.15 : 0)),
                           value: podiumUp)
            }
            .foregroundStyle(TavernPalette.parchment)
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

    private func rows(_ entries: [RankedLeaderboard.Entry]) -> some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                row(entry, pinned: false)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
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
                ZStack(alignment: .bottomTrailing) {
                    RankEmblem(tier: rank.tier, size: 40)
                    if entry.online { LeaderboardOnlineDot(size: 9) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.username).font(.system(size: 16, weight: .black, design: .serif)).lineLimit(1)
                        if entry.you { TavernTag(text: String(localized: "YOU"), leather: true) }
                    }
                    Text(entry.title.map { "\(rank.title) · \($0)" } ?? rank.title)
                        .font(.system(size: 12, design: .serif)).opacity(0.75).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    if let move = moves[entry.username] { moveMark(move) }
                    Text("\(entry.wins)–\(entry.losses)")
                        .font(.system(size: 13, weight: .bold, design: .serif)).monospacedDigit().opacity(0.85)
                    if !mythic { RankPips(filled: rank.pips, tier: rank.tier, size: 7) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                TavernFill(material: .leather)
                    .overlay(LinearGradient(colors: [rank.tier.tint.opacity(entry.you ? 0.22 : 0.08), .clear], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(entry.you ? TavernPalette.brass : TavernPalette.brass.opacity(0.4), lineWidth: entry.you ? 2 : 1)
            }
            .modifier(MythicShimmer(active: mythic, cornerRadius: 10))
            .shadow(color: mythic ? RankTier.mythic.tint.opacity(0.35) : .black.opacity(pinned ? 0.6 : 0.35), radius: pinned ? 10 : 5, y: 3)
            .foregroundStyle(TavernPalette.parchment)
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
            Text("\(abs(move))").font(.system(size: 11, weight: .heavy, design: .serif)).monospacedDigit()
        }
        .foregroundStyle(move > 0 ? Color(red: 0.5, green: 0.9, blue: 0.45) : Color(red: 1, green: 0.55, blue: 0.45))
        .transition(.scale.combined(with: .opacity))
    }

    private func accessibilityText(_ entry: RankedLeaderboard.Entry) -> String {
        var parts = [String(localized: "Number \(entry.position)"), entry.username, entry.rank.title]
        if let title = entry.title { parts.append(title) }
        if entry.online { parts.append(String(localized: "online")) }
        parts.append(String(localized: "\(entry.wins) wins, \(entry.losses) losses"))
        if entry.you { parts.append(String(localized: "you")) }
        return parts.joined(separator: ", ")
    }

    private func note(_ text: String, icon: String, identifier: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 14, weight: .semibold, design: .serif))
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

/// A band of ember light that sweeps across Mythic rows every few seconds.
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
                        LinearGradient(colors: [.clear, RankTier.mythic.tint.opacity(0.35), .white.opacity(0.28), .clear],
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
