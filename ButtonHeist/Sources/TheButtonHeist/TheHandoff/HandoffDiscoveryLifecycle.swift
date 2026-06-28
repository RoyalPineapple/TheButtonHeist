import Foundation
import os.log

import TheScore

private let discoveryLogger = ButtonHeistLog.logger(.handoff(.discovery))

/// Discovery lifecycle invariant: only callbacks from the current live discovery session can mutate the discovery projection.
@ButtonHeistActor
final class HandoffDiscoveryLifecycle {

    private struct DiscoverySession {
        let id: UUID
        let discovery: any DeviceDiscovering
    }

    private var discoverySession: DiscoverySession?

    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var isDiscovering = false

    var hasDiscoverySession: Bool {
        discoverySession != nil
    }

    @discardableResult
    func start(
        makeDiscovery: () -> any DeviceDiscovering,
        onDeviceFound: @escaping @ButtonHeistActor (DiscoveredDevice) -> Void,
        onDeviceLost: @escaping @ButtonHeistActor (DiscoveredDevice) -> Void
    ) -> Bool {
        guard discoverySession == nil else { return false }

        discoveredDevices.removeAll()
        isDiscovering = false

        let sessionID = UUID()
        let activeDiscovery = makeDiscovery()
        discoverySession = DiscoverySession(id: sessionID, discovery: activeDiscovery)
        activeDiscovery.onEvent = { [weak self, sessionID] event in
            guard let self, self.isCurrentSession(sessionID) else { return }
            self.handle(event, onDeviceFound: onDeviceFound, onDeviceLost: onDeviceLost)
        }
        activeDiscovery.start()
        return true
    }

    func stop() {
        let activeDiscovery = discoverySession?.discovery
        discoverySession = nil
        isDiscovering = false
        discoveredDevices = []
        activeDiscovery?.stop()
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        discoverySession?.id == sessionID
    }

    private func handle(
        _ event: DiscoveryEvent,
        onDeviceFound: @ButtonHeistActor (DiscoveredDevice) -> Void,
        onDeviceLost: @ButtonHeistActor (DiscoveredDevice) -> Void
    ) {
        switch event {
        case .found(let device):
            discoveryLogger.info("Device found: \(device.name)")
            discoveredDevices = discoverySession?.discovery.discoveredDevices ?? []
            onDeviceFound(device)
        case .lost(let device):
            discoveryLogger.info("Device lost: \(device.name)")
            discoveredDevices = discoverySession?.discovery.discoveredDevices ?? []
            onDeviceLost(device)
        case .stateChanged(let isReady):
            discoveryLogger.info("Discovery state changed: isReady=\(isReady)")
            isDiscovering = isReady
        }
    }
}
