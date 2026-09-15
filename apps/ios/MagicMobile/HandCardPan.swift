import SwiftUI
#if canImport(UIKit)
import UIKit

/// Reject sideways pans before recognition so the containing hand ScrollView
/// owns browsing. A SwiftUI DragGesture cannot fail after inspecting its angle.
struct HandCardPan: UIViewRepresentable {
    var changed: (CGSize, CGPoint) -> Void
    var ended: (CGSize, CGPoint, Bool) -> Void
    var inspect: () -> Void

    func makeUIView(context: Context) -> PanView {
        let view = PanView()
        view.changed = changed
        view.ended = ended
        view.inspect = inspect
        return view
    }

    func updateUIView(_ view: PanView, context: Context) {
        view.changed = changed
        view.ended = ended
        view.inspect = inspect
    }

    final class PanView: UIView, UIGestureRecognizerDelegate {
        var changed: ((CGSize, CGPoint) -> Void)?
        var ended: ((CGSize, CGPoint, Bool) -> Void)?
        var inspect: (() -> Void)?
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
            guard window != nil else { return }
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


        @objc private func tapped() { inspect?() }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { inspect?() }
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
