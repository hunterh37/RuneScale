import RealityKit
import RuneScaleCore
import SwiftUI

/// Mirrors the game's open right-click menu in 3D at the tapped point. Rows are top to bottom;
/// a tap picks that row in the game client.
struct GameMenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let menu = model.gameMenu {
            VStack(alignment: .leading, spacing: 0) {
                Text("Choose Option")
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 0.36, green: 0.33, blue: 0.27))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                ForEach(Array(menu.rows.enumerated()), id: \.offset) { i, row in
                    Button { model.selectMenu(i) } label: {
                        HStack(spacing: 6) {
                            Text(row.option).foregroundStyle(.white)
                            if !row.target.isEmpty {
                                Text(row.target).foregroundStyle(Color(red: 1, green: 1, blue: 0))
                            }
                        }
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
            }
            .padding(.bottom, 6)
            .frame(minWidth: 240, alignment: .leading)
            .fixedSize()
            .background(Color(red: 0.36, green: 0.33, blue: 0.27).opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

enum GameMenuPlacement {
    /// Shows `entity` above the anchored point when the open menu belongs to `scene`, facing the viewer.
    @MainActor
    static func update(_ entity: Entity?, model: AppModel, scene: WorldScene?, lift: Float) {
        guard let entity else { return }
        guard model.gameMenu != nil, let scene, let a = model.menuAnchor, a.scene == ObjectIdentifier(scene) else {
            entity.isEnabled = false
            return
        }
        let p = scene.world.convert(position: a.point, to: nil)
        entity.setPosition(p + [0, lift, 0], relativeTo: nil)
        entity.components.set(BillboardComponent())
        entity.isEnabled = true
    }
}
