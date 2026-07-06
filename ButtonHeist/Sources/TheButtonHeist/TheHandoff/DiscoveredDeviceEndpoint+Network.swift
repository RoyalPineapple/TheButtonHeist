import Network

extension DiscoveredDeviceEndpoint {
    var nwEndpoint: NWEndpoint {
        switch self {
        case .hostPort(let host, let port):
            return .hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: port)
            )
        case .service(let name, let type, let domain):
            return .service(
                name: name,
                type: type,
                domain: domain,
                interface: nil
            )
        }
    }
}
