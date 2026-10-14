import Foundation
import CoreGraphics
import ImageIO
import Observation
import RuneScaleCore

@MainActor
@Observable
final class AppModel {
    static let immersiveID = "world"

    let client = StreamClient()
    let browser = ServiceBrowser()
    var host = UserDefaults.standard.string(forKey: "host") ?? "" {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    var port = UserDefaults.standard.string(forKey: "port") ?? "43595" {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }
    var token = UserDefaults.standard.string(forKey: "token") ?? "" {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    /// 1.0 = one OSRS tile per meter (life size, player about 1.8 m tall).
    var lifeSize: Double = UserDefaults.standard.object(forKey: "lifeSize") as? Double ?? 1.0 {
        didSet {
            UserDefaults.standard.set(lifeSize, forKey: "lifeSize")
            scenes.forEach { $0.applyScale() }
        }
    }
    /// Tiles from the player beyond which terrain and objects are hidden. Saved across launches.
    var renderDistance: Double = UserDefaults.standard.object(forKey: "renderDistance") as? Double ?? 32 {
        didSet {
            UserDefaults.standard.set(renderDistance, forKey: "renderDistance")
            scenes.forEach { $0.applyRenderDistance() }
        }
    }
    /// Room-scale only: full immersion with a black sky sphere instead of passthrough. Saved across launches.
    var blackSkybox: Bool = UserDefaults.standard.bool(forKey: "blackSkybox") {
        didSet { UserDefaults.standard.set(blackSkybox, forKey: "blackSkybox") }
    }
    var immersiveOpen = false
    var inputEnabled: Bool = UserDefaults.standard.object(forKey: "inputEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(inputEnabled, forKey: "inputEnabled") }
    }
    var lastAck: RSProtocol.InputAck?
    /// Mirrored client canvas (all tabs, chat, minimap, dialogs) from UI_FRAME.
    var interfaceImage: CGImage?
    var canvasSize = CGSize(width: 765, height: 503)
    var interfaceFrames = 0
    var showInterface: Bool = UserDefaults.standard.object(forKey: "showInterface") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showInterface, forKey: "showInterface") }
    }
    /// Next interface tap is a right click (opens the game menu), then resets.
    var rightClickNext = false
    private var clickSeq: UInt32 = 0
    /// Inventory (28) and equipment (14) from CONTAINER; icons from ITEM_ICON by item id.
    var inventory = RSProtocol.Container(kind: .inventory, ids: Array(repeating: -1, count: 28), quantities: Array(repeating: 0, count: 28))
    var equipment = RSProtocol.Container(kind: .equipment, ids: Array(repeating: -1, count: 14), quantities: Array(repeating: 0, count: 14))
    var itemIcons: [Int32: CGImage] = [:]
    var backpackOpen = false
    /// Side tab last opened from the left-hand menu.
    var selectedTab: GameTab?
    /// Local player model; hidden by default since the viewer stands inside it.
    var showLocalPlayer: Bool = UserDefaults.standard.object(forKey: "showLocalPlayer") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showLocalPlayer, forKey: "showLocalPlayer") }
    }
    var handGestures: Bool = UserDefaults.standard.object(forKey: "handGestures") as? Bool ?? true {
        didSet { UserDefaults.standard.set(handGestures, forKey: "handGestures") }
    }
    var showWeapon: Bool = UserDefaults.standard.object(forKey: "showWeapon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showWeapon, forKey: "showWeapon"); rig.showWeapon = showWeapon }
    }
    var swordHand: String = UserDefaults.standard.string(forKey: "swordHand") ?? "right" {
        didSet { UserDefaults.standard.set(swordHand, forKey: "swordHand") }
    }
    var lastGesture = "No gesture yet"
    /// Worn models on the user's body (immersive space only).
    let rig = EquipmentRig()

    private var scenes: [WorldScene] = []

    init() {
        rig.showWeapon = showWeapon
        client.onMessage = { [weak self] msg in self?.handle(msg) }
        browser.start()
        loadLaunchReplay()
    }

    private func handle(_ msg: RSProtocol.Message) {
        if case .inputAck(let a) = msg { self.lastAck = a; return }
        if case .uiFrame(let f) = msg { self.applyInterface(f); return }
        if case .container(let c) = msg {
            if c.kind == .inventory { self.inventory = c } else { self.equipment = c }
            return
        }
        if case .itemIcon(let id, let png) = msg {
            if let src = CGImageSourceCreateWithData(png as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { self.itemIcons[id] = img }
            return
        }
        record(msg)
        for k in pendingMsgs.keys { pendingMsgs[k]?.append(msg) }
        self.scenes.forEach { $0.apply(msg) }
        if case .equipModel(let slot, _, let meshId) = msg, let scene = self.scenes.first {
            self.rig.set(slot: slot, meshId: meshId, scene: scene)
        }
    }

    // MARK: Offline replay (simulator harness)

    /// Messages fed to every scene instead of the network. Set by `-replay <path|mock|mock-clean>`.
    private(set) var replay: [RSProtocol.Message]?
    var replayName: String?
    var replayAudit: ColorAudit.Report?
    /// View opened at launch with `-replayView immersive|tabletop|none` (default immersive).
    var replayAutoOpen: String?

    private func loadLaunchReplay() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let env = ProcessInfo.processInfo.environment
        guard let src = value("-replay") ?? env["RUNESCALE_REPLAY"] else { return }
        loadReplay(src)
        if replay != nil { replayAutoOpen = value("-replayView") ?? "immersive" }
    }

    /// `mock` = synthetic scene with legacy white-texture rows, `mock-clean` = without them, else a .rsrec path.
    func loadReplay(_ src: String) {
        let msgs: [RSProtocol.Message]
        switch src {
        case "mock": msgs = MockWorld.messages(legacy: true)
        case "mock-clean": msgs = MockWorld.messages(legacy: false)
        case "palette": msgs = MockWorld.paletteTest()
        default:
            let path = (src as NSString).expandingTildeInPath
            guard let data = FileManager.default.contents(atPath: path),
                  let m = try? Recording.messages(from: data) else {
                print("[RuneScale] replay: cannot read \(path)")
                return
            }
            msgs = m
        }
        client.disconnect()
        replay = msgs
        replayName = src
        replayAudit = ColorAudit.report(msgs)
        if let a = replayAudit {
            print("[RuneScale] replay \(src): \(msgs.count) messages, \(a.meshes) meshes (\(a.whiteMeshes) near-white), \(a.tiles) tiles (\(a.whiteTiles) near-white)")
        }
        worldLog = []
        scenes.forEach { s in s.clear(); msgs.forEach(s.apply) }
        msgs.forEach { m in
            if case .container = m { handle(m) }
            if case .itemIcon = m { handle(m) }
        }
    }

    func stopReplay() {
        replay = nil
        replayName = nil
        replayAudit = nil
        scenes.forEach { $0.clear() }
    }

    /// World messages since the last HELLO/RESET; seeds scenes opened mid-session without a reconnect.
    private var worldLog: [RSProtocol.Message] = []
    private var seedTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Live messages that arrive while a scene is still seeding.
    private var pendingMsgs: [ObjectIdentifier: [RSProtocol.Message]] = [:]
    private static let seedBatch = 40

    private func record(_ msg: RSProtocol.Message) {
        switch msg {
        case .hello, .reset: worldLog = [msg]
        case .frame:
            if let i = worldLog.lastIndex(where: { if case .frame = $0 { true } else { false } }) { worldLog.remove(at: i) }
            worldLog.append(msg)
        default: worldLog.append(msg)
        }
    }

    func register(_ scene: WorldScene) {
        guard !scenes.contains(where: { $0 === scene }) else { return }
        let seed = replay ?? worldLog
        let id = ObjectIdentifier(scene)
        pendingMsgs[id] = []
        // Mesh building is synchronous on main; spreading it over frames avoids the RealityKit commit watchdog.
        seedTasks[id] = Task { @MainActor [weak self, weak scene] in
            var i = 0
            while i < seed.count {
                guard let scene, !Task.isCancelled else { return }
                let end = min(i + Self.seedBatch, seed.count)
                seed[i..<end].forEach(scene.apply)
                i = end
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard let self, let scene, !Task.isCancelled else { return }
            self.seedTasks[id] = nil
            self.pendingMsgs.removeValue(forKey: id)?.forEach(scene.apply)
            self.scenes.append(scene)
            if self.replay != nil, let first = self.scenes.first {
                seed.forEach { if case .equipModel(let slot, _, let mid) = $0 { self.rig.set(slot: slot, meshId: mid, scene: first) } }
            }
        }
    }

    func unregister(_ scene: WorldScene) {
        seedTasks.removeValue(forKey: ObjectIdentifier(scene))?.cancel()
        pendingMsgs.removeValue(forKey: ObjectIdentifier(scene))
        scenes.removeAll { $0 === scene }
    }

    /// One tap = one click at a scene-local point (OSRS units).
    func click(_ p: (x: Int32, y: Int32, z: Int32), button: RSProtocol.Button) {
        guard inputEnabled, client.isConnected else { return }
        clickSeq &+= 1
        client.send(RSProtocol.encodeClick(seq: clickSeq, button: button, x: p.x, y: p.y, z: p.z))
    }

    /// One gesture = one click on an inventory or equipment slot.
    func clickSlot(_ container: RSProtocol.ContainerKind, slot: Int, button: RSProtocol.Button = .left) {
        guard inputEnabled, client.isConnected, (0..<256).contains(slot) else { return }
        clickSeq &+= 1
        client.send(RSProtocol.encodeWidgetClick(seq: clickSeq, button: button, container: container, slot: UInt8(slot)))
    }

    private func applyInterface(_ f: RSProtocol.UIFrame) {
        guard showInterface,
              let src = CGImageSourceCreateWithData(f.jpeg as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        interfaceImage = img
        canvasSize = CGSize(width: f.canvasWidth, height: f.canvasHeight)
        interfaceFrames += 1
    }

    /// One tap on the interface panel = one click at that canvas pixel. `unit` is 0...1 in panel space.
    func clickInterface(unit: CGPoint) {
        guard inputEnabled, client.isConnected else { return }
        let button: RSProtocol.Button = rightClickNext ? .right : .left
        rightClickNext = false
        let x = Int32((min(max(unit.x, 0), 0.9999) * canvasSize.width).rounded(.down))
        let y = Int32((min(max(unit.y, 0), 0.9999) * canvasSize.height).rounded(.down))
        clickSeq &+= 1
        client.send(RSProtocol.encodeUIClick(seq: clickSeq, button: button, x: x, y: y))
    }

    /// Fixed-mode canvas rect scaled to the current canvas, in image pixels.
    func canvasRect(_ r: CGRect) -> CGRect {
        guard let img = interfaceImage else { return r }
        let sx = CGFloat(img.width) / GameTab.fixed.width, sy = CGFloat(img.height) / GameTab.fixed.height
        return CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
    }

    /// One click on a side tab stone.
    func openTab(_ tab: GameTab) {
        selectedTab = tab
        let p = tab.stone
        let saved = rightClickNext
        rightClickNext = false
        clickInterface(unit: CGPoint(x: p.x / GameTab.fixed.width, y: p.y / GameTab.fixed.height))
        rightClickNext = saved
    }

    func connectManual() {
        UserDefaults.standard.set(host, forKey: "host")
        UserDefaults.standard.set(port, forKey: "port")
        UserDefaults.standard.set(token, forKey: "token")
        guard let p = UInt16(port) else { return }
        replay = nil
        scenes.forEach { $0.clear() }
        client.connect(.manual(host: host, port: p), token: token)
    }

    func connect(service: ServiceBrowser.Service) {
        UserDefaults.standard.set(token, forKey: "token")
        replay = nil
        scenes.forEach { $0.clear() }
        client.connect(.bonjour(service.endpoint), token: token)
    }
}
