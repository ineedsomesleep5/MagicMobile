import SwiftUI
import UIKit

// The Arena board's table pieces (BoardMode.arena). Positions come from ArenaLayout through ArenaCanvas; behaviour stays
// with the views and helpers the Hearth board already uses (PlayerZoneMenu, BattlefieldRow, GameActionDockModel…).

struct ArenaBoardKey: EnvironmentKey { static let defaultValue = false }
struct CardFramesKey: EnvironmentKey { static let defaultValue = true }

/// The table's camera, so cards lying on it lean the way the rendered table does: the plate's pitch (landscape 22°,
/// portrait 16°, scripts/brand/arena_layout.json), the camera's distance in points (35 mm lens on a 36 mm sensor across
/// the screen's long side: half of it over tan 27°) and the screen's centre, toward which every card converges.
struct ArenaTableLean: Equatable {
    let pitch: Double
    let distance: CGFloat
    let centerX: CGFloat

    init(canvas: ArenaCanvas) {
        pitch = canvas.layout.landscape ? 22 : 16
        distance = max(canvas.screen.width, canvas.screen.height) / 2 / tan(27 * .pi / 180)
        centerX = canvas.screen.width / 2
    }

    /// The tilt for a card laid out at `frame` (global): its axis anchored under the screen's centre line, so its
    /// sides converge toward the table's vanishing point rather than its own.
    func anchor(for frame: CGRect) -> UnitPoint { UnitPoint(x: (centerX - frame.minX) / max(frame.width, 1), y: 0.5) }
    func perspective(for frame: CGRect) -> CGFloat { max(frame.width, frame.height) / distance }
}

struct ArenaTableLeanKey: EnvironmentKey { static let defaultValue: ArenaTableLean? = nil }

extension EnvironmentValues {
    /// True while the Arena board draws: battlefield tiles lean back with the table and tapped ones tilt instead of turning.
    var arenaBoard: Bool {
        get { self[ArenaBoardKey.self] }
        set { self[ArenaBoardKey.self] = newValue }
    }
    var arenaTableLean: ArenaTableLean? {
        get { self[ArenaTableLeanKey.self] }
        set { self[ArenaTableLeanKey.self] = newValue }
    }
    /// Tavern frames on battlefield cards (CardFramesPreference); off draws the reference game's cards.
    var cardFrames: Bool {
        get { self[CardFramesKey.self] }
        set { self[CardFramesKey.self] = newValue }
    }
}

enum ArenaPalette {
    static let cream = Color(red: 1, green: 0.965, blue: 0.88)
    static let viewerRim = Color(red: 0.91, green: 0.54, blue: 0.23)
    static let opponentRim = Color(red: 0.31, green: 0.55, blue: 1)
    static let attackGlow = Color(red: 1, green: 0.22, blue: 0.12)
    static let targetGlow = Color(red: 0.55, green: 0.9, blue: 1)
    static let iconFill = Color(red: 0.08, green: 0.045, blue: 0.025)
}

/// The leaning tavern table: the plate stretches to the screen the way the layout does, so the mat sits under the lanes.
struct ArenaTableBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            Image(landscape ? "tavern-arena-landscape" : "tavern-arena-portrait")
                .resizable()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay {
                    // The lamp over the middle of the mat: warm light only, no texture.
                    RadialGradient(colors: [Color(red: 1, green: 0.77, blue: 0.47).opacity(0.13), .clear],
                                   center: .center, startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.42)
                        .blendMode(.screen)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Text with a thin black outline, for numbers laid over a picture.
struct ArenaOutlinedText: View {
    let text: String
    let size: CGFloat
    var color: Color = ArenaPalette.cream

    var body: some View {
        let outline = max(0.8, size * 0.05)
        Text(text)
            .font(.system(size: size, weight: .black, design: .serif))
            .monospacedDigit()
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, x: outline, y: outline)
            .shadow(color: .black, radius: 0, x: -outline, y: outline)
            .shadow(color: .black, radius: 0, x: outline, y: -outline)
            .shadow(color: .black, radius: 0, x: -outline, y: -outline)
            .shadow(color: .black.opacity(0.7), radius: size * 0.12, y: size * 0.06)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A player's life medallion: their picture inside a brass ring, the life total over it. It glows ember on its owner's
/// turn and red (attack) or blue (target) while it can be chosen.
struct ArenaHeroMedallion: View {
    let player: PlayerGameState
    let diameter: CGFloat
    var active = false
    var glow: Color? = nil
    var commanderReady = false
    var showsLife = true

    var body: some View {
        let portrait = diameter * 0.74
        ZStack {
            if commanderReady { TavernCommanderReadyGlow(diameter: portrait) }
            PlayerPortrait(player: player, size: portrait)
                .frame(width: portrait, height: portrait)
                .clipShape(Circle())
                .overlay(Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center,
                                                      startRadius: portrait * 0.25, endRadius: portrait * 0.55)))
            ring
            if !showsLife {
                EmptyView()
            } else if player.isOut {
                ArenaOutlinedText(text: "Out", size: diameter * 0.24, color: .gray)
            } else {
                ArenaOutlinedText(text: "\(player.life)", size: diameter * 0.34)
                    .contentTransition(.numericText(value: Double(player.life)))
                    .animation(.easeOut(duration: 0.3), value: player.life)
            }
        }
        .frame(width: diameter, height: diameter)
        .background {
            if let glow {
                Circle().fill(glow).frame(width: diameter * 1.15, height: diameter * 1.15).blur(radius: diameter * 0.12)
            } else if active {
                Circle().fill(TavernPalette.ember.opacity(0.7)).frame(width: diameter * 1.05, height: diameter * 1.05)
                    .blur(radius: diameter * 0.1)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
        .opacity(player.isOut ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    @ViewBuilder private var ring: some View {
        if let frame = UIImage(named: "tavern-medallion-frame") {
            Image(uiImage: frame).resizable().scaledToFit()
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
        } else {
            Circle().strokeBorder(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), TavernPalette.brass, TavernPalette.brassDark],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: diameter * 0.11)
                .frame(width: diameter, height: diameter)
        }
    }
}

/// The real Magic card back (the image the app already shows for hidden cards), fetched once with the player's
/// artwork consent and kept in Caches; until then the tavern's leather back stands in.
@MainActor
final class ArenaCardBackArt: ObservableObject {
    static let shared = ArenaCardBackArt()
    @Published private(set) var image: UIImage?
    private var started = false
    private var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("magic-card-back.jpg")
    }

    func load() {
        guard !started else { return }
        started = true
        if let data = try? Data(contentsOf: cacheFile), let image = UIImage(data: data) {
            self.image = image
            return
        }
        guard MagicMobilePreferences.current.bool(forKey: NativeArtworkPreference.key),
              let url = CardImageURL.image("Hidden card", variant: .board), url.scheme == "https" else { return }
        let file = cacheFile
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return }
            try? data.write(to: file, options: .atomic)
            self.image = image
        }
    }
}

