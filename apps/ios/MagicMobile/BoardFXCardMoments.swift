import SwiftUI

/// Card moments (docs/BOARD_FX_ROADMAP.md, phase 16): counters by kind, power and toughness changes, phasing, exile,
/// transforms, control changes and tokens. The 3D pieces are Blender-rendered sprite strips
/// (scripts/brand/fx_sprites.py, image sets tavern-fx-*), each FRAMES square frames of a spin. Everything here draws
/// only while its effect plays; a still board draws nothing. Android's BoardFXCardMoments.kt matches it.
extension BoardFXPainter {
    static let spriteFrames = 12
    static let exileCyan = Color(red: 0.72, green: 0.9, blue: 1)
    static let phaseViolet = Color(red: 0.66, green: 0.62, blue: 1)
    static let brassChain = Color(red: 0.86, green: 0.66, blue: 0.32)

    /// One frame of a sprite strip, drawn into `rect`.
    static func sprite(_ name: String, frame: Int, in rect: CGRect, opacity: Double = 1, in context: inout GraphicsContext) {
        guard opacity > 0.01, rect.width > 1 else { return }
        var layer = context
        layer.opacity = opacity
        layer.clip(to: Path(rect))
        let frames = spriteFrames
        let index = ((frame % frames) + frames) % frames
        let image = layer.resolve(Image(name))
        layer.draw(image, in: CGRect(x: rect.minX - rect.width * CGFloat(index), y: rect.minY,
                                     width: rect.width * CGFloat(frames), height: rect.height))
    }

    static func spriteName(_ kind: BoardFXCounterKind) -> String {
        switch kind {
        case .plusOne: return "tavern-fx-counter-plus"
        case .minusOne: return "tavern-fx-counter-minus"
        case .loyalty: return "tavern-fx-counter-loyalty"
        case .other: return "tavern-fx-counter-coin"
        }
    }

    static func counterColor(_ kind: BoardFXCounterKind) -> Color {
        switch kind {
        case .plusOne: return Color(red: 0.45, green: 1, blue: 0.55)
        case .minusOne: return Color(red: 0.78, green: 0.5, blue: 1)
        case .loyalty: return Color(red: 0.5, green: 0.75, blue: 1)
        case .other: return gold
        }
    }

    /// A bounce that settles: 0 → overshoot → 1.
    static func bounce(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        if x < 0.6 { return easeIn(x / 0.6) }
        let k = (x - 0.6) / 0.4
        return 1 - 0.18 * sin(k * .pi) * (1 - k)
    }

    /// Counters arriving or leaving: the piece drops onto the card's corner with a spin and a bounce (or lifts away),
    /// its count rises from it, and a -1/-1 drop splashes a violet ripple over the card.
    static func counterMoment(_ kind: BoardFXCounterKind, delta: Int, on rect: CGRect, progress p: Double, motion: Bool,
                              seed: Int, in context: inout GraphicsContext) {
        let color = counterColor(kind)
        let side = min(rect.width * 0.5, 46)
        let rest = CGPoint(x: rect.maxX - side * 0.42, y: rect.minY + side * 0.5)
        let name = spriteName(kind)
        let label = kind.label(delta: delta)
        if !motion {
            let fade = window(p, fadeIn: 0.15, fadeOut: 0.7)
            sprite(name, frame: 0, in: CGRect(x: rest.x - side / 2, y: rest.y - side / 2, width: side, height: side), opacity: fade, in: &context)
            number(label, at: CGPoint(x: rest.x, y: rest.y + side * 0.55), color: color, size: 18, progress: p, motion: false, in: &context)
            return
        }
        let impact = 0.42
        if delta > 0 {
            let fall = bounce(p / impact)
            let y = rest.y - (1 - fall) * (rect.height * 0.9 + 30)
            // Two quick turns while it falls, slowing to its face as it lands.
            let turn = p < impact ? Int(easeOut(p / impact) * Double(spriteFrames * 2)) : 0
            let fade = p > 0.82 ? (1 - p) / 0.18 : 1
            let scale = p < impact ? 0.7 + 0.3 * fall : 1 + 0.12 * max(0, 1 - (p - impact) / 0.12)
            let s = side * scale
            sprite(name, frame: turn, in: CGRect(x: rest.x - s / 2, y: y - s / 2, width: s, height: s), opacity: fade, in: &context)
            if p >= impact {
                let q = (p - impact) / (1 - impact)
                shockwave(at: rest, color: color, maxRadius: side * 1.1, progress: min(1, q * 1.6), in: &context)
                sparks(from: CGRect(x: rest.x - side / 2, y: rest.y - side / 2, width: side, height: side), color: color, count: 12,
                       progress: q, seed: seed, style: .burst, in: &context)
                if kind == .minusOne {
                    // Ichor: the card dims violet for a beat under the ripple.
                    flash(rect, color: color.opacity(0.7), progress: q, in: &context)
                    shockwave(at: CGPoint(x: rect.midX, y: rect.midY), color: color.opacity(0.7), maxRadius: rect.width * 0.8,
                              progress: q, in: &context)
                }
                number(label, at: CGPoint(x: rest.x, y: rest.y + side * 0.6), color: color, size: 22, progress: q, motion: true, in: &context)
            }
        } else {
            // Removed: the piece lifts off the card, turning, and fades as its count drops away.
            let q = easeOut(p)
            let y = rest.y - q * 46
            let s = side * (1 - 0.35 * q)
            sprite(name, frame: Int(q * Double(spriteFrames)), in: CGRect(x: rest.x - s / 2, y: y - s / 2, width: s, height: s),
                   opacity: 1 - p, in: &context)
            number(label, at: CGPoint(x: rest.x, y: rest.y + side * 0.6), color: color.opacity(0.85), size: 20, progress: p,
                   motion: true, in: &context)
        }
    }

