import Foundation
import Network
import os
import TheScore

private let reachabilityLogger = Logger(subsystem: "com.buttonheist.thewheelman", category: "reachability")

/// A discovered iOS device running TheInsideJob
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint
    /// Simulator UDID from Bonjour TXT record (nil on physical devices)
    public let simulatorUDID: String?
    /// Stable installation identifier from Bonjour TXT record
    public let installationId: String?
    /// Human-readable device name from Bonjour TXT record
    public let displayDeviceName: String?
    /// Instance identifier from Bonjour TXT record (human-readable label)
    public let instanceId: String?
    /// Whether the device has an active session (from Bonjour TXT record)
    public let sessionActive: Bool?
    /// TLS certificate fingerprint from Bonjour TXT record (sha256:hex)
    public let certFingerprint: String?

    public init(id: String, name: String, endpoint: NWEndpoint,
                simulatorUDID: String? = nil,
                installationId: String? = nil,
                displayDeviceName: String? = nil,
                instanceId: String? = nil,
                sessionActive: Bool? = nil,
                certFingerprint: String? = nil) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.simulatorUDID = simulatorUDID
        self.installationId = installationId
        self.displayDeviceName = displayDeviceName
        self.instanceId = instanceId
        self.sessionActive = sessionActive
        self.certFingerprint = certFingerprint
    }

    /// Convenience init for direct host:port connections (no Bonjour).
    public init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        self.init(id: "\(host):\(port)", name: "\(host):\(port)", endpoint: endpoint)
    }

    public var connectionType: ConnectionScope {
        if simulatorUDID != nil { return .simulator }
        if id.hasPrefix("usb-") { return .usb }
        return .network
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    /// Short instance ID parsed from service name (e.g., "a1b2c3d4")
    /// Service name format: "AppName-DeviceName#shortId"
    public var shortId: String? {
        guard let hashIndex = name.firstIndex(of: "#") else { return nil }
        let id = String(name[name.index(after: hashIndex)...])
        return id.isEmpty ? nil : id
    }

    /// The name portion without the instance ID suffix
    private var nameWithoutId: String {
        if let hashIndex = name.firstIndex(of: "#") {
            return String(name[..<hashIndex])
        }
        return name
    }

    /// Parse the service name to extract app name and device name
    /// Service name format: "AppName#instanceId" (v3) or "AppName-DeviceName#shortId" (v2)
    public var parsedName: (appName: String, deviceName: String)? {
        let baseName = nameWithoutId
        guard let lastDashIndex = baseName.lastIndex(of: "-") else { return nil }
        let appName = String(baseName[..<lastDashIndex])
        let deviceName = String(baseName[baseName.index(after: lastDashIndex)...])
        guard !appName.isEmpty && !deviceName.isEmpty else { return nil }
        return (appName, deviceName)
    }

    /// App name extracted from service name
    /// For v3 format "AppName#id", returns the part before #
    public var appName: String {
        parsedName?.appName ?? nameWithoutId
    }

    /// Device name extracted from service name (empty for v3 format)
    public var deviceName: String {
        displayDeviceName ?? parsedName?.deviceName ?? ""
    }

    var discoveryIdentity: String {
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let installationId = Self.normalizedIdentifier(installationId) {
            return "install|\(normalizedAppName)|\(installationId)"
        }

        return "service|\(id)"
    }

    /// Check if this device matches a filter string.
    /// Matches case-insensitively: contains on name/appName/deviceName, prefix on shortId/instanceId/simulatorUDID.
    public func matches(filter: String) -> Bool {
        let low = filter.lowercased()
        return name.lowercased().contains(low) ||
            appName.lowercased().contains(low) ||
            deviceName.lowercased().contains(low) ||
            (shortId?.lowercased().hasPrefix(low) ?? false) ||
            (installationId?.lowercased().hasPrefix(low) ?? false) ||
            (instanceId?.lowercased().hasPrefix(low) ?? false) ||
            (simulatorUDID?.lowercased().hasPrefix(low) ?? false)
    }
}

extension Array where Element == DiscoveredDevice {
    /// Return the first device matching the filter, or the first device if filter is nil.
    public func first(matching filter: String?) -> DiscoveredDevice? {
        guard let filter else { return first }
        return first { $0.matches(filter: filter) }
    }

    /// Probe all devices in parallel and return only those that are reachable.
    /// Uses the Inside Job status RPC as a lightweight liveness check; devices
    /// that fail to respond with a valid status payload are treated as stale.
    public func reachable(timeout: TimeInterval = 1.5) async -> [DiscoveredDevice] {
        await withTaskGroup(of: (Int, DiscoveredDevice?).self) { group in
            for (index, device) in self.enumerated() {
                group.addTask {
                    let reachable = await probeReachability(for: device, timeout: timeout)
                    return reachable ? (index, device) : (index, nil)
                }
            }
            var indexed: [(Int, DiscoveredDevice)] = []
            for await (index, device) in group {
                if let device { indexed.append((index, device)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

@ButtonHeistActor
var makeReachabilityConnection: (DiscoveredDevice) -> any DeviceConnecting = { device in
    let connection = DeviceConnection(device: device, token: nil, driverId: nil)
    connection.autoRespondToAuthRequired = false
    return connection
}

@ButtonHeistActor
private func probeReachability(for device: DiscoveredDevice, timeout: TimeInterval) async -> Bool {
    let connection = makeReachabilityConnection(device)
    var reachable = false
    var finished = false

    connection.onEvent = { event in
        switch event {
        case .transportReady:
            // Once TCP/TLS is up, send a lightweight status probe.
            connection.send(.status)
        case .connected:
            break
        case .message(let message, _):
            if case .status = message {
                reachabilityLogger.debug("Status reachable: \(device.name, privacy: .public)")
                reachable = true
                finished = true
                connection.disconnect()
            }
        case .disconnected:
            if !finished {
                finished = true
            }
        }
    }

    connection.connect()

    let deadline = Date().addingTimeInterval(timeout)
    while !finished && Date() < deadline {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    if !finished {
        reachabilityLogger.debug("Status probe timeout: \(device.name, privacy: .public)")
        connection.disconnect()
    }

    return reachable
}
