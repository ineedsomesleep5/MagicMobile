import AVFoundation
import SwiftUI
import UIKit

// Board FX renderer. One Canvas draws every active effect as a pure function of
// elapsed time, with card flights layered above it: no per-particle state, no
// work while idle, and no hit testing. Event derivation lives in BoardEventTimeline.swift.

#if DEBUG
/// Visual QA: `MAGICMOBILE_BOARD_FX_FREEZE=<seconds>` holds every effect batch at that
/// moment and never prunes it, so a design preview can be screenshotted mid-effect.
enum BoardFXPreviewFreeze {
    static let seconds: TimeInterval? = ProcessInfo.processInfo.environment["MAGICMOBILE_BOARD_FX_FREEZE"].flatMap(TimeInterval.init)
}
#endif

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
    let clock: BoardFXClock
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
                    let _ = clock.observe(effects, at: now)
                    ZStack {
                        Canvas { context, size in
                            for effect in effects {
                                guard let p = progress(effect, now: now) else { continue }
                                let elapsed = p * effect.scheduled.duration
                                draw(effect.scheduled, progress: p, elapsed: elapsed, size: size, in: &context)
                            }
                        }
                        ForEach(flights) { flight in
                            if let p = progress(flight.effect, now: now), let placement = flight.placement(progress: p) {
                                Group {
                                    if placement.fullCard {
                                        CardTile(card: flight.card, selected: false, zoneName: "Effect",
                                                 width: placement.size.width, height: placement.size.height, ignoreTappedRotation: true)
                                    } else {
                                        // Same frame as the battlefield tile, so take-off and landing are seamless.
                                        ArenaBattlefieldCard(card: flight.card, zoneName: "Effect",
                                                             width: placement.size.width, height: placement.size.height)
                                    }
                                }
                                    .modifier(BoardFXShading(shading: flight.shading(progress: p), size: placement.size))
                                    .shadow(color: .black.opacity(0.55), radius: 10 + 8 * placement.lift, y: 6 + 10 * placement.lift)
                                    .scaleEffect(placement.scale)
                                    .rotationEffect(.degrees(placement.rotation))
                                    .opacity(placement.opacity)
                                    .position(placement.center)
                            }
                        }
                    }
                }
                .task(id: effects.last?.id) {
                    #if DEBUG
                    // A frozen preview keeps its effects on screen.
                    if BoardFXPreviewFreeze.seconds != nil { return }
                    #endif
                    // Wait for the last effect's end on the frame clock; batches not yet
                    // drawn count from now.
                    while !Task.isCancelled {
                        let now = Date()
                        let end = effects.map { effect in
                            (clock.origin(for: effect.start) ?? now).addingTimeInterval(effect.scheduled.end)
                        }.max() ?? now
                        let wait = end.timeIntervalSince(now) + 0.05
                        if wait <= 0.05 && effects.allSatisfy({ clock.origin(for: $0.start) != nil }) { break }
                        try? await Task.sleep(for: .seconds(max(wait, 0.05)))
                    }
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

    private func point(_ target: BoardFXStrikeTarget) -> CGPoint? {
        switch target {
        case let .card(id): return rect(id).map { CGPoint(x: $0.midX, y: $0.midY) }
        case let .player(id): return anchors.playerPoint(id)
        }
    }

    private func progress(_ effect: ActiveBoardFX, now: Date) -> Double? {
        guard let origin = clock.origin(for: effect.start) else { return nil }
        var sinceStart = now.timeIntervalSince(origin)
        #if DEBUG
        if let freeze = BoardFXPreviewFreeze.seconds { sinceStart = min(sinceStart, freeze) }
        #endif
        let elapsed = sinceStart - effect.scheduled.delay
        guard elapsed >= 0, elapsed <= effect.scheduled.duration else { return nil }
        return elapsed / effect.scheduled.duration
    }

    private var flights: [BoardFXFlight] {
        effects.compactMap { effect in
            let fx = effect.scheduled
            guard fx.usesMotion, let card = subjects[fx.event.subjectID] else { return nil }
            switch fx.event {
            case let .enteredBattlefield(id, playerID, source, _, entrance):
                guard let target = rect(id) else { return nil }
                let origin = source == .stack ? anchors.stackPoint : anchors.handPoint(playerID)
                let kind: BoardFXFlight.Kind = entrance == .plain
                    ? .arrive(from: origin, to: target)
                    : .showcaseArrive(from: origin, center: anchors.stackPoint, to: target, commander: entrance == .commander)
                return BoardFXFlight(effect: effect, card: card, kind: kind)
            case let .leftBattlefield(id, playerID, destination, _):
                guard let origin = rect(id) else { return nil }
                let target = destination == .hand ? anchors.handPoint(playerID) : anchors.playerPoint(playerID)
                return BoardFXFlight(effect: effect, card: card, kind: .depart(from: origin, to: target, destination: destination))
            case let .spellCast(_, _, controllerID, _, weight):
                return BoardFXFlight(effect: effect, card: card,
                                     kind: .cast(from: anchors.handPoint(controllerID), to: anchors.stackPoint, weight: weight))
            case let .combatStrike(id, target, _, _):
                guard let origin = rect(id), let hit = point(target) else { return nil }
                return BoardFXFlight(effect: effect, card: card, kind: .strike(from: origin, to: hit))
            default:
                return nil
            }
        }
    }

    private func draw(_ fx: ScheduledBoardFX, progress p: Double, elapsed: Double, size: CGSize,
                      in context: inout GraphicsContext) {
        let motion = fx.usesMotion
        switch fx.event {
        case let .spellCast(stackID, name, _, tint, weight):
            let center = anchors.stackPoint
            let showcase = BoardFXFlight.castSize(weight)
            if weight == .big || weight == .commander {
                BoardFXPainter.screenFlash(size, color: weight == .commander ? BoardFXPainter.gold : tint.color,
                                           progress: elapsed / 0.6, in: &context)
                if motion {
                    BoardFXPainter.rays(at: center, color: weight == .commander ? BoardFXPainter.gold : tint.color,
                                        radius: showcase.height * 1.3, progress: p, elapsed: elapsed, in: &context)
                }
            }
            BoardFXPainter.runeBurst(at: center, color: tint.color, progress: min(1, elapsed / 1.1), seed: fx.id,
                                     motion: motion, in: &context)
            if motion && weight != .ability {
                let hold = CGRect(x: center.x - showcase.width / 2, y: center.y - showcase.height / 2,
                                  width: showcase.width, height: showcase.height)
                BoardFXPainter.elemental(tint, around: hold, elapsed: elapsed, fade: BoardFXPainter.window(p, fadeIn: 0.12, fadeOut: 0.85),
                                         seed: fx.id, in: &context)
            }
            // Below the showcased card for abilities too (the card covered it at +54).
            let bannerY = center.y + BoardFXBannerPlan.offset(showcaseHeight: showcase.height, motion: motion)
            let title = BoardFXBannerPlan.title(name: name, isAbility: weight == .ability, sourceName: subjects[stackID]?.card.name)
            BoardFXPainter.banner(title, subtitle: weight == .commander ? "COMMANDER" : nil,
                                  at: CGPoint(x: center.x, y: bannerY), color: weight == .commander ? BoardFXPainter.gold : tint.color,
                                  progress: p, in: &context)
        case let .enteredBattlefield(cardID, _, _, tint, entrance):
            guard let rect = rect(cardID) else { return }
            // With a flight, the glow is the landing; without one it plays immediately.
            let flying = motion && subjects[cardID] != nil
            let landing = flying ? BoardFXScheduler.landingFraction(entrance) : 0
            if flying && entrance != .plain && p < landing {
                let center = anchors.stackPoint
                let showcase = BoardFXFlight.castSize(entrance == .commander ? .commander : .spell)
                let hold = CGRect(x: center.x - showcase.width / 2, y: center.y - showcase.height / 2,
                                  width: showcase.width, height: showcase.height)
                let fade = BoardFXPainter.window(p / landing, fadeIn: 0.15, fadeOut: 0.75)
                if entrance == .commander {
                    BoardFXPainter.screenFlash(size, color: BoardFXPainter.gold, progress: elapsed / 0.7, in: &context)
                    BoardFXPainter.rays(at: center, color: BoardFXPainter.gold, radius: showcase.height * 1.35,
                                        progress: p / landing, elapsed: elapsed, in: &context)
                }
                BoardFXPainter.elemental(tint, around: hold, elapsed: elapsed, fade: fade, seed: fx.id, in: &context)
                if let name = subjects[cardID]?.card.name {
                    BoardFXPainter.banner(name, subtitle: entrance == .commander ? "COMMANDER" : nil,
                                          at: CGPoint(x: center.x, y: center.y + showcase.height / 2 + 22),
                                          color: entrance == .commander ? BoardFXPainter.gold : tint.color,
                                          progress: min(1, p / (landing * 0.8)), in: &context)
                }
            }
            guard !flying || p >= landing else { return }
            let glow = flying ? (p - landing) / (1 - landing) : p
            let color = entrance == .commander ? BoardFXPainter.gold : tint.color
            BoardFXPainter.arrivalGlow(rect, color: color, progress: glow, motion: motion, in: &context)
            if motion {
                BoardFXPainter.sparks(from: rect, color: color, count: entrance == .commander ? 34 : 16, progress: glow,
                                      seed: fx.id, style: .rise, in: &context)
                if entrance == .commander {
                    BoardFXPainter.shockwave(at: CGPoint(x: rect.midX, y: rect.midY), color: color, maxRadius: 150,
                                             progress: glow, in: &context)
                }
            }
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
            BoardFXPainter.arrivalGlow(rect, color: BoardFXPainter.attackRed, progress: p, motion: motion, in: &context)
            if motion {
                BoardFXPainter.sparks(from: rect, color: tint.color, count: 10, progress: p, seed: fx.id, style: .burst, in: &context)
                BoardFXPainter.slash(across: rect, color: BoardFXPainter.attackRed, progress: p, in: &context)
            }
        case let .blockDeclared(cardID, attackerID):
            guard let blocker = rect(cardID) else { return }
            BoardFXPainter.arrivalGlow(blocker, color: BoardFXPainter.blockSteel, progress: p, motion: motion, in: &context)
            if let attacker = rect(attackerID) {
                BoardFXPainter.link(from: blocker, to: attacker, color: BoardFXPainter.blockSteel, progress: p, in: &context)
            }
        case .firstStrikeBeat:
            // XMage's first-strike damage step: named while its strikes, damage and deaths play.
            BoardFXPainter.banner("First strike", at: anchors.stackPoint, color: BoardFXPainter.attackRed, progress: p, in: &context)
        case let .combatStrike(attackerID, target, tint, _):
            guard let origin = rect(attackerID), let hit = point(target) else { return }
            let impact = BoardFXScheduler.strikeImpactFraction
            if motion && p > 0.15 && p < impact + 0.05 {
                BoardFXPainter.trail(from: CGPoint(x: origin.midX, y: origin.midY), to: hit, color: tint.color,
                                     progress: (p - 0.15) / (impact - 0.15), in: &context)
            }
            if p >= impact {
                let q = (p - impact) / (1 - impact)
                let hitRect = CGRect(x: hit.x - 30, y: hit.y - 30, width: 60, height: 60)
                BoardFXPainter.shockwave(at: hit, color: BoardFXPainter.attackRed, maxRadius: motion ? 70 : 40, progress: q, in: &context)
                if motion { BoardFXPainter.sparks(from: hitRect, color: Color(red: 1, green: 0.75, blue: 0.35), count: 20, progress: q, seed: fx.id, style: .burst, in: &context) }
            }
        case let .lifeChanged(playerID, delta):
            let point = anchors.playerPoint(playerID)
            let color = delta < 0 ? Color(red: 1, green: 0.3, blue: 0.26) : Color(red: 0.45, green: 1, blue: 0.55)
            // Bigger swings read bigger.
            let size = min(64, 34 + CGFloat(abs(delta)) * 2.5)
            BoardFXPainter.number(delta < 0 ? "\(delta)" : "+\(delta)", at: point, color: color, size: size, progress: p, motion: motion, in: &context)
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

    static let gold = Color(red: 1, green: 0.8, blue: 0.36)
    static let attackRed = Color(red: 1, green: 0.36, blue: 0.2)
    static let blockSteel = Color(red: 0.55, green: 0.78, blue: 1)

    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }
    static func easeIn(_ t: Double) -> Double { pow(min(max(t, 0), 1), 2.2) }

    /// 0 → 1 → 0 envelope over progress with linear fades.
    static func window(_ p: Double, fadeIn: Double, fadeOut: Double) -> Double {
        if p < fadeIn { return max(0, p / fadeIn) }
        if p > fadeOut { return max(0, 1 - (p - fadeOut) / max(0.001, 1 - fadeOut)) }
        return 1
    }

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

    /// Continuous color-identity particles around a showcased card: fire for red,
    /// frost for blue, leaves for green, light for white, smoke for black, gold
    /// glints for multicolor and steel sparks for colorless. `fade` scales it all.
    static func elemental(_ tint: BoardFXTint, around rect: CGRect, elapsed: Double, fade: Double, seed: Int,
                          in context: inout GraphicsContext) {
        guard fade > 0.01 else { return }
        var glow = context
        glow.blendMode = .plusLighter
        glow.opacity = 0.35 * fade
        glow.fill(Path(roundedRect: rect.insetBy(dx: -10, dy: -10), cornerRadius: 16),
                  with: .radialGradient(Gradient(colors: [tint.color.opacity(0.8), .clear]),
                                        center: CGPoint(x: rect.midX, y: rect.midY), startRadius: rect.width * 0.2,
                                        endRadius: rect.height * 0.75))
        let count = tint == .black ? 16 : 30
        for i in 0..<count {
            let rate = 0.55 + 0.6 * noise(seed, i, 11)
            let life = (elapsed * rate + noise(seed, i, 12)).truncatingRemainder(dividingBy: 1)
            // Emit along the card's edge.
            let edge = noise(seed, i, 13)
            let side = Int(noise(seed, i, 14) * 4)
            let start: CGPoint
            switch side {
            case 0: start = CGPoint(x: rect.minX + rect.width * edge, y: rect.maxY)
            case 1: start = CGPoint(x: rect.minX + rect.width * edge, y: rect.minY)
            case 2: start = CGPoint(x: rect.minX, y: rect.minY + rect.height * edge)
            default: start = CGPoint(x: rect.maxX, y: rect.minY + rect.height * edge)
            }
            let outward = CGPoint(x: start.x - rect.midX, y: start.y - rect.midY)
            let length = max(1, hypot(outward.x, outward.y))
            let out = CGPoint(x: outward.x / length, y: outward.y / length)
            var layer = context
            layer.blendMode = .plusLighter
            let alpha = fade * sin(.pi * life)
            switch tint {
            case .red:
                // Embers: rise and flicker from yellow to deep orange.
                let x = start.x + sin(elapsed * 6 + Double(i)) * 5 + out.x * 12 * life
                let y = start.y - 70 * life
                let r = 2.6 * (1 - life) + 0.8
                layer.opacity = alpha * (0.7 + 0.3 * sin(elapsed * 20 + Double(i)))
                let color = life < 0.4 ? Color(red: 1, green: 0.85, blue: 0.4) : Color(red: 1, green: 0.4, blue: 0.12)
                layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 1.6, width: r * 2, height: r * 3.2)), with: .color(color))
            case .blue:
                // Frost shards: small rotating diamonds drifting outward.
                let x = start.x + out.x * 34 * life
                let y = start.y + out.y * 34 * life + 10 * life
                let s = 4.5 * (1 - life * 0.5)
                layer.opacity = alpha * 0.9
                var shard = Path()
                shard.move(to: CGPoint(x: 0, y: -s * 1.6)); shard.addLine(to: CGPoint(x: s * 0.6, y: 0))
                shard.addLine(to: CGPoint(x: 0, y: s * 1.6)); shard.addLine(to: CGPoint(x: -s * 0.6, y: 0)); shard.closeSubpath()
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(elapsed * 2 + Double(i)))
                layer.fill(shard, with: .color(Color(red: 0.78, green: 0.93, blue: 1)))
            case .green:
                // Leaves: sway and spiral upward.
                let x = start.x + sin(elapsed * 3 + Double(i) * 1.7) * 14 * life + out.x * 10 * life
                let y = start.y - 55 * life
                layer.opacity = alpha * 0.85
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(elapsed * 3 + Double(i)))
                layer.fill(Path(ellipseIn: CGRect(x: -4.5, y: -2, width: 9, height: 4)),
                           with: .color(i.isMultiple(of: 3) ? Color(red: 0.8, green: 1, blue: 0.45) : Color(red: 0.35, green: 0.85, blue: 0.4)))
            case .white:
                // Motes of light drifting up with a soft halo.
                let x = start.x + out.x * 8 * life
                let y = start.y - 40 * life
                let r = 3 * (1 - life) + 1
                layer.opacity = alpha * 0.8
                layer.fill(Path(ellipseIn: CGRect(x: x - r * 2, y: y - r * 2, width: r * 4, height: r * 4)),
                           with: .color(Color(red: 1, green: 0.96, blue: 0.8).opacity(0.35)))
                layer.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(.white))
            case .black:
                // Smoke: slow expanding puffs, drawn normally so they darken.
                var smoke = context
                let x = start.x + out.x * 26 * life
                let y = start.y + out.y * 26 * life - 18 * life
                let r = 8 + 16 * life
                smoke.opacity = fade * 0.22 * (1 - life)
                smoke.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .color(Color(red: 0.16, green: 0.05, blue: 0.24)))
                layer.opacity = alpha * 0.8
                layer.fill(Path(ellipseIn: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)),
                           with: .color(Color(red: 0.78, green: 0.5, blue: 1)))
            case .multicolor, .colorless:
                // Glints: four-point stars that twinkle in place, just outside the card.
                let x = start.x + out.x * 10
                let y = start.y + out.y * 10
                let s = 5 * sin(.pi * life)
                layer.opacity = alpha
                var star = Path()
                star.move(to: CGPoint(x: x, y: y - s)); star.addLine(to: CGPoint(x: x + s * 0.25, y: y))
                star.addLine(to: CGPoint(x: x, y: y + s)); star.addLine(to: CGPoint(x: x - s * 0.25, y: y)); star.closeSubpath()
                star.move(to: CGPoint(x: x - s, y: y)); star.addLine(to: CGPoint(x: x, y: y + s * 0.25))
                star.addLine(to: CGPoint(x: x + s, y: y)); star.addLine(to: CGPoint(x: x, y: y - s * 0.25)); star.closeSubpath()
                layer.fill(star, with: .color(tint == .multicolor ? gold : Color(white: 0.92)))
            }
        }
    }

    /// Slowly turning light rays behind a hero card.
    static func rays(at center: CGPoint, color: Color, radius: CGFloat, progress p: Double, elapsed: Double,
                     in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        layer.opacity = 0.5 * window(p, fadeIn: 0.12, fadeOut: 0.8)
        let count = 14
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi + elapsed * 0.35
            let width = 0.09
            var ray = Path()
            ray.move(to: center)
            ray.addLine(to: CGPoint(x: center.x + cos(angle - width) * radius, y: center.y + sin(angle - width) * radius))
            ray.addLine(to: CGPoint(x: center.x + cos(angle + width) * radius, y: center.y + sin(angle + width) * radius))
            ray.closeSubpath()
            layer.fill(ray, with: .radialGradient(Gradient(colors: [color.opacity(0.9), .clear]), center: center,
                                                  startRadius: 0, endRadius: radius))
        }
    }

    /// Whole-board tint for big spells and commanders; `progress` 0...1 over the flash.
    static func screenFlash(_ size: CGSize, color: Color, progress p: Double, in context: inout GraphicsContext) {
        guard p < 1 else { return }
        var layer = context
        layer.blendMode = .plusLighter
        layer.opacity = 0.32 * (1 - max(0, p))
        layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
    }

    static func shockwave(at center: CGPoint, color: Color, maxRadius: CGFloat, progress p: Double,
                          in context: inout GraphicsContext) {
        guard p < 1 else { return }
        var layer = context
        layer.blendMode = .plusLighter
        let r = 8 + (maxRadius - 8) * easeOut(p)
        layer.opacity = 1 - p
        layer.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .color(color), lineWidth: 1 + 5 * (1 - p))
    }

    /// Diagonal claw mark across an attacker as it is declared.
    static func slash(across rect: CGRect, color: Color, progress p: Double, in context: inout GraphicsContext) {
        guard p < 0.6 else { return }
        let q = p / 0.6
        var layer = context
        layer.blendMode = .plusLighter
        layer.opacity = 1 - q
        for offset in [-8.0, 0, 8] {
            var cut = Path()
            let start = CGPoint(x: rect.minX + 4 + offset, y: rect.minY + 4)
            let end = CGPoint(x: rect.maxX - 4 + offset, y: rect.maxY - 4)
            cut.move(to: start)
            cut.addLine(to: CGPoint(x: start.x + (end.x - start.x) * easeOut(q * 1.6), y: start.y + (end.y - start.y) * easeOut(q * 1.6)))
            layer.stroke(cut, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    /// Glowing tether pairing a blocker with its attacker.
    static func link(from a: CGRect, to b: CGRect, color: Color, progress p: Double, in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        layer.opacity = window(p, fadeIn: 0.15, fadeOut: 0.7)
        var line = Path()
        let start = CGPoint(x: a.midX, y: a.midY), end = CGPoint(x: b.midX, y: b.midY)
        let reach = easeOut(p / 0.35)
        line.move(to: start)
        line.addLine(to: CGPoint(x: start.x + (end.x - start.x) * reach, y: start.y + (end.y - start.y) * reach))
        layer.stroke(line, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        layer.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 5], dashPhase: -p * 60))
    }

    /// Motion streak behind a charging attacker.
    static func trail(from: CGPoint, to: CGPoint, color: Color, progress p: Double, in context: inout GraphicsContext) {
        let head = easeIn(p) * 0.82
        let tail = max(0, head - 0.3)
        var layer = context
        layer.blendMode = .plusLighter
        layer.opacity = 0.8
        var streak = Path()
        streak.move(to: CGPoint(x: from.x + (to.x - from.x) * tail, y: from.y + (to.y - from.y) * tail))
        streak.addLine(to: CGPoint(x: from.x + (to.x - from.x) * head, y: from.y + (to.y - from.y) * head))
        layer.stroke(streak, with: .color(color.opacity(0.4)), style: StrokeStyle(lineWidth: 18, lineCap: .round))
        layer.stroke(streak, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
        guard p < 1 else { return }
        var layer = context
        layer.blendMode = .plusLighter
        let outer = motion ? 24 + 90 * easeOut(p) : 46
        let inner = motion ? 14 + 50 * easeOut(min(1, p * 1.3)) : 30
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

    static func banner(_ title: String, subtitle: String? = nil, at point: CGPoint, color: Color, progress p: Double,
                       in context: inout GraphicsContext) {
        let fade = window(p, fadeIn: 0.08, fadeOut: 0.82)
        guard fade > 0 else { return }
        var layer = context
        layer.opacity = fade
        let text = layer.resolve(Text(title).font(.system(size: 16, weight: .heavy, design: .serif)).foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 300, height: 44))
        let caption = subtitle.map {
            layer.resolve(Text($0).font(.system(size: 10, weight: .black)).tracking(2).foregroundStyle(color))
        }
        let captionHeight: CGFloat = caption == nil ? 0 : 13
        let frame = CGRect(x: point.x - size.width / 2 - 14, y: point.y - size.height / 2 - 7 - captionHeight / 2,
                           width: size.width + 28, height: size.height + 14 + captionHeight)
        layer.fill(Path(roundedRect: frame, cornerRadius: 12), with: .color(Color.black.opacity(0.78)))
        layer.stroke(Path(roundedRect: frame, cornerRadius: 12), with: .color(color), lineWidth: 1.5)
        if let caption {
            layer.draw(caption, at: CGPoint(x: point.x, y: frame.minY + 11))
            layer.draw(text, at: CGPoint(x: point.x, y: point.y + captionHeight / 2))
        } else {
            layer.draw(text, at: point)
        }
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
    /// Points of sideways travel; big hits also jolt the board down a little.
    var amplitude: CGFloat = 6

    func effectValue(size: CGSize) -> ProjectionTransform {
        let decay = 1 - animatableData.truncatingRemainder(dividingBy: 1)
        let offset = sin(animatableData * .pi * 6) * amplitude * decay
        let jolt = amplitude > 8 ? abs(sin(animatableData * .pi * 4)) * amplitude * 0.35 * decay : 0
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: jolt))
    }
}

