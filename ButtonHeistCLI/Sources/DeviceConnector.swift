import Foundation
import Network
import ButtonHeist

@MainActor
final class DeviceConnector {
    let client = HeistClient()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64
    private let directHost: String?
    private let directPort: UInt16?

    init(deviceFilter: String?, host: String? = nil, port: UInt16? = nil,
         token: String? = nil, quiet: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
        // Flags override env vars
        self.directHost = host
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_HOST"]
        self.directPort = port
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_PORT"].flatMap { UInt16($0) }
        self.deviceFilter = deviceFilter
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
        self.quiet = quiet
        self.discoveryTimeout = UInt64(discoveryTimeout * 1_000_000_000)
        self.connectionTimeout = UInt64(connectionTimeout * 1_000_000_000)
        self.client.token = token ?? ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
    }

    /// Connect to a device — direct if host/port are set, otherwise via Bonjour discovery.
    func connect() async throws {
        if let host = directHost, let port = directPort {
            // Direct connection — skip Bonjour entirely
            if !quiet { logStatus("Connecting to \(host):\(port)...") }
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: port)
            )
            let device = DiscoveredDevice(
                id: "\(host):\(port)",
                name: "\(host):\(port)",
                endpoint: endpoint
            )
            try await connectToDevice(device)
            return
        }

        // Bonjour discovery path
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
        }

        try await connectToDevice(device)
    }

    func disconnect() {
        client.disconnect()
        client.stopDiscovery()
    }

    // MARK: - Private

    private func connectToDevice(_ device: DiscoveredDevice) async throws {
        if !quiet { logStatus("Connecting...") }

        var connected = false
        var connectionError: Error?
        client.onConnected = { _ in connected = true }
        client.onDisconnected = { error in connectionError = error }
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
