import Foundation

import TheScore

@ButtonHeistActor
extension TheHandoff {
    func startDiscovery() {
        guard !discoveryLifecycle.hasDiscoverySession else { return }

        discoveryLifecycle.start(
            makeDiscovery: makeDiscovery,
            onDeviceFound: { [weak self] device in self?.onDeviceFound?(device) },
            onDeviceLost: { [weak self] device in self?.onDeviceLost?(device) }
        )
    }

    func stopDiscovery() {
        discoveryLifecycle.stop()
    }

    /// Discover devices and validate each deduped advertisement as it appears.
    func discoverReachableDevices(
        timeout: TimeInterval = 3.0,
        probeTimeout: TimeInterval = 0.5,
        retryInterval: TimeInterval = 0.2
    ) async -> [DiscoveredDevice] {
        let startedTemporaryDiscovery = !discoveryLifecycle.hasDiscoverySession
        if startedTemporaryDiscovery {
            startDiscovery()
        }
        defer {
            if startedTemporaryDiscovery {
                stopDiscovery()
            }
        }

        return await ReachableDeviceScanner(getDiscoveredDevices: { [weak self] in
            self?.discoveryLifecycle.discoveredDevices ?? []
        }, token: serverMessageRouter.authToken).scan(
            timeout: timeout,
            probeTimeout: probeTimeout,
            retryInterval: retryInterval
        )
    }
}
