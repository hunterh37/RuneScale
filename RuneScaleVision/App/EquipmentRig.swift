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
        // weapons: longest axis along the blade (-z of the holder)
        if slot == .weapon { model.orientation = Self.alignLongest(b.extents, to: [0, 0, -1]); model.position = model.orientation.act(model.position) }
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
            w.isEnabled = a.isTracked
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
        glove?.orientation = grip
    }

    static func alignLongest(_ e: SIMD3<Float>, to dir: SIMD3<Float>) -> simd_quatf {
        let axis: SIMD3<Float> = e.x >= e.y && e.x >= e.z ? [1, 0, 0] : e.y >= e.z ? [0, 1, 0] : [0, 0, 1]
        return simd_quatf(from: axis, to: dir)
    }
}
