import Foundation
import RealityKit
import RuneScaleCore
import UIKit

/// Game hitsplats and HP bars drawn above actors, in scene-local meters (1 tile = 1 m).
/// Shows only what the game sends (HITSPLAT, HEALTH); nothing is predicted.
@MainActor
final class CombatOverlays {
    @MainActor private final class Slot {
        let anchor = Entity()
        let bar = Entity()
        let fill: ModelEntity
        var splats: [Entity?] = Array(repeating: nil, count: 4)
        init(fill: ModelEntity) { self.fill = fill }
    }

    private static let barWidth: Float = 0.7, barHeight: Float = 0.09
    private static let splatRadius: Float = 0.17
    private static let splatLife: Duration = .milliseconds(1200)

    private var slots: [UInt32: Slot] = [:]
    private var textMeshes: [String: MeshResource] = [:]
    private lazy var barMesh = MeshResource.generateBox(width: Self.barWidth, height: Self.barHeight, depth: 0.01)
    private lazy var discMesh = MeshResource.generateCylinder(height: 0.01, radius: Self.splatRadius)

    /// Places overlays above an actor at its FRAME transform (world-local). `mesh` gives the model height.
    func place(key: UInt32, transform t: Transform, mesh: MeshResource?, world: Entity, local: Bool) {
        guard let s = slots[key] else { return }
        if s.anchor.parent !== world { world.addChild(s.anchor) }
        var p = t.translation
        if local {
            // the viewer stands inside the local player: show at chest height, ahead of the player
            let fwd = t.rotation.act([0, 0, 1])
            p += SIMD3(fwd.x, 0, fwd.z) * 0.6 + [0, 1.1, 0]
        } else {
            p.y += max(0.6, mesh?.bounds.max.y ?? 1.5) + 0.15
        }
        s.anchor.move(to: Transform(translation: p), relativeTo: world, duration: 0.08, timingFunction: .linear)
    }

    func hitsplat(_ h: RSProtocol.Hitsplat, on entity: Entity?) {
        guard entity != nil else { return }
        let s = slot(h.key)
        if let hp = h.health { setBar(s, hp.fraction) }
        let i = s.splats.firstIndex(where: { $0 == nil }) ?? 0
        s.splats[i]?.removeFromParent()
        let e = makeSplat(h)
        // 0 center, 1 below, 2 left, 3 right (the game's four-hitsplat layout)
        let offsets: [SIMD3<Float>] = [[0, 0, 0], [0, -0.36, 0], [-0.36, -0.18, 0], [0.36, -0.18, 0]]
        e.position = offsets[i] + [0, -0.25, 0]
        s.anchor.addChild(e)
        s.splats[i] = e
        Task { @MainActor [weak e, weak s] in
            try? await Task.sleep(for: Self.splatLife)
            guard let e, let s else { return }
            e.removeFromParent()
            if let j = s.splats.firstIndex(where: { $0 === e }) { s.splats[j] = nil }
        }
    }

    /// HEALTH: bars for listed actors, hidden for the rest.
    func health(_ list: [RSProtocol.Health], actors: [UInt32: ModelEntity]) {
        var shown = Set<UInt32>()
        for h in list where actors[h.key] != nil {
            shown.insert(h.key)
            setBar(slot(h.key), h.fraction)
        }
        for (key, s) in slots where !shown.contains(key) { s.bar.isEnabled = false }
    }

    func forget(_ key: UInt32) {
        slots.removeValue(forKey: key)?.anchor.removeFromParent()
    }

    func removeAll() {
        slots.values.forEach { $0.anchor.removeFromParent() }
        slots.removeAll()
    }

    // MARK: building

    private func slot(_ key: UInt32) -> Slot {
        if let s = slots[key] { return s }
        let back = ModelEntity(mesh: barMesh, materials: [Self.unlit(.init(red: 0.8, green: 0, blue: 0, alpha: 1))])
        let fill = ModelEntity(mesh: barMesh, materials: [Self.unlit(.init(red: 0, green: 0.8, blue: 0, alpha: 1))])
        fill.position.z = 0.006
        let s = Slot(fill: fill)
        s.bar.addChild(back)
        s.bar.addChild(fill)
        s.bar.components.set(BillboardComponent())
        s.bar.isEnabled = false
        s.anchor.addChild(s.bar)
        slots[key] = s
        return s
    }

    private func setBar(_ s: Slot, _ fraction: Float) {
        let f = max(0, min(1, fraction))
        s.fill.scale = [max(f, 0.0001), 1, 1]
        s.fill.position.x = -Self.barWidth * (1 - f) / 2
        s.bar.isEnabled = true
    }

    private func makeSplat(_ h: RSProtocol.Hitsplat) -> Entity {
        let root = Entity()
        root.components.set(BillboardComponent())
        let disc = ModelEntity(mesh: discMesh, materials: [Self.unlit(Self.color(h))])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(disc)
        let text = "\(h.amount)"
        let mesh = textMesh(text)
        let label = ModelEntity(mesh: mesh, materials: [Self.unlit(.white)])
        let b = mesh.bounds
        label.position = [-b.center.x, -b.center.y, 0.012]
        root.addChild(label)
        return root
    }

    private func textMesh(_ s: String) -> MeshResource {
        if let m = textMeshes[s] { return m }
        let m = MeshResource.generateText(s, extrusionDepth: 0.004, font: .boldSystemFont(ofSize: 0.18),
                                          containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        if textMeshes.count > 256 { textMeshes.removeAll() }
        textMeshes[s] = m
        return m
    }

    /// Colors by HitsplatID: 0 damage blue, poison green, venom teal, disease yellow, heal purple, else red.
    private static func color(_ h: RSProtocol.Hitsplat) -> UIColor {
        switch h.type {
        case 65: return UIColor(red: 0.1, green: 0.55, blue: 0.1, alpha: 1)
        case 5: return UIColor(red: 0.1, green: 0.45, blue: 0.4, alpha: 1)
        case 4: return UIColor(red: 0.8, green: 0.7, blue: 0.1, alpha: 1)
        case 6: return UIColor(red: 0.6, green: 0.1, blue: 0.6, alpha: 1)
        default: return h.amount == 0 ? UIColor(red: 0.15, green: 0.3, blue: 0.8, alpha: 1) : UIColor(red: 0.75, green: 0.05, blue: 0.05, alpha: 1)
        }
    }

    private static func unlit(_ c: UIColor) -> UnlitMaterial {
        var m = UnlitMaterial(color: c)
        m.blending = .opaque
        return m
    }
}
