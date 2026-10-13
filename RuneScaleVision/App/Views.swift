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

    private var statusText: String {
        switch model.client.status {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .connected: "Connected (read-only stream)"
        case .failed(let e): "Error: \(e)"
        }
    }
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @State private var scene: WorldScene?

    var body: some View {
        RealityView { content in
            let s = WorldScene(mode: .roomScale, model: model)
            content.add(s.root)
            scene = s
            model.register(s)
        }
        .onDisappear {
            if let scene { model.unregister(scene) }
            model.immersiveOpen = false
        }
    }
}

struct TabletopView: View {
    @Environment(AppModel.self) private var model
    @State private var scene: WorldScene?

    var body: some View {
        RealityView { content in
            let s = WorldScene(mode: .tabletop, model: model)
            content.add(s.root)
            scene = s
            model.register(s)
        }
        .onDisappear { if let scene { model.unregister(scene) } }
    }
}
