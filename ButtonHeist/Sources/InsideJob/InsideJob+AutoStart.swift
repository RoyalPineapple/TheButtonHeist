#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

private let autoStartLogger = Logger(subsystem: "com.buttonheist.insidejob", category: "autostart")

/// Bridge class for Objective-C +load auto-start.
/// Configuration via environment variables (highest priority) or Info.plist:
/// - INSIDEJOB_DISABLE / InsideJobDisableAutoStart: Set to true to disable
/// - INSIDEJOB_TOKEN / InsideJobToken: Auth token (auto-generated if not set)
/// - INSIDEJOB_ID / InsideJobInstanceId: Human-readable instance identifier
/// - INSIDEJOB_POLLING_INTERVAL / InsideJobPollingInterval: Polling interval in seconds
@objc public class InsideJobAutoStarter: NSObject {
    @objc public static func autoStart() {
        autoStartLogger.info("========== AUTO-START BEGIN ==========")
        autoStartLogger.info("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        autoStartLogger.info("Device: \(UIDevice.current.name)")
        autoStartLogger.info("System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")

        // Check INSIDEJOB_DISABLE environment variable
        if let envValue = ProcessInfo.processInfo.environment["INSIDEJOB_DISABLE"],
           ["true", "1", "yes"].contains(envValue.lowercased()) {
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

        autoStartLogger.info("Starting with polling interval: \(interval)")

        Task { @MainActor in
            autoStartLogger.debug("MainActor task executing...")
            do {
                InsideJob.configure(token: token, instanceId: instanceId)
                try InsideJob.shared.start()
                InsideJob.shared.startPolling(interval: interval)
                autoStartLogger.info("========== AUTO-START SUCCESS ==========")
            } catch {
                autoStartLogger.error("========== AUTO-START FAILED: \(error) ==========")
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
