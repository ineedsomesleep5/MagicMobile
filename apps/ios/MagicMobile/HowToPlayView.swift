import SwiftUI

/// "How to play" (Caleb, 2026-10-03; Arena's look since 2026-10-22): a chooser of tutorial tiles over card art,
/// each tutorial a run of glass pages with an animated scene built from the table's own pieces (frames, ribbons,
/// medallions, gems, the hourglass). `HowToPlayView()` opens the chooser; `HowToPlayView(tutorialID:)`
/// opens straight into one tutorial, which is how the first-launch walkthrough opens.
struct HowToPlayView: View {
    private let startID: String?
    /// Starts the guided first game (GuidedGame.swift); the chooser offers it when set.
    private let playGuided: (() -> Void)?
    /// Starts a lesson (Lessons.swift); the chooser offers the lessons when set.
    private let playLesson: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.arenaPanelClose) private var panelClose
    /// Closes the Arena menu panel this page is shown in, or the sheet elsewhere.
    private func closePanel() { if let panelClose { panelClose() } else { dismiss() } }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tutorial: HowToPlayTutorial?
    @State private var lessons = false

    init(tutorialID: String? = nil, playGuided: (() -> Void)? = nil, playLesson: ((String) -> Void)? = nil) {
        startID = tutorialID
        self.playGuided = playGuided
        self.playLesson = playLesson
        _tutorial = State(initialValue: HowToPlayText.tutorials.first { $0.id == tutorialID })
    }

    var body: some View {
        ZStack {
            if lessons, let playLesson {
                LessonListView(play: { id in close(); playLesson(id) }, playGuided: playGuided.map { play in { close(); play() } },
                               back: { open(nil) })
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else if let tutorial {
                HowToPlayBook(tutorial: tutorial, backToChooser: startID == nil ? { open(nil) } : nil, close: close)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                HowToPlayChooser(choose: { open($0) }, playGuided: playGuided.map { play in { close(); play() } },
                                 openLessons: playLesson == nil ? nil : { openLessons() }, close: close)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func open(_ next: HowToPlayTutorial?) {
        GameAudio.shared.play(.pageFlip)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { tutorial = next; lessons = false }
    }

    private func openLessons() {
        GameAudio.shared.play(.pageFlip)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { lessons = true }
    }

    private func close() {
        GameAudio.shared.play(.uiClose)
        closePanel()
    }
}

// MARK: - Chooser

/// Arena's Learn page: the tutorials as tiles over card art, side by side when the phone lies sideways (all one height,
/// Begin on one line along their foot) and stacked when it stands; the guided first game first when the menu offers it.
private struct HowToPlayChooser: View {
    let choose: (HowToPlayTutorial) -> Void
    let playGuided: (() -> Void)?
    let openLessons: (() -> Void)?
    let close: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            ArenaPanelHeader(title: HowToPlayText.title, closeIdentifier: "howToPlay.close")
            if verticalSizeClass == .compact {
                // Sideways the tiles share the panel's height, so nothing is left empty under them; at the largest text
                // sizes they scroll instead.
                ViewThatFits(in: .vertical) {
                    HStack(alignment: .top, spacing: 14) { books }
                        .frame(minHeight: 260, maxHeight: .infinity)
                        .padding(16)
                    ScrollView {
                        HStack(alignment: .top, spacing: 14) { books }
                            .padding(16)
                    }
                }
            } else {
                // Upright the three tiles fit the panel; shorter art keeps every Begin in view (the judge, 2026-10-22).
                ScrollView {
                    VStack(spacing: 12) { books }
                        .padding(16)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .mask(ArenaScrollFade(depth: 20))
            }
        }
    }

    @ViewBuilder private var books: some View {
        if let openLessons {
            // The lessons first: short scripted games on the real board, the guided game as their last step.
            book(id: "lessons", title: LessonText.title, subtitle: "", icon: "graduationcap.fill",
                 art: "Grizzly Bears", colors: ["G"], action: HowToPlayText.begin, primary: true, choose: openLessons)
        } else if let playGuided {
            book(id: "guided", title: GuidedGameText.title, subtitle: GuidedGameText.subtitle, icon: "graduationcap.fill",
                 art: "Emmara, Soul of the Accord", colors: ["G", "W"], action: GuidedGameText.start, primary: true, choose: playGuided)
        }
        ForEach(HowToPlayText.tutorials) { tutorial in
            book(id: tutorial.id, title: tutorial.title, subtitle: tutorial.subtitle,
                 icon: tutorial.id == "commander" ? "crown.fill" : "table.furniture",
                 art: tutorial.id == "commander" ? "The Ur-Dragon" : "Teferi, Temporal Archmage",
                 colors: tutorial.id == "commander" ? ["W", "U", "B", "R", "G"] : ["U"],
                 action: HowToPlayText.begin) { choose(tutorial) }
        }
    }

    /// Arena's Learn tiles: a card's art over the title, its plaque at the tile's foot. What it teaches is VoiceOver's
    /// (the judge, 2026-10-22: no descriptions); the guided game is the one ember plaque, the tutorials leather, as Arena
    /// keeps ember for the single primary action.
    private func book(id: String, title: String, subtitle: String, icon: String, art: String, colors: [String], action: String,
                      primary: Bool = false, choose: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: choose) {
            if verticalSizeClass == .compact { sideways(title: title, icon: icon, art: art, colors: colors, action: action, primary: primary) }
            else { upright(title: title, icon: icon, art: art, colors: colors, action: action, primary: primary) }
        }
        .buttonStyle(.plain)
        .background(shape.fill(Color.black.opacity(0.45)))
        .clipShape(shape)
        .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        .contentShape(Rectangle())
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title). \(subtitle)")
        .accessibilityIdentifier("howToPlay.tutorial.\(id)")
    }

    private func emblem(_ icon: String) -> some View {
        ArenaEmblem(symbol: icon, size: 16, lit: true)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.black.opacity(0.7)))
            .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
            .padding(10)
    }

    /// Upright, Arena's way (Caleb, 2026-10-26: the thin strips showed shoulders, not faces, under a gap): the art fills
    /// the tile, sharp and framed on its upper part, with the title and plaque on a shade along its foot.
    private func upright(title: String, icon: String, art: String, colors: [String], action: String, primary: Bool) -> some View {
        ZStack(alignment: .bottom) {
            ArenaArt(name: art, colors: colors, variant: .inspection, focus: 0.3)
                .scaleEffect(1.06)
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .frame(height: 96)
            HStack(alignment: .bottom, spacing: 10) {
                Text(title)
                    .font(ArenaMenuStyle.font(19, .bold))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .shadow(color: .black, radius: 3, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HowToPlayPlaque(text: action, icon: "chevron.right", primary: primary)
            }
            .padding(14)
        }
        .frame(height: 158)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) { emblem(icon) }
        .multilineTextAlignment(.leading)
    }

    private func sideways(title: String, icon: String, art: String, colors: [String], action: String, primary: Bool) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                // Cropped in from every edge, so a printing's frame never shows along the art's border.
                ArenaArt(name: art, colors: colors, variant: .inspection, focus: 0.3)
                    .frame(height: 104)
                    .scaleEffect(1.14)
                    .clipped()
                    .overlay(alignment: .topLeading) { emblem(icon) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(ArenaMenuStyle.font(19, .bold))
                        .foregroundStyle(ArenaMenuStyle.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 10)
                    HStack {
                        Spacer(minLength: 0)
                        HowToPlayPlaque(text: action, icon: "chevron.right", primary: primary)
                    }
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Book

/// One tutorial: its title, swipeable glass pages, gold progress diamonds and the Back, Next and Done plaques. The
/// identifiers match the previous walkthrough's, so its UI tests hold.
private struct HowToPlayBook: View {
    let tutorial: HowToPlayTutorial
    /// Returns to the chooser; nil when the book opened by itself.
    let backToChooser: (() -> Void)?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var index = 0

    private var pages: [HowToPlayPage] { tutorial.pages }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    HowToPlayPageView(tutorialID: tutorial.id, page: page, wide: verticalSizeClass == .compact)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // At least a page's picture and words; it fills the rest of the panel when the panel is taller.
            .frame(minHeight: verticalSizeClass == .compact ? 214 : 460, maxHeight: .infinity)
            footer
        }
        .onChange(of: index) { _, _ in GameAudio.shared.play(.pageFlip) }
    }

    /// The panel's head, as `ArenaPanelHeader` draws it: back to the tutorials, the title in large type, and Skip.
    private var header: some View {
        HStack(spacing: 4) {
            if let backToChooser {
                Button(action: backToChooser) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(ArenaMenuStyle.text)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HowToPlayText.title)
                .accessibilityIdentifier("howToPlay.chooser")
            }
            Text(tutorial.title)
                .font(ArenaMenuStyle.font(22, .bold))
                .foregroundStyle(ArenaMenuStyle.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(HowToPlayText.skip, action: close)
                .buttonStyle(ArenaPillButtonStyle())
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
                .accessibilityHidden(isLast)
                .accessibilityIdentifier("howToPlay.skip")
        }
        .padding(.leading, backToChooser == nil ? 18 : 6)
        .padding(.trailing, 10)
        .padding(.top, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.45) }
    }

    /// The gold diamonds, then Back as the leather plaque and Next (or Done) as the ember one. Sideways the diamonds
    /// sit between the two plaques, so the whole page fits under the top bar (the judge, 2026-10-22: the plaques' rims
    /// were cut by the panel's foot); the row keeps the pages' side insets.
    private var footer: some View {
        let wide = verticalSizeClass == .compact
        return VStack(spacing: 10) {
            if !wide { progress }
            HStack(spacing: 12) {
                backButton
                if wide { progress.fixedSize() }
                forwardButton
            }
        }
        .frame(maxWidth: wide ? .infinity : 560)
        .padding(.horizontal, 20)
        .padding(.top, wide ? 2 : 6)
        .padding(.bottom, 14)
    }

    private var backButton: some View {
        Button { go(-1) } label: { Text(HowToPlayText.back) }
            .buttonStyle(ArenaPlayButtonStyle(cancel: true, fontSize: 17))
            .frame(height: 46)
            .disabled(index == 0)
            .opacity(index == 0 ? 0.5 : 1)
            .accessibilityIdentifier("howToPlay.back")
    }

    @ViewBuilder private var forwardButton: some View {
        if isLast {
            Button(action: close) { Text(HowToPlayText.done) }
                .buttonStyle(ArenaPlayButtonStyle(fontSize: 17))
                .frame(height: 46)
                .accessibilityIdentifier("howToPlay.done")
        } else {
            Button { go(1) } label: { Text(HowToPlayText.next) }
                .buttonStyle(ArenaPlayButtonStyle(fontSize: 17))
                .frame(height: 46)
                .accessibilityIdentifier("howToPlay.next")
        }
    }

    /// Gold diamonds, the current page's lit; VoiceOver hears "Page 3 of 12" and can swipe up or down.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(pages.indices, id: \.self) { page in
                // Gold diamonds, the current page's lit.
                Rectangle()
                    .fill(page == index ? AnyShapeStyle(ArenaMenuStyle.goldFill) : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: page == index ? 8 : 5.5, height: page == index ? 8 : 5.5)
                    .rotationEffect(.degrees(45))
                    .shadow(color: page == index ? ArenaMenuStyle.gold.opacity(0.7) : .clear, radius: 3)
                    .frame(width: 11, height: 11)
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
}

