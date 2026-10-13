import SwiftUI
import RealityKit
import RuneScaleCore

struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Pairing token") {
                    TextField("6-digit token from the RuneLite panel", text: $model.token)
                        .keyboardType(.numberPad)
                }
                Section("Nearby RuneLite") {
                    if model.browser.services.isEmpty {
                        Text("Searching for RuneScale Stream on this network").foregroundStyle(.secondary)
                    }
                    ForEach(model.browser.services) { s in
                        Button(s.name) { model.connect(service: s) }
                    }
                }
                Section("Manual") {
                    TextField("Mac IP address", text: $model.host)
                    TextField("Port", text: $model.port).keyboardType(.numberPad)
                    Button("Connect") { model.connectManual() }
                        .disabled(model.host.isEmpty || model.token.isEmpty)
                }
                Section("Input") {
                    Toggle("Tap to click in game", isOn: $model.inputEnabled)
                    Toggle("Show interface panel", isOn: $model.showInterface)
                    Text("\(model.interfaceFrames) interface frames").foregroundStyle(.secondary)
                    Text("Also enable Headset input in the RuneLite plugin config.").foregroundStyle(.secondary)
                    if let a = model.lastAck {
                        Text("Last click #\(a.seq): \(ackText(a))").foregroundStyle(.secondary)
                    }
                }
                Section("Status") {
                    Text(statusText)
                    Text("\(model.client.messagesReceived) messages, \(model.client.bytesReceived / 1024) KB")
                        .foregroundStyle(.secondary)
                }
                Section("Scale") {
                    Slider(value: $model.lifeSize, in: 0.25...2.0, step: 0.05) {
                        Text("Life size")
                    }
                    Text(String(format: "%.2fx (1.00x = 1 tile per meter)", model.lifeSize)).foregroundStyle(.secondary)
                }
                Section("View") {
                    Button(model.immersiveOpen ? "Exit room-scale" : "Enter room-scale") {
                        Task {
                            if model.immersiveOpen {
                                await dismissImmersiveSpace()
                                model.immersiveOpen = false
                            } else if case .opened = await openImmersiveSpace(id: AppModel.immersiveID) {
                                model.immersiveOpen = true
                            }
                        }
                    }
                    Button("Open tabletop") { openWindow(id: "tabletop") }
                }
            }
            .navigationTitle("RuneScale")
        }
    }

    private func ackText(_ a: RSProtocol.InputAck) -> String {
        switch a.result {
        case .ok: "sent at \(a.canvasX),\(a.canvasY)"
        case .disabled: "Headset input is off in RuneLite"
        case .offscreen: "point not visible in the game view"
        case .rateLimited: "dropped (too fast)"
        case .notLoggedIn: "not logged in"
        case .unknown: "unknown result"
        }
    }

    private var statusText: String {
        switch model.client.status {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed(let e): "Error: \(e)"
        }
    }
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @State private var scene: WorldScene?
    @State private var panel: Entity?
    @State private var head = HeadTracker()

    var body: some View {
        RealityView { content, attachments in
            let s = WorldScene(mode: .roomScale, model: model)
            content.add(s.root)
            scene = s
            model.register(s)
            if let ui = attachments.entity(for: "interface") {
                ui.position = [0, 1.15, -0.75] // until the device pose is known
                content.add(ui)
                panel = ui
            }
        } attachments: {
            Attachment(id: "interface") {
                InterfacePanel(width: 1000) { recenter() }
                    .environment(model)
            }
        }
        .modifier(TapToClick(model: model, scene: scene))
        .task {
            await head.start()
            for _ in 0..<30 {
                if recenter() { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear {
            if let scene { model.unregister(scene) }
            head.stop()
            model.immersiveOpen = false
        }
    }

    /// Anchors the interface panel 0.7 m in front of the user, below eye level, facing them.
    @discardableResult
    private func recenter() -> Bool {
        guard let panel, let m = head.pose() else { return false }
        let h = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        var f = -SIMD3<Float>(m.columns.2.x, 0, m.columns.2.z)
        guard simd_length(f) > 1e-3 else { return false }
        f = simd_normalize(f)
        panel.position = h + f * 0.7 + [0, -0.28, 0]
        let yaw = simd_quatf(angle: atan2(-f.x, -f.z), axis: [0, 1, 0])
        panel.orientation = yaw * simd_quatf(angle: -0.3, axis: [1, 0, 0])
        return true
    }
}

struct TabletopView: View {
    @Environment(AppModel.self) private var model
    @State private var scene: WorldScene?

    var body: some View {
        RealityView { content, attachments in
            let s = WorldScene(mode: .tabletop, model: model)
            content.add(s.root)
            scene = s
            model.register(s)
            if let ui = attachments.entity(for: "interface") {
                // front edge of the volume, tilted up toward the viewer
                ui.position = [0, -0.2, 0.36]
                ui.orientation = simd_quatf(angle: -0.55, axis: [1, 0, 0])
                content.add(ui)
            }
        } attachments: {
            Attachment(id: "interface") {
                InterfacePanel(width: 760, onRecenter: nil)
                    .environment(model)
            }
        }
        .modifier(TapToClick(model: model, scene: scene))
        .onDisappear { if let scene { model.unregister(scene) } }
    }
}

/// Tap on any scene entity sends one left click at that 3D point.
private struct TapToClick: ViewModifier {
    let model: AppModel
    let scene: WorldScene?

    func body(content: Content) -> some View {
        content.gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let scene, Self.isInWorld(value.entity, scene.world) else { return }
                    let p = value.convert(value.location3D, from: .local, to: scene.world)
                    model.click(Coordinates.units(p, metersPerUnit: 1 / Coordinates.unitsPerTile), button: .left)
                }
        )
    }

    /// Taps on the interface attachment are handled by the panel, not as world clicks.
    private static func isInWorld(_ e: Entity, _ world: Entity) -> Bool {
        var cur: Entity? = e
        while let c = cur {
            if c === world { return true }
            cur = c.parent
        }
        return false
    }
}
