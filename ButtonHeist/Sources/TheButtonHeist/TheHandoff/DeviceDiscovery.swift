import Foundation
import ButtonHeistSupport
import Network
import os.log

import TheScore

private let logger = ButtonHeistLog.logger(.handoff(.discovery))

enum DeviceDiscoveryBrowserState: Equatable, Sendable {
    case setup
    case waiting
    case ready
    case failed(String)
    case cancelled
}

protocol DeviceDiscoveryBrowsing {
    func start(
        queue: DispatchQueue,
        onResultsChanged: @escaping @Sendable (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void,
        onStateChanged: @escaping @Sendable (DeviceDiscoveryBrowserState) -> Void
    )
    func cancel()
}

final class NWDeviceDiscoveryBrowser: DeviceDiscoveryBrowsing {
    private let browser: NWBrowser

    init() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: buttonHeistServiceType, domain: "local."),
            using: parameters
        )
    }

    func start(
        queue: DispatchQueue,
        onResultsChanged: @escaping @Sendable (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void,
        onStateChanged: @escaping @Sendable (DeviceDiscoveryBrowserState) -> Void
    ) {
        browser.browseResultsChangedHandler = onResultsChanged
        browser.stateUpdateHandler = { state in
            onStateChanged(Self.browserState(from: state))
        }
        browser.start(queue: queue)
    }

    func cancel() {
        browser.cancel()
    }

    private static func browserState(from state: NWBrowser.State) -> DeviceDiscoveryBrowserState {
        switch state {
        case .setup:
            return .setup
        case .waiting:
            return .waiting
        case .ready:
            return .ready
        case .failed(let error):
            return .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        @unknown default:
            return .failed(String(describing: state))
        }
    }
}

/// Discovers Button Heist services via Bonjour and emits device found/lost events.
@ButtonHeistActor
final class DeviceDiscovery: DeviceDiscovering {

    private enum DiscoveryPhase {
        case idle
        case active(ActiveDiscovery)
    }

    private struct ActiveDiscovery {
        let id: UUID
        let browser: any DeviceDiscoveryBrowsing
        let eventStream: DeviceDiscoveryEventStream
        let eventConsumerTask: Task<Void, Never>
        var registry: DiscoveryRegistry
        var reachabilityTask: Task<Void, Never>?
        var browserState: DeviceDiscoveryBrowserState

        func cancelOwnedTasks() {
            eventStream.finish()
            eventConsumerTask.cancel()
            reachabilityTask?.cancel()
        }
    }

    private var discoveryPhase: DiscoveryPhase = .idle
    private let browserQueue = DispatchQueue(label: "com.buttonheist.thehandoff.discovery.browser")
    private let reachabilityValidationInterval: TimeInterval
    private let makeBrowser: () -> any DeviceDiscoveryBrowsing

    var discoveredDevices: [DiscoveredDevice] {
        switch discoveryPhase {
        case .idle:
            return []
        case .active(let activeDiscovery):
            return activeDiscovery.registry.devices
        }
    }

    var onEvent: (@ButtonHeistActor (DiscoveryEvent) -> Void)?

    init(
        reachabilityValidationInterval: TimeInterval = 3.0,
        makeBrowser: @escaping () -> any DeviceDiscoveryBrowsing = { NWDeviceDiscoveryBrowser() }
    ) {
        self.reachabilityValidationInterval = reachabilityValidationInterval
        self.makeBrowser = makeBrowser
    }

    func start() {
        guard case .idle = discoveryPhase else {
            logger.info("Bonjour discovery is already active")
            return
        }
        logger.info("Starting Bonjour discovery for type: \(buttonHeistServiceType)")

        let sessionID = UUID()
        let browser = makeBrowser()
        let eventStream = DeviceDiscoveryEventStream()
        let eventConsumerTask = Task { @ButtonHeistActor [weak self, eventStream, sessionID] in
            for await event in eventStream.events {
                guard let self else { return }
                self.handleBrowserEvent(event, sessionID: sessionID)
            }
        }

        discoveryPhase = .active(ActiveDiscovery(
            id: sessionID,
            browser: browser,
            eventStream: eventStream,
            eventConsumerTask: eventConsumerTask,
            registry: DiscoveryRegistry(),
            reachabilityTask: nil,
            browserState: .setup
        ))
        browser.start(
            queue: browserQueue,
            onResultsChanged: { [eventStream] results, changes in
                eventStream.yield(.resultsChanged(results, changes: changes))
            },
            onStateChanged: { [eventStream] state in
                eventStream.yield(.stateChanged(state))
            }
        )
        logger.info("Browser started")
    }

    func stop() {
        guard case .active(let activeDiscovery) = discoveryPhase else { return }
        discoveryPhase = .idle
        activeDiscovery.cancelOwnedTasks()
        activeDiscovery.browser.cancel()
    }

    private func handleBrowserEvent(_ event: DeviceDiscoveryBrowserEvent, sessionID: UUID) {
        switch event {
        case .resultsChanged(let results, let changes):
            logger.info("Results changed: \(results.count) results, \(changes.count) changes")
            handleResults(results, changes: changes, sessionID: sessionID)
        case .stateChanged(let state):
            logger.info("Browser state: \(String(describing: state))")
            handleStateUpdate(state, sessionID: sessionID)
        }
    }

