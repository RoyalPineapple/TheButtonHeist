import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "discovery")

enum DiscoveryMutation: Equatable {
    case found(DiscoveredDevice)
    case lost(DiscoveredDevice)
}

struct DiscoveryRegistry {
    struct Advertisement {
        let device: DiscoveredDevice
        let identity: String
        let sequence: UInt64
    }

    private var advertisementsByServiceName: [String: Advertisement] = [:]
    private var visibleServiceNameByIdentity: [String: String] = [:]
    private var nextSequence: UInt64 = 0

    var devices: [DiscoveredDevice] {
        visibleServiceNameByIdentity.values
            .compactMap { advertisementsByServiceName[$0] }
            .sorted { lhs, rhs in lhs.sequence > rhs.sequence }
            .map(\.device)
    }

    mutating func recordFound(_ device: DiscoveredDevice) -> [DiscoveryMutation] {
        nextSequence &+= 1

        let advertisement = Advertisement(
            device: device,
            identity: device.discoveryIdentity,
            sequence: nextSequence
        )
        advertisementsByServiceName[device.id] = advertisement

        let identity = advertisement.identity
        guard let visibleServiceName = visibleServiceNameByIdentity[identity] else {
            visibleServiceNameByIdentity[identity] = device.id
            return [.found(device)]
        }

        guard visibleServiceName != device.id else {
            visibleServiceNameByIdentity[identity] = device.id
            return []
        }

        if let previous = advertisementsByServiceName[visibleServiceName] {
            visibleServiceNameByIdentity[identity] = device.id
            return [.lost(previous.device), .found(device)]
        }

        visibleServiceNameByIdentity[identity] = device.id
        return [.found(device)]
    }

    mutating func recordLost(serviceName: String) -> [DiscoveryMutation] {
        guard let removed = advertisementsByServiceName.removeValue(forKey: serviceName) else {
            return []
        }

        let identity = removed.identity
        guard visibleServiceNameByIdentity[identity] == serviceName else {
            return []
        }

        if let replacement = newestAdvertisement(for: identity) {
            visibleServiceNameByIdentity[identity] = replacement.device.id
            return [.lost(removed.device), .found(replacement.device)]
        }

        visibleServiceNameByIdentity.removeValue(forKey: identity)
        return [.lost(removed.device)]
    }

    private func newestAdvertisement(for identity: String) -> Advertisement? {
        advertisementsByServiceName.values
            .filter { $0.identity == identity }
            .max { lhs, rhs in lhs.sequence < rhs.sequence }
    }
}

@ButtonHeistActor
public final class DeviceDiscovery: DeviceDiscovering {

    private var browser: NWBrowser?
    private var registry = DiscoveryRegistry()
    private var reachabilityTask: Task<Void, Never>?
    private let browserQueue = DispatchQueue(label: "com.buttonheist.thehandoff.discovery.browser")
    private let reachabilityValidationInterval: TimeInterval

    public var discoveredDevices: [DiscoveredDevice] {
        registry.devices
    }

    public var onEvent: ((DiscoveryEvent) -> Void)?

    public init(reachabilityValidationInterval: TimeInterval = 3.0) {
        self.reachabilityValidationInterval = reachabilityValidationInterval
    }

    public func start() {
        logger.info("Starting Bonjour discovery for type: \(buttonHeistServiceType)")

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: buttonHeistServiceType, domain: "local."),
            using: parameters
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { [weak self] in
                logger.info("Results changed: \(results.count) results, \(changes.count) changes")
                await self?.handleResults(results, changes: changes)
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                logger.info("Browser state: \(String(describing: state))")
                await self?.handleStateUpdate(state)
            }
        }

        browser?.start(queue: browserQueue)
        startReachabilityValidation()
        logger.info("Browser started")
    }

    public func stop() {
        reachabilityTask?.cancel()
        reachabilityTask = nil
        browser?.cancel()
        browser = nil
        registry = DiscoveryRegistry()
    }

    private func handleStateUpdate(_ state: NWBrowser.State) {
        onEvent?(.stateChanged(isReady: state == .ready))
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                logger.info("Service added: \(String(describing: result.endpoint))")
                if let device = makeDevice(from: result) {
                    logger.info("Device found: \(device.name)")
                    apply(registry.recordFound(device))
                }
            case .removed(let result):
                logger.info("Service removed: \(String(describing: result.endpoint))")
                if case let .service(name, _, _, _) = result.endpoint {
                    apply(registry.recordLost(serviceName: name))
                }
            case .changed(let old, let new, _):
                logger.info("Service changed: \(String(describing: old.endpoint)) -> \(String(describing: new.endpoint))")
                if case let .service(oldName, _, _, _) = old.endpoint,
                   case let .service(newName, _, _, _) = new.endpoint,
                   oldName != newName {
                    apply(registry.recordLost(serviceName: oldName))
                }
                if let device = makeDevice(from: new) {
                    apply(registry.recordFound(device))
                }
            case .identical:
                break
            @unknown default:
                logger.warning("Unknown change type")
            }
        }
    }

    private func makeDevice(from result: NWBrowser.Result) -> DiscoveredDevice? {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return nil
        }

        let txtRecord = result.endpoint.txtRecord ?? {
            if case .bonjour(let metadataTXTRecord) = result.metadata {
                return metadataTXTRecord
            }
            return nil
        }()

        var simUDID: String?
        var installationId: String?
        var displayDeviceName: String?
        var instanceId: String?
        var sessionActive: Bool?
        var certFingerprint: String?
        if let txtRecord {
            simUDID = txtRecord["simudid"]
            installationId = txtRecord["installationid"]
            displayDeviceName = txtRecord["devicename"]
            instanceId = txtRecord["instanceid"]
            certFingerprint = txtRecord["certfp"]
            if let value = txtRecord["sessionactive"] {
                sessionActive = value == "1"
            }
        }

        return DiscoveredDevice(
            id: name,
            name: name,
            endpoint: result.endpoint,
            simulatorUDID: simUDID,
            installationId: installationId,
            displayDeviceName: displayDeviceName,
            instanceId: instanceId,
            sessionActive: sessionActive,
            certFingerprint: certFingerprint
        )
    }

    private func apply(_ mutations: [DiscoveryMutation]) {
        for mutation in mutations {
            switch mutation {
            case .found(let device):
                onEvent?(.found(device))
            case .lost(let device):
                logger.info("Device lost: \(device.name)")
                onEvent?(.lost(device))
            }
        }
    }

    private func startReachabilityValidation() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.reachabilityValidationInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.validateVisibleDevicesReachability()
            }
        }
    }

    private func validateVisibleDevicesReachability() async {
        let visibleDevices = registry.devices
        guard !visibleDevices.isEmpty else { return }

        let unreachableServiceNames = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for device in visibleDevices {
                group.addTask {
                    await device.isReachable(timeout: 0.75) ? nil : device.id
                }
            }

            var unreachable: [String] = []
            for await serviceName in group {
                if let serviceName {
                    unreachable.append(serviceName)
                }
            }
            return unreachable
        }

        for serviceName in unreachableServiceNames {
            logger.info("Evicting unreachable device advertisement: \(serviceName)")
            apply(registry.recordLost(serviceName: serviceName))
        }
    }
}
