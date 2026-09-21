import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A touch-owned inspection is transient. Explicit Inspect actions remain persistent.
final class HoldCardInspection: ObservableObject {
    @Published private(set) var isActive = false
    private var dismiss: (() -> Void)?

    func begin(dismiss: @escaping () -> Void) {
        end()
        self.dismiss = dismiss
        isActive = true
    }

    func end() {
        guard isActive else { return }
        let completion = dismiss
        dismiss = nil
        isActive = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { completion?() }
    }
}

private struct HoldCardInspectionKey: EnvironmentKey {
    static let defaultValue: HoldCardInspection? = nil
}

extension EnvironmentValues {
    var holdCardInspection: HoldCardInspection? {
        get { self[HoldCardInspectionKey.self] }
        set { self[HoldCardInspectionKey.self] = newValue }
    }
}

private struct HoldInspectionScope: ViewModifier {
    @StateObject private var inspection = HoldCardInspection()
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.environment(\.holdCardInspection, inspection)
            .onChange(of: phase) { phase in if phase != .active { inspection.end() } }
            .onDisappear { inspection.end() }
    }
}

private struct CardHoldModifier: ViewModifier {
    let inspect: () -> Void
    let release: () -> Void
    @Environment(\.holdCardInspection) private var inspection
    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.overlay {
            CardHoldTouchView(begin: {
                inspection?.begin(dismiss: release)
                inspect()
            }, end: {
                if let inspection { inspection.end() } else { release() }
            })
            .accessibilityHidden(true)
        }
        #else
        content.onLongPressGesture(minimumDuration: 0.35, maximumDistance: 8, pressing: {
            if !$0 { release() }
        }, perform: inspect)
        #endif
    }
}

#if canImport(UIKit)
/// A long press remains possible only while the finger is still. Unlike a
/// zero-distance SwiftUI drag, it never claims a swipe from the parent scroll view.
private struct CardHoldTouchView: UIViewRepresentable {
    let begin: () -> Void
    let end: () -> Void

    func makeUIView(context: Context) -> TouchView { TouchView() }
    func updateUIView(_ view: TouchView, context: Context) {
        view.begin = begin
        view.end = end
    }
    static func dismantleUIView(_ view: TouchView, coordinator: ()) { view.finish() }

    final class TouchView: UIView {
        var begin: (() -> Void)?
        var end: (() -> Void)?
        private var inspecting = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.35
            hold.allowableMovement = 8
            addGestureRecognizer(hold)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { finish() }
        }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: inspecting = true; begin?()
            case .ended, .cancelled, .failed: finish()
            default: break
            }
        }
        func finish() {
            guard inspecting else { return }
            inspecting = false
            end?()
        }
    }
}
#endif

private struct HoldInspectionInteraction: ViewModifier {
    @Environment(\.holdCardInspection) private var inspection
    func body(content: Content) -> some View {
        if let inspection {
            HoldInspectionInteractionContent(inspection: inspection, content: content)
        } else { content }
    }
}

private struct HoldInspectionInteractionContent<Content: View>: View {
    @ObservedObject var inspection: HoldCardInspection
    let content: Content
    var body: some View { content.allowsHitTesting(!inspection.isActive) }
}

extension View {
    func holdInspectionScope() -> some View { modifier(HoldInspectionScope()) }
    func onCardHold(inspect: @escaping () -> Void, release: @escaping () -> Void) -> some View {
        modifier(CardHoldModifier(inspect: inspect, release: release))
    }
    func inspectionTouchPassthrough() -> some View { modifier(HoldInspectionInteraction()) }
}
