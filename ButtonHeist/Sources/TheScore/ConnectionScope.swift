import Foundation

/// Defines which connection sources a server will accept.
///
/// Each scope corresponds to a network path:
/// - `simulator`: Loopback address or `lo` interface — iOS Simulator on the same Mac
/// - `usb`: `anpi` interface (Apple Network Private Interface) — physical device over USB
/// - `network`: Everything else — WiFi, LAN, or broader network
///
/// By default, only simulator and USB are allowed. Set `INSIDEJOB_SCOPE` to change:
/// ```
/// INSIDEJOB_SCOPE=simulator,usb,network  // also allow WiFi/LAN
/// INSIDEJOB_SCOPE=usb                    // USB only
/// ```
public enum ConnectionScope: String, Sendable, CaseIterable, Codable {
    case simulator
    case usb
    case network

    /// Parse a comma-separated scope string (e.g. "simulator,usb").
    /// Returns nil for empty/invalid input (caller should fall back to defaults).
    public static func parse(_ value: String) -> Set<ConnectionScope>? {
        let scopes = value
            .split(separator: ",")
            .compactMap { ConnectionScope(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        return scopes.isEmpty ? nil : Set(scopes)
    }

    /// Default scopes: simulator and USB only (network is opt-in).
    public static let `default`: Set<ConnectionScope> = [.simulator, .usb]

    /// All scopes allowed (including network).
    public static let all: Set<ConnectionScope> = Set(ConnectionScope.allCases)
}