/// One page: the scene in its dark inset, then the title and words on glass. When the words fit, the picture grows into
/// the page's height, so a tall panel is never half empty; at large text sizes the page scrolls, so nothing clips.
private struct HowToPlayPageView: View {
    let tutorialID: String
    let page: HowToPlayPage
    let wide: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            layout(scene: HowToPlayScene(key: "\(tutorialID)/\(page.id)")
                .frame(maxWidth: wide ? 320 : 400)
                .frame(minHeight: wide ? 180 : 210, maxHeight: wide ? .infinity : 340), fills: wide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("howToPlay.page.\(page.id)")
            ScrollView {
                layout(scene: HowToPlayScene(key: "\(tutorialID)/\(page.id)")
                    .frame(maxWidth: wide ? 320 : 380)
                    .frame(height: 210))
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("howToPlay.page.\(page.id)")
        }
    }

    /// `fills`: sideways the words' pane runs the picture's full height, so the two boxes share their top and bottom
    /// edges (the judge, 2026-10-22).
    private func layout<Picture: View>(scene: Picture, fills: Bool = false) -> some View {
        let stack = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 22))
            : AnyLayout(VStackLayout(alignment: .center, spacing: 16))
        return stack {
            scene
            VStack(alignment: wide ? .leading : .center, spacing: 8) {
                Text(page.title)
                    .font(ArenaMenuStyle.font(23, .bold))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .accessibilityAddTraits(.isHeader)
                Text(page.body)
                    .font(ArenaMenuStyle.font(16, .medium))
                    .lineSpacing(3)
                    .foregroundStyle(ArenaMenuStyle.text.opacity(0.82))
            }
            .multilineTextAlignment(wide ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: 480, maxHeight: fills ? .infinity : nil, alignment: wide ? .leading : .center)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, wide ? 10 : 14)
    }
}

