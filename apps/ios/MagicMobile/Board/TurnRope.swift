import SwiftUI
import UIKit

/// What the online turn timer shows, fed by `OnDeviceMultiplayer` (the host's `TurnClock` decides
/// what a timeout does). The board reads it from the environment, so only the ring redraws.
@MainActor
final class TurnClockFeed: ObservableObject {
    @Published private(set) var board = TurnClockBoard()
    @Published private(set) var localSeat: String?
    @Published private(set) var seatNames: [String: String] = [:]

    func update(board: TurnClockBoard, localSeat: String?, seatNames: [String: String]) {
        if self.board != board { self.board = board }
        if self.localSeat != localSeat { self.localSeat = localSeat }
        if self.seatNames != seatNames { self.seatNames = seatNames }
    }
}

private struct TurnClockFeedKey: EnvironmentKey {
    static let defaultValue: TurnClockFeed? = nil
}

extension EnvironmentValues {
    /// The online table's turn clocks; nil in solo games, which have no clock.
    var turnClockFeed: TurnClockFeed? {
        get { self[TurnClockFeedKey.self] }
        set { self[TurnClockFeedKey.self] = newValue }
    }
}

/// The online turn timer's ring around the pass button (it replaced the burning rope, 2026-10-13).
/// For the last `TurnClockRules.rope` seconds of a decision an ember runs clockwise round the brass
/// ring, eating the glowing arc behind it; the arc turns ember red for the last 5 seconds.
/// Android: `TurnRope.kt`.
struct TurnClockRing: View {
    @ObservedObject var feed: TurnClockFeed
    let diameter: CGFloat
    @State private var burning = false

    var body: some View {
        let board = feed.board
        let local = feed.localSeat
        ZStack {
            if burning {
                // Redrawn at 30 Hz only while the ring burns; nothing ticks before that.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    if let rope = board.rope(localSeat: local, now: ProcessInfo.processInfo.systemUptime) {
                        TurnClockRingFace(rope: rope, name: feed.seatNames[rope.seat], diameter: diameter,
                                          time: context.date.timeIntervalSinceReferenceDate)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .task(id: RingWatch(board: board, local: local)) { await watch(board, local: local) }
    }

    private struct RingWatch: Equatable { let board: TurnClockBoard; let local: String? }

    /// Sleeps until the ring should light, then until it burns out.
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

/// The ring itself: a dark groove, the arc of time left from the ember back to twelve o'clock,
/// the ember, and (for an opponent's clock or after a timeout) a tag above the button.
private struct TurnClockRingFace: View {
    let rope: TurnClockBoard.Rope
    let name: String?
    let diameter: CGFloat
    let time: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        var text = rope.isLocal ? String(localized: "Your time") : String(localized: "\(name ?? String(localized: "Opponent"))’s time")
        if rope.strikes > 0 { text += " · " + String(localized: "timeout \(rope.strikes) of \(TurnClockRules.online.strikesToForfeit)") }
        return text.uppercased()
    }

    var body: some View {
        let urgent = rope.remaining <= 5
        let lineWidth = max(4, diameter * 0.055)
        let radius = diameter / 2 - lineWidth / 2
        let flicker = reduceMotion ? 1 : 1 + 0.18 * sin(time * 23) * cos(time * 7)
        let pulse = urgent && !reduceMotion ? 0.5 + 0.5 * sin(time * 9) : 0
        // The ember leads clockwise from twelve o'clock; the arc behind it is the time left.
        let angle = Angle.degrees(-90 + (1 - rope.fraction) * 360)
        // Hottest next to the ember, cooling toward twelve o'clock.
        let arcColors = urgent ? [Color(red: 1, green: 0.78, blue: 0.55), TavernPalette.ember, TavernPalette.enamel]
            : [TavernPalette.parchment, TavernPalette.brass, TavernPalette.brassDark]
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.55), lineWidth: lineWidth + 2)
                .padding(lineWidth / 2)
            Circle()
                .trim(from: 1 - rope.fraction, to: 1)
                // Drawn before the quarter turn, so the gradient's angles are the trim's own.
                .stroke(AngularGradient(colors: arcColors, center: .center,
                                        startAngle: .degrees((1 - rope.fraction) * 360), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
                .shadow(color: (urgent ? TavernPalette.ember : TavernPalette.brass).opacity(0.55 + 0.35 * pulse), radius: 4 + 4 * pulse)
                .opacity(rope.isLocal ? 1 : 0.8)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.95), TavernPalette.ember, TavernPalette.enamel.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: lineWidth * 1.4))
                .frame(width: lineWidth * 2.8, height: lineWidth * 2.8)
                .scaleEffect(flicker)
                .shadow(color: TavernPalette.ember.opacity(0.9), radius: 8)
                .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            // Right-aligned with the ring: the button sits near the screen's right edge.
            if !rope.isLocal || rope.strikes > 0 {
                TavernTag(text: label, leather: true, accent: urgent ? TavernPalette.ember : TavernPalette.brass)
                    .offset(y: -26)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(localized: "\(Int(rope.remaining.rounded(.up))) seconds left"))
    }
}