/// A face-down Magic card.
struct ArenaCardBack: View {
    @ObservedObject private var art = ArenaCardBackArt.shared

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Group {
                if let image = art.image {
                    Image(uiImage: image).resizable()
                } else {
                    leatherBack(width: width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.06))
        }
        .onAppear { art.load() }
        .accessibilityHidden(true)
    }

    private func leatherBack(width: CGFloat) -> some View {
        ZStack {
            TavernFill(material: .leather)
            LinearGradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
        }
        .overlay(RoundedRectangle(cornerRadius: width * 0.06).strokeBorder(Color.black.opacity(0.85), lineWidth: max(1, width * 0.06)))
    }
}

/// A library as a real stack of cards: one sliver per few cards (a little thicker than life so the count reads), the
/// back on top, lying back with the table.
struct ArenaDeckPile: View {
    let count: Int
    let size: CGSize
    let label: String

    var body: some View {
        let thickness = count > 0 ? max(1.5, CGFloat(count) * size.height * 0.0055) : 0
        let layers = min(16, Int((thickness / 1.1).rounded()))
        ZStack {
            Ellipse().fill(.black.opacity(count > 0 ? 0.55 : 0)).blur(radius: 4)
                .frame(width: size.width * 1.1, height: size.height * 0.5).offset(y: size.height * 0.32)
            if count == 0 {
                RoundedRectangle(cornerRadius: 4).strokeBorder(TavernPalette.brass.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(0..<layers, id: \.self) { index in
                let fraction = layers > 1 ? Double(index) / Double(layers - 1) : 1
                RoundedRectangle(cornerRadius: size.width * 0.08)
                    .fill(Color(hue: 0.105, saturation: 0.32, brightness: 0.62 + 0.26 * fraction + (index % 2 == 0 ? 0 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: size.width * 0.08).strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                    .offset(x: -thickness * 0.22 * CGFloat(index) / CGFloat(max(layers, 1)),
                            y: -thickness * CGFloat(index) / CGFloat(max(layers, 1)))
            }
            if count > 0 {
                ArenaCardBack().offset(x: -thickness * 0.22, y: -thickness)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(ArenaTableLeanEffect())
        .overlay(alignment: .bottomTrailing) {
            if count > 0 { ArenaCountBadge(count: count).offset(x: 8, y: -2) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Lays a view on the table: tilted by the table camera's pitch, converging on its vanishing point.
struct ArenaTableLeanEffect: ViewModifier {
    @Environment(\.arenaTableLean) private var lean

    @ViewBuilder func body(content: Content) -> some View {
        // Off the Arena table (Hearth) the tile stays flat and pays for no geometry reads.
        if let lean {
            content.visualEffect { view, proxy in
                let frame = proxy.frame(in: .global)
                return view.rotation3DEffect(.degrees(lean.pitch), axis: (x: 1, y: 0, z: 0),
                                             anchor: lean.anchor(for: frame), perspective: lean.perspective(for: frame))
            }
        } else {
            content
        }
    }
}

/// A count on a small leather lozenge in a brass edge.
struct ArenaCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .heavy, design: .serif))
            .monospacedDigit()
            .foregroundStyle(TavernPalette.label)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 17)
            .background(TavernPalette.leather, in: Capsule())
            .overlay(Capsule().strokeBorder(TavernPalette.brass, lineWidth: 1.2))
            .fixedSize()
    }
}

/// A graveyard: its top card face up, or an empty dashed slot; a tap opens the whole zone.
struct ArenaGraveyardPile: View {
    let cards: [ZoneCard]
    let size: CGSize
    let label: String
    /// An exile pile: the same top card under a cool, ghostly veil with the exile mark.
    var exile = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            ZStack {
                if let top = cards.last {
                    CardTile(card: top, selected: false, zoneName: exile ? "Exile" : "Graveyard", width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .overlay {
                            if exile {
                                RoundedRectangle(cornerRadius: size.width * 0.07)
                                    .fill(Color(red: 0.35, green: 0.3, blue: 0.62).opacity(0.38))
                                    .overlay(Image(systemName: "sparkles").font(.system(size: size.width * 0.32, weight: .bold))
                                                .foregroundStyle(.white.opacity(0.85)).shadow(color: .black, radius: 2))
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if cards.count > 1 { ArenaCountBadge(count: cards.count).offset(x: 6, y: 4) }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(TavernPalette.brass.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cards.isEmpty)
        .accessibilityLabel(cards.isEmpty ? "\(label), empty" : "\(label), \(cards.count) cards")
    }
}

/// The opponent's hand as a fan of card backs along the top edge.
struct ArenaOpponentHandFan: View {
    let count: Int
    let card: CGSize
    let pitch: CGFloat

    var body: some View {
        let shown = min(count, 12)
        // A few cards still fan out past the medallion in front of them.
        let pitch = shown > 1 ? max(self.pitch, card.width * 1.8 / CGFloat(shown - 1)) : 0
        ZStack {
            ForEach(0..<shown, id: \.self) { index in
                let offset = CGFloat(index) - CGFloat(shown - 1) / 2
                ArenaCardBack()
                    .frame(width: card.width, height: card.height)
                    .rotationEffect(.degrees(180 - Double(offset) * 4))
                    .offset(x: offset * pitch, y: -offset * offset * 0.9)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            }
        }
        .frame(width: card.width + CGFloat(max(shown - 1, 0)) * pitch, height: card.height)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(count == 1 ? "1 card in hand" : "\(count) cards in hand")
    }
}

// MARK: - Phase strip

/// The reference's phase strip: all eight steps of a turn as dark icons on a thin track, always shown, the current one
/// lit in the active player's colour; moving on sends a spark along the track to the next icon.
struct ArenaPhaseStrip: View {
    let step: String?
    let viewerTurn: Bool
    let width: CGFloat
    var iconSize: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparkX: CGFloat?
    @State private var ignite = false
    /// The latest move: a spark still travelling for an older one does nothing when it lands.
    @State private var moves = 0

    enum Icon { case diamond, card, sword, shield, burst }

    /// Beginning, main 1, attackers, blockers, damage, end of combat, main 2, end: the reference's strip.
    static let icons: [Icon] = [.diamond, .card, .sword, .shield, .burst, .diamond, .card, .diamond]

    /// Which of the eight icons a step lights.
    static func current(for step: String?) -> Int? {
        switch (step ?? "").lowercased().replacingOccurrences(of: "_", with: "-") {
        case "beginning", "untap", "upkeep", "draw": return 0
        case "precombat-main", "main1": return 1
        case "combat", "begin-combat", "declare-attackers": return 2
        case "declare-blockers": return 3
        case "first-combat-damage", "first-strike-damage", "combat-damage": return 4
        case "end-combat": return 5
        case "postcombat-main", "main2": return 6
        case "ending", "end", "end-turn", "cleanup": return 7
        default: return nil
        }
    }

    var body: some View {
        let icons = Self.icons
        let current = Self.current(for: step)
        let rim = viewerTurn ? ArenaPalette.viewerRim : ArenaPalette.opponentRim
        let spacing = (width - 12) / CGFloat(icons.count)
        let positions = icons.indices.map { 6 + spacing * (CGFloat($0) + 0.5) }
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(colors: [.clear, TavernPalette.brass.opacity(0.75), TavernPalette.brass.opacity(0.75), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: 1.4)
                .shadow(color: .black.opacity(0.6), radius: 0.5, y: 0.8)
                .position(x: width / 2, y: iconSize / 2 + 2)
            if let current, current > 0 {
                // The part of the turn already played, lit in the turn's colour.
                Capsule().fill(LinearGradient(colors: [rim.opacity(0.2), rim], startPoint: .leading, endPoint: .trailing))
                    .frame(width: positions[current] - positions[0], height: 2)
                    .position(x: (positions[0] + positions[current]) / 2, y: iconSize / 2 + 2)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: current)
            }
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                // The current step stays dark only while the spark is still on its way to it.
                let on = index == current && sparkX == nil
                ArenaPhaseIcon(icon: icon, rim: rim, on: on, size: iconSize * (icon == .diamond ? 0.7 : 0.9) * (on ? 1.2 : 1))
                    .scaleEffect(on && ignite ? 1.45 : 1)
                    .position(x: positions[index], y: iconSize / 2 + 2)
            }
            if let sparkX {
                Circle().fill(RadialGradient(colors: [.white, rim, .clear], center: .center, startRadius: 0, endRadius: 7))
                    .frame(width: 14, height: 14)
                    .position(x: sparkX, y: iconSize / 2 + 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: iconSize + 4)
        .onChange(of: current) { old, new in move(from: old, to: new, positions: positions) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TavernPhaseTrack.describe(step).title)
        .accessibilityIdentifier("board.phase.plate")
    }

    private func move(from old: Int?, to new: Int?, positions: [CGFloat]) {
        moves += 1
        let move = moves
        guard !reduceMotion, let old, let new, old != new else { sparkX = nil; return }
        let distance = abs(positions[new] - positions[old])
        let duration = 0.22 + min(0.26, Double(distance) * 0.0022)
        sparkX = positions[old]
        withAnimation(.easeInOut(duration: duration)) { sparkX = positions[new] }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard moves == move else { return }
            sparkX = nil
            withAnimation(.easeOut(duration: 0.08)) { ignite = true }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.35)) { ignite = false }
        }
    }
}

/// One phase icon: a small enamel piece in a brass rim with an engraved detail, dark walnut while it waits, lit from
/// gold-white into the turn's colour, with a halo, while it is the current step.
struct ArenaPhaseIcon: View {
    let icon: ArenaPhaseStrip.Icon
    let rim: Color
    let on: Bool
    let size: CGFloat

    var body: some View {
        let silhouette = ArenaPhaseShape(icon: icon)
        let enamel = on ? [Color.white, Color(red: 1, green: 0.86, blue: 0.56), rim]
                        : [Color(red: 0.42, green: 0.33, blue: 0.24), Color(red: 0.2, green: 0.14, blue: 0.1), Color(red: 0.08, green: 0.05, blue: 0.04)]
        ZStack {
            silhouette.fill(LinearGradient(colors: enamel, startPoint: .top, endPoint: .bottom))
            // Facet shading: the lower right turns away from the lamp.
            silhouette.fill(LinearGradient(colors: [.clear, .black.opacity(on ? 0.16 : 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
            ArenaPhaseDetail(icon: icon)
                .stroke(on ? Color(red: 0.42, green: 0.2, blue: 0.04).opacity(0.8) : TavernPalette.brass.opacity(0.6),
                        style: StrokeStyle(lineWidth: max(0.7, size * 0.05), lineCap: .round, lineJoin: .round))
            silhouette.stroke(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), TavernPalette.brass, Color(red: 0.33, green: 0.2, blue: 0.07)],
                                             startPoint: .top, endPoint: .bottom),
                              style: StrokeStyle(lineWidth: max(1, size * 0.07), lineJoin: .round))
            // A thin lamp highlight along the top edge.
            silhouette.stroke(Color.white.opacity(on ? 0.7 : 0.25), lineWidth: max(0.5, size * 0.03))
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
        }
        .frame(width: size, height: size)
        // The halo sits behind without taking part in the layout (inside the stack it doubled the lit icon's size).
        .background {
            if on {
                Circle()
                    .fill(RadialGradient(colors: [rim.opacity(0.7), rim.opacity(0)], center: .center, startRadius: 0, endRadius: size))
                    .frame(width: size * 2, height: size * 2)
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        .shadow(color: on ? rim : .clear, radius: on ? 5 : 0)
    }
}

/// A rounded rectangle drawn from lines and arcs. iOS fills a `Path(roundedRect:)` returned from a small Shape at the
/// shape's full size from the rectangle's corner (a block beside each card icon, 2026-10-20), so the phase icons
/// draw theirs by hand.
func arenaRoundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
    let r = min(radius, rect.width / 2, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
    path.closeSubpath()
    return path
}

/// The engraved line inside each phase icon, on the same 20 × 20 grid: a gem's table, a card's art box and text, a
/// blade's fuller, a shield's boss and bands, a burst's core.
struct ArenaPhaseDetail: Shape {
    let icon: ArenaPhaseStrip.Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        switch icon {
        case .diamond:
            path.addLines([p(10, 6.6), p(13.4, 10), p(10, 13.4), p(6.6, 10)])
            path.closeSubpath()
        case .card:
            path.addPath(arenaRoundedRectPath(CGRect(origin: p(6.7, 4.3), size: CGSize(width: 6.6 * scale, height: 6.2 * scale)),
                                              radius: scale))
            path.move(to: p(7, 12.9)); path.addLine(to: p(13, 12.9))
            path.move(to: p(7, 14.9)); path.addLine(to: p(11.4, 14.9))
        case .sword:
            path.move(to: p(16.2, 3.8)); path.addLine(to: p(8.8, 11.2))
            path.addEllipse(in: CGRect(origin: p(1.6, 16.4), size: CGSize(width: 2 * scale, height: 2 * scale)))
        case .shield:
            path.addEllipse(in: CGRect(origin: p(7.8, 6.8), size: CGSize(width: 4.4 * scale, height: 4.4 * scale)))
            path.move(to: p(10, 3.4)); path.addLine(to: p(10, 6.8))
            path.move(to: p(10, 11.2)); path.addLine(to: p(10, 16.4))
        case .burst:
            path.addEllipse(in: CGRect(origin: p(7.4, 7.8), size: CGSize(width: 5.2 * scale, height: 5.2 * scale)))
        }
        return path
    }
}

/// The strip's icons, drawn on a 20 × 20 grid like the prototype's SVGs.
struct ArenaPhaseShape: Shape {
    let icon: ArenaPhaseStrip.Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 20
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.addLines(points.map { CGPoint(x: rect.minX + $0.0 * scale, y: rect.minY + $0.1 * scale) })
            path.closeSubpath()
            return path
        }
        let blade = [(17.6, 2.4), (17.1, 5.4), (8.6, 13.9), (6.1, 11.4), (14.6, 2.9)] as [(CGFloat, CGFloat)]
        let guardBar = [(3.9, 10.6), (9.4, 16.1), (8.2, 17.3), (2.7, 11.8)] as [(CGFloat, CGFloat)]
        let grip = [(5.6, 15.2), (3.3, 17.5), (2.5, 16.7), (4.8, 14.4)] as [(CGFloat, CGFloat)]
        switch icon {
        case .diamond:
            return polygon([(10, 3.5), (16.5, 10), (10, 16.5), (3.5, 10)])
        case .card:
            return arenaRoundedRectPath(CGRect(x: rect.minX + 5 * scale, y: rect.minY + 2.5 * scale, width: 10 * scale, height: 15 * scale),
                                        radius: 2 * scale)
        case .sword:
            var path = polygon(blade)
            path.addPath(polygon(guardBar)); path.addPath(polygon(grip))
            return path
        case .shield:
            var path = Path()
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
            path.move(to: p(10, 2.2))
            path.addLine(to: p(16.4, 4.4))
            path.addLine(to: p(16.4, 9.4))
            path.addCurve(to: p(10, 17.8), control1: p(16.4, 13.6), control2: p(13.5, 16.3))
            path.addCurve(to: p(3.6, 9.4), control1: p(6.5, 16.3), control2: p(3.6, 13.6))
            path.addLine(to: p(3.6, 4.4))
            path.closeSubpath()
            return path
        case .burst:
            return polygon([(10, 1.6), (11.9, 6.4), (16.8, 4.5), (14.6, 9.2), (18.9, 11.9), (13.9, 12.7), (14.1, 17.8),
                            (10, 14.7), (5.9, 17.8), (6.1, 12.7), (1.1, 11.9), (5.4, 9.2), (3.2, 4.5), (8.1, 6.4)])
        }
    }
}

// MARK: - Controls

/// The corner's plaque buttons: ember glass for the call to action, leather for the secondary one, a quiet label when
/// it's the opponent's turn. The capsule is drawn a little inside a 44 pt target.
struct ArenaPlaqueButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, waiting }
    var kind: Kind = .primary
    var fontSize: CGFloat = 18
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: kind == .waiting ? fontSize * 0.8 : fontSize, weight: .bold, design: .serif))
            .foregroundStyle(kind == .secondary ? TavernPalette.parchment : kind == .waiting ? TavernPalette.parchment.opacity(0.9)
                             : Color(red: 1, green: 0.91, blue: 0.66))
            .shadow(color: .black.opacity(0.75), radius: 1, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if kind != .waiting {
                    Group {
                        if kind == .primary { TavernFill(material: .ember) } else { TavernFill(material: .leather) }
                    }
                    .clipShape(Capsule())
                    .padding(3)
                    .overlay { TavernCapsuleRim() }
                    .padding(.vertical, 3)
                }
            }
            .contentShape(Rectangle())
            .saturation(isEnabled ? 1 : 0.2)
            .brightness(isEnabled ? (configuration.isPressed ? 0.08 : 0) : -0.12)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(kind == .waiting ? 0 : 0.45), radius: 4, y: 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .pressSound(.uiTap, isPressed: configuration.isPressed)
    }
}

/// A small brass-rimmed leather pill: pass ahead (">>") and Undo.
struct ArenaPillStyle: ButtonStyle {
    var lit = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy, design: .serif))
            .foregroundStyle(lit ? Color.white : Color(red: 0.96, green: 0.8, blue: 0.48))
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Group { if lit { TavernFill(material: .ember) } else { TavernFill(material: .leather) } }
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(TavernPalette.brass, lineWidth: 1.5))
            }
            .shadow(color: lit ? TavernPalette.ember.opacity(0.8) : .black.opacity(0.5), radius: lit ? 8 : 3, y: 2)
            .contentShape(Rectangle().inset(by: -8))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Pass ahead: the skip options while you play, Stop while the table skips for you.
