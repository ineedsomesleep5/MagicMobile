#if DEBUG
import Foundation

/// Development fixtures for the profile and the friends screens, so they can be looked at (and UI tested)
/// without the network or an account. Never compiled into a release build.
///
///   MAGICMOBILE_UI_TEST_SOCIAL=1      a rich game history for the own profile, and a fixture account:
///                                     friends, searchable players and public profiles instead of the server
///   MAGICMOBILE_UI_TEST_OPEN=profile|friends|public:<name>|search:<text>   opens that screen at launch
///   --deck-history-layout-ui-test     eighteen development games with detailed records (see ProfileHistoryFixture)
enum SocialFixtures {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var isActive: Bool { environment["MAGICMOBILE_UI_TEST_SOCIAL"] != nil }
    static var openScreen: String? { isActive ? environment["MAGICMOBILE_UI_TEST_OPEN"] : nil }

    struct Deck {
        let id: String, name: String, commander: String, colors: [String], bracket: Int
    }

    static let decks = [
        Deck(id: "local:goblins", name: "Goblin Warren", commander: "Krenko, Mob Boss", colors: ["R"], bracket: 3),
        Deck(id: "local:vampires", name: "Blood Court", commander: "Edgar Markov", colors: ["W", "B", "R"], bracket: 3),
        Deck(id: "local:atraxa", name: "Proliferate", commander: "Atraxa, Praetors' Voice", colors: ["W", "U", "B", "G"], bracket: 4),
        Deck(id: "local:ninjas", name: "Shadow Ninjas", commander: "Yuriko, the Tiger's Shadow", colors: ["U", "B"], bracket: 2),
        Deck(id: "local:elves", name: "Elven Chorus", commander: "Lathril, Blade of the Elves", colors: ["B", "G"], bracket: 2),
    ]

    static let foes: [(name: String, commander: String)] = [
        ("Ayula's Moot", "Ayula, Queen Among Bears"), ("Tavern Brawlers", "Grand Arbiter Augustin IV"),
        ("Graveyard Shift", "Meren of Clan Nel Toth"), ("Storm Front", "Niv-Mizzet, Parun"),
        ("Dragon Hoard", "The Ur-Dragon"), ("Elfball", "Marwyn, the Nurturer"),
    ]

    /// Oldest first: wins, losses and a draw, finishing on a four-game streak with a best run of six.
    private static let results = Array("WWLWLWWWLWWLLWWWWWWLWLWWDWLWWLWWWWWW")

    /// Thirty-six games over seven weeks, newest first; the ranked ones climb from Silver. Also returns the
    /// rank the games leave behind.
    static func matches(now: Date, season: String) -> (matches: [MatchRecord], rank: RankState) {
        var state = RankState.fresh(season: season)
        state.position = RankPosition(tier: .silver, division: 2, pips: 1)
        state.peak = state.position
        var made: [MatchRecord] = []
        for (index, letter) in results.enumerated() {
            let deck = decks[(index * index + index / 3) % decks.count]
            let foe = foes[(index * 5 + 1) % foes.count]
            let outcome: RankOutcome = letter == "W" ? .win : (letter == "L" ? .loss : .draw)
            let ranked = index % 2 == 0
            var change: RankChange?
            if ranked {
                let result = RankLadder.apply(outcome, to: state, deckBracket: deck.bracket)
                state = result.state
                change = result.change
            }
            let date = now.addingTimeInterval(-Double(results.count - 1 - index) * 1.35 * 86_400 - 3_600 * Double(index % 5))
            made.append(MatchRecord(date: date, mode: ranked ? .ranked : (index % 7 == 1 ? .casual : .quick),
                                    opponents: [.init(name: foe.name, commander: foe.commander, isAI: true)],
                                    opponentBracket: foe.name.count % 3 + 2, aiSkill: 3, deckID: deck.id, deckName: deck.name,
                                    commander: deck.commander, colors: deck.colors, deckBracket: deck.bracket, outcome: outcome,
                                    turns: 6 + (index * 3) % 8, rankChange: change, season: ranked ? season : nil))
        }
        state.history = [
            SeasonRecord(season: "2026-09", final: RankPosition(tier: .bronze, division: 1, pips: 2),
                         peak: RankPosition(tier: .silver, division: 4, pips: 0), wins: 11, losses: 9),
            SeasonRecord(season: "2026-08", final: RankPosition(tier: .bronze, division: 3, pips: 0),
                         peak: RankPosition(tier: .bronze, division: 2, pips: 2), wins: 6, losses: 8),
        ]
        return (made.reversed(), state)
    }
}

