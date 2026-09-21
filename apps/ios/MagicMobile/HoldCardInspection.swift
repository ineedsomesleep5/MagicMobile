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

private struct CardInteractionModifier: ViewModifier {
    let tap: () -> Void
    let inspect: () -> Void
    let release: () -> Void
    @Environment(\.holdCardInspection) private var inspection
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.overlay {
            CardTouchView(tap: tap, begin: {
                inspection?.begin(dismiss: release)
                inspect()
            }, end: endInspection, enabled: enabled)
            .accessibilityHidden(true)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { tap() } }
        #else
        content.onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 8,
                pressing: { if !$0 { endInspection() } }, perform: inspect)
        #endif
    }

    private func endInspection() {
        if let inspection { inspection.end() } else { release() }
    }
}

#if canImport(UIKit)
/// UIKit arbitrates both card gestures against its containing scroll view.
/// A hold cancels selection; a swipe cancels both. No touch-down drag competes
/// with scrolling, and the transparent touch view owns taps explicitly.
private struct CardTouchView: UIViewRepresentable {
    let tap: () -> Void
    let begin: () -> Void
    let end: () -> Void
    let enabled: Bool

    func makeUIView(context: Context) -> TouchView { TouchView() }
    func updateUIView(_ view: TouchView, context: Context) {
        view.tap = tap
        view.begin = begin
        view.end = end
        view.isUserInteractionEnabled = enabled
        if !enabled { view.finish() }
    }
    static func dismantleUIView(_ view: TouchView, coordinator: ()) { view.finish() }

    final class TouchView: UIView {
        var tap: (() -> Void)?
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
            let selection = UITapGestureRecognizer(target: self, action: #selector(selected(_:)))
            selection.require(toFail: hold)
            addGestureRecognizer(hold)
            addGestureRecognizer(selection)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { finish() }
        }
        @objc private func selected(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { tap?() }
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
    func onCardInteraction(tap: @escaping () -> Void, inspect: @escaping () -> Void, release: @escaping () -> Void) -> some View {
        modifier(CardInteractionModifier(tap: tap, inspect: inspect, release: release))
    }
    func inspectionTouchPassthrough() -> some View { modifier(HoldInspectionInteraction()) }
}
