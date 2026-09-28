import SwiftUI

/// "How to play": a paged walkthrough of the game and the app in the menu brand. It opens once
/// by itself on the main menu (HowToPlayLaunch) and any time from the menu or the Game Menu.
/// Android's HowToPlayView (ui/HowToPlayView.kt) draws the same pages.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var index = 0
    private let pages = HowToPlayText.pages

    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    HowToPlayPageView(page: page, wide: verticalSizeClass == .compact)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            footer
        }
        .background {
            ZStack {
                BrandTheme.canvas
                RadialGradient(colors: [BrandTheme.ember.opacity(0.12), .clear], center: .top, startRadius: 10, endRadius: 420)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onChange(of: index) { _, _ in GameAudio.shared.play(.pageFlip) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 28, glint: false)
            Text(HowToPlayText.title.uppercased())
                .font(.system(size: 13, weight: .heavy)).tracking(2.4)
                .foregroundStyle(BrandTheme.ember)
                .accessibilityLabel(HowToPlayText.title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(HowToPlayText.skip, action: close)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BrandTheme.inkSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
                .accessibilityHidden(isLast)
                .accessibilityIdentifier("howToPlay.skip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            progress
            HStack(spacing: 12) {
                Button { go(-1) } label: { Text(HowToPlayText.back).frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                    .disabled(index == 0)
                    .accessibilityIdentifier("howToPlay.back")
                if isLast {
                    Button(action: close) { Text(HowToPlayText.done).frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(kind: .primary))
                        .accessibilityIdentifier("howToPlay.done")
                } else {
                    Button { go(1) } label: { Text(HowToPlayText.next).frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(kind: .primary))
                        .accessibilityIdentifier("howToPlay.next")
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Dots with the current page drawn long; VoiceOver hears "Page 3 of 10" and can swipe up or down.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { page in
                Capsule()
                    .fill(page == index ? BrandTheme.ember : BrandTheme.border)
                    .frame(width: page == index ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: index)
        .frame(minHeight: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HowToPlayText.progress(page: index + 1, of: pages.count))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(1)
            case .decrement: go(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("howToPlay.progress")
    }

    private func go(_ step: Int) {
        let next = min(pages.count - 1, max(0, index + step))
        guard next != index else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { index = next }
    }

    private func close() {
        GameAudio.shared.play(.uiClose)
        dismiss()
    }
}

/// One page: the drawing, then the title and body. The page scrolls, so large text never clips.
private struct HowToPlayPageView: View {
    let page: HowToPlayPage
    let wide: Bool

    var body: some View {
        ScrollView {
            let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 28))
                : AnyLayout(VStackLayout(alignment: .center, spacing: 22))
            layout {
                HowToPlayIllustration(pageID: page.id)
                    .frame(maxWidth: wide ? 300 : 360)
                    .frame(height: 200)
                VStack(alignment: wide ? .leading : .center, spacing: 10) {
                    Text(page.title)
                        .font(.system(.title, weight: .black))
                        .tracking(-0.4)
                        .foregroundStyle(BrandTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.body)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(BrandTheme.inkSecondary)
                }
                .multilineTextAlignment(wide ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("howToPlay.page.\(page.id)")
    }
}

// MARK: - Illustrations

/// Small drawn mockups of the real controls. Decorative: the page's words say the same, so
/// VoiceOver skips them, and their type stays fixed so they never grow out of their frame.
struct HowToPlayIllustration: View {
    let pageID: String
    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [BrandTheme.surfaceRaised, BrandTheme.canvas], startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [BrandTheme.ember.opacity(0.16), .clear], center: .center, startRadius: 4, endRadius: 170)
            drawing
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(BrandTheme.border, lineWidth: 1))
        .environment(\.dynamicTypeSize, .large)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var drawing: some View {
        switch pageID {
        case "welcome": welcome
        case "decks": decks
        case "start": start
        case "board": HowToPlayMiniBoard()
        case "casting": HowToPlayCasting()
        case "priority": priority
        case "combat": combat
        case "reading": reading
        case "resume": resume
        case "friends": friends
        default: EmptyView()
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            BrandMark(size: 84)
            HStack(spacing: 8) {
                HowToPlayChip(text: "COMMANDER")
                HowToPlayChip(text: "RULES BY XMAGE")
            }
        }
    }

    private var decks: some View {
        HStack(spacing: 18) {
            HowToPlayMiniCard(width: 78, tint: BrandTheme.ember, symbol: "crown.fill")
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR DECK").font(.system(size: 9, weight: .heavy)).tracking(2).foregroundStyle(BrandTheme.ember)
                Text("Token Triumph").font(.system(size: 17, weight: .heavy)).foregroundStyle(BrandTheme.ink)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(DeckStudioPlayText.playing)
                }
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(MagicPalette.emerald)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(MagicPalette.emerald.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(MagicPalette.emerald.opacity(0.6), lineWidth: 1))
                HowToPlayPill(text: DeckStudioPlayText.play, systemImage: "play.fill", style: .ember)
            }
        }
    }

    private var start: some View {
        HStack(spacing: 24) {
            HowToPlayD20(size: 78)
            VStack(spacing: 14) {
                ZStack {
                    ForEach(0..<3, id: \.self) { card in
                        HowToPlayMiniCard(width: 38, tint: [MagicPalette.arcaneBlue, MagicPalette.emerald, BrandTheme.ember][card])
                            .rotationEffect(.degrees(Double(card - 1) * 12), anchor: .bottom)
                            .offset(x: CGFloat(card - 1) * 16)
                    }
                }
                .frame(height: 60)
                HStack(spacing: 6) {
                    HowToPlayPill(text: "Mulligan", style: .quiet)
                    HowToPlayPill(text: "Keep", style: .ember)
                }
            }
        }
    }

    private var priority: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                HowToPlayMiniCard(width: 22, tint: MagicPalette.oxblood, symbol: "bolt.fill")
                Text("On the stack").font(.system(size: 10, weight: .bold)).foregroundStyle(MagicPalette.parchment.opacity(0.7))
            }
            VStack(spacing: 3) {
                HowToPlayPill(text: "Pass Priority", systemImage: "forward.end.fill", style: .dock)
                Text(GameplayActionPresentation.priorityDetail(hasStack: false))
                    .font(.system(size: 10)).foregroundStyle(MagicPalette.parchment.opacity(0.8))
            }
            HowToPlayPill(text: "Skip…", systemImage: "forward.end", style: .quiet)
        }
    }

    private var combat: some View {
        VStack(spacing: 14) {
            HStack(spacing: 30) {
                HowToPlayMiniCard(width: 56, tint: MagicPalette.oxblood, symbol: "bolt.fill", outline: .red)
                    .rotationEffect(.degrees(12))
                HowToPlayMiniCard(width: 56, tint: MagicPalette.arcaneBlue, symbol: "shield.fill")
            }
            HowToPlayPill(text: "Done Attacking", style: .dock)
        }
    }

    private var reading: some View {
        HStack(spacing: 18) {
            HowToPlayMiniCard(width: 84, tint: MagicPalette.arcaneBlue, symbol: "eye.fill")
                .overlay(alignment: .bottom) {
                    Circle().fill(BrandTheme.ember.opacity(0.28))
                        .overlay(Circle().strokeBorder(BrandTheme.ember, lineWidth: 2))
                        .frame(width: 30, height: 30)
                        .offset(y: 10)
                }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "text.book.closed")
                    Text("GAME LOG").tracking(1.6)
                }
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(MagicPalette.antiqueGold)
                ForEach([96, 70, 84, 58], id: \.self) { width in
                    HStack(spacing: 5) {
                        Circle().fill(MagicPalette.antiqueGold.opacity(0.6)).frame(width: 5, height: 5)
                        Capsule().fill(MagicPalette.parchment.opacity(0.3)).frame(width: CGFloat(width), height: 5)
                    }
                }
            }
            .padding(10)
            .background(MagicPalette.iron.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MagicPalette.antiqueGold.opacity(0.3), lineWidth: 1))
        }
    }

    private var resume: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass").font(.system(size: 20, weight: .bold)).foregroundStyle(BrandTheme.ember)
                Text("10 min").font(.system(size: 26, weight: .black)).foregroundStyle(BrandTheme.ink)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(GameResumeText.promptTitle).font(.system(size: 13, weight: .heavy)).foregroundStyle(BrandTheme.ink)
                HStack(spacing: 6) {
                    HowToPlayPill(text: GameResumeText.resume, systemImage: "play.fill", style: .ember)
                    HowToPlayPill(text: GameResumeText.abandon, style: .quiet)
                }
            }
            .padding(12)
            .background(BrandTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BrandTheme.border, lineWidth: 1))
        }
    }

    private var friends: some View {
        HStack(spacing: 12) {
            HowToPlayPhone()
            VStack(spacing: 5) {
                Text("TABLE CODE").font(.system(size: 8, weight: .heavy)).tracking(1.4).foregroundStyle(BrandTheme.inkSecondary)
                Text("K7Q 2MX").font(.system(size: 19, weight: .black, design: .monospaced)).foregroundStyle(BrandTheme.ink)
                Capsule().fill(BrandTheme.ember.opacity(0.7)).frame(width: 76, height: 2)
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text("Online")
                }
                .font(.system(size: 10, weight: .bold)).foregroundStyle(BrandTheme.ember)
            }
            HowToPlayPhone()
        }
    }
}

