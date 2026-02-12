import Foundation
import Network
import TheGoods
import os.log

private let logger = Logger(subsystem: "com.buttonheist.wheelman", category: "discovery")

@MainActor
public final class DeviceDiscovery {

    private var browser: NWBrowser?
    private var discoveredDevices: [String: DiscoveredDevice] = [:]

    public var onDeviceFound: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?
    public var onStateChange: ((Bool) -> Void)?

    public init() {}

    public func start() {
        logger.info("Starting Bonjour discovery for type: \(buttonHeistServiceType)")

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: buttonHeistServiceType, domain: "local."),
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

    public func stop() {
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
