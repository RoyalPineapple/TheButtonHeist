import Foundation
import Network
import AccraCore
import os.log

private let logger = Logger(subsystem: "com.accra.client", category: "discovery")

@MainActor
final class DeviceDiscovery {

    private var browser: NWBrowser?
    private var discoveredDevices: [String: DiscoveredDevice] = [:]

    var onDeviceFound: ((DiscoveredDevice) -> Void)?
    var onDeviceLost: ((DiscoveredDevice) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    func start() {
        logger.info("Starting Bonjour discovery for type: \(accraServiceType)")

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: accraServiceType, domain: "local."),
            using: parameters
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                logger.info("Results changed: \(results.count) results, \(changes.count) changes")
                self?.handleResults(results, changes: changes)
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                logger.info("Browser state: \(String(describing: state))")
                self?.onStateChange?(state == .ready)
            }
        }

        browser?.start(queue: .main)
        logger.info("Browser started")
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
                logger.info("Service added: \(String(describing: result.endpoint))")
                if case let .service(name, _, _, _) = result.endpoint {
                    let device = DiscoveredDevice(
                        id: name,
                        name: name,
                        endpoint: result.endpoint
                    )
                    discoveredDevices[name] = device
                    logger.info("Device found: \(name)")
                    onDeviceFound?(device)
                }
            case .removed(let result):
                logger.info("Service removed: \(String(describing: result.endpoint))")
                if case let .service(name, _, _, _) = result.endpoint {
                    if let device = discoveredDevices.removeValue(forKey: name) {
                        logger.info("Device lost: \(name)")
                        onDeviceLost?(device)
                    }
                }
            case .changed(let old, let new, _):
                logger.info("Service changed: \(String(describing: old.endpoint)) -> \(String(describing: new.endpoint))")
            case .identical:
                break
            @unknown default:
                logger.warning("Unknown change type")
            }
        }
    }
}
