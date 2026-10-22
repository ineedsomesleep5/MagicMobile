import SwiftUI

/// The Play panel's three ways to play from Find Match.
enum ArenaPlayMode: String, CaseIterable, Identifiable {
    case quick, ranked, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return String(localized: "Quick")
        case .ranked: return String(localized: "Ranked")
        case .custom: return String(localized: "Custom")
        }
    }

    static let storageKey = "magicmobile.play.mode"
}

/// The tabs along the top of the Play panel.
enum ArenaPlayTab: String, CaseIterable, Identifiable {
    case find, friends, recent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .find: return String(localized: "Find Match")
        case .friends: return String(localized: "Friends")
        case .recent: return String(localized: "Recently Played")
        }
    }

    var symbol: String {
        switch self {
        case .find: return "shield.lefthalf.filled"
        case .friends: return "person.2.fill"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

/// A shelf of deck boxes in the picker.
struct ArenaDeckSection: Identifiable {
    let id: String
    let title: String
    let decks: [ArenaDeckBoxModel]
    /// The shelf starts with a "New deck" box.
    var offersNewDeck = false
}

/// A game from the profile's history, offered again from Recently Played.
struct ArenaRecentGame: Identifiable {
    let id: String
    let mode: PlayMode
    let deckID: String
    let deckName: String
    let commander: String?
    let colors: [String]
    let detail: String
    let won: Bool?

    var modeTitle: String {
        switch mode {
        case .quick: return String(localized: "Quick Match")
        case .ranked: return String(localized: "Ranked")
        case .casual: return String(localized: "Custom Table")
        }
    }
}

/// Everything the Play panel shows and does. The root view owns the state; the panel only draws it.
struct ArenaPlayPanelModel {
    var sections: [ArenaDeckSection]
    var selectedDeckID: Binding<String>
    var deckName: String?
    var deckBracket: CommanderBracket?
    var mode: Binding<ArenaPlayMode>
    var tab: Binding<ArenaPlayTab>
    // Quick Match
    var quickBracket: Binding<Int>
    var quickDeckID: Binding<String>
    var quickSkill: Binding<Int>
    var startingPlayer: Binding<String>
    // Ranked
    var rank: RankState
    var canSearchPeople: Bool
    var search: RankedMatchmaker.Phase?
    // A friend's challenge on its way
    var waitingFor: String?
    // Custom
    var playerMode: Binding<String>
    var mayStart: Bool
    var status: String?
    var recent: [ArenaRecentGame]
    let close: () -> Void
    let newDeck: () -> Void
    let explainBracket: () -> Void
    let startQuick: () -> Void
    let findRanked: () -> Void
    let cancelSearch: () -> Void
    let playAINow: () -> Void
    let cancelChallenge: () -> Void
    let openCustom: () -> Void
    let rankedHall: () -> Void
    let leaderboard: () -> Void
    let challengeFriend: () -> Void
    let hostOnline: () -> Void
    let joinOnline: () -> Void
    let gameCenter: () -> Void
    let chooseRecent: (ArenaRecentGame) -> Void

    /// The opponents' bracket Quick Match resolves to (0 is "match my deck").
    var quickResolvedBracket: Int {
        quickBracket.wrappedValue == 0 ? min(4, deckBracket?.rawValue ?? 2) : quickBracket.wrappedValue
    }

    /// Ranked allows the deck at this tier.
    var rankedEligible: Bool { (deckBracket?.rawValue ?? 99) <= rank.position.tier.maxDeckBracket }

    var busy: Bool { search != nil || waitingFor != nil }

    /// The chosen deck's box.
    var selectedDeck: ArenaDeckBoxModel? {
        sections.lazy.flatMap(\.decks).first { $0.id == selectedDeckID.wrappedValue }
    }
}

/// Arena's Play panel (Caleb, 2026-10-22): the room darkened, your decks as boxes on the left, and on the right the
/// blade, lit along its seam, with the tabs, the ways to play, their options and the Play plaque. In portrait the
/// blade is a sheet along the bottom. A search waits inside the blade: Play turns into Cancel under a timer.
struct ArenaPlayPanel: View {
    let model: ArenaPlayPanelModel
    let compact: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if compact {
                VStack(spacing: 0) {
                    ArenaDeckPicker(model: model, compact: true)
                    ArenaPlayBlade(model: model, compact: true)
                        .frame(height: 372)
                }
            } else {
                HStack(spacing: 0) {
                    ArenaDeckPicker(model: model, compact: false)
                    ArenaPlayBlade(model: model, compact: false)
                        .frame(width: 248)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("play.panel")
    }
}

// MARK: - Deck picker

/// The left of the panel: the way to play in a few words, and every deck as a box, by shelf.
struct ArenaDeckPicker: View {
    let model: ArenaPlayPanelModel
    let compact: Bool
    @State private var collapsed: Set<String> = []

    private var heading: (title: String, detail: String) {
        switch model.tab.wrappedValue {
        case .friends:
            return (String(localized: "Play with Friends"), String(localized: "Pick your deck, then challenge a friend or share a table code. iPhone and Android play together."))
        case .recent:
            return (String(localized: "Recently Played"), model.recent.isEmpty ? String(localized: "Your last tables show up here once you've played.")
                                                                                : String(localized: "Pick a game to set it up again."))
        case .find:
            switch model.mode.wrappedValue {
            case .quick: return (String(localized: "Quick Match"), String(localized: "One AI opponent at your deck's bracket. No rank change."))
            case .ranked: return (String(localized: "Ranked"), String(localized: "One opponent near your rank. Wins fill pips, losses take them."))
            case .custom: return (String(localized: "Custom Table"), String(localized: "Up to three AI opponents, Game Center, or an online table."))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.tab.wrappedValue == .recent {
                ArenaRecentShelf(model: model, compact: compact)
            } else {
                deckShelves
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("play.decks")
    }

    private var deckShelves: some View {
            GeometryReader { proxy in
                let gap: CGFloat = compact ? 10 : 12
                let usable = proxy.size.width - (compact ? 32 : 48)
                let columns = max(2, Int((usable + gap) / ((compact ? 118 : 112) + gap)))
                let boxWidth = floor((usable - gap * CGFloat(columns - 1)) / CGFloat(columns))
                ScrollViewReader { reader in
                    ScrollView {
                        // The shelves themselves are not lazy, so the chosen deck's shelf can be scrolled to before it shows.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.sections) { section in
                                ArenaSectionHeader(title: section.title, count: section.decks.count,
                                                   collapsed: Binding(get: { collapsed.contains(section.id) },
                                                                      set: { if $0 { collapsed.insert(section.id) } else { collapsed.remove(section.id) } }))
                                    .id("shelf-\(section.id)")
                                if !collapsed.contains(section.id) {
                                    // Rows leave room for an open box's lid to rise.
                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(boxWidth), spacing: gap, alignment: .top), count: columns),
                                              alignment: .leading, spacing: ArenaBoxGeometry(width: boxWidth).rise + 8) {
                                        if section.offersNewDeck {
                                            Button(action: model.newDeck) { ArenaNewDeckBox(width: boxWidth) }
                                                .buttonStyle(BrandPressStyle())
                                                .accessibilityIdentifier("play.newDeck")
                                        }
                                        ForEach(section.decks) { deck in
                                            deckButton(deck, width: boxWidth)
                                        }
                                    }
                                    .padding(.top, ArenaBoxGeometry(width: boxWidth).rise + 12)
                                    .padding(.bottom, 10)
                                }
                            }
                        }
                        .padding(.horizontal, compact ? 16 : 24)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                    .opacity(model.busy ? 0.4 : 1)
                    .task {
                        // Once the shelves are laid out, bring the chosen deck into view, a little above the middle.
                        try? await Task.sleep(for: .milliseconds(250))
                        if let shelf = shelf(of: model.selectedDeckID.wrappedValue) { reader.scrollTo(shelf, anchor: .top) }
                    }
                    // A deck chosen elsewhere (Recently Played) comes into view; one already showing stays put.
                    .onChange(of: model.selectedDeckID.wrappedValue) { _, id in
                        withAnimation(.easeOut(duration: 0.3)) { reader.scrollTo(id) }
                    }
                }
            }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading.title).font(ArenaMenuStyle.font(compact ? 22 : 24, .bold)).foregroundStyle(ArenaMenuStyle.text)
                    .shadow(color: .black, radius: 2)
                    .accessibilityAddTraits(.isHeader)
                Text(heading.detail).font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                let rules = ArenaCaps(text: String(localized: "100 cards · up to 4 players"), size: 9.5)
                if compact { rules }
                HStack(spacing: 8) {
                    if !compact { rules }
                    if let bracket = model.deckBracket {
                        Button(action: model.explainBracket) {
                            HStack(spacing: 4) {
                                Text(bracket.title).font(ArenaMenuStyle.font(10.5, .bold)).foregroundStyle(ArenaMenuStyle.text)
                                Image(systemName: "info.circle").font(.system(size: 10, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold)
                            }
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(BrandPressStyle())
                        .accessibilityLabel(String(localized: "\(bracket.title). Bracket details"))
                        .accessibilityIdentifier("play.deck.bracket")
                    }
                }
            }
            Spacer(minLength: 8)
            ArenaCloseButton(identifier: "lobby.back", action: model.close)
                .disabled(model.busy)
        }
        .padding(.leading, compact ? 16 : 24)
        .padding(.trailing, compact ? 8 : 12)
        .padding(.top, compact ? 10 : 12)
        .padding(.bottom, 4)
    }

    /// The shelf a deck sits on, as its heading's scroll id.
    private func shelf(of deckID: String) -> String? {
        model.sections.first { $0.decks.contains { $0.id == deckID } }.map { "shelf-\($0.id)" }
    }

    private func deckButton(_ deck: ArenaDeckBoxModel, width: CGFloat) -> some View {
        let selected = deck.id == model.selectedDeckID.wrappedValue
        return Button {
            GameAudio.shared.play(.uiTap)
            model.selectedDeckID.wrappedValue = deck.id
        } label: {
            ArenaDeckBox(deck: deck, selected: selected, width: width)
        }
        .buttonStyle(BrandPressStyle())
        .disabled(model.busy)
        .id(deck.id)
        .accessibilityIdentifier("play.deck.\(deck.id)")
    }
}

// MARK: - Recently played

/// Recently Played's left side, as Arena's: a tall tile for each recent table (its deck's art and box, the way you
/// played, whom you met), or an empty tile that points to Find Match.
struct ArenaRecentShelf: View {
    let model: ArenaPlayPanelModel
    let compact: Bool

    var body: some View {
        ScrollView(compact ? .horizontal : .vertical) {
            let layout = compact ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                                 : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            Group {
                if model.recent.isEmpty {
                    empty
                } else if compact {
                    layout { ForEach(model.recent) { tile($0) } }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 14) {
                        ForEach(model.recent) { tile($0) }
                    }
                }
            }
            .padding(.horizontal, compact ? 16 : 24)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private func isChosen(_ game: ArenaRecentGame) -> Bool {
        guard game.deckID == model.selectedDeckID.wrappedValue else { return false }
        switch game.mode {
        case .quick: return model.mode.wrappedValue == .quick
        case .ranked: return model.mode.wrappedValue == .ranked
        case .casual: return model.mode.wrappedValue == .custom
        }
    }

    private func tile(_ game: ArenaRecentGame) -> some View {
        let chosen = isChosen(game)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            GameAudio.shared.play(.uiTap)
            model.chooseRecent(game)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ArenaArt(name: game.commander ?? "", colors: game.colors)
                    .frame(height: 120)
                    .overlay(alignment: .bottomLeading) {
                        ArenaPips(colors: game.colors, size: 14).padding(8)
                    }
                    .clipShape(shape)
                ArenaCaps(text: game.modeTitle, size: 9)
                Text(game.deckName).font(ArenaMenuStyle.font(14, .bold)).foregroundStyle(ArenaMenuStyle.text).lineLimit(1)
                HStack(spacing: 6) {
                    Text(game.detail).font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim).lineLimit(1)
                    Spacer(minLength: 0)
                    if let won = game.won {
                        Text(won ? String(localized: "Won") : String(localized: "Lost"))
                            .font(ArenaMenuStyle.font(11, .bold))
                            .foregroundStyle(won ? ArenaMenuStyle.win : ArenaMenuStyle.loss)
                    }
                }
            }
            .padding(8)
            .frame(width: compact ? 168 : nil)
            .background(shape.fill(Color.black.opacity(0.45)))
            .overlay(shape.strokeBorder(chosen ? AnyShapeStyle(Color(red: 1, green: 0.88, blue: 0.56)) : AnyShapeStyle(ArenaGlass.hairline),
                                        lineWidth: chosen ? 1.6 : 0.8).opacity(chosen ? 1 : 0.6))
            .shadow(color: chosen ? Color(red: 1, green: 0.78, blue: 0.36).opacity(0.5) : .clear, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("recent.\(game.id)")
    }

    /// No games yet: a dashed tile in the gold hairline, and the way to Find Match.
    private var empty: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ArenaMenuStyle.gold.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                VStack(spacing: 8) {
                    ArenaEmblem(symbol: "clock.arrow.circlepath", size: 26)
                    Text(String(localized: "Your last tables show up here"))
                        .font(ArenaMenuStyle.font(14, .semibold)).foregroundStyle(ArenaMenuStyle.text)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
            }
            .frame(width: 190, height: 200)
            Button(String(localized: "Go to Find Match")) { model.tab.wrappedValue = .find }
                .buttonStyle(ArenaPillButtonStyle())
                .accessibilityIdentifier("recent.findMatch")
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    }
}

