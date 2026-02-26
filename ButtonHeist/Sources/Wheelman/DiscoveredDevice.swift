import Foundation
import Network

/// A discovered iOS device running InsideJob
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint
    /// Simulator UDID from Bonjour TXT record (nil on physical devices)
    public let simulatorUDID: String?
    /// Token hash from Bonjour TXT record (for pre-connection filtering)
    public let tokenHash: String?
    /// Instance identifier from Bonjour TXT record (human-readable label)
    public let instanceId: String?

    public init(id: String, name: String, endpoint: NWEndpoint,
                simulatorUDID: String? = nil,
                tokenHash: String? = nil, instanceId: String? = nil) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.simulatorUDID = simulatorUDID
        self.tokenHash = tokenHash
        self.instanceId = instanceId
    }

    /// Convenience init for direct host:port connections (no Bonjour).
    public init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        self.init(id: "\(host):\(port)", name: "\(host):\(port)", endpoint: endpoint)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
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
        parsedName?.deviceName ?? ""
    }

    /// Check if this device matches a filter string.
    /// Matches case-insensitively: contains on name/appName/deviceName, prefix on shortId/instanceId/simulatorUDID.
    public func matches(filter: String) -> Bool {
        let low = filter.lowercased()
        return name.lowercased().contains(low) ||
            appName.lowercased().contains(low) ||
            deviceName.lowercased().contains(low) ||
            (shortId?.lowercased().hasPrefix(low) ?? false) ||
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
}
