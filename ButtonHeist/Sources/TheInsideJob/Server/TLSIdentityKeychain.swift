import CryptoKit
import Foundation
import Security

enum TLSIdentityKeychain {
    static func load(label: String) throws -> TLSIdentity? {
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
        let fingerprint = TLSCertificateFacts.fingerprint(derBytes: derBytes)
        let expiry = try TLSCertificateFacts.expiryDate(derBytes: derBytes)
        return TLSIdentity(identity: secIdentity, certificate: cert, fingerprint: fingerprint, expiryDate: expiry)
    }

    static func store(material: TLSCertificateMaterial, label: String) throws(TLSIdentityError) -> SecIdentity {
        try store(privateKey: material.privateKey, certificate: material.certificate, label: label, accessible: true)
    }

    static func createEphemeralIdentity(material: TLSCertificateMaterial) throws(TLSIdentityError) -> SecIdentity {
        let tempLabel = "com.buttonheist.tls.ephemeral.\(UUID().uuidString)"
        defer {
            deleteIgnoringMissing(secClass: kSecClassCertificate, label: tempLabel)
            deleteIgnoringMissing(secClass: kSecClassKey, label: tempLabel)
        }
        return try store(privateKey: material.privateKey, certificate: material.certificate, label: tempLabel, accessible: false)
    }

    static func delete(label: String) throws(TLSIdentityError) {
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

    private static func store(
        privateKey: P256.Signing.PrivateKey,
        certificate: SecCertificate,
        label: String,
        accessible: Bool
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

        let certAddQuery = itemAddQuery(
            secClass: kSecClassCertificate,
            valueRef: certificate,
            label: label,
            accessible: accessible
        )
        var certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        if certStatus == errSecDuplicateItem {
            deleteIgnoringMissing(secClass: kSecClassCertificate, label: label)
            certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        }
        guard certStatus == errSecSuccess else {
            throw TLSIdentityError.keychainError(certStatus)
        }

        let keyAddQuery = itemAddQuery(secClass: kSecClassKey, valueRef: secKey, label: label, accessible: accessible)
        var keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        if keyStatus == errSecDuplicateItem {
            deleteIgnoringMissing(secClass: kSecClassKey, label: label)
            keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        }
        guard keyStatus == errSecSuccess else {
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
        return unsafeDowncast(identityRef as AnyObject, to: SecIdentity.self)
    }

    private static func itemAddQuery(
        secClass: CFString,
        valueRef: Any,
        label: String,
        accessible: Bool
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: secClass,
            kSecValueRef as String: valueRef,
            kSecAttrLabel as String: label,
        ]
        if accessible {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return query
    }

    private static func deleteIgnoringMissing(secClass: CFString, label: String) {
        SecItemDelete([kSecClass as String: secClass, kSecAttrLabel as String: label] as CFDictionary)
    }
}
