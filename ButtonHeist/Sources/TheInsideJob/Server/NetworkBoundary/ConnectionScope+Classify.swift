import Foundation
import Network

import TheScore

struct ConnectionPathEvidence {
    let host: NWEndpoint.Host
    let interfaceFacts: [InterfaceFact]
    let path: Path

    init(host: NWEndpoint.Host, interfaceNames: [String] = []) {
        let interfaceFacts = interfaceNames.map(InterfaceFact.init(name:))
        self.host = host
        self.interfaceFacts = interfaceFacts
        self.path = Self.path(for: host, interfaceFacts: interfaceFacts)
    }

    enum Path: Equatable {
        case simulator(SimulatorReason)
        case usb(USBReason)
        case network(NetworkReason)

        var scope: ConnectionScope {
            switch self {
            case .simulator:
                return .simulator
            case .usb:
                return .usb
            case .network:
                return .network
            }
        }
    }

    enum SimulatorReason: Equatable {
        case ipv4LoopbackAddress
        case ipv4LoopbackRange
        case ipv6LoopbackAddress
        case loopbackInterface(name: String)
    }

    enum USBReason: Equatable {
        case appleNetworkPrivateInterface(name: String)
    }

    enum NetworkReason: Equatable {
        case noLocalPathEvidence
    }

    struct InterfaceFact: Equatable {
        let name: String
        let heuristic: InterfaceHeuristic?

        init(name: String) {
            self.name = name
            self.heuristic = InterfaceHeuristic(name: name)
        }
    }

    enum InterfaceHeuristic: Equatable {
        case loopback
        case appleNetworkPrivateInterface

        init?(name: String) {
            if name.hasPrefix("lo") {
                self = .loopback
            } else if name.hasPrefix("anpi") {
                self = .appleNetworkPrivateInterface
            } else {
                return nil
            }
        }
    }

    private static func path(for host: NWEndpoint.Host, interfaceFacts: [InterfaceFact]) -> Path {
        switch host {
        case .ipv4(let address):
            if address == .loopback {
                return .simulator(.ipv4LoopbackAddress)
            }
            if address.rawValue.first == 127 {
                return .simulator(.ipv4LoopbackRange)
            }
        case .ipv6(let address):
            if address == .loopback {
                return .simulator(.ipv6LoopbackAddress)
            }
        default:
            break
        }

        if let interface = interfaceFacts.first(where: { $0.heuristic == .loopback }) {
            return .simulator(.loopbackInterface(name: interface.name))
        }

        if let interface = interfaceFacts.first(where: { $0.heuristic == .appleNetworkPrivateInterface }) {
            return .usb(.appleNetworkPrivateInterface(name: interface.name))
        }

        return .network(.noLocalPathEvidence)
    }
}

extension ConnectionScope {
    /// Classify a remote host into a connection scope using typed Network framework values.
    ///
    /// - Loopback address or loopback interface evidence → `.simulator`
    /// - Apple Network Private Interface evidence → `.usb` (CoreDevice tunnel)
    /// - Everything else → `.network`
    ///
    /// Pass `interfaceNames` from `NWConnection.currentPath?.availableInterfaces.map { $0.name }`
    /// after the connection reaches `.ready` for precise classification.
    static func classify(host: NWEndpoint.Host, interfaceNames: [String] = []) -> ConnectionScope {
        let evidence = ConnectionPathEvidence(host: host, interfaceNames: interfaceNames)
        return classify(evidence)
    }

    static func classify(_ evidence: ConnectionPathEvidence) -> ConnectionScope {
        evidence.path.scope
    }
}
