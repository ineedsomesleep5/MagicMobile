import SwiftUI
import CoreMotion

/// The tavern room behind the main menu: a rendered 3D room (scripts/brand/tavern_room.py) in three
/// depth layers that slide against each other as the phone tilts, with its candles, lanterns and hearth
/// flickering on top. Android draws the same room (TavernRoomBackdrop.kt).
struct TavernRoomBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAmbientMotion) private var ambient
    @StateObject private var tilt = DeviceTilt()
    @ObservedObject private var images = TavernRoomImages.shared
    @State private var start = Date()

    /// The room's art is installed (tavern-room-* images and tavern-room.json).
    static var available: Bool { TavernRoomScene.shared != nil }

    var body: some View {
        GeometryReader { proxy in
            let orientation = proxy.size.height >= proxy.size.width ? TavernRoomScene.portrait : TavernRoomScene.landscape
            if let scene = TavernRoomScene.shared, let shot = scene.views[orientation] {
                let moving = !reduceMotion && ambient
                let layers = images.orientation == orientation ? images.layers : [:]
                ZStack {
                    ForEach(TavernRoomScene.Layer.allCases, id: \.self) { layer in
                        if let image = layers[layer] {
                            TavernRoomLayer(shot: shot, image: image, size: proxy.size, offset: tilt.offset * layer.depth)
                        }
                    }
                    if layers.isEmpty {
                        // Decoding (first appearance or a turn of the phone): the room fades in when ready.
                        EmptyView()
                    } else if moving {
                        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                            glows(shot, size: proxy.size, t: timeline.date.timeIntervalSince(start))
                        }
                    } else {
                        glows(shot, size: proxy.size, t: 0)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .animation(.easeOut(duration: 0.35), value: layers.isEmpty)
                .task(id: orientation) { images.load(orientation) }
            }
        }
        // Tilt only while the room is on screen and moving; anything covering the menu stops it.
        .onAppear { if !reduceMotion && ambient { tilt.start() } }
        .onDisappear { tilt.stop() }
        .onChange(of: !reduceMotion && ambient) { _, now in if now { tilt.start() } else { tilt.stop() } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Warm glows over each flame, breathing at their own pace; nearer flames move with their layer.
    private func glows(_ shot: TavernRoomScene.Shot, size: CGSize, t: Double) -> some View {
        Canvas { context, canvasSize in
            context.blendMode = .plusLighter
            for (index, light) in shot.lights.enumerated() {
                let layer = TavernRoomScene.Layer(rawValue: light.layer) ?? .back
                let center = shot.point(light, in: canvasSize, offset: tilt.offset * layer.depth)
                let seed = Double(index) * 1.618
                let flicker = 0.78 + 0.14 * sin(t * (7.1 + seed) + seed) + 0.08 * sin(t * (13.3 + seed * 0.7))
                let radius = max(8, light.radius * shot.scale(in: canvasSize) * shot.height * (light.kind == "hearth" ? 1.2 : 1.6))
                    * (0.94 + 0.06 * flicker)
                let warm = light.kind == "hearth" ? Color(red: 1, green: 0.45, blue: 0.12) : Color(red: 1, green: 0.62, blue: 0.28)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [warm.opacity(0.42 * flicker), warm.opacity(0.12 * flicker), .clear]),
                    center: center, startRadius: 0, endRadius: radius))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One depth layer: the image aspect-filled with a little overscan, shifted by the tilt.
private struct TavernRoomLayer: View {
    let shot: TavernRoomScene.Shot
    let image: UIImage
    let size: CGSize
    let offset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width * TavernRoomScene.overscan, height: size.height * TavernRoomScene.overscan)
            .offset(offset)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

/// The installed room: per orientation, its three images and where its flames sit.
final class TavernRoomScene {
    enum Layer: String, CaseIterable {
        case back, mid, front
        /// How far the layer slides with the tilt: nearer moves more, which reads as depth.
        var depth: CGFloat {
            switch self {
            case .back: return 0.3
            case .mid: return 0.65
            case .front: return 1
            }
        }
    }

    struct Light: Decodable {
        let x: Double
        let y: Double
        let layer: String
        let kind: String
        /// A fraction of the image's height.
        let radius: Double
    }

    struct Shot {
        let orientation: String
        let width: Double
        let height: Double
        let lights: [Light]

        /// Every layer is in the asset catalogue (looked up, not decoded or kept).
        var complete: Bool { Layer.allCases.allSatisfy { UIImage(named: Self.imageName(orientation, $0)) != nil } }

        static func imageName(_ orientation: String, _ layer: Layer) -> String { "tavern-room-\(orientation)-\(layer.rawValue)" }

        /// The aspect-fill scale of the rendered frame (with overscan) into `size`.
        func scale(in size: CGSize) -> Double {
            max(size.width * TavernRoomScene.overscan / width, size.height * TavernRoomScene.overscan / height)
        }

        /// Where a light lands on screen.
        func point(_ light: Light, in size: CGSize, offset: CGSize) -> CGPoint {
            let s = scale(in: size)
            let drawnWidth = width * s, drawnHeight = height * s
            return CGPoint(x: (size.width - drawnWidth) / 2 + light.x * drawnWidth + offset.width,
                           y: (size.height - drawnHeight) / 2 + light.y * drawnHeight + offset.height)
        }
    }

    static let portrait = "portrait"
    static let landscape = "landscape"
    /// Each layer is drawn this much larger than the screen so a tilt never shows its edge.
    static let overscan: CGFloat = 1.08

    let views: [String: Shot]

    private struct File: Decodable {
        struct Orientation: Decodable { let width: Double; let height: Double; let lights: [Light] }
        let portrait: Orientation
        let landscape: Orientation
    }

    private init?(data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let portrait = Shot(orientation: Self.portrait, width: file.portrait.width, height: file.portrait.height, lights: file.portrait.lights)
        let landscape = Shot(orientation: Self.landscape, width: file.landscape.width, height: file.landscape.height, lights: file.landscape.lights)
        guard portrait.complete, landscape.complete else { return nil }
        views = [Self.portrait: portrait, Self.landscape: landscape]
    }

    /// Loaded once; nil when the room isn't installed (the flat tavern wall shows instead).
    static let shared: TavernRoomScene? = {
        guard let url = Bundle.main.url(forResource: "tavern-room", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return TavernRoomScene(data: data)
    }()
}

/// The phone's tilt from where it was held when the room appeared, smoothed, as a small offset.
@MainActor
final class DeviceTilt: ObservableObject {
    @Published private(set) var offset: CGSize = .zero
    /// The furthest the nearest layer slides, in points.
    static let reach: CGFloat = 16
    private let motion = CMMotionManager()
    private var reference: (x: Double, y: Double)?

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        reference = nil
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            let reference = self.reference ?? (gravity.x, gravity.y)
            self.reference = (reference.x * 0.995 + gravity.x * 0.005, reference.y * 0.995 + gravity.y * 0.005)  // drifts back to centre
            let dx = max(-1, min(1, (gravity.x - reference.x) * 3)), dy = max(-1, min(1, (gravity.y - reference.y) * 3))
            let target = CGSize(width: -dx * Self.reach, height: dy * Self.reach)
            let next = CGSize(width: self.offset.width * 0.8 + target.width * 0.2, height: self.offset.height * 0.8 + target.height * 0.2)
            // Publish only a visible move: a still phone must not redraw the menu thirty times a second
            // (that churn also made the simulator drop taps in screens covering the menu).
            if abs(next.width - self.offset.width) >= 0.25 || abs(next.height - self.offset.height) >= 0.25 { self.offset = next }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        if offset != .zero { offset = .zero }
    }
}

private func * (size: CGSize, factor: CGFloat) -> CGSize { CGSize(width: size.width * factor, height: size.height * factor) }

/// The room's layers for one orientation at a time, decoded off the main thread: three screen-sized
/// images decoded on first draw stalled launch and every return to the menu.
@MainActor
final class TavernRoomImages: ObservableObject {
    static let shared = TavernRoomImages()
    @Published private(set) var orientation: String?
    @Published private(set) var layers: [TavernRoomScene.Layer: UIImage] = [:]
    private var loading: String?

    func load(_ orientation: String) {
        guard orientation != self.orientation, orientation != loading else { return }
        loading = orientation
        Task.detached(priority: .userInitiated) {
            var decoded: [TavernRoomScene.Layer: UIImage] = [:]
            for layer in TavernRoomScene.Layer.allCases {
                if let image = UIImage(named: TavernRoomScene.Shot.imageName(orientation, layer))?.preparingForDisplay() {
                    decoded[layer] = image
                }
            }
            await MainActor.run {
                guard self.loading == orientation else { return }
                // Only this orientation stays in memory.
                self.layers = decoded
                self.orientation = orientation
                self.loading = nil
            }
        }
    }
}
