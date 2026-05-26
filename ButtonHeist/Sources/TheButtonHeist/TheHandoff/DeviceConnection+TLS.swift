import CryptoKit
import Foundation
import Network
import Security

nonisolated extension DeviceConnection {

    static func makeTLSParameters(
        expectedFingerprint: String,
        failureTracker: TLSFailureTracker
    ) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let expected = expectedFingerprint
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, completionHandler in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                      let leaf = chain.first else {
                    deviceConnectionLogger.error("TLS verification failed: no server certificate")
                    failureTracker.record(.certificateMismatch)
                    completionHandler(false)
                    return
                }
                let derData = SecCertificateCopyData(leaf) as Data
                let hash = SHA256.hash(data: derData)
                let actual = "sha256:" + hash.map { String(format: "%02x", $0) }.joined()

                let matches = actual == expected
                if matches {
                    deviceConnectionLogger.debug("TLS fingerprint verified")
                } else {
                    deviceConnectionLogger.error("TLS fingerprint mismatch: expected=\(expected.prefix(20))... actual=\(actual.prefix(20))...")
                    failureTracker.record(.certificateMismatch)
                }
                completionHandler(matches)
            },
            DispatchQueue(label: "com.buttonheist.tls.verify")
        )

        return NWParameters(tls: tlsOptions)
    }

    static func makeLoopbackTLSParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completionHandler in
                completionHandler(true)
            },
            DispatchQueue(label: "com.buttonheist.tls.loopback")
        )

        return NWParameters(tls: tlsOptions)
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
