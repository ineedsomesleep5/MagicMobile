import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A slow breathing value for glows, stepped thirty times a second on one shared clock.
///
/// A SwiftUI repeating animation redraws at the display's full rate (up to 120 a second on
/// ProMotion) for as long as it runs, and the board's glows run for most of a player's turn. On a
/// glow this slow thirty steps a second look the same and let the display rest in between. Every
/// breath steps on the same grid (AmbientTimelineSchedule), fifteen a second while the phone is
/// hot, and rests at `high` once the board is idle (BoardActivity). Android's `rememberBoardBreath`
/// does the same.
struct BoardBreath<Content: View>: View {
    /// Seconds from `low` to `high`; the way back takes as long.
    let period: Double
    var low: Double = 0
    var high: Double = 1
    @ViewBuilder let content: (Double) -> Content
    @ObservedObject private var heat = DeviceHeat.shared
    @ObservedObject private var activity = BoardActivity.shared

    var body: some View {
        let resting = activity.isIdle
        TimelineView(AmbientTimelineSchedule(interval: heat.ambientInterval, paused: resting)) { timeline in
            content(resting ? high : Self.value(at: timeline.date, period: period, low: low, high: high))
        }
        .animation(.easeInOut(duration: 0.6), value: resting)
    }

    /// Eases between `low` and `high` like `.easeInOut`. Every breath reads the same wall clock, so
    /// glows with the same period rise and fall together.
    static func value(at date: Date, period: Double, low: Double, high: Double) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2 * period) / period
        return low + (high - low) * (0.5 - 0.5 * cos(.pi * phase))
    }
}

/// A repeating 0 to 1 for slow motion away from the board (menus, ranked pages), on the same grid as the breaths: thirty
/// steps a second, fifteen while hot. A repeating SwiftUI animation would redraw at up to 120 a second as long as its page
/// stays open. Unlike BoardBreath it never rests: BoardActivity only knows about the board.
struct AmbientLoop<Content: View>: View {
    let period: Double
    @ViewBuilder let content: (Double) -> Content
    @ObservedObject private var heat = DeviceHeat.shared

    var body: some View {
        TimelineView(AmbientTimelineSchedule(interval: heat.ambientInterval)) { timeline in
            content(AmbientTimelineSchedule.phase(at: timeline.date, period: period))
        }
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

/// Tells BoardActivity about every touch on the board's window without taking part in any gesture: its recognizer
/// fails as soon as a touch begins, never delays or cancels touches, and recognizes alongside everything else.
struct BoardTouchActivity: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView {
        private let noticer = TouchNoticer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if noticer.view !== window { detach() }
            window?.addGestureRecognizer(noticer)
        }

        func detach() { noticer.view?.removeGestureRecognizer(noticer) }
    }

    final class TouchNoticer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            BoardActivity.shared.note()
            state = .failed
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