// MARK: The fixture account: friends, searchable players and public profiles instead of the server

extension SocialFixtures {
    static let ownName = "CalebM"

    struct Player {
        let name: String
        let visibility: ProfileVisibility
        let commander: String
        let step: Int
        let pips: Int
        let title: String?
        let online: Bool
        var hosting: (code: String, seats: Int)?
    }

    static let players: [Player] = [
        Player(name: "Aria_Blade", visibility: .public, commander: "Atraxa, Praetors' Voice", step: 13, pips: 2, title: "Gold Champion", online: true, hosting: ("K7M2QX", 2)),
        Player(name: "DarkMoonDan", visibility: .public, commander: "Yuriko, the Tiger's Shadow", step: 9, pips: 1, title: nil, online: false),
        Player(name: "ManaFiend", visibility: .public, commander: "Krenko, Mob Boss", step: 17, pips: 3, title: "Platinum Warden", online: true),
        Player(name: "DannyDraws", visibility: .public, commander: "Edgar Markov", step: 6, pips: 0, title: nil, online: true),
        Player(name: "DaisyDuel", visibility: .public, commander: "Lathril, Blade of the Elves", step: 11, pips: 1, title: "Contender", online: false),
        Player(name: "DarthMulligan", visibility: .public, commander: "The Ur-Dragon", step: 14, pips: 0, title: "Unstoppable", online: false),
        Player(name: "DaCommander", visibility: .public, commander: "Meren of Clan Nel Toth", step: 3, pips: 2, title: nil, online: false),
        Player(name: "Dahlia_Rose", visibility: .public, commander: "Ayula, Queen Among Bears", step: 20, pips: 7, title: "Mythic Legend", online: false),
        Player(name: "Dagger99", visibility: .friends, commander: "Niv-Mizzet, Parun", step: 8, pips: 3, title: nil, online: false),
        Player(name: "DaPrivate", visibility: .private, commander: "Marwyn, the Nurturer", step: 7, pips: 0, title: nil, online: false),
        Player(name: "Zephyr_K", visibility: .public, commander: "Ghave, Guru of Spores", step: 5, pips: 1, title: nil, online: false),
    ]

