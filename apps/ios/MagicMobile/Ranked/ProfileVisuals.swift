import SwiftUI

/// The pictures of a profile, drawn in the tavern's brass and leather. The own profile and other
/// players' public profiles share them; Android draws the same set (ProfileVisuals.kt).
enum ProfilePalette {
    /// Wins: the tavern's gold.
    static let win = Color(red: 0.98, green: 0.78, blue: 0.36)
    static let winDeep = Color(red: 0.93, green: 0.50, blue: 0.22)
    static let loss = Color(red: 0.62, green: 0.16, blue: 0.12)
    static let draw = Color(red: 0.62, green: 0.58, blue: 0.50)
    static let track = Color.black.opacity(0.42)

    static func mana(_ symbol: String) -> Color {
        switch symbol {
        case "W": return Color(red: 0.97, green: 0.92, blue: 0.74)
        case "U": return Color(red: 0.30, green: 0.55, blue: 0.90)
        case "B": return Color(red: 0.46, green: 0.36, blue: 0.52)
        case "R": return Color(red: 0.89, green: 0.30, blue: 0.22)
        case "G": return Color(red: 0.32, green: 0.68, blue: 0.36)
        default: return Color(white: 0.6)
        }
    }

    static let winGradient = LinearGradient(colors: [win, winDeep], startPoint: .top, endPoint: .bottom)
}

/// A section's title: brass capitals.
struct ProfileSectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
                .foregroundStyle(BrandTheme.brassGradient)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(.system(size: 11, weight: .semibold, design: .serif)).opacity(0.7)
            }
        }
    }
}

/// Our own chip: leather with a thin brass rim, ember glass when chosen. Filters use it.
struct ProfileChip: View {
    let title: String
    var detail: String?
    let selected: Bool
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .heavy, design: .serif)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 11, weight: .semibold, design: .serif)).opacity(0.7).monospacedDigit() }
            }
            .foregroundStyle(selected ? Color(red: 1, green: 0.91, blue: 0.66) : TavernPalette.parchment)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                TavernFill(material: selected ? .ember : .leather)
                    .overlay(selected ? Color.clear : Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .padding(1.5)
            }
            .overlay { TavernCapsuleRim(thin: true) }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Our own segmented control: a leather trough in brass with one ember-glass segment lit.
struct ProfileSegmented<Value: Hashable>: View {
    struct Option { let value: Value; let title: String; let icon: String; let identifier: String }

