import Foundation
import ButtonHeist

@ButtonHeistActor
final class DeviceConnector {
    let client = TheMastermind()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64

    init(deviceFilter: String?,
         token: String? = nil, quiet: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
        self.deviceFilter = deviceFilter
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
        self.quiet = quiet
        self.discoveryTimeout = UInt64(discoveryTimeout * 1_000_000_000)
        self.connectionTimeout = UInt64(connectionTimeout * 1_000_000_000)
        self.client.token = token ?? ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
        self.client.driverId = ProcessInfo.processInfo.environment["BUTTONHEIST_DRIVER_ID"]
        self.client.autoSubscribe = false
    }

    /// Connect to a device via Bonjour discovery.
    func connect() async throws {
        if !quiet { logStatus("Searching for iOS devices...") }
        client.startDiscovery()

        let device = try await resolveReachableDevice()

        if !quiet {
            logStatus("Found: \(client.displayName(for: device))")
        }

        try await connectToDevice(device)
    }

    func disconnect() {
        client.disconnect()
        client.stopDiscovery()
    }

    // MARK: - Private

    private func resolveReachableDevice() async throws -> DiscoveredDevice {
        if let directDevice = directConnectDevice(from: deviceFilter) {
            return directDevice
        }

        let start = DispatchTime.now().uptimeNanoseconds
        var lastSignature = ""
        var stableAt = start
        var probedSignature: String?

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            let discovered = client.discoveredDevices
            let signature = discoverySignature(for: discovered)

            if signature != lastSignature {
                lastSignature = signature
                stableAt = now
            }

            let stabilized = !discovered.isEmpty && now - stableAt >= 500_000_000
            if stabilized && probedSignature != signature {
                let reachable = await discovered.reachable()
                if let device = selectDevice(from: reachable) {
                    return device
                }
                probedSignature = signature
            }

            if now - start > discoveryTimeout {
                return try await finalDeviceSelection()
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func finalDeviceSelection() async throws -> DiscoveredDevice {
        let reachable = await client.discoveredDevices.reachable()
        if let device = selectDevice(from: reachable) {
            return device
        }

        if let filter = deviceFilter {
            throw FenceError.noMatchingDevice(
                filter: filter,
                available: reachable.map(\.name)
            )
        }

        throw FenceError.noDeviceFound
    }

    private func selectDevice(from devices: [DiscoveredDevice]) -> DiscoveredDevice? {
        if let filter = deviceFilter {
            return devices.first(matching: filter)
        }

        guard devices.count == 1 else {
            return nil
        }

        return devices[0]
    }

    private func discoverySignature(for devices: [DiscoveredDevice]) -> String {
        devices.map(\.id).sorted().joined(separator: "|")
    }

    private func directConnectDevice(from filter: String?) -> DiscoveredDevice? {
        guard let filter else { return nil }
        guard let separator = filter.lastIndex(of: ":") else { return nil }

        let host = String(filter[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let portString = String(filter[filter.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty,
              let port = UInt16(portString),
              port > 0 else {
            return nil
        }

        return DiscoveredDevice(host: host, port: port)
    }

    private func connectToDevice(_ device: DiscoveredDevice) async throws {
        if !quiet { logStatus("Connecting...") }

        var connected = false
        var connectionError: Error?
        client.onConnected = { _ in connected = true }
        client.onDisconnected = { reason in if connectionError == nil { connectionError = reason } }
        client.onAuthApproved = { token in
            if let token {
                logStatus("BUTTONHEIST_TOKEN=\(token)")
            }
        }
        client.onAuthFailed = { reason in
            connectionError = FenceError.authFailed(reason)
        }
        client.onSessionLocked = { payload in
            connectionError = FenceError.sessionLocked(payload.message)
        }
        client.connect(to: device)

        let connStart = DispatchTime.now()
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connStart.uptimeNanoseconds > connectionTimeout {
                throw FenceError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let error = connectionError {
            throw error
        }

        if !quiet { logStatus("Connected") }
    }
}