// MARK: - Scenes

/// Seconds since the scene appeared, looping scenes on one clock. With Reduce Motion the clock
/// holds at one second, a representative still.
private struct HowToPlayClock<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            content(reduceMotion ? 1 : timeline.date.timeIntervalSince(start))
        }
    }
}

/// The lesson's picture in a leather inset. Decorative: the words say the same, so VoiceOver
/// skips it, and its type stays fixed so it never grows out of its frame.
private struct HowToPlayScene: View {
    let key: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.12, blue: 0.14), Color(red: 0.05, green: 0.05, blue: 0.06)], startPoint: .top, endPoint: .bottom)
                .overlay(RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 40, endRadius: 260))
            drawing
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        .environment(\.dynamicTypeSize, .large)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var drawing: some View {
        switch key {
        case "table/welcome": HowToPlayWelcomeScene()
        case "table/decks": HowToPlayDecksScene()
        case "table/start": HowToPlayStartScene()
        case "table/board": HowToPlayTableScene()
        case "table/casting": HowToPlayCastScene()
        case "table/glow": HowToPlayGlowScene()
        case "table/priority": HowToPlayPriorityScene()
        case "table/combat": HowToPlayCombatScene(keywords: false)
        case "table/piles": HowToPlayPileScene()
        case "table/reading": HowToPlayReadingScene()
        case "table/resume": HowToPlayResumeScene()
        case "table/friends": HowToPlayFriendsScene()
        case "commander/format": HowToPlayFormatScene()
        case "commander/commander": HowToPlayCommanderScene()
        case "commander/colors": HowToPlayColorsScene()
        case "commander/turn": HowToPlayTurnScene()
        case "commander/mana": HowToPlayManaScene()
        case "commander/stack": HowToPlayStackScene()
        case "commander/combat": HowToPlayCombatScene(keywords: true)
        case "commander/permanents": HowToPlayPermanentsScene()
        case "commander/winning": HowToPlayWinningScene()
        default: EmptyView()
        }
    }
}

// MARK: Pieces

/// A framed battlefield tile as the lessons draw it: the real painted frame of its kind over a
/// coloured art wash, a name on the parchment ribbon, so the lesson shows the real thing.
struct HowToPlayTile: View {
    var kind: TavernFrameKind = .creature
    var name: String? = nil
    var tint: Color = Color(red: 0.22, green: 0.40, blue: 0.30)
    var width: CGFloat = 56
    var symbol: String = "sparkle"

