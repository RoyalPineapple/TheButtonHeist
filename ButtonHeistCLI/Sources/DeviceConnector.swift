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
         token: String? = nil, quiet: Bool = false, force: Bool = false,
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
        self.client.forceSession = force
        self.client.driverId = ProcessInfo.processInfo.environment["BUTTONHEIST_DRIVER_ID"]
        self.client.autoSubscribe = false
    }

    /// Connect to a device — direct if host/port are set, otherwise via Bonjour discovery.
    func connect() async throws {
        warnIfPartialDirectConfig(host: directHost, port: directPort, quiet: quiet)

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
            do {
                try await connectToDevice(device)
            } catch {
                if !quiet {
                    await discoverAndReport(client: client)
                }
                throw error
            }
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
        client.onTokenReceived = { [quiet] token in
            if !quiet {
                logStatus("Received auth token from device")
                logStatus("Set BUTTONHEIST_TOKEN=\(token) for future connections")
            }
        }
        client.onSessionLocked = { payload in
            connectionError = CLIError.sessionLocked(payload.message)
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
    case sessionLocked(String)

    var description: String {
        switch self {
        case .noDeviceFound:
            return "No devices found within timeout. Is the app running?"
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return "No device matching '\(filter)'. Available: \(list)"
        case .connectionTimeout:
            return """
                Connection timed out
                  Hint: Verify the host address is correct and the app is running.
                """
        case .connectionFailed(let msg):
            let lower = msg.lowercased()
            if lower.contains("refused") {
                return """
                    Connection failed: \(msg)
                      Hint: Connection refused usually means wrong port or the app isn't running.
                    """
            }
            return """
                Connection failed: \(msg)
                  Hint: Check that the host and port are correct and the app is running.
                """
        case .sessionLocked(let msg):
            return """
                Session locked: \(msg)
                  Another driver is currently connected. Wait for it to finish,
                  or use --force to take over the session.
                """
        }
    }
}

/// Run a quick Bonjour scan and log any discovered devices to stderr.
/// Call after a direct connection failure to give the user immediate context.
@MainActor
func discoverAndReport(client: HeistClient, seconds: UInt64 = 3) async {
    logStatus("  Scanning for devices via Bonjour...")
    client.startDiscovery()
    try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
    let devices = client.discoveredDevices
    client.stopDiscovery()

    if devices.isEmpty {
        logStatus("  No devices found via Bonjour either — is the app running?")
    } else {
        logStatus("  Devices found via Bonjour:")
        for device in devices {
            let name = device.deviceName.isEmpty
                ? device.appName
                : "\(device.appName) on \(device.deviceName)"
            logStatus("    - \(name)")
        }
        logStatus("  Try connecting without --host/--port to use Bonjour discovery.")
    }
}

/// Emit a stderr warning when only one of host/port is configured.
/// Call before the `if let host, let port` branch in each connection path.
func warnIfPartialDirectConfig(host: String?, port: UInt16?, quiet: Bool) {
    guard !quiet else { return }
    if host != nil && port == nil {
        logStatus("Warning: --host is set but --port is missing. Falling back to Bonjour discovery.")
        logStatus("  Hint: Set both BUTTONHEIST_HOST and BUTTONHEIST_PORT for direct connection.")
    } else if host == nil && port != nil {
        logStatus("Warning: --port is set but --host is missing. Falling back to Bonjour discovery.")
        logStatus("  Hint: Set both BUTTONHEIST_HOST and BUTTONHEIST_PORT for direct connection.")
    }
}
