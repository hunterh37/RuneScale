import Foundation
import Network
import Observation

/// Browses _runescale._tcp advertised by the RuneLite plugin (jmDNS).
@MainActor
@Observable
final class ServiceBrowser {
    struct Service: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    var services: [Service] = []
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        let b = NWBrowser(for: .bonjour(type: "_runescale._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let list: [Service] = results.compactMap { r in
                if case .service(let name, _, _, _) = r.endpoint { return Service(name: name, endpoint: r.endpoint) }
                return nil
            }
            Task { @MainActor in self?.services = list.sorted { $0.name < $1.name } }
        }
        b.start(queue: .main)
        browser = b
    }
}
