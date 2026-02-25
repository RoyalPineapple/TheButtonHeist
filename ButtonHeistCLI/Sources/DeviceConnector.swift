import Foundation
import ButtonHeist

@MainActor
final class DeviceConnector {
    let client = TheClient()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64

    init(deviceFilter: String?,
         token: String? = nil, quiet: Bool = false, force: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
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

    /// Connect to a device via Bonjour discovery.
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
        client.onDisconnected = { error in if connectionError == nil { connectionError = error } }
        client.onTokenReceived = { token in
            // Always output — callers parse this for session reuse
            logStatus("BUTTONHEIST_TOKEN=\(token)")
        }
        client.onAuthFailed = { reason in
            connectionError = CLIError.authFailed(reason)
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
            throw error
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
    case authFailed(String)

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
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .connectionFailed(let msg):
            return """
                Connection failed: \(msg)
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .sessionLocked(let msg):
            return """
                Session locked: \(msg)
                  Another driver is currently connected. Wait for it to finish,
                  or use --force to take over the session.
                """
        case .authFailed(let msg):
            return """
                Auth failed: \(msg)
                  Retry without --token to request a fresh session.
                """
        }
    }

    var exitCode: Int32 {
        switch self {
        case .authFailed: return ExitCode.authFailed.rawValue
        case .sessionLocked: return ExitCode.connectionFailed.rawValue
        case .noDeviceFound, .noMatchingDevice: return ExitCode.noDeviceFound.rawValue
        case .connectionTimeout: return ExitCode.timeout.rawValue
        case .connectionFailed: return ExitCode.connectionFailed.rawValue
        }
    }
}
