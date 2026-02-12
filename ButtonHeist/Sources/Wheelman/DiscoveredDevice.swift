import Foundation
import Network

/// A discovered iOS device running InsideMan
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(id: String, name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }

    /// Parse the service name to extract app name and device name
    /// Service name format: "AppName-DeviceName"
    public var parsedName: (appName: String, deviceName: String)? {
        guard let lastDashIndex = name.lastIndex(of: "-") else { return nil }
        let appName = String(name[..<lastDashIndex])
        let deviceName = String(name[name.index(after: lastDashIndex)...])
        guard !appName.isEmpty && !deviceName.isEmpty else { return nil }
        return (appName, deviceName)
    }

    /// App name extracted from service name
    public var appName: String {
        parsedName?.appName ?? name
    }

    /// Device name extracted from service name
    public var deviceName: String {
        parsedName?.deviceName ?? ""
    }
}
