import CryptoKit
import Foundation
import Security

import SwiftASN1
import X509

struct TLSCertificateMaterial {
    let privateKey: P256.Signing.PrivateKey
    let derBytes: [UInt8]
    let certificate: SecCertificate
    let fingerprint: String
    let expiryDate: Date

    static func generate(validityDays: Double = 365.25) throws -> TLSCertificateMaterial {
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
        let derBytes = serializer.serializedBytes
        return try TLSCertificateMaterial(
            privateKey: key,
            derBytes: derBytes,
            certificate: makeSecCertificate(derBytes: derBytes),
            fingerprint: TLSCertificateFacts.fingerprint(derBytes: derBytes),
            expiryDate: TLSCertificateFacts.expiryDate(derBytes: derBytes)
        )
    }

    static func makeSecCertificate(derBytes: [UInt8]) throws -> SecCertificate {
        let data = Data(derBytes)
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            throw TLSIdentityError.invalidCertificateData
        }
        return cert
    }
}
