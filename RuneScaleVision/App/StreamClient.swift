import Foundation
import Network
import Observation
import RuneScaleCore

/// WebSocket client. Receives the scene stream; sends CLICK messages for headset input.
@MainActor
@Observable
final class StreamClient {
    enum Target {
        case manual(host: String, port: UInt16)
        case bonjour(NWEndpoint)
    }

    enum Status: Equatable { case idle, connecting, connected, failed(String) }

    var status: Status = .idle
    var messagesReceived = 0
    var bytesReceived = 0
    var isConnected: Bool { status == .connected }
    @ObservationIgnored var onMessage: ((RSProtocol.Message) -> Void)?

    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var last: (Target, String)?
    private let queue = DispatchQueue(label: "org.oldschool.runescape.runescale.net")

    func connect(_ target: Target, token: String) {
        disconnect()
        last = (target, token)
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 64 << 20
        ws.setAdditionalHeaders([("X-RuneScale-Token", token)])
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.includePeerToPeer = false

        let endpoint: NWEndpoint
        switch target {
        case .manual(let host, let port):
            let q = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let url = URL(string: "ws://\(host):\(port)/?token=\(q)") else {
                status = .failed("Invalid host"); return
            }
            endpoint = .url(url)
        case .bonjour(let e):
            endpoint = e
        }

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        status = .connecting
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                switch state {
                case .ready: self.status = .connected
                case .failed(let e): self.status = .failed(e.localizedDescription)
                case .waiting(let e): self.status = .failed("Waiting: \(e.localizedDescription)")
                case .cancelled: if self.status != .idle { self.status = .idle }
                default: break
                }
            }
        }
        conn.start(queue: queue)
        receive(on: conn)
    }

    func reconnect() {
        guard let (t, tok) = last else { return }
        connect(t, token: tok)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        status = .idle
    }

    func send(_ data: Data) {
        guard let connection, isConnected else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
        let ctx = NWConnection.ContentContext(identifier: "click", metadata: [meta])
        connection.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    nonisolated private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            if let error {
                Task { @MainActor in self?.status = .failed(error.localizedDescription) }
                return
            }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .close {
                Task { @MainActor in self?.status = .failed("Closed by plugin (check token)") }
                return
            }
            if let data, !data.isEmpty, let msg = try? RSProtocol.decode(data) {
                let size = data.count
                Task { @MainActor in
                    guard let self, self.connection === conn else { return }
                    self.messagesReceived += 1
                    self.bytesReceived += size
                    self.onMessage?(msg)
                }
            }
            self?.receive(on: conn)
        }
    }
}
