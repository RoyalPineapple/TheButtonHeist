import Foundation
import Security
import os.log

private let tlsIdentityLogger = Logger(subsystem: "com.buttonheist.thegetaway", category: "tls")

actor TLSIdentity {
    let identity: SecIdentity
    private let certificate: SecCertificate
    nonisolated let fingerprint: String
    nonisolated let expiryDate: Date

    /// Number of days before expiry at which the certificate is auto-renewed.
    static let renewalThresholdDays: Int = 30

    /// Number of days before expiry at which a warning is logged.
    static let warningThresholdDays: Int = 60

    init(identity: SecIdentity, certificate: SecCertificate, fingerprint: String, expiryDate: Date) {
        self.identity = identity
        self.certificate = certificate
        self.fingerprint = fingerprint
        self.expiryDate = expiryDate
    }

    init(identity: SecIdentity, material: TLSCertificateMaterial) {
        self.init(
            identity: identity,
            certificate: material.certificate,
            fingerprint: material.fingerprint,
            expiryDate: material.expiryDate
        )
    }

    /// Retrieve an existing identity from the Keychain, or create and store a new one.
    /// If the loaded certificate expires within ``renewalThresholdDays`` days, it is
    /// deleted and a fresh one is generated. A warning is logged if expiry is within
    /// ``warningThresholdDays`` days.
    static func getOrCreate(label: String = "com.buttonheist.tls") throws -> TLSIdentity {
        if let existing = try TLSIdentityKeychain.load(label: label) {
            let daysRemaining = existing.daysUntilExpiry
            if daysRemaining <= renewalThresholdDays {
                tlsIdentityLogger.warning(
                    "TLS certificate expires in \(daysRemaining) day(s) — regenerating"
                )
                try TLSIdentityKeychain.delete(label: label)
            } else {
                if daysRemaining <= warningThresholdDays {
                    tlsIdentityLogger.warning(
                        "TLS certificate expires in \(daysRemaining) day(s) — consider renewal soon"
                    )
                }
                tlsIdentityLogger.debug("Loaded existing TLS identity from Keychain")
                return existing
            }
        }

        tlsIdentityLogger.info("No existing TLS identity found, generating new one")
        let material = try TLSCertificateMaterial.generate()
        let secIdentity = try TLSIdentityKeychain.store(material: material, label: label)
        tlsIdentityLogger.info("TLS identity stored in Keychain: \(material.fingerprint)")
        return TLSIdentity(identity: secIdentity, material: material)
    }

    /// Create an explicitly requested ephemeral identity by temporarily storing
    /// items in the Keychain for `SecIdentity` creation, then immediately
    /// removing them.
    static func createEphemeral() throws -> TLSIdentity {
        let material = try TLSCertificateMaterial.generate()
        let secIdentity = try TLSIdentityKeychain.createEphemeralIdentity(material: material)
        tlsIdentityLogger.info("Created ephemeral TLS identity: \(material.fingerprint)")
        return TLSIdentity(identity: secIdentity, material: material)
    }

    /// Remove a stored identity from the Keychain.
    static func delete(label: String = "com.buttonheist.tls") throws(TLSIdentityError) {
        try TLSIdentityKeychain.delete(label: label)
    }

    /// Number of whole days until this certificate expires (negative if already expired).
    nonisolated var daysUntilExpiry: Int {
        let interval = expiryDate.timeIntervalSinceNow
        return Int(interval / (24 * 3600))
    }
}
