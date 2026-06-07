#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct InsideJobRuntimeConfiguration: Equatable, Sendable {
    let token: String?
    let tokenSource: StartupConfigurationSource
    let instanceIdSource: StartupConfigurationSource
    let preferredPort: UInt16
    let preferredPortSource: StartupConfigurationSource
    let allowedScopes: Set<ConnectionScope>
    let allowedScopesSource: StartupConfigurationSource
    let sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>
    let sessionIdentity: InsideJobSessionIdentity

    static func resolve(
        startupConfiguration: StartupConfiguration,
        token: String?,
        instanceId: String?,
        allowedScopes: Set<ConnectionScope>?,
        port: UInt16
    ) -> InsideJobRuntimeConfiguration {
        let resolvedToken = resolvedRuntimeToken(
            explicitToken: token,
            startupToken: startupConfiguration.token
        )
        return InsideJobRuntimeConfiguration(
            token: resolvedToken.value,
            tokenSource: resolvedToken.source,
            instanceId: instanceId,
            instanceIdSource: instanceId == nil ? .generated : .api,
            preferredPort: port,
            preferredPortSource: port == 0 ? .defaultValue : .api,
            allowedScopes: allowedScopes ?? startupConfiguration.allowedScopes.value,
            allowedScopesSource: allowedScopes == nil ? startupConfiguration.allowedScopes.source : .api,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout
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
            sessionReleaseTimeout: startupConfiguration.sessionTimeout
        )
    }

    private static func resolvedRuntimeToken(
        explicitToken: String?,
        startupToken: ResolvedStartupValue<String?>
    ) -> ResolvedStartupValue<String> {
        if let explicitToken = nonEmptyToken(explicitToken) {
            return ResolvedStartupValue(value: explicitToken, source: .api)
        }
        if let startupTokenValue = nonEmptyToken(startupToken.value) {
            return ResolvedStartupValue(value: startupTokenValue, source: startupToken.source)
        }
        return ResolvedStartupValue(value: GeneratedSessionToken.make(), source: .generated)
    }

    private static func nonEmptyToken(_ token: String?) -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }

    init(
        token: String?,
        tokenSource: StartupConfigurationSource,
        instanceId: String?,
        instanceIdSource: StartupConfigurationSource,
        preferredPort: UInt16,
        preferredPortSource: StartupConfigurationSource,
        allowedScopes: Set<ConnectionScope>,
        allowedScopesSource: StartupConfigurationSource,
        sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>,
        sessionIdentity: InsideJobSessionIdentity? = nil
    ) {
        self.token = token
        self.tokenSource = tokenSource
        self.instanceIdSource = instanceIdSource
        self.preferredPort = preferredPort
        self.preferredPortSource = preferredPortSource
        self.allowedScopes = allowedScopes
        self.allowedScopesSource = allowedScopesSource
        self.sessionReleaseTimeout = sessionReleaseTimeout
        self.sessionIdentity = sessionIdentity ?? InsideJobSessionIdentity.make(instanceId: instanceId)
    }
}

struct InsideJobSessionIdentity: Equatable, Sendable {
    let sessionId: UUID
    let installationId: String
    let effectiveInstanceId: String

    static func make(instanceId: String?) -> InsideJobSessionIdentity {
        let sessionId = UUID()
        return InsideJobSessionIdentity(
            sessionId: sessionId,
            installationId: loadInstallationId(),
            effectiveInstanceId: instanceId ?? String(sessionId.uuidString.prefix(8)).lowercased()
        )
    }

    private static func loadInstallationId() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.buttonheist.theinsidejob"
        let defaultsKey = "\(bundleId).installation-id"

        if let existing = UserDefaults.standard.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: defaultsKey)
        return generated
    }
}

@MainActor
extension TheInsideJob {
    var effectiveInstanceId: String {
        runtimeConfiguration.sessionIdentity.effectiveInstanceId
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
