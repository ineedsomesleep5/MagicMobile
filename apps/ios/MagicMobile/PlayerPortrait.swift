import SwiftUI
import UIKit

/// A player's face at the table: their commander's art in a ring that turns gold on their
/// turn, spins while an AI decides, and greys out with a skull once they are out.
struct PlayerPortrait: View {
    let player: PlayerGameState
    var size: CGFloat = 44
    var active = false
    var thinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var commanderName: String? {
        player.commanders?.compactMap(\.name).first { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [MagicPalette.iron, MagicPalette.leather], startPoint: .top, endPoint: .bottom))
            if let name = commanderName {
                NativeCardArtworkView(name: name, variant: .board, contentMode: .fill, artOnly: true) { _, _ in initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .saturation(player.isOut ? 0 : 1)
        .opacity(player.isOut ? 0.5 : 1)
        .overlay(Circle().stroke(ring, lineWidth: active ? 2.5 : 1.3))
        .shadow(color: active ? MagicPalette.antiqueGold.opacity(0.55) : .clear, radius: 6)
        .overlay {
            if thinking && !player.isOut {
                ThinkingRing(color: BoardTurnColors.opponent, still: reduceMotion)
                    .padding(-3.5)
            }
        }
        .overlay(alignment: .bottom) {
            if player.isOut {
                Image(systemName: "skull.fill")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(MagicPalette.oxblood))
                    .offset(y: size * 0.14)
            }
        }
        .accessibilityHidden(true)
    }

    private var ring: Color {
        if player.isOut { return .gray.opacity(0.6) }
        return active ? MagicPalette.antiqueGold : MagicPalette.borderBronze.opacity(0.8)
    }

    private var initials: some View {
        Text(String((player.displayName ?? "?").prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .black, design: .rounded))
            .foregroundStyle(MagicPalette.parchment)
    }
}

/// A short arc orbiting a portrait while that player decides. Core Animation turns it in the render server: the
/// SwiftUI repeating animation it replaced redrew the whole board every frame for as long as an AI thought
/// (Instruments on Caleb's iPhone, 2026-10-18). While the phone is hot it turns at up to 30 frames a second.
private struct ThinkingRing: View {
    let color: Color
    let still: Bool
    @ObservedObject private var heat = DeviceHeat.shared

    var body: some View {
        if still {
            Circle().stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        } else {
            OrbitingArc(color: UIColor(color), hot: heat.isHot)
        }
    }
}

/// A 0.3 turn of a circle, 2.5 pt wide with round caps, turning clockwise once every 1.1 s.
private struct OrbitingArc: UIViewRepresentable {
    let color: UIColor
    let hot: Bool

    func makeUIView(context: Context) -> OrbitingArcView { OrbitingArcView() }

    func updateUIView(_ view: OrbitingArcView, context: Context) {
        view.configure(color: color, hot: hot)
    }
}

final class OrbitingArcView: UIView {
    private static let key = "orbit"
    private let arc = CAShapeLayer()
    private var hot = false
    private var foreground: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        arc.fillColor = nil
        arc.lineWidth = 2.5
        arc.lineCap = .round
        layer.addSublayer(arc)
        // The render server drops layer animations while the app is in the background.
        foreground = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spin(restart: true) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
    }

    func configure(color: UIColor, hot: Bool) {
        arc.strokeColor = color.cgColor
        let changed = hot != self.hot
        self.hot = hot
        spin(restart: changed)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.frame = bounds
        // SwiftUI's Circle().trim(from: 0, to: 0.3).stroke(...): centred on the frame's edge, from three o'clock.
        let radius = min(bounds.width, bounds.height) / 2
        arc.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                                startAngle: 0, endAngle: 0.3 * 2 * .pi, clockwise: true).cgPath
        CATransaction.commit()
        spin(restart: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        spin(restart: false)
    }

    private func spin(restart: Bool) {
        guard window != nil else { return }
        if restart { arc.removeAnimation(forKey: Self.key) }
        guard arc.animation(forKey: Self.key) == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = 1.1
        turn.repeatCount = .infinity
        turn.timingFunction = CAMediaTimingFunction(name: .linear)
        turn.isRemovedOnCompletion = false
        if hot { turn.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30) }
        arc.add(turn, forKey: Self.key)
    }
}

/// "Aurelia is thinking" with three pulsing dots.
struct ThinkingLabel: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            Text("\(name) is thinking")
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    Circle().frame(width: 3.5, height: 3.5)
                        .opacity(reduceMotion ? 0.8 : (phase == index ? 1 : 0.3))
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                phase = (phase + 1) % 3
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name) is thinking"))
    }
}
