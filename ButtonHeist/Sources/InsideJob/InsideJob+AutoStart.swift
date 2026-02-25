#if canImport(UIKit)
#if DEBUG
import UIKit

/// Called from Objective-C +load method to auto-start the server.
/// Configuration via environment variables (highest priority) or Info.plist:
/// - INSIDEJOB_DISABLE / InsideJobDisableAutoStart: Set to true to disable
/// - INSIDEJOB_TOKEN / InsideJobToken: Auth token (auto-generated if not set)
/// - INSIDEJOB_ID / InsideJobInstanceId: Human-readable instance identifier
/// - INSIDEJOB_POLLING_INTERVAL / InsideJobPollingInterval: Polling interval in seconds
@_cdecl("InsideJob_autoStartFromLoad")
public func insideJobAutoStartFromLoad() {
    NSLog("[InsideJob] ========== AUTO-START BEGIN ==========")
    NSLog("[InsideJob] Bundle ID: %@", Bundle.main.bundleIdentifier ?? "unknown")
    NSLog("[InsideJob] Device: %@", UIDevice.current.name)
    NSLog("[InsideJob] System: %@ %@", UIDevice.current.systemName, UIDevice.current.systemVersion)

    // Check INSIDEJOB_DISABLE environment variable
    if let envValue = ProcessInfo.processInfo.environment["INSIDEJOB_DISABLE"],
       ["true", "1", "yes"].contains(envValue.lowercased()) {
        NSLog("[InsideJob] Auto-start disabled via INSIDEJOB_DISABLE")
        return
    }

    // Check Info.plist InsideJobDisableAutoStart
    if let disable = Bundle.main.object(forInfoDictionaryKey: "InsideJobDisableAutoStart") as? Bool, disable {
        NSLog("[InsideJob] Auto-start disabled via Info.plist")
        return
    }

    // Get polling interval (default 1.0, minimum 0.5)
    var interval: TimeInterval = 1.0
    if let envInterval = ProcessInfo.processInfo.environment["INSIDEJOB_POLLING_INTERVAL"],
       let parsed = TimeInterval(envInterval) {
        interval = max(0.5, parsed)
    } else if let plistInterval = Bundle.main.object(forInfoDictionaryKey: "InsideJobPollingInterval") as? Double {
        interval = max(0.5, plistInterval)
    }

    // Get auth token
    var token: String?
    if let envToken = ProcessInfo.processInfo.environment["INSIDEJOB_TOKEN"] {
        token = envToken
    } else if let plistToken = Bundle.main.object(forInfoDictionaryKey: "InsideJobToken") as? String {
        token = plistToken
    }

    // Get instance ID
    var instanceId: String?
    if let envId = ProcessInfo.processInfo.environment["INSIDEJOB_ID"] {
        instanceId = envId
    } else if let plistId = Bundle.main.object(forInfoDictionaryKey: "InsideJobInstanceId") as? String {
        instanceId = plistId
    }

    NSLog("[InsideJob] Starting with polling interval: %f", interval)

    Task { @MainActor in
        NSLog("[InsideJob] MainActor task executing...")
        do {
            InsideJob.configure(token: token, instanceId: instanceId)
            try InsideJob.shared.start()
            InsideJob.shared.startPolling(interval: interval)
            NSLog("[InsideJob] ========== AUTO-START SUCCESS ==========")
        } catch {
            NSLog("[InsideJob] ========== AUTO-START FAILED: %@ ==========", String(describing: error))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
