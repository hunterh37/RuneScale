import SwiftUI

@main
struct RuneScaleApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "connect") {
            ConnectionView()
                .environment(model)
                #if DEBUG
                .director(DemoRoutes.register(model))
                #endif
        }
        .defaultSize(width: 560, height: 720)

        Window("Tabletop", id: "tabletop") {
            TabletopView()
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.0, height: 0.6, depth: 1.0, in: .meters)

        WindowGroup(id: "interface") {
            InterfacePanel()
                .environment(model)
        }
        .defaultSize(width: 1000, height: 760)
        .windowResizability(.contentMinSize)

        ImmersiveSpace(id: AppModel.immersiveID) {
            ImmersiveView()
                .environment(model)
        }
        .immersionStyle(selection: Binding<ImmersionStyle>(
            get: { model.blackSkybox ? .full : .mixed },
            set: { _ in }
        ), in: .mixed, .full)
        .immersiveEnvironmentBehavior(.coexist)
    }
}
