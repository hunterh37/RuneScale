import ARKit
import QuartzCore
import RealityKit
import RuneScaleCore
import simd

/// Hand tracking to game clicks. Sword hand: swing = one Attack click on the NPC it hits or aims at.
/// Either hand: reach over the shoulder and make a fist = open the backpack at that hand.
/// Every gesture produces at most one click; the game decides the outcome.
@MainActor
final class HandInput {
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private var left = GestureRecognizer()
    private var right = GestureRecognizer()

    func stop() { session.stop() }

    func run(model: AppModel, scene: @escaping () -> WorldScene?, head: @escaping () -> simd_float4x4?,
             sword: @escaping () -> Entity?, backpack: @escaping () -> Entity?, rig: EquipmentRig) async {
        guard HandTrackingProvider.isSupported else {
            model.lastGesture = "Hand tracking not supported; tap to click"
            return
        }
        let auth = await session.requestAuthorization(for: [.handTracking])
        guard auth[.handTracking] == .allowed else {
            model.lastGesture = "Hand tracking denied; tap to click"
            return
        }
        do { try await session.run([provider]) } catch {
            model.lastGesture = "Hand tracking failed: \(error.localizedDescription)"
            return
        }
        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            let isRight = anchor.chirality == .right
            let swordSide = (model.swordHand == "right") == isRight
            // placeholder blade only while no weapon model is worn
            if swordSide { sword()?.isEnabled = anchor.isTracked && !rig.hasWeapon && rig.showWeapon }
            rig.updateHand(anchor, swordSide: swordSide)
            if let h = head() { rig.updateBody(head: h) }

            guard anchor.isTracked, let s = Self.sample(anchor) else {
                _ = isRight ? right.lost() : left.lost()
                continue
            }
            if swordSide, !rig.hasWeapon, let blade = sword() { SwordModel.attach(blade, to: anchor) }
            let events = isRight ? right.update(s) : left.update(s)
            for e in events { handle(e, swordSide: swordSide, model: model, scene: scene(), head: head(), backpack: backpack()) }
        }
    }

    private func handle(_ e: GestureEvent, swordSide: Bool, model: AppModel, scene: WorldScene?, head: simd_float4x4?, backpack: Entity?) {
        switch e {
        case .swing(let from, let to, let v):
            guard swordSide, let scene else { return }
            let intent = IntentMapper.swing(from: from, to: to, velocity: v, targets: scene.npcTargets())
            if case .attack(let key) = intent, let p = scene.clickPoint(actor: key) {
                model.click(p, button: .left)
                model.lastGesture = "Swing: attack NPC \(key)"
            } else {
                model.lastGesture = "Swing: no NPC in reach"
            }
        case .grabBegan(let palm):
            guard let head, IntentMapper.isBackpackReach(hand: palm, head: head), let backpack else { return }
            // panel 0.45 m ahead of the head at chest height, facing the user
            let h = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
            var f = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
            f = simd_length(f) > 1e-3 ? simd_normalize(f) : [0, 0, -1]
            backpack.position = h + f * 0.45 + [0, -0.3, 0]
            backpack.orientation = simd_quatf(angle: atan2(-f.x, -f.z), axis: [0, 1, 0]) * simd_quatf(angle: -0.4, axis: [1, 0, 0])
            backpack.isEnabled = true
            model.backpackOpen = true
            model.lastGesture = "Backpack opened"
        default:
            break
        }
        if !model.backpackOpen { backpack?.isEnabled = false }
    }

    static func sample(_ a: HandAnchor) -> HandSample? {
        guard let sk = a.handSkeleton else { return nil }
        let m = a.originFromAnchorTransform
        func p(_ j: HandSkeleton.JointName) -> SIMD3<Float> {
            let w = m * sk.joint(j).anchorFromJointTransform.columns.3
            return SIMD3(w.x, w.y, w.z)
        }
        return HandSample(time: CACurrentMediaTime(), wrist: p(.wrist), palm: p(.middleFingerKnuckle),
                          thumbTip: p(.thumbTip), indexTip: p(.indexFingerTip), middleTip: p(.middleFingerTip),
                          ringTip: p(.ringFingerTip), littleTip: p(.littleFingerTip))
    }
}

/// Simple blade held in the sword hand (placeholder until the equipped weapon model streams, M5).
enum SwordModel {
    static func make() -> Entity {
        let root = Entity()
        let blade = ModelEntity(mesh: .generateBox(size: [0.03, 0.008, 0.6], cornerRadius: 0.003),
                                materials: [SimpleMaterial(color: .init(white: 0.85, alpha: 1), isMetallic: true)])
        blade.position = [0, 0, -0.36]
        let guardBar = ModelEntity(mesh: .generateBox(size: [0.14, 0.02, 0.02]),
                                   materials: [SimpleMaterial(color: .brown, isMetallic: false)])
        guardBar.position = [0, 0, -0.05]
        root.addChild(blade)
        root.addChild(guardBar)
        return root
    }

    /// Blade along the fist: from the palm through the middle knuckle direction.
    static func attach(_ e: Entity, to a: HandAnchor) {
        guard let sk = a.handSkeleton else { return }
        let m = a.originFromAnchorTransform
        let knuckle = m * sk.joint(.middleFingerKnuckle).anchorFromJointTransform
        let wrist = m * sk.joint(.wrist).anchorFromJointTransform
        let pk = SIMD3(knuckle.columns.3.x, knuckle.columns.3.y, knuckle.columns.3.z)
        let pw = SIMD3(wrist.columns.3.x, wrist.columns.3.y, wrist.columns.3.z)
        // grip axis across the fist (thumb side), blade points along it
        let side = SIMD3(knuckle.columns.2.x, knuckle.columns.2.y, knuckle.columns.2.z)
        let dir = simd_length(side) > 1e-3 ? simd_normalize(side) * (a.chirality == .right ? 1 : -1) : simd_normalize(pk - pw)
        e.position = pk
        e.orientation = simd_quatf(from: [0, 0, -1], to: dir)
    }
}