    private func handleStateUpdate(_ state: DeviceDiscoveryBrowserState, sessionID: UUID) {
        guard case .active(var activeDiscovery) = discoveryPhase,
              activeDiscovery.id == sessionID else { return }

        switch state {
        case .ready:
            activeDiscovery.browserState = .ready
            discoveryPhase = .active(activeDiscovery)
            onEvent?(.stateChanged(isReady: true))
            startReachabilityValidation(sessionID: sessionID)
        case .setup, .waiting:
            activeDiscovery.browserState = state
            activeDiscovery.reachabilityTask?.cancel()
            activeDiscovery.reachabilityTask = nil
            discoveryPhase = .active(activeDiscovery)
            onEvent?(.stateChanged(isReady: false))
        case .failed(let description):
            finishTerminalBrowserState(
                activeDiscovery,
                failure: .connectionFailed("Bonjour discovery failed: \(description)"),
                cancelBrowser: true
            )
        case .cancelled:
            finishTerminalBrowserState(
                activeDiscovery,
                failure: .connectionFailed("Bonjour discovery was cancelled"),
                cancelBrowser: false
            )
        }
    }

    private func finishTerminalBrowserState(
        _ activeDiscovery: ActiveDiscovery,
        failure: HandoffConnectionError,
        cancelBrowser: Bool
    ) {
        activeDiscovery.cancelOwnedTasks()
        if cancelBrowser {
            activeDiscovery.browser.cancel()
        }
        discoveryPhase = .idle
        onEvent?(.failed(failure))
    }

    private func handleResults(
        _ results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>,
        sessionID: UUID
    ) {
        guard case .active(var activeDiscovery) = discoveryPhase,
              activeDiscovery.id == sessionID else { return }
        for change in changes {
            switch change {
            case .added(let result):
                logger.info("Service added: \(String(describing: result.endpoint))")
                if let device = makeDevice(from: result) {
                    logger.info("Device found: \(device.name)")
                    let mutations = activeDiscovery.registry.recordFound(device)
                    discoveryPhase = .active(activeDiscovery)
                    apply(mutations)
                }
            case .removed(let result):
                logger.info("Service removed: \(String(describing: result.endpoint))")
                if case let .service(name, _, _, _) = result.endpoint,
                   let deviceID = try? DiscoveryDeviceID(validating: name) {
                    let mutations = activeDiscovery.registry.recordLost(deviceID)
                    discoveryPhase = .active(activeDiscovery)
                    apply(mutations)
                }
            case .changed(let old, let new, _):
                logger.info("Service changed: \(String(describing: old.endpoint)) -> \(String(describing: new.endpoint))")
                if case let .service(oldName, _, _, _) = old.endpoint,
                   case let .service(newName, _, _, _) = new.endpoint,
                   oldName != newName,
                   let oldDeviceID = try? DiscoveryDeviceID(validating: oldName) {
                    let mutations = activeDiscovery.registry.recordLost(oldDeviceID)
                    discoveryPhase = .active(activeDiscovery)
                    apply(mutations)
                }
                if let device = makeDevice(from: new) {
                    let mutations = activeDiscovery.registry.recordFound(device)
                    discoveryPhase = .active(activeDiscovery)
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
        guard case .active(var activeDiscovery) = discoveryPhase,
              activeDiscovery.id == sessionID,
              activeDiscovery.browserState == .ready else { return }
        activeDiscovery.reachabilityTask?.cancel()
        let task = Task { [weak self, sessionID] in
            while !Task.isCancelled {
                guard let self else { return }
                guard await Task.cancellableSleep(for: .seconds(self.reachabilityValidationInterval)) else { return }
                guard !Task.isCancelled else { return }
                await self.validateVisibleDevicesReachability(sessionID: sessionID)
            }
        }
        activeDiscovery.reachabilityTask = task
        discoveryPhase = .active(activeDiscovery)
    }

    private func validateVisibleDevicesReachability(sessionID: UUID) async {
        guard case .active(let activeDiscovery) = discoveryPhase,
              activeDiscovery.id == sessionID,
              activeDiscovery.browserState == .ready else { return }
        let visibleDevices = activeDiscovery.registry.devices
        guard !visibleDevices.isEmpty else { return }

        let unreachableDeviceIDs = await withTaskGroup(of: DiscoveryDeviceID?.self) { group in
            for device in visibleDevices {
                group.addTask {
                    await device.isReachable(timeout: 0.75) ? nil : device.id
                }
            }

            var unreachable: [DiscoveryDeviceID] = []
            for await deviceID in group {
                if let deviceID {
                    unreachable.append(deviceID)
                }
            }
            return unreachable
        }

        guard case .active(var activeDiscovery) = discoveryPhase,
              activeDiscovery.id == sessionID else {
            return
        }
        for deviceID in unreachableDeviceIDs {
            logger.info("Evicting unreachable device advertisement: \(deviceID)")
            let mutations = activeDiscovery.registry.recordLost(deviceID)
            discoveryPhase = .active(activeDiscovery)
            apply(mutations)
        }
    }
}
