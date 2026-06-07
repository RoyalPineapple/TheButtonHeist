#if canImport(UIKit)
#if DEBUG
import UIKit

@MainActor
extension TheInsideJob {
    @discardableResult
    func advertiseService(on transport: ServerTransport, port: UInt16) -> String? {
        let exposure = ServerExposure(allowedScopes: runtimeConfiguration.allowedScopes)
        guard exposure.publishesBonjour else {
            insideJobLogger.info("Bonjour advertisement disabled: \(exposure.bonjourDisabledReason ?? "unknown", privacy: .public)")
            return nil
        }

        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)#\(effectiveInstanceId)"

        transport.advertise(
            serviceName: serviceName,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            installationId: runtimeConfiguration.sessionIdentity.installationId,
            instanceId: effectiveInstanceId,
            additionalTXT: [
                "devicename": UIDevice.current.name
            ]
        )

        return serviceName
    }

    func logStartupSummary(
        actualPort: UInt16,
        bonjourServiceName: String?
    ) {
        let scopeNames = runtimeConfiguration.allowedScopes.map(\.rawValue).sorted().joined(separator: ",")
        let bonjourDescription = if let bonjourServiceName {
            "bonjour=advertising service=\(bonjourServiceName)"
        } else {
            "bonjour=disabled reason=network-scope-not-enabled"
        }
        let fields = [
            "actualPort=\(actualPort)",
            "preferredPort=\(runtimeConfiguration.preferredPort)(\(runtimeConfiguration.preferredPortSource.label))",
            "tokenSource=\(runtimeConfiguration.tokenSource.label)",
            "sessionId=\(runtimeConfiguration.sessionIdentity.sessionId.uuidString)",
            "instanceIdentifier=\(effectiveInstanceId)(\(runtimeConfiguration.instanceIdSource.label))",
            "allowedScopes=\(scopeNames)(\(runtimeConfiguration.allowedScopesSource.label))",
            "sessionTimeout=\(runtimeConfiguration.sessionReleaseTimeout.value)s(\(runtimeConfiguration.sessionReleaseTimeout.source.label))",
            "tls=psk",
            bonjourDescription
        ].joined(separator: " ")
        insideJobLogger.info("Startup summary: \(fields, privacy: .public) token=<redacted>")
        if runtimeConfiguration.tokenSource == .generated, let token = runtimeConfiguration.token {
            insideJobLogger.warning("Generated ButtonHeist token: BUTTONHEIST_TOKEN=\(token, privacy: .public)")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
