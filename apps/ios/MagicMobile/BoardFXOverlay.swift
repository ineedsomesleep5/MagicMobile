import SwiftUI
import UIKit

// Board FX renderer. One Canvas draws every active effect as a pure function of
// elapsed time, with card flights layered above it: no per-particle state, no
// work while idle, and no hit testing. Event derivation lives in BoardEventTimeline.swift.

/// Board positions in the overlay's coordinate space.
struct BoardFXAnchors {
    var viewerID: String
    var viewerPoint: CGPoint
    var opponentPoint: CGPoint
    var stackPoint: CGPoint
    /// Where the viewer's hand sits and where an opponent's hidden hand is implied.
    var viewerHandPoint: CGPoint
    var opponentHandPoint: CGPoint

    func playerPoint(_ playerID: String) -> CGPoint { playerID == viewerID ? viewerPoint : opponentPoint }
    func handPoint(_ playerID: String?) -> CGPoint { playerID == viewerID ? viewerHandPoint : opponentHandPoint }
}

struct BoardFXOverlay: View {
    let effects: [ActiveBoardFX]
    let subjects: [String: ZoneCard]
    /// Rendered card rectangles in this overlay's coordinate space.
    let cardBounds: [String: CGRect]
    let anchors: BoardFXAnchors
    let prune: () -> Void

    /// Cards that just left the battlefield no longer report bounds; keep their last rectangle.
    @State private var lastKnownBounds: [String: CGRect] = [:]

