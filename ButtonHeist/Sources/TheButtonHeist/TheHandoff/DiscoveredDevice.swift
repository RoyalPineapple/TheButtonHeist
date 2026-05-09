import Foundation
import Network
import os

import TheScore

private let reachabilityLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "reachability")

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

    /// Parse a "host:port" string and create a device. Returns nil on invalid input.
    public static func fromHostPort(
        _ value: String,
        id: String? = nil,
        name: String? = nil,
        certFingerprint: String? = nil
    ) -> DiscoveredDevice? {
        guard let (host, port) = parseHostPort(from: value) else { return nil }
        let resolvedId = id ?? "\(host):\(port)"
        let resolvedName = name ?? "\(host):\(port)"
        return DiscoveredDevice(
            id: resolvedId,
            name: resolvedName,
            endpoint: .hostPort(host: .init(host), port: .init(integerLiteral: port)),
            certFingerprint: certFingerprint
        )
    }

    /// Convenience init for direct host:port connections (no Bonjour).
    public init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        self.init(id: "\(host):\(port)", name: "\(host):\(port)", endpoint: endpoint)
    }

    /// Parse a direct loopback connection target from a filter string.
    /// Accepts `localhost`, `127.x.x.x`, and IPv6 loopback forms with a port.
    public static func directConnectTarget(from filter: String?) -> DiscoveredDevice? {
        guard let filter else { return nil }
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (host, port) = parseHostPort(from: trimmed), isLoopbackHost(host) else {
            return nil
        }
        return DiscoveredDevice(host: host, port: port)
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

    private static func parseHostPort(from value: String) -> (String, UInt16)? {
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("["),
           let closingBracket = value.firstIndex(of: "]"),
           let separator = value.index(closingBracket, offsetBy: 1, limitedBy: value.endIndex),
           separator < value.endIndex,
           value[separator] == ":" {
            let host = String(value[value.index(after: value.startIndex)..<closingBracket])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let portString = String(value[value.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, let port = UInt16(portString), port > 0 else { return nil }
            return (host, port)
        }

        guard let separator = value.lastIndex(of: ":") else { return nil }
        let host = String(value[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let portString = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = UInt16(portString), port > 0 else { return nil }
        return (host, port)
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Only trust IP addresses, not hostnames like "localhost" (spoofable via /etc/hosts).
        // Use 127.0.0.1 or ::1 instead.
        return normalized == "::1" ||
            normalized == "0:0:0:0:0:0:0:1" ||
            normalized.hasPrefix("127.")
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
                    let reachable = await device.isReachable(timeout: timeout)
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

extension DiscoveredDevice {
    @ButtonHeistActor
    func isReachable(timeout: TimeInterval = 1.5) async -> Bool {
        let connection = makeReachabilityConnection(self)
        let deviceName = name
        let resolver = ReachabilityResolver()

        // Wire the connection's onEvent callback to resolve the probe:
        // `.message(.status)` resolves true; `.disconnected` resolves false.
        // The resolver is one-shot so a subsequent `.disconnected` after a
        // successful `.status` is a no-op. `[weak connection]` breaks the
        // closure→connection→closure cycle so the probe connection deallocates
        // promptly after `isReachable` returns.
        connection.onEvent = { [weak connection] event in
            switch event {
            case .transportReady:
                connection?.send(.status)
            case .connected:
                break
            case .message(let message, _, _):
                if case .status = message {
                    reachabilityLogger.debug("Status reachable: \(deviceName, privacy: .public)")
                    resolver.resolve(true)
                }
            case .disconnected:
                resolver.resolve(false)
            }
        }

        connection.connect()

        // Schedule a timeout that resolves false if the probe hasn't completed.
        let timeoutTask = Task { @ButtonHeistActor in
            guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
            resolver.resolve(false)
        }
        defer { timeoutTask.cancel() }

        let reachable = await resolver.value
        connection.disconnect()
        if !reachable {
            reachabilityLogger.debug("Status probe miss: \(deviceName, privacy: .public)")
        }
        return reachable
    }
}

/// One-shot bool resolver backing `DiscoveredDevice.isReachable`. Holds a
/// continuation that is resumed exactly once by whichever signal arrives
/// first: a successful status message, a disconnect, or the timeout.
@ButtonHeistActor
private final class ReachabilityResolver {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var pendingResult: Bool?

    var value: Bool {
        get async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if let pendingResult {
                    continuation.resume(returning: pendingResult)
                    return
                }
                self.continuation = continuation
            }
        }
    }

    func resolve(_ value: Bool) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
            return
        }
        // Result arrived before any awaiter registered; remember it so the
        // first `await value` returns immediately.
        if pendingResult == nil {
            pendingResult = value
        }
    }
}
