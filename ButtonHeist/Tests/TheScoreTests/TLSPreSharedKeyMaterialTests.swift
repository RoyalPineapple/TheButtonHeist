import Network
import Testing

import TheScore

@Test func `network parameters carry TLS options`() {
    let parameters = ButtonHeistTLSPreSharedKey.networkParameters(from: "token")

    #expect(parameters.defaultProtocolStack.applicationProtocols.contains { $0 is NWProtocolTLS.Options })
}
