import Foundation
import os.log

private let discoveryLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "discovery")

/// Discovery lifecycle invariant: only callbacks from the current live discovery session can mutate the discovery projection.
@ButtonHeistActor
final class HandoffDiscoveryLifecycle {

    private struct ActiveSession {
        let id: UUID
        let discovery: any DeviceDiscovering
    }

    private var activeSession: ActiveSession?

    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var isDiscovering = false

    var hasActiveSession: Bool {
        activeSession != nil
    }

    @discardableResult
    func start(
        makeDiscovery: () -> any DeviceDiscovering,
        onDeviceFound: @escaping @ButtonHeistActor (DiscoveredDevice) -> Void,
        onDeviceLost: @escaping @ButtonHeistActor (DiscoveredDevice) -> Void
    ) -> Bool {
        guard activeSession == nil else { return false }

        discoveredDevices.removeAll()
        isDiscovering = false

        let sessionID = UUID()
        let activeDiscovery = makeDiscovery()
        activeSession = ActiveSession(id: sessionID, discovery: activeDiscovery)
        activeDiscovery.onEvent = { [weak self, sessionID] event in
            guard let self, self.isCurrentSession(sessionID) else { return }
            self.handle(event, onDeviceFound: onDeviceFound, onDeviceLost: onDeviceLost)
        }
        activeDiscovery.start()
        return true
    }

    func stop() {
        let activeDiscovery = activeSession?.discovery
        activeSession = nil
        isDiscovering = false
        discoveredDevices = []
        activeDiscovery?.stop()
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        activeSession?.id == sessionID
    }

    private func handle(
        _ event: DiscoveryEvent,
        onDeviceFound: @ButtonHeistActor (DiscoveredDevice) -> Void,
        onDeviceLost: @ButtonHeistActor (DiscoveredDevice) -> Void
    ) {
        switch event {
        case .found(let device):
            discoveryLogger.info("Device found: \(device.name)")
            discoveredDevices = activeSession?.discovery.discoveredDevices ?? []
            onDeviceFound(device)
        case .lost(let device):
            discoveryLogger.info("Device lost: \(device.name)")
            discoveredDevices = activeSession?.discovery.discoveredDevices ?? []
            onDeviceLost(device)
        case .stateChanged(let isReady):
            discoveryLogger.info("Discovery state changed: isReady=\(isReady)")
            isDiscovering = isReady
        }
    }
}
