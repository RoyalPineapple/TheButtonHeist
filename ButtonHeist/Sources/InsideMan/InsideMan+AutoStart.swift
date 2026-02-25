#if canImport(UIKit)
#if DEBUG
import UIKit

/// Called from Objective-C +load method to auto-start the server.
/// Configuration via environment variables (highest priority) or Info.plist:
/// - INSIDEMAN_DISABLE / InsideManDisableAutoStart: Set to true to disable
/// - INSIDEMAN_PORT / InsideManPort: Fixed port number (0 = auto, default)
/// - INSIDEMAN_TOKEN / InsideManToken: Auth token (auto-generated if not set)
/// - INSIDEMAN_ID / InsideManInstanceId: Human-readable instance identifier
/// - INSIDEMAN_POLLING_INTERVAL / InsideManPollingInterval: Polling interval in seconds
@_cdecl("InsideMan_autoStartFromLoad")
public func insideManAutoStartFromLoad() {
    NSLog("[InsideMan] ========== AUTO-START BEGIN ==========")
    NSLog("[InsideMan] Bundle ID: %@", Bundle.main.bundleIdentifier ?? "unknown")
    NSLog("[InsideMan] Device: %@", UIDevice.current.name)
    NSLog("[InsideMan] System: %@ %@", UIDevice.current.systemName, UIDevice.current.systemVersion)

    // Check INSIDEMAN_DISABLE environment variable
    if let envValue = ProcessInfo.processInfo.environment["INSIDEMAN_DISABLE"],
       ["true", "1", "yes"].contains(envValue.lowercased()) {
        NSLog("[InsideMan] Auto-start disabled via INSIDEMAN_DISABLE")
        return
    }

    // Check Info.plist InsideManDisableAutoStart
    if let disable = Bundle.main.object(forInfoDictionaryKey: "InsideManDisableAutoStart") as? Bool, disable {
        NSLog("[InsideMan] Auto-start disabled via Info.plist")
        return
    }

    // Get fixed port (0 = auto-assign)
    var port: UInt16 = 0
    if let envPort = ProcessInfo.processInfo.environment["INSIDEMAN_PORT"],
       let parsed = UInt16(envPort) {
        port = parsed
    } else if let plistPort = Bundle.main.object(forInfoDictionaryKey: "InsideManPort") as? Int {
        port = UInt16(clamping: plistPort)
    }

    // Get polling interval (default 1.0, minimum 0.5)
    var interval: TimeInterval = 1.0
    if let envInterval = ProcessInfo.processInfo.environment["INSIDEMAN_POLLING_INTERVAL"],
       let parsed = TimeInterval(envInterval) {
        interval = max(0.5, parsed)
    } else if let plistInterval = Bundle.main.object(forInfoDictionaryKey: "InsideManPollingInterval") as? Double {
        interval = max(0.5, plistInterval)
    }

    // Get auth token
    var token: String?
    if let envToken = ProcessInfo.processInfo.environment["INSIDEMAN_TOKEN"] {
        token = envToken
    } else if let plistToken = Bundle.main.object(forInfoDictionaryKey: "InsideManToken") as? String {
        token = plistToken
    }

    // Get instance ID
    var instanceId: String?
    if let envId = ProcessInfo.processInfo.environment["INSIDEMAN_ID"] {
        instanceId = envId
    } else if let plistId = Bundle.main.object(forInfoDictionaryKey: "InsideManInstanceId") as? String {
        instanceId = plistId
    }

    NSLog("[InsideMan] Starting with port: %d, polling interval: %f", port, interval)

    Task { @MainActor in
        NSLog("[InsideMan] MainActor task executing...")
        do {
            InsideMan.configure(port: port, token: token, instanceId: instanceId)
            try InsideMan.shared.start()
            InsideMan.shared.startPolling(interval: interval)
            NSLog("[InsideMan] ========== AUTO-START SUCCESS ==========")
        } catch {
            NSLog("[InsideMan] ========== AUTO-START FAILED: %@ ==========", String(describing: error))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
