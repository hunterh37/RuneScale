import SwiftUI
import ARKit
import QuartzCore

/// Mirrored RuneLite canvas: every side tab, chatbox, minimap, orbs and dialogs.
/// A tap clicks the matching canvas pixel; "Right click" makes the next tap a right click.
struct InterfacePanel: View {
    @Environment(AppModel.self) private var model
    let width: CGFloat
    var onRecenter: (() -> Void)?

    var body: some View {
        @Bindable var model = model
        if model.showInterface {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Text("Interface").font(.headline)
                    Spacer()
                    Toggle(isOn: $model.rightClickNext) { Label("Right click", systemImage: "contextualmenu.and.cursorarrow") }
                        .toggleStyle(.button)
                    if let onRecenter {
                        Button("Recenter", systemImage: "scope", action: onRecenter)
                    }
                }
                canvas
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(18)
            .frame(width: width)
            .glassBackgroundEffect()
        }
    }

    @ViewBuilder private var canvas: some View {
        let aspect = model.canvasSize.width / max(model.canvasSize.height, 1)
        if let img = model.interfaceImage {
            GeometryReader { geo in
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        model.clickInterface(unit: CGPoint(x: v.location.x / geo.size.width,
                                                           y: v.location.y / geo.size.height))
                    })
            }
            .aspectRatio(aspect, contentMode: .fit)
        } else {
            Text(model.client.isConnected ? "Waiting for interface frames (Stream interface in RuneLite)" : "Not connected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .aspectRatio(aspect, contentMode: .fit)
                .background(.black.opacity(0.3))
        }
    }
}

/// Device pose for placing the life-scale interface panel in front of the user.
@MainActor
final class HeadTracker {
    private let session = ARKitSession()
    private let world = WorldTrackingProvider()

    func start() async {
        guard WorldTrackingProvider.isSupported else { return }
        try? await session.run([world])
    }

    func stop() { session.stop() }

    func pose() -> simd_float4x4? {
        guard world.state == .running else { return nil }
        return world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.originFromAnchorTransform
    }
}