/// A card silhouette: frame, name bar, art box with an optional symbol, and rules lines.
struct HowToPlayMiniCard: View {
    var width: CGFloat = 44
    var tint: Color = MagicPalette.arcaneBlue
    var symbol: String? = nil
    var outline: Color = MagicPalette.antiqueGold.opacity(0.75)

    var body: some View {
        let height = width * 1.395
        let radius = width * 0.08
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(white: 0.09))
            .overlay {
                VStack(alignment: .leading, spacing: width * 0.05) {
                    Capsule().fill(MagicPalette.parchment.opacity(0.55))
                        .frame(width: width * 0.55, height: max(1.5, width * 0.06))
                    RoundedRectangle(cornerRadius: width * 0.04)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            if let symbol {
                                Image(systemName: symbol).font(.system(size: width * 0.3, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .frame(height: height * 0.42)
                    ForEach(0..<3, id: \.self) { line in
                        Capsule().fill(MagicPalette.parchment.opacity(0.28))
                            .frame(width: width * (line == 2 ? 0.5 : 0.8), height: max(1, width * 0.04))
                    }
                }
                .padding(width * 0.09)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(outline, lineWidth: max(1, width * 0.03)))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}

/// A button face as a label: ember (menu call to action), dock (the board's orange Pass
/// Priority capsule) or quiet (a secondary control).
struct HowToPlayPill: View {
    enum Style { case ember, dock, quiet }
    let text: String
    var systemImage: String? = nil
    let style: Style

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .black)) }
            Text(text).font(style == .dock ? .system(size: 14, weight: .bold, design: .serif) : .system(size: 12, weight: .heavy))
        }
        .lineLimit(1)
        .foregroundStyle(style == .ember ? BrandTheme.emberInk : style == .dock ? Color.white : MagicPalette.parchment)
        .padding(.horizontal, style == .dock ? 22 : 12)
        .frame(height: style == .dock ? 36 : 28)
        .background {
            switch style {
            case .ember: Capsule().fill(BrandTheme.emberGradient)
            case .dock: Capsule().fill(LinearGradient(colors: [Color(red: 0.78, green: 0.31, blue: 0.065), Color(red: 0.64, green: 0.20, blue: 0.05)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            case .quiet: Capsule().fill(LinearGradient(colors: [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.76)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay {
            Capsule().strokeBorder(style == .dock ? Color(red: 1, green: 0.79, blue: 0.39) : style == .ember ? Color.white.opacity(0.22)
                                   : MagicPalette.parchment.opacity(0.25), lineWidth: style == .dock ? 1.5 : 1)
        }
    }
}

private struct HowToPlayChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(1.4)
            .foregroundStyle(BrandTheme.ember)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(BrandTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BrandTheme.border, lineWidth: 1))
    }
}

/// A D20 seen face-on: a hexagon with the center face and its edges.
struct HowToPlayD20: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            HowToPlayD20Shape(facets: false).fill(BrandTheme.emberGradient)
            HowToPlayD20Shape(facets: true).stroke(BrandTheme.emberInk.opacity(0.45), lineWidth: 1.5)
            HowToPlayD20Shape(facets: false).stroke(Color.white.opacity(0.3), lineWidth: 1)
            Text("20").font(.system(size: size * 0.24, weight: .black)).foregroundStyle(BrandTheme.emberInk)
                .offset(y: size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: BrandTheme.ember.opacity(0.4), radius: 10)
    }
}

