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
                Section("Hands") {
                    Toggle("Hand gestures (swing, backpack)", isOn: $model.handGestures)
                    Toggle("Show own player model", isOn: $model.showLocalPlayer)
                    Picker("Sword hand", selection: $model.swordHand) {
                        Text("Right").tag("right")
                        Text("Left").tag("left")
                    }
                    Text(model.lastGesture).foregroundStyle(.secondary)
                }
                Section("Status") {
                    Text(statusText)
                    Text("\(model.client.messagesReceived) messages, \(model.client.bytesReceived / 1024) KB")
                        .foregroundStyle(.secondary)
                }
                Section("Replay") {
                    if let name = model.replayName {
                        Text("Replaying \(name)")
                        if let a = model.replayAudit {
                            Text("\(a.meshes) meshes, \(a.whiteMeshes) near-white; \(a.tiles) tiles, \(a.whiteTiles) near-white")
                                .foregroundStyle(.secondary)
                        }
                        Button("Stop replay") { model.stopReplay() }
                    } else {
                        Button("Load mock world") { model.loadReplay("mock") }
                    }
                }
                Section("Scale") {
                    Slider(value: $model.lifeSize, in: 0.25...2.0, step: 0.05) {
                        Text("Life size")
                    }
                    Text(String(format: "%.2fx (1.00x = 1 tile per meter)", model.lifeSize)).foregroundStyle(.secondary)
                }
                Section("Render distance") {
                    Slider(value: $model.renderDistance, in: 8...104, step: 4) {
                        Text("Render distance")
                    }
                    Text("\(Int(model.renderDistance)) tiles").foregroundStyle(.secondary)
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
                    Button("Open interface window") { openWindow(id: "interface") }
                }
            }
            .navigationTitle("RuneScale")
        }
        .task {
            guard let view = model.replayAutoOpen else { return }
            model.replayAutoOpen = nil
            switch view {
            case "tabletop": openWindow(id: "tabletop")
            case "immersive":
                if case .opened = await openImmersiveSpace(id: AppModel.immersiveID) { model.immersiveOpen = true }
            default: break
            }
        }
    }

    private func ackText(_ a: RSProtocol.InputAck) -> String {
        switch a.result {
        case .ok: "sent at \(a.canvasX),\(a.canvasY)"
        case .disabled: "Headset input is off in RuneLite"
        case .offscreen: "point not visible in the game view"
        case .rateLimited: "dropped (too fast)"
        case .notLoggedIn: "not logged in"
        case .widgetHidden: "open the inventory or equipment tab in game"
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
    @Environment(\.openWindow) private var openWindow
    @State private var head = HeadTracker()
    @State private var hands = HandInput()
    @State private var backpack: Entity?
    @State private var sword: Entity?

    var body: some View {
        RealityView { content, attachments in
            let s = WorldScene(mode: .roomScale, model: model)
            content.add(s.root)
            scene = s
            model.register(s)
            content.add(model.rig.root)
            let blade = SwordModel.make()
            blade.isEnabled = false
            content.add(blade)
            sword = blade
            if let bag = attachments.entity(for: "backpack") {
                bag.isEnabled = false
                content.add(bag)
                backpack = bag
            }
        } attachments: {
            Attachment(id: "backpack") {
                BackpackView { model.backpackOpen = false }
                    .environment(model)
            }
        }
        .modifier(TapToClick(model: model, scene: scene))
        .task {
            guard model.handGestures else { return }
            await hands.run(model: model, scene: { scene }, head: { head.pose() }, sword: { sword }, backpack: { backpack }, rig: model.rig)
        }
        .task { await head.start() }
        .onAppear { if model.showInterface { openWindow(id: "interface") } }
        .onDisappear {
            if let scene { model.unregister(scene) }
            head.stop()
            hands.stop()
            model.immersiveOpen = false
        }
    }

}

struct TabletopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var scene: WorldScene?

    var body: some View {
        RealityView { content in
            let s = WorldScene(mode: .tabletop, model: model)
            content.add(s.root)
            scene = s
            model.register(s)
        }
        .modifier(TapToClick(model: model, scene: scene))
        .onAppear { if model.showInterface { openWindow(id: "interface") } }
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