    let options: [Option]
    @Binding var selection: Value
    var identifier: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.identifier) { option in
                let on = option.value == selection
                Button { if !on { selection = option.value } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: option.icon).font(.system(size: 14, weight: .bold))
                        Text(option.title).font(.system(size: 12, weight: .heavy, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Color(red: 1, green: 0.91, blue: 0.66) : TavernPalette.parchment.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if on {
                            TavernFill(material: .ember).clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TavernPalette.brassLine, lineWidth: 1))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(option.identifier)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TavernPalette.brass.opacity(0.55), lineWidth: 1.2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Win rate

/// The record as a ring: wins in gold, draws in stone, losses in oxblood, the win rate in the middle.
struct WinRateRing: View {
    let wins: Int
    let losses: Int
    let draws: Int
    var size: CGFloat = 132
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int { wins + losses + draws }
    private var line: CGFloat { size * 0.13 }

    var body: some View {
        ZStack {
            Circle().stroke(ProfilePalette.track, lineWidth: line)
            if total > 0 {
                segment(from: 0, length: fraction(wins), style: AnyShapeStyle(ProfilePalette.winGradient))
                segment(from: fraction(wins), length: fraction(draws), style: AnyShapeStyle(ProfilePalette.draw))
                segment(from: fraction(wins) + fraction(draws), length: fraction(losses), style: AnyShapeStyle(ProfilePalette.loss))
            }
            Circle().strokeBorder(TavernPalette.brass.opacity(0.5), lineWidth: 1)
                .padding(-line / 2 - 1.5)
            VStack(spacing: 0) {
                Text(total == 0 ? "–" : "\(Int((Double(wins) / Double(total) * 100).rounded()))%")
                    .font(.system(size: size * 0.27, weight: .black, design: .serif)).monospacedDigit()
                    .foregroundStyle(BrandTheme.brassGradient)
                Text(String(localized: "WIN RATE")).font(.system(size: size * 0.075, weight: .heavy, design: .serif)).tracking(1.2).opacity(0.7)
            }
        }
        .frame(width: size, height: size)
        .padding(line / 2 + 2)
        .onAppear {
            if reduceMotion { progress = 1 } else { withAnimation(.easeOut(duration: 0.9)) { progress = 1 } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total == 0 ? String(localized: "Win rate: no games yet")
                            : String(localized: "Win rate \(Int((Double(wins) / Double(total) * 100).rounded())) percent: \(wins) wins, \(losses) losses, \(draws) draws"))
        .accessibilityIdentifier("profile.winRate")
    }

    private func fraction(_ count: Int) -> CGFloat { total == 0 ? 0 : CGFloat(count) / CGFloat(total) }

    @ViewBuilder
    private func segment(from start: CGFloat, length: CGFloat, style: AnyShapeStyle) -> some View {
        if length > 0 {
            let gap: CGFloat = length < 1 ? 0.006 : 0
            Circle()
                .trim(from: start + gap / 2, to: start + max(0.002, length * progress - gap / 2))
                .stroke(style, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A big number over a small caption, in a dark inset tile.
struct ProfileStatTile: View {
    let title: String
    let value: String
    var icon: String?
    var tint: Color = TavernPalette.parchment

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(tint) }
                Text(value).font(.system(size: 21, weight: .black, design: .serif)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TavernPalette.brass.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Games over time

/// The last eight weeks as bars: wins in gold at the foot, other games in oxblood above.
struct WeeklyBars: View {
    let weeks: [ProfileSummary.Week]
    var barHeight: CGFloat = 104

    private static let utc = TimeZone(identifier: "UTC") ?? .gmt

    var body: some View {
        let peak = CGFloat(max(3, weeks.map(\.games).max() ?? 0))
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(weeks) { week in
                VStack(spacing: 4) {
                    Text(week.games == 0 ? " " : "\(week.games)")
                        .font(.system(size: 11, weight: .heavy, design: .serif)).monospacedDigit().opacity(0.85)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(ProfilePalette.track)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            let others = CGFloat(week.games - week.wins) / peak * barHeight
                            let won = CGFloat(week.wins) / peak * barHeight
                            if week.games > week.wins { Rectangle().fill(ProfilePalette.loss).frame(height: others) }
                            if week.wins > 0 { Rectangle().fill(ProfilePalette.winGradient).frame(height: won) }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: barHeight)
                    Text(week.start.formatted(Date.FormatStyle(timeZone: Self.utc).month(.abbreviated).day()))
                        .font(.system(size: 9, weight: .semibold, design: .serif)).opacity(0.65)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Week of \(week.start.formatted(Date.FormatStyle(timeZone: Self.utc).month(.wide).day())): \(week.games) games, \(week.wins) wins"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.weeks")
    }
}

// MARK: Rank history

/// Rank over time: the standing after each ranked game, on the ladder's tiers.
struct RankHistoryChart: View {
    let points: [ProfileSummary.RankPoint]
    var height: CGFloat = 150

    private var tiers: [(tier: RankTier, low: Int)] {
        RankTier.allCases.map { ($0, $0.rawValue * RankPosition.divisions * RankPosition.pipsPerDivision) }
    }

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in draw(&context, size) }
                .frame(height: height)
            if let first = points.first, let last = points.last, points.count > 1 {
                HStack {
                    Text(first.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text(String(localized: "\(points.count) ranked games"))
                    Spacer()
                    Text(last.date.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.system(size: 10, weight: .semibold, design: .serif)).opacity(0.65)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryText)
        .accessibilityIdentifier("profile.rankHistory")
    }

    private var summaryText: String {
        guard let first = points.first, let last = points.last else { return String(localized: "Rank history: no ranked games yet") }
        if points.count == 1 { return String(localized: "Rank history: \(last.position.title) after one ranked game") }
        return String(localized: "Rank history: from \(first.position.title) to \(last.position.title) over \(points.count) ranked games")
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        guard !points.isEmpty else { return }
        let values = points.map(\.points)
        let low = max(0, (values.min() ?? 0) - 3)
        let high = max(low + 10, (values.max() ?? 0) + 3)
        let left: CGFloat = 26, right: CGFloat = 10, top: CGFloat = 10, bottom: CGFloat = 10
        let width = size.width - left - right, plot = size.height - top - bottom
        func y(_ value: Int) -> CGFloat { top + (1 - CGFloat(value - low) / CGFloat(high - low)) * plot }
        func x(_ index: Int) -> CGFloat { points.count == 1 ? left + width / 2 : left + CGFloat(index) / CGFloat(points.count - 1) * width }

        // Tier bands: a hairline where a tier starts, its initial in the tier's metal.
        for entry in tiers {
            let band = entry.low..<(entry.tier == .mythic ? Int.max : entry.low + 16)
            let visibleLow = max(low, band.lowerBound), visibleHigh = min(high, band.upperBound == Int.max ? high : band.upperBound)
            if entry.low > low && entry.low < high {
                var line = Path(); line.move(to: CGPoint(x: left, y: y(entry.low))); line.addLine(to: CGPoint(x: size.width - right, y: y(entry.low)))
                context.stroke(line, with: .color(entry.tier.tint.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if visibleHigh - visibleLow >= 4 {
                let mid = y((visibleLow + visibleHigh) / 2)
                context.draw(Text(String(entry.tier.name.prefix(1))).font(.system(size: 13, weight: .black, design: .serif)).foregroundStyle(entry.tier.tint.opacity(0.9)),
                             at: CGPoint(x: 10, y: mid))
            }
        }
        var area = Path(), line = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: x(index), y: y(value))
            if index == 0 { line.move(to: point); area.move(to: CGPoint(x: point.x, y: top + plot)); area.addLine(to: point) }
            else { line.addLine(to: point); area.addLine(to: point) }
        }
        area.addLine(to: CGPoint(x: x(values.count - 1), y: top + plot)); area.closeSubpath()
        context.fill(area, with: .linearGradient(Gradient(colors: [ProfilePalette.winDeep.opacity(0.38), .clear]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + plot)))
        context.stroke(line, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), ProfilePalette.winDeep]),
                                                   startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + width, y: 0)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        for (index, value) in values.enumerated().dropLast() {
            let dot = Path(ellipseIn: CGRect(x: x(index) - 2.5, y: y(value) - 2.5, width: 5, height: 5))
            context.fill(dot, with: .color(Color(red: 1, green: 0.9, blue: 0.62)))
        }
        if let last = values.last, let tier = points.last?.position.tier {
            let center = CGPoint(x: x(values.count - 1), y: y(last))
            var glow = context
            glow.addFilter(.shadow(color: tier.tint, radius: 7))
            glow.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(tier.tint))
            context.stroke(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }
    }
}

// MARK: Colors

/// Color identity as a ring of the five colors, by games played with each.
struct ColorPie: View {
    let shares: [ProfileSummary.Share]
    var size: CGFloat = 112

    private var total: Int { shares.reduce(0) { $0 + $1.games } }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Canvas { context, canvas in
                    let line = size * 0.26
                    let radius = (min(canvas.width, canvas.height) - line) / 2
                    let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                    var start = Angle.degrees(-90)
                    for share in shares where share.games > 0 {
                        let sweep = Angle.degrees(360 * Double(share.games) / Double(max(1, total)))
                        var arc = Path()
                        arc.addArc(center: center, radius: radius, startAngle: start + .degrees(shares.count > 1 ? 1.2 : 0),
                                   endAngle: start + sweep - .degrees(shares.count > 1 ? 1.2 : 0), clockwise: false)
                        context.stroke(arc, with: .color(ProfilePalette.mana(share.id)), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                        start += sweep
                    }
                }
                Circle().strokeBorder(TavernPalette.brass.opacity(0.5), lineWidth: 1).padding(size * 0.02)
                Circle().strokeBorder(TavernPalette.brass.opacity(0.35), lineWidth: 1).padding(size * 0.28)
                Image(systemName: "sparkle").font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(shares) { share in
                    HStack(spacing: 8) {
                        TavernAwareManaSymbol(symbol: share.id, size: 17)
                        Text(PlayerStats.colorName(share.id)).font(.system(size: 13, weight: .semibold, design: .serif)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int((Double(share.games) / Double(max(1, total)) * 100).rounded()))%")
                            .font(.system(size: 12, weight: .heavy, design: .serif)).monospacedDigit().opacity(0.85)
                    }
                    .environment(\.tavernBoard, true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "\(PlayerStats.colorName(share.id)): \(share.games) games, \(share.wins) wins"))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.colors")
    }
}

// MARK: Commanders

/// A commander's illustration as a tile in a brass edge, with how often it was played and won.
struct CommanderTile: View {
    let share: ProfileSummary.Share
    var crown = false

    var body: some View {
        // The tile's shape is set by an empty base; the picture and the captions are laid over it, so a picture
        // that fills never widens the tile past its cell.
        Color.clear
            .aspectRatio(0.78, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [MagicPalette.iron, MagicPalette.leather], startPoint: .top, endPoint: .bottom)
                    // Laid over an empty view, so a picture that fills cannot widen the tile.
                    Color.clear.overlay {
                        NativeCardArtworkView(name: share.id, variant: .board, contentMode: .fill, artOnly: true) { _, _ in
                            Text(String(share.id.prefix(1))).font(.system(size: 40, weight: .black, design: .serif)).foregroundStyle(TavernPalette.parchment.opacity(0.25))
                        }
                    }
                    .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(share.id).font(.system(size: 11, weight: .heavy, design: .serif)).lineLimit(2).minimumScaleFactor(0.8)
                            .foregroundStyle(TavernPalette.parchment)
                        Text(String(localized: "\(share.games) games · \(Int((share.winRate * 100).rounded()))% won"))
                            .font(.system(size: 9, weight: .semibold, design: .serif)).foregroundStyle(ProfilePalette.win)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(7)
                    if crown {
                        Image(systemName: "crown.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                            .padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TavernPalette.brassLine, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(share.id): \(share.games) games, \(share.wins) won"))
    }
}

/// The most played commanders as art tiles, the first with a crown.
struct CommanderTiles: View {
    let shares: [ProfileSummary.Share]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                CommanderTile(share: share, crown: index == 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.commanders")
    }
}

// MARK: Streaks and trophies

/// Current and best streaks as flames.
struct StreakRow: View {
    let current: Int
    let best: Int

    var body: some View {
        HStack(spacing: 10) {
            streak(title: String(localized: "Streak"), value: current, hot: current >= 3)
            streak(title: String(localized: "Best"), value: best, hot: false)
        }
    }

    private func streak(title: String, value: Int, hot: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").font(.system(size: 20, weight: .bold))
                .foregroundStyle(value > 0 ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4), ProfilePalette.winDeep],
                                                                          startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.gray.opacity(0.5)))
                .shadow(color: hot ? ProfilePalette.winDeep : .clear, radius: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.system(size: 22, weight: .black, design: .serif)).monospacedDigit()
                Text(title.uppercased()).font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1).opacity(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TavernPalette.brass.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(title): \(value) wins in a row"))
    }
}

/// The achievements as brass coins on a wooden shelf; earned ones shine, the rest wait in the dark.
/// Tapping one reads what it is for.
struct TrophyShelf: View {
    let unlocked: Set<Achievement>
    @State private var chosen: Achievement?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(spacing: 10) {
            let rows = Achievement.allCases.chunked(into: 5)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(row) { achievement in coin(achievement) }
                        ForEach(0..<(5 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.34, blue: 0.16), Color(red: 0.28, green: 0.15, blue: 0.06)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 7)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1) }
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                }
            }
            Text(chosen.map { "\($0.title): \($0.detail)" } ?? String(localized: "Tap a coin to read what it is for."))
                .font(.system(size: 12, weight: .semibold, design: .serif)).opacity(chosen == nil ? 0.55 : 0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 32, alignment: .topLeading)
                .accessibilityIdentifier("profile.trophyNote")
        }
    }

    private func coin(_ achievement: Achievement) -> some View {
        let earned = unlocked.contains(achievement)
        return Button { chosen = achievement } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(earned ? AnyShapeStyle(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), Color(red: 0.72, green: 0.48, blue: 0.16), Color(red: 0.36, green: 0.22, blue: 0.08)],
                                                                           center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 30))
                                         : AnyShapeStyle(Color.black.opacity(0.5)))
                    Circle().strokeBorder(earned ? TavernPalette.brassLine : LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    Image(systemName: achievement.systemImage)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(earned ? Color(red: 0.30, green: 0.15, blue: 0.04) : Color.gray.opacity(0.55))
                        .shadow(color: earned ? .white.opacity(0.35) : .clear, radius: 0, y: 1)
                }
                .frame(width: 46, height: 46)
                .shadow(color: earned ? ProfilePalette.win.opacity(0.4) : .black.opacity(0.4), radius: earned ? 5 : 2, y: 2)
                Text(achievement.title).font(.system(size: 9, weight: .heavy, design: .serif)).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7).opacity(earned ? 0.95 : 0.45).frame(height: 24, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(achievement.title). \(achievement.detail)")
        .accessibilityValue(earned ? String(localized: "Earned") : String(localized: "Locked"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("profile.trophy.\(achievement.rawValue)")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: Games

/// One finished game as a card: the commander's art, the result stamp, who it was against and when.
/// A game with a detailed record opens it (`onOpenDetail`); any other opens its details in place.
struct ProfileGameCard: View {
    let game: ProfileGame
    var identifier: String
    var openPlayer: ((String) -> Void)?
    var onOpenDetail: (() -> Void)?
    @State private var expanded = false

    private var detailed: Bool { onOpenDetail != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if let onOpenDetail { onOpenDetail() } else { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } }
            } label: {
                HStack(spacing: 12) {
                    art
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "vs \(opponentText)")).font(.system(size: 15, weight: .heavy, design: .serif)).lineLimit(1)
                        Text(game.deckName.isEmpty ? (game.commander ?? String(localized: "Deck")) : game.deckName)
                            .font(.system(size: 12, weight: .semibold, design: .serif)).opacity(0.8).lineLimit(1)
                        HStack(spacing: 6) {
                            TavernTag(text: modeText.uppercased(), leather: true)
                            Text(game.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11, design: .serif)).opacity(0.65)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        stamp
                        if let delta = game.rankDelta, delta != 0 {
                            Text(delta > 0 ? "+\(delta)" : "\(delta)").font(.system(size: 12, weight: .heavy, design: .serif)).monospacedDigit()
                                .foregroundStyle(delta > 0 ? Color(red: 0.6, green: 0.95, blue: 0.55) : Color(red: 1, green: 0.55, blue: 0.45))
                        } else if detailed {
                            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 12, weight: .bold)).foregroundStyle(BrandTheme.ember)
                        }
                    }
                }
                .padding(10)
                .frame(minHeight: 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint(detailed ? String(localized: "Opens the match dashboard") : (expanded ? String(localized: "Hides the details") : String(localized: "Shows the details")))
            .accessibilityIdentifier(identifier)
            if expanded && !detailed { details.transition(.opacity) }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TavernPalette.brass.opacity(0.45), lineWidth: 1))
    }

    private var label: String {
        let deck = game.deckName.isEmpty ? (game.commander ?? "") : game.deckName
        let delta = game.rankDelta.map { $0 == 0 ? "" : ", \($0 > 0 ? "+" : "")\($0) pips" } ?? ""
        return "\(resultName) against \(opponentText), \(deck), \(modeText), \(game.date.formatted(date: .abbreviated, time: .omitted))\(delta)"
    }

    private var art: some View {
        ZStack {
            LinearGradient(colors: [MagicPalette.iron, MagicPalette.leather], startPoint: .top, endPoint: .bottom)
            if let commander = game.commander {
                NativeCardArtworkView(name: commander, variant: .board, contentMode: .fill, artOnly: true) { _, _ in
                    Image(systemName: "person.fill").foregroundStyle(TavernPalette.parchment.opacity(0.4))
                }
            } else {
                Image(systemName: "person.fill").foregroundStyle(TavernPalette.parchment.opacity(0.4))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TavernPalette.brassLine, lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private var stamp: some View {
        Text(resultLetter)
            .font(.system(size: 17, weight: .black, design: .serif))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(resultColor))
            .overlay(Circle().strokeBorder(TavernPalette.brass.opacity(0.8), lineWidth: 1.2))
            .accessibilityLabel(resultName)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(TavernPalette.brass.opacity(0.35))
            ForEach(Array(game.opponents.enumerated()), id: \.offset) { _, opponent in
                HStack(spacing: 8) {
                    if let commander = opponent.commander {
                        NativeCardArtworkView(name: commander, variant: .board, contentMode: .fill, artOnly: true) { _, _ in Color.clear }
                            .frame(width: 30, height: 30).clipShape(Circle())
                            .overlay(Circle().strokeBorder(TavernPalette.brass.opacity(0.6), lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if let openPlayer, !opponent.isAI, !opponent.hidden {
                            Button { openPlayer(opponent.name) } label: {
                                Text(opponent.name).font(.system(size: 13, weight: .heavy, design: .serif)).underline()
                                    .foregroundStyle(BrandTheme.ember).frame(minHeight: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(String(localized: "Opens their profile"))
                            .accessibilityIdentifier("\(identifier).opponent.\(opponent.name)")
                        } else {
                            Text(opponent.name).font(.system(size: 13, weight: .heavy, design: .serif))
                        }
                        if let commander = opponent.commander {
                            Text(commander).font(.system(size: 11, design: .serif)).italic().opacity(0.7).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if opponent.isAI { TavernTag(text: String(localized: "AI"), leather: true) }
                }
            }
            HStack(spacing: 14) {
                if let turns = game.turns { Label(String(localized: "\(turns) turns"), systemImage: "hourglass").labelStyle(.titleOnly) }
                Text(game.date.formatted(date: .complete, time: .shortened))
            }
            .font(.system(size: 11, design: .serif)).opacity(0.7)
            if game.opponents.isEmpty {
                Text(String(localized: "Opponents weren't recorded for this game.")).font(.system(size: 11, design: .serif)).italic().opacity(0.55)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private var opponentText: String {
        let names = game.opponents.map { $0.hidden ? String(localized: "a player") : $0.name }
        return names.count <= 1 ? (names.first ?? String(localized: "Opponent")) : String(localized: "\(names.count) opponents")
    }

    private var modeText: String {
        switch game.mode {
        case .quick: return String(localized: "Quick")
        case .ranked: return game.vsHuman ? String(localized: "Ranked · Player") : String(localized: "Ranked · AI")
        case .casual: return String(localized: "Custom")
        }
    }

    private var resultLetter: String {
        switch game.outcome { case .win: return "W"; case .loss: return "L"; case .draw: return "D" }
    }

    private var resultName: String {
        switch game.outcome { case .win: return String(localized: "Won"); case .loss: return String(localized: "Lost"); case .draw: return String(localized: "Drawn") }
    }

    private var resultColor: Color {
        switch game.outcome {
        case .win: return Color(red: 0.25, green: 0.5, blue: 0.2)
        case .loss: return MagicPalette.oxblood
        case .draw: return Color(white: 0.35)
        }
    }
}

/// A line of rank: the badge, the division, the season and the record, for a profile's top.
struct ProfileRankSummary: View {
    let position: RankPosition
    let seasonName: String
    let wins: Int
    let losses: Int
    let peak: RankPosition

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RankBadge(position: position, size: 96, showsPips: true)
            VStack(alignment: .leading, spacing: 5) {
                Text(position.title)
                    .font(.system(size: 22, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), position.tier.tint], startPoint: .top, endPoint: .bottom))
                Text(String(localized: "Season \(seasonName)")).font(.system(size: 13, weight: .semibold, design: .serif)).opacity(0.8)
                Text(String(localized: "Ranked \(wins)–\(losses) · Peak \(peak.title)")).font(.system(size: 14, design: .serif))
            }
            Spacer(minLength: 0)
        }
    }
}

/// An empty picture's note: a line saying what will fill it.
struct ProfileEmptyNote: View {
    let text: String
    var systemImage = "sparkles"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
            Text(text).font(.system(size: 13, design: .serif)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TavernPalette.brass.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}