    var body: some View {
        Group {
            if effects.isEmpty {
                Color.clear
            } else {
                TimelineView(.animation) { timeline in
                    let now = timeline.date
                    ZStack {
                        Canvas { context, _ in
                            for effect in effects {
                                guard let p = progress(effect, now: now) else { continue }
                                draw(effect.scheduled, progress: p, in: &context)
                            }
                        }
                        ForEach(flights) { flight in
                            if let p = progress(flight.effect, now: now), let placement = flight.placement(progress: p) {
                                CardTile(card: flight.card, selected: false, zoneName: "Effect",
                                         width: placement.size.width, height: placement.size.height, ignoreTappedRotation: true)
                                    .shadow(color: .black.opacity(0.55), radius: 10, y: 6)
                                    .scaleEffect(placement.scale)
                                    .rotationEffect(.degrees(placement.rotation))
                                    .opacity(placement.opacity)
                                    .position(placement.center)
                            }
                        }
                    }
                }
                .task(id: effects.last?.id) {
                    guard let end = effects.map(\.endDate).max() else { return }
                    let wait = end.timeIntervalSinceNow + 0.05
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard !Task.isCancelled else { return }
                    prune()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { lastKnownBounds = cardBounds }
        .onChange(of: cardBounds) { _, bounds in
            lastKnownBounds.merge(bounds, uniquingKeysWith: { _, new in new })
            if lastKnownBounds.count > 400 { lastKnownBounds = bounds }
        }
    }

    private func rect(_ cardID: String) -> CGRect? {
        cardBounds[cardID] ?? lastKnownBounds[cardID]
    }

    private func progress(_ effect: ActiveBoardFX, now: Date) -> Double? {
        let elapsed = now.timeIntervalSince(effect.start) - effect.scheduled.delay
        guard elapsed >= 0, elapsed <= effect.scheduled.duration else { return nil }
        return elapsed / effect.scheduled.duration
    }

    private var flights: [BoardFXFlight] {
        effects.compactMap { effect in
            guard effect.scheduled.usesMotion, let card = subjects[effect.scheduled.event.subjectID] else { return nil }
            switch effect.scheduled.event {
            case let .enteredBattlefield(id, playerID, source, _):
                guard let target = rect(id) else { return nil }
                let origin = source == .stack ? anchors.stackPoint : anchors.handPoint(playerID)
                return BoardFXFlight(effect: effect, card: card, kind: .arrive(from: origin, to: target))
            case let .leftBattlefield(id, playerID, destination, _):
                guard let origin = rect(id) else { return nil }
                let target = destination == .hand ? anchors.handPoint(playerID) : anchors.playerPoint(playerID)
                return BoardFXFlight(effect: effect, card: card, kind: .depart(from: origin, to: target))
            case let .spellCast(_, _, controllerID, _):
                return BoardFXFlight(effect: effect, card: card,
                                     kind: .cast(from: anchors.handPoint(controllerID), to: anchors.stackPoint))
            default:
                return nil
            }
        }
    }

    private func draw(_ fx: ScheduledBoardFX, progress p: Double, in context: inout GraphicsContext) {
        let motion = fx.usesMotion
        switch fx.event {
        case let .spellCast(_, name, _, tint):
            let stackPoint = anchors.stackPoint
            BoardFXPainter.runeBurst(at: stackPoint, color: tint.color, progress: p, seed: fx.id, motion: motion, in: &context)
            BoardFXPainter.banner(name, at: CGPoint(x: stackPoint.x, y: stackPoint.y - 54), color: tint.color, progress: p, in: &context)
        case let .enteredBattlefield(cardID, _, _, tint):
            guard let rect = rect(cardID) else { return }
            // With a flight, the glow is the landing; without one it plays immediately.
            let flying = motion && subjects[cardID] != nil
            let landing = BoardFXScheduler.arrivalFlightFraction
            guard !flying || p >= landing else { return }
            let glow = flying ? (p - landing) / (1 - landing) : p
            BoardFXPainter.arrivalGlow(rect, color: tint.color, progress: glow, motion: motion, in: &context)
            if motion { BoardFXPainter.sparks(from: rect, color: tint.color, count: 16, progress: glow, seed: fx.id, style: .rise, in: &context) }
        case let .leftBattlefield(cardID, _, destination, tint):
            guard let rect = rect(cardID) else { return }
            if !(motion && subjects[cardID] != nil) {
                BoardFXPainter.departure(rect, color: tint.color, destination: destination, progress: p, motion: motion, in: &context)
            }
            if motion {
                let style: BoardFXPainter.SparkStyle = destination == .exile ? .rise : .fall
                let color = destination == .exile ? Color(red: 0.72, green: 0.9, blue: 1) : Color(red: 1, green: 0.45, blue: 0.16)
                BoardFXPainter.sparks(from: rect, color: color, count: 22, progress: p, seed: fx.id, style: style, in: &context)
            }
        case let .damageMarked(cardID, amount):
            guard let rect = rect(cardID) else { return }
            BoardFXPainter.flash(rect, color: .red, progress: p, in: &context)
            if motion { BoardFXPainter.sparks(from: rect, color: Color(red: 1, green: 0.3, blue: 0.2), count: 12, progress: p, seed: fx.id, style: .burst, in: &context) }
            BoardFXPainter.number("-\(amount)", at: CGPoint(x: rect.midX, y: rect.midY), color: Color(red: 1, green: 0.32, blue: 0.28), size: 26, progress: p, motion: motion, in: &context)
        case let .countersAdded(cardID, amount):
            guard let rect = rect(cardID) else { return }
            if motion { BoardFXPainter.sparks(from: rect, color: Color(red: 0.55, green: 1, blue: 0.55), count: 10, progress: p, seed: fx.id, style: .rise, in: &context) }
            BoardFXPainter.number("+\(amount)", at: CGPoint(x: rect.midX, y: rect.minY + 12), color: Color(red: 0.55, green: 1, blue: 0.55), size: 20, progress: p, motion: motion, in: &context)
        case let .attackDeclared(cardID, tint):
            guard let rect = rect(cardID) else { return }
            BoardFXPainter.arrivalGlow(rect, color: Color(red: 1, green: 0.36, blue: 0.2), progress: p, motion: motion, in: &context)
            if motion { BoardFXPainter.sparks(from: rect, color: tint.color, count: 8, progress: p, seed: fx.id, style: .burst, in: &context) }
        case let .lifeChanged(playerID, delta):
            let point = anchors.playerPoint(playerID)
            let color = delta < 0 ? Color(red: 1, green: 0.3, blue: 0.26) : Color(red: 0.45, green: 1, blue: 0.55)
            BoardFXPainter.number(delta < 0 ? "\(delta)" : "+\(delta)", at: point, color: color, size: 40, progress: p, motion: motion, in: &context)
        }
    }
}

extension BoardFXTint {
    var color: Color {
        switch self {
        case .white: return Color(red: 1, green: 0.95, blue: 0.78)
        case .blue: return Color(red: 0.36, green: 0.66, blue: 1)
        case .black: return Color(red: 0.72, green: 0.48, blue: 0.95)
        case .red: return Color(red: 1, green: 0.42, blue: 0.22)
        case .green: return Color(red: 0.42, green: 0.9, blue: 0.45)
        case .multicolor: return Color(red: 1, green: 0.8, blue: 0.32)
        case .colorless: return Color(red: 0.82, green: 0.84, blue: 0.9)
        }
    }
}

enum BoardFXPainter {
    enum SparkStyle { case rise, fall, burst }

    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }

    /// Deterministic 0..<1 noise so particles need no stored state.
    static func noise(_ seed: Int, _ index: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 73_856_093 ^ index &* 19_349_663 ^ salt &* 83_492_791)
        x ^= x >> 33; x &*= 0xff51afd7ed558ccd; x ^= x >> 33; x &*= 0xc4ceb9fe1a85ec53; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    static func sparks(from rect: CGRect, color: Color, count: Int, progress p: Double, seed: Int,
                       style: SparkStyle, in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        let t = p * 0.9
        for i in 0..<count {
            let origin = CGPoint(x: rect.minX + rect.width * noise(seed, i, 1), y: rect.minY + rect.height * noise(seed, i, 2))
            let speed = 40 + 90 * noise(seed, i, 3)
            let angle: Double
            let gravity: Double
            switch style {
            case .rise: angle = -.pi / 2 + (noise(seed, i, 4) - 0.5) * 0.9; gravity = -30
            case .fall: angle = .pi / 2 + (noise(seed, i, 4) - 0.5) * 1.4; gravity = 120
            case .burst: angle = noise(seed, i, 4) * 2 * .pi; gravity = 60
            }
            let x = origin.x + cos(angle) * speed * t
            let y = origin.y + sin(angle) * speed * t + gravity * t * t
            let radius = (1.2 + 2.2 * noise(seed, i, 5)) * (1 - p * 0.6)
            layer.opacity = (1 - p) * (0.6 + 0.4 * noise(seed, i, 6))
            layer.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }
    }

    static func arrivalGlow(_ rect: CGRect, color: Color, progress p: Double, motion: Bool, in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        let grow = motion ? 14 * easeOut(p) : 0
        let frame = rect.insetBy(dx: -grow, dy: -grow)
        layer.opacity = 1 - p
        layer.stroke(Path(roundedRect: frame, cornerRadius: 8 + grow / 2), with: .color(color), lineWidth: 1 + 3 * (1 - p))
        layer.opacity = 0.35 * (1 - p)
        layer.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color))
    }

