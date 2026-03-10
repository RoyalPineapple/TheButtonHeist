import Foundation
import Network

/// Defines which connection sources a server will accept.
///
/// Each scope corresponds to a network path:
/// - `simulator`: Loopback connections (`::1`, `127.0.0.1`) — iOS Simulator on the same Mac
/// - `usb`: CoreDevice IPv6 tunnel (`fd??:` ULA prefix) — physical device over USB
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

    /// Classify a remote host into a connection scope using typed Network framework values.
    ///
    /// - IPv4/IPv6 loopback → `.simulator`
    /// - `anpi` interface (Apple Network Private Interface) → `.usb` (CoreDevice tunnel)
    /// - IPv6 ULA (`fd00::/8`) on non-`anpi` interface → `.network` (regular ULA, not USB)
    /// - Everything else → `.network`
    ///
    /// Pass `interfaces` from `NWConnection.currentPath?.availableInterfaces` after the
    /// connection reaches `.ready` for precise CoreDevice USB detection.
    public static func classify(host: NWEndpoint.Host, interfaces: [NWInterface] = []) -> ConnectionScope {
        switch host {
        case .ipv4(let addr):
            if addr == .loopback { return .simulator }
            if addr.rawValue.first == 127 { return .simulator }
            return .network

        case .ipv6(let addr):
            if addr == .loopback { return .simulator }
            // CoreDevice USB: check for anpi (Apple Network Private Interface)
            let isAnpi = interfaces.contains { $0.name.hasPrefix("anpi") }
            if isAnpi { return .usb }
            // fd00::/8 ULA without anpi — treat as USB only if no interface info available
            // (pre-.ready fallback). With interface info, non-anpi ULA is network.
            if addr.rawValue.first == 0xfd && interfaces.isEmpty { return .usb }
            return .network

        default:
            return .network
        }
    }
}
