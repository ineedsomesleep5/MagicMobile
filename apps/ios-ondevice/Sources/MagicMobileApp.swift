import SwiftUI

@main
struct MagicMobileApp: App {
    @State private var model = EngineLabModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            EngineLabView(model: model)
                .task { await model.connect() }
                .onChange(of: scenePhase) { _, phase in
                    // Stops UI polling/input only. This is not an engine checkpoint or a background server.
                    model.setForeground(phase == .active)
                }
        }
    }
}
