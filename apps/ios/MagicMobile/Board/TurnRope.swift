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

    /// The seat a board player sits in: seat names are unique and are the engine's player names.
    func seat(named name: String?) -> String? {
        guard let name else { return nil }
        return seatNames.first { $0.value == name }?.key
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

/// The online turn timer (it replaced the burning rope, 2026-10-13): for the last
/// `TurnClockRules.rope` seconds of a seat's decision an ember runs clockwise round a brass ring,
/// eating the glowing arc behind it; the arc turns ember red for the last 5 seconds. Your own clock
/// rings the pass button and an opponent's rings their medallion, so whose time it is needs no
/// words. Timeouts show as studs at three o'clock. Android: `TurnRope.kt`.
struct TurnClockRing: View {
    @ObservedObject var feed: TurnClockFeed
    /// Whose clock this ring shows, by table name; nil is this phone's own seat. Resolved here,
    /// where the feed is observed, so a ring drawn before the seat names arrive still lights.
    var playerName: String? = nil
    let diameter: CGFloat
    @State private var burning = false

    var body: some View {
        let seat = playerName.map { feed.seat(named: $0) } ?? feed.localSeat
        // Only this seat's clock; the board's own pick prefers yours and then the soonest.
        let board = TurnClockBoard(paused: feed.board.paused, clocks: feed.board.clocks.filter { $0.seat == seat })
        let isLocal = seat != nil && seat == feed.localSeat
        ZStack {
            if burning, let seat {
                // Redrawn at 30 Hz only while the ring burns; nothing ticks before that.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    if let rope = board.rope(localSeat: seat, now: ProcessInfo.processInfo.systemUptime) {
                        TurnClockRingFace(rope: rope, isLocal: isLocal, name: feed.seatNames[seat], diameter: diameter,
                                          time: context.date.timeIntervalSinceReferenceDate)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .task(id: RingWatch(board: board, seat: seat)) { await watch(board, seat: seat, isLocal: isLocal) }
    }

    private struct RingWatch: Equatable { let board: TurnClockBoard; let seat: String? }

    /// Sleeps until the ring should light, then until it burns out.
    private func watch(_ board: TurnClockBoard, seat: String?, isLocal: Bool) async {
        while !Task.isCancelled {
            let now = ProcessInfo.processInfo.systemUptime
            guard let seat, let wait = board.secondsUntilRope(localSeat: seat, now: now) else { burning = false; return }
            if wait > 0 {
                burning = false
                try? await Task.sleep(for: .seconds(wait))
            } else {
                if !burning, isLocal { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                burning = true
                try? await Task.sleep(for: .seconds((board.rope(localSeat: seat, now: now)?.remaining ?? 0) + 0.25))
            }
        }
    }
}

/// The ring itself: a dark groove, the arc of time left from the ember back to twelve o'clock,
/// the ember, and one stud per timeout in a row.
private struct TurnClockRingFace: View {
    let rope: TurnClockBoard.Rope
    let isLocal: Bool
    let name: String?
    let diameter: CGFloat
    let time: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let frost = Color(red: 0.45, green: 0.72, blue: 1)

    private var label: String {
        var text = isLocal ? String(localized: "Your time") : String(localized: "\(name ?? String(localized: "Opponent"))’s time")
        if rope.strikes > 0 { text += ", " + String(localized: "timeout \(rope.strikes) of \(TurnClockRules.online.strikesToForfeit)") }
        return text
    }

    var body: some View {
        let urgent = rope.remaining <= 5
        let lineWidth = max(4, diameter * 0.055)
        let radius = diameter / 2 - lineWidth / 2
        let flicker = reduceMotion ? 1 : 1 + 0.18 * sin(time * 23) * cos(time * 7)
        let pulse = urgent && !reduceMotion ? 0.5 + 0.5 * sin(time * 9) : 0
        // The ember leads clockwise from twelve o'clock; the arc behind it is the time left.
        let angle = Angle.degrees(-90 + (1 - rope.fraction) * 360)
        // Hottest next to the ember, cooling toward twelve o'clock. An opponent's burns cold blue
        // until the last 5 seconds, so it stands off their brass frame (and off your own ring).
        let arcColors = urgent ? [Color(red: 1, green: 0.78, blue: 0.55), TavernPalette.ember, TavernPalette.enamel]
            : isLocal ? [TavernPalette.parchment, TavernPalette.brass, TavernPalette.brassDark]
            : [Color(red: 0.88, green: 0.95, blue: 1), Self.frost, Color(red: 0.12, green: 0.26, blue: 0.52)]
        let spark = urgent || isLocal ? TavernPalette.ember : Self.frost
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
                .shadow(color: (urgent ? TavernPalette.ember : isLocal ? TavernPalette.brass : Self.frost).opacity(0.55 + 0.35 * pulse), radius: 4 + 4 * pulse)
            // Timeouts in a row: studs on the groove at three o'clock (twelve sits under the camera
            // on the opponent's medallion), lit for each one.
            if rope.strikes > 0 {
                ForEach(0..<TurnClockRules.online.strikesToForfeit, id: \.self) { index in
                    let stud = Angle.degrees(Double(index - 1) * 11)
                    Circle()
                        .fill(index < rope.strikes ? TavernPalette.ember : TavernPalette.brassDark)
                        .overlay(Circle().strokeBorder(TavernPalette.brass, lineWidth: 1))
                        .frame(width: lineWidth * 1.5, height: lineWidth * 1.5)
                        .shadow(color: index < rope.strikes ? TavernPalette.ember : .clear, radius: 3)
                        .offset(x: radius * cos(stud.radians), y: radius * sin(stud.radians))
                }
            }
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.95), spark, spark.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: lineWidth * 1.4))
                .frame(width: lineWidth * 2.8, height: lineWidth * 2.8)
                .scaleEffect(flicker)
                .shadow(color: spark.opacity(0.9), radius: 8)
                .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(localized: "\(Int(rope.remaining.rounded(.up))) seconds left"))
    }
}