    /// Power and toughness changed beyond the counters: the change floats up over the card and its stat corner pulses.
    static func statsMoment(power: Int, toughness: Int, on rect: CGRect, progress p: Double, motion: Bool,
                            in context: inout GraphicsContext) {
        func signed(_ value: Int) -> String { value >= 0 ? "+\(value)" : "\(value)" }
        let total = power + toughness
        let color = total > 0 ? Color(red: 0.45, green: 1, blue: 0.55) : total < 0 ? Color(red: 0.78, green: 0.5, blue: 1) : gold
        let corner = CGPoint(x: rect.maxX - 12, y: rect.maxY - 12)
        shockwave(at: corner, color: color, maxRadius: motion ? 34 : 20, progress: min(1, p * 1.5), in: &context)
        if motion { arrivalGlow(rect, color: color.opacity(0.6), progress: min(1, p * 1.3), motion: false, in: &context) }
        number("\(signed(power))/\(signed(toughness))", at: CGPoint(x: rect.midX, y: rect.midY), color: color, size: 22,
               progress: p, motion: motion, in: &context)
    }

    /// Phasing: bands of violet light sweep the card as it thins out of the world (or back in). The tile itself shows
    /// the phased-out state for as long as it lasts (ArenaBattlefieldCard dims it); this is only the moment.
    static func phaseMoment(out: Bool, on rect: CGRect, progress p: Double, motion: Bool, seed: Int,
                            in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        layer.clip(to: Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 10))
        let fade = window(p, fadeIn: 0.12, fadeOut: 0.7)
        let bands = motion ? 4 : 2
        for i in 0..<bands {
            // Bands sweep down when leaving, up when returning.
            let phase = (p * 1.6 + Double(i) / Double(bands)).truncatingRemainder(dividingBy: 1)
            let y = out ? rect.minY + rect.height * phase : rect.maxY - rect.height * phase
            let band = CGRect(x: rect.minX - 4, y: y - 6, width: rect.width + 8, height: 12)
            layer.opacity = 0.55 * fade
            layer.fill(Path(band), with: .linearGradient(Gradient(colors: [.clear, phaseViolet, .clear]),
                                                         startPoint: CGPoint(x: band.midX, y: band.minY),
                                                         endPoint: CGPoint(x: band.midX, y: band.maxY)))
        }
        if motion {
            shockwave(at: CGPoint(x: rect.midX, y: rect.midY), color: phaseViolet.opacity(0.8), maxRadius: rect.width * 0.9,
                      progress: out ? p : 1 - p, in: &context)
            sparks(from: rect, color: phaseViolet, count: 14, progress: p, seed: seed, style: out ? .rise : .fall, in: &context)
        }
    }

    /// Exile: a pillar of pale light over the card and the sigil ring turning under it while the card burns away cold.
    static func exileMoment(on rect: CGRect, progress p: Double, motion: Bool, elapsed: Double, seed: Int,
                            in context: inout GraphicsContext) {
        let fade = window(p, fadeIn: 0.1, fadeOut: 0.65)
        var light = context
        light.blendMode = .plusLighter
        light.addFilter(.blur(radius: 6))
        let height = rect.height * (motion ? 2.6 : 1.4) * easeOut(min(1, p / 0.35))
        let pillar = CGRect(x: rect.midX - rect.width * 0.38, y: rect.maxY - height, width: rect.width * 0.76, height: height)
        light.opacity = 0.75 * fade
        light.fill(Path(roundedRect: pillar, cornerRadius: pillar.width / 2),
                   with: .linearGradient(Gradient(colors: [exileCyan.opacity(0), exileCyan, .white]),
                                         startPoint: CGPoint(x: pillar.midX, y: pillar.minY),
                                         endPoint: CGPoint(x: pillar.midX, y: pillar.maxY)))
        guard motion else { return }
        let ringWidth = rect.width * 1.7
        let ring = CGRect(x: rect.midX - ringWidth / 2, y: rect.maxY - ringWidth * 0.62, width: ringWidth, height: ringWidth)
        var glow = context
        glow.blendMode = .plusLighter
        sprite("tavern-fx-exile-ring", frame: Int(elapsed * 16), in: ring, opacity: fade, in: &glow)
        sparks(from: rect, color: exileCyan, count: 18, progress: p, seed: seed &+ 31, style: .rise, in: &context)
    }

    /// Control change: a brass chain reaches from the old controller to the card, then snaps as the card settles in its
    /// new rows.
    static func chainMoment(from origin: CGPoint, to rect: CGRect, progress p: Double, motion: Bool, seed: Int,
                            in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        let target = CGPoint(x: rect.midX, y: rect.midY)
        let reach = easeOut(min(1, p / 0.45))
        let end = CGPoint(x: origin.x + (target.x - origin.x) * reach, y: origin.y + (target.y - origin.y) * reach)
        let snap = p > 0.55
        layer.opacity = snap ? max(0, 1 - (p - 0.55) / 0.3) : 1
        var chain = Path()
        chain.move(to: origin)
        chain.addLine(to: end)
        layer.stroke(chain, with: .color(brassChain.opacity(0.35)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        // Links: alternate long ovals, drawn as a dashed double stroke.
        layer.stroke(chain, with: .color(brassChain), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [9, 5]))
        layer.stroke(chain, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [9, 5]))
        if p > 0.45 {
            let q = (p - 0.45) / 0.55
            arrivalGlow(rect, color: brassChain, progress: q, motion: motion, in: &context)
            if motion { sparks(from: rect, color: gold, count: 14, progress: q, seed: seed, style: .burst, in: &context) }
        }
    }

    /// A token forming: motes of its colour gather into the card from around it.
    static func gather(into rect: CGRect, color: Color, count: Int, progress p: Double, seed: Int, in context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        let q = easeOut(min(1, p / 0.7))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<count {
            let angle = noise(seed, i, 11) * 2 * .pi
            let distance = (rect.width * 0.9 + 40 * noise(seed, i, 12)) * (1 - q)
            let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance * 1.2)
            let r = 1.5 + 2.5 * noise(seed, i, 13)
            layer.opacity = window(p, fadeIn: 0.1, fadeOut: 0.75)
            layer.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }

    /// A new face: a ring of light around the card while the tile itself turns over (BoardFXCardMotion.flips).
    static func transformMoment(on rect: CGRect, color: Color, progress p: Double, motion: Bool, seed: Int, in context: inout GraphicsContext) {
        arrivalGlow(rect, color: color, progress: p, motion: motion, in: &context)
        if motion {
            shockwave(at: CGPoint(x: rect.midX, y: rect.midY), color: color, maxRadius: rect.width, progress: p, in: &context)
            sparks(from: rect, color: color, count: 12, progress: p, seed: seed, style: .burst, in: &context)
        }
    }
}
