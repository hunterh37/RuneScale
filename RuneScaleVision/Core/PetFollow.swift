import simd

/// Life-size follower placement: the own pet trails the viewer's headset on the floor plane.
/// Units are scene-local meters (1 tile = 1 m), XZ only.
public enum PetFollow {
    public struct State: Sendable, Equatable {
        public var position: SIMD2<Float>
        public var yaw: Float
        public init(position: SIMD2<Float>, yaw: Float) { self.position = position; self.yaw = yaw }
    }

    /// Spot behind and to the right of the viewer. `forward` need not be normalized.
    public static func target(head: SIMD2<Float>, forward: SIMD2<Float>, distance: Float = 0.9, side: Float = 0.45) -> SIMD2<Float> {
        let len = simd_length(forward)
        let f = len > 1e-4 ? forward / len : SIMD2<Float>(0, -1)
        let right = SIMD2<Float>(-f.y, f.x)
        return head - f * distance + right * side
    }

    /// One step toward `goal`. Stays put inside `deadZone`; speed scales with distance up to
    /// `maxSpeed` m/s; snaps when farther than `teleport`. Yaw faces the motion, or the viewer when idle.
    public static func step(_ s: State, goal: SIMD2<Float>, head: SIMD2<Float>, dt: Float,
                            deadZone: Float = 0.35, maxSpeed: Float = 3, teleport: Float = 6) -> State {
        let d = goal - s.position
        let dist = simd_length(d)
        if dist > teleport { return State(position: goal, yaw: yawFacing(head - goal, fallback: s.yaw)) }
        if dist <= deadZone { return State(position: s.position, yaw: yawFacing(head - s.position, fallback: s.yaw)) }
        let speed = min(maxSpeed, dist * 2.5)
        let move = min(dist - deadZone * 0.5, speed * max(0, dt))
        let p = s.position + d / dist * move
        return State(position: p, yaw: yawFacing(d, fallback: s.yaw))
    }

    /// RealityKit yaw about +Y that turns a model at orientation 0 (OSRS south, +Z) toward `dir`.
    public static func yawFacing(_ dir: SIMD2<Float>, fallback: Float) -> Float {
        guard simd_length(dir) > 1e-4 else { return fallback }
        return atan2(dir.x, dir.y)
    }
}
