import SwiftUI
#if canImport(UIKit)
import UIKit

/// Connect the hand's scrubber to the same scroll view used by sideways card swipes.
/// No second gesture recognizer competes with card casting or inspection.
final class HandScrollController: ObservableObject {
    weak var scrollView: UIScrollView?
    @Published private(set) var progress: CGFloat = 0

    func refreshProgress() {
        guard let scrollView else { return }
        let start = -scrollView.adjustedContentInset.left
        let distance = scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right - start
        let next = distance > 0 ? min(1, max(0, (scrollView.contentOffset.x - start) / distance)) : 0
        if progress != next { progress = next }
    }

    func scroll(to progress: CGFloat) {
        guard let scrollView else { return }
        let start = -scrollView.adjustedContentInset.left
        let end = max(start, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right)
        scrollView.setContentOffset(CGPoint(x: start + (end - start) * min(1, max(0, progress)),
                                           y: scrollView.contentOffset.y), animated: false)
        refreshProgress()
    }
}

struct HandScrollConnection: UIViewRepresentable {
    let controller: HandScrollController
    func makeUIView(context: Context) -> ConnectionView { ConnectionView(controller: controller) }
    func updateUIView(_ view: ConnectionView, context: Context) { view.connect() }

    final class ConnectionView: UIView {
        let controller: HandScrollController
        init(controller: HandScrollController) {
            self.controller = controller
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); connect() }
        func connect() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView { controller.scrollView = scroll; return }
                ancestor = view.superview
            }
        }
    }
}

/// Reject sideways pans before recognition so the containing hand ScrollView
/// owns browsing. A SwiftUI DragGesture cannot fail after inspecting its angle.
struct HandCardPan: UIViewRepresentable {
    var changed: (CGSize, CGPoint) -> Void
    var ended: (CGSize, CGPoint, Bool) -> Void
    var inspect: () -> Void
    var tap: (() -> Void)? = nil
    var releaseInspection: () -> Void = {}
    /// Finger down on or up from the card (presentation only: lift under the finger).
    var pressed: (Bool) -> Void = { _ in }
    @Environment(\.holdCardInspection) private var inspection

    func makeUIView(context: Context) -> PanView {
        let view = PanView()
        view.changed = changed
        view.ended = ended
        view.inspect = inspect
        view.tap = tap
        view.pressed = pressed
        view.beginInspection = { inspection?.begin(dismiss: releaseInspection); inspect() }
        view.endInspection = { if let inspection { inspection.end() } else { releaseInspection() } }
        return view
    }

    func updateUIView(_ view: PanView, context: Context) {
        view.changed = changed
        view.ended = ended
        view.inspect = inspect
        view.tap = tap
        view.pressed = pressed
        view.beginInspection = { inspection?.begin(dismiss: releaseInspection); inspect() }
        view.endInspection = { if let inspection { inspection.end() } else { releaseInspection() } }
    }

    static func dismantleUIView(_ view: PanView, coordinator: ()) { view.finishInspection() }

    final class PanView: UIView, UIGestureRecognizerDelegate {
        var changed: ((CGSize, CGPoint) -> Void)?
        var ended: ((CGSize, CGPoint, Bool) -> Void)?
        var inspect: (() -> Void)?
        var tap: (() -> Void)?
        var pressed: ((Bool) -> Void)?
        var beginInspection: (() -> Void)?
        var endInspection: (() -> Void)?
        private var inspecting = false
        private var start = CGPoint.zero
        private weak var handScrollView: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(updatePan))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            addGestureRecognizer(pan)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.35
            hold.allowableMovement = 8
            addGestureRecognizer(hold)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.require(toFail: hold)
            tap.require(toFail: pan)
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { finishInspection(); return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if handScrollView !== scroll {
                        // Explicitly arbitrate with the containing scroll view.
                        // Its pan otherwise wins before this child receives .began.
                        scroll.panGestureRecognizer.require(toFail: pan)
                        handScrollView = scroll
                    }
                    break
                }
                ancestor = view.superview
            }
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
            let delta = pan.translation(in: self)
            return delta.y < 0 && abs(delta.y) > abs(delta.x) * 1.35
        }


        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            pressed?(true)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            pressed?(false)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            pressed?(false)
        }

        @objc private func tapped() { if let tap { tap() } else { inspect?() } }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: inspecting = true; beginInspection?()
            case .ended, .cancelled, .failed: finishInspection()
            default: break
            }
        }

        func finishInspection() {
            guard inspecting else { return }
            inspecting = false
            endInspection?()
        }

        @objc private func updatePan() {
            let delta = pan.translation(in: self)
            let translation = CGSize(width: delta.x, height: delta.y)
            if pan.state == .began {
                let point = pan.location(in: self)
                start = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
            }
            switch pan.state {
            case .began, .changed: changed?(translation, start)
            case .ended: ended?(translation, start, false)
            case .cancelled, .failed: ended?(translation, start, true)
            default: break
            }
        }
    }
}
#endif
