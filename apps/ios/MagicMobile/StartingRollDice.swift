import Foundation
import simd

// The starting roll's dice, as pure data and maths (no SceneKit, no UIKit), so the landing rule can be
// tested without the app: the die model's faces, the recorded throws, the symmetry that lets one throw
// end on any number, and where the table's camera and lanes go. docs/STARTING_ROLL.md has the picture.
// The same logic is ported to Android in ondevice/StartingRollDice.kt; keep them in step.

// MARK: - Model

/// d20.json: what each face of the die is called, where it points and which way its numeral reads.
struct D20Model: Decodable, Equatable {
    struct Face: Decodable, Equatable {
        let index: Int
        let number: Int
        let normal: [Float]
        let cornerDirections: [[Float]]

        var normalVector: SIMD3<Float> { SIMD3(normal[0], normal[1], normal[2]) }
        func corner(_ k: Int) -> SIMD3<Float> {
            let c = cornerDirections[k % cornerDirections.count]
            return SIMD3(c[0], c[1], c[2])
        }
    }

    let circumradius: Float
    let inradius: Float
    let faces: [Face]
    let vertices: [[Float]]

    func face(numbered number: Int) -> Face? { faces.first { $0.number == number } }
}

/// d20-throws.json: recorded tumbles along the table, each ending with some face up.
struct D20ThrowBank: Decodable, Equatable {
    struct Throw: Decodable, Equatable {
        let frames: Int
        let faceUp: Int
        let position: [Float]
        let orientation: [Float]
        let railTime: Float
        let tableHits: [[Float]]

        var duration: Float { Float(frames - 1) / 60 }
        func position(at frame: Int) -> SIMD3<Float> {
            let i = min(max(frame, 0), frames - 1) * 3
            return SIMD3(position[i], position[i + 1], position[i + 2])
        }
        func orientation(at frame: Int) -> simd_quatf {
            let i = min(max(frame, 0), frames - 1) * 4
            return simd_quatf(ix: orientation[i], iy: orientation[i + 1], iz: orientation[i + 2], r: orientation[i + 3])
        }
    }

    let fps: Int
    let recordings: [Throw]

    // `throws` is a keyword, so the JSON key is renamed here.
    private enum CodingKeys: String, CodingKey {
        case fps
        case recordings = "throws"
    }
}

// MARK: - Landing a throw on a chosen number

/// One die's throw, re-labelled so the recorded path ends with `number` on top.
///
/// A regular icosahedron looks the same after any of its 60 rotations. The recording ends with face F up;
/// to make it end with face T up, the body is turned by the symmetry S that carries T onto F before the
/// recorded motion is applied: world orientation = recorded orientation * S. Nothing about the motion
/// changes, only which numeral sits on which face. Three symmetries carry T onto F (they differ by a
/// third of a turn about the face); the one that leaves the numeral reading closest to upright is used,
/// and the last stretch of the throw turns the die the rest of the way, as a die skids to a stop.
struct D20ThrowPlan {
    let model: D20Model
    let recorded: D20ThrowBank.Throw
    let number: Int
    /// The three symmetries' choice and the end yaw (radians about world up) added over the settle.
    let corner: Int
    let endYaw: Float
    let symmetry: simd_quatf
    /// Where the lane puts the die, and how far the path is stretched toward the rail (1 = as recorded).
    let origin: SIMD3<Float>
    let footprint: Float

    /// `upright` is the direction the numeral should read toward, in world space (horizontal): far from the viewer.
    init(model: D20Model, recorded: D20ThrowBank.Throw, number: Int, origin: SIMD3<Float> = .zero,
         footprint: Float = 1, upright: SIMD3<Float> = SIMD3(0, 0, -1), jitter: Float = 0) {
        self.model = model
        self.recorded = recorded
        self.number = number
        self.origin = origin
        self.footprint = footprint
        let target = model.face(numbered: number) ?? model.faces[0]
        let resting = model.faces[recorded.faceUp]
        let finish = recorded.orientation(at: recorded.frames - 1)
        var best: (corner: Int, yaw: Float, symmetry: simd_quatf)?
        for k in 0..<3 {
            let s = D20Landing.symmetry(model: model, from: target, to: resting, corner: k)
            // Where the numeral on the top face will point in the world, flattened onto the table.
            var up = finish.act(s.act(target.corner(0)))
            up.y = 0
            let yaw = D20Landing.yaw(from: up, to: upright)
            if best == nil || abs(yaw) < abs(best!.yaw) { best = (k, yaw, s) }
        }
        corner = best!.corner
        endYaw = best!.yaw + jitter
        symmetry = best!.symmetry
    }