    var body: some View {
        let height = width * 1.08
        ZStack(alignment: .topLeading) {
            if let frame = kind.image {
                let window = kind.window
                LinearGradient(colors: [tint, tint.opacity(0.5), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .overlay {
                        Image(systemName: symbol).font(.system(size: width * 0.24, weight: .light))
                            .foregroundStyle(ArenaMenuStyle.gold).opacity(0.75)
                    }
                    .frame(width: width * window.width, height: height * window.height)
                    .offset(x: width * window.minX, y: height * window.minY)
                Image(uiImage: frame).resizable().interpolation(.high).frame(width: width, height: height)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(tint)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .overlay(alignment: .top) {
            if let name, let ribbon = TavernCardParts.ribbon {
                let ribbonHeight = width * TavernCardParts.ribbonAspect
                ZStack {
                    Image(uiImage: ribbon).resizable().interpolation(.high)
                    Text(name)
                        .font(.system(size: max(7, width * 0.105), weight: .bold, design: .serif))
                        .foregroundStyle(ArenaGlass.text)
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .frame(width: width * 0.62)
                        .offset(y: -ribbonHeight * 0.06)
                }
                .frame(width: width, height: ribbonHeight)
                .offset(y: height * TavernFrameKind.ribbonCenterY - ribbonHeight / 2)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}

/// A player's medallion as the Arena board draws it: an initial on dark glass in a thin gold ring, life on a dark oval
/// below.
struct HowToPlayMedallion: View {
    var label = "A"
    var life: Int? = 40
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.20, green: 0.21, blue: 0.25), Color(red: 0.06, green: 0.06, blue: 0.08)],
                                         center: .init(x: 0.4, y: 0.3), startRadius: 0, endRadius: size / 2))
            Text(label)
                .font(ArenaMenuStyle.title(size * 0.42, .bold))
                .foregroundStyle(ArenaGlass.text)
            Circle().strokeBorder(ArenaMenuStyle.gold.opacity(0.8), lineWidth: max(1, size * 0.04))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            if let life { ArenaCountBadge(count: life, size: size * 0.42).offset(y: size * 0.2) }
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}

/// The hourglass pass button's painted face.
struct HowToPlayHourglass: View {
    var size: CGFloat = 60
    var body: some View {
        Group {
            if let image = UIImage(named: "tavern-hourglass-button") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Circle().fill(BrandTheme.ember)
                    .overlay(Image(systemName: "hourglass").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white))
                    .overlay(Circle().strokeBorder(BrandTheme.brassGradient, lineWidth: 3))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }
}

/// A button as a label: Arena's orange pill, or its dark glass one.
struct HowToPlayPlaque: View {
    let text: String
    var icon: String? = nil
    var primary = true

    var body: some View {
        ArenaButtonFace(label: HStack(spacing: 5) {
                            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .black)) }
                            Text(text)
                        },
                        kind: primary ? .primary : .secondary, font: ArenaMenuStyle.title(13, .bold), fills: false, inset: 8, glow: 0.5)
            .allowsHitTesting(false)
    }
}

/// A name plate on its own, the banner under a showcased spell: light serif on dark glass in a gold hairline.
private struct HowToPlayRibbon: View {
    let text: String
    var width: CGFloat = 120
    var body: some View {
        Text(text)
            .font(ArenaMenuStyle.title(width * 0.095, .bold))
            .foregroundStyle(ArenaGlass.text)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: width * 0.84, height: width * 0.2)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}

/// A finger's touch: a brass ring that swells and fades.
private struct HowToPlayTouch: View {
    let phase: Double
    var body: some View {
        let p = max(0, min(1, phase))
        Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
            .frame(width: 18 + 26 * p, height: 18 + 26 * p)
            .opacity(1 - p)
    }
}

private func loop(_ t: Double, _ period: Double) -> Double { t.truncatingRemainder(dividingBy: period) }
private func breath(_ t: Double, _ speed: Double = 2.4) -> Double { 0.5 + 0.5 * sin(t * speed) }

// MARK: Table scenes

private struct HowToPlayWelcomeScene: View {
    var body: some View {
        HowToPlayClock { t in
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(BrandTheme.ember.opacity(0.18 + 0.12 * breath(t, 1.6)))
                        .frame(width: 130, height: 130).blur(radius: 16)
                    if let mark = UIImage(named: "LaunchMark") {
                        Image(uiImage: mark).resizable().scaledToFit().frame(width: 96, height: 96)
                    } else {
                        BrandMark(size: 84)
                    }
                }
                HStack(spacing: 8) {
                    TavernTag(text: "COMMANDER")
                    TavernTag(text: "RULES BY XMAGE")
                }
            }
        }
    }
}

private struct HowToPlayDecksScene: View {
    var body: some View {
        HStack(spacing: 18) {
            HowToPlayTile(kind: .creature, name: "Emmara", tint: Color(red: 0.2, green: 0.45, blue: 0.28), width: 78, symbol: "crown.fill")
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR DECK").font(ArenaMenuStyle.font(9, .heavy)).tracking(2)
                        .foregroundStyle(Color(red: 0.62, green: 0.16, blue: 0.08))
                    Text("Token Triumph").font(.system(size: 17, weight: .black, design: .serif)).foregroundStyle(ArenaGlass.text)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .modifier(HowToPlayGlass(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                TavernTag(text: "PLAYING", leather: true)
                HowToPlayPlaque(text: DeckStudioPlayText.play, icon: "play.fill")
            }
        }
    }
}

private struct HowToPlayStartScene: View {
    var body: some View {
        HowToPlayClock { t in
            let roll = loop(t, 3.2)
            HStack(spacing: 24) {
                HowToPlayD20(size: 78)
                    .rotationEffect(.degrees(roll < 1 ? sin(roll * 18) * 14 * (1 - roll) : 0))
                VStack(spacing: 14) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { card in
                            HowToPlayTile(kind: [.creature, .land, .artifact][card],
                                          tint: [Color(red: 0.2, green: 0.4, blue: 0.3), Color(red: 0.3, green: 0.3, blue: 0.3), Color(red: 0.45, green: 0.3, blue: 0.2)][card],
                                          width: 40)
                                .rotationEffect(.degrees(Double(card - 1) * 12), anchor: .bottom)
                                .offset(x: CGFloat(card - 1) * 18)
                        }
                    }
                    .frame(height: 60)
                    HStack(spacing: 6) {
                        HowToPlayPlaque(text: "Mulligan", primary: false)
                        HowToPlayPlaque(text: "Keep")
                    }
                }
            }
        }
    }
}