struct ArenaPassAheadPill: View {
    @Environment(\.nativeTurnControl) private var control

    var body: some View {
        if let control {
            if control.isAutoPassing {
                Button(action: control.stop) { skipGlyph }
                    .buttonStyle(ArenaPillStyle(lit: true))
                    .accessibilityLabel("Stop skipping")
                    .accessibilityHint(control.status ?? "Stops future automatic passes")
            } else {
                TavernMenu(arrowEdge: .bottom) {
                    TavernMenuItem(title: "End turn — skip stack responses", action: control.skipResponses)
                        .disabled(!control.canSkipResponses)
                    TavernMenuItem(title: "Skip to my turn — skip stack responses", action: control.skipToMyTurn)
                        .disabled(!control.canSkipToMyTurn)
                    TavernMenuItem(title: "End turn — stop for responses", action: control.endTurn)
                        .disabled(!control.canEndTurn)
                    TavernMenuItem(title: control.isFullControl ? "Full control: on (this turn)" : "Full control this turn",
                                   systemImage: "hand.raised.fill", action: control.toggleFullControl)
                } label: { skipGlyph }
                .buttonStyle(ArenaPillStyle())
                .disabled(!control.canEndTurn && !control.canSkipResponses && !control.canSkipToMyTurn)
                .accessibilityLabel("Skip options")
                .accessibilityHint("Choose how long to skip responses. Required choices always stop skipping.")
            }
        }
    }

