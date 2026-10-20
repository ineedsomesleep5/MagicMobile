import SwiftUI
import UIKit

// The Arena board's table pieces (BoardMode.arena). Positions come from ArenaLayout through ArenaCanvas; behaviour stays
// with the views and helpers the Hearth board already uses (PlayerZoneMenu, BattlefieldRow, GameActionDockModel…).

struct ArenaBoardKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True while the Arena board draws: battlefield tiles lean back with the table and tapped ones tilt instead of turning.
    var arenaBoard: Bool {
        get { self[ArenaBoardKey.self] }
        set { self[ArenaBoardKey.self] = newValue }
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
        .rotation3DEffect(.degrees(24), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        .overlay(alignment: .bottomTrailing) {
            if count > 0 { ArenaCountBadge(count: count).offset(x: 8, y: -2) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
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

/// The reference's phase strip: dark icons rimmed in the active player's colour on a thin track. The current step
/// ignites; moving on sends a spark along the track to the next icon.
struct ArenaPhaseStrip: View {
    let step: String?
    let viewerTurn: Bool
    let width: CGFloat
    var iconSize: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit: Int?
    @State private var sparkX: CGFloat?
    @State private var ignite = false

    enum Icon { case diamond, card, sword, swords, shield, burst }

    /// The strip's icons and which is current; combat opens into its steps while it runs.
    static func items(for step: String?) -> (icons: [Icon], current: Int?) {
        let described = TavernPhaseTrack.describe(step)
        let raw = (step ?? "").lowercased().replacingOccurrences(of: "_", with: "-")
        guard described.phase == 2 else {
            return ([.diamond, .card, .sword, .card, .diamond], described.phase)
        }
        let combat: Int
        switch raw {
        case "declare-attackers": combat = 1
        case "declare-blockers": combat = 2
        case "first-combat-damage", "first-strike-damage", "combat-damage", "end-combat": combat = 3
        default: combat = 0
        }
        return ([.diamond, .card, .sword, .swords, .shield, .burst, .card, .diamond], 2 + combat)
    }

    var body: some View {
        let items = Self.items(for: step)
        let rim = viewerTurn ? ArenaPalette.viewerRim : ArenaPalette.opponentRim
        let spacing = (width - 12) / CGFloat(max(items.icons.count, 1))
        let positions = items.icons.indices.map { 6 + spacing * (CGFloat($0) + 0.5) }
        ZStack(alignment: .leading) {
            Capsule().fill(rim.opacity(0.65)).frame(width: width, height: 1.4)
            ForEach(Array(items.icons.enumerated()), id: \.offset) { index, icon in
                let on = index == (lit ?? items.current)
                ArenaPhaseIcon(icon: icon, rim: rim, on: on, size: iconSize * (icon == .diamond ? 0.7 : 1))
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
        .onChange(of: items.current) { old, new in move(from: old, to: new, positions: positions) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TavernPhaseTrack.describe(step).title)
        .accessibilityIdentifier("board.phase.plate")
    }

    private func move(from old: Int?, to new: Int?, positions: [CGFloat]) {
        guard let new, new < positions.count else { lit = nil; return }
        guard !reduceMotion, let old, old < positions.count, old != new else { lit = new; return }
        let distance = abs(positions[new] - positions[old])
        let duration = 0.22 + min(0.26, Double(distance) * 0.0022)
        lit = -1
        sparkX = positions[old]
        withAnimation(.easeInOut(duration: duration)) { sparkX = positions[new] }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            sparkX = nil
            lit = new
            withAnimation(.easeOut(duration: 0.08)) { ignite = true }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.35)) { ignite = false }
        }
    }
}

struct ArenaPhaseIcon: View {
    let icon: ArenaPhaseStrip.Icon
    let rim: Color
    let on: Bool
    let size: CGFloat

    var body: some View {
        let shape = ArenaPhaseShape(icon: icon)
        ZStack {
            shape.fill(on ? AnyShapeStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.85, blue: 0.55), rim],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(ArenaPalette.iconFill))
            shape.stroke(on ? Color.white.opacity(0.9) : rim, lineWidth: 1.2)
        }
        .frame(width: size, height: size)
        .shadow(color: on ? rim : .clear, radius: on ? 4 : 0)
        .shadow(color: on ? rim.opacity(0.8) : .clear, radius: on ? 9 : 0)
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
            return Path(roundedRect: CGRect(x: rect.minX + 5 * scale, y: rect.minY + 2.5 * scale, width: 10 * scale, height: 15 * scale),
                        cornerRadius: 2 * scale)
        case .sword:
            var path = polygon(blade)
            path.addPath(polygon(guardBar)); path.addPath(polygon(grip))
            return path
        case .swords:
            var path = polygon(blade)
            path.addPath(polygon(guardBar)); path.addPath(polygon(grip))
            path.addPath(polygon([(2.4, 2.4), (5.4, 2.9), (13.9, 11.4), (11.4, 13.9), (2.9, 5.4)]))
            path.addPath(polygon([(16.1, 10.6), (10.6, 16.1), (11.8, 17.3), (17.3, 11.8)]))
            path.addPath(polygon([(14.4, 15.2), (16.7, 17.5), (17.5, 16.7), (15.2, 14.4)]))
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
    let inspect: (ZoneCard) -> Void
    let openStack: () -> Void

    var body: some View {
        ZStack {
            if let card = object.displaySourceCard {
                Button { inspect(card) } label: {
                    CardTile(card: card, selected: false, zoneName: "Stack", width: size.width, height: size.height,
                             imageVariant: .inspection)
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            } else {
                abilityPanel
            }
        }
        .frame(width: size.width, height: size.height)
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
        .accessibilityLabel("Top of the stack: \(object.displayName)")
    }

    /// An ability or a spell whose card isn't known: its name and text on parchment in a brass frame.
    private var abilityPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(object.displayName)
                .font(.system(size: max(11, size.width * 0.085), weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.22, green: 0.11, blue: 0.04))
                .lineLimit(2).minimumScaleFactor(0.7)
            Rectangle().fill(TavernPalette.brass.opacity(0.6)).frame(height: 1)
            Text(PromptDisplayText.clean(object.rulesText ?? object.displaySourceName))
                .font(.system(size: max(9, size.width * 0.065), weight: .regular, design: .serif))
                .foregroundStyle(Color(red: 0.22, green: 0.11, blue: 0.04))
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(size.width * 0.08)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(TavernFill(material: .parchment))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { TavernBrassFrame(scale: 0.45) }
        .onTapGesture { if let card = object.displaySourceCard { inspect(card) } }
    }
}

/// The slim caption over the midline that says what the table wants ("Choose attackers.", "Pay {1}{R}").
struct ArenaPromptCaption: View {
    let text: String

    var body: some View {
        GameRulesText(source: text, symbolSize: 15)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(TavernPalette.parchment)
            .shadow(color: .black, radius: 2)
            .shadow(color: .black.opacity(0.8), radius: 6)
            .lineLimit(2)
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
        HStack(spacing: 1) {
            ForEach(values, id: \.0) { symbol, count in
                let symbols = HStack(spacing: -4) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        ManaSymbolView(symbol: symbol, size: 18).shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
                    }
                    if count > 3 {
                        Text("+\(count - 3)").font(.system(size: 10, weight: .heavy, design: .serif))
                            .foregroundStyle(TavernPalette.parchment).shadow(color: .black, radius: 1).padding(.leading, 5)
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
        .padding(.horizontal, 4)
        .background(Capsule().fill(Color.black.opacity(0.35)).frame(height: 26))
    }
}