/// The table in miniature, a brass ring pointing out each part in turn.
private struct HowToPlayTableScene: View {
    private let callouts = ["Opponent", "The mat", "Your hand", "Turn plate", "Hourglass"]

    var body: some View {
        HowToPlayClock { t in
            let step = Int(loop(t, Double(callouts.count) * 1.5) / 1.5)
            HStack(spacing: 14) {
                ZStack {
                    HowToPlayTable()
                    VStack(spacing: 6) {
                        HStack {
                            HowToPlayMedallion(label: "A", life: 40, size: 30).padding(.leading, 4)
                            Spacer()
                            TavernTag(text: "TURN 3", leather: true)
                        }
                        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in HowToPlayTile(width: 22) } }
                        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in HowToPlayTile(kind: .artifact, tint: Color(red: 0.4, green: 0.3, blue: 0.2), width: 22) } }
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom) {
                            HowToPlayMedallion(label: "Y", life: 37, size: 30).padding(.leading, 4)
                            Spacer()
                            ZStack {
                                ForEach(0..<4, id: \.self) { card in
                                    HowToPlayTile(kind: .land, tint: Color(red: 0.2, green: 0.3, blue: 0.4), width: 18)
                                        .rotationEffect(.degrees(Double(card) * 8 - 12), anchor: .bottom)
                                        .offset(x: CGFloat(card) * 9 - 14)
                                }
                            }
                            Spacer()
                            HowToPlayHourglass(size: 30).padding(.trailing, 4)
                        }
                        .padding(.bottom, 6)
                    }
                    .padding(6)
                    calloutRing(step)
                }
                .frame(width: 150, height: 190)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(callouts.enumerated()), id: \.offset) { offset, label in
                        HStack(spacing: 6) {
                            Circle().fill(offset == step ? AnyShapeStyle(ArenaMenuStyle.orange) : AnyShapeStyle(Color.black.opacity(0.4)))
                                .frame(width: 8, height: 8)
                            Text(label).font(.system(size: 12, weight: offset == step ? .black : .semibold, design: .serif))
                                .foregroundStyle(ArenaGlass.text.opacity(offset == step ? 1 : 0.6))
                        }
                    }
                }
            }
        }
    }

    private func calloutRing(_ step: Int) -> some View {
        let frames: [CGRect] = [CGRect(x: 4, y: 4, width: 40, height: 40), CGRect(x: 10, y: 48, width: 130, height: 76),
                                CGRect(x: 48, y: 140, width: 56, height: 46), CGRect(x: 92, y: 8, width: 54, height: 26),
                                CGRect(x: 106, y: 142, width: 40, height: 40)]
        let frame = frames[min(step, frames.count - 1)]
        return RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
            .shadow(color: ArenaMenuStyle.gold.opacity(0.8), radius: 4)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(.easeInOut(duration: 0.35), value: step)
    }
}

/// A hand card rises to the centre, hangs in its colour's light with its ribbon, then goes.
private struct HowToPlayCastScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 3.4)
            let rise = min(1, p / 0.7)
            let lift = 1 - pow(1 - rise, 3)
            let fade = p > 2.8 ? max(0, 1 - (p - 2.8) / 0.6) : 1
            let glow = p > 0.6 ? min(1, (p - 0.6) / 0.4) * fade : 0
            HStack(spacing: 22) {
                ZStack {
                    HowToPlayTile(kind: .creature, name: "Serra Angel", tint: Color(red: 0.75, green: 0.7, blue: 0.5), width: 70, symbol: "sparkles")
                        .background { TavernTileGlow(color: Color(red: 1, green: 0.95, blue: 0.78)).opacity(glow) }
                        .scaleEffect(0.55 + 0.45 * lift)
                        .offset(y: 70 - 90 * lift)
                        .opacity(fade)
                    HowToPlayRibbon(text: "Serra Angel", width: 110)
                        .offset(y: 62)
                        .opacity(glow)
                }
                .frame(width: 130, height: 190)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        TavernTag(text: "PAY COST")
                        TavernManaGemFace(symbol: "W", count: 1, diameter: 22)
                        TavernManaGemFace(symbol: "W", count: 0, diameter: 22)
                        TavernGenericGem(value: 3)
                    }
                    HStack(spacing: 8) {
                        HowToPlayTile(kind: .land, tint: Color(red: 0.35, green: 0.33, blue: 0.3), width: 34)
                            .rotationEffect(.degrees(p > 1.2 ? 90 : 0))
                            .animation(.easeOut(duration: 0.3), value: p > 1.2)
                        Image(systemName: "hand.tap.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold)
                        Text("tap a land").font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaGlass.text.opacity(0.8))
                    }
                }
            }
        }
    }
}

