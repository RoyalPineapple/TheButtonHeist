#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct InsideJobRuntimeConfiguration: Equatable, Sendable {
    let token: ResolvedStartupValue<SessionAuthToken>
    let preferredPort: ResolvedStartupValue<UInt16>
    let allowedScopes: ResolvedStartupValue<Set<ConnectionScope>>
    let addressFamily: ListenerAddressFamily
    let sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>
    let fingerprintsEnabled: ResolvedStartupValue<Bool>
    let failureEvidencePolicy: ResolvedStartupValue<FailureEvidencePolicy>
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
        let resolvedInstanceId = ResolvedStartupValue(
            value: explicitInstanceId,
            source: explicitInstanceId == nil ? .generated : .api
        )
        return InsideJobRuntimeConfiguration(
            token: resolvedToken,
            preferredPort: ResolvedStartupValue(
                value: port,
                source: port == 0 ? .defaultValue : .api
            ),
            allowedScopes: allowedScopes.map {
                ResolvedStartupValue(value: $0, source: .api)
            } ?? startupConfiguration.allowedScopes,
            addressFamily: addressFamily,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout,
            fingerprintsEnabled: fingerprintsEnabled.map {
                ResolvedStartupValue(value: $0, source: .api)
            } ?? startupConfiguration.fingerprintsEnabled,
            failureEvidencePolicy: startupConfiguration.failureEvidencePolicy,
            sessionIdentity: InsideJobSessionIdentity.make(instanceId: resolvedInstanceId)
        )
    }

    static func resolve(startupConfiguration: StartupConfiguration) -> InsideJobRuntimeConfiguration {
        let resolvedToken = resolvedRuntimeToken(
            explicitToken: nil,
            startupToken: startupConfiguration.token
        )
        return InsideJobRuntimeConfiguration(
            token: resolvedToken,
            preferredPort: startupConfiguration.preferredPort,
            allowedScopes: startupConfiguration.allowedScopes,
            addressFamily: .dualStack,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout,
            fingerprintsEnabled: startupConfiguration.fingerprintsEnabled,
            failureEvidencePolicy: startupConfiguration.failureEvidencePolicy,
            sessionIdentity: InsideJobSessionIdentity.make(instanceId: startupConfiguration.instanceId)
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
}

struct InsideJobSessionIdentity: Equatable, Sendable {
    let launchId: ServerLaunchID
    let installationId: InstallationID
    let effectiveInstanceId: ResolvedStartupValue<InsideJobInstanceID>

    static func make(
        instanceId: ResolvedStartupValue<InsideJobInstanceID?>
    ) -> InsideJobSessionIdentity {
        guard let launchId = try? ServerLaunchID(validating: UUID().uuidString),
              let generatedInstanceId = try? InsideJobInstanceID(
                validating: String(launchId.description.prefix(8)).lowercased()
              ) else {
            preconditionFailure("UUID generation produced a blank server identity")
        }
        return InsideJobSessionIdentity(
            launchId: launchId,
            installationId: loadInstallationId(),
            effectiveInstanceId: instanceId.value.map {
                ResolvedStartupValue(value: $0, source: instanceId.source)
            } ?? ResolvedStartupValue(value: generatedInstanceId, source: .generated)
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
        runtimeConfiguration.sessionIdentity.effectiveInstanceId.value
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