    var duration: Float { recorded.duration }
    var restPose: D20Pose { pose(at: duration) }

    /// The die's pose `time` seconds into the throw (held at its resting pose afterwards).
    func pose(at time: Float) -> D20Pose {
        let clamped = min(max(time, 0), duration)
        let exact = clamped * 60
        let i = Int(exact.rounded(.down))
        let f = exact - Float(i)
        let p0 = recorded.position(at: i), p1 = recorded.position(at: i + 1)
        let q0 = recorded.orientation(at: i), q1 = recorded.orientation(at: i + 1)
        let p = p0 + (p1 - p0) * f
        let q = simd_slerp(q0, simd_dot(q0, q1) < 0 ? simd_quatf(vector: -q1.vector) : q1, f)
        // The extra yaw comes in over the last stretch, after the final hard bounce.
        let settleStart = max(recorded.railTime + 0.3, duration - 0.75)
        let t = min(max((clamped - settleStart) / max(duration - settleStart, 0.001), 0), 1)
        let eased = t * t * (3 - 2 * t)
        let yaw = simd_quatf(angle: endYaw * eased, axis: SIMD3(0, 1, 0))
        let position = SIMD3(origin.x + p.x * footprint, p.y, origin.z + p.z * footprint)
        return D20Pose(position: position, orientation: simd_normalize(yaw * q * symmetry))
    }

    /// When the die first lands on the rail, in seconds.
    var railTime: Float { recorded.railTime }
}

struct D20Pose: Equatable {
    var position: SIMD3<Float>
    var orientation: simd_quatf
}

enum D20Landing {
    /// The rotation (in the die's own frame) that turns face `target` into face `resting`, with the
    /// numeral's corner 0 on `target` landing on `resting`'s corner `k`.
    static func symmetry(model: D20Model, from target: D20Model.Face, to resting: D20Model.Face, corner k: Int) -> simd_quatf {
        func frame(_ normal: SIMD3<Float>, _ corner: SIMD3<Float>) -> simd_float3x3 {
            let n = simd_normalize(normal)
            let u = simd_normalize(corner - n * simd_dot(corner, n))
            return simd_float3x3(columns: (n, u, simd_cross(n, u)))
        }
        let a = frame(target.normalVector, target.corner(0))
        let b = frame(resting.normalVector, resting.corner(k))
        return simd_quatf(b * a.transpose)
    }

    /// The turn about +y that carries one horizontal direction onto another, in -pi...pi. A turn of t about +y
    /// takes the heading atan2(x, z) to heading + t.
    static func yaw(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Float {
        var turn = atan2(b.x, b.z) - atan2(a.x, a.z)
        while turn > .pi { turn -= 2 * .pi }
        while turn <= -.pi { turn += 2 * .pi }
        return turn
    }

    /// A throw for a seat's roll, spread so neighbours look different: the roll round and the seat pick it.
    static func throwIndex(round: Int, seatIndex: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (round * 5 + seatIndex * 3 + (round > 0 ? 1 : 0)) % count
    }

    /// A small deterministic offset in -range...range for a seat's roll, so the numerals do not all stand to attention.
    static func jitter(round: Int, seatIndex: Int, range: Float) -> Float {
        let h = UInt32(truncatingIfNeeded: (round &* 7919) &+ (seatIndex &* 104729) &+ 17)
        let unit = Float((h &* 2654435761) >> 16 & 0xFFFF) / 65535
        return (unit * 2 - 1) * range
    }
}

// MARK: - The table's camera and lanes

/// Where the camera sits, where each seat's lane runs and how far the throws travel, for one stage.
/// All in the die's units (circumradius 1) on the table plane at y = 0, +z toward the viewer.
struct D20TableLayout: Equatable {
    struct Input: Equatable {
        /// The stage in points, and the part of it the dice may use (where the roll area is).
        var size: CGSize
        var region: CGRect
        var seatCount: Int
        var matSize: SIMD2<Float>
    }

