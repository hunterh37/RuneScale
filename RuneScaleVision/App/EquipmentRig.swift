import ARKit
import QuartzCore
import RealityKit
import RuneScaleCore
import simd

/// Worn items from EQUIP_MODEL on the user: weapon in the sword hand, shield in the off hand,
/// gloves on both hands, helm/amulet/body/cape/legs/boots placed from the head pose.
@MainActor
final class EquipmentRig {
    let root = Entity()
    private var slots: [EquipSlot: Entity] = [:]
    private var gloveCopy: Entity?
    private var meshIds: [EquipSlot: Int64] = [:]

    init() { root.name = "EquipmentRig" }

    var hasWeapon: Bool { slots[.weapon] != nil }
    /// Hide the held weapon (UI toggle).
    var showWeapon = true
    /// Reverse the detected hilt end; the spread heuristic picks the tip on curved blades.
    var flipWeapon = true

    /// Rebuild one slot from the scene mesh cache.
    func set(slot raw: UInt8, meshId: Int64, scene: WorldScene) {
        guard let slot = EquipSlot(rawValue: raw), slot != .ammo else { return }
        guard meshIds[slot] != meshId else { return }
        meshIds[slot] = meshId
        slots.removeValue(forKey: slot)?.removeFromParent()
        if slot == .gloves { gloveCopy?.removeFromParent(); gloveCopy = nil }
        guard meshId != 0, let res = scene.meshResource(meshId) else { return }
        let model = ModelEntity(mesh: res, materials: [scene.paletteMaterial])
        let b = res.bounds
        let s = BodyLayout.scale(extents: b.extents, slot: slot)
        model.scale = .init(repeating: s)
        model.position = -b.center * s
        // body items arrive in icon pose (upright, front toward +z here); turn the front to -z (forward)
        if slot.anchor == .body {
            model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            model.position = -model.orientation.act(b.center * s)
        }
        // weapons: longest axis along the blade (-z of the holder)
        if slot == .weapon {
            // hand holds the hilt: blade (hilt -> tip) along -z, grip ~9% of length in from the pommel
            let axis = Self.longestAxis(b.extents)
            let sign = Self.hiltSign(res, center: b.center, axis: axis) * (flipWeapon ? -1 : 1)
            let half = simd_dot(b.extents, axis) / 2
            model.orientation = simd_quatf(from: axis * -sign, to: [0, 0, -1])
            let gripLocal = b.center + axis * sign * half * 0.82
            model.position = -model.orientation.act(gripLocal * s)
        }
        let holder = Entity()
        holder.addChild(model)
        root.addChild(holder)
        slots[slot] = holder
        if slot == .gloves {
            let c = holder.clone(recursive: true)
            root.addChild(c)
            gloveCopy = c
        }
    }

    /// Per frame from the head pose. The helm is hidden (it would sit over the eyes).
    func updateBody(head: simd_float4x4) {
        for (slot, e) in slots where slot.anchor == .body {
            guard slot != .head, let m = BodyLayout.transform(slot, head: head) else { e.isEnabled = false; continue }
            e.isEnabled = true
            e.transform = Transform(matrix: m)
        }
        slots[.head]?.isEnabled = false
    }

    /// Per hand update from hand tracking.
    func updateHand(_ a: HandAnchor, swordSide: Bool) {
        guard let sk = a.handSkeleton else { return }
        let m = a.originFromAnchorTransform * sk.joint(.middleFingerKnuckle).anchorFromJointTransform
        let p = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let grip = simd_quatf(m)
        if swordSide, let w = slots[.weapon] {
            w.isEnabled = a.isTracked && showWeapon
            SwordModel.attach(w, to: a)
        }
        if !swordSide, let s = slots[.shield] {
            s.isEnabled = a.isTracked
            // shield face outward from the back of the hand
            s.position = p
            s.orientation = grip
        }
        let glove = swordSide ? slots[.gloves] : gloveCopy
        glove?.isEnabled = a.isTracked
        glove?.position = p
        // OSRS models are Y-up; turn the ring axis onto the joint's x (forearm) axis.
        glove?.orientation = grip * simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
    }

    static func longestAxis(_ e: SIMD3<Float>) -> SIMD3<Float> {
        e.x >= e.y && e.x >= e.z ? [1, 0, 0] : e.y >= e.z ? [0, 1, 0] : [0, 0, 1]
    }

    /// +1 when the hilt is at the +axis end. The guard makes the hilt end wider than the
    /// blade near the tip, so compare cross-section spread in the 10-35% bands from each end.
    static func hiltSign(_ res: MeshResource, center: SIMD3<Float>, axis: SIMD3<Float>) -> Float {
        var pts: [SIMD3<Float>] = []
        for m in res.contents.models { for part in m.parts { pts.append(contentsOf: part.positions.elements) } }
        guard pts.count > 8 else { return 1 }
        let ts = pts.map { simd_dot($0 - center, axis) }
        guard let lo = ts.min(), let hi = ts.max(), hi > lo else { return 1 }
        func spread(_ a: Float, _ b: Float) -> Float {
            let band = zip(pts, ts).filter { $0.1 >= a && $0.1 <= b }.map { ($0.0 - center) - axis * $0.1 }
            guard band.count > 1 else { return 0 }
            var mn = band[0], mx = band[0]
            for v in band { mn = simd_min(mn, v); mx = simd_max(mx, v) }
            return simd_length(mx - mn)
        }
        let len = hi - lo
        let low = spread(lo + len * 0.1, lo + len * 0.35)
        let high = spread(hi - len * 0.35, hi - len * 0.1)
        return high > low ? 1 : -1
    }

    static func alignLongest(_ e: SIMD3<Float>, to dir: SIMD3<Float>) -> simd_quatf {
        let axis: SIMD3<Float> = e.x >= e.y && e.x >= e.z ? [1, 0, 0] : e.y >= e.z ? [0, 1, 0] : [0, 0, 1]
        return simd_quatf(from: axis, to: dir)
    }
}
