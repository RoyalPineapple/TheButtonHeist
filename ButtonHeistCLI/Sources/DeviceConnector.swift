import Foundation
import ButtonHeist

@MainActor
final class DeviceConnector {
    let client = HeistClient()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64

    init(deviceFilter: String?, token: String? = nil, quiet: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
        self.deviceFilter = deviceFilter
        self.quiet = quiet
        self.discoveryTimeout = UInt64(discoveryTimeout * 1_000_000_000)
        self.connectionTimeout = UInt64(connectionTimeout * 1_000_000_000)
        self.client.token = token ?? ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
    }

    /// Discover devices, filter by --device if set, connect, and return
    func connect() async throws {
        if !quiet { logStatus("Searching for iOS devices...") }
        client.startDiscovery()

        // Wait for at least one matching device
        let startTime = DispatchTime.now()
        while matchingDevice() == nil {
            if DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds > discoveryTimeout {
                if let filter = deviceFilter {
                    throw CLIError.noMatchingDevice(filter: filter,
                        available: client.discoveredDevices.map { $0.name })
                }
                throw CLIError.noDeviceFound
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let device = matchingDevice() else {
            throw CLIError.noDeviceFound
        }

        if !quiet {
            logStatus("Found: \(client.displayName(for: device))")
            logStatus("Connecting...")
        }

        var connected = false
        var connectionError: Error?
        client.onConnected = { _ in connected = true }
        client.onDisconnected = { error in connectionError = error }
        client.onTokenReceived = { [quiet] token in
            if !quiet {
                logStatus("Received auth token from device")
                logStatus("Set BUTTONHEIST_TOKEN=\(token) for future connections")
            }
        }
        client.connect(to: device)

        let connStart = DispatchTime.now()
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connStart.uptimeNanoseconds > connectionTimeout {
                throw CLIError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let error = connectionError {
            throw CLIError.connectionFailed(error.localizedDescription)
        }

        if !quiet { logStatus("Connected") }
    }

    func disconnect() {
        client.disconnect()
        client.stopDiscovery()
    }

    /// Find first device matching the filter (or first device if no filter)
    private func matchingDevice() -> DiscoveredDevice? {
        client.discoveredDevices.first(matching: deviceFilter)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])
    case connectionTimeout
    case connectionFailed(String)

    var description: String {
        switch self {
        case .noDeviceFound:
            return "No devices found within timeout"
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return "No device matching '\(filter)'. Available: \(list)"
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        }
    }
}