/// Outline: a pointy-top hexagon. Facets: the inner triangle and the edges out to the corners.
struct HowToPlayD20Shape: Shape {
    let facets: Bool

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        func point(_ degrees: Double, _ scale: Double) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: center.x + CGFloat(cos(angle) * scale) * radius, y: center.y + CGFloat(sin(angle) * scale) * radius)
        }
        let outer = [-90.0, -30, 30, 90, 150, 210].map { point($0, 1) }
        var path = Path()
        if !facets {
            path.addLines(outer)
            path.closeSubpath()
            return path
        }
        let inner = [-90.0, 30, 150].map { point($0, 0.55) }
        path.addLines(inner)
        path.closeSubpath()
        // Each inner corner meets its own outer corner and the two beside it.
        for (corner, outerIndex) in zip(inner, [0, 2, 4]) {
            for offset in [-1, 0, 1] {
                path.move(to: corner)
                path.addLine(to: outer[(outerIndex + offset + 6) % 6])
            }
        }
        return path
    }
}

/// The portrait board in miniature, labelled region by region.
private struct HowToPlayMiniBoard: View {
    private struct Row: Hashable { let label: String; let height: CGFloat }
    private let rows = [Row(label: "Opponents", height: 26), Row(label: "Their battlefield", height: 28),
                        Row(label: "Your battlefield", height: 28), Row(label: "Turn bar", height: 14), Row(label: "Your hand", height: 30)]
    private let spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: spacing) {
                opponentBar.frame(height: rows[0].height)
                cardRow(count: 4, tint: MagicPalette.arcaneBlue).frame(height: rows[1].height)
                cardRow(count: 3, tint: MagicPalette.emerald).frame(height: rows[2].height)
                Text("YOUR TURN · Main 1")
                    .font(.system(size: 7, weight: .black)).foregroundStyle(MagicPalette.antiqueGold)
                    .padding(.horizontal, 6)
                    .frame(height: rows[3].height)
                    .background(MagicPalette.iron.opacity(0.9), in: Capsule())
                hand.frame(height: rows[4].height)
            }
            .padding(8)
            .frame(width: 138)
            .background(LinearGradient(colors: [Color(red: 0.055, green: 0.085, blue: 0.10), Color(red: 0.10, green: 0.16, blue: 0.16)],
                                       startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MagicPalette.antiqueGold.opacity(0.45), lineWidth: 1))
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 5) {
                        Capsule().fill(BrandTheme.ember).frame(width: 10, height: 2)
                        Text(row.label).font(.system(size: 10, weight: .bold)).foregroundStyle(BrandTheme.ink)
                    }
                    .frame(height: row.height, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var opponentBar: some View {
        HStack(spacing: 4) {
            Circle().fill(MagicPalette.arcaneBlue).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text("AI 1").font(.system(size: 6, weight: .bold)).foregroundStyle(MagicPalette.parchment)
                Text("40").font(.system(size: 10, weight: .black)).foregroundStyle(MagicPalette.antiqueGold)
            }
            Spacer(minLength: 0)
            Image(systemName: "person.2.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(MagicPalette.antiqueGold)
                .frame(width: 16, height: 16)
                .background(MagicPalette.iron, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .background(MagicPalette.iron.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BoardTurnColors.opponent.opacity(0.7), lineWidth: 1))
    }

    private func cardRow(count: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in HowToPlayMiniCard(width: 19, tint: tint, outline: MagicPalette.antiqueGold.opacity(0.5)) }
        }
    }

    private var hand: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { card in
                HowToPlayMiniCard(width: 20, tint: [MagicPalette.emerald, MagicPalette.arcaneBlue, BrandTheme.ember, MagicPalette.oxblood, MagicPalette.emerald][card])
                    .rotationEffect(.degrees(Double(card - 2) * 9), anchor: .bottom)
                    .offset(x: CGFloat(card - 2) * 13, y: 3)
            }
        }
    }
}

