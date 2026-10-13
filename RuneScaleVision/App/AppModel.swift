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
    var host = UserDefaults.standard.string(forKey: "host") ?? ""
    var port = UserDefaults.standard.string(forKey: "port") ?? "43595"
    var token = UserDefaults.standard.string(forKey: "token") ?? ""
    /// 1.0 = one OSRS tile per meter (life size, player about 1.8 m tall).
    var lifeSize: Double = UserDefaults.standard.object(forKey: "lifeSize") as? Double ?? 1.0 {
        didSet {
            UserDefaults.standard.set(lifeSize, forKey: "lifeSize")
            scenes.forEach { $0.applyScale() }
        }
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

    private var scenes: [WorldScene] = []

    init() {
        client.onMessage = { [weak self] msg in
            guard let self else { return }
            if case .inputAck(let a) = msg { self.lastAck = a; return }
            if case .uiFrame(let f) = msg { self.applyInterface(f); return }
            self.scenes.forEach { $0.apply(msg) }
        }
        browser.start()
    }

    func register(_ scene: WorldScene) {
        guard !scenes.contains(where: { $0 === scene }) else { return }
        scenes.append(scene)
        if client.isConnected { client.reconnect() } // server resends everything on connect
    }

    func unregister(_ scene: WorldScene) {
        scenes.removeAll { $0 === scene }
    }

    /// One tap = one click at a scene-local point (OSRS units).
    func click(_ p: (x: Int32, y: Int32, z: Int32), button: RSProtocol.Button) {
        guard inputEnabled, client.isConnected else { return }
        clickSeq &+= 1
        client.send(RSProtocol.encodeClick(seq: clickSeq, button: button, x: p.x, y: p.y, z: p.z))
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

    func connectManual() {
        UserDefaults.standard.set(host, forKey: "host")
        UserDefaults.standard.set(port, forKey: "port")
        UserDefaults.standard.set(token, forKey: "token")
        guard let p = UInt16(port) else { return }
        scenes.forEach { $0.clear() }
        client.connect(.manual(host: host, port: p), token: token)
    }

    func connect(service: ServiceBrowser.Service) {
        UserDefaults.standard.set(token, forKey: "token")
        scenes.forEach { $0.clear() }
        client.connect(.bonjour(service.endpoint), token: token)
    }
}
