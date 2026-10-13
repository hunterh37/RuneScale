import Foundation
import Metal
import RealityKit
import RuneScaleCore
import CoreGraphics

/// Turns protocol messages into RealityKit entities. Geometry is built at 1 tile = 1 m;
/// `root.scale` applies the life-size or tabletop factor.
@MainActor
final class WorldScene {
    enum Mode { case roomScale, tabletop }

    let root = Entity()
    private let world = Entity()
    private let mode: Mode
    private weak var model: AppModel?
    private static let metersPerUnit: Float = 1 / Coordinates.unitsPerTile

    private var meshes: [Int64: MeshResource] = [:]
    private var transientOrder: [Int64] = []
    private var statics: [Int64: Entity] = [:]
    private var terrain: [Entity] = []
    private var actors: [UInt32: ModelEntity] = [:]
    private var playerTarget = SIMD3<Float>.zero
    private var hasPlayer = false
    private static let maxTransient = 800

    private lazy var material: RealityKit.Material = Self.makeMaterial()

    init(mode: Mode, model: AppModel) {
        self.mode = mode
        self.model = model
        root.name = "RuneScaleRoot"
        root.addChild(world)
        applyScale()
    }

    func applyScale() {
        switch mode {
        case .roomScale:
            root.scale = .init(repeating: Float(model?.lifeSize ?? 1))
        case .tabletop:
            root.scale = .init(repeating: 0.02) // 48 tiles across ~1 m volume
            root.position = [0, -0.28, 0]
        }
    }

    func clear() {
        world.children.removeAll()
        meshes.removeAll(); transientOrder.removeAll()
        statics.removeAll(); terrain.removeAll(); actors.removeAll()
        hasPlayer = false
    }

    func apply(_ msg: RSProtocol.Message) {
        switch msg {
        case .hello:
            clear()
        case .reset:
            clear()
        case .mesh(let m):
            addMesh(m)
        case .terrain(let tiles):
            let g = GeometryBuilder.build(tiles: tiles, metersPerUnit: Self.metersPerUnit)
            if let res = resource(g) {
                let e = ModelEntity(mesh: res, materials: [material])
                world.addChild(e)
                terrain.append(e)
            }
        case .staticAdd(let list):
            for inst in list { placeStatic(inst) }
        case .staticRemove(let ids):
            for id in ids { statics.removeValue(forKey: id)?.removeFromParent() }
        case .frame(let f):
            applyFrame(f)
        }
    }

    private func addMesh(_ m: RSProtocol.Mesh) {
        guard meshes[m.id] == nil else { return }
        let g = GeometryBuilder.build(mesh: m, metersPerUnit: Self.metersPerUnit)
        guard let res = resource(g) else { return }
        meshes[m.id] = res
        if m.transient {
            transientOrder.append(m.id)
            if transientOrder.count > Self.maxTransient {
                let drop = transientOrder.removeFirst()
                meshes.removeValue(forKey: drop)
            }
        }
    }

    private func placeStatic(_ inst: RSProtocol.Instance) {
        statics.removeValue(forKey: inst.id)?.removeFromParent()
        guard let res = meshes[inst.meshId] else { return }
        let e = ModelEntity(mesh: res, materials: [material])
        if inst.id < 0 {
            e.position = .zero // terrain tile models carry scene-local vertices
        } else {
            e.position = Coordinates.point(x: Float(inst.x), y: Float(inst.y), z: Float(inst.z), metersPerUnit: Self.metersPerUnit)
            e.orientation = simd_quatf(angle: Coordinates.yaw(orientation: inst.orientation), axis: [0, 1, 0])
        }
        world.addChild(e)
        statics[inst.id] = e
    }

    private func applyFrame(_ f: RSProtocol.Frame) {
        let s = Self.metersPerUnit
        let player = Coordinates.point(x: Float(f.playerX), y: Float(f.playerY), z: Float(f.playerZ), metersPerUnit: s)
        // keep the local player at the origin with the tile surface on the floor
        let target = Transform(translation: -player)
        if hasPlayer {
            world.move(to: target, relativeTo: root, duration: 0.08, timingFunction: .linear)
        } else {
            world.transform = target
            hasPlayer = true
        }

        var seen = Set<UInt32>()
        for a in f.actors {
            guard let res = meshes[a.meshId] else { continue }
            seen.insert(a.key)
            let pos = Coordinates.point(x: Float(a.x), y: Float(a.y), z: Float(a.z), metersPerUnit: s)
            let t = Transform(rotation: simd_quatf(angle: Coordinates.yaw(orientation: a.orientation), axis: [0, 1, 0]), translation: pos)
            if let e = actors[a.key] {
                if e.model?.mesh !== res { e.model?.mesh = res }
                e.move(to: t, relativeTo: world, duration: 0.08, timingFunction: .linear)
            } else {
                let e = ModelEntity(mesh: res, materials: [material])
                e.transform = t
                world.addChild(e)
                actors[a.key] = e
            }
        }
        for (key, e) in actors where !seen.contains(key) {
            e.removeFromParent()
            actors.removeValue(forKey: key)
        }
    }

    private func resource(_ g: Geometry) -> MeshResource? {
        guard !g.isEmpty else { return nil }
        var d = MeshDescriptor(name: "rs")
        d.positions = MeshBuffers.Positions(g.positions)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(g.uvs)
        d.primitives = .triangles(g.indices)
        return try? MeshResource.generate(from: [d])
    }

    private static func makeMaterial() -> RealityKit.Material {
        var mat = UnlitMaterial()
        mat.faceCulling = .none
        let n = Palette.size
        let bytes = Palette.rgbaBytes()
        let cs = CGColorSpaceCreateDeviceRGB()
        if let provider = CGDataProvider(data: Data(bytes) as CFData),
           let img = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: cs,
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                             decode: nil, shouldInterpolate: false, intent: .defaultIntent),
           let tex = try? TextureResource(image: img, options: .init(semantic: .color)) {
            let sd = MTLSamplerDescriptor()
            sd.minFilter = .nearest
            sd.magFilter = .nearest
            sd.mipFilter = .notMipmapped
            mat.color = .init(tint: .white, texture: .init(tex, sampler: .init(sd)))
        }
        return mat
    }
}
