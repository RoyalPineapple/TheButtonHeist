import Foundation
import Network

import TheScore

extension ConnectionScope {
    /// Classify a remote host into a connection scope using typed Network framework values.
    ///
    /// - IPv4/IPv6 loopback address or `lo` interface → `.simulator`
    /// - `anpi` interface (Apple Network Private Interface) → `.usb` (CoreDevice tunnel)
    /// - Everything else → `.network`
    ///
    /// Pass `interfaceNames` from `NWConnection.currentPath?.availableInterfaces.map(\.name)`
    /// after the connection reaches `.ready` for precise classification.
    public static func classify(host: NWEndpoint.Host, interfaceNames: [String] = []) -> ConnectionScope {
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
        if interfaceNames.contains(where: { $0.hasPrefix("lo") }) { return .simulator }

        // anpi = USB (Apple Network Private Interface, CoreDevice tunnel)
        if interfaceNames.contains(where: { $0.hasPrefix("anpi") }) { return .usb }

        return .network
    }
}
