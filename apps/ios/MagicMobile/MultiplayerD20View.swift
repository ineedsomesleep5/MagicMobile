import SceneKit
import SwiftUI
import UIKit

/// A presentation of authoritative starting-roll data. The match coordinator owns
/// the dice values, tie rounds, and winner; this view only plays them back.
struct MultiplayerD20View: View {
    let roll: OnDeviceStartingRoll
    let seatNames: [String: String]
    let isLocalWinner: Bool
    let onDismiss: () -> Void

    init(roll: OnDeviceStartingRoll, seatNames: [String: String], isLocalWinner: Bool,
         onDismiss: @escaping () -> Void) {
        self.roll = roll
        self.seatNames = seatNames
        self.isLocalWinner = isLocalWinner
        self.onDismiss = onDismiss
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var dieFlight
    @State private var shownRoundIndex: Int?
    @State private var activeSeatID: String?
    @State private var activeValue: Int?
    @State private var settledRolls: [String: Int] = [:]
    @State private var traveled = false
    @State private var landed = false
    @State private var playbackFinished = false
    @State private var spinTurns = 0
    @State private var skipAnimation = false
    @State private var playedRounds: [[String: Int]] = []

    private var rounds: [[String: Int]] { roll.rounds.map(\.rolls) }
    private var playerIDs: [String] {
        (rounds.first.map { Array($0.keys) } ?? Array(seatNames.keys)).sorted()
    }

    private var playbackKey: PlaybackKey {
        PlaybackKey(seatNames: seatNames, rounds: rounds, winnerID: roll.winnerSeatID,
                    reduceMotion: reduceMotion, skipAnimation: skipAnimation)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width >= 560
            let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : (wide ? playerIDs.count : 2)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columnCount))

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if wide {
                            HStack(alignment: .center, spacing: 20) {
                                header.frame(maxWidth: 230)
                                if !playbackFinished { rollStage(wide: true) }
                            }
                        } else {
                            header
                            if !playbackFinished { rollStage(wide: false) }
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(playerIDs, id: \.self) { playerID in
                                playerCard(playerID, compact: wide)
                            }
                        }
                    }
                    .padding(18)
                }
                if playbackFinished, winnerName != nil {
                    Button(action: onDismiss) {
                        Text("Continue to game")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .accessibilityIdentifier("multiplayerD20.continue")
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(Palette.canvas)
        }
        .frame(minHeight: 310)
        .task(id: playbackKey) { await playSuppliedRounds() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STARTING ROLL")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Palette.accent)
            Text(headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            if !playbackFinished && !reduceMotion {
                Button("Skip animation") { skipAnimation = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 5)
                    .accessibilityIdentifier("multiplayerD20.skipAnimation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        if playbackFinished, let winnerName {
            return isLocalWinner ? "You won the roll" : "\(winnerName) wins the roll"
        }
        if let activeSeatID { return "\(seatNames[activeSeatID] ?? "Player") rolls" }
        if let shownRoundIndex, shownRoundIndex > 0 { return "Tie. Roll again." }
        return "Who goes first?"
    }

    private var detail: String {
        guard let shownRoundIndex else { return "Waiting for the shared D20 results." }
        if playbackFinished, winnerName != nil { return "Round \(shownRoundIndex + 1) of \(rounds.count) · D20" }
        return "Round \(shownRoundIndex + 1) of \(rounds.count) · Highest roll starts. Ties reroll."
    }

    private var winnerName: String? {
        guard playerIDs.contains(roll.winnerSeatID) else { return nil }
        return seatNames[roll.winnerSeatID] ?? "Player"
    }

    private func rollStage(wide: Bool) -> some View {
        GeometryReader { stage in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Palette.accent.opacity(0.25), lineWidth: 1))
                if let seat = activeSeatID {
                    D20Face(value: landed ? activeValue : nil, spinning: !landed,
                            turns: spinTurns, emphasized: landed, compact: false)
                        .frame(width: wide ? 112 : 132, height: wide ? 112 : 132)
                        .matchedGeometryEffect(id: "die-\(seat)", in: dieFlight)
                        .offset(x: traveled ? 0 : -min(stage.size.width * 0.38, 160),
                                y: traveled ? 0 : -12)
                        .rotationEffect(.degrees(traveled ? 0 : -18))
                        .overlay(alignment: .topTrailing) {
                            if landed, let activeValue {
                                Text("\(activeValue)")
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Palette.accent, in: Capsule())
                                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                                    .offset(x: 18, y: -10)
                            }
                        }
                } else {
                    Text(playbackFinished ? "Roll complete" : "D20 · Starting player")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .frame(height: wide ? 124 : 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activeSeatID.map { "\(seatNames[$0] ?? "Player") rolling a D20" } ??
                            (playbackFinished ? "Starting roll complete" : "Preparing the D20"))
    }

    private func playerCard(_ playerID: String, compact: Bool) -> some View {
        let name = seatNames[playerID] ?? "Player"
        let value = settledRolls[playerID]
        let isRolling = activeSeatID == playerID
        let isWinner = playbackFinished && roll.winnerSeatID == playerID
        let isOut = shownRoundIndex.map { $0 > 0 && rounds[$0][playerID] == nil && value != nil } ?? false

        return VStack(spacing: compact ? 7 : 10) {
            Group {
                if let value, !isRolling {
                    D20Face(value: value, spinning: false, turns: 0,
                            emphasized: isWinner, compact: true)
                        .matchedGeometryEffect(id: "die-\(playerID)", in: dieFlight)
                } else {
                    Image(systemName: "dice")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(Palette.secondary.opacity(0.7))
                }
            }
            .frame(width: compact ? 68 : 76, height: compact ? 68 : 76)
            .accessibilityHidden(true)

            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(status(for: playerID, value: value, isRolling: isRolling,
                        isOut: isOut, isWinner: isWinner))
                .font(.caption.weight(.medium))
                .foregroundStyle(isWinner ? Palette.accent : Palette.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 12 : 18)
        .padding(.horizontal, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(isWinner ? Palette.accent : Palette.ink.opacity(0.12), lineWidth: isWinner ? 2 : 1))
        .opacity(isOut ? 0.65 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(for: playerID, name: name,
                                                     displayedValue: value, isRolling: isRolling,
                                                     isOut: isOut, isWinner: isWinner))
    }

    private func status(for playerID: String, value: Int?, isRolling: Bool,
                        isOut: Bool, isWinner: Bool) -> String {
        if isWinner { return "Goes first" }
        if isOut { return "Out of the reroll" }
        if isRolling { return "Rolling…" }
        guard let value else { return "Ready" }
        if let shownRoundIndex, shownRoundIndex < rounds.count - 1,
           tiedLeaders(in: shownRoundIndex).contains(playerID) { return "Tied · reroll" }
        return "Rolled \(value)"
    }

    private func accessibilityDescription(for playerID: String, name: String, displayedValue: Int?,
                                          isRolling: Bool, isOut: Bool, isWinner: Bool) -> String {
        if isRolling { return "\(name) is rolling a twenty-sided die" }
        guard let displayedValue else { return "\(name), waiting to roll" }
        let suffix: String
        if isWinner { suffix = "goes first" }
        else if isOut { suffix = "out of the reroll" }
        else if let shownRoundIndex, shownRoundIndex < rounds.count - 1,
                tiedLeaders(in: shownRoundIndex).contains(playerID) {
            suffix = "tied for highest; rerolling"
        } else { suffix = "result" }
        return "\(name) rolled \(displayedValue) on a twenty-sided die; \(suffix)"
    }

    private func tiedLeaders(in index: Int) -> Set<String> {
        guard rounds.indices.contains(index), let highest = rounds[index].values.max() else { return [] }
        let leaders = rounds[index].filter { $0.value == highest }
        return leaders.count > 1 ? Set(leaders.map(\.key)) : []
    }

    @MainActor
    private func playSuppliedRounds() async {
        guard !rounds.isEmpty else {
            shownRoundIndex = nil
            activeSeatID = nil
            settledRolls = [:]
            playbackFinished = false
            playedRounds = []
            return
        }

        if reduceMotion || skipAnimation {
            shownRoundIndex = rounds.count - 1
            activeSeatID = nil
            settledRolls = rounds.reduce(into: [:]) { values, round in
                values.merge(round, uniquingKeysWith: { _, latest in latest })
            }
            playbackFinished = true
            playedRounds = rounds
            return
        }

        // Appended authoritative rounds continue from the last displayed tie.
        let continuesPrevious = !playedRounds.isEmpty && rounds.starts(with: playedRounds)
        let firstNewRound = continuesPrevious ? playedRounds.count : 0
        if firstNewRound == rounds.count {
            playbackFinished = true
            return
        }

        playbackFinished = false
        for index in firstNewRound..<rounds.count {
            guard !Task.isCancelled else { return }
            shownRoundIndex = index
            for seat in playerIDs where rounds[index][seat] != nil {
                guard !Task.isCancelled, let value = rounds[index][seat] else { return }
                settledRolls.removeValue(forKey: seat)
                activeSeatID = seat
                activeValue = value
                traveled = false
                landed = false
                spinTurns += 1
                // Let the die appear at the launch edge before animating to center.
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { traveled = true }
                try? await Task.sleep(for: .milliseconds(720))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { landed = true }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    settledRolls[seat] = value
                    activeSeatID = nil
                }
                try? await Task.sleep(for: .milliseconds(360))
            }
            playedRounds = Array(rounds.prefix(index + 1))
        }
        withAnimation(.easeOut(duration: 0.28)) { playbackFinished = true }
    }

    private struct PlaybackKey: Equatable {
        let seatNames: [String: String]
        let rounds: [[String: Int]]
        let winnerID: String?
        let reduceMotion: Bool
        let skipAnimation: Bool
    }

    private enum Palette {
        static let canvas = Color(red: 20 / 255, green: 21 / 255, blue: 24 / 255)
        static let surface = Color(red: 31 / 255, green: 33 / 255, blue: 37 / 255)
        static let ink = Color(red: 243 / 255, green: 241 / 255, blue: 236 / 255)
        static let secondary = Color(red: 177 / 255, green: 178 / 255, blue: 182 / 255)
        static let accent = Color(red: 1, green: 128 / 255, blue: 88 / 255)
    }

    private struct D20Face: View {
        let value: Int?
        let spinning: Bool
        let turns: Int
        let emphasized: Bool
        let compact: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Group {
                if reduceMotion {
                    staticFace
                } else {
                    D20SceneView(value: value, turns: turns, spinning: spinning)
                }
            }
            .shadow(color: Palette.accent.opacity(emphasized ? 0.38 : 0.18), radius: 14, y: 8)
        }

        private var staticFace: some View {
            ZStack {
                DieOutline()
                    .fill(LinearGradient(colors: [Palette.accent.opacity(0.95), Palette.accent.opacity(0.45),
                                                  Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                DieFacets().stroke(Palette.ink.opacity(0.28), lineWidth: 1)
                DieOutline().strokeBorder(Palette.ink.opacity(0.7), lineWidth: 1.5)
                Text(value.map(String.init) ?? "D20")
                    .font(.system(size: compact ? 25 : 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// A real icosahedron: 12 vertices, 20 flat-shaded triangular faces, and 30 edges.
    /// Each face is numbered. The chosen face is oriented toward the camera before
    /// the full-turn tumble, so SceneKit never selects or changes a game result.
    private struct D20SceneView: UIViewRepresentable {
        let value: Int?
        let turns: Int
        let spinning: Bool

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> SCNView {
            let view = SCNView(frame: .zero)
            view.scene = context.coordinator.scene
            view.backgroundColor = .clear
            view.isOpaque = false
            view.allowsCameraControl = false
            view.isUserInteractionEnabled = false
            view.autoenablesDefaultLighting = false
            view.antialiasingMode = .multisampling4X
            view.preferredFramesPerSecond = 30
            view.rendersContinuously = false
            view.isPlaying = true
            view.accessibilityElementsHidden = true
            return view
        }

        func updateUIView(_ view: SCNView, context: Context) {
            context.coordinator.present(value: value, turns: turns, spinning: spinning)
        }

        final class Coordinator {
            let scene = SCNScene()
            private let die = SCNNode()
            private let labels = SCNNode()
            private var faceOrientations: [simd_quatf] = []
            private var lastValue: Int?
            private var lastTurns = 0

            init() {
                buildDie()
                scene.rootNode.addChildNode(die)

                let camera = SCNNode()
                let optics = SCNCamera()
                optics.usesOrthographicProjection = true
                optics.orthographicScale = 2.15
                camera.camera = optics
                camera.position = SCNVector3(0, 0, 4)
                scene.rootNode.addChildNode(camera)

                let key = SCNNode()
                key.light = SCNLight()
                key.light?.type = .omni
                key.light?.intensity = 900
                key.position = SCNVector3(-2, 3, 4)
                scene.rootNode.addChildNode(key)

                let fill = SCNNode()
                fill.light = SCNLight()
                fill.light?.type = .ambient
                fill.light?.intensity = 350
                scene.rootNode.addChildNode(fill)
                scene.background.contents = UIColor.clear
            }

            func present(value: Int?, turns: Int, spinning: Bool) {
                labels.isHidden = value == nil
                let resultChanged = value != lastValue
                let newTurn = turns != lastTurns
                guard resultChanged || newTurn else { return }
                lastValue = value
                lastTurns = turns
                die.removeAction(forKey: "tumble")
                if let value, (1...20).contains(value) {
                    die.simdOrientation = simd_inverse(faceOrientations[value - 1])
                } else {
                    die.simdOrientation = simd_quatf(angle: 0.55, axis: SIMD3<Float>(0, 1, 0))
                }
                guard newTurn && spinning else { return }
                // Integral full turns end at the same orientation as the supplied face.
                let tumble = SCNAction.rotateBy(x: .pi * 2, y: .pi * 4, z: .pi * 2, duration: 0.72)
                tumble.timingMode = .easeInEaseOut
                die.runAction(tumble, forKey: "tumble")
            }

            private func buildDie() {
                let phi = Float((1 + sqrt(5.0)) / 2)
                let raw: [SIMD3<Float>] = [
                    [-1, phi, 0], [1, phi, 0], [-1, -phi, 0], [1, -phi, 0],
                    [0, -1, phi], [0, 1, phi], [0, -1, -phi], [0, 1, -phi],
                    [phi, 0, -1], [phi, 0, 1], [-phi, 0, -1], [-phi, 0, 1]
                ]
                let vertices = raw.map(simd_normalize)
                let faces: [[Int]] = [
                    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
                    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
                    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
                    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
                ]

                var positions: [SCNVector3] = []
                var normals: [SCNVector3] = []
                for (faceIndex, face) in faces.enumerated() {
                    let a = vertices[face[0]]
                    var b = vertices[face[1]]
                    var c = vertices[face[2]]
                    var normal = simd_normalize(simd_cross(b - a, c - a))
                    if simd_dot(normal, a + b + c) < 0 {
                        swap(&b, &c)
                        normal = -normal
                    }
                    for vertex in [a, b, c] {
                        positions.append(SCNVector3(vertex.x, vertex.y, vertex.z))
                        normals.append(SCNVector3(normal.x, normal.y, normal.z))
                    }
                    let basis = Self.faceBasis(normal)
                    faceOrientations.append(basis)

                    let text = SCNText(string: String(faceIndex + 1), extrusionDepth: 0.003)
                    text.font = UIFont.monospacedDigitSystemFont(ofSize: 1, weight: .bold)
                    text.flatness = 0.006
                    let ink = SCNMaterial()
                    ink.lightingModel = .constant
                    ink.diffuse.contents = UIColor(red: 243 / 255, green: 241 / 255, blue: 236 / 255, alpha: 1)
                    ink.isDoubleSided = true
                    text.materials = [ink]
                    let textNode = SCNNode(geometry: text)
                    let bounds = text.boundingBox
                    textNode.position = SCNVector3(-(bounds.min.x + bounds.max.x) * 0.18,
                                                   -(bounds.min.y + bounds.max.y) * 0.18, 0)
                    textNode.scale = SCNVector3(0.36, 0.36, 0.36)
                    let faceNode = SCNNode()
                    faceNode.simdOrientation = basis
                    faceNode.simdPosition = (a + b + c) / 3 + normal * 0.025
                    faceNode.addChildNode(textNode)
                    labels.addChildNode(faceNode)
                }

                let shell = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                    elements: [SCNGeometryElement(indices: (0..<positions.count).map(UInt16.init),
                                                  primitiveType: .triangles)]
                )
                let enamel = SCNMaterial()
                enamel.lightingModel = .physicallyBased
                enamel.diffuse.contents = UIColor(red: 0.73, green: 0.31, blue: 0.13, alpha: 1)
                enamel.metalness.contents = 0.22
                enamel.roughness.contents = 0.35
                shell.materials = [enamel]
                die.geometry = shell

                // Draw each physical edge once, including on the back of the die.
                let edgeIDs = Set(faces.flatMap { face in
                    [(face[0], face[1]), (face[1], face[2]), (face[2], face[0])].map {
                        min($0.0, $0.1) * vertices.count + max($0.0, $0.1)
                    }
                })
                let edgeIndices: [UInt16] = edgeIDs.sorted().flatMap { id in
                    [UInt16(id / vertices.count), UInt16(id % vertices.count)]
                }
                let wire = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices.map {
                    SCNVector3($0.x, $0.y, $0.z)
                })], elements: [SCNGeometryElement(indices: edgeIndices, primitiveType: .line)])
                let metal = SCNMaterial()
                metal.lightingModel = .constant
                metal.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.46, alpha: 1)
                wire.materials = [metal]
                die.addChildNode(SCNNode(geometry: wire))
                die.addChildNode(labels)
            }

            private static func faceBasis(_ normal: SIMD3<Float>) -> simd_quatf {
                let vertical = SIMD3<Float>(0, 1, 0)
                let fallback = SIMD3<Float>(1, 0, 0)
                let reference = abs(simd_dot(normal, vertical)) > 0.95 ? fallback : vertical
                let up = simd_normalize(reference - normal * simd_dot(reference, normal))
                let right = simd_normalize(simd_cross(up, normal))
                return simd_quatf(simd_float3x3(columns: (right, simd_cross(normal, right), normal)))
            }
        }
    }

    private struct DieOutline: InsettableShape {
        var insetAmount: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let points: [CGPoint] = [
                CGPoint(x: 0.5, y: 0.02), CGPoint(x: 0.91, y: 0.23),
                CGPoint(x: 0.97, y: 0.65), CGPoint(x: 0.5, y: 0.98),
                CGPoint(x: 0.03, y: 0.65), CGPoint(x: 0.09, y: 0.23)
            ]
            let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
            var path = Path()
            for (index, point) in points.enumerated() {
                let position = CGPoint(x: bounds.minX + point.x * bounds.width,
                                       y: bounds.minY + point.y * bounds.height)
                if index == 0 { path.move(to: position) }
                else { path.addLine(to: position) }
            }
            path.closeSubpath()
            return path
        }

        func inset(by amount: CGFloat) -> DieOutline {
            var copy = self
            copy.insetAmount += amount
            return copy
        }
    }

    private struct DieFacets: Shape {
        func path(in rect: CGRect) -> Path {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var path = Path()
            path.move(to: point(0.5, 0.02))
            path.addLine(to: point(0.5, 0.27))
            path.addLine(to: point(0.09, 0.23))
            path.move(to: point(0.5, 0.27))
            path.addLine(to: point(0.91, 0.23))
            path.move(to: point(0.09, 0.23))
            path.addLine(to: point(0.19, 0.7))
            path.addLine(to: point(0.5, 0.98))
            path.move(to: point(0.91, 0.23))
            path.addLine(to: point(0.81, 0.7))
            path.addLine(to: point(0.5, 0.98))
            return path
        }
    }
}
