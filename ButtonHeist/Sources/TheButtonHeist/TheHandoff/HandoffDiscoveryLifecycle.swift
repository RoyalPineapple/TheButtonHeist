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

    private enum DiscoveryReadiness {
        case waiting
        case ready
    }

    private enum HandoffDiscoveryPhase {
        case idle
        case active(DiscoverySession, readiness: DiscoveryReadiness)
        case failed(HandoffConnectionError)
    }

    private var phase: HandoffDiscoveryPhase = .idle

    var discoveredDevices: [DiscoveredDevice] {
        currentSession?.discovery.discoveredDevices ?? []
    }

    var isDiscovering: Bool {
        guard case .active(_, .ready) = phase else { return false }
        return true
    }

    var hasDiscoverySession: Bool {
        currentSession != nil
    }

    @discardableResult
    func start(
        makeDiscovery: () -> any DeviceDiscovering,
        onDeviceFound: @escaping @ButtonHeistActor (DiscoveredDevice) -> Void,
        onDeviceLost: @escaping @ButtonHeistActor (DiscoveredDevice) -> Void
    ) -> Bool {
        guard currentSession == nil else { return false }

        let sessionID = UUID()
        let activeDiscovery = makeDiscovery()
        let session = DiscoverySession(id: sessionID, discovery: activeDiscovery)
        phase = .active(session, readiness: .waiting)
        activeDiscovery.onEvent = { [weak self, sessionID] event in
            guard let self, self.isCurrentSession(sessionID) else { return }
            self.handle(event, onDeviceFound: onDeviceFound, onDeviceLost: onDeviceLost)
        }
        activeDiscovery.start()
        return true
    }

    func stop() {
        let activeDiscovery = currentSession?.discovery
        phase = .idle
        activeDiscovery?.stop()
    }

    private var currentSession: DiscoverySession? {
        switch phase {
        case .active(let session, _):
            return session
        case .idle, .failed:
            return nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        currentSession?.id == sessionID
    }

    private func handle(
        _ event: DiscoveryEvent,
        onDeviceFound: @ButtonHeistActor (DiscoveredDevice) -> Void,
        onDeviceLost: @ButtonHeistActor (DiscoveredDevice) -> Void
    ) {
        switch event {
        case .found(let device):
            discoveryLogger.info("Device found: \(device.name)")
            onDeviceFound(device)
        case .lost(let device):
            discoveryLogger.info("Device lost: \(device.name)")
            onDeviceLost(device)
        case .stateChanged(let isReady):
            discoveryLogger.info("Discovery state changed: isReady=\(isReady)")
            replaceReadiness(isReady)
        case .failed(let failure):
            discoveryLogger.error("Discovery failed: \(failure.localizedDescription)")
            let activeDiscovery = currentSession?.discovery
            phase = .failed(failure)
            activeDiscovery?.stop()
        }
    }

    private func replaceReadiness(_ isReady: Bool) {
        guard let session = currentSession else { return }
        let readiness: DiscoveryReadiness = isReady ? .ready : .waiting
        phase = .active(session, readiness: readiness)
    }
}
