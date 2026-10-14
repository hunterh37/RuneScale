import Foundation
import simd

/// One hand's joints for one frame, in world meters (y up).
public struct HandSample: Sendable {
    public var time: TimeInterval
    public var wrist: SIMD3<Float>
    public var palm: SIMD3<Float>          // middle finger knuckle
    public var thumbTip: SIMD3<Float>
    public var indexTip: SIMD3<Float>
    public var middleTip: SIMD3<Float>
    public var ringTip: SIMD3<Float>
    public var littleTip: SIMD3<Float>

    public init(time: TimeInterval, wrist: SIMD3<Float>, palm: SIMD3<Float>, thumbTip: SIMD3<Float>,
                indexTip: SIMD3<Float>, middleTip: SIMD3<Float>, ringTip: SIMD3<Float>, littleTip: SIMD3<Float>) {
        self.time = time; self.wrist = wrist; self.palm = palm; self.thumbTip = thumbTip
        self.indexTip = indexTip; self.middleTip = middleTip; self.ringTip = ringTip; self.littleTip = littleTip
    }

    public var pinchDistance: Float { simd_distance(thumbTip, indexTip) }
    /// Mean distance from the four fingertips to the palm.
    public var curl: Float {
        (simd_distance(indexTip, palm) + simd_distance(middleTip, palm)
         + simd_distance(ringTip, palm) + simd_distance(littleTip, palm)) / 4
    }
    public var pinchPoint: SIMD3<Float> { (thumbTip + indexTip) / 2 }
}

public enum GestureEvent: Sendable, Equatable {
    case pinchBegan(SIMD3<Float>)
    case pinchEnded(SIMD3<Float>)
    case grabBegan(SIMD3<Float>)
    case grabEnded(SIMD3<Float>)
    /// Fast wrist arc. `from`/`to` bound the fast segment; `velocity` is peak m/s vector.
    case swing(from: SIMD3<Float>, to: SIMD3<Float>, velocity: SIMD3<Float>)
}

/// Per-hand recognizer. Feed one sample per frame; each call returns zero or more events.
/// Thresholds use hysteresis so a held pose emits one began and one ended.
public struct GestureRecognizer: Sendable {
    public struct Config: Sendable {
        public var pinchOn: Float = 0.015, pinchOff: Float = 0.03
        public var grabOn: Float = 0.055, grabOff: Float = 0.08
        public var swingSpeed: Float = 1.5        // m/s to start a swing
        public var swingEndSpeed: Float = 0.8     // m/s to finish it
        public var swingMinLength: Float = 0.25   // m of travel
        public var swingCooldown: TimeInterval = 0.4
        public init() {}
    }

    public var config: Config
    public private(set) var pinching = false
    public private(set) var grabbing = false
    private var last: HandSample?
    private var swingStart: SIMD3<Float>?
    private var swingPeak = SIMD3<Float>.zero
    private var lastSwingEnd: TimeInterval = -.infinity
    private var smoothedVelocity = SIMD3<Float>.zero

    public init(config: Config = Config()) { self.config = config }

    /// Tracking lost: close any open gesture.
    public mutating func lost() -> [GestureEvent] {
        var out = [GestureEvent]()
        if let l = last {
            if pinching { out.append(.pinchEnded(l.pinchPoint)) }
            if grabbing { out.append(.grabEnded(l.palm)) }
        }
        pinching = false; grabbing = false; swingStart = nil; last = nil
        smoothedVelocity = .zero
        return out
    }