    static let verticalFieldOfView: Float = 40 * .pi / 180
    /// The ray through the middle of the roll area meets the table this far from straight down.
    static let tilt: Float = 18 * .pi / 180
    /// How far from the rail the throw starts and how far its resting places spread (die radii).
    static let throwDepth: Float = 8.2

    let laneX: [Float]
    let railZ: Float
    let footprint: Float
    /// Points per die radius at the middle of the roll area.
    let pointsPerUnit: Float
    let cameraPosition: SIMD3<Float>
    /// The direction the camera looks (unit), tilted down toward the table.
    let cameraForward: SIMD3<Float>
    let verticalFieldOfView = D20TableLayout.verticalFieldOfView

    init(_ input: Input) {
        let count = max(1, input.seatCount)
        let width = Float(max(input.region.width, 1)), height = Float(max(input.region.height, 1))
        let spacing: Float = count <= 2 ? 3.1 : 2.45
        // Dice as big as the width allows, but never so big the throw cannot fit the height.
        let byWidth = width / (spacing * Float(count) + 1.4)
        let minFootprint: Float = 0.5
        let byHeight = height / ((Self.throwDepth + 1.6) * minFootprint)
        let ppu = min(min(byWidth, byHeight), 58)
        let footprint = min(1, max(minFootprint, height / ((Self.throwDepth + 1.6) * ppu)))
        pointsPerUnit = ppu
        self.footprint = footprint
        laneX = (0..<count).map { (Float($0) - Float(count - 1) / 2) * spacing }
        railZ = -input.matSize.y / 2
        // The ray through the middle of the roll area meets the table at the point halfway down the throw.
        let span = Self.throwDepth * footprint
        let target = SIMD3<Float>(0, 0, railZ + span / 2 + 0.2)
        let stageHeight = Float(input.size.height)
        let fPx = stageHeight / 2 / tan(Self.verticalFieldOfView / 2)
        // The roll area need not sit in the middle of the stage: the camera's axis is turned by the angle
        // between the stage's middle and the roll area's, so the same ray lands on the area's middle.
        let beta = atan((Float(input.region.midY) - stageHeight / 2) / fPx)
        let rayPitch = Float.pi / 2 - Self.tilt
        let distance = fPx / (ppu * cos(beta))
        let h = distance * sin(rayPitch)
        cameraPosition = target + SIMD3(0, h, h / tan(rayPitch))
        let axisPitch = rayPitch - beta
        cameraForward = SIMD3(0, -sin(axisPitch), -cos(axisPitch))
    }
}

// MARK: - glTF binary (just what the dice and tables use)

/// A decoded .glb: one mesh primitive's vertex data, its textures and a few material flags. The die and the
/// tables are written by scripts/brand/d20.py; this reads exactly that, no more.
struct D20GLB {
    struct Material: Equatable {
        var baseColorTexture: Int?
        var normalTexture: Int?
        var metallicRoughnessTexture: Int?
        var unlit = false
        var blend = false
    }

    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let tangents: [SIMD4<Float>]
    let indices: [UInt32]
    let images: [Data]
    let material: Material

    enum LoadError: Error { case malformed(String) }

