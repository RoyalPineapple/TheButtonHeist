#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct InsideJobRuntimeConfiguration: Equatable, Sendable {
    let token: SessionAuthToken
    let tokenSource: StartupConfigurationSource
    let instanceIdSource: StartupConfigurationSource
    let preferredPort: UInt16
    let preferredPortSource: StartupConfigurationSource
    let allowedScopes: Set<ConnectionScope>
    let allowedScopesSource: StartupConfigurationSource
    let addressFamily: ListenerAddressFamily
    let sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>
    let fingerprintsEnabled: Bool
    let fingerprintsEnabledSource: StartupConfigurationSource
    let failureEvidencePolicy: FailureEvidencePolicy
    let failureEvidencePolicySource: StartupConfigurationSource
    let sessionIdentity: InsideJobSessionIdentity

    static func resolve(
        startupConfiguration: StartupConfiguration,
        token: String?,
        instanceId: String?,
        allowedScopes: Set<ConnectionScope>?,
        port: UInt16,
        addressFamily: ListenerAddressFamily = .dualStack,
        fingerprintsEnabled: Bool? = nil
    ) -> InsideJobRuntimeConfiguration {
        let explicitToken = token.flatMap { try? SessionAuthToken(validating: $0) }
        let explicitInstanceId = instanceId.flatMap { try? InsideJobInstanceID(validating: $0) }
        let resolvedToken = resolvedRuntimeToken(
            explicitToken: explicitToken,
            startupToken: startupConfiguration.token
        )
        return InsideJobRuntimeConfiguration(
            token: resolvedToken.value,
            tokenSource: resolvedToken.source,
            instanceId: explicitInstanceId,
            instanceIdSource: explicitInstanceId == nil ? .generated : .api,
            preferredPort: port,
            preferredPortSource: port == 0 ? .defaultValue : .api,
            allowedScopes: allowedScopes ?? startupConfiguration.allowedScopes.value,
            allowedScopesSource: allowedScopes == nil ? startupConfiguration.allowedScopes.source : .api,
            addressFamily: addressFamily,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout,
            fingerprintsEnabled: fingerprintsEnabled ?? startupConfiguration.fingerprintsEnabled.value,
            fingerprintsEnabledSource: fingerprintsEnabled == nil ? startupConfiguration.fingerprintsEnabled.source : .api,
            failureEvidencePolicy: startupConfiguration.failureEvidencePolicy.value,
            failureEvidencePolicySource: startupConfiguration.failureEvidencePolicy.source
        )
    }

    static func resolve(startupConfiguration: StartupConfiguration) -> InsideJobRuntimeConfiguration {
        let resolvedToken = resolvedRuntimeToken(
            explicitToken: nil,
            startupToken: startupConfiguration.token
        )
        return InsideJobRuntimeConfiguration(
            token: resolvedToken.value,
            tokenSource: resolvedToken.source,
            instanceId: startupConfiguration.instanceId.value,
            instanceIdSource: startupConfiguration.instanceId.source,
            preferredPort: startupConfiguration.preferredPort.value,
            preferredPortSource: startupConfiguration.preferredPort.source,
            allowedScopes: startupConfiguration.allowedScopes.value,
            allowedScopesSource: startupConfiguration.allowedScopes.source,
            addressFamily: .dualStack,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout,
            fingerprintsEnabled: startupConfiguration.fingerprintsEnabled.value,
            fingerprintsEnabledSource: startupConfiguration.fingerprintsEnabled.source,
            failureEvidencePolicy: startupConfiguration.failureEvidencePolicy.value,
            failureEvidencePolicySource: startupConfiguration.failureEvidencePolicy.source
        )
    }

    private static func resolvedRuntimeToken(
        explicitToken: SessionAuthToken?,
        startupToken: ResolvedStartupValue<SessionAuthToken?>
    ) -> ResolvedStartupValue<SessionAuthToken> {
        if let explicitToken {
            return ResolvedStartupValue(value: explicitToken, source: .api)
        }
        if let startupTokenValue = startupToken.value {
            return ResolvedStartupValue(value: startupTokenValue, source: startupToken.source)
        }
        return ResolvedStartupValue(value: GeneratedSessionToken.make(), source: .generated)
    }

    init(
        token: SessionAuthToken,
        tokenSource: StartupConfigurationSource,
        instanceId: InsideJobInstanceID?,
        instanceIdSource: StartupConfigurationSource,
        preferredPort: UInt16,
        preferredPortSource: StartupConfigurationSource,
        allowedScopes: Set<ConnectionScope>,
        allowedScopesSource: StartupConfigurationSource,
        addressFamily: ListenerAddressFamily = .dualStack,
        sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>,
        fingerprintsEnabled: Bool = true,
        fingerprintsEnabledSource: StartupConfigurationSource = .defaultValue,
        failureEvidencePolicy: FailureEvidencePolicy = .screenshot,
        failureEvidencePolicySource: StartupConfigurationSource = .defaultValue,
        sessionIdentity: InsideJobSessionIdentity? = nil
    ) {
        self.token = token
        self.tokenSource = tokenSource
        self.instanceIdSource = instanceIdSource
        self.preferredPort = preferredPort
        self.preferredPortSource = preferredPortSource
        self.allowedScopes = allowedScopes
        self.allowedScopesSource = allowedScopesSource
        self.addressFamily = addressFamily
        self.sessionReleaseTimeout = sessionReleaseTimeout
        self.fingerprintsEnabled = fingerprintsEnabled
        self.fingerprintsEnabledSource = fingerprintsEnabledSource
        self.failureEvidencePolicy = failureEvidencePolicy
        self.failureEvidencePolicySource = failureEvidencePolicySource
        self.sessionIdentity = sessionIdentity ?? InsideJobSessionIdentity.make(instanceId: instanceId)
    }
}

