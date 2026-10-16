import ARKit
import CoreGraphics
import RealityKit
import RuneScaleCore
import simd
import SwiftUI

/// Game side tabs in fixed-mode canvas pixels (765x503). Scaled by canvasSize for other sizes.
enum GameTab: Int, CaseIterable, Identifiable {
    case combat, skills, quests, inventory, equipment, prayer, magic
    case clan, friends, account, logout, settings, emotes, music
    var id: Int { rawValue }

    var title: String {
        ["Combat", "Skills", "Quests", "Backpack", "Worn", "Prayer", "Magic",
         "Clan", "Friends", "Account", "Logout", "Settings", "Emotes", "Music"][rawValue]
    }
    var symbol: String {
        ["figure.fencing", "chart.bar.fill", "flag.fill", "backpack.fill", "shield.lefthalf.filled",
         "sparkles", "wand.and.stars", "person.3.fill", "person.2.fill", "person.crop.circle",
         "rectangle.portrait.and.arrow.right", "gearshape.fill", "face.smiling", "music.note"][rawValue]
    }
    /// Tab stone centre: top row y 185, bottom row y 484, columns 33 px apart from x 538.
    var stone: CGPoint {
        let col = CGFloat(rawValue % 7), row = rawValue / 7
        return CGPoint(x: 538 + col * 33, y: row == 0 ? 185 : 484)
    }
    /// Side panel region holding the open tab's contents.
    static let panel = CGRect(x: 548, y: 205, width: 190, height: 262)
    static let fixed = CGSize(width: 765, height: 503)
}

/// Left-hand menu: palm faces the eyes = panel floats above the palm. Tab buttons click the
/// game tab stone; the cropped side panel below mirrors the open tab and forwards taps.
struct HandMenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 7), spacing: 6) {
                ForEach(GameTab.allCases) { tab in
                    Button { model.openTab(tab) } label: {
                        Image(systemName: tab.symbol).font(.system(size: 18)).frame(width: 44, height: 40)
                    }
                    .buttonStyle(.plain)
                    .background(model.selectedTab == tab ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(.black.opacity(0.25)),
                                in: RoundedRectangle(cornerRadius: 10))
                    .hoverEffect()
                    .accessibilityLabel(tab.title)
                }
            }
            HStack {
                Text(model.selectedTab?.title ?? "Tabs").font(.caption.bold())
                Spacer()
                if model.selectedTab == .music, !model.nowPlaying.isEmpty {
                    Text(model.nowPlaying).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { @Bindable var m = model; m.audioEnabled.toggle() } label: {
                    Image(systemName: model.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.audioEnabled ? "Mute" : "Unmute")
            }
            panel
        }
        .padding(12)
        .frame(width: 360)
        .glassBackgroundEffect()
    }

    @ViewBuilder private var panel: some View {
        let r = GameTab.panel
        if let img = model.interfaceImage, let crop = img.cropping(to: model.canvasRect(r)) {
            GeometryReader { geo in
                Image(decorative: crop, scale: 1).resizable().interpolation(.medium)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        let x = r.minX + v.location.x / geo.size.width * r.width
                        let y = r.minY + v.location.y / geo.size.height * r.height
                        model.clickInterface(unit: CGPoint(x: x / GameTab.fixed.width, y: y / GameTab.fixed.height))
                    })
            }
            .aspectRatio(r.width / r.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Text(model.client.isConnected ? "Waiting for interface frames" : "Not connected")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).aspectRatio(r.width / r.height, contentMode: .fit)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

enum HandMenuPlacement {
    /// Palm normal facing the head (dot > 0.5) on the menu hand.
    static func palmFacesHead(_ a: HandAnchor, head: simd_float4x4) -> (pos: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard let sk = a.handSkeleton else { return nil }
        let m = a.originFromAnchorTransform
        func p(_ j: HandSkeleton.JointName) -> SIMD3<Float> {
            let w = m * sk.joint(j).anchorFromJointTransform.columns.3
            return SIMD3(w.x, w.y, w.z)
        }
        let wrist = p(.wrist), index = p(.indexFingerKnuckle), little = p(.littleFingerKnuckle)
        var n = simd_cross(index - wrist, little - wrist)
        guard simd_length(n) > 1e-5 else { return nil }
        n = simd_normalize(n) * (a.chirality == .left ? -1 : 1)
        let palm = (wrist + index + little) / 3
        let h = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let toHead = simd_normalize(h - palm)
        return simd_dot(n, toHead) > 0.5 ? (palm, n) : nil
    }

    /// Panel 0.12 m above the palm along its normal, billboarded to the head (yaw only).
    static func place(_ e: Entity, palm: SIMD3<Float>, normal: SIMD3<Float>, head: simd_float4x4) {
        let h = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let pos = palm + normal * 0.06 + [0, 0.14, 0]
        let d = h - pos
        e.position = pos
        e.orientation = simd_quatf(angle: atan2(d.x, d.z), axis: [0, 1, 0])
    }
}