/// A red edge that flares when you take a big hit.
struct BoardHitVignette: View {
    let strength: Double

    var body: some View {
        RadialGradient(colors: [.clear, .clear, Color(red: 0.85, green: 0.05, blue: 0.02).opacity(0.55)],
                       center: .center, startRadius: 0, endRadius: 520)
            .opacity(strength)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Board events to recorded cues (Resources/Audio, credited in CREDITS.txt and the Sound Lab).
/// Ambient session: respects the silent switch and mixes with the player's music.
@MainActor
enum BoardFXSound {
    static let key = GameAudio.effectsKey

    /// What arrived, so a land thuds, a token pops and a creature lands with weight.
    struct Arrival: Equatable {
        var isLand = false
        var isToken = false
    }

    /// Sounds for one board transition, each timed to the effect it accompanies. Casts use
    /// the spell's color identity; GameAudio's cooldowns turn bursts into a flurry.
    @MainActor
    static func play(_ scheduled: [ScheduledBoardFX], viewerID: String, arrivals: [String: Arrival] = [:]) {
        let hasStrike = scheduled.contains { if case .combatStrike = $0.event { return true }; return false }
        for cue in cues(scheduled, viewerID: viewerID, arrivals: arrivals, hasStrike: hasStrike) {
            GameAudio.shared.play(cue.sound, after: cue.at, volume: cue.volume)
        }
    }

    struct Cue: Equatable {
        let sound: GameSound
        let at: TimeInterval
        var volume: Float = 1
    }

    static func cues(_ scheduled: [ScheduledBoardFX], viewerID: String, arrivals: [String: Arrival] = [:],
                     hasStrike: Bool) -> [Cue] {
        var cues: [Cue] = []
        for fx in scheduled {
            switch fx.event {
            case let .spellCast(_, _, controllerID, tint, weight):
                // Opponents' spells sit a little further back in the mix.
                let level: Float = controllerID == viewerID ? 1 : 0.75
                switch weight {
                case .ability:
                    // Only your own abilities chime; a pod's triggers would otherwise chatter.
                    if controllerID == viewerID { cues.append(Cue(sound: .ability, at: fx.delay)) }
                case .commander: cues.append(Cue(sound: .commanderCast, at: fx.delay, volume: level))
                case .big:
                    cues.append(Cue(sound: GameSound.cast(for: tint), at: fx.delay, volume: level))
                    cues.append(Cue(sound: .spellBig, at: fx.delay + 0.05, volume: level))
                case .spell: cues.append(Cue(sound: GameSound.cast(for: tint), at: fx.delay, volume: level))
                }
            case .attackDeclared: cues.append(Cue(sound: .attack, at: fx.delay))
            case .blockDeclared: cues.append(Cue(sound: .block, at: fx.delay))
            case let .combatStrike(_, target, _, _):
                cues.append(Cue(sound: target == .player(viewerID) ? .playerHit : .strike, at: fx.handoff))
            case .firstStrikeBeat: break
            case .damageMarked:
                if !hasStrike { cues.append(Cue(sound: .strike, at: fx.delay, volume: 0.7)) }
            case let .leftBattlefield(_, _, to, _):
                switch to {
                case .exile?: cues.append(Cue(sound: .exile, at: fx.delay))
                case .hand?, .library?: cues.append(Cue(sound: .cardPickup, at: fx.delay))
                default: cues.append(Cue(sound: .death, at: fx.delay))
                }
            case let .enteredBattlefield(id, _, _, _, entrance):
                let arrival = arrivals[id] ?? Arrival()
                let sound: GameSound = entrance == .commander ? .creatureEnter
                    : arrival.isLand ? .landDrop : arrival.isToken ? .tokenCreate : .creatureEnter
                cues.append(Cue(sound: sound, at: fx.landing))
            case .countersAdded: cues.append(Cue(sound: .counter, at: fx.delay))
            case let .lifeChanged(id, delta):
                if delta > 0 {
                    cues.append(Cue(sound: .lifeGain, at: fx.delay, volume: id == viewerID ? 1 : 0.55))
                } else if id == viewerID, !hasStrike {
                    cues.append(Cue(sound: .lifeLoss, at: fx.delay))
                }
            }
        }
        return cues
    }
}

enum BoardFXHaptics {
    @MainActor
    static func play(_ scheduled: [ScheduledBoardFX], viewerID: String) {
        if let strike = scheduled.filter({ if case .combatStrike = $0.event { return true }; return false }).map(\.handoff).min() {
            DispatchQueue.main.asyncAfter(deadline: .now() + strike) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        if let hit = scheduled.first(where: { if case let .lifeChanged(id, delta) = $0.event { return id == viewerID && delta < 0 }; return false }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + hit.delay) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else if scheduled.contains(where: { if case .leftBattlefield = $0.event { return true }; return false }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if let hero = scheduled.first(where: {
            if case .enteredBattlefield(_, _, _, _, .commander) = $0.event { return true }; return false
        }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + hero.landing) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
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
            GameAudioSettings()
        }
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 9, padding: 10)
    }
}

/// Sound effects and music, each with a level. Changes apply immediately.
struct GameAudioSettings: View {
    @AppStorage(GameAudio.effectsKey, store: MagicMobilePreferences.current) private var effects = true
    @AppStorage(GameAudio.musicKey, store: MagicMobilePreferences.current) private var music = true
    @AppStorage(GameAudio.effectsVolumeKey, store: MagicMobilePreferences.current) private var effectsVolume = 0.9
    @AppStorage(GameAudio.musicVolumeKey, store: MagicMobilePreferences.current) private var musicVolume = GameAudio.defaultMusicVolume
    @State private var soundLabOpen = false

    /// A level of zero reads as off, and switching music back on brings back a level you can hear.
    private var musicOn: Binding<Bool> {
        Binding(get: { music && musicVolume > 0 }, set: { on in
            music = on
            if on && musicVolume <= 0.02 { musicVolume = GameAudio.defaultMusicVolume }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Effect Sounds", isOn: $effects)
                .accessibilityIdentifier("settings.boardSounds")
            if effects {
                Slider(value: $effectsVolume, in: 0...1) { Text("Effects volume") }
                    .accessibilityIdentifier("settings.effectsVolume")
            }
            Toggle("Music", isOn: musicOn)
                .accessibilityIdentifier("settings.music")
            if musicOn.wrappedValue {
                Slider(value: $musicVolume, in: 0...1) { Text("Music volume") }
                    .accessibilityIdentifier("settings.musicVolume")
            }
            HStack(spacing: 8) {
                Text("Sounds follow your iPhone's Silent switch.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 4)
                Button {
                    soundLabOpen = true
                } label: {
                    Label("Sound Lab", systemImage: "waveform")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10).frame(minHeight: 34)
                        .background(Capsule().fill(.white.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.soundLab")
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white.opacity(0.85))
        .tint(GameBoardTheme.current.antiqueGold)
        .onChange(of: effects) { _, on in if on { GameAudio.shared.play(.uiToggle) } }
        .onChange(of: music) { _, _ in GameAudio.shared.settingsChanged() }
        .onChange(of: musicVolume) { _, _ in GameAudio.shared.settingsChanged() }
        .onChange(of: effectsVolume) { _, _ in GameAudio.shared.play(.uiTick) }
        .sheet(isPresented: $soundLabOpen) { SoundLabView() }
    }
}

/// One card face moving across the board for an effect.
struct BoardFXFlight: Identifiable {
    enum Kind {
        case arrive(from: CGPoint, to: CGRect)
        /// Rise to the center, hold long enough to read, then settle into the slot.
        case showcaseArrive(from: CGPoint, center: CGPoint, to: CGRect, commander: Bool)
        case depart(from: CGRect, to: CGPoint, destination: BoardFXZone?)
        case cast(from: CGPoint, to: CGPoint, weight: BoardFXSpellWeight)
        /// Wind up, charge the target, hit, and return to the slot.
        case strike(from: CGRect, to: CGPoint)
    }

    struct Placement {
        var center: CGPoint
        var size: CGSize
        var scale: CGFloat
        var rotation: Double
        var opacity: Double
        /// Full printed card (showcases) rather than the battlefield frame.
        var fullCard = false
        /// 0 on the table, 1 held high above it (deeper shadow).
        var lift: Double = 0
    }

    let effect: ActiveBoardFX
    let card: ZoneCard
    let kind: Kind

    var id: Int { effect.id }

    /// Showcase size: large enough to read the card at the center of the board.
    static func castSize(_ weight: BoardFXSpellWeight) -> CGSize {
        switch weight {
        case .ability: return CGSize(width: 76, height: 106)
        case .spell: return CGSize(width: 150, height: 210)
        case .big, .commander: return CGSize(width: 166, height: 232)
        }
    }

    /// Quadratic arc between two points, lifted toward the top of the screen.
    static func arc(_ a: CGPoint, _ b: CGPoint, lift: CGFloat, t: Double) -> CGPoint {
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - lift)
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    enum Shading: Equatable {
        case none
        case dissolve(progress: Double, edge: Color)
        case foil(phase: Double)
    }

    /// Graveyard (or unknown) and exile departures burn away; bounces fly.
    static func dissolves(_ destination: BoardFXZone?) -> Bool {
        destination == nil || destination == .graveyard || destination == .exile
    }

    func shading(progress p: Double) -> Shading {
        switch kind {
        case let .depart(_, _, destination) where Self.dissolves(destination):
            let edge = destination == .exile ? Color(red: 0.75, green: 0.92, blue: 1) : Color(red: 1, green: 0.52, blue: 0.12)
            return .dissolve(progress: p, edge: edge)
        case .cast, .showcaseArrive:
            return .foil(phase: p * 2.2)
        default:
            return .none
        }
    }

    /// Rise, hold and exit for a showcase whose total run is `duration` seconds.
    private func showcase(from: CGPoint, center: CGPoint, size: CGSize, progress p: Double, duration: TimeInterval,
                          holdEnd: Double) -> Placement? {
        let rise = min(0.3, 0.42 / duration)
        if p < rise {
            let t = BoardFXPainter.easeOut(p / rise)
            return Placement(center: Self.arc(from, center, lift: 50, t: t), size: size, scale: 0.45 + 0.6 * t,
                             rotation: -8 * (1 - t), opacity: min(1, p / rise * 3), fullCard: true, lift: t)
        }
        // Hold still (a slow breath) so the card can be read.
        let hold = (p - rise) / max(0.001, holdEnd - rise)
        let bob = sin(min(hold, 1) * .pi * 2) * 3
        return Placement(center: CGPoint(x: center.x, y: center.y + bob), size: size, scale: 1.05 - 0.05 * min(hold, 1),
                         rotation: 0, opacity: 1, fullCard: true, lift: 1)
    }

    func placement(progress p: Double) -> Placement? {
        let duration = effect.scheduled.duration
        switch kind {
        case let .arrive(from, to):
            let landing = BoardFXScheduler.arrivalFlightFraction
            guard p < landing else { return nil }
            let t = BoardFXPainter.easeOut(p / landing)
            return Placement(center: Self.arc(from, CGPoint(x: to.midX, y: to.midY), lift: 60, t: t),
                             size: to.size, scale: 1.35 - 0.35 * t, rotation: -8 * (1 - t), opacity: min(1, p / landing * 4),
                             lift: 1 - t)
        case let .showcaseArrive(from, center, to, commander):
            let landing = BoardFXScheduler.landingFraction(commander ? .commander : .showcase)
            guard p < landing else { return nil }
            let size = Self.castSize(commander ? .commander : .spell)
            let settle = landing - min(0.2, 0.48 / duration)
            if p < settle {
                return showcase(from: from, center: center, size: size, progress: p, duration: duration, holdEnd: settle)
            }
            // Settle into the slot, shrinking to the tile's width.
            let t = BoardFXPainter.easeIn((p - settle) / (landing - settle))
            let target = CGPoint(x: to.midX, y: to.midY)
            let finalScale = to.width / size.width
            return Placement(center: Self.arc(center, target, lift: 20, t: t), size: size,
                             scale: 1 - (1 - finalScale) * t, rotation: 0, opacity: 1, fullCard: true, lift: 1 - t)
        case let .depart(from, _, destination) where Self.dissolves(destination):
            // Burn away in place with a slight lift; the shader does the rest.
            let t = BoardFXPainter.easeOut(p)
            return Placement(center: CGPoint(x: from.midX, y: from.midY - 10 * t), size: from.size,
                             scale: 1 + 0.06 * t, rotation: 0, opacity: 1, lift: t * 0.3)
        case let .depart(from, to, _):
            let t = p * p
            return Placement(center: Self.arc(CGPoint(x: from.midX, y: from.midY), to, lift: 30, t: t),
                             size: from.size, scale: 1 - 0.6 * t, rotation: 14 * t, opacity: 1 - t, lift: 0.4)
        case let .cast(from, to, weight):
            let size = Self.castSize(weight)
            // Exit: shrink toward the stack and fade over the last third of a second.
            let exit = 1 - min(0.3, 0.35 / duration)
            if p < exit {
                return showcase(from: from, center: to, size: size, progress: p, duration: duration, holdEnd: exit)
            }
            let t = BoardFXPainter.easeIn((p - exit) / (1 - exit))
            return Placement(center: to, size: size, scale: 1 - 0.45 * t, rotation: 0, opacity: 1 - t, fullCard: true, lift: 1 - t)
        case let .strike(from, to):
            let home = CGPoint(x: from.midX, y: from.midY)
            let dx = to.x - home.x, dy = to.y - home.y
            let distance = max(1, hypot(dx, dy))
            let unit = CGPoint(x: dx / distance, y: dy / distance)
            let windup = 0.15, impact = BoardFXScheduler.strikeImpactFraction, recoil = impact + 0.1
            // Stop with the card's leading edge on the target.
            let reach = max(0, distance - from.height * 0.45)
            let hit = CGPoint(x: home.x + unit.x * reach, y: home.y + unit.y * reach)
            let back = CGPoint(x: home.x - unit.x * 14, y: home.y - unit.y * 14)
            let tilt = unit.x >= 0 ? 1.0 : -1.0
            if p < windup {
                let t = BoardFXPainter.easeOut(p / windup)
                return Placement(center: Self.lerp(home, back, t), size: from.size, scale: 1 + 0.1 * t,
                                 rotation: -5 * tilt * t, opacity: 1, lift: t)
            }
            if p < impact {
                let t = BoardFXPainter.easeIn((p - windup) / (impact - windup))
                return Placement(center: Self.lerp(back, hit, t), size: from.size, scale: 1.1 + 0.08 * t,
                                 rotation: -5 * tilt * (1 - t) + 6 * tilt * t, opacity: 1, lift: 1)
            }
            if p < recoil {
                // Brief squash on contact.
                return Placement(center: hit, size: from.size, scale: 1.12, rotation: 6 * tilt, opacity: 1, lift: 0.8)
            }
            let t = BoardFXPainter.easeOut((p - recoil) / (1 - recoil))
            return Placement(center: Self.lerp(hit, home, t), size: from.size, scale: 1.12 - 0.12 * t,
                             rotation: 6 * tilt * (1 - t), opacity: 1, lift: 0.8 * (1 - t))
        }
    }
}

/// Frame clock for effect batches. A snapshot can stall the main thread while the
/// board relays out; each batch starts on its first drawn frame instead of at
/// ingest, so no opening plays off-screen. Reference type on purpose: it is written
/// while rendering and must not invalidate views.
final class BoardFXClock {
    private var firstFrames: [Date: Date] = [:]

    func observe(_ effects: [ActiveBoardFX], at now: Date) {
        for effect in effects where firstFrames[effect.start] == nil {
            firstFrames[effect.start] = now
        }
        if firstFrames.count > 32 {
            let live = Set(effects.map(\.start))
            firstFrames = firstFrames.filter { live.contains($0.key) }
        }
    }

    func origin(for batch: Date) -> Date? { firstFrames[batch] }
}

private struct BoardFXClockKey: EnvironmentKey {
    static let defaultValue = BoardFXClock()
}

private struct BoardFXCardMotionKey: EnvironmentKey {
    static let defaultValue = BoardFXCardMotion()
}

extension EnvironmentValues {
    var boardFXCardMotion: BoardFXCardMotion {
        get { self[BoardFXCardMotionKey.self] }
        set { self[BoardFXCardMotionKey.self] = newValue }
    }

    var boardFXClock: BoardFXClock {
        get { self[BoardFXClockKey.self] }
        set { self[BoardFXClockKey.self] = newValue }
    }
}

/// Applied to real board tiles: hides a card while a flight stands in for it,
/// lunges new attackers, and holds attackers and blockers forward with a glow.
/// Layout and anchors are unaffected.
struct BoardFXCardMotionModifier: ViewModifier {
    let cardID: String
    @Environment(\.boardFXCardMotion) private var motion
    @Environment(\.boardFXClock) private var clock
    /// The window currently hiding the tile (for windows that start later).
    @State private var hiding: BoardFXCardMotion.Hidden?
    /// Windows that have finished; the tile shows again unless another window covers it.
    @State private var revealed = Set<BoardFXCardMotion.Hidden>()

    func body(content: Content) -> some View {
        let windows = motion.hidden[cardID] ?? []
        let hidden = windows.contains { !revealed.contains($0) && ($0.from <= 0 || hiding == $0) }
        let lunge = motion.lunges[cardID]
        let stance = motion.stances[cardID]
        // Direction 0 (no lunge) keeps the offset at zero when the trigger resets.
        let direction = CGFloat(lunge?.direction ?? 0)
        let stanceColor = stance?.kind == .blocking ? BoardFXPainter.blockSteel : BoardFXPainter.attackRed
        let forward: CGFloat = stance?.moves == true ? CGFloat(stance!.direction) * (stance!.kind == .attacking ? 12 : 7) : 0
        content
            .overlay {
                if stance != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(stanceColor, lineWidth: 2)
                        .shadow(color: stanceColor.opacity(0.9), radius: 8)
                        .padding(-2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .scaleEffect(stance?.moves == true ? 1.05 : 1)
            .offset(y: forward)
            .animation(.spring(response: 0.38, dampingFraction: 0.72), value: stance)
            .opacity(hidden ? 0 : 1)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: lunge?.token ?? -1) { view, value in
                view.offset(y: value * direction)
            } keyframes: { _ in
                SpringKeyframe(CGFloat(22), duration: 0.18, spring: .snappy)
                SpringKeyframe(CGFloat.zero, duration: 0.34, spring: .bouncy)
            }
            .task(id: windows) {
                revealed.formIntersection(windows)
                guard !windows.isEmpty else { return }
                // Time the windows on the overlay's frame clock (see BoardFXClock). A double
                // striker has one window per strike, so its tile shows between them.
                var polls = 0
                while windows.contains(where: { clock.origin(for: $0.batch) == nil }) && polls < 60 && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33)); polls += 1
                }
                let timed = windows.map { window -> (window: BoardFXCardMotion.Hidden, origin: Date) in
                    (window, clock.origin(for: window.batch) ?? Date())
                }.sorted { $0.origin.addingTimeInterval($0.window.from) < $1.origin.addingTimeInterval($1.window.from) }
                for (window, origin) in timed where !revealed.contains(window) {
                    if window.from > 0 {
                        let start = origin.addingTimeInterval(window.from).timeIntervalSinceNow
                        if start > 0 { try? await Task.sleep(for: .seconds(start)) }
                        guard !Task.isCancelled else { return }
                        hiding = window
                    }
                    let wait = origin.addingTimeInterval(window.until).timeIntervalSinceNow
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard !Task.isCancelled else { return }
                    revealed.insert(window)
                    if hiding == window { hiding = nil }
                }
            }
    }
}

extension View {
    func boardFXCardMotion(_ cardID: String) -> some View {
        modifier(BoardFXCardMotionModifier(cardID: cardID))
    }
}

/// Applies the Metal card shaders from BoardFXShaders.metal.
struct BoardFXShading: ViewModifier {
    let shading: BoardFXFlight.Shading
    let size: CGSize

    func body(content: Content) -> some View {
        switch shading {
        case .none:
            content
        case let .dissolve(progress, edge):
            content.colorEffect(ShaderLibrary.mmDissolve(.float2(size), .float(progress), .color(edge)))
        case let .foil(phase):
            content.colorEffect(ShaderLibrary.mmFoil(.float2(size), .float(phase), .float(1)))
        }
    }
}

/// Turn-start ribbon: a gold-edged band sweeps across the board with the owner's name.
struct BoardTurnBanner: View {
    let title: String
    let turn: Int
    let isViewer: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var sweep: CGFloat = -1

    var body: some View {
        let accent = isViewer ? BoardFXPainter.gold : Color(red: 0.62, green: 0.74, blue: 1)
        ZStack {
            LinearGradient(colors: [.clear, Color.black.opacity(0.86), Color.black.opacity(0.86), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 104)
                .overlay(alignment: .top) { edge(accent) }
                .overlay(alignment: .bottom) { edge(accent) }
                .scaleEffect(x: shown ? 1 : 0.05, y: 1)
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 40, weight: .black, design: .serif))
                    .tracking(3)
                    .foregroundStyle(LinearGradient(colors: [.white, accent, accent.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // Light sweep across the title.
                        LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 70)
                            .offset(x: sweep * 220)
                            .blendMode(.plusLighter)
                            .mask {
                                Text(title.uppercased())
                                    .font(.system(size: 40, weight: .black, design: .serif))
                                    .tracking(3)
                            }
                    }
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("Turn \(turn)")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(accent.opacity(0.85))
            }
            .shadow(color: accent.opacity(0.6), radius: 14)
            .offset(y: shown ? 0 : 14)
            .opacity(shown ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), turn \(turn)")
        .onAppear {
            if reduceMotion { shown = true; return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { shown = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.25)) { sweep = 1 }
        }
    }

    private func edge(_ color: Color) -> some View {
        LinearGradient(colors: [.clear, color, color, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 2)
            .shadow(color: color, radius: 6)
    }
}

/// Animated backdrop for the game-over panel, edge to edge with no banding: one continuous
/// tint sized to the screen diagonal (so the status bar, top bar, board and dock share it),
/// turning rays and rising motes for a win, falling ash for a loss.
struct GameResultBackdrop: View {
    let victory: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                wash(size)
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                        let t = timeline.date.timeIntervalSince(start)
                        Canvas { context, size in draw(in: &context, size: size, t: t) }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func wash(_ size: CGSize) -> some View {
        let reach = max(1, hypot(size.width, size.height) * 0.6)
        let center = UnitPoint(x: 0.5, y: 0.42)
        return RadialGradient(colors: victory
                ? [Color(red: 0.62, green: 0.46, blue: 0.12).opacity(0.62), Color(red: 0.40, green: 0.28, blue: 0.07).opacity(0.46)]
                : [Color(red: 0.42, green: 0.05, blue: 0.04).opacity(0.62), Color(red: 0.20, green: 0.02, blue: 0.02).opacity(0.5)],
                center: center, startRadius: 0, endRadius: reach)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let intro = min(1, t / 0.8)
        let reach = hypot(size.width, size.height)
        if victory {
            BoardFXPainter.rays(at: center, color: BoardFXPainter.gold, radius: reach * 0.7,
                                progress: 0.4, elapsed: t * 0.6, in: &context)
            // Motes rise across the whole screen, not a band.
            for i in 0..<70 {
                let speed = 0.05 + 0.08 * BoardFXPainter.noise(9, i, 1)
                let life = (t * speed + BoardFXPainter.noise(9, i, 2)).truncatingRemainder(dividingBy: 1)
                let x = size.width * BoardFXPainter.noise(9, i, 3) + sin(t * 0.8 + Double(i)) * 14
                let y = size.height * (1.02 - 1.08 * life)
                let r = 1.2 + 2.4 * BoardFXPainter.noise(9, i, 4)
                var mote = context
                mote.blendMode = .plusLighter
                mote.opacity = intro * sin(.pi * life) * (0.55 + 0.45 * sin(t * 3 + Double(i)))
                mote.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                          with: .color(i % 3 == 0 ? .white : BoardFXPainter.gold))
            }
        } else {
            for i in 0..<60 {
                let life = (t * (0.06 + 0.08 * BoardFXPainter.noise(3, i, 1)) + BoardFXPainter.noise(3, i, 2))
                    .truncatingRemainder(dividingBy: 1)
                let x = size.width * BoardFXPainter.noise(3, i, 3) + sin(t + Double(i)) * 12
                let y = size.height * (1.08 * life - 0.04)
                var ash = context
                ash.opacity = 0.5 * sin(.pi * life) * intro
                ash.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)),
                         with: .color(Color(red: 0.75, green: 0.7, blue: 0.68)))
            }
        }
    }
}