struct InsideJobSessionIdentity: Equatable, Sendable {
    let launchId: ServerLaunchID
    let installationId: InstallationID
    let effectiveInstanceId: InsideJobInstanceID

    static func make(instanceId: InsideJobInstanceID?) -> InsideJobSessionIdentity {
        guard let launchId = try? ServerLaunchID(validating: UUID().uuidString),
              let generatedInstanceId = try? InsideJobInstanceID(
                validating: String(launchId.description.prefix(8)).lowercased()
              ) else {
            preconditionFailure("UUID generation produced a blank server identity")
        }
        return InsideJobSessionIdentity(
            launchId: launchId,
            installationId: loadInstallationId(),
            effectiveInstanceId: instanceId ?? generatedInstanceId
        )
    }

    private static func loadInstallationId() -> InstallationID {
        let defaultsKey = "\(Bundle.main.insideJobIdentifier).installation-id"

        if let existing = UserDefaults.standard.string(forKey: defaultsKey),
           let installationId = try? InstallationID(validating: existing) {
            return installationId
        }

        guard let generated = try? InstallationID(validating: UUID().uuidString.lowercased()) else {
            preconditionFailure("UUID generation produced a blank installation ID")
        }
        UserDefaults.standard.set(generated.description, forKey: defaultsKey)
        return generated
    }
}

@MainActor
extension TheInsideJob {
    var effectiveInstanceId: InsideJobInstanceID {
        runtimeConfiguration.sessionIdentity.effectiveInstanceId
    }
}

extension Bundle {
    var insideJobIdentifier: BundleIdentifier {
        guard let bundleIdentifier,
              let identifier = try? BundleIdentifier(validating: bundleIdentifier) else {
            return "com.buttonheist.theinsidejob"
        }
        return identifier
    }
}

extension ProcessInfo {
    var simulatorUDID: SimulatorUDID? {
        environment[.udid].flatMap { try? SimulatorUDID(validating: $0) }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
