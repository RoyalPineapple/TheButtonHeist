import Dispatch
import Network
import Security

import TheScore

enum ServerTLSParameters {
    private static let tlsPskWithAES128GCMSHA256 = tls_ciphersuite_t(rawValue: 0x00A8)!

    static func make(token: String) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tlsPskWithAES128GCMSHA256
        )

        let keyData = ButtonHeistTLSPreSharedKey.material(from: token)
        let identityData = ButtonHeistTLSPreSharedKey.identity
        let keyDispatchData = keyData.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityDispatchData = identityData.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            keyDispatchData as dispatch_data_t,
            identityDispatchData as dispatch_data_t
        )
        sec_protocol_options_set_tls_pre_shared_key_identity_hint(
            tlsOptions.securityProtocolOptions,
            identityDispatchData as dispatch_data_t
        )

        return NWParameters(tls: tlsOptions)
    }
}