    private var skipGlyph: some View {
        Image(systemName: "forward.fill").font(.system(size: 13, weight: .black))
    }
}

/// The top of the stack as a big card on the right (the reference's stack), with the count, and a tab that opens the
/// whole stack. A tap shows the card's full text.
struct ArenaStackCard: View {
    let object: XmageStackObject
    let count: Int
    let size: CGSize
    /// A commander cast from the command zone: the card wears a gold rim and a crown, and that is its whole fanfare.
    var commander = false
    let inspect: (ZoneCard) -> Void
    let openStack: () -> Void

    /// XMage marks spells; everything else on the stack is an activated or triggered ability.
    static func isAbility(_ object: XmageStackObject) -> Bool { (object.objectType ?? "").uppercased() != "SPELL" && object.objectType != nil }

    var body: some View {
        ZStack {
            if let card = object.displaySourceCard, Self.isAbility(object) {
                Button { inspect(card) } label: {
                    ArenaAbilityCard(source: card, text: object.rulesText ?? object.displayName, size: size)
                }
                .buttonStyle(.plain)
            } else if let card = object.displaySourceCard {
                Button { inspect(card) } label: {
                    CardTile(card: card, selected: false, zoneName: "Stack", width: size.width, height: size.height,
                             imageVariant: .inspection)
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            } else {
                // A spell or ability whose card isn't known: its name and text on the Arena's ability card.
                ArenaAbilityCard(source: nil, name: object.displayName, text: object.rulesText ?? object.displaySourceName, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if commander {
                RoundedRectangle(cornerRadius: size.width * 0.05)
                    .strokeBorder(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), TavernPalette.brass,
                                                          Color(red: 0.6, green: 0.42, blue: 0.12)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 3)
                    .shadow(color: Color(red: 1, green: 0.8, blue: 0.35).opacity(0.8), radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if commander {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.3, green: 0.17, blue: 0.03))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.58), TavernPalette.brass],
                                                             startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(y: -14)
                    .accessibilityLabel("Commander")
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
        .overlay(alignment: .leading) {
            Button(action: openStack) {
                ZStack {
                    if let coin = UIImage(named: "tavern-ui-coin") { Image(uiImage: coin).resizable().scaledToFit() }
                    else { Circle().fill(TavernPalette.brass) }
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.04))
                }
                .frame(width: 27, height: 27)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -40)
            .accessibilityLabel("Open the stack")
            .accessibilityIdentifier("board.stack.tray")
        }
        .overlay(alignment: .topTrailing) {
            if count > 1 { ArenaCountBadge(count: count).offset(x: 6, y: -6) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.isAbility(object) ? "Top of the stack: an ability of \(object.displaySourceName)"
                                                   : "Top of the stack: \(object.displayName)")
    }
}

/// The slim caption over the midline that says what the table wants ("Choose attackers.", "Pay {1}{R}").
// MARK: - Arena chrome

/// The Arena board's own surfaces, the reference game's dialogs and browsers rather than the Hearth board's tooled
/// leather and parchment: dark glass a little lighter at the top, edged in a fine gold hairline. The plaques and gold
/// titles stay; they are already the Arena corner's.
enum ArenaGlass {
    static let top = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let bottom = Color(red: 0.04, green: 0.045, blue: 0.06)
    static let hairline = LinearGradient(colors: [Color(red: 0.96, green: 0.80, blue: 0.46).opacity(0.85),
                                                  Color(red: 0.55, green: 0.38, blue: 0.14).opacity(0.7)],
                                         startPoint: .top, endPoint: .bottom)
    static let text = Color(red: 0.95, green: 0.92, blue: 0.86)
}

/// A filled glass surface (sheets, pop-overs, full-width backings).
struct ArenaGlassBackground: View {
    var body: some View {
        LinearGradient(colors: [ArenaGlass.top.opacity(0.97), ArenaGlass.bottom.opacity(0.98)], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1) }
            .ignoresSafeArea()
    }
}