    public mutating func update(_ s: HandSample) -> [GestureEvent] {
        var out = [GestureEvent]()

        // grab first: a fist also closes thumb to index, which must not read as a pinch
        let curl = s.curl
        if !grabbing && curl < config.grabOn {
            grabbing = true
            if pinching { pinching = false; out.append(.pinchEnded(s.pinchPoint)) }
            out.append(.grabBegan(s.palm))
        } else if grabbing && curl > config.grabOff {
            grabbing = false
            out.append(.grabEnded(s.palm))
        }

        if !grabbing {
            let d = s.pinchDistance
            if !pinching && d < config.pinchOn {
                pinching = true
                out.append(.pinchBegan(s.pinchPoint))
            } else if pinching && d > config.pinchOff {
                pinching = false
                out.append(.pinchEnded(s.pinchPoint))
            }
        }

        if let l = last, s.time > l.time {
            let v = (s.wrist - l.wrist) / Float(s.time - l.time)
            smoothedVelocity = smoothedVelocity * 0.5 + v * 0.5
            let speed = simd_length(smoothedVelocity)
            if let start = swingStart {
                if speed > simd_length(swingPeak) { swingPeak = smoothedVelocity }
                if speed < config.swingEndSpeed {
                    if simd_distance(start, s.wrist) >= config.swingMinLength {
                        out.append(.swing(from: start, to: s.wrist, velocity: swingPeak))
                        lastSwingEnd = s.time
                    }
                    swingStart = nil
                }
            } else if speed > config.swingSpeed && s.time - lastSwingEnd > config.swingCooldown {
                swingStart = l.wrist
                swingPeak = smoothedVelocity
            }
        }
        last = s
        return out
    }
}

/// What a gesture asks the game to do. Each intent is exactly one click.
public enum GestureIntent: Sendable, Equatable {
    case attack(actorKey: UInt32)
    case openBackpack
    case none
}

public struct GestureTarget: Sendable {
    public var key: UInt32
    public var center: SIMD3<Float>   // world meters
    public var radius: Float
    public init(key: UInt32, center: SIMD3<Float>, radius: Float) {
        self.key = key; self.center = center; self.radius = radius
    }
}

public enum IntentMapper {
    /// Weapon reach past the wrist (sword length).
    public static let reach: Float = 0.6
    /// Swing pick: NPC hit by the blade path, else nearest NPC within 25 degrees of the swing
    /// direction and 3 m. Returns one attack or none.
    public static func swing(from: SIMD3<Float>, to: SIMD3<Float>, velocity: SIMD3<Float>,
                             targets: [GestureTarget], aimCone: Float = 25, maxRange: Float = 3) -> GestureIntent {
        let dir = simd_length(velocity) > 1e-4 ? simd_normalize(velocity) : simd_normalize(to - from)
        let a = from, b = to + dir * reach
        var best: (UInt32, Float)?
        for t in targets {
            let d = distance(point: t.center, segmentA: a, segmentB: b) - t.radius
            if d <= 0.15, d < (best?.1 ?? .infinity) { best = (t.key, d) }
        }
        if let best { return .attack(actorKey: best.0) }
        let cosMax = cos(aimCone * .pi / 180)
        var aimed: (UInt32, Float)?
        for t in targets {
            let v = t.center - to
            let dist = simd_length(v)
            guard dist > 1e-3, dist <= maxRange else { continue }
            let c = simd_dot(v / dist, dir)
            if c >= cosMax, c > (aimed?.1 ?? -1) { aimed = (t.key, c) }
        }
        if let aimed { return .attack(actorKey: aimed.0) }
        return .none
    }

    /// Over-the-shoulder reach: hand above shoulder height and behind the head plane.
    public static func isBackpackReach(hand: SIMD3<Float>, head: simd_float4x4) -> Bool {
        let h = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        var fwd = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        guard simd_length(fwd) > 1e-3 else { return false }
        fwd = simd_normalize(fwd)
        let rel = hand - h
        return rel.y > -0.25 && simd_dot(rel, fwd) < -0.02
    }

    static func distance(point p: SIMD3<Float>, segmentA a: SIMD3<Float>, segmentB b: SIMD3<Float>) -> Float {
        let ab = b - a
        let len2 = simd_length_squared(ab)
        guard len2 > 1e-8 else { return simd_distance(p, a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / len2))
        return simd_distance(p, a + ab * t)
    }
}
