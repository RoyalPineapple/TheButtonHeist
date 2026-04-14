import Foundation
import Network

import TheScore

/// Abstraction over `NWInterface` for testability.
/// The only property needed for scope classification is `name`.
public protocol NetworkInterfaceNaming: Sendable {
    var name: String { get }
}

extension NWInterface: NetworkInterfaceNaming {}

extension ConnectionScope {
    /// Classify a remote host into a connection scope using typed Network framework values.
    ///
    /// - IPv4/IPv6 loopback address or `lo` interface → `.simulator`
    /// - `anpi` interface (Apple Network Private Interface) → `.usb` (CoreDevice tunnel)
    /// - Everything else → `.network`
    ///
    /// Pass `interfaces` from `NWConnection.currentPath?.availableInterfaces` after the
    /// connection reaches `.ready` for precise classification.
    public static func classify(host: NWEndpoint.Host, interfaces: [some NetworkInterfaceNaming] = [NWInterface]()) -> ConnectionScope {
        // Loopback address = simulator
        switch host {
        case .ipv4(let addr):
            if addr == .loopback || addr.rawValue.first == 127 { return .simulator }
        case .ipv6(let addr):
            if addr == .loopback { return .simulator }
        default:
            break
        }

        // lo0 interface = simulator (Simulator may use link-local addresses on loopback)
        if interfaces.contains(where: { $0.name.hasPrefix("lo") }) { return .simulator }

        // anpi = USB (Apple Network Private Interface, CoreDevice tunnel)
        if interfaces.contains(where: { $0.name.hasPrefix("anpi") }) { return .usb }

        return .network
    }
}