/// A floating glass panel with rounded corners in the gold hairline.
struct ArenaGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14
    var opacity: Double = 0.92

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(colors: [ArenaGlass.top.opacity(opacity), ArenaGlass.bottom.opacity(opacity)],
                                          startPoint: .top, endPoint: .bottom))
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)))
            }
            .overlay { shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
    }
}

/// ArenaGlassPanel only on the Arena board.
struct ArenaGlassIf: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 14

    @ViewBuilder func body(content: Content) -> some View {
        if active { content.modifier(ArenaGlassPanel(cornerRadius: cornerRadius)) } else { content }
    }
}

/// Closes a board panel that the Arena board shows on the table instead of in a sheet (`boardSheet`). Panels that close
/// themselves call it in place of `dismiss`, which would reach past the board.
private struct BoardPanelCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }

extension EnvironmentValues {
    var boardPanelClose: (() -> Void)? {
        get { self[BoardPanelCloseKey.self] }
        set { self[BoardPanelCloseKey.self] = newValue }
    }
}

extension View {
    /// A board panel: a sheet on the Hearth board; on the Arena board a glass panel over the dimmed table, no system sheet.
    @ViewBuilder
    func boardSheet<Content: View>(isPresented: Binding<Bool>, arena: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        if arena {
            overlay { ArenaPanelOverlay(isPresented: isPresented, content: content) }
        } else {
            sheet(isPresented: isPresented, content: content)
        }
    }
}

/// The Arena board's panel: centred on the table over a dimmed board; a tap on the board closes it.
struct ArenaPanelOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                if isPresented {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented = false }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    content()
                        .environment(\.boardPanelClose, { isPresented = false })
                        .environment(\.arenaBoard, true)
                        .frame(maxWidth: min(proxy.size.width - 32, landscape ? 640 : 560),
                               maxHeight: proxy.size.height * (landscape ? 0.92 : 0.84))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .modifier(ArenaGlassPanel(cornerRadius: 22, opacity: 0.96))
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                        .accessibilityAddTraits(.isModal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: isPresented)
        }
    }
}

/// A row or option on glass: a lighter pane in the hairline; primary rows a touch brighter.
struct ArenaGlassRow: ViewModifier {
    var primary = false
    var danger = false
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(danger ? Color(red: 0.42, green: 0.08, blue: 0.07).opacity(0.85)
                                  : Color.white.opacity(primary ? 0.11 : 0.06))
            }
            .overlay { shape.strokeBorder(danger ? AnyShapeStyle(Color(red: 0.9, green: 0.4, blue: 0.3).opacity(0.7)) : AnyShapeStyle(ArenaGlass.hairline),
                                          lineWidth: primary ? 1.2 : 0.8) }
    }
}

/// ArenaGlassRow only on the Arena board.
struct ArenaGlassRowIf: ViewModifier {
    let active: Bool
    var primary = false

    @ViewBuilder func body(content: Content) -> some View {
        if active { content.modifier(ArenaGlassRow(primary: primary)) } else { content }
    }
}

/// The glass close button that stands in for the Hearth board's wax seal.
struct ArenaCloseLabel: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(ArenaGlass.text)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.1)))
            .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
    }
}

/// A card's colour for its frame, the reference's way: its one colour, gold for several, grey for none (lands without a
/// cost take their basic land types).
enum ArenaCardColor {
    static func frame(for card: ZoneCard) -> Color {
        var colors = Set<String>()
        let cost = card.card.manaCost?.uppercased() ?? ""
        for symbol in ["W", "U", "B", "R", "G"] where cost.contains(symbol) { colors.insert(symbol) }
        for color in card.card.tokenColors ?? [] {
            switch color.lowercased() {
            case "w", "white": colors.insert("W")
            case "u", "blue": colors.insert("U")
            case "b", "black": colors.insert("B")
            case "r", "red": colors.insert("R")
            case "g", "green": colors.insert("G")
            default: break
            }
        }
        if colors.isEmpty {
            for (land, symbol) in [("Plains", "W"), ("Island", "U"), ("Swamp", "B"), ("Mountain", "R"), ("Forest", "G")]
            where card.card.typeLine.localizedCaseInsensitiveContains(land) { colors.insert(symbol) }
        }
        if colors.count > 1 { return Color(red: 0.93, green: 0.74, blue: 0.32) }
        switch colors.first {
        case "W": return Color(red: 0.93, green: 0.88, blue: 0.72)
        case "U": return Color(red: 0.25, green: 0.52, blue: 0.95)
        case "B": return Color(red: 0.42, green: 0.30, blue: 0.48)
        case "R": return Color(red: 0.86, green: 0.22, blue: 0.14)
        case "G": return Color(red: 0.22, green: 0.66, blue: 0.30)
        default: return Color(red: 0.62, green: 0.62, blue: 0.66)
        }
    }
}

