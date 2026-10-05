import SwiftUI

/// The player's profile: rank and season, title, favorite commander, stats, achievements and
/// match history, all in the tavern.
struct PlayerProfileView: View {
    @ObservedObject var record: PlayerRecordStore
    let playerName: String
    /// Commanders of the player's own decks (saved, then included), offered as the profile picture.
    var deckCommanders: [String] = []
    let back: () -> Void
    @State private var showAllMatches = false

    private var stats: PlayerStats { record.stats }
    private var unlocked: Set<Achievement> { record.achievements }

    var body: some View {
        TavernLobbyPage(title: String(localized: "Profile"), back: back) {
            header
            seasonCard
            statsCard
            if !stats.colors.isEmpty { colorsCard }
            if !stats.decks.isEmpty { decksCard }
            achievementsCard
            historyCard
        }
        .onAppear { record.refreshSeason() }
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
        let played = stats.commanders.prefix(12).map(\.label)
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

    // MARK: Season

    private var seasonCard: some View {
        HStack(alignment: .center, spacing: 16) {
            RankBadge(position: record.rank.position, size: 104, showsPips: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(record.rank.position.title)
                    .font(.system(size: 22, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), record.rank.position.tier.tint],
                                                    startPoint: .top, endPoint: .bottom))
                Text(String(localized: "Season \(RankLadder.seasonName(record.rank.season))"))
                    .font(.system(size: 13, weight: .semibold, design: .serif)).opacity(0.8)
                Text(String(localized: "Ranked \(record.rank.wins)–\(record.rank.losses) · Peak \(record.rank.peak.title)"))
                    .font(.system(size: 14, design: .serif))
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
            Spacer(minLength: 0)
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.season")
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(String(localized: "Record"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                tile(String(localized: "Games"), "\(stats.games)")
                tile(String(localized: "Wins"), "\(stats.wins)")
                tile(String(localized: "Win rate"), stats.games == 0 ? "–" : "\(Int((stats.winRate * 100).rounded()))%")
                tile(String(localized: "Streak"), "\(stats.currentStreak)")
                tile(String(localized: "Best streak"), "\(stats.bestStreak)")
                tile(String(localized: "Avg. turns"), stats.averageTurns.map { String(format: "%.1f", $0) } ?? "–")
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityIdentifier("profile.stats")
    }

    private var colorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Colors"))
            ForEach(stats.colors) { line in
                HStack(spacing: 10) {
                    TavernAwareManaSymbol(symbol: line.id, size: 20)
                    Text(line.label).font(.system(size: 14, weight: .semibold, design: .serif)).frame(width: 64, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.45))
                            Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.32), TavernPalette.enamel], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, proxy.size.width * line.winRate))
                        }
                    }
                    .frame(height: 10)
                    Text("\(line.wins)/\(line.games)").font(.system(size: 12, design: .serif)).monospacedDigit().opacity(0.8)
                }
                .environment(\.tavernBoard, true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "\(line.label): \(line.wins) wins in \(line.games) games"))
            }
        }
        .modifier(TavernLeatherCard())
    }

    private var decksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Your decks"))
            ForEach(stats.decks.prefix(6)) { line in
                HStack(spacing: 12) {
                    CommanderDeckPortrait(name: line.detail, namespace: nil).frame(width: 34, height: 47)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.label).font(.system(size: 15, weight: .bold, design: .serif)).lineLimit(1)
                        if let commander = line.detail { Text(commander).font(.system(size: 12, design: .serif)).italic().opacity(0.7).lineLimit(1) }
                    }
                    Spacer(minLength: 6)
                    Text("\(line.wins)–\(line.games - line.wins)").font(.system(size: 14, weight: .heavy, design: .serif)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .modifier(TavernParchmentCard())
    }

    // MARK: Achievements

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(String(localized: "Achievements · \(unlocked.count)/\(Achievement.allCases.count)"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Achievement.allCases) { achievement in
                    let earned = unlocked.contains(achievement)
                    HStack(spacing: 10) {
                        Image(systemName: achievement.systemImage)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(earned ? AnyShapeStyle(BrandTheme.brassGradient) : AnyShapeStyle(Color.gray))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.4)).overlay(Circle().strokeBorder(earned ? TavernPalette.brass : .gray.opacity(0.5), lineWidth: 1.5)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(achievement.title).font(.system(size: 13, weight: .heavy, design: .serif)).lineLimit(1).minimumScaleFactor(0.8)
                            Text(achievement.detail).font(.system(size: 11, design: .serif)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(earned ? 1 : 0.5)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(earned ? String(localized: "Earned") : String(localized: "Locked"))
                }
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityIdentifier("profile.achievements")
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Match history"))
            if record.matches.isEmpty {
                Text(String(localized: "Your games show here after you play.")).font(.system(size: 14, design: .serif)).opacity(0.75)
            }
            ForEach(record.matches.prefix(showAllMatches ? 60 : 8)) { match in RankedMatchRow(match: match) }
            if record.matches.count > 8 {
                Button(showAllMatches ? String(localized: "Show fewer") : String(localized: "Show more")) {
                    withAnimation { showAllMatches.toggle() }
                }
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityIdentifier("profile.history")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
            .foregroundStyle(BrandTheme.brassGradient)
            .accessibilityAddTraits(.isHeader)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .black, design: .serif)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TavernPalette.brass.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// One finished game: result, mode, opponent and the rank it moved.
struct RankedMatchRow: View {
    let match: MatchRecord

    var body: some View {
        HStack(spacing: 10) {
            Text(resultLetter)
                .font(.system(size: 15, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(resultColor))
                .overlay(Circle().strokeBorder(TavernPalette.brass.opacity(0.7), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "vs \(opponentText)")).font(.system(size: 14, weight: .bold, design: .serif)).lineLimit(1)
                Text("\(modeText) · \(match.deckName) · \(match.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11, design: .serif)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let change = match.rankChange {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(change.pipDelta > 0 ? "+\(change.pipDelta)" : "\(change.pipDelta)")
                        .font(.system(size: 13, weight: .heavy, design: .serif)).monospacedDigit()
                        .foregroundStyle(change.pipDelta >= 0 ? Color(red: 0.6, green: 0.95, blue: 0.55) : Color(red: 1, green: 0.55, blue: 0.45))
                    Text(change.after.title).font(.system(size: 10, design: .serif)).opacity(0.7)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var opponentText: String {
        let names = match.opponents.map(\.name)
        return names.count <= 1 ? (names.first ?? String(localized: "Opponent")) : String(localized: "\(names.count) opponents")
    }

    private var modeText: String {
        switch match.mode {
        case .quick: return String(localized: "Quick")
        case .ranked: return match.vsHuman ? String(localized: "Ranked · Player") : String(localized: "Ranked · AI")
        case .casual: return String(localized: "Custom")
        }
    }

    private var resultLetter: String {
        switch match.outcome { case .win: return "W"; case .loss: return "L"; case .draw: return "D" }
    }

    private var resultColor: Color {
        switch match.outcome {
        case .win: return Color(red: 0.25, green: 0.5, blue: 0.2)
        case .loss: return MagicPalette.oxblood
        case .draw: return Color(white: 0.35)
        }
    }
}

/// A friend's ranked card, opened from the friends list.
struct PlayerCardView: View {
    let username: String
    let card: PlayerProfileCard?
    let loading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TavernPanelTitle(text: username)
                Spacer(minLength: 8)
                Button { dismiss() } label: { TavernSealLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Done"))
                    .accessibilityIdentifier("playerCard.close")
            }
            .modifier(TavernTitleBar())
            .padding(.horizontal, 16).padding(.top, 12)
            VStack(spacing: 14) {
                if loading {
                    ProgressView().tint(TavernPalette.brass).padding(40)
                } else if let card, let position = card.position {
                    RankBadge(position: position, size: 120, showsPips: true, showsTitle: true)
                    if let title = card.title { TavernTag(text: title, leather: true, accent: TavernPalette.ember) }
                    Text(String(localized: "Ranked \(card.wins ?? 0)–\(card.losses ?? 0) this season"))
                        .font(.system(size: 15, design: .serif))
                    if let peak = card.peakStep { Text(String(localized: "Peak \(RankPosition.atStep(peak).title)")).font(.system(size: 13, design: .serif)).opacity(0.8) }
                    if let commander = card.favoriteCommander {
                        CommanderArtMedallion(name: commander, diameter: 72).frame(width: 98, height: 98)
                        Text(commander).font(.system(size: 13, design: .serif)).italic().opacity(0.8)
                    }
                } else {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 40)).foregroundStyle(BrandTheme.brassGradient).padding(.top, 20)
                    Text(String(localized: "\(username) hasn't played ranked this season.")).font(.system(size: 15, design: .serif))
                }
            }
            .foregroundStyle(TavernPalette.parchment)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .background(TavernSheetBackground())
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
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