    /// The friends list the fixture account starts with.
    static func startingFriends(now: Date = Date()) -> [PlayerFriend] {
        func row(_ name: String, _ relation: String, hoursAgo: Double? = nil) -> PlayerFriend {
            let player = players.first { $0.name == name }
            return PlayerFriend(id: UUID(), username: name, relation: relation, online: relation == "friend" && player?.online == true,
                                lastSeenAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) }, platform: name == "Aria_Blade" ? "android" : "ios",
                                hostingCode: relation == "friend" ? player?.hosting?.code : nil,
                                hostingOpenSeats: relation == "friend" ? player?.hosting?.seats : nil)
        }
        return [row("Aria_Blade", "friend"), row("ManaFiend", "friend"), row("DarkMoonDan", "friend", hoursAgo: 2),
                row("DannyDraws", "incoming"), row("DaisyDuel", "outgoing")]
    }

    static func rank(_ name: String) -> RankPosition? {
        players.first { $0.name == name }.map { .published(step: $0.step, pips: $0.pips) }
    }

    /// mm_search_players on the fixture: a name's start, case-insensitive; never private profiles; the exact name first,
    /// then friends, then alphabetical; twelve at most.
    static func search(_ prefix: String, friends: [PlayerFriend]) -> [PlayerSearchResult] {
        let wanted = prefix.lowercased()
        let season = RankLadder.season(for: Date())
        let hits = players.filter { $0.name.lowercased().hasPrefix(wanted) && $0.visibility != .private }
        let sorted = hits.sorted { lhs, rhs in
            let l = (lhs.name.lowercased() == wanted, friends.contains { $0.username == lhs.name && $0.isFriend }, lhs.name.lowercased())
            let r = (rhs.name.lowercased() == wanted, friends.contains { $0.username == rhs.name && $0.isFriend }, rhs.name.lowercased())
            if l.0 != r.0 { return l.0 }
            if l.1 != r.1 { return l.1 }
            return l.2 < r.2
        }
        return sorted.prefix(12).map { player in
            let relation = friends.first { $0.username == player.name }?.relation ?? "none"
            let visible = player.visibility == .public || relation == "friend"
            return PlayerSearchResult(username: player.name, favoriteCommander: visible ? player.commander : nil, season: visible ? season : nil,
                                      rankStep: visible ? player.step : nil, pips: visible ? player.pips : nil, visibility: player.visibility,
                                      relation: relation == "friend" || relation == "incoming" ? relation : (relation == "outgoing" ? "outgoing" : "none"),
                                      online: relation == "friend" ? player.online : nil)
        }
    }

    /// mm_public_profile on the fixture.
    static func publicProfile(_ name: String, friends: [PlayerFriend], own: String?) -> PublicProfileResult {
        if name.lowercased() == (own ?? ownName).lowercased() {
            return .profile(profile(for: Player(name: own ?? ownName, visibility: .public, commander: "Krenko, Mob Boss", step: 9, pips: 1, title: "Rising Star", online: true),
                                    relation: "self"))
        }
        guard let player = players.first(where: { $0.name.lowercased() == name.lowercased() }) else { return .notFound }
        let relation = friends.first { $0.username == player.name }?.relation ?? "none"
        let allowed = player.visibility == .public || (player.visibility == .friends && relation == "friend")
        if !allowed {
            return .profile(PublicProfile(username: player.name, restricted: true, visibility: player.visibility, relation: relation, online: nil, title: nil,
                                          favoriteCommander: nil, rank: nil, summary: ProfileSummary(), games: []))
        }
        return .profile(profile(for: player, relation: relation))
    }

    private static func profile(for player: Player, relation: String) -> PublicProfile {
        var seed = UInt64(player.name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 })
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let now = Date()
        let mine = decks
        let humans = players.map(\.name).filter { $0 != player.name }
        var games: [ProfileGame] = []
        var points: [ProfileSummary.RankPoint] = []
        var standing = max(0, player.step * 4 + player.pips - 10)
        let count = 22 + next(8)
        for index in 0..<count {
            let deck = mine[(index + next(3)) % mine.count]
            let won = next(100) < 45 + player.step * 2
            let ranked = index % 2 == 0
            let withHuman = next(3) == 0
            let foe = withHuman ? (name: humans[next(humans.count)], commander: foes[next(foes.count)].commander, ai: false)
                                : (name: foes[next(foes.count)].name, commander: foes[next(foes.count)].commander, ai: true)
            let date = now.addingTimeInterval(-Double(count - 1 - index) * 1.6 * 86_400 - Double(next(40_000)))
            if ranked { standing = max(0, standing + (won ? 1 : -1)); points.append(.init(date: date, points: standing)) }
            games.append(ProfileGame(id: "\(player.name)-\(index)", date: date, mode: ranked ? .ranked : (index % 5 == 1 ? .casual : .quick),
                                     outcome: won ? .win : .loss, deckName: deck.name, commanders: [deck.commander], colors: deck.colors,
                                     opponents: [.init(name: foe.name, commander: foe.commander, isAI: foe.ai, hidden: foe.name == "Dagger99" && index % 3 == 0 && !foe.ai)],
                                     turns: 5 + next(9)))
        }
        games.reverse()
        let season = RankLadder.season(for: now)
        let summary = ProfileSummary(games: games, now: now, rankPoints: Array(points.suffix(60)))
        return PublicProfile(username: player.name, restricted: false, visibility: player.visibility, relation: relation,
                             online: relation == "friend" ? player.online : nil, title: player.title, favoriteCommander: player.commander,
                             rank: .init(season: season, step: player.step, pips: player.pips, peakStep: min(20, player.step + 1),
                                         wins: summary.wins / 2, losses: summary.losses / 2),
                             summary: summary, games: Array(games.prefix(30)))
    }
}

/// `--deck-history-layout-ui-test`: the profile's recent games are the eighteen development games of
/// Deck Studio's history fixture (DeckStudioPlaytestInsightsView.fixtureGames, with their detailed records),
/// so the match dashboard can be opened from the profile. The ids, dates and results mirror that fixture.
enum ProfileHistoryFixture {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--deck-history-layout-ui-test")
            && ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_PREFERENCES"] != nil
    }

    static func matches() -> [MatchRecord] {
        (0..<18).map { index in
            let identifier = "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))"
            return MatchRecord(id: UUID(uuidString: identifier)!, date: Date(timeIntervalSince1970: 1_780_000_000 - Double(index * 86_400)),
                               mode: .quick, opponents: [.init(name: "Fixture rival", commander: "Aurelia, the Warleader", isAI: true)],
                               opponentBracket: 2, aiSkill: 3, deckID: "precon:token-triumph", deckName: "Token Triumph",
                               commander: "Isamaru, Hound of Konda", colors: ["W"], deckBracket: 2,
                               outcome: index.isMultiple(of: 2) ? .win : .loss, turns: 8, rankChange: nil, season: nil,
                               engineMatchID: identifier)
        }
    }
}
#endif
