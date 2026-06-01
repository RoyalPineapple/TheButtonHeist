// Mixed unit + integration: the certificate-generation tests are pure, but the
// Keychain integration section (marked below) requires entitlements and is
// hosted under BH Demo.
import XCTest
import Security
import CryptoKit
@testable import TheInsideJob

final class TLSIdentityTests: XCTestCase {

    // MARK: - Certificate Generation (pure, no Keychain)

    func testGenerateCertificateProducesValidDER() throws {
        let material = try TLSCertificateMaterial.generate()
        XCTAssertGreaterThan(material.derBytes.count, 0)
        let secCert = SecCertificateCreateWithData(nil, Data(material.derBytes) as CFData)
        XCTAssertNotNil(secCert, "DER bytes must be accepted by SecCertificateCreateWithData")
    }

    func testMakeSecCertificateRoundTrips() throws {
        let material = try TLSCertificateMaterial.generate()
        let secCert = try TLSCertificateMaterial.makeSecCertificate(derBytes: material.derBytes)
        let roundTripped = SecCertificateCopyData(secCert) as Data
        XCTAssertEqual(Array(roundTripped), material.derBytes)
    }

    func testDifferentKeysProduceDifferentCerts() throws {
        let first = try TLSCertificateMaterial.generate()
        let second = try TLSCertificateMaterial.generate()
        XCTAssertNotEqual(first.derBytes, second.derBytes)
    }

    // MARK: - Fingerprint (pure, no Keychain)

    func testFingerprintFormat() throws {
        let material = try TLSCertificateMaterial.generate()
        let fp = TLSCertificateFacts.fingerprint(derBytes: material.derBytes)
        XCTAssertTrue(fp.hasPrefix("sha256:"), "Fingerprint must start with 'sha256:'")
        let hex = String(fp.dropFirst("sha256:".count))
        XCTAssertEqual(hex.count, 64, "SHA-256 hex should be 64 characters")
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "Must be valid hex")
        XCTAssertEqual(hex, hex.lowercased(), "Must be lowercase")
    }

    func testFingerprintDeterministic() throws {
        let material = try TLSCertificateMaterial.generate()
        let fp1 = TLSCertificateFacts.fingerprint(derBytes: material.derBytes)
        let fp2 = TLSCertificateFacts.fingerprint(derBytes: material.derBytes)
        XCTAssertEqual(fp1, fp2)
    }

    func testDifferentCertsProduceDifferentFingerprints() throws {
        let first = try TLSCertificateMaterial.generate()
        let second = try TLSCertificateMaterial.generate()
        let fp1 = TLSCertificateFacts.fingerprint(derBytes: first.derBytes)
        let fp2 = TLSCertificateFacts.fingerprint(derBytes: second.derBytes)
        XCTAssertNotEqual(fp1, fp2)
    }

    func testFingerprintMatchesCryptoKitDirectly() throws {
        let material = try TLSCertificateMaterial.generate()
        let hash = SHA256.hash(data: material.derBytes)
        let expected = "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
        let actual = TLSCertificateFacts.fingerprint(derBytes: material.derBytes)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - SecKey Bridging (no Keychain persistence needed)

    func testPrivateKeyBridgesToSecKey() throws {
        let material = try TLSCertificateMaterial.generate()
        let keyData = material.privateKey.x963Representation
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error)
        XCTAssertNotNil(secKey, "P256 private key must bridge to SecKey")
        XCTAssertNil(error)
    }

    // MARK: - Keychain Integration (hosted in BH Demo for entitlements)

    func testGetOrCreateAndRetrieve() throws {
        let label = "com.buttonheist.tls.test.\(UUID().uuidString)"
        defer { try? TLSIdentity.delete(label: label) }

        let first = try makeKeychainIdentityOrSkip(label: label)
        let second = try makeKeychainIdentityOrSkip(label: label)
        XCTAssertEqual(first.fingerprint, second.fingerprint,
                       "Same label should return the same identity")
    }

    func testDeleteRemovesIdentity() throws {
        let label = "com.buttonheist.tls.test.\(UUID().uuidString)"

        let first = try makeKeychainIdentityOrSkip(label: label)
        do {
            try TLSIdentity.delete(label: label)
        } catch {
            try skipIfKeychainUnavailable(error)
            throw error
        }
        let second = try makeKeychainIdentityOrSkip(label: label)
        XCTAssertNotEqual(first.fingerprint, second.fingerprint,
                          "After delete, a new identity should be generated")
        do {
            try TLSIdentity.delete(label: label)
        } catch {
            try skipIfKeychainUnavailable(error)
            throw error
        }
    }

    func testEphemeralIdentityProducesValidTLSParameters() async throws {
        let identity = try makeEphemeralIdentityOrSkip()
        let params = await identity.makeTLSParameters()
        XCTAssertNotNil(params, "makeTLSParameters must succeed for valid ephemeral identity")
    }

    private func makeKeychainIdentityOrSkip(label: String) throws -> TLSIdentity {
        do {
            return try TLSIdentity.getOrCreate(label: label)
        } catch {
            try skipIfKeychainUnavailable(error)
            throw error
        }
    }
}

func makeEphemeralIdentityOrSkip() throws -> TLSIdentity {
    do {
        return try TLSIdentity.createEphemeral()
    } catch {
        try skipIfKeychainUnavailable(error)
        throw error
    }
}

func skipIfKeychainUnavailable(_ error: Error) throws {
    guard case TLSIdentityError.keychainError(let status) = error,
          status == errSecMissingEntitlement || status == errSecWrPerm else {
        return
    }
    throw XCTSkip("Keychain identity storage is unavailable in this test runner (OSStatus \(status)).")
}
