import SwiftUI

/// One page of the home page's featured panel.
struct ArenaFeature: Identifiable {
    let id: String
    let kicker: String
    let title: String
    let detail: String
    /// A card whose art fills the panel.
    let art: String
    var colors: [String] = []
    let action: () -> Void
}

/// One of the tiles beside the featured panel.
struct ArenaHomeTile: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let art: String
    var colors: [String] = []
    let action: () -> Void
}

/// What the home page shows.
struct ArenaHomeContent {
    var features: [ArenaFeature]
    var tiles: [ArenaHomeTile]
    var deck: ArenaDeckBoxModel?
    var rank: RankPosition
    var wins: Int
    var losses: Int
    var friendsOnline: Int
    var unread: Bool
    let play: () -> Void
    let friends: () -> Void
    let updates: () -> Void
    let downloads: () -> Void
    let openDeck: () -> Void
    let openRank: () -> Void
}

/// The home page in Arena's layout over the 3D tavern room (Caleb, 2026-10-22: keep the room, follow Arena): a
/// featured panel and three tiles in the middle, progress medallions on a rail under them, friends in the lower left and
/// the Play plaque in the lower right. Nothing scrolls.
struct ArenaHomeView: View {
    let content: ArenaHomeContent
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            if compact { portrait(proxy.size) } else { landscape(proxy.size) }
        }
    }

    // MARK: Layouts

    private func landscape(_ size: CGSize) -> some View {
        let bottom: CGFloat = 64
        let blockHeight = min(250, max(170, size.height - bottom - 30))
        let featureWidth = min(480, (size.width - 40) * 0.62)
        let tilesWidth = min(270, size.width - 40 - featureWidth - 10)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ArenaFeaturePanel(features: content.features)
                    .frame(width: featureWidth, height: blockHeight)
                VStack(spacing: 8) {
                    ForEach(content.tiles) { tile in
                        ArenaHomeTileView(tile: tile, wide: false)
                    }
                }
                .frame(width: tilesWidth, height: blockHeight)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 12) {
                corner
                Spacer(minLength: 0)
                ArenaProgressRail(content: content, compact: false)
                Spacer(minLength: 0)
                playButton(width: 176, height: 44)
            }
            .frame(height: bottom)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func portrait(_ size: CGSize) -> some View {
        let featureHeight = min(320, size.height * 0.38)
        let tileHeight = min(96, max(70, (size.height - featureHeight - 230) / 3))
        return VStack(spacing: 0) {
            ArenaFeaturePanel(features: content.features)
                .frame(height: featureHeight)
                .padding(.top, 14)
            VStack(spacing: 8) {
                ForEach(content.tiles) { tile in
                    ArenaHomeTileView(tile: tile, wide: true).frame(height: tileHeight)
                }
            }
            .padding(.top, 10)
            Spacer(minLength: 10)
            ArenaProgressRail(content: content, compact: true)
            Spacer(minLength: 10)
            HStack(alignment: .center) {
                corner
                Spacer(minLength: 8)
                playButton(width: 190, height: 50)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
    }

    /// Friends, and in portrait news and downloads (the top bar has no room for them there).
    private var corner: some View {
        HStack(spacing: 4) {
            ArenaCornerButton(symbol: "person.2.fill", title: String(localized: "Friends"),
                              badge: content.friendsOnline > 0 ? "\(content.friendsOnline)" : nil, unread: content.unread,
                              identifier: "menu.social", action: content.friends)
            if compact {
                ArenaCornerButton(symbol: "newspaper.fill", title: String(localized: "Updates"), identifier: "menu.updates",
                                  action: content.updates)
                ArenaCornerButton(symbol: "arrow.down.circle.fill", title: String(localized: "Downloads"), identifier: "menu.downloads",
                                  action: content.downloads)
            }
        }
    }

    private func playButton(width: CGFloat, height: CGFloat) -> some View {
        Button {
            GameAudio.shared.play(.menuPlay)
            content.play()
        } label: {
            Text(String(localized: "Play"))
        }
        .buttonStyle(ArenaPlayButtonStyle(fontSize: compact ? 23 : 21))
        .frame(width: width, height: height)
        .accessibilityIdentifier("menu.play")
    }
}

// MARK: - Featured panel

/// The big panel: one feature at a time over its card's art, arrows and dots to move between them, and a slow turn on
/// its own.
struct ArenaFeaturePanel: View {
    let features: [ArenaFeature]
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAmbientMotion) private var ambient

    var body: some View {
        let feature = features.isEmpty ? nil : features[min(index, features.count - 1)]
        ZStack(alignment: .bottomLeading) {
            if let feature {
                Button {
                    GameAudio.shared.play(.uiOpen)
                    feature.action()
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        ArenaArt(name: feature.art, colors: feature.colors)
                            .id(feature.id)
                            .transition(.opacity)
                        // A dark band only behind the words: the art stays crisp above it.
                        LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.88), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 4) {
                            ArenaCaps(text: feature.kicker)
                            Text(feature.title).font(ArenaMenuStyle.font(20, .bold)).foregroundStyle(ArenaMenuStyle.text)
                                .shadow(color: .black, radius: 3)
                                .lineLimit(2).minimumScaleFactor(0.8)
                            Text(feature.detail).font(ArenaMenuStyle.font(12.5, .medium)).foregroundStyle(ArenaMenuStyle.text.opacity(0.85))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(BrandPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.feature.\(feature.id)")
                .accessibilityHint(String(localized: "Opens it"))
            }
            if features.count > 1 { controls }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.width < -40 { step(1) } else if value.translation.width > 40 { step(-1) }
        })
        .task(id: index) {
            guard features.count > 1, !reduceMotion, ambient else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            step(1)
        }
    }

    private var controls: some View {
        ZStack {
            HStack {
                arrow("chevron.left", String(localized: "Previous")) { step(-1) }
                Spacer()
                arrow("chevron.right", String(localized: "Next")) { step(1) }
            }
            VStack {
                Spacer()
                HStack(spacing: 5) {
                    ForEach(features.indices, id: \.self) { i in
                        Circle().fill(i == index ? Color.white : Color.white.opacity(0.35)).frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            }
        }
    }

    private func arrow(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black, radius: 3)
                .frame(width: 44, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int) {
        guard !features.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            index = (index + delta + features.count) % features.count
        }
    }
}

/// A tile: crisp art with the title and a gold line on a dark band at the bottom.
struct ArenaHomeTileView: View {
    let tile: ArenaHomeTile
    let wide: Bool

    var body: some View {
        Button {
            GameAudio.shared.play(.uiOpen)
            tile.action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArenaArt(name: tile.art, colors: tile.colors)
                LinearGradient(stops: [.init(color: .clear, location: wide ? 0.35 : 0.3), .init(color: .black.opacity(0.85), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title).font(ArenaMenuStyle.font(wide ? 17 : 15, .bold)).foregroundStyle(ArenaMenuStyle.text)
                        .shadow(color: .black, radius: 2)
                    Text(tile.subtitle).font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaMenuStyle.gold)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 8, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.tile.\(tile.id)")
    }
}

/// A card's art, filling its frame; the deck's colours as light through glass until the art is on the phone.
struct ArenaArt: View {
    let name: String
    var colors: [String] = []

    var body: some View {
        GeometryReader { proxy in
            NativeCardArtworkView(name: name, variant: .board, contentMode: .fill, artOnly: true) { _, _ in
                ArenaColorGlass(colors: colors)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// Your deck, rank and season as medallions on a gold rail with tick marks, centred under the panels.
struct ArenaProgressRail: View {
    let content: ArenaHomeContent
    let compact: Bool

    var body: some View {
        let rank = content.rank
        let pips = rank.tier == .mythic ? RankPosition.pipsPerDivision : min(RankPosition.pipsPerDivision, rank.pips)
        let played = content.wins + content.losses
        HStack(spacing: compact ? 6 : 14) {
            if let deck = content.deck {
                medallion(progress: 1, title: deck.name, subtitle: String(localized: "Your deck"), action: content.openDeck,
                          identifier: "home.deck") {
                    ArenaArt(name: deck.commander ?? "", colors: deck.colors)
                        .clipShape(Circle())
                }
            }
            medallion(progress: Double(pips) / Double(RankPosition.pipsPerDivision), title: rank.title,
                      subtitle: rank.tier == .mythic ? String(localized: "Mythic") : String(localized: "\(pips) of \(RankPosition.pipsPerDivision) pips"),
                      action: content.openRank, identifier: "home.rank") {
                RankEmblem(tier: rank.tier, size: 32)
            }
            if !compact || content.deck == nil {
                medallion(progress: played == 0 ? 0 : Double(content.wins) / Double(played),
                          title: String(localized: "Season \(content.wins)–\(content.losses)"),
                          subtitle: played == 0 ? String(localized: "No games yet") : String(localized: "\(Int((Double(content.wins) / Double(played) * 100).rounded()))% won"),
                          action: content.openRank, identifier: "home.season") {
                    Image(systemName: "laurel.leading").font(.system(size: 18, weight: .bold)).foregroundStyle(ArenaMenuStyle.metal)
                }
            }
        }
        .padding(.horizontal, 6)
        .background(alignment: .center) { rail }
        .fixedSize(horizontal: !compact, vertical: true)
    }

    /// The line the medallions sit on, with a tick between each.
    private var rail: some View {
        GeometryReader { proxy in
            let y = proxy.size.height / 2
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                for i in 0...8 {
                    let x = proxy.size.width * CGFloat(i) / 8
                    path.move(to: CGPoint(x: x, y: y - 3))
                    path.addLine(to: CGPoint(x: x, y: y + 3))
                }
            }
            .stroke(ArenaGlass.hairline, lineWidth: 1)
            .opacity(0.65)
        }
        .padding(.horizontal, -18)
        .accessibilityHidden(true)
    }

    private func medallion<Face: View>(progress: Double, title: String, subtitle: String, action: @escaping () -> Void,
                                       identifier: String, @ViewBuilder face: () -> Face) -> some View {
        Button {
            GameAudio.shared.play(.uiOpen)
            action()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(red: 0.08, green: 0.07, blue: 0.06))
                    Circle().trim(from: 0, to: max(0.001, progress))
                        .stroke(LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.38), ArenaMenuStyle.ember], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 3).padding(1.5)
                    face().frame(width: 32, height: 32)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(ArenaMenuStyle.font(12, .bold)).foregroundStyle(ArenaMenuStyle.text).lineLimit(1)
                    Text(subtitle).font(ArenaMenuStyle.font(10.5, .semibold)).foregroundStyle(ArenaMenuStyle.dim).lineLimit(1)
                }
                .frame(maxWidth: compact ? 92 : 130, alignment: .leading)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.92),
                                                               Color(red: 0.04, green: 0.045, blue: 0.06).opacity(0.94)],
                                                      startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// A deck's colours as light through dark glass, standing in for art that isn't on the phone yet (no words, no pips).
struct ArenaColorGlass: View {
    let colors: [String]

    private static let tints: [String: Color] = [
        "W": Color(red: 0.93, green: 0.86, blue: 0.66), "U": Color(red: 0.2, green: 0.46, blue: 0.78),
        "B": Color(red: 0.36, green: 0.28, blue: 0.40), "R": Color(red: 0.8, green: 0.28, blue: 0.18),
        "G": Color(red: 0.22, green: 0.55, blue: 0.32)
    ]

    var body: some View {
        let chosen = ["W", "U", "B", "R", "G"].filter(colors.contains).compactMap { Self.tints[$0] }
        let palette = chosen.isEmpty ? [Color(red: 0.40, green: 0.41, blue: 0.44), Color(red: 0.16, green: 0.17, blue: 0.19)]
            : chosen.count == 1 ? [chosen[0], chosen[0].opacity(0.45)] : chosen
        ZStack {
            Color.black
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.8)
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 2, endRadius: 140)
        }
        .accessibilityHidden(true)
    }
}
