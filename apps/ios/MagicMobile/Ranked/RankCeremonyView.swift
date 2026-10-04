import SwiftUI

/// The result screen's rank strip: the badge, then each pip filling or emptying in turn, with the
/// bonuses that earned extra pips.
struct RankProgressPanel: View {
    let change: RankChange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownPoints: Int?

    private var shown: RankPosition { RankPosition(points: shownPoints ?? change.before.points) }

    var body: some View {
        HStack(spacing: 14) {
            RankBadge(position: shown, size: 64, showsPips: false)
                .id(shown.tier.rawValue * 10 + shown.division)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            VStack(alignment: .leading, spacing: 6) {
                Text(shown.title)
                    .font(.system(size: 18, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), shown.tier.tint], startPoint: .top, endPoint: .bottom))
                if shown.tier == .mythic {
                    Label("\(shown.pips)", systemImage: "flame.fill")
                        .font(.system(size: 14, weight: .heavy, design: .serif)).foregroundStyle(shown.tier.tint)
                } else {
                    RankPips(filled: shown.pips, tier: shown.tier, size: 13,
                             highlight: shownPoints == nil ? nil : (change.pipDelta >= 0 ? shown.pips - 1 : shown.pips))
                }
                Text(deltaText)
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .foregroundStyle(change.pipDelta > 0 ? Color(red: 0.6, green: 0.95, blue: 0.55)
                                     : change.pipDelta < 0 ? Color(red: 1, green: 0.55, blue: 0.45) : TavernPalette.parchment.opacity(0.7))
                if !change.bonuses.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(change.bonuses, id: \.self) { bonus in
                            TavernTag(text: bonus == .streak ? String(localized: "Win streak +1") : String(localized: "Underdog +1"),
                                      leather: true, accent: TavernPalette.ember)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background { TavernFill(material: .leather).overlay(Color.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 10)) }
        .overlay { TavernBrassFrame(scale: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Ranked: \(change.after.title). \(deltaText)"))
        .accessibilityIdentifier("rank.progress")
        .task { await play() }
    }

    private var deltaText: String {
        switch change.pipDelta {
        case let n where n > 0: return n == 1 ? String(localized: "+1 pip") : String(localized: "+\(n) pips")
        case let n where n < 0: return n == -1 ? String(localized: "−1 pip") : String(localized: "\(n) pips")
        default: return change.outcome == .loss ? String(localized: "No pips to lose") : String(localized: "No change")
        }
    }

    /// One pip at a time, so a crossing into the next division is seen.
    private func play() async {
        let from = change.before.points, to = change.after.points
        guard from != to else { return }
        if reduceMotion { shownPoints = to; return }
        try? await Task.sleep(for: .milliseconds(700))
        let step = to > from ? 1 : -1
        var value = from
        while value != to {
            value += step
            withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) { shownPoints = value }
            GameAudio.shared.play(step > 0 ? .counter : .lifeLoss, volume: 0.7)
            try? await Task.sleep(for: .milliseconds(420))
        }
    }
}

/// A full-screen moment for moving up or down a division or tier. Up: the old badge charges,
/// bursts into embers and the new one slams down under turning light. Down: the badge cracks,
/// falls away and the lower one settles, dimmed.
struct RankCeremonyOverlay: View {
    let change: RankChange
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var burstAt: Date?
    @State private var finished = false
    @State private var spinStart = Date()

    private var promoted: Bool { change.after > change.before }
    private var tierChange: Bool { change.after.tier != change.before.tier }