/// A hand card rising toward the battlefield, the Pay cost tray and a highlighted target.
/// The card drifts up and back unless Reduce Motion is on.
private struct HowToPlayCasting: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(MagicPalette.antiqueGold.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 96, height: 40)
                    .overlay(Text("Battlefield").font(.system(size: 9, weight: .bold)).foregroundStyle(MagicPalette.parchment.opacity(0.7)))
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .black)).foregroundStyle(BrandTheme.ember)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                    HowToPlayMiniCard(width: 44, tint: MagicPalette.emerald, symbol: "leaf.fill")
                        .offset(y: CGFloat(-5 + 5 * cos(t * 2.4)))
                }
                .frame(width: 44, height: 72)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Text("Pay cost").font(.system(size: 9, weight: .black)).foregroundStyle(MagicPalette.antiqueGold)
                    pip("2", fill: Color.gray.opacity(0.55))
                    pip("", fill: Color(red: 0.24, green: 0.6, blue: 0.33))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(MagicPalette.iron.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MagicPalette.antiqueGold.opacity(0.6), lineWidth: 1))
                HStack(spacing: 8) {
                    HowToPlayMiniCard(width: 30, tint: MagicPalette.arcaneBlue, outline: MagicPalette.emerald)
                        .shadow(color: MagicPalette.emerald.opacity(0.8), radius: 6)
                    Image(systemName: "scope").font(.system(size: 16, weight: .bold)).foregroundStyle(MagicPalette.emerald)
                }
            }
        }
    }

    private func pip(_ text: String, fill: Color) -> some View {
        Circle().fill(fill).frame(width: 18, height: 18)
            .overlay(Text(text).font(.system(size: 10, weight: .black)).foregroundStyle(.white))
    }
}

/// A phone outline with a player at its table.
private struct HowToPlayPhone: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(BrandTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BrandTheme.ink.opacity(0.55), lineWidth: 1.5))
            .overlay {
                Image(systemName: "person.crop.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(BrandTheme.ember)
            }
            .overlay(alignment: .top) { Capsule().fill(BrandTheme.ink.opacity(0.4)).frame(width: 14, height: 3).padding(.top, 5) }
            .frame(width: 46, height: 84)
    }
}

#if DEBUG
#Preview("How to play") {
    HowToPlayView()
}
#endif
