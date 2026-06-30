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

    private enum HandoffDiscoveryPhase {
        case idle
        case starting(DiscoverySession)
        case ready(DiscoverySession, devices: [DiscoveredDevice])
        case waiting(DiscoverySession, devices: [DiscoveredDevice])
        case failed(HandoffConnectionError)
    }

    private var phase: HandoffDiscoveryPhase = .idle

    var discoveredDevices: [DiscoveredDevice] {
        switch phase {
        case .ready(_, let devices), .waiting(_, let devices):
            return devices
        case .idle, .starting, .failed:
            return []
        }
    }

    var isDiscovering: Bool {
        if case .ready = phase { return true }
        return false
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
        phase = .starting(session)
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
        case .starting(let session),
             .ready(let session, _),
             .waiting(let session, _):
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
            replaceDevicesWithCurrentDiscoveryProjection()
            onDeviceFound(device)
        case .lost(let device):
            discoveryLogger.info("Device lost: \(device.name)")
            replaceDevicesWithCurrentDiscoveryProjection()
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

    private func replaceDevicesWithCurrentDiscoveryProjection() {
        guard let session = currentSession else { return }
        let devices = session.discovery.discoveredDevices
        switch phase {
        case .ready:
            phase = .ready(session, devices: devices)
        case .starting, .waiting:
            phase = .waiting(session, devices: devices)
        case .idle, .failed:
            break
        }
    }

    private func replaceReadiness(_ isReady: Bool) {
        guard let session = currentSession else { return }
        let devices = session.discovery.discoveredDevices
        if isReady {
            phase = .ready(session, devices: devices)
        } else {
            phase = .waiting(session, devices: devices)
        }
    }
}
