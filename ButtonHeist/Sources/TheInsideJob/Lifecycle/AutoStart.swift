#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

private let autoStartLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "autostart")

/// Called from Objective-C +load method to auto-start the server.
/// Configuration via environment variables (highest priority) or Info.plist:
/// - INSIDEJOB_DISABLE / InsideJobDisableAutoStart: Set to true to disable
/// - INSIDEJOB_TOKEN / InsideJobToken: Auth token (auto-generated if not set)
/// - INSIDEJOB_ID / InsideJobInstanceId: Human-readable instance identifier
/// - INSIDEJOB_POLLING_INTERVAL / InsideJobPollingInterval: Polling interval in seconds
/// - INSIDEJOB_PORT / InsideJobPort: Fixed TCP port to listen on (0 or unset = any available)
@_cdecl("TheInsideJob_autoStartFromLoad")
public func theInsideJobAutoStartFromLoad() {
    autoStartLogger.info("========== AUTO-START BEGIN ==========")
    autoStartLogger.info("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")

    // Check INSIDEJOB_DISABLE environment variable
    if EnvironmentKey.insideJobDisable.boolValue {
        autoStartLogger.info("Auto-start disabled via INSIDEJOB_DISABLE")
        return
    }

    // Check Info.plist InsideJobDisableAutoStart
    if let disable = Bundle.main.object(forInfoDictionaryKey: "InsideJobDisableAutoStart") as? Bool, disable {
        autoStartLogger.info("Auto-start disabled via Info.plist")
        return
    }

    // Get polling interval (default 1.0, minimum 0.5)
    var interval: TimeInterval = 1.0
    if let envInterval = EnvironmentKey.insideJobPollingInterval.value,
       let parsed = TimeInterval(envInterval) {
        interval = max(0.5, parsed)
    } else if let plistInterval = Bundle.main.object(forInfoDictionaryKey: "InsideJobPollingInterval") as? Double {
        interval = max(0.5, plistInterval)
    }

    // Get auth token
    var token: String?
    if let envToken = EnvironmentKey.insideJobToken.value {
        token = envToken
    } else if let plistToken = Bundle.main.object(forInfoDictionaryKey: "InsideJobToken") as? String {
        token = plistToken
    }

    // Get instance ID
    var instanceId: String?
    if let envId = EnvironmentKey.insideJobId.value {
        instanceId = envId
    } else if let plistId = Bundle.main.object(forInfoDictionaryKey: "InsideJobInstanceId") as? String {
        instanceId = plistId
    }

    // Get preferred port (0 = any available)
    var port: UInt16 = 0
    if let envPort = EnvironmentKey.insideJobPort.value,
       let parsed = UInt16(envPort), parsed > 0 {
        port = parsed
    } else if let plistPort = Bundle.main.object(forInfoDictionaryKey: "InsideJobPort") as? Int,
              plistPort > 0, plistPort <= UInt16.max {
        port = UInt16(plistPort)
    }

    autoStartLogger.info("Starting with polling interval: \(interval)")

    Task { @MainActor in
        autoStartLogger.debug("MainActor task executing...")
        autoStartLogger.info("Device: \(UIDevice.current.name)")
        autoStartLogger.info("System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        do {
            TheInsideJob.configure(token: token, instanceId: instanceId, port: port)
            try await TheInsideJob.shared.start()
            TheInsideJob.shared.startPolling(interval: interval)
            autoStartLogger.info("========== AUTO-START SUCCESS ==========")
        } catch {
            autoStartLogger.error("========== AUTO-START FAILED: \(error) ==========")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
