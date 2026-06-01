import Foundation
import Security

enum TLSIdentityError: Error, LocalizedError {
    case invalidCertificateData
    case keychainError(OSStatus)
    case keyCreationFailed(CFError?)

    var errorDescription: String? {
        switch self {
        case .invalidCertificateData:
            return "Generated certificate DER data was rejected by SecCertificateCreateWithData"
        case .keychainError(let status):
            return "Keychain operation failed with status \(status)"
        case .keyCreationFailed(let error):
            if let error {
                return "Private key creation failed: \(error)"
            }
            return "Private key creation failed"
        }
    }
}
