import SwiftUI

/// A slow breathing value for glows, stepped thirty times a second on one shared clock.
///
/// A SwiftUI repeating animation redraws at the display's full rate (up to 120 a second on
/// ProMotion) for as long as it runs, and the board's glows run for most of a player's turn. On a
/// glow this slow thirty steps a second look the same and let the display rest in between.
/// Android's `rememberBoardBreath` does the same.
struct BoardBreath<Content: View>: View {
    /// Seconds from `low` to `high`; the way back takes as long.
    let period: Double
    var low: Double = 0
    var high: Double = 1
    @ViewBuilder let content: (Double) -> Content

    static var stepsPerSecond: Double { 30 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Self.stepsPerSecond)) { timeline in
            content(Self.value(at: timeline.date, period: period, low: low, high: high))
        }
    }

    /// Eases between `low` and `high` like `.easeInOut`. Every breath reads the same wall clock, so
    /// glows with the same period rise and fall together.
    static func value(at date: Date, period: Double, low: Double, high: Double) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2 * period) / period
        return low + (high - low) * (0.5 - 0.5 * cos(.pi * phase))
    }
}

/// Frames only while a brief effect is on screen: thirty a second for `active` seconds at the start
/// of every `cycle`, then nothing until the next cycle. A glint that shows for under a second every
/// few seconds no longer redraws thirty times a second in between.
struct BurstTimelineSchedule: TimelineSchedule {
    /// The cycles count from here (the same date the view measures its time from).
    let start: Date
    let cycle: TimeInterval
    let active: TimeInterval
    /// No frames at all (Reduce Motion, or the effect is switched off).
    var paused = false
    var frameInterval: TimeInterval = 1.0 / 30

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(schedule: self, upcoming: startDate, lowFrequency: mode == .lowFrequency)
    }

    struct Entries: Sequence, IteratorProtocol {
        let schedule: BurstTimelineSchedule
        var upcoming: Date?
        let lowFrequency: Bool

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            guard !schedule.paused, schedule.cycle > 0 else { upcoming = nil; return current }
            let elapsed = Swift.max(0, current.timeIntervalSince(schedule.start))
            let offset = elapsed.truncatingRemainder(dividingBy: schedule.cycle)
            // One frame past the active part draws the effect gone; then wait for the next cycle.
            if !lowFrequency, offset < schedule.active {
                upcoming = current.addingTimeInterval(schedule.frameInterval)
            } else {
                // Never a zero step: rounding at a cycle's very end must still move forward.
                upcoming = current.addingTimeInterval(Swift.max(schedule.cycle - offset, schedule.frameInterval))
            }
            return current
        }
    }
}
