import Foundation
import Network

import TheScore

nonisolated extension DeviceConnection {

    static func makeTLSParameters(token: String) -> NWParameters {
        ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token)
    }

    static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }

        switch host {
        case .ipv4(let addr):
            return addr == .loopback || addr.rawValue.first == 127
        case .ipv6(let addr):
            return addr == .loopback
        case .name:
            return false
        @unknown default:
            return false
        }
    }
}
