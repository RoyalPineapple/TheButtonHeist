import Foundation

nonisolated extension DeviceConnection {
    static func isLoopbackEndpoint(_ endpoint: DiscoveredDeviceEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "::1" ||
            normalized == "0:0:0:0:0:0:0:1" ||
            normalized.hasPrefix("127.")
    }
}
