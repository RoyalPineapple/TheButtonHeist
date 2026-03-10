import XCTest
import Security
import Crypto
@testable import TheGetaway

final class TLSIdentityTests: XCTestCase {

    // MARK: - Certificate Generation (pure, no Keychain)

    func testGenerateCertificateProducesValidDER() throws {
        let (_, derBytes) = try TLSIdentity.generateCertificate()
        XCTAssertGreaterThan(derBytes.count, 0)
        let secCert = SecCertificateCreateWithData(nil, Data(derBytes) as CFData)
        XCTAssertNotNil(secCert, "DER bytes must be accepted by SecCertificateCreateWithData")
    }

    func testMakeSecCertificateRoundTrips() throws {
        let (_, derBytes) = try TLSIdentity.generateCertificate()
        let secCert = try TLSIdentity.makeSecCertificate(derBytes: derBytes)
        let roundTripped = SecCertificateCopyData(secCert) as Data
        XCTAssertEqual(Array(roundTripped), derBytes)
    }

    func testDifferentKeysProduceDifferentCerts() throws {
        let (_, der1) = try TLSIdentity.generateCertificate()
        let (_, der2) = try TLSIdentity.generateCertificate()
        XCTAssertNotEqual(der1, der2)
    }

    // MARK: - Fingerprint (pure, no Keychain)

    func testFingerprintFormat() throws {
        let (_, derBytes) = try TLSIdentity.generateCertificate()
        let fp = TLSIdentity.computeFingerprint(derBytes: derBytes)
        XCTAssertTrue(fp.hasPrefix("sha256:"), "Fingerprint must start with 'sha256:'")
        let hex = String(fp.dropFirst("sha256:".count))
        XCTAssertEqual(hex.count, 64, "SHA-256 hex should be 64 characters")
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "Must be valid hex")
        XCTAssertEqual(hex, hex.lowercased(), "Must be lowercase")
    }

    func testFingerprintDeterministic() throws {
        let (_, derBytes) = try TLSIdentity.generateCertificate()
        let fp1 = TLSIdentity.computeFingerprint(derBytes: derBytes)
        let fp2 = TLSIdentity.computeFingerprint(derBytes: derBytes)
        XCTAssertEqual(fp1, fp2)
    }

    func testDifferentCertsProduceDifferentFingerprints() throws {
        let (_, der1) = try TLSIdentity.generateCertificate()
        let (_, der2) = try TLSIdentity.generateCertificate()
        let fp1 = TLSIdentity.computeFingerprint(derBytes: der1)
        let fp2 = TLSIdentity.computeFingerprint(derBytes: der2)
        XCTAssertNotEqual(fp1, fp2)
    }

    func testFingerprintMatchesCryptoKitDirectly() throws {
        let (_, derBytes) = try TLSIdentity.generateCertificate()
        let hash = SHA256.hash(data: derBytes)
        let expected = "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
        let actual = TLSIdentity.computeFingerprint(derBytes: derBytes)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - SecKey Bridging (no Keychain persistence needed)

    func testPrivateKeyBridgesToSecKey() throws {
        let (privateKey, _) = try TLSIdentity.generateCertificate()
        let keyData = privateKey.x963Representation
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

    // MARK: - Keychain Integration (may fail without entitlements)

    func testGetOrCreateAndRetrieve() throws {
        let label = "com.buttonheist.tls.test.\(UUID().uuidString)"
        defer { try? TLSIdentity.delete(label: label) }

        do {
            let first = try TLSIdentity.getOrCreate(label: label)
            let second = try TLSIdentity.getOrCreate(label: label)
            XCTAssertEqual(first.fingerprint, second.fingerprint,
                           "Same label should return the same identity")
        } catch let error as TLSIdentityError {
            if case .keychainError(let status) = error, status == -34018 {
                throw XCTSkip("Keychain not available in this test environment (errSecMissingEntitlement)")
            }
            throw error
        }
    }

    func testDeleteRemovesIdentity() throws {
        let label = "com.buttonheist.tls.test.\(UUID().uuidString)"

        do {
            let first = try TLSIdentity.getOrCreate(label: label)
            try TLSIdentity.delete(label: label)
            let second = try TLSIdentity.getOrCreate(label: label)
            XCTAssertNotEqual(first.fingerprint, second.fingerprint,
                              "After delete, a new identity should be generated")
            try TLSIdentity.delete(label: label)
        } catch let error as TLSIdentityError {
            if case .keychainError = error {
                throw XCTSkip("Keychain not fully available in this test environment")
            }
            throw error
        }
    }

    func testEphemeralIdentityProducesValidSecIdentity() throws {
        do {
            let identity = try TLSIdentity.createEphemeral()
            let secId = sec_identity_create(identity.identity)
            XCTAssertNotNil(secId, "sec_identity_create must succeed for Network framework TLS")
        } catch let error as TLSIdentityError {
            if case .keychainError(let status) = error, status == -34018 {
                throw XCTSkip("Keychain not available in this test environment (errSecMissingEntitlement)")
            }
            throw error
        }
    }
}