    static func departure(_ rect: CGRect, color: Color, destination: BoardFXZone?, progress p: Double,
                          motion: Bool, in context: inout GraphicsContext) {
        let shrink = motion ? 0.2 * easeOut(p) : 0
        let drift: Double = motion ? (destination == .exile ? -18 : 14) * easeOut(p) : 0
        let frame = rect.insetBy(dx: rect.width * shrink / 2, dy: rect.height * shrink / 2).offsetBy(dx: 0, dy: drift)
        var layer = context
        layer.opacity = 0.7 * (1 - p)
        layer.fill(Path(roundedRect: frame, cornerRadius: 6), with: .color(Color.black.opacity(0.55)))
        layer.stroke(Path(roundedRect: frame, cornerRadius: 6), with: .color(color), lineWidth: 2)
    }

    static func flash(_ rect: CGRect, color: Color, progress p: Double, in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        layer.opacity = 0.55 * max(0, 1 - p * 2.2)
        layer.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color))
    }

    static func runeBurst(at center: CGPoint, color: Color, progress p: Double, seed: Int, motion: Bool,
                          in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        let outer = motion ? 24 + 70 * easeOut(p) : 46
        let inner = motion ? 14 + 40 * easeOut(min(1, p * 1.3)) : 30
        layer.opacity = 1 - p
        layer.stroke(Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)),
                     with: .color(color), lineWidth: 2.5)
        layer.opacity = 0.7 * (1 - p)
        layer.stroke(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)),
                     with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6], dashPhase: p * 40))
        if motion {
            sparks(from: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12), color: color, count: 18,
                   progress: p, seed: seed, style: .burst, in: &context)
        }
    }

    static func banner(_ title: String, at point: CGPoint, color: Color, progress p: Double, in context: inout GraphicsContext) {
        let fade = p < 0.15 ? p / 0.15 : (p > 0.7 ? (1 - p) / 0.3 : 1)
        var layer = context
        layer.opacity = fade
        let text = layer.resolve(Text(title).font(.system(size: 14, weight: .heavy, design: .serif)).foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 260, height: 40))
        let frame = CGRect(x: point.x - size.width / 2 - 12, y: point.y - size.height / 2 - 6, width: size.width + 24, height: size.height + 12)
        layer.fill(Path(roundedRect: frame, cornerRadius: frame.height / 2), with: .color(Color.black.opacity(0.72)))
        layer.stroke(Path(roundedRect: frame, cornerRadius: frame.height / 2), with: .color(color), lineWidth: 1.5)
        layer.draw(text, at: point)
    }

    static func number(_ value: String, at point: CGPoint, color: Color, size: CGFloat, progress p: Double,
                       motion: Bool, in context: inout GraphicsContext) {
        let pop = motion && p < 0.18 ? 1 + 0.45 * (1 - p / 0.18) : 1
        let rise = motion ? -34 * easeOut(p) : -8 * p
        let fade = p > 0.65 ? (1 - p) / 0.35 : 1
        var layer = context
        layer.opacity = fade
        layer.translateBy(x: point.x, y: point.y + rise)
        layer.scaleBy(x: pop, y: pop)
        let shadow = layer.resolve(Text(value).font(.system(size: size, weight: .black, design: .rounded)).foregroundStyle(.black.opacity(0.8)))
        layer.draw(shadow, at: CGPoint(x: 1.5, y: 2))
        let text = layer.resolve(Text(value).font(.system(size: size, weight: .black, design: .rounded)).foregroundStyle(color))
        layer.draw(text, at: .zero)
    }
}