// MARK: - Blade

/// The right of the panel (the bottom in portrait): tabs, the ways to play, options, and the Play plaque.
struct ArenaPlayBlade: View {
    let model: ArenaPlayPanelModel
    let compact: Bool
    @State private var friendWay: ArenaFriendWay = .challenge

    var body: some View {
        VStack(spacing: 0) {
            tabs
            if model.tab.wrappedValue == .find { modes }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { options }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            // The list fades out over the footer's line rather than running into it.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .accessibilityIdentifier("lobby.scroll")
            footer
        }
        .background { bladeBackground }
        .overlay(alignment: compact ? .top : .leading) { ArenaSeam(vertical: !compact) }
    }

    private var bladeBackground: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: compact ? 18 : 0, topTrailingRadius: compact ? 18 : 0, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color(red: 0.085, green: 0.085, blue: 0.11).opacity(0.98), Color(red: 0.035, green: 0.035, blue: 0.047).opacity(0.99)],
                                 startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: compact ? .bottom : [.bottom, .trailing])
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(ArenaPlayTab.allCases) { tab in
                let on = model.tab.wrappedValue == tab
                Button {
                    GameAudio.shared.play(.uiTap)
                    model.tab.wrappedValue = tab
                } label: {
                    VStack(spacing: 4) {
                        ArenaEmblem(symbol: tab.symbol, size: 18, lit: on)
                        Text(tab.title).font(ArenaMenuStyle.font(10, .semibold))
                            .foregroundStyle(on ? Color.white : ArenaMenuStyle.dim)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 50 : 56)
                    .background(on ? Color.white.opacity(0.05) : .clear)
                    .overlay(alignment: .bottom) {
                        if on {
                            Capsule().fill(Color(red: 0.42, green: 0.70, blue: 1)).frame(height: 3).padding(.horizontal, 14)
                                .shadow(color: Color(red: 0.42, green: 0.70, blue: 1), radius: 5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(BrandPressStyle())
                .disabled(model.busy)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("play.tab.\(tab.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.35) }
        .padding(.top, compact ? 4 : 0)
    }

    private var modes: some View {
        HStack(spacing: 6) {
            ForEach(ArenaPlayMode.allCases) { mode in
                let on = model.mode.wrappedValue == mode
                Button {
                    GameAudio.shared.play(.uiTap)
                    model.mode.wrappedValue = mode
                } label: {
                    VStack(spacing: 4) {
                        ArenaModeGem(mode: mode, rank: model.rank.position, lit: on, size: compact ? 34 : 40)
                        Text(mode.title).font(ArenaMenuStyle.font(11, .semibold))
                            .foregroundStyle(on ? Color.white : ArenaMenuStyle.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.6))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(BrandPressStyle())
                .disabled(model.busy)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("play.\(mode.rawValue)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .opacity(model.busy ? 0.4 : 1)
    }

    // MARK: Options

    @ViewBuilder private var options: some View {
        switch model.tab.wrappedValue {
        case .find:
            switch model.mode.wrappedValue {
            case .quick: quickOptions
            case .ranked: rankedOptions
            case .custom: customOptions
            }
        case .friends: friendsOptions
        case .recent: recentOptions
        }
    }

    @ViewBuilder private var quickOptions: some View {
        ArenaCaps(text: String(localized: "Opponent's bracket"), size: 9.5).padding(.top, 8).padding(.bottom, 2)
        let match = model.deckBracket.map { String(localized: "Match my deck · B\(min(4, $0.rawValue))") } ?? String(localized: "Match my deck")
        ArenaOptionRow(title: match, selected: model.quickBracket.wrappedValue == 0, identifier: "quick.bracket.0") {
            model.quickBracket.wrappedValue = 0
        }
        ForEach(CommanderBracket.allCases.filter { $0 != .cedh }, id: \.rawValue) { bracket in
            ArenaOptionRow(title: bracket.name, value: "B\(bracket.rawValue)", selected: model.quickBracket.wrappedValue == bracket.rawValue,
                           identifier: "quick.bracket.\(bracket.rawValue)") {
                model.quickBracket.wrappedValue = bracket.rawValue
            }
        }
        ArenaCaps(text: String(localized: "Opponent's deck"), size: 9.5).padding(.top, 12).padding(.bottom, 4)
        TavernPicker(title: String(localized: "Opponent deck"), selection: model.quickDeckID, sections: [
            .init(options: [(String(localized: "Surprise me"), "")]),
            .init(title: String(localized: "Bracket \(model.quickResolvedBracket) decks"),
                  options: AIDeckPool.pool(for: model.quickResolvedBracket).map { ("\($0.name) · \($0.commander)", $0.id) }),
        ], identifier: "quick.deck", showsTitle: false)
        ArenaStepper(title: String(localized: "AI skill"), value: model.quickSkill, range: 1...10, identifier: "quick.skill")
            .padding(.top, 4)
        Text(String(localized: "3 is a fair fight. Higher skill thinks longer."))
            .font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim)
        ArenaCaps(text: String(localized: "Who goes first"), size: 9.5).padding(.top, 12).padding(.bottom, 2)
        ArenaSegmented(options: [(String(localized: "Choose"), "choose"), (String(localized: "Roll D20"), "roll")],
                       selection: model.startingPlayer, identifier: "quick.startingPlayer", stretch: true)
    }

    @ViewBuilder private var rankedOptions: some View {
        let rank = model.rank
        HStack(spacing: 12) {
            RankBadge(position: rank.position, size: 48, showsPips: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(rank.position.title).font(ArenaMenuStyle.font(17, .bold)).foregroundStyle(ArenaMenuStyle.text)
                Text(String(localized: "Season: \(RankLadder.seasonName(rank.season))"))
                    .font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim).lineLimit(2)
                Text(String(localized: "\(rank.wins) wins · \(rank.losses) losses"))
                    .font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaMenuStyle.gold)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ranked.standing")
        ArenaOptionRow(title: String(localized: "Ranked Commander"), value: String(localized: "1v1"), selected: true, identifier: "ranked.format") {}
        if !model.rankedEligible, let bracket = model.deckBracket {
            Label(String(localized: "\(bracket.title) is above \(rank.position.tier.name)'s limit (Bracket \(rank.position.tier.maxDeckBracket)). Choose another deck."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(ArenaMenuStyle.font(12, .semibold))
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.5))
                .padding(.vertical, 6)
                .accessibilityIdentifier("ranked.ineligible")
        }
        Text(model.canSearchPeople ? String(localized: "A player near your rank, or an AI if nobody's searching.")
                                   : String(localized: "Profiles are offline: an AI takes the seat, and counts the same."))
            .lineLimit(2)
            .font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
        ArenaOptionRow(title: String(localized: "Season and rules"), chevron: true, identifier: "ranked.hall", action: model.rankedHall)
        ArenaOptionRow(title: String(localized: "Leaderboard"), chevron: true, identifier: "ranked.leaderboard", action: model.leaderboard)
    }

    @ViewBuilder private var customOptions: some View {
        ArenaCaps(text: String(localized: "Players"), size: 9.5).padding(.top, 8).padding(.bottom, 2)
        ArenaOptionRow(title: String(localized: "Against the AI"), detail: String(localized: "One to three AI opponents"),
                       selected: model.playerMode.wrappedValue == "ai", identifier: "custom.ai") { model.playerMode.wrappedValue = "ai" }
        ArenaOptionRow(title: String(localized: "Online table"), detail: String(localized: "iPhone & Android · table code"),
                       selected: model.playerMode.wrappedValue == "online", identifier: "custom.online") { model.playerMode.wrappedValue = "online" }
        ArenaOptionRow(title: String(localized: "Game Center"), detail: String(localized: "iPhones nearby or invited"),
                       selected: model.playerMode.wrappedValue == "gamecenter", identifier: "custom.gamecenter") { model.playerMode.wrappedValue = "gamecenter" }
        Text(String(localized: "Choose each seat at the table next."))
            .font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            .padding(.top, 8)
    }

    @ViewBuilder private var friendsOptions: some View {
        ArenaCaps(text: String(localized: "With friends"), size: 9.5).padding(.top, 8).padding(.bottom, 2)
        ForEach(ArenaFriendWay.allCases) { way in
            ArenaOptionRow(title: way.title, detail: way.detail, selected: friendWay == way, identifier: "friends.\(way.rawValue)") {
                friendWay = way
            }
        }
    }

    /// The chosen table's deck as an open box, the way it was played and the deck's bracket.
    @ViewBuilder private var recentOptions: some View {
        if model.recent.isEmpty {
            Text(String(localized: "Play a game and it waits here, ready to set up again."))
                .font(ArenaMenuStyle.font(12.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 8) {
                if let deck = model.selectedDeck {
                    ArenaDeckBox(deck: deck, selected: true, width: 120)
                        .padding(.top, ArenaBoxGeometry(width: 120).rise + 6)
                }
                ArenaCaps(text: model.mode.wrappedValue == .ranked ? String(localized: "Ranked") : model.mode.wrappedValue == .custom
                          ? String(localized: "Custom Table") : String(localized: "Quick Match"), size: 10)
                if let bracket = model.deckBracket {
                    Text(bracket.title).font(ArenaMenuStyle.font(12, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let phase = model.search {
                ArenaSearchStatus(phase: phase, playAINow: model.playAINow)
            } else if let friend = model.waitingFor {
                VStack(spacing: 2) {
                    Text(String(localized: "Waiting for \(friend)…")).font(ArenaMenuStyle.font(14, .bold)).foregroundStyle(ArenaMenuStyle.text)
                    Text(String(localized: "Your challenge is on its way.")).font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("challenge.waiting")
            } else if let status = model.status {
                Text(status).font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            plaque
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, compact ? 6 : 14)
        .background(alignment: .top) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.3) }
    }

    @ViewBuilder private var plaque: some View {
        if model.search != nil {
            Button(String(localized: "Cancel"), action: model.cancelSearch)
                .buttonStyle(ArenaPlayButtonStyle(cancel: true, fontSize: 19))
                .frame(height: 46)
                .disabled({ if case .matched = model.search { return true }; return false }())
                .accessibilityIdentifier("ranked.search.cancel")
        } else if model.waitingFor != nil {
            Button(String(localized: "Withdraw"), action: model.cancelChallenge)
                .buttonStyle(ArenaPlayButtonStyle(cancel: true, fontSize: 19))
                .frame(height: 46)
                .accessibilityIdentifier("challenge.cancel")
        } else {
            let (title, identifier, enabled, action) = primary
            Button(title, action: action)
                .buttonStyle(ArenaPlayButtonStyle(fontSize: 20))
                .frame(height: 46)
                .disabled(!enabled)
                .accessibilityIdentifier(identifier)
        }
    }

    private var primary: (String, String, Bool, () -> Void) {
        switch model.tab.wrappedValue {
        case .friends:
            switch friendWay {
            case .challenge: return (String(localized: "Challenge"), "play.friends", true, model.challengeFriend)
            case .host: return (String(localized: "Host Table"), "play.friends", true, model.hostOnline)
            case .join: return (String(localized: "Join Table"), "play.friends", true, model.joinOnline)
            case .gamecenter: return (String(localized: "Game Center"), "play.friends", true, model.gameCenter)
            }
        case .recent where model.recent.isEmpty:
            return (String(localized: "Find Match"), "play.recent", true, { model.tab.wrappedValue = .find })
        case .recent, .find:
            switch model.mode.wrappedValue {
            case .quick: return (String(localized: "Play"), "quick.start", model.mayStart, model.startQuick)
            case .ranked: return (String(localized: "Find Match"), "ranked.find", model.mayStart && model.rankedEligible, model.findRanked)
            case .custom: return (String(localized: "Set Up Table"), "play.start", true, model.openCustom)
            }
        }
    }
}

/// A way to play as a cut gem: an ember flame for Quick, your rank's emblem for Ranked, a table for Custom.
struct ArenaModeGem: View {
    let mode: ArenaPlayMode
    let rank: RankPosition
    let lit: Bool
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.24, green: 0.16, blue: 0.10), Color(red: 0.07, green: 0.05, blue: 0.04)],
                                     center: .init(x: 0.4, y: 0.3), startRadius: 0, endRadius: 22))
            Circle().strokeBorder(lit ? AnyShapeStyle(ArenaMenuStyle.metal) : AnyShapeStyle(ArenaGlass.hairline), lineWidth: lit ? 1.6 : 1)
            switch mode {
            case .quick:
                Image(systemName: "bolt.fill").font(.system(size: 17, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), ArenaMenuStyle.ember], startPoint: .top, endPoint: .bottom))
            case .ranked:
                RankEmblem(tier: rank.tier, size: size * 0.8)
            case .custom:
                Image(systemName: "person.3.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(ArenaMenuStyle.metal)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: lit ? ArenaMenuStyle.ember.opacity(0.55) : .clear, radius: 8)
        .accessibilityHidden(true)
    }
}

/// The blade's lit edge: an ember seam that flickers like a flame.
struct ArenaSeam: View {
    let vertical: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAmbientMotion) private var ambient
    @State private var flicker = false

    var body: some View {
        let line = LinearGradient(colors: [ArenaMenuStyle.seam.opacity(0.55), Color(red: 1, green: 0.84, blue: 0.5), ArenaMenuStyle.seam,
                                           Color(red: 1, green: 0.7, blue: 0.3), ArenaMenuStyle.seam.opacity(0.6)],
                                  startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
        // A burning edge: a bright core, an ember glow around it, a wider haze.
        Rectangle()
            .fill(line)
            .frame(width: vertical ? 3.5 : nil, height: vertical ? nil : 3.5)
            .shadow(color: ArenaMenuStyle.seam.opacity(flicker ? 1 : 0.7), radius: flicker ? 9 : 7)
            .shadow(color: Color(red: 1, green: 0.35, blue: 0.1).opacity(0.55), radius: 20)
            .ignoresSafeArea(edges: vertical ? .bottom : [])
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion, ambient else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { flicker = true }
            }
    }
}

/// A ranked search in the blade: how long it has run, and the AI on offer.
struct ArenaSearchStatus: View {
    let phase: RankedMatchmaker.Phase
    let playAINow: () -> Void

    var body: some View {
        switch phase {
        case .matched(let ticket):
            VStack(spacing: 2) {
                Text(String(localized: "Challenger found")).font(ArenaMenuStyle.font(14, .bold)).foregroundStyle(ArenaMenuStyle.text)
                Text(ticket.opponent ?? String(localized: "Another player")).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.gold)
                Text(String(localized: "Setting the table…")).font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ranked.search")
        default:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let since: Date = { if case .searching(let start) = phase { return start }; return context.date }()
                let elapsed = max(0, Int(context.date.timeIntervalSince(since)))
                let left = max(0, Int(RankedMatchmaker.searchSeconds) - elapsed)
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(String(localized: "Searching…")).font(ArenaMenuStyle.font(14, .bold)).foregroundStyle(ArenaMenuStyle.text)
                        Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                            .font(ArenaMenuStyle.font(14, .bold)).monospacedDigit().foregroundStyle(ArenaMenuStyle.gold)
                    }
                    Text(String(localized: "An AI takes the seat in \(left) s."))
                        .font(ArenaMenuStyle.font(11, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    Button(String(localized: "Play the AI now"), action: playAINow)
                        .buttonStyle(ArenaPillButtonStyle())
                        .accessibilityIdentifier("ranked.search.ai")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ranked.search")
        }
    }
}

/// The ways to play with friends in the Play panel's Friends tab.
enum ArenaFriendWay: String, CaseIterable, Identifiable {
    case challenge, host, join, gamecenter
    var id: String { rawValue }

    var title: String {
        switch self {
        case .challenge: return String(localized: "Challenge a friend")
        case .host: return String(localized: "Host an online table")
        case .join: return String(localized: "Join with a code")
        case .gamecenter: return String(localized: "Game Center")
        }
    }

    var detail: String {
        switch self {
        case .challenge: return String(localized: "Quick Match or Ranked")
        case .host: return String(localized: "Share its code with anyone")
        case .join: return String(localized: "iPhone or Android table")
        case .gamecenter: return String(localized: "Invite iPhones nearby")
        }
    }
}
