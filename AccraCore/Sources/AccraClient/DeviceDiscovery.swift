import Foundation
import Network
import AccraCore

@MainActor
final class DeviceDiscovery {

    private var browser: NWBrowser?
    private var discoveredDevices: [String: DiscoveredDevice] = [:]

    var onDeviceFound: ((DiscoveredDevice) -> Void)?
    var onDeviceLost: ((DiscoveredDevice) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: accraServiceType, domain: "local."),
            using: parameters
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results, changes: changes)
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.onStateChange?(state == .ready)
            }
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        discoveredDevices.removeAll()
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    let device = DiscoveredDevice(
                        id: name,
                        name: name,
                        endpoint: result.endpoint
                    )
                    discoveredDevices[name] = device
                    onDeviceFound?(device)
                }
            case .removed(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    if let device = discoveredDevices.removeValue(forKey: name) {
                        onDeviceLost?(device)
                    }
                }
            default:
                break
            }
        }
    }
}
