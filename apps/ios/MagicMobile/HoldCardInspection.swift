import SwiftUI

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
    @GestureState private var touching = false
    @State private var opened = false

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35, maximumDistance: 8)
                .onEnded { _ in
                    opened = true
                    inspection?.begin(dismiss: release)
                    inspect()
                }
        )
        // Track lift/cancellation simultaneously, without making a zero-distance
        // drag part of the high-priority recognizer that arbitrates card taps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onEnded { _ in finish() }
        )
        .onChange(of: touching) { if !$0 { finish() } }
        .onDisappear { finish() }
    }

    private func finish() {
        guard opened else { return }
        opened = false
        if let inspection { inspection.end() } else { release() }
    }
}

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
