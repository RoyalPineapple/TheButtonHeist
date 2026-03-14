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
        let resolver = DeviceResolver(
            filter: deviceFilter,
            discoveryTimeout: discoveryTimeout,
            getDiscoveredDevices: { [client] in client.discoveredDevices }
        )
        do {
            return try await resolver.resolve()
        } catch let error as DeviceResolver.ResolutionError {
            switch error {
            case .noDeviceFound:
                throw FenceError.noDeviceFound
            case .noMatchingDevice(let filter, let available):
                throw FenceError.noMatchingDevice(filter: filter, available: available)
            }
        }
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
