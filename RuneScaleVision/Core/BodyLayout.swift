import simd

/// Where worn items sit on the user. Slots follow RuneLite EquipmentInventorySlot indices.
/// Hands come from hand tracking; torso, legs and feet are inferred from the head pose.
public enum EquipSlot: UInt8, Sendable, CaseIterable {
    case head = 0, cape = 1, amulet = 2, weapon = 3, body = 4, shield = 5, legs = 7, gloves = 9, boots = 10, ring = 12, ammo = 13

    public enum Anchor: Sendable, Equatable { case swordHand, offHand, bothHands, body }
    public var anchor: Anchor {
        switch self {
        case .weapon: .swordHand
        case .shield: .offHand
        case .gloves, .ring: .bothHands
        default: .body
        }
    }

    /// Longest model extent after scaling, meters.
    public var targetSize: Float {
        switch self {
        case .weapon: 0.9
        case .shield: 0.55
        case .head: 0.3
        case .body: 0.55
        case .legs: 0.85
        case .cape: 0.9
        case .boots: 0.3
        case .amulet: 0.18
        case .gloves: 0.14
        case .ring: 0.03
        case .ammo: 0.0 // hidden
        }
    }
}

public enum BodyLayout {
    /// Torso yaw follows the head yaw; offsets in the torso frame (x right, y up, z back).
    public static func offset(_ slot: EquipSlot, eyeHeight: Float) -> SIMD3<Float>? {
        switch slot {
        case .head: [0, 0.08, 0.04]
        case .amulet: [0, -0.28, -0.08]
        case .body: [0, -0.48, 0.02]
        case .cape: [0, -0.55, 0.2]
        case .legs: [0, -0.5 - (eyeHeight - 0.5) / 2, 0.02]  // hip to floor midpoint
        case .boots: [0, -eyeHeight + 0.08, -0.02]           // on the floor
        default: nil
        }
    }

    /// World transform of a body slot from the device (head) pose. Head excluded from rendering
    /// by the caller so the helm does not block the view.
    public static func transform(_ slot: EquipSlot, head: simd_float4x4, floorY: Float = 0) -> simd_float4x4? {
        let h = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        guard let o = offset(slot, eyeHeight: max(h.y - floorY, 0.8)) else { return nil }
        var fwd = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        fwd = simd_length(fwd) > 1e-3 ? simd_normalize(fwd) : [0, 0, -1]
        let yaw = atan2(-fwd.x, -fwd.z)
        let r = simd_quatf(angle: yaw, axis: [0, 1, 0])
        var m = simd_float4x4(r)
        m.columns.3 = SIMD4(h + r.act(o), 1)
        return m
    }

    /// Uniform scale that makes the longest extent equal the slot's target size.
    public static func scale(extents: SIMD3<Float>, slot: EquipSlot) -> Float {
        let longest = max(extents.x, extents.y, extents.z)
        return longest > 1e-5 ? slot.targetSize / longest : 0
    }
}
