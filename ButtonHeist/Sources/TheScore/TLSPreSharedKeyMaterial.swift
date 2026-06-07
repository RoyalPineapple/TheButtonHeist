import CryptoKit
import Dispatch
import Foundation
import Network
import Security

/// Shared TLS-PSK derivation for the macOS client and iOS server.
public enum ButtonHeistTLSPreSharedKey {
    public static let identity = Data("buttonheist-tls-psk-v1".utf8)
    public static let derivedKeyByteCount = 32

    private static let tlsPskWithAES128GCMSHA256 = tls_ciphersuite_t(rawValue: 0x00A8)!
    private static let salt = Data("com.buttonheist.network-framework-psk.salt.v1".utf8)
    private static let info = Data("ButtonHeist Network.framework TLS PSK v1".utf8)

    public static func material(from token: String) -> Data {
        let inputKeyMaterial = SymmetricKey(data: Data(token.utf8))
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: info,
            outputByteCount: derivedKeyByteCount
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }

    public static func makeNetworkParameters(token: String) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tlsPskWithAES128GCMSHA256
        )

        let keyData = material(from: token)
        let identityData = identity
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
