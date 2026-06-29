import Foundation
import Network
import os.log

import TheScore

private let logger = ButtonHeistLog.logger(.handoff(.discovery))

/// Discovers Button Heist services via Bonjour and emits device found/lost events.
@ButtonHeistActor
final class DeviceDiscovery: DeviceDiscovering {

    private enum DiscoveryPhase {
        case idle
        case active(
            id: UUID,
            browser: NWBrowser,
            registry: DiscoveryRegistry,
            reachabilityTask: Task<Void, Never>?
        )
    }

    private var discoveryPhase: DiscoveryPhase = .idle
    private let browserQueue = DispatchQueue(label: "com.buttonheist.thehandoff.discovery.browser")
    private let reachabilityValidationInterval: TimeInterval

    var discoveredDevices: [DiscoveredDevice] {
        switch discoveryPhase {
        case .idle:
            return []
        case .active(_, _, let registry, _):
            return registry.devices
        }
    }

    var onEvent: (@ButtonHeistActor (DiscoveryEvent) -> Void)?

    init(reachabilityValidationInterval: TimeInterval = 3.0) {
        self.reachabilityValidationInterval = reachabilityValidationInterval
    }

    func start() {
        logger.info("Starting Bonjour discovery for type: \(buttonHeistServiceType)")

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let sessionID = UUID()
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: buttonHeistServiceType, domain: "local."),
            using: parameters
        )

        browser.browseResultsChangedHandler = { [weak self, sessionID] results, changes in
            Task { [weak self, sessionID] in
                logger.info("Results changed: \(results.count) results, \(changes.count) changes")
                await self?.handleResults(results, changes: changes, sessionID: sessionID)
            }
        }

        browser.stateUpdateHandler = { [weak self, sessionID] state in
            Task { [weak self, sessionID] in
                logger.info("Browser state: \(String(describing: state))")
                await self?.handleStateUpdate(state, sessionID: sessionID)
            }
        }

        discoveryPhase = .active(
            id: sessionID,
            browser: browser,
            registry: DiscoveryRegistry(),
            reachabilityTask: nil
        )
        browser.start(queue: browserQueue)
        startReachabilityValidation(sessionID: sessionID)
        logger.info("Browser started")
    }

    func stop() {
        guard case .active(_, let browser, _, let reachabilityTask) = discoveryPhase else { return }
        reachabilityTask?.cancel()
        browser.cancel()
        discoveryPhase = .idle
    }

    private func handleStateUpdate(_ state: NWBrowser.State, sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        onEvent?(.stateChanged(isReady: state == .ready))
    }

    private func handleResults(
        _ results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>,
        sessionID: UUID
    ) {
        guard case .active(let activeSessionID, let browser, var registry, let reachabilityTask) = discoveryPhase,
              activeSessionID == sessionID else { return }
        for change in changes {
            switch change {
            case .added(let result):
                logger.info("Service added: \(String(describing: result.endpoint))")
                if let device = makeDevice(from: result) {
                    logger.info("Device found: \(device.name)")
                    let mutations = registry.recordFound(device)
                    discoveryPhase = .active(
                        id: sessionID,
                        browser: browser,
                        registry: registry,
                        reachabilityTask: reachabilityTask
                    )
                    apply(mutations)
                }
            case .removed(let result):
                logger.info("Service removed: \(String(describing: result.endpoint))")
                if case let .service(name, _, _, _) = result.endpoint {
                    let mutations = registry.recordLost(DiscoveryServiceName(name))
                    discoveryPhase = .active(
                        id: sessionID,
                        browser: browser,
                        registry: registry,
                        reachabilityTask: reachabilityTask
                    )
                    apply(mutations)
                }
            case .changed(let old, let new, _):
                logger.info("Service changed: \(String(describing: old.endpoint)) -> \(String(describing: new.endpoint))")
                if case let .service(oldName, _, _, _) = old.endpoint,
                   case let .service(newName, _, _, _) = new.endpoint,
                   oldName != newName {
                    let mutations = registry.recordLost(DiscoveryServiceName(oldName))
                    discoveryPhase = .active(
                        id: sessionID,
                        browser: browser,
                        registry: registry,
                        reachabilityTask: reachabilityTask
                    )
                    apply(mutations)
                }
                if let device = makeDevice(from: new) {
                    let mutations = registry.recordFound(device)
                    discoveryPhase = .active(
                        id: sessionID,
                        browser: browser,
                        registry: registry,
                        reachabilityTask: reachabilityTask
                    )
                    apply(mutations)
                }
            case .identical:
                break
            @unknown default:
                logger.warning("Unknown change type")
            }
        }
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

    private func startReachabilityValidation(sessionID: UUID) {
        guard case .active(let activeSessionID, let browser, let registry, let existingTask) = discoveryPhase,
              activeSessionID == sessionID else { return }
        existingTask?.cancel()
        let task = Task { [weak self, sessionID] in
            while !Task.isCancelled {
                guard let self else { return }
                guard await Task.cancellableSleep(for: .seconds(self.reachabilityValidationInterval)) else { return }
                guard !Task.isCancelled else { return }
                await self.validateVisibleDevicesReachability(sessionID: sessionID)
            }
        }
        discoveryPhase = .active(id: sessionID, browser: browser, registry: registry, reachabilityTask: task)
    }

    private func validateVisibleDevicesReachability(sessionID: UUID) async {
        guard case .active(let activeSessionID, _, let registry, _) = discoveryPhase,
              activeSessionID == sessionID else { return }
        let visibleDevices = registry.devices
        guard !visibleDevices.isEmpty else { return }

        let unreachableServiceNames = await withTaskGroup(of: String?.self) { group in
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

        guard case .active(let activeSessionID, let currentBrowser, var currentRegistry, let currentReachabilityTask) = discoveryPhase,
              activeSessionID == sessionID else {
            return
        }
        for serviceName in unreachableServiceNames {
            logger.info("Evicting unreachable device advertisement: \(serviceName)")
            let mutations = currentRegistry.recordLost(DiscoveryServiceName(serviceName))
            discoveryPhase = .active(
                id: sessionID,
                browser: currentBrowser,
                registry: currentRegistry,
                reachabilityTask: currentReachabilityTask
            )
            apply(mutations)
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        guard case .active(let activeSessionID, _, _, _) = discoveryPhase else { return false }
        return activeSessionID == sessionID
    }
}