private struct HowToPlayGlowScene: View {
    var body: some View {
        HowToPlayClock { t in
            let b = breath(t)
            HStack(spacing: 18) {
                VStack(spacing: 8) {
                    HowToPlayTile(kind: .creature, width: 56)
                        .background { TavernTileGlow(color: Color(red: 0.3, green: 0.95, blue: 0.45), strength: 0.7 + 0.3 * b) }
                    TavernTag(text: "PLAY", leather: true)
                }
                VStack(spacing: 8) {
                    HowToPlayTile(kind: .creature, tint: Color(red: 0.45, green: 0.2, blue: 0.2), width: 56)
                        .background { TavernTileGlow(color: .red, strength: 0.7 + 0.3 * b) }
                    TavernTag(text: "TARGET", leather: true)
                }
                VStack(spacing: 8) {
                    HowToPlayTile(kind: .artifact, tint: Color(red: 0.4, green: 0.3, blue: 0.2), width: 56)
                        .saturation(0.3).brightness(-0.12)
                        .rotationEffect(.degrees(90))
                        .frame(width: 60, height: 60)
                    TavernTag(text: "TAPPED", leather: true)
                }
            }
        }
    }
}

/// The hourglass turns over on a tap; the skip ring waits beside it.
private struct HowToPlayPriorityScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 3)
            let turn = p < 0.6 ? 0.0 : min(1, (p - 0.6) / 0.6)
            HStack(spacing: 26) {
                ZStack {
                    HowToPlayHourglass(size: 84)
                        .rotation3DEffect(.degrees(180 * (1 - pow(1 - turn, 2))), axis: (x: 0, y: 1, z: 0))
                    if p < 0.6 { HowToPlayTouch(phase: p / 0.6) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    TavernTag(text: "PASS PRIORITY")
                    HStack(spacing: 8) {
                        Image(systemName: "forward.end.fill").modifier(TavernRingLabel())
                        Text("Skip").font(ArenaMenuStyle.font(13, .bold)).foregroundStyle(ArenaGlass.text)
                    }
                    TavernStackTray(count: 1, topName: "Counterspell", open: {}, width: 124)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// An attacker lunges in its red light; a blocker steps into its way. The format's lesson
/// adds the flying and reach badges.
private struct HowToPlayCombatScene: View {
    let keywords: Bool

    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 3)
            let lunge = p < 1 ? 0.0 : p < 1.5 ? (p - 1) / 0.5 : p < 2.4 ? 1 : max(0, 1 - (p - 2.4) / 0.6)
            VStack(spacing: 10) {
                HStack(spacing: 40) {
                    VStack(spacing: 6) {
                        if keywords { TavernTag(text: "FLYING", leather: true) }
                        HowToPlayTile(kind: .creature, name: "Attacker", tint: Color(red: 0.5, green: 0.18, blue: 0.15), width: 58, symbol: "bolt.fill")
                            .background { TavernTileGlow(color: .red).opacity(lunge) }
                            .offset(y: 16 * lunge)
                    }
                    VStack(spacing: 6) {
                        if keywords { TavernTag(text: "REACH", leather: true) }
                        HowToPlayTile(kind: .creature, name: "Blocker", tint: Color(red: 0.2, green: 0.35, blue: 0.5), width: 58, symbol: "shield.fill")
                            .offset(y: -10 * lunge)
                    }
                }
                HStack(spacing: 8) {
                    HowToPlayPlaque(text: HowToPlayText.back, primary: false)
                    HowToPlayPlaque(text: keywords ? "Done Blocking" : "Done Attacking")
                }
            }
        }
    }
}

private struct HowToPlayPileScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 2.6)
            let spread = p < 1.2 ? 0.0 : min(1, (p - 1.2) / 0.5)
            HStack(spacing: 30) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        ForEach(0..<4, id: \.self) { card in
                            HowToPlayTile(kind: .token, name: "Soldier", tint: Color(red: 0.75, green: 0.68, blue: 0.5), width: 54)
                                .offset(x: CGFloat(card) * (4 + 18 * spread), y: CGFloat(-card) * (3 - 3 * spread))
                        }
                    }
                    ArenaCountBadge(count: 9, size: 24).offset(x: 10, y: 8).opacity(1 - spread)
                    if p < 1.2 { HowToPlayTouch(phase: p / 1.2).offset(x: -20, y: -20) }
                }
                .frame(width: 120, height: 80)
                VStack(alignment: .leading, spacing: 8) {
                    TavernTag(text: "TAP · NEXT", leather: true)
                    TavernTag(text: "HOLD · SPREAD", leather: true)
                }
            }
        }
    }
}

private struct HowToPlayReadingScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 2.4)
            HStack(spacing: 18) {
                ZStack {
                    HowToPlayTile(kind: .enchantment, name: "Rhystic Study", tint: Color(red: 0.2, green: 0.3, blue: 0.5), width: 84, symbol: "eye.fill")
                        .scaleEffect(p > 1 ? 1.08 : 1)
                        .animation(.easeOut(duration: 0.25), value: p > 1)
                    if p < 1 { HowToPlayTouch(phase: p) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "text.book.closed")
                        Text("GAME LOG").tracking(1.6)
                    }
                    .font(ArenaMenuStyle.font(9, .heavy))
                    .foregroundStyle(Color(red: 0.62, green: 0.16, blue: 0.08))
                    ForEach([96, 70, 84, 58], id: \.self) { width in
                        HStack(spacing: 5) {
                            Circle().fill(ArenaMenuStyle.gold).frame(width: 5, height: 5)
                            Capsule().fill(ArenaGlass.text.opacity(0.35)).frame(width: CGFloat(width), height: 5)
                        }
                    }
                }
                .padding(10)
                .modifier(HowToPlayGlass(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            }
        }
    }
}

