import SwiftUI
import UIKit

/// The online turn timer's burning rope, laid across the middle of the table for the last
/// `TurnClockRules.rope` seconds of a decision (Hearthstone's rope). Android: `TurnRope.kt`.
/// It only reads `OnDeviceMultiplayer.turnClock`; the host's `TurnClock` decides what a timeout does.
struct TurnRopeOverlay: View {
    @ObservedObject var multiplayer: OnDeviceMultiplayer
    @State private var burning = false

    var body: some View {
        let board = multiplayer.turnClock
        let local = multiplayer.endpoint?.seatID
        ZStack {
            if burning {
                // Redrawn at 20 Hz only while a rope burns; nothing ticks before that.
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    if let rope = board.rope(localSeat: local, now: ProcessInfo.processInfo.systemUptime) {
                        TurnRope(rope: rope, name: multiplayer.seatNames[rope.seat], time: context.date.timeIntervalSinceReferenceDate)
                            .transition(.opacity)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: RopeWatch(board: board, local: local)) { await watch(board, local: local) }
    }

    private struct RopeWatch: Equatable { let board: TurnClockBoard; let local: String? }

    /// Sleeps until the rope should light, then until it burns out.
    private func watch(_ board: TurnClockBoard, local: String?) async {
        while !Task.isCancelled {
            let now = ProcessInfo.processInfo.systemUptime
            guard let wait = board.secondsUntilRope(localSeat: local, now: now) else { burning = false; return }
            if wait > 0 {
                burning = false
                try? await Task.sleep(for: .seconds(wait))
            } else {
                if !burning, board.rope(localSeat: local, now: now)?.isLocal == true { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                burning = true
                try? await Task.sleep(for: .seconds((board.rope(localSeat: local, now: now)?.remaining ?? 0) + 0.25))
            }
        }
    }
}

/// A twisted hemp rope in brass trim, burning from the left toward the pass disc's side,
/// with an ember at the burning end and a tag naming whose time it is.
struct TurnRope: View {
    let rope: TurnClockBoard.Rope
    let name: String?
    let time: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        var text = rope.isLocal ? String(localized: "Your time") : String(localized: "\(name ?? String(localized: "Opponent"))’s time")
        if rope.strikes > 0 { text += " · " + String(localized: "timeout \(rope.strikes) of \(TurnClockRules.online.strikesToForfeit)") }
        return text.uppercased()
    }

    var body: some View {
        VStack(spacing: 6) {
            TavernTag(text: label, leather: true, accent: rope.remaining <= 5 ? TavernPalette.ember : TavernPalette.brass)
            GeometryReader { proxy in
                let width = proxy.size.width
                let burnX = width * (1 - rope.fraction)
                let flicker = reduceMotion ? 1 : 1 + 0.18 * sin(time * 23) * cos(time * 7)
                ZStack(alignment: .leading) {
                    // The burnt-out stretch: a scorched line.
                    Capsule().fill(Color.black.opacity(0.45))
                        .frame(width: max(0, burnX), height: 3)
                    // What is left of the rope.
                    RopeStrand()
                        .frame(width: max(0, width - burnX), height: 9)
                        .offset(x: burnX)
                    // The ember at the burning end.
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.95), TavernPalette.ember, TavernPalette.enamel.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 11))
                        .frame(width: 22, height: 22)
                        .scaleEffect(flicker)
                        .shadow(color: TavernPalette.ember.opacity(0.9), radius: 8)
                        .offset(x: burnX - 11)
                }
                .frame(height: 22)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(localized: "\(Int(rope.remaining.rounded(.up))) seconds left"))
    }
}

/// A rope drawn as a brass-and-hemp capsule with diagonal twists.
private struct RopeStrand: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let capsule = Path(roundedRect: rect, cornerRadius: size.height / 2)
            context.fill(capsule, with: .linearGradient(
                Gradient(colors: [TavernPalette.parchment, TavernPalette.brass, TavernPalette.brassDark]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            context.clip(to: capsule)
            var twists = Path()
            let step: CGFloat = 7
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                twists.move(to: CGPoint(x: x, y: size.height))
                twists.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(twists, with: .color(TavernPalette.brassDark.opacity(0.55)), lineWidth: 1.6)
            context.stroke(capsule, with: .color(Color.black.opacity(0.5)), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}