    init(data: Data) throws {
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
        }
        guard data.count > 28, u32(0) == 0x46546C67, u32(4) == 2 else { throw LoadError.malformed("not a glb") }
        let jsonLength = Int(u32(12))
        guard u32(16) == 0x4E4F534A, data.count >= 20 + jsonLength + 8 else { throw LoadError.malformed("no json chunk") }
        let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + jsonLength))) as? [String: Any] ?? [:]
        let binStart = 20 + jsonLength + 8
        guard u32(20 + jsonLength + 4) == 0x004E4942 else { throw LoadError.malformed("no binary chunk") }
        let bin = data.subdata(in: binStart..<min(data.count, binStart + Int(u32(20 + jsonLength))))

        let views = json["bufferViews"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        func bytes(of accessor: Int) throws -> (Data, Int) {
            guard accessors.indices.contains(accessor), let view = accessors[accessor]["bufferView"] as? Int,
                  views.indices.contains(view), let count = accessors[accessor]["count"] as? Int else {
                throw LoadError.malformed("accessor \(accessor)")
            }
            let offset = (views[view]["byteOffset"] as? Int ?? 0) + (accessors[accessor]["byteOffset"] as? Int ?? 0)
            let length = views[view]["byteLength"] as? Int ?? 0
            guard offset + length <= bin.count else { throw LoadError.malformed("buffer overrun") }
            return (bin.subdata(in: offset..<(offset + length)), count)
        }
        func floats(_ accessor: Int, _ width: Int) throws -> [Float] {
            let (raw, count) = try bytes(of: accessor)
            guard raw.count >= count * width * 4 else { throw LoadError.malformed("short accessor") }
            return raw.withUnsafeBytes { buffer in
                (0..<(count * width)).map { Float(bitPattern: buffer.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self).littleEndian) }
            }
        }
        guard let meshes = json["meshes"] as? [[String: Any]], let primitive = (meshes.first?["primitives"] as? [[String: Any]])?.first,
              let attributes = primitive["attributes"] as? [String: Int], let indexAccessor = primitive["indices"] as? Int,
              let position = attributes["POSITION"] else { throw LoadError.malformed("no mesh") }
        let p = try floats(position, 3), n = try attributes["NORMAL"].map { try floats($0, 3) } ?? [], t = try attributes["TEXCOORD_0"].map { try floats($0, 2) } ?? []
        let tan = try attributes["TANGENT"].map { try floats($0, 4) } ?? []
        positions = stride(from: 0, to: p.count, by: 3).map { SIMD3(p[$0], p[$0 + 1], p[$0 + 2]) }
        normals = stride(from: 0, to: n.count, by: 3).map { SIMD3(n[$0], n[$0 + 1], n[$0 + 2]) }
        uvs = stride(from: 0, to: t.count, by: 2).map { SIMD2(t[$0], t[$0 + 1]) }
        tangents = stride(from: 0, to: tan.count, by: 4).map { SIMD4(tan[$0], tan[$0 + 1], tan[$0 + 2], tan[$0 + 3]) }
        let (rawIndices, indexCount) = try bytes(of: indexAccessor)
        let componentType = accessors[indexAccessor]["componentType"] as? Int ?? 5125
        indices = rawIndices.withUnsafeBytes { buffer in
            (0..<indexCount).map { i in
                componentType == 5123
                    ? UInt32(buffer.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self).littleEndian)
                    : buffer.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self).littleEndian
            }
        }

        let imageList = json["images"] as? [[String: Any]] ?? []
        images = imageList.compactMap { entry in
            guard let view = entry["bufferView"] as? Int, views.indices.contains(view) else { return nil }
            let offset = views[view]["byteOffset"] as? Int ?? 0
            let length = views[view]["byteLength"] as? Int ?? 0
            guard offset + length <= bin.count else { return nil }
            return bin.subdata(in: offset..<(offset + length))
        }
        let textures = json["textures"] as? [[String: Any]] ?? []
        func source(_ info: Any?) -> Int? {
            guard let index = (info as? [String: Any])?["index"] as? Int, textures.indices.contains(index) else { return nil }
            return textures[index]["source"] as? Int
        }
        var material = Material()
        if let materials = json["materials"] as? [[String: Any]], let first = materials.first {
            let pbr = first["pbrMetallicRoughness"] as? [String: Any]
            material.baseColorTexture = source(pbr?["baseColorTexture"])
            material.metallicRoughnessTexture = source(pbr?["metallicRoughnessTexture"])
            material.normalTexture = source(first["normalTexture"])
            material.unlit = (first["extensions"] as? [String: Any])?["KHR_materials_unlit"] != nil
            material.blend = first["alphaMode"] as? String == "BLEND"
        }
        self.material = material
    }
}
