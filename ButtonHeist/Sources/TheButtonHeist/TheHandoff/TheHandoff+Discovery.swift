import Foundation
import os.log

import TheScore

private let handoffDiscoveryLogger = ButtonHeistLog.logger(.handoff(.discovery))

@ButtonHeistActor
extension TheHandoff {
    func startDiscovery() {
        handoffDiscoveryLogger.info("startDiscovery called, hasSession=\(self.hasActiveDiscoverySession)")
        guard !discoveryLifecycle.hasDiscoverySession else {
            handoffDiscoveryLogger.info("Already discovering, skipping")
            return
        }

        discoveryLifecycle.start(
            makeDiscovery: makeDiscovery,
            onDeviceFound: { [weak self] device in self?.onDeviceFound?(device) },
            onDeviceLost: { [weak self] device in self?.onDeviceLost?(device) }
        )
        handoffDiscoveryLogger.info("Discovery started")
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
        let startedTemporaryDiscovery = !hasActiveDiscoverySession
        if startedTemporaryDiscovery {
            startDiscovery()
        }
        defer {
            if startedTemporaryDiscovery {
                stopDiscovery()
            }
        }

        return await ReachableDeviceScanner(getDiscoveredDevices: { [weak self] in
            self?.discoveredDevices ?? []
        }, token: token).scan(
            timeout: timeout,
            probeTimeout: probeTimeout,
            retryInterval: retryInterval
        )
    }
}
