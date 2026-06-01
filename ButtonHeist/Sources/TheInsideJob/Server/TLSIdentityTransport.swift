import Network
import os.log

private let tlsTransportLogger = Logger(subsystem: "com.buttonheist.thegetaway", category: "tls")

extension TLSIdentity {
    /// Build NWParameters configured for TLS using this identity.
    /// Actor-isolated so SecIdentity never crosses isolation boundaries.
    func makeTLSParameters() -> NWParameters? {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            tlsTransportLogger.warning("sec_identity_create failed for TLS identity")
            return nil
        }
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            secIdentity
        )
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )
        return NWParameters(tls: tlsOptions)
    }
}
