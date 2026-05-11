import CryptoKit
import Foundation
import Network
import Security
import os.log

import SwiftASN1
import X509

private let logger = Logger(subsystem: "com.buttonheist.thegetaway", category: "tls")

actor TLSIdentity {
    private let identity: SecIdentity
    private let certificate: SecCertificate
    nonisolated let fingerprint: String
    nonisolated let expiryDate: Date

    /// Number of days before expiry at which the certificate is auto-renewed.
    static let renewalThresholdDays: Int = 30

    /// Number of days before expiry at which a warning is logged.
    static let warningThresholdDays: Int = 60

    private init(identity: SecIdentity, certificate: SecCertificate, fingerprint: String, expiryDate: Date) {
        self.identity = identity
        self.certificate = certificate
        self.fingerprint = fingerprint
        self.expiryDate = expiryDate
    }

    /// Retrieve an existing identity from the Keychain, or create and store a new one.
    /// If the loaded certificate expires within ``renewalThresholdDays`` days, it is
    /// deleted and a fresh one is generated. A warning is logged if expiry is within
    /// ``warningThresholdDays`` days.
    static func getOrCreate(label: String = "com.buttonheist.tls") throws -> TLSIdentity {
        if let existing = try loadFromKeychain(label: label) {
            let daysRemaining = existing.daysUntilExpiry
            if daysRemaining <= renewalThresholdDays {
                logger.warning(
                    "TLS certificate expires in \(daysRemaining) day(s) — regenerating"
                )
                try delete(label: label)
            } else {
                if daysRemaining <= warningThresholdDays {
                    logger.warning(
                        "TLS certificate expires in \(daysRemaining) day(s) — consider renewal soon"
                    )
                }
                logger.debug("Loaded existing TLS identity from Keychain")
                return existing
            }
        }

        logger.info("No existing TLS identity found, generating new one")
        let (privateKey, derBytes) = try generateCertificate()
        let secCert = try makeSecCertificate(derBytes: derBytes)
        let fp = computeFingerprint(derBytes: derBytes)
        let expiry = try certificateExpiryDate(derBytes: derBytes)

        do {
            let secIdentity = try storeInKeychain(privateKey: privateKey, certificate: secCert, label: label)
            logger.info("TLS identity stored in Keychain: \(fp)")
            return TLSIdentity(identity: secIdentity, certificate: secCert, fingerprint: fp, expiryDate: expiry)
        } catch {
            logger.warning("Keychain storage failed, using ephemeral identity: \(error)")
            return try createEphemeral()
        }
    }

    /// Create an ephemeral identity by temporarily storing items in the Keychain
    /// for `SecIdentity` creation, then immediately removing them.
    static func createEphemeral() throws -> TLSIdentity {
        let (privateKey, derBytes) = try generateCertificate()
        let secCert = try makeSecCertificate(derBytes: derBytes)
        let fp = computeFingerprint(derBytes: derBytes)
        let expiry = try certificateExpiryDate(derBytes: derBytes)
        let secIdentity = try createInMemoryIdentity(privateKey: privateKey, certificate: secCert)
        logger.info("Created ephemeral TLS identity: \(fp)")
        return TLSIdentity(identity: secIdentity, certificate: secCert, fingerprint: fp, expiryDate: expiry)
    }

    /// Remove a stored identity from the Keychain.
    static func delete(label: String = "com.buttonheist.tls") throws(TLSIdentityError) {
        let classes: [CFString] = [kSecClassKey, kSecClassCertificate, kSecClassIdentity]
        for secClass in classes {
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecAttrLabel as String: label,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw TLSIdentityError.keychainError(status)
            }
        }
    }

    // MARK: - TLS Parameters

    /// Build NWParameters configured for TLS using this identity.
    /// Actor-isolated so SecIdentity never crosses isolation boundaries.
    func makeTLSParameters() -> NWParameters? {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            logger.warning("sec_identity_create failed for TLS identity")
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

    // MARK: - Certificate Generation

    static func generateCertificate(
        validityDays: Double = 365.25
    ) throws -> (P256.Signing.PrivateKey, [UInt8]) {
        let key = P256.Signing.PrivateKey()
        let name = try DistinguishedName {
            CommonName("ButtonHeist")
            OrganizationName("ButtonHeist")
        }
        let now = Date()
        let notValidAfter = now.addingTimeInterval(validityDays * 24 * 3600)
        let cert = try X509.Certificate(
            version: .v3,
            serialNumber: X509.Certificate.SerialNumber(),
            publicKey: .init(key.publicKey),
            notValidBefore: now,
            notValidAfter: notValidAfter,
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: X509.Certificate.Extensions {},
            issuerPrivateKey: .init(key)
        )
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        return (key, serializer.serializedBytes)
    }

    static func makeSecCertificate(derBytes: [UInt8]) throws -> SecCertificate {
        let data = Data(derBytes)
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            throw TLSIdentityError.invalidCertificateData
        }
        return cert
    }

    static func computeFingerprint(derBytes: [UInt8]) -> String {
        let hash = SHA256.hash(data: derBytes)
        return "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse the ``notValidAfter`` date from DER-encoded certificate bytes.
    static func certificateExpiryDate(derBytes: [UInt8]) throws -> Date {
        let cert = try X509.Certificate(derEncoded: derBytes)
        return cert.notValidAfter
    }

    /// Number of whole days until this certificate expires (negative if already expired).
    nonisolated var daysUntilExpiry: Int {
        let interval = expiryDate.timeIntervalSinceNow
        return Int(interval / (24 * 3600))
    }

    // MARK: - Keychain Operations

    private static func loadFromKeychain(label: String) throws -> TLSIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let identityRef = result else {
            throw TLSIdentityError.keychainError(status)
        }

        // SecItemCopyMatching returns CFTypeRef; bridge to SecIdentity
        guard CFGetTypeID(identityRef as CFTypeRef) == SecIdentityGetTypeID() else {
            throw TLSIdentityError.keychainError(errSecParam)
        }
        let secIdentity = unsafeDowncast(identityRef as AnyObject, to: SecIdentity.self)
        var certRef: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(secIdentity, &certRef)
        guard certStatus == errSecSuccess, let cert = certRef else {
            throw TLSIdentityError.keychainError(certStatus)
        }

        let derData = SecCertificateCopyData(cert) as Data
        let derBytes = Array(derData)
        let fp = computeFingerprint(derBytes: derBytes)
        let expiry = try certificateExpiryDate(derBytes: derBytes)
        return TLSIdentity(identity: secIdentity, certificate: cert, fingerprint: fp, expiryDate: expiry)
    }

    private static func storeInKeychain(
        privateKey: P256.Signing.PrivateKey,
        certificate: SecCertificate,
        label: String
    ) throws(TLSIdentityError) -> SecIdentity {
        let keyData = privateKey.x963Representation
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, keyAttributes as CFDictionary, &error) else {
            throw TLSIdentityError.keyCreationFailed(error?.takeRetainedValue())
        }

        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        if certStatus == errSecDuplicateItem {
            SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label] as CFDictionary)
            certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        }
        guard certStatus == errSecSuccess else {
            throw TLSIdentityError.keychainError(certStatus)
        }

        let keyAddQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: secKey,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        if keyStatus == errSecDuplicateItem {
            SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrLabel as String: label] as CFDictionary)
            keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        }
        guard keyStatus == errSecSuccess else {
            // Clean up the certificate we just stored to avoid orphaned items
            SecItemDelete(certAddQuery as CFDictionary)
            throw TLSIdentityError.keychainError(keyStatus)
        }

        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
        ]
        var identityResult: CFTypeRef?
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityResult)
        guard identityStatus == errSecSuccess, let identityRef = identityResult else {
            throw TLSIdentityError.keychainError(identityStatus)
        }
        guard CFGetTypeID(identityRef as CFTypeRef) == SecIdentityGetTypeID() else {
            throw TLSIdentityError.keychainError(errSecParam)
        }
        let secIdentity = unsafeDowncast(identityRef as AnyObject, to: SecIdentity.self)
        return secIdentity
    }

    private static func createInMemoryIdentity(
        privateKey: P256.Signing.PrivateKey,
        certificate: SecCertificate
    ) throws(TLSIdentityError) -> SecIdentity {
        let tempLabel = "com.buttonheist.tls.ephemeral.\(UUID().uuidString)"

        // Clean up temporary Keychain items when we're done.
        // The SecIdentity object is retained in memory after the entries are deleted.
        defer {
            let certDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: tempLabel,
            ]
            SecItemDelete(certDeleteQuery as CFDictionary)

            let keyDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrLabel as String: tempLabel,
            ]
            SecItemDelete(keyDeleteQuery as CFDictionary)
        }

        let keyData = privateKey.x963Representation
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, keyAttributes as CFDictionary, &error) else {
            throw TLSIdentityError.keyCreationFailed(error?.takeRetainedValue())
        }

        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: tempLabel,
        ]
        let certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        guard certStatus == errSecSuccess else {
            throw TLSIdentityError.keychainError(certStatus)
        }

        let keyAddQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: secKey,
            kSecAttrLabel as String: tempLabel,
        ]
        let keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        guard keyStatus == errSecSuccess else {
            throw TLSIdentityError.keychainError(keyStatus)
        }

        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: tempLabel,
            kSecReturnRef as String: true,
        ]
        var identityResult: CFTypeRef?
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityResult)
        guard identityStatus == errSecSuccess, let identityRef = identityResult else {
            throw TLSIdentityError.keychainError(identityStatus)
        }

        guard CFGetTypeID(identityRef as CFTypeRef) == SecIdentityGetTypeID() else {
            throw TLSIdentityError.keychainError(errSecParam)
        }
        let secIdentity = unsafeDowncast(identityRef as AnyObject, to: SecIdentity.self)
        return secIdentity
    }
}

// MARK: - Errors

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
