import CryptoKit
import Foundation

/// Shared TLS-PSK material derivation for the macOS client and iOS server.
public enum ButtonHeistTLSPreSharedKey {
    public static let identity = Data("buttonheist-tls-psk-v1".utf8)
    public static let derivedKeyByteCount = 32

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
}
