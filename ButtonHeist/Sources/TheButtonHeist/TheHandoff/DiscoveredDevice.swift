import Foundation
import Network

import TheScore

/// A discovered iOS device running TheInsideJob.
///
/// `id` is the discovery identity used to dedupe and resolve a concrete endpoint:
/// Bonjour service name, USB device identifier, or direct `host:port`. `name` is
/// the advertised service label. Human-facing display text is derived separately
/// by `displayName(among:)` so target resolution does not depend on formatting.
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    /// Stable discovery key for this advertised endpoint.
    public let id: String
    /// Advertised service label, usually `AppName#instanceId`.
    let name: String
    let endpoint: NWEndpoint
    /// Simulator UDID from Bonjour TXT record (nil on physical devices)
    let simulatorUDID: String?
    /// Stable installation identifier from Bonjour TXT record
    let installationId: String?
    /// Human-readable device name from Bonjour TXT record
    private let advertisedDeviceName: String?
    /// Instance identifier from Bonjour TXT record (human-readable label)
    let instanceId: String?
    /// Legacy TLS certificate fingerprint from older Bonjour TXT records. Current PSK transport ignores it.
    let certFingerprint: String?
    /// Connection scope advertised or inferred at discovery time.
    let connectionType: ConnectionScope

    public init(id: String, name: String, endpoint: NWEndpoint,
                simulatorUDID: String? = nil,
                installationId: String? = nil,
                displayDeviceName: String? = nil,
                instanceId: String? = nil,
                certFingerprint: String? = nil,
                connectionType: ConnectionScope? = nil) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.simulatorUDID = simulatorUDID
        self.installationId = installationId
        self.advertisedDeviceName = displayDeviceName
        self.instanceId = instanceId
        self.certFingerprint = certFingerprint
        self.connectionType = connectionType ?? Self.inferConnectionType(
            id: id,
            simulatorUDID: simulatorUDID
        )
    }

    /// Parse a "host:port" string and create a device. Returns nil on invalid input.
    static func fromHostPort(
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
    init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        self.init(id: "\(host):\(port)", name: "\(host):\(port)", endpoint: endpoint)
    }

    /// Parse a direct loopback connection target from a filter string.
    /// Accepts `localhost`, `127.x.x.x`, and IPv6 loopback forms with a port.
    static func directConnectTarget(from filter: String?) -> DiscoveredDevice? {
        guard let filter else { return nil }
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (host, port) = parseHostPort(from: trimmed), isLoopbackHost(host) else {
            return nil
        }
        return DiscoveredDevice(host: host, port: port)
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

    private static func inferConnectionType(id: String, simulatorUDID: String?) -> ConnectionScope {
        if simulatorUDID != nil { return .simulator }
        if id.hasPrefix("usb-") { return .usb }
        return .network
    }

    /// Instance ID parsed from service name suffix (e.g., "a1b2c3d4").
    /// Service name format: "AppName#instanceId".
    var shortId: String? {
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

    /// App name extracted from service name
    var appName: String {
        nameWithoutId
    }

    /// Device name advertised through the TXT record.
    var deviceName: String {
        advertisedDeviceName ?? ""
    }

    var discoveryIdentity: String {
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let installationId = Self.normalizedIdentifier(installationId) {
            return "install|\(normalizedAppName)|\(installationId)"
        }

        return "service|\(id)"
    }

    var resolutionDiagnosticLabel: String {
        guard !deviceName.isEmpty else { return name }
        return "\(name) (\(deviceName))"
    }

    /// Check if this device matches a requested target query.
    /// Matches case-insensitively: contains on service/app/device names, exact
    /// or prefix on identifiers.
    func matches(resolutionQuery query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return false }

        let nameMatches = [name, appName, deviceName]
            .map { $0.lowercased() }
            .contains { $0.contains(normalizedQuery) }

        let identifierMatches = [shortId, installationId, instanceId, simulatorUDID, id]
            .compactMap { $0?.lowercased() }
            .contains { $0 == normalizedQuery || $0.hasPrefix(normalizedQuery) }

        return nameMatches || identifierMatches
    }

    /// Backwards-compatible spelling for existing callers.
    func matches(filter: String) -> Bool {
        matches(resolutionQuery: filter)
    }

    /// Compute display text with disambiguation when multiple discovered
    /// devices advertise the same app label.
    func displayName(among devices: [DiscoveredDevice]) -> String {
        let app = appName
        let deviceSuffix = deviceName.isEmpty ? "" : " (\(deviceName))"
        let sameAppDevices = devices.filter { $0.appName == app }

        guard sameAppDevices.count > 1 else { return app }

        let sameAppAndDevice = sameAppDevices.filter { $0.deviceName == deviceName }
        if sameAppAndDevice.count > 1, let shortId {
            return "\(app)\(deviceSuffix) [\(shortId)]"
        }
        return "\(app)\(deviceSuffix)"
    }
}

extension Array where Element == DiscoveredDevice {
    /// Return the first device matching the filter, or the first device if filter is nil.
    func first(matching filter: String?) -> DiscoveredDevice? {
        guard let filter else { return first }
        return first { $0.matches(filter: filter) }
    }

}