/// An ability on the stack the reference game's way: its source's frame colour and art, a type line that says
/// "Ability", only the ability's own text, a rounded foot, and the keyword's icon in the corner when it has one.
struct ArenaAbilityCard: View {
    let source: ZoneCard?
    var name: String? = nil
    /// The type line: "Ability", or "Mode 2" for a modal spell's mode.
    var kind = "Ability"
    let text: String
    let size: CGSize

    var body: some View {
        let frame = source.map(ArenaCardColor.frame(for:)) ?? Color(red: 0.62, green: 0.62, blue: 0.66)
        let edge = max(3, size.width * 0.035)
        let shape = ArenaAbilityShape(corner: size.width * 0.05)
        let icon = XmageCardIcon.keywordIcons(rules: text).first.flatMap { XmageCardIcon.assetName(for: $0.iconType) }
        ZStack {
            shape.fill(LinearGradient(colors: [frame, frame.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                Text(source?.card.name ?? name ?? "Ability")
                    .font(.system(size: max(10, size.width * 0.075), weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.06))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, size.width * 0.05)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: size.height * 0.085)
                    .background(ZStack { Color(white: 0.94); frame.opacity(0.28) })
                Group {
                    if let source {
                        TavernArtCrop(card: source, zoneName: "Stack", tagReserve: 0)
                    } else {
                        LinearGradient(colors: [frame.opacity(0.6), Color(red: 0.1, green: 0.1, blue: 0.12)], startPoint: .top, endPoint: .bottom)
                            .overlay(Image(systemName: "sparkles").font(.system(size: size.width * 0.2, weight: .bold)).foregroundStyle(.white.opacity(0.5)))
                    }
                }
                .frame(height: size.height * 0.4)
                .clipped()
                Text(kind)
                    .font(.system(size: max(9, size.width * 0.062), weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.06))
                    .padding(.horizontal, size.width * 0.05)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: size.height * 0.07)
                    .background(ZStack { Color(white: 0.9); frame.opacity(0.22) })
                ZStack(alignment: .topLeading) {
                    Color(red: 0.97, green: 0.95, blue: 0.9)
                    GameRulesText(source: PromptDisplayText.clean(text), symbolSize: max(9, size.width * 0.06))
                        .font(.system(size: max(9, size.width * 0.062), weight: .regular, design: .serif))
                        .foregroundStyle(Color(red: 0.1, green: 0.08, blue: 0.06))
                        .minimumScaleFactor(0.55)
                        .padding(size.width * 0.06)
                }
            }
            .padding(edge)
            .clipShape(shape.inset(by: edge * 0.5))
            shape.strokeBorder(.black.opacity(0.85), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if let icon, let image = UIImage(named: icon) {
                Image(uiImage: image).resizable().scaledToFit()
                    .padding(4)
                    .frame(width: size.width * 0.16, height: size.width * 0.16)
                    .background(Circle().fill(Color(red: 0.12, green: 0.1, blue: 0.08)))
                    .overlay(Circle().stroke(TavernPalette.brass, lineWidth: 1))
                    .offset(x: -size.width * 0.06, y: size.height * 0.1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ability of \(source?.card.name ?? name ?? "a permanent"): \(PromptDisplayText.clean(text))")
    }
}

/// The Arena board's ability browser, after the reference game's browsers (Caleb, 2026-10-20): a dark veil, the
/// abilities as Arena ability cards in a row, one line of instructions and the corner's plaques. Ordering triggers,
/// you tap them in the order they should resolve (1 resolves first) and press Done; choosing an ability, a tap picks
/// it. A hold shows the source card.
struct ArenaAbilityBrowser: View {
    let prompt: PromptEnvelopeV2
    let abilities: [XmagePromptAbility]
    /// Ordering triggers (XMage's PICK_ABILITY) rather than choosing one ability.
    let ordering: Bool
    let pending: Bool
    let screen: CGSize
    var canRemember = false
    /// The prompt's own way out (XMage's Cancel), when it has one.
    var cancel: (title: String, action: () -> Void)?
    let choose: (XmagePromptAbility) -> Void
    /// The order to resolve in, first to last, and whether XMage should keep putting the first pick first.
    let order: ([XmagePromptAbility], Bool) -> Void
    let inspect: (ZoneCard) -> Void
    @State private var picked: [String] = []
    @State private var remember = false

    private var cardSize: CGSize {
        let landscape = screen.width > screen.height
        let height = min(landscape ? screen.height * 0.5 : 230, 250)
        return CGSize(width: height * 0.72, height: height)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(ordering ? "Order your triggers" : "Choose an ability")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                Text(ordering ? "Tap them in the order they resolve: 1 resolves first." : PromptDisplayText.clean(prompt.message))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(ArenaGlass.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(abilities) { ability in card(ability) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(minWidth: screen.width)
                }
                if ordering && canRemember {
                    RememberChoiceToggle(title: "Always put my last-resolving pick first", isOn: $remember)
                }
                if !ordering, let cancel {
                    Button(cancel.title, action: cancel.action)
                        .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                        .frame(width: 150, height: 40)
                        .accessibilityIdentifier("arena.abilities.cancel")
                }
                if ordering {
                    HStack(spacing: 12) {
                        Button("Auto Order") { order(abilities, false) }
                            .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                            .frame(width: 150, height: 40)
                            .accessibilityIdentifier("arena.triggers.auto")
                        Button(picked.count >= abilities.count - 1 ? "Done" : "\(picked.count) of \(abilities.count)") {
                            let chosen = picked.compactMap { id in abilities.first { $0.id == id } }
                            order(chosen + abilities.filter { !picked.contains($0.id) }, remember)
                        }
                        .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 16))
                        .frame(width: 150, height: 40)
                        .disabled(picked.count < abilities.count - 1)
                        .accessibilityIdentifier("arena.triggers.done")
                    }
                }
            }
            .disabled(pending)
            .opacity(pending ? 0.7 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.abilityBrowser")
    }

    private func card(_ ability: XmagePromptAbility) -> some View {
        let number = picked.firstIndex(of: ability.id).map { $0 + 1 }
        return ArenaAbilityCard(source: ability.sourceCard, name: ability.sourceName, text: ability.rulesText ?? ability.label, size: cardSize)
            .overlay {
                if number != nil {
                    ArenaAbilityShape(corner: cardSize.width * 0.05).strokeBorder(Color(red: 1, green: 0.82, blue: 0.4), lineWidth: 3)
                        .shadow(color: Color(red: 1, green: 0.75, blue: 0.3), radius: 8)
                }
            }
            .overlay(alignment: .top) {
                if let number { TavernCoin(value: number, size: 34).offset(y: -17).transition(.scale) }
            }
            .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
            .scaleEffect(number != nil ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: number)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !pending else { return }
                if !ordering { choose(ability); return }
                if let index = picked.firstIndex(of: ability.id) { picked.remove(at: index) } else { picked.append(ability.id) }
                GameHaptics.selection()
            }
            .onLongPressGesture(minimumDuration: 0.35) { if let source = ability.sourceCard { inspect(source) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ability.sourceName ?? ability.sourceCard?.card.name ?? "Ability"): \(PromptDisplayText.clean(ability.rulesText ?? ability.label))")
            .accessibilityValue(number.map { "Resolves \($0)" } ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("arena.ability.\(ability.id)")
    }
}

/// The whole stack the Arena way (Caleb, 2026-10-20): its cards side by side over the dimmed table, like the ability
/// browser, the one that resolves next first. Spells show as their card, abilities as ability cards; whose each is and
/// what it targets sits underneath. A tap reads a card; Resolve All and Done below. Landscape lays them in one row,
/// portrait in two columns, so many show at once.
struct ArenaStackBrowser: View {
    let snapshot: GameSnapshot
    let screen: CGSize
    var resolveAll: (() -> Void)?
    var stopSkipping: (() -> Void)?
    let inspect: (ZoneCard) -> Void
    let close: () -> Void

    private var objects: [XmageStackObject] { snapshot.stackTopFirst }
    private var landscape: Bool { screen.width > screen.height }

    private var cardSize: CGSize {
        if landscape {
            let height = min(screen.height * 0.5, 230)
            return CGSize(width: height * 0.72, height: height)
        }
        let width = min((screen.width - 24 * 2 - 18) / 2, 180)
        return CGSize(width: width, height: width / 0.72)
    }

    private var responding: Bool {
        (snapshot.legalActions ?? []).contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            VStack(spacing: landscape ? 8 : 12) {
                header
                if landscape {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in entry(object, position: index) }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                        .frame(minWidth: screen.width)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.fixed(cardSize.width), spacing: 18), GridItem(.fixed(cardSize.width), spacing: 18)],
                                  spacing: 26) {
                            ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in entry(object, position: index) }
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    }
                }
                buttons
            }
            .padding(.top, landscape ? 10 : 56)
            .padding(.bottom, landscape ? 10 : 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.stackBrowser")
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("The Stack")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                TavernCoin(value: snapshot.xmage?.stack.count ?? objects.count, size: 28)
                    .accessibilityLabel("\(snapshot.xmage?.stack.count ?? objects.count) on the stack")
            }
            HStack(spacing: 8) {
                Text(objects.count > 1 ? "Resolves left to right" : "Resolves next")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(ArenaGlass.text.opacity(0.75))
                TavernTag(text: responding ? "YOUR RESPONSE" : "WAITING", leather: true, accent: responding ? TavernPalette.ember : nil)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if let stopSkipping {
                Button("Stop skipping", action: stopSkipping)
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 15))
                    .frame(width: 150, height: 40)
            }
            if let resolveAll {
                Button("Resolve All", action: resolveAll)
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                    .frame(width: 150, height: 40)
                    .accessibilityIdentifier("board.stack.sheet.resolveAll")
            }
            Button("Done", action: close)
                .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 16))
                .frame(width: 150, height: 40)
                .accessibilityIdentifier("board.stack.done")
        }
    }

    private func entry(_ object: XmageStackObject, position: Int) -> some View {
        let next = position == 0
        let ability = ArenaStackCard.isAbility(object) || object.displaySourceCard == nil
        return VStack(spacing: 7) {
            Group {
                if ability {
                    ArenaAbilityCard(source: object.displaySourceCard, name: object.displaySourceCard == nil ? object.displayName : nil,
                                     text: object.rulesText ?? object.displayName, size: cardSize)
                } else if let card = object.displaySourceCard {
                    CardTile(card: card, selected: false, zoneName: "Stack", width: cardSize.width, height: cardSize.height,
                             imageVariant: .inspection)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if next {
                    RoundedRectangle(cornerRadius: cardSize.width * 0.05)
                        .strokeBorder(Color(red: 1, green: 0.82, blue: 0.4), lineWidth: 3)
                        .shadow(color: Color(red: 1, green: 0.75, blue: 0.3), radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) { TavernCoin(value: position + 1, size: 30).offset(y: -15) }
            .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
            .contentShape(Rectangle())
            .onTapGesture { if let card = object.displaySourceCard { inspect(card) } }
            VStack(spacing: 2) {
                Text(next ? "RESOLVES NEXT" : owner(object).uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .serif)).tracking(0.8)
                    .foregroundStyle(next ? Color(red: 0.98, green: 0.72, blue: 0.4) : ArenaGlass.text.opacity(0.65))
                if next {
                    Text(owner(object)).font(.system(size: 11, design: .serif).italic()).foregroundStyle(ArenaGlass.text.opacity(0.75))
                }
                if let targets = object.targetIds, !targets.isEmpty {
                    Label(StackTargetPresentation.labels(for: targets, in: snapshot).joined(separator: ", "), systemImage: "scope")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(ArenaGlass.text)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: cardSize.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position + 1). \(object.displayName), \(owner(object))")
        .accessibilityValue(PromptDisplayText.clean(object.rulesText ?? ""))
        .accessibilityHint(object.displaySourceCard == nil ? "" : "Tap to read the card")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("arena.stack.\(object.id)")
    }

    /// "Yours" or "Aurelia's".
    private func owner(_ object: XmageStackObject) -> String {
        guard let controller = object.controllerId else { return object.displaySourceName }
        return snapshot.isViewer(controller) ? "Yours" : "\(snapshot.playerLabel(controller))’s"
    }
}

/// A question the Arena way (Caleb, 2026-10-20; the reference's "Pay 2 life?"): the table dims, the question is the
/// title, the card it's about stands in the middle (an ability as its ability card), and the answers sit under it as
/// plaques. "View Battlefield" steps it aside.
struct ArenaQuestionStage<Answers: View>: View {
    let title: String
    let object: XmageStackObject?
    let card: ZoneCard?
    let screen: CGSize
    let inspect: (ZoneCard) -> Void
    @ViewBuilder let answers: Answers
    @State private var peeking = false

    var body: some View {
        let landscape = screen.width > screen.height
        let height = landscape ? min(screen.height * 0.48, 220) : min(screen.height * 0.36, 330)
        let size = CGSize(width: height * 0.72, height: height)
        ZStack {
            Color.black.opacity(peeking ? 0 : 0.72).ignoresSafeArea()
                .allowsHitTesting(!peeking)
                .accessibilityHidden(true)
            VStack(spacing: landscape ? 10 : 18) {
                GameRulesText(source: PromptDisplayText.clean(title), cardName: object?.displaySourceName ?? card?.card.name, symbolSize: 18)
                    .font(.system(size: landscape ? 20 : 22, weight: .bold, design: .serif))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("arena.question.title")
                Group {
                    if let object, ArenaStackCard.isAbility(object) || object.displaySourceCard == nil {
                        ArenaAbilityCard(source: object.displaySourceCard, name: object.displaySourceCard == nil ? object.displayName : nil,
                                         text: object.rulesText ?? object.displayName, size: size)
                    } else if let shown = object?.displaySourceCard ?? card {
                        CardTile(card: shown, selected: false, zoneName: "Question", width: size.width, height: size.height, imageVariant: .inspection)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                .contentShape(Rectangle())
                .onTapGesture { if let shown = object?.displaySourceCard ?? card { inspect(shown) } }
                answers
            }
            .padding(.top, landscape ? 0 : 40)
            .opacity(peeking ? 0 : 1)
            .allowsHitTesting(!peeking)
            Button(peeking ? "Back to the question" : "View Battlefield") { peeking.toggle() }
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(ArenaGlass.text)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, landscape ? 4 : 50)
                .padding(.trailing, 16)
                .accessibilityIdentifier("arena.question.viewBattlefield")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.question")
    }
}

/// A modal spell's modes the Arena way: each mode is a card with the spell's art over its text, side by side over the
/// dimmed table; a tap chooses it (XMage asks again for each further mode). The prompt's own answers (Done) sit below.
struct ArenaModeBrowser: View {
    let title: String
    let detail: String
    let source: ZoneCard?
    let modes: [ChoicePromptOption]
    let pending: Bool
    let screen: CGSize
    var answers: [(id: String, title: String, action: () -> Void)] = []
    let choose: (ChoicePromptOption) -> Void
    let inspect: (ZoneCard) -> Void

    private var cardSize: CGSize {
        let landscape = screen.width > screen.height
        let height = min(landscape ? screen.height * 0.52 : 250, 250)
        return CGSize(width: height * 0.72, height: height)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(ArenaGlass.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                            ArenaAbilityCard(source: source, name: source == nil ? "Mode \(index + 1)" : nil, kind: "Mode \(index + 1)",
                                             text: Self.text(of: mode), size: cardSize)
                                .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
                                .contentShape(Rectangle())
                                .onTapGesture { guard !pending else { return }; GameHaptics.selection(); choose(mode) }
                                .onLongPressGesture(minimumDuration: 0.35) { if let source { inspect(source) } }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(PromptDisplayText.clean(mode.label))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("arena.mode.\(mode.id)")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(minWidth: screen.width)
                }
                if !answers.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(answers, id: \.id) { answer in
                            Button(answer.title, action: answer.action)
                                .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 16))
                                .frame(width: 150, height: 40)
                        }
                    }
                }
            }
            .disabled(pending)
            .opacity(pending ? 0.7 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.modeBrowser")
    }

    /// "1. Create a Treasure token." without its number: the card's place shows the order.
    static func text(of mode: ChoicePromptOption) -> String {
        let label = PromptDisplayText.clean(mode.label)
        guard let range = label.range(of: #"^\d+\.\s*"#, options: .regularExpression) else { return label }
        return String(label[range.upperBound...])
    }
}

/// The ability card's outline: square shoulders and a gently rounded foot.
struct ArenaAbilityShape: InsettableShape {
    var corner: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = max(0, corner - insetAmount)
        let foot = r.height * 0.1
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addArc(center: CGPoint(x: r.maxX - c, y: r.minY + c), radius: c, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - foot))
        path.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - foot), control: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addArc(center: CGPoint(x: r.minX + c, y: r.minY + c), radius: c, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ArenaAbilityShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// The light arc from the ability on the stack to what it points at (its targets, or its source when it has none).
struct ArenaStackArc: View {
    let from: CGRect
    let to: [CGRect]
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        Canvas { context, _ in
            for target in to {
                let start = CGPoint(x: from.minX, y: from.midY)
                let end = CGPoint(x: target.midX, y: target.midY)
                let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - abs(start.x - end.x) * 0.25 - 30)
                var path = Path()
                path.move(to: start)
                path.addQuadCurve(to: end, control: control)
                let trimmed = path.trimmedPath(from: 0, to: drawn)
                context.stroke(trimmed, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                context.stroke(trimmed, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                context.stroke(trimmed, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion { drawn = 1 } else { withAnimation(.easeOut(duration: 0.45)) { drawn = 1 } }
        }
    }
}

struct ArenaPromptCaption: View {
    let text: String

    var body: some View {
        GameRulesText(source: text, symbolSize: 15)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(TavernPalette.parchment)
            .shadow(color: .black, radius: 2)
            .shadow(color: .black.opacity(0.8), radius: 6)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .allowsHitTesting(false)
            .accessibilityIdentifier("board.arena.caption")
    }
}

/// Floating mana the reference's way: plain mana symbols by your portrait, one per mana; a symbol takes a tap while
/// you pay (XMage asks for floating mana then).
struct ArenaFloatingMana: View {
    let pool: ManaPool?
    let payable: Set<String>
    let spend: (String) -> Void

    var body: some View {
        let values: [(String, Int)] = [("W", pool?.W ?? 0), ("U", pool?.U ?? 0), ("B", pool?.B ?? 0),
                                       ("R", pool?.R ?? 0), ("G", pool?.G ?? 0), ("C", pool?.C ?? 0)].filter { $0.1 > 0 }
        HStack(spacing: 2) {
            ForEach(values, id: \.0) { symbol, count in
                let symbols = ManaSymbolView(symbol: symbol, size: 20)
                    .shadow(color: .black.opacity(0.75), radius: 1.5, y: 1)
                    .overlay(alignment: .bottomTrailing) {
                        if count > 1 {
                            Text("\(count)").font(.system(size: 10, weight: .black, design: .serif)).monospacedDigit()
                                .foregroundStyle(.white).padding(.horizontal, 3)
                                .background(Capsule().fill(Color.black.opacity(0.85)))
                                .offset(x: 5, y: 4)
                        }
                    }
                if payable.contains(symbol) {
                    Button { spend(symbol) } label: {
                        symbols.padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(Capsule().strokeBorder(TavernPalette.ember.opacity(0.8), lineWidth: 1.2).frame(height: 24))
                    .accessibilityLabel("Spend floating \(symbol) mana, \(count) available")
                    .accessibilityIdentifier("board.mana.spend.\(symbol)")
                } else {
                    symbols.padding(.horizontal, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(count) floating \(symbol) mana")
                }
            }
        }
        .padding(.horizontal, 5)
        .background(Capsule().fill(Color.black.opacity(0.45)).frame(height: 28))
        .overlay(Capsule().strokeBorder(TavernPalette.brass.opacity(0.55), lineWidth: 1).frame(height: 28))
    }
}
