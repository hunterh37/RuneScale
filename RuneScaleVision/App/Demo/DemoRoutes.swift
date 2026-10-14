#if DEBUG
import DicyaninStageDirector
import SwiftUI

/// Replay a world (`src`: mock, mock-clean or a .rsrec path) and open one view for capture.
enum DemoRoutes {
    @MainActor static func register(_ model: AppModel) -> (RouteBook) -> Void {
        { b in
            b.group("world") { b in
                b.route("tabletop", "Replay in the tabletop volume", duration: 6, tags: ["hero"]) { t in
                    model.loadReplay(t.param("src") ?? "mock-clean")
                    t.openWindow("tabletop")
                    await t.wait(3)
                    await t.ready(); await t.wait(3); t.done()
                }
                b.route("immersive", "Replay at room scale", duration: 6) { t in
                    model.loadReplay(t.param("src") ?? "mock-clean")
                    await t.openImmersive(AppModel.immersiveID)
                    model.immersiveOpen = true
                    await t.wait(3)
                    await t.ready(); await t.wait(3); t.done()
                }
            }
        }
    }
}
#endif