private struct HowToPlayResumeScene: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HowToPlayHourglass(size: 44)
                Text("10 min").font(.system(size: 26, weight: .black, design: .serif)).foregroundStyle(ArenaGlass.text)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(GameResumeText.promptTitle).font(ArenaMenuStyle.font(13, .heavy)).foregroundStyle(ArenaGlass.text)
                HStack(spacing: 6) {
                    HowToPlayPlaque(text: GameResumeText.resume, icon: "play.fill")
                    HowToPlayPlaque(text: GameResumeText.abandon, primary: false)
                }
            }
            .padding(12)
            .modifier(HowToPlayGlass(cornerRadius: 12))
        }
    }
}

private struct HowToPlayFriendsScene: View {
    var body: some View {
        HStack(spacing: 14) {
            phone("Y")
            VStack(spacing: 6) {
                Text("TABLE CODE").font(ArenaMenuStyle.font(8, .heavy)).tracking(1.4)
                    .foregroundStyle(Color(red: 0.62, green: 0.16, blue: 0.08))
                Text("K7Q 2MX").font(.system(size: 19, weight: .black, design: .monospaced)).foregroundStyle(ArenaGlass.text)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .modifier(HowToPlayGlass(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            .overlay(alignment: .bottom) { TavernTag(text: "ONLINE", leather: true).offset(y: 16) }
            phone("A")
        }
    }

    private func phone(_ label: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.black.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            .overlay { HowToPlayMedallion(label: label, life: nil, size: 30) }
            .frame(width: 48, height: 86)
    }
}

// MARK: Commander scenes

private struct HowToPlayFormatScene: View {
    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                HowToPlayTable()
                    .frame(width: 96, height: 96)
                HowToPlayMedallion(label: "A", life: nil, size: 30).offset(y: -58)
                HowToPlayMedallion(label: "B", life: nil, size: 30).offset(x: 62)
                HowToPlayMedallion(label: "C", life: nil, size: 30).offset(y: 58)
                HowToPlayMedallion(label: "Y", life: nil, size: 30).offset(x: -62)
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) { ArenaCountBadge(count: 100, size: 30); Text("cards, one of each").serifNote() }
                HStack(spacing: 8) { ArenaCountBadge(count: 40, size: 30); Text("life each").serifNote() }
                HStack(spacing: 8) { Image(systemName: "crown.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold).frame(width: 30); Text("a legendary leader").serifNote() }
            }
        }
    }
}

/// The commander rises from the command zone; each recast adds two to its cost.
private struct HowToPlayCommanderScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 4)
            let rise = min(1, p / 0.8)
            let lift = 1 - pow(1 - rise, 3)
            let casts = min(2, Int(p / 1.5))
            HStack(spacing: 26) {
                ZStack {
                    TavernCommanderReadyGlow(diameter: 50).opacity(p < 0.5 ? 1 : 0)
                    HowToPlayMedallion(label: "Y", life: nil, size: 50)
                    HowToPlayTile(kind: .creature, name: "Commander", tint: Color(red: 0.55, green: 0.42, blue: 0.2), width: 60, symbol: "crown.fill")
                        .scaleEffect(0.4 + 0.6 * lift)
                        .offset(y: -8 - 74 * lift)
                        .opacity(min(1, rise * 3))
                }
                .frame(width: 90, height: 190)
                VStack(alignment: .leading, spacing: 10) {
                    TavernTag(text: "COMMAND ZONE")
                    HStack(spacing: 6) {
                        TavernGenericGem(value: 3)
                        ForEach(0..<casts, id: \.self) { _ in
                            Text("+2").font(ArenaMenuStyle.font(13, .black)).foregroundStyle(ArenaGlass.text)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: casts)
                    Text("the commander tax").serifNote()
                }
            }
        }
    }
}

private struct HowToPlayColorsScene: View {
    var body: some View {
        VStack(spacing: 16) {
            HowToPlayTile(kind: .creature, name: "Emmara", tint: Color(red: 0.2, green: 0.45, blue: 0.28), width: 64, symbol: "crown.fill")
            HStack(spacing: 10) {
                ForEach(["W", "U", "B", "R", "G"], id: \.self) { symbol in
                    let lit = symbol == "G" || symbol == "W"
                    TavernManaGemFace(symbol: symbol, count: lit ? 1 : 0, diameter: 28)
                        .opacity(lit ? 1 : 0.4)
                }
            }
            TavernTag(text: "GREEN AND WHITE ONLY", leather: true)
        }
    }
}

private struct HowToPlayTurnScene: View {
    private let steps = ["UNTAP", "DRAW", "MAIN 1", "COMBAT", "MAIN 2", "END"]

    var body: some View {
        HowToPlayClock { t in
            let current = Int(loop(t, Double(steps.count) * 1.1) / 1.1)
            VStack(spacing: 14) {
                TavernPhasePlate(step: ["untap", "draw", "precombat-main", "combat", "postcombat-main", "end"][current], turn: 3, width: 140)
                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                        TavernTag(text: step, leather: offset != current)
                            .scaleEffect(offset == current ? 1.08 : 0.92)
                            .animation(.easeOut(duration: 0.25), value: current)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 12, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold)
                    Text("then the player on your left").serifNote()
                }
            }
        }
    }
}

