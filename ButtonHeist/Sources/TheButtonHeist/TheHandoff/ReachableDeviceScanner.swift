import Foundation

/// Probes discovered devices until it can return the currently reachable subset.
@ButtonHeistActor
struct ReachableDeviceScanner {
    let getDiscoveredDevices: () -> [DiscoveredDevice]
    var token: String?

    func scan(
        timeout: TimeInterval = 3.0,
        probeTimeout: TimeInterval = 0.5,
        retryInterval: TimeInterval = 0.2
    ) async -> [DiscoveredDevice] {
        let deadline = Date().addingTimeInterval(timeout)
        var reachableIDs: Set<String> = []
        var nextProbeAt: [String: Date] = [:]

        while Date() < deadline {
            let snapshot = getDiscoveredDevices()
            let currentIDs = Set(snapshot.map(\.id))
            reachableIDs = reachableIDs.filter { currentIDs.contains($0) }
            nextProbeAt = nextProbeAt.filter { currentIDs.contains($0.key) }

            let dueDevices = devicesReadyForProbe(
                in: snapshot,
                reachableIDs: reachableIDs,
                nextProbeAt: nextProbeAt
            )

            if !dueDevices.isEmpty {
                let retryAt = Date().addingTimeInterval(retryInterval)
                let reachable = await dueDevices.reachable(token: token, timeout: probeTimeout)
                let reachableDeviceIDs = Set(reachable.map(\.id))
                for device in dueDevices {
                    if reachableDeviceIDs.contains(device.id) {
                        reachableIDs.insert(device.id)
                        nextProbeAt.removeValue(forKey: device.id)
                    } else {
                        nextProbeAt[device.id] = retryAt
                    }
                }
            }

            guard await Task.cancellableSleep(for: .milliseconds(100)) else { break }
        }

        return getDiscoveredDevices().filter { reachableIDs.contains($0.id) }
    }

    private func devicesReadyForProbe(
        in devices: [DiscoveredDevice],
        reachableIDs: Set<String>,
        nextProbeAt: [String: Date]
    ) -> [DiscoveredDevice] {
        let now = Date()
        return devices.filter { device in
            !reachableIDs.contains(device.id) &&
                (nextProbeAt[device.id] ?? .distantPast) <= now
        }
    }
}