/// Brief horizontal shake for hits on the local player. Integer values rest at zero.
struct BoardImpactShake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(animatableData * .pi * 6) * 6 * (1 - animatableData.truncatingRemainder(dividingBy: 1))
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

enum BoardFXHaptics {
    @MainActor
    static func play(_ scheduled: [ScheduledBoardFX], viewerID: String) {
        if scheduled.contains(where: { if case let .lifeChanged(id, delta) = $0.event { return id == viewerID && delta < 0 }; return false }) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if scheduled.contains(where: { if case .leftBattlefield = $0.event { return true }; return false }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct BoardEffectsPicker: View {
    @AppStorage(BoardFXLevel.key) private var level = BoardFXLevel.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Board Effects")
                    .font(.callout.weight(.black))
                    .foregroundStyle(.white)
                Text("Spell, combat and life animations. Reduce Motion always limits them.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
            Picker("Board Effects", selection: $level) {
                ForEach(BoardFXLevel.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.boardEffects")
        }
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 10)
    }
}

/// One card face moving across the board for an effect.
struct BoardFXFlight: Identifiable {
    enum Kind {
        case arrive(from: CGPoint, to: CGRect)
        case depart(from: CGRect, to: CGPoint)
        case cast(from: CGPoint, to: CGPoint)
    }

    struct Placement {
        var center: CGPoint
        var size: CGSize
        var scale: CGFloat
        var rotation: Double
        var opacity: Double
    }

    let effect: ActiveBoardFX
    let card: ZoneCard
    let kind: Kind

    var id: Int { effect.id }

    /// Quadratic arc between two points, lifted toward the top of the screen.
    static func arc(_ a: CGPoint, _ b: CGPoint, lift: CGFloat, t: Double) -> CGPoint {
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - lift)
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
    }

    func placement(progress p: Double) -> Placement? {
        switch kind {
        case let .arrive(from, to):
            let landing = BoardFXScheduler.arrivalFlightFraction
            guard p < landing else { return nil }
            let t = BoardFXPainter.easeOut(p / landing)
            return Placement(center: Self.arc(from, CGPoint(x: to.midX, y: to.midY), lift: 60, t: t),
                             size: to.size, scale: 1.35 - 0.35 * t, rotation: -8 * (1 - t), opacity: min(1, p / landing * 4))
        case let .depart(from, to):
            let t = p * p
            return Placement(center: Self.arc(CGPoint(x: from.midX, y: from.midY), to, lift: 30, t: t),
                             size: from.size, scale: 1 - 0.6 * t, rotation: 14 * t, opacity: 1 - t)
        case let .cast(from, to):
            let size = CGSize(width: 86, height: 120)
            if p < 0.3 {
                let t = BoardFXPainter.easeOut(p / 0.3)
                return Placement(center: Self.arc(from, to, lift: 40, t: t), size: size, scale: 0.6 + 0.5 * t,
                                 rotation: -6 * (1 - t), opacity: min(1, p / 0.3 * 3))
            }
            let hold = (p - 0.3) / 0.7
            return Placement(center: to, size: size, scale: 1.1 - 0.15 * hold, rotation: 0,
                             opacity: hold < 0.6 ? 1 : 1 - (hold - 0.6) / 0.4)
        }
    }
}

private struct BoardFXCardMotionKey: EnvironmentKey {
    static let defaultValue = BoardFXCardMotion()
}

extension EnvironmentValues {
    var boardFXCardMotion: BoardFXCardMotion {
        get { self[BoardFXCardMotionKey.self] }
        set { self[BoardFXCardMotionKey.self] = newValue }
    }
}

/// Applied to real board tiles: hides a card while its flight is in the air and
/// lunges attackers. Layout and anchors are unaffected.
struct BoardFXCardMotionModifier: ViewModifier {
    let cardID: String
    @Environment(\.boardFXCardMotion) private var motion
    @State private var landed: Date?

    func body(content: Content) -> some View {
        let landing = motion.arrivals[cardID]
        let hidden = landing.map { landed != $0 && $0 > Date() } ?? false
        let lunge = motion.lunges[cardID]
        // Direction 0 (no lunge) keeps the offset at zero when the trigger resets.
        let direction = CGFloat(lunge?.direction ?? 0)
        content
            .opacity(hidden ? 0 : 1)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: lunge?.token ?? -1) { view, value in
                view.offset(y: value * direction)
            } keyframes: { _ in
                SpringKeyframe(CGFloat(22), duration: 0.18, spring: .snappy)
                SpringKeyframe(CGFloat.zero, duration: 0.34, spring: .bouncy)
            }
            .task(id: landing) {
                guard let landing else { return }
                let wait = landing.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                landed = landing
            }
    }
}

extension View {
    func boardFXCardMotion(_ cardID: String) -> some View {
        modifier(BoardFXCardMotionModifier(cardID: cardID))
    }
}
