#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheGetaway {

    func sendServerInfo(respond: @escaping (Data) -> Void) {
        let screenBounds = ScreenMetrics.current.bounds
        guard let listeningPort = transport?.listeningPort else {
            sendMessage(
                .error(ServerError(kind: .general, message: "Server info contract failed: transport is not listening")),
                respond: respond
            )
            return
        }
        let info = ServerInfo(
            appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            screenWidth: screenBounds.width,
            screenHeight: screenBounds.height,
            instanceId: identity.sessionId.uuidString,
            instanceIdentifier: identity.effectiveInstanceId,
            listeningPort: listeningPort,
            simulatorUDID: ProcessInfo.processInfo.environment[.udid],
            vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString,
            tlsActive: identity.tlsActive
        )
        sendMessage(.info(info), respond: respond)
    }

    func makeStatusPayload() async -> StatusPayload {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

        let identity = StatusIdentity(
            appName: appName,
            bundleIdentifier: bundleId,
            appBuild: appBuild,
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            buttonHeistVersion: buttonHeistVersion
        )

        let isActive = await muscle.isSessionActive
        let connectionCount = await muscle.activeSessionConnectionCount
        let activeDriverId = await muscle.exposedDriverId
        let session = StatusSession(
            active: isActive,
            watchersAllowed: false,
            activeConnections: connectionCount,
            activeDriverId: activeDriverId
        )

        return StatusPayload(identity: identity, session: session)
    }

    static func makePongPayload(identity: ServerIdentity) -> PongPayload {
        let info = Bundle.main.infoDictionary ?? [:]
        let appName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? ProcessInfo.processInfo.processName
        return PongPayload(
            buttonHeistVersion: buttonHeistVersion,
            appName: appName,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            appVersion: info["CFBundleShortVersionString"] as? String,
            appBuild: info["CFBundleVersion"] as? String,
            serverInstanceIdentifier: identity.effectiveInstanceId
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
