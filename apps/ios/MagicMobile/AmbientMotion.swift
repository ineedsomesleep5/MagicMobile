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
///
/// The frame times are a fixed grid counted from `start`. A timeline asks for its entries again and
/// again from "now"; the answer must begin with the latest grid time at or before that date and go
/// on with strictly later ones, or the view is told to update immediately, forever.
struct BurstTimelineSchedule: TimelineSchedule {
    /// The cycles count from here (the same date the view measures its time from).
    let start: Date
    let cycle: TimeInterval
    let active: TimeInterval
    /// No frames at all (Reduce Motion, or the effect is switched off).
    var paused = false
    var frameInterval: TimeInterval = 1.0 / 30

    /// Frames 0...burstFrames in each cycle; the last one falls after `active` and draws the effect gone.
    var burstFrames: Int { Int((active / frameInterval).rounded(.up)) }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        guard !paused, cycle > 0, frameInterval > 0, cycle > active + frameInterval else {
            return Entries(schedule: self, cycleIndex: 0, frameIndex: 0, lowFrequency: false, finished: false, single: true)
        }
        let elapsed = Swift.max(0, startDate.timeIntervalSince(start))
        let cycleIndex = Int(elapsed / cycle)
        let offset = elapsed - Double(cycleIndex) * cycle
        let lowFrequency = mode == .lowFrequency
        // Always-on displays get one frame a cycle: the effect gone.
        let frameIndex = lowFrequency ? burstFrames : Swift.min(burstFrames, Int(offset / frameInterval))
        return Entries(schedule: self, cycleIndex: cycleIndex, frameIndex: frameIndex, lowFrequency: lowFrequency,
                       finished: false, single: false)
    }

    struct Entries: Sequence, IteratorProtocol {
        let schedule: BurstTimelineSchedule
        var cycleIndex: Int
        var frameIndex: Int
        let lowFrequency: Bool
        var finished: Bool
        /// Paused: the one entry is `start`, so the view draws once and never again.
        let single: Bool

        mutating func next() -> Date? {
            guard !finished else { return nil }
            if single { finished = true; return schedule.start }
            let date = schedule.start.addingTimeInterval(Double(cycleIndex) * schedule.cycle
                                                         + Double(frameIndex) * schedule.frameInterval)
            if lowFrequency || frameIndex >= schedule.burstFrames {
                cycleIndex += 1
                frameIndex = lowFrequency ? schedule.burstFrames : 0
            } else {
                frameIndex += 1
            }
            return date
        }
    }
}
