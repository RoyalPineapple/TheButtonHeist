import CryptoKit
import Foundation

import X509

enum TLSCertificateFacts {
    static func fingerprint(derBytes: [UInt8]) -> String {
        let hash = SHA256.hash(data: derBytes)
        return "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse the ``notValidAfter`` date from DER-encoded certificate bytes.
    static func expiryDate(derBytes: [UInt8]) throws -> Date {
        let cert = try X509.Certificate(derEncoded: derBytes)
        return cert.notValidAfter
    }
}