/// Three lands tap one after another and the rail's gems light up.
private struct HowToPlayManaScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 3.6)
            let tapped = min(3, Int(p / 0.7))
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { index in
                        HowToPlayTile(kind: .land, name: index == 2 ? "Plains" : "Forest",
                                      tint: index == 2 ? Color(red: 0.6, green: 0.55, blue: 0.4) : Color(red: 0.2, green: 0.4, blue: 0.25), width: 46)
                            .rotationEffect(.degrees(index < tapped ? 90 : 0))
                            .animation(.easeOut(duration: 0.3), value: tapped)
                            .frame(width: 54, height: 54)
                    }
                }
                HStack(spacing: 8) {
                    TavernManaGemFace(symbol: "G", count: min(2, tapped), diameter: 26)
                    TavernManaGemFace(symbol: "W", count: tapped > 2 ? 1 : 0, diameter: 26)
                    TavernGenericGem(value: 2)
                    Text("= a 3-mana spell").serifNote()
                }
            }
        }
    }
}

/// Spells pile onto the stack and the last one in resolves first.
private struct HowToPlayStackScene: View {
    private let names = ["Giant Growth", "Lightning Bolt", "Counterspell"]

    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 4.2)
            let shown = min(3, Int(p / 0.8) + 1)
            let resolving = p > 2.8
            HStack(spacing: 24) {
                ZStack(alignment: .bottom) {
                    ForEach(0..<shown, id: \.self) { index in
                        HowToPlayRibbon(text: names[index], width: 128)
                            .offset(y: CGFloat(-index) * 30)
                            .opacity(resolving && index == shown - 1 ? max(0, 1 - (p - 2.8) / 0.6) : 1)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.3), value: shown)
                .frame(width: 130, height: 120, alignment: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    TavernTag(text: "LAST IN", leather: true)
                    Image(systemName: "arrow.down").font(.system(size: 12, weight: .black)).foregroundStyle(ArenaMenuStyle.gold)
                    TavernTag(text: "FIRST OUT", leather: true)
                }
            }
        }
    }
}

private struct HowToPlayPermanentsScene: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                HowToPlayTile(kind: .creature, width: 50)
                    .overlay(alignment: .bottom) {
                        Image(systemName: "hourglass").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.86, blue: 0.56)).shadow(color: .black, radius: 1).offset(y: 4)
                    }
                HowToPlayTile(kind: .artifact, tint: Color(red: 0.4, green: 0.3, blue: 0.2), width: 50)
                HowToPlayTile(kind: .enchantment, tint: Color(red: 0.4, green: 0.25, blue: 0.4), width: 50)
                HowToPlayTile(kind: .land, tint: Color(red: 0.3, green: 0.32, blue: 0.3), width: 50)
            }
            HStack(spacing: 6) {
                ForEach(["CREATURE", "ARTIFACT", "ENCHANTMENT", "LAND"], id: \.self) { TavernTag(text: $0, leather: true) }
            }
            HStack(spacing: 6) {
                Image(systemName: "hourglass").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.86, blue: 0.56))
                Text("summoning sick this turn").serifNote()
            }
        }
    }
}

private struct HowToPlayWinningScene: View {
    var body: some View {
        HowToPlayClock { t in
            let p = loop(t, 3)
            let life = max(0, 40 - Int(p / 2.2 * 40))
            HStack(spacing: 22) {
                HowToPlayMedallion(label: "A", life: life, size: 56)
                    .opacity(life == 0 ? 0.45 : 1)
                    .saturation(life == 0 ? 0.2 : 1)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) { ArenaCountBadge(count: 0, size: 26); Text("life").serifNote() }
                    HStack(spacing: 8) {
                        Image(systemName: "drop.triangle.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.4)).frame(width: 26)
                        Text("10 poison").serifNote()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold).frame(width: 26)
                        Text("21 from one commander").serifNote()
                    }
                }
            }
        }
    }
}

private extension Text {
    /// A short note beside a scene's piece, in parchment serif.
    func serifNote() -> some View {
        font(ArenaMenuStyle.font(12, .semibold)).foregroundStyle(ArenaGlass.text.opacity(0.9))
    }
}

/// A D20 seen face-on in brass: a hexagon with the center face and its edges.
struct HowToPlayD20: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            HowToPlayD20Shape(facets: false).fill(BrandTheme.brassGradient)
            HowToPlayD20Shape(facets: true).stroke(Color(red: 0.35, green: 0.2, blue: 0.06).opacity(0.6), lineWidth: 1.5)
            HowToPlayD20Shape(facets: false).stroke(Color.white.opacity(0.3), lineWidth: 1)
            Text("20").font(.system(size: size * 0.24, weight: .black, design: .serif)).foregroundStyle(Color(red: 0.3, green: 0.16, blue: 0.05))
                .offset(y: size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: TavernPalette.brass.opacity(0.4), radius: 10)
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

#if DEBUG
#Preview("How to play") {
    HowToPlayView()
}
#endif

/// A note or a card in a lesson: dark glass in the gold hairline (the Arena menus' look), where the tavern had parchment.
private struct HowToPlayGlass: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
    }
}

/// The table in a lesson: the Arena board's own surface, in its glass edge.
private struct HowToPlayTable: View {
    var body: some View {
        Group {
            if let table = UIImage(named: "tavern-arena-portrait") {
                Image(uiImage: table).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.22, green: 0.16, blue: 0.11), Color(red: 0.10, green: 0.07, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
    }
}