    var body: some View {
        ZStack {
            Color.black.opacity(stage > 0 ? 0.9 : 0).ignoresSafeArea()
            if promoted && stage >= 2 { RankLightRays(tint: change.after.tier.tint).transition(.opacity) }
            if let burstAt { RankEmberBurst(start: burstAt, tint: promoted ? change.after.tier.tint : Color(white: 0.55), upward: promoted) }
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                ZStack {
                    if stage < 2 { oldBadge }
                    if stage >= 2 { newBadge }
                }
                .frame(height: 220)
                titleBlock.opacity(stage >= 3 ? 1 : 0)
                Spacer(minLength: 0)
                Group {
                    if finished {
                        Button { close() } label: { Text(String(localized: "Continue")).frame(minWidth: 180) }
                            .buttonStyle(TavernButtonStyle(kind: .primary, fontSize: 18))
                            .accessibilityIdentifier("rank.ceremony.continue")
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        // Only Continue closes it, so a stray tap never skips the moment.
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel(promoted ? String(localized: "Ranked up to \(change.after.title)") : String(localized: "Ranked down to \(change.after.title)"))
        .accessibilityIdentifier("rank.ceremony")
        .task { await run() }
    }

    private var oldBadge: some View {
        RankBadge(position: change.before, size: 170, showsPips: false, spin: stage == 1 && promoted ? .init(start: spinStart, turns: 1, duration: 0.9) : nil)
            .scaleEffect(stage == 1 ? (promoted ? 1.1 : 0.96) : 1)
            .modifier(RankShake(amount: stage == 1 ? (promoted ? 3 : 7) : 0))
            .overlay { if !promoted && stage >= 1 { RankCracks(progress: stage >= 1 ? 1 : 0).frame(width: 150, height: 150) } }
            .saturation(!promoted && stage >= 1 ? 0.3 : 1)
            .brightness(promoted && stage == 1 ? 0.15 : 0)
            .shadow(color: (promoted ? change.before.tier.tint : .black).opacity(stage == 1 ? 0.9 : 0.4), radius: stage == 1 ? 30 : 8)
            .transition(promoted ? .scale(scale: 1.8).combined(with: .opacity)
                                 : .offset(y: 260).combined(with: .opacity))
    }

    private var newBadge: some View {
        RankBadge(position: change.after, size: 190, showsPips: false,
                  spin: .init(start: burstAt ?? Date(), turns: promoted ? 3 : 1, duration: promoted ? 1.6 : 1.1, reverse: !promoted))
            .shadow(color: promoted ? change.after.tier.tint.opacity(0.85) : .black.opacity(0.5), radius: promoted ? 34 : 10)
            .saturation(promoted ? 1 : 0.75)
            .transition(promoted ? .scale(scale: 2.2).combined(with: .opacity)
                                 : .offset(y: -120).combined(with: .opacity))
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(promoted ? (tierChange ? String(localized: "NEW RANK") : String(localized: "RANKED UP"))
                          : String(localized: "RANKED DOWN"))
                .font(.system(size: 15, weight: .black, design: .serif)).tracking(4)
                .foregroundStyle(promoted ? TavernPalette.brass : Color(red: 0.85, green: 0.4, blue: 0.35))
            Text(change.after.title)
                .font(.system(size: 40, weight: .black, design: .serif))
                .foregroundStyle(LinearGradient(colors: [.white, change.after.tier.tint], startPoint: .top, endPoint: .bottom))
                .shadow(color: (promoted ? change.after.tier.tint : .black).opacity(0.7), radius: 12)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(promoted ? String(localized: "Your opponents grow stronger.") : String(localized: "Win your next games to climb back."))
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(TavernPalette.parchment.opacity(0.8))
        }
        .multilineTextAlignment(.center)
    }

    private func run() async {
        if reduceMotion {
            stage = 3; finished = true
            GameAudio.shared.play(promoted ? .victory : .defeat, volume: 0.6)
            return
        }
        spinStart = Date()
        withAnimation(.easeOut(duration: 0.3)) { stage = 1 }
        GameAudio.shared.play(promoted ? .ability : .lifeLoss)
        try? await Task.sleep(for: .milliseconds(promoted ? 900 : 1100))
        burstAt = Date()
        GameAudio.shared.play(promoted ? .commanderCast : .death)
        withAnimation(promoted ? .spring(response: 0.5, dampingFraction: 0.55) : .easeIn(duration: 0.6)) { stage = 2 }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeOut(duration: 0.45)) { stage = 3 }
        if promoted { GameAudio.shared.play(.victory, volume: 0.55) }
        try? await Task.sleep(for: .milliseconds(700))
        finished = true
    }

    private func close() {
        GameAudio.shared.play(.uiConfirm)
        done()
    }
}

/// Slow turning shafts of light behind a new badge.
private struct RankLightRays: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 24) / 24 * 360
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let radius = max(size.width, size.height)
                for index in 0..<12 {
                    let start = Angle.degrees(angle + Double(index) * 30)
                    var wedge = Path()
                    wedge.move(to: center)
                    wedge.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .degrees(9), clockwise: false)
                    wedge.closeSubpath()
                    canvas.fill(wedge, with: .radialGradient(Gradient(colors: [tint.opacity(0.35), .clear]),
                                                             center: center, startRadius: 0, endRadius: radius * 0.6))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Embers thrown out from the badge: up and out for a promotion, falling ash for a demotion.
private struct RankEmberBurst: View {
    let start: Date
    let tint: Color
    let upward: Bool
    private static let count = 46

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                guard t < 2.6 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
                for index in 0..<Self.count {
                    // A fixed spread per ember, so the burst looks the same each frame.
                    let seed = Double(index) * 12.9898
                    let angle = (seed.truncatingRemainder(dividingBy: 6.283))
                    let speed = 120 + (seed * 7).truncatingRemainder(dividingBy: 220)
                    let gravity = upward ? -40.0 : 260.0
                    let x = center.x + cos(angle) * speed * t
                    let y = center.y + sin(angle) * speed * t * (upward ? 1 : 0.4) + 0.5 * gravity * t * t
                    let life = max(0, 1 - t / 2.4)
                    let radius = (2 + (seed * 3).truncatingRemainder(dividingBy: 4)) * life
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    canvas.fill(Path(ellipseIn: rect), with: .color(tint.opacity(life)))
                    canvas.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)), with: .color(tint.opacity(life * 0.25)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Cracks spreading across a badge that is about to fall.
private struct RankCracks: View {
    var progress: CGFloat

    var body: some View {
        Canvas { canvas, size in
            let w = size.width, h = size.height
            let lines: [[CGPoint]] = [
                [.init(x: 0.5, y: 0.45), .init(x: 0.38, y: 0.3), .init(x: 0.33, y: 0.12)],
                [.init(x: 0.5, y: 0.45), .init(x: 0.66, y: 0.36), .init(x: 0.82, y: 0.38)],
                [.init(x: 0.5, y: 0.45), .init(x: 0.55, y: 0.62), .init(x: 0.47, y: 0.86)],
                [.init(x: 0.55, y: 0.62), .init(x: 0.72, y: 0.7)],
                [.init(x: 0.38, y: 0.3), .init(x: 0.2, y: 0.4)],
            ]
            for line in lines {
                var path = Path()
                path.addLines(line.map { CGPoint(x: $0.x * w, y: $0.y * h) })
                canvas.stroke(path.trimmedPath(from: 0, to: progress), with: .color(.black.opacity(0.85)), lineWidth: 3)
                canvas.stroke(path.trimmedPath(from: 0, to: progress), with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.6), value: progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A quick tremble while a badge charges or cracks.
private struct RankShake: ViewModifier {
    var amount: CGFloat

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: amount == 0)) { context in
            content.offset(x: amount == 0 ? 0 : amount * sin(context.date.timeIntervalSinceReferenceDate * 60))
        }
    }
}
