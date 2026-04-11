import Foundation

/// Encapsulates the stabilize-then-probe device resolution algorithm.
/// Used by both TheHandoff (framework) and DeviceConnector (CLI) to avoid duplication.
@ButtonHeistActor
public struct DeviceResolver {
    public let filter: String?
    public let discoveryTimeout: UInt64
    public let getDiscoveredDevices: () -> [DiscoveredDevice]

    public init(
        filter: String?,
        discoveryTimeout: UInt64,
        getDiscoveredDevices: @escaping () -> [DiscoveredDevice]
    ) {
        self.filter = filter
        self.discoveryTimeout = discoveryTimeout
        self.getDiscoveredDevices = getDiscoveredDevices
    }

    public func resolve() async throws -> DiscoveredDevice {
        if let directDevice = DiscoveredDevice.directConnectTarget(from: filter) {
            return directDevice
        }

        let start = DispatchTime.now().uptimeNanoseconds
        var lastSignature = ""
        var stableAt = start
        var lastProbeAt: UInt64?
        let probeInterval: UInt64 = 1_000_000_000

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            let discovered = getDiscoveredDevices()
            let signature = Self.discoverySignature(for: discovered)

            if signature != lastSignature {
                lastSignature = signature
                stableAt = now
            }

            let stabilized = !discovered.isEmpty && now - stableAt >= 500_000_000
            let shouldProbe = stabilized && (lastProbeAt == nil || now - (lastProbeAt ?? 0) >= probeInterval)
            if shouldProbe {
                lastProbeAt = now
                let reachable = await discovered.reachable()
                if let device = Self.selectDevice(from: reachable, filter: filter) {
                    return device
                }
                if filter == nil, reachable.count > 1 {
                    throw TheHandoff.ConnectionError.noMatchingDevice(
                        filter: "(none)",
                        available: reachable.map(\.name)
                    )
                }
            }

            if now - start > discoveryTimeout {
                return try await finalSelection()
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func finalSelection() async throws(TheHandoff.ConnectionError) -> DiscoveredDevice {
        let reachable = await getDiscoveredDevices().reachable()
        if let device = Self.selectDevice(from: reachable, filter: filter) {
            return device
        }

        if filter == nil, reachable.count > 1 {
            throw TheHandoff.ConnectionError.noMatchingDevice(
                filter: "(none)",
                available: reachable.map(\.name)
            )
        }

        if let filter {
            throw TheHandoff.ConnectionError.noMatchingDevice(
                filter: filter,
                available: reachable.map(\.name)
            )
        }

        throw TheHandoff.ConnectionError.noDeviceFound
    }

    static func selectDevice(from devices: [DiscoveredDevice], filter: String?) -> DiscoveredDevice? {
        if let filter {
            return devices.first(matching: filter)
        }
        guard devices.count == 1 else { return nil }
        return devices[0]
    }

    static func discoverySignature(for devices: [DiscoveredDevice]) -> String {
        devices.map(\.id).sorted().joined(separator: "|")
    }
}
