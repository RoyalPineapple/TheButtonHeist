import Foundation
import Network
import AccessibilityBridgeProtocol

@MainActor
@Observable
final class BonjourBrowser {

    struct DiscoveredDevice: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let endpoint: NWEndpoint

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
            lhs.id == rhs.id
        }
    }

    private(set) var devices: [DiscoveredDevice] = []
    private(set) var isSearching = false

    private var browser: NWBrowser?

    func startBrowsing() {
        stopBrowsing()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: accessibilityBridgeServiceType, domain: "local."),
            using: parameters
        )

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateUpdate(state)
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: .main)
        isSearching = true
        print("[BonjourBrowser] Started browsing for \(accessibilityBridgeServiceType)")
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleStateUpdate(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("[BonjourBrowser] Ready")
        case .failed(let error):
            print("[BonjourBrowser] Failed: \(error)")
            isSearching = false
        case .cancelled:
            print("[BonjourBrowser] Cancelled")
            isSearching = false
        default:
            break
        }
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var newDevices: [DiscoveredDevice] = []

        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                let device = DiscoveredDevice(
                    name: name,
                    endpoint: result.endpoint
                )
                newDevices.append(device)
                print("[BonjourBrowser] Found device: \(name)")
            }
        }

        devices = newDevices
    }
}
