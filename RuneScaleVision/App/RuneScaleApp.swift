import SwiftUI

@main
struct RuneScaleApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "connect") {
            ConnectionView()
                .environment(model)
        }
        .defaultSize(width: 560, height: 720)

        WindowGroup(id: "tabletop") {
            TabletopView()
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.0, height: 0.6, depth: 1.0, in: .meters)

        ImmersiveSpace(id: AppModel.immersiveID) {
            ImmersiveView()
                .environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed, .full)
        .immersiveEnvironmentBehavior(.coexist)
    }
}
