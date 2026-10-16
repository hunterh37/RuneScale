import Foundation
import QuartzCore
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
    /// Parent of all scene geometry; its local space is scene-local meters (1 tile = 1 m).
    let world = Entity()
    let mode: Mode
    private weak var model: AppModel?
    private static let metersPerUnit: Float = 1 / Coordinates.unitsPerTile

    private var meshes: [Int64: MeshResource] = [:]
    private var transientOrder: [Int64] = []
    private var statics: [Int64: Entity] = [:]
    private var terrain: [Entity] = []
    private var actors: [UInt32: ModelEntity] = [:]
    /// Last FRAME state per actor key, scene-local units, for attack clicks.
    private(set) var actorState: [UInt32: RSProtocol.Actor] = [:]
    private var playerTarget = SIMD3<Float>.zero
    private var hasPlayer = false
    /// Scene-local XZ center per cullable entity (statics and terrain).
    private var cullCenters: [ObjectIdentifier: SIMD2<Float>] = [:]
    private var playerXZ = SIMD2<Float>.zero
    /// Local player height in scene units (OSRS, positive down), for area sounds without a source actor.
    private var playerUnitsY: Float = 0
    private var lastCullTile = SIMD2<Int32>(.max, .max)
    private static let maxTransient = 4000
    /// Device pose in the immersive space origin; room-scale sets it so the own pet trails the viewer.
    var headPose: (() -> simd_float4x4?)?
    private var petFollow: PetFollow.State?
    private var lastFrameTime: Double?

    private lazy var material: RealityKit.Material = Self.makeMaterial()
    /// Hitsplats and HP bars from HITSPLAT/HEALTH, parented to actor entities.
    private let overlays = CombatOverlays()

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
        statics.removeAll(); terrain.removeAll(); actors.removeAll(); overlays.removeAll()
        cullCenters.removeAll(); cullSlack.removeAll(); lastCullTile = .init(.max, .max)
        hasPlayer = false
        petFollow = nil; lastFrameTime = nil
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
                track(e)
                Self.makeTappable(e, exact: res)
            }
        case .staticAdd(let list):
            for inst in list { placeStatic(inst) }
        case .staticRemove(let ids):
            for id in ids { if let e = statics.removeValue(forKey: id) { untrack(e) } }
        case .frame(let f):
            applyFrame(f)
        case .hitsplat(let h):
            overlays.hitsplat(h, on: actors[h.key])
        case .health(let list):
            overlays.health(list, actors: actors)
        case .inputAck, .uiFrame, .container, .itemIcon, .equipModel, .menu, .sound, .music:
            break
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
                // evict oldest mesh not shown by an actor; in-use meshes go to the back
                let inUse = Set(actorState.values.map(\.meshId))
                for _ in 0..<transientOrder.count {
                    let drop = transientOrder.removeFirst()
                    if inUse.contains(drop) { transientOrder.append(drop); continue }
                    meshes.removeValue(forKey: drop)
                    break
                }
            }
        }
    }

    private func placeStatic(_ inst: RSProtocol.Instance) {
        if let old = statics.removeValue(forKey: inst.id) { untrack(old) }
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
        track(e)
        if inst.id < 0 { Self.makeTappable(e, exact: res) } else { Self.makeTappable(e, bounds: res) }
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

        playerXZ = [player.x, player.z]
        playerUnitsY = Float(f.playerY)
        let tile = SIMD2<Int32>(Int32(player.x.rounded(.down)), Int32(player.z.rounded(.down)))
        if tile != lastCullTile { lastCullTile = tile; applyRenderDistance() }

        let now = CACurrentMediaTime()
        let dt = Float(min(0.25, now - (lastFrameTime ?? now)))
        lastFrameTime = now
        if !f.actors.contains(where: { $0.kind == .ownPet }) { petFollow = nil }

        var seen = Set<UInt32>(minimumCapacity: f.actors.count)
        let showLocal = UserDefaults.standard.object(forKey: "showLocalPlayer") as? Bool ?? false
        actorState = Dictionary(f.actors.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for a in f.actors {
            seen.insert(a.key) // keep an actor whose new mesh has not arrived yet
            guard let res = meshes[a.meshId] else {
                if let e = actors[a.key] {
                    let pos = Coordinates.point(x: Float(a.x), y: Float(a.y), z: Float(a.z), metersPerUnit: s)
                    e.move(to: Transform(rotation: simd_quatf(angle: Coordinates.yaw(orientation: a.orientation), axis: [0, 1, 0]), translation: pos), relativeTo: world, duration: 0.08, timingFunction: .linear)
                }
                continue
            }
            var t = Transform(rotation: simd_quatf(angle: Coordinates.yaw(orientation: a.orientation), axis: [0, 1, 0]),
                              translation: Coordinates.point(x: Float(a.x), y: Float(a.y), z: Float(a.z), metersPerUnit: s))
            if a.kind == .ownPet, let follow = followTransform(game: t, dt: dt) { t = follow }
            overlays.place(key: a.key, transform: t, mesh: res, world: world, local: a.kind == .local)
            let visible = a.kind != .local || showLocal
            if let e = actors[a.key] {
                if e.isEnabled != visible { e.isEnabled = visible }
                if e.model?.mesh !== res { e.model?.mesh = res }
                e.move(to: t, relativeTo: world, duration: 0.08, timingFunction: .linear)
            } else {
                let e = ModelEntity(mesh: res, materials: [material])
                e.transform = t
                e.isEnabled = visible
                world.addChild(e)
                actors[a.key] = e
                Self.makeTappable(e, bounds: res)
            }
        }
        for (key, e) in actors where !seen.contains(key) {
            overlays.forget(key)
            e.removeFromParent()
            actors.removeValue(forKey: key)
        }
    }

    /// Room-scale own-pet placement near the headset, in `world` space. Nil keeps the game position.
    private func followTransform(game t: Transform, dt: Float) -> Transform? {
        guard mode == .roomScale, model?.petFollowsMe ?? true, let m = headPose?() else { petFollow = nil; return nil }
        let headW = world.convert(position: SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z), from: nil)
        let fwdW = world.convert(direction: -SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z), from: nil)
        let head = SIMD2(headW.x, headW.z)
        let goal = PetFollow.target(head: head, forward: [fwdW.x, fwdW.z])
        let cur = petFollow ?? PetFollow.State(position: goal, yaw: 0)
        let next = PetFollow.step(cur, goal: goal, head: head, dt: dt)
        petFollow = next
        return Transform(rotation: simd_quatf(angle: next.yaw, axis: [0, 1, 0]),
                         translation: [next.position.x, t.translation.y, next.position.y])
    }

    /// Parent entity and local offset for a game sound: the source actor when known, the scene
    /// point at player height for area sounds, the viewer origin otherwise.
    func soundAnchor(_ snd: RSProtocol.Sound) -> (parent: Entity, offset: SIMD3<Float>) {
        if snd.sourceKey != .max, let e = actors[snd.sourceKey], e.isEnabled || snd.area { return (e, [0, 1.0, 0]) }
        if snd.area {
            let p = Coordinates.point(x: Float(snd.x), y: playerUnitsY, z: Float(snd.z), metersPerUnit: Self.metersPerUnit)
            return (world, p + [0, 1.0, 0])
        }
        return (root, [0, 1.2, 0])
    }

    private var renderRadius: Float { Float(model?.renderDistance ?? 32) } // 1 tile = 1 scene meter

    private func track(_ e: ModelEntity) {
        let b = e.visualBounds(relativeTo: world)
        guard !b.isEmpty else { return }
        let c = SIMD2(b.center.x, b.center.z)
        cullCenters[ObjectIdentifier(e)] = c
        // large entities (terrain chunks) use their half-size as slack
        let slack = max(b.extents.x, b.extents.z) / 2
        e.isEnabled = simd_distance(c, playerXZ) <= renderRadius + slack
        if slack > 0 { cullSlack[ObjectIdentifier(e)] = slack }
    }
    private func untrack(_ e: Entity) {
        cullCenters.removeValue(forKey: ObjectIdentifier(e)); cullSlack.removeValue(forKey: ObjectIdentifier(e))
        e.removeFromParent()
    }
    private var cullSlack: [ObjectIdentifier: Float] = [:]

    func applyRenderDistance() {
        let r = renderRadius
        func update(_ e: Entity) {
            let id = ObjectIdentifier(e)
            guard let c = cullCenters[id] else { return }
            let on = simd_distance(c, playerXZ) <= r + (cullSlack[id] ?? 0)
            if e.isEnabled != on { e.isEnabled = on }
        }
        terrain.forEach(update)
        statics.values.forEach(update)
    }

    func meshResource(_ id: Int64) -> MeshResource? { meshes[id] }
    var paletteMaterial: RealityKit.Material { material }

    /// NPCs as swing targets in world meters (bounds of the rendered actor).
    func npcTargets() -> [GestureTarget] {
        actors.compactMap { key, e in
            guard actorState[key]?.kind == .npc else { return nil }
            let b = e.visualBounds(relativeTo: nil)
            guard !b.isEmpty else { return nil }
            return GestureTarget(key: key, center: b.center, radius: max(0.15, min(b.extents.x, b.extents.z) / 2))
        }
    }

    /// Body-center click point for an actor: tile position raised half a typical model height.
    func clickPoint(actor key: UInt32) -> (x: Int32, y: Int32, z: Int32)? {
        guard let a = actorState[key] else { return nil }
        return (a.x, a.y - 90, a.z) // height is positive downward
    }

    private var clickMarker: Entity?

    /// World-space point to click for a tap. Terrain uses the exact hit; box-collider entities
    /// (actors, objects) use their mesh center, since a point on the box surface floats off the
    /// ground and projects onto a different tile in the game camera. Shows a 3D marker.
    func clickPoint(for e: Entity, hit: SIMD3<Float>) -> SIMD3<Float> {
        let isTerrain = terrain.contains { $0 === e }
        var p = hit
        var ground = hit
        if !isTerrain, let m = (e as? ModelEntity)?.model?.mesh {
            p = e.convert(position: m.bounds.center, to: world)
            ground = e.convert(position: [m.bounds.center.x, m.bounds.min.y, m.bounds.center.z], to: world)
        }
        showClickMarker(at: ground, red: !isTerrain)
        return p
    }

    private func showClickMarker(at p: SIMD3<Float>, red: Bool) {
        clickMarker?.removeFromParent()
        let s = Self.metersPerUnit * Coordinates.unitsPerTile // 1 tile in world units
        var mat = UnlitMaterial(color: red ? .red : .yellow)
        mat.blending = .opaque
        let bar = MeshResource.generateBox(width: s * 0.7, height: s * 0.04, depth: s * 0.1)
        let m = Entity()
        for angle in [Float.pi / 4, -Float.pi / 4] {
            let b = ModelEntity(mesh: bar, materials: [mat])
            b.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            m.addChild(b)
        }
        m.position = p + [0, s * 0.05, 0]
        world.addChild(m)
        clickMarker = m
        Task { @MainActor [weak m, weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let m else { return }
            m.removeFromParent()
            if self?.clickMarker === m { self?.clickMarker = nil }
        }
    }

    /// Box collider from mesh bounds: cheap, used for objects and actors.
    private static func makeTappable(_ e: ModelEntity, bounds res: MeshResource) {
        let b = res.bounds
        guard b.extents.x > 0 || b.extents.y > 0 || b.extents.z > 0 else { return }
        let size = simd_max(b.extents, SIMD3(repeating: 0.05))
        e.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: b.center)], isStatic: true))
        e.components.set(InputTargetComponent())
    }

    /// Exact triangle collider for terrain, built off the main actor.
    private static func makeTappable(_ e: ModelEntity, exact res: MeshResource) {
        e.components.set(InputTargetComponent())
        Task { @MainActor [weak e] in
            guard let shape = try? await ShapeResource.generateStaticMesh(from: res), let e else { return }
            e.components.set(CollisionComponent(shapes: [shape], isStatic: true))
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

    /// Uncompressed, no mips: the palette is a lookup table, and block compression
    /// (the RealityKit default) mixes neighboring texels into wrong face colors.
    private static var paletteOptions: TextureResource.CreateOptions {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "P.compress") == "1" { return .init(semantic: .color) }
        #endif
        return .init(semantic: .color, compression: .none, mipmapsMode: .none)
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
           let tex = try? TextureResource(image: img, options: Self.paletteOptions) {
            let sd = MTLSamplerDescriptor()
            sd.minFilter = .nearest
            sd.magFilter = .nearest
            sd.mipFilter = .notMipmapped
            mat.color = .init(tint: .white, texture: .init(tex, sampler: .init(sd)))
        }
        return mat
    }
}
