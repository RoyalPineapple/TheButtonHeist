#if canImport(UIKit)
#if DEBUG
import Foundation
import os.log
import UIKit

private let accessibilityNotificationLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

private struct CapturedAccessibilityNotification {
    let code: UInt32
    let notificationData: CapturedAccessibilityNotificationPayload
    let associatedElement: CapturedAccessibilityNotificationPayload
}

// Rationale: singleton state is protected by `lock`; callbacks copy weak subscribers before fan-out.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
final class AccessibilityNotificationObserver: @unchecked Sendable {
    static let shared = AccessibilityNotificationObserver()

    private let lock = NSLock()
    private var subscribers: [ObjectIdentifier: WeakAccessibilityNotificationSubscriber] = [:]
    private var latestSequenceStorage: UInt64 = 0

    var latestSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latestSequenceStorage
    }

    var hasSubscribers: Bool {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredSubscribers()
        return !subscribers.isEmpty
    }

    var isInstalled: Bool {
        AccessibilityNotificationCallbackState.shared.isInstalled
    }

    private init() {}

    func subscribe(_ subscriber: AccessibilityNotificationBus) {
        addSubscriber(subscriber)
        if AccessibilityNotificationPrivateSPI.enableUnitTestModeIfAvailable() {
            accessibilityNotificationLogger.info("Armed accessibility notification callback via private unit-test mode SPI")
        } else {
            accessibilityNotificationLogger.debug("Private accessibility unit-test mode SPI is unavailable")
        }
        AccessibilityNotificationCallbackState.shared.install()
    }

    func unsubscribe(_ subscriber: AccessibilityNotificationBus) {
        lock.lock()
        defer { lock.unlock() }

        subscribers[ObjectIdentifier(subscriber)] = nil
        removeExpiredSubscribers()
    }

    func uninstall() {
        removeAllSubscribers()
        AccessibilityNotificationCallbackState.shared.uninstall()
    }

    fileprivate func rebroadcast(
        code: UInt32,
        notificationData: CapturedAccessibilityNotificationPayload,
        associatedElement: CapturedAccessibilityNotificationPayload
    ) {
        let subscribers = recordAndCopySubscribers()
        for subscriber in subscribers {
            subscriber.record(
                code: code,
                notificationData: notificationData,
                associatedElement: associatedElement
            )
        }
    }

    private func addSubscriber(_ subscriber: AccessibilityNotificationBus) {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredSubscribers()
        subscribers[ObjectIdentifier(subscriber)] = WeakAccessibilityNotificationSubscriber(subscriber)
    }

    private func removeAllSubscribers() {
        lock.lock()
        defer { lock.unlock() }

        subscribers.removeAll()
    }

    private func recordAndCopySubscribers() -> [AccessibilityNotificationBus] {
        lock.lock()
        defer { lock.unlock() }

        latestSequenceStorage += 1
        removeExpiredSubscribers()
        return subscribers.values.compactMap(\.subscriber)
    }

    private func removeExpiredSubscribers() {
        subscribers = subscribers.filter { $0.value.subscriber != nil }
    }
}

private struct WeakAccessibilityNotificationSubscriber {
    weak var subscriber: AccessibilityNotificationBus?

    init(_ subscriber: AccessibilityNotificationBus) {
        self.subscriber = subscriber
    }
}

// Rationale: global registration state is protected by `lock`; registration is main-thread only.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
private final class AccessibilityNotificationCallbackState: @unchecked Sendable {
    static let shared = AccessibilityNotificationCallbackState()

    private let lock = NSLock()
    private var installedRegistration: AccessibilityNotificationPrivateSPI.InstalledCallback?

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installedRegistration != nil
    }

    func install() {
        lock.lock()
        defer { lock.unlock() }

        guard installedRegistration == nil else {
            return
        }

        do {
            installedRegistration = try AccessibilityNotificationPrivateSPI.installNotificationCallback(
                shouldCapture: {
                    AccessibilityNotificationObserver.shared.hasSubscribers
                },
                handler: { notification in
                    AccessibilityNotificationCallbackState.shared.record(notification)
                }
            )
            accessibilityNotificationLogger.info(
                "Installed accessibility notification callback source=\(self.installedRegistration?.source ?? "unknown", privacy: .public)"
            )
        } catch {
            accessibilityNotificationLogger.info(
                "accessibility notification callback install failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func uninstall() {
        lock.lock()
        defer { lock.unlock() }

        guard let installedRegistration else { return }
        do {
            try installedRegistration.uninstall()
        } catch {
            accessibilityNotificationLogger.info(
                "accessibility notification callback uninstall failed: \(String(describing: error), privacy: .public)"
            )
        }
        self.installedRegistration = nil
        accessibilityNotificationLogger.info("Removed accessibility notification callback")
    }

    private func record(_ notification: CapturedAccessibilityNotification) {
        guard AccessibilityNotificationObserver.shared.hasSubscribers else {
            return
        }

        AccessibilityNotificationObserver.shared.rebroadcast(
            code: notification.code,
            notificationData: notification.notificationData,
            associatedElement: notification.associatedElement
        )
    }

}

/// Safe Swift wrapper around the private accessibility notification SPI.
///
/// This deliberately acknowledges the risk: these are private Apple symbols,
/// may disappear or change ABI between OS releases, and must never become a
/// correctness dependency. Button Heist treats this as DEBUG-only tripwire
/// signal. If the SPI is absent or shape assumptions fail, installation fails
/// closed and the rest of the evidence pipeline continues without notification
/// hints.
///
/// Notification-specific private API handling lives in this type:
/// - C ABI function typealiases for UIAccessibility's private callbacks
/// - UIAccessibility's private block registration and removal
/// - accessibility unit-test-mode arming
///
/// Raw private symbol names, framework paths, `dlopen`, `dlsym`, and C function
/// casts are centralized in `ButtonHeistPrivateSPI`.
///
/// Everything outside this wrapper gets safe Swift operations:
/// `enableUnitTestModeIfAvailable()`, `installNotificationCallback(...)`, an
/// `InstalledCallback` token, and `CapturedAccessibilityNotification` values.
/// Live Objective-C payloads are converted inside an `autoreleasepool` before
/// leaving the callback so strong references stay as short-lived as possible.
///
/// Guarantees:
/// - Exact symbol names only; no fuzzy search and no executable-memory writes.
/// - Main-thread registration/removal, matching the apparent framework usage.
/// - The Swift block is retained both by UIAccessibility and by our installed
///   registration token for the lifetime of the observer.
/// - Private payload objects leave this wrapper only as normalized, weakly-held
///   notification evidence.
private enum AccessibilityNotificationPrivateSPI {
    // Private UIAccessibility registration API. The block signature is inferred
    // from `_UIAXBroadcastMainThread`, which invokes each registered block as:
    //   block(notificationCode, notificationData, associatedElement)
    private typealias NotificationCallbackBlock = @convention(block) (
        UInt32,
        AnyObject?,
        AnyObject?
    ) -> Void

    private typealias AddNotificationCallbackFunction = @convention(c) (
        NotificationCallbackBlock,
        AnyObject
    ) -> Void

    private typealias RemoveNotificationCallbackFunction = @convention(c) (AnyObject) -> Void

    // Private AccessibilitySupport switch that lets normal app processes pass
    // `_UIAXBroadcastMainThread`'s notification gate. This is an arming step,
    // not the observer mechanism itself.
    private typealias SetUnitTestModeFunction = @convention(c) (Int32) -> Void

    enum InstallError: Error, CustomStringConvertible {
        case notMainThread
        case callbackSymbolsUnavailable(checkedSources: [String])

        var description: String {
            switch self {
            case .notMainThread:
                return "notMainThread"
            case .callbackSymbolsUnavailable(let checkedSources):
                let sample = checkedSources.prefix(8).joined(separator: ", ")
                return "callbackSymbolsUnavailable(checked=\(checkedSources.count), sample=[\(sample)])"
            }
        }
    }

    private struct ResolvedSymbols {
        let source: String
        let handle: UnsafeMutableRawPointer
        let addCallback: AddNotificationCallbackFunction
        let removeCallback: RemoveNotificationCallbackFunction
    }

    final class InstalledCallback {
        let source: String

        private let frameworkHandle: UnsafeMutableRawPointer
        private let remove: (NSString) -> Void
        private let key: NSString
        private let retainedCallback: Any
        private var isInstalled = true

        fileprivate init(
            source: String,
            frameworkHandle: UnsafeMutableRawPointer,
            remove: @escaping (NSString) -> Void,
            key: NSString,
            retainedCallback: Any
        ) {
            self.source = source
            self.frameworkHandle = frameworkHandle
            self.remove = remove
            self.key = key
            self.retainedCallback = retainedCallback
        }

        deinit {
            try? uninstall()
        }

        func uninstall() throws {
            guard isInstalled else { return }
            guard Thread.isMainThread else {
                throw InstallError.notMainThread
            }

            remove(key)
            isInstalled = false

            // Keep the framework loaded. UIAccessibility owns process-global
            // state and may still have internal references to the dictionary.
            _ = frameworkHandle
            _ = retainedCallback
        }
    }

    @discardableResult
    static func enableUnitTestModeIfAvailable() -> Bool {
        guard let setUnitTestMode: SetUnitTestModeFunction = ButtonHeistPrivateSPI.function(
            .accessibilitySetUnitTestMode,
            in: .libAccessibility,
            as: SetUnitTestModeFunction.self
        ) else {
            return false
        }
        setUnitTestMode(1)
        return true
    }

    static func installNotificationCallback(
        shouldCapture: @escaping () -> Bool,
        handler: @escaping (CapturedAccessibilityNotification) -> Void
    ) throws -> InstalledCallback {
        guard Thread.isMainThread else {
            throw InstallError.notMainThread
        }

        let symbols = try resolveSymbols()
        let observerKey = "com.buttonheist.accessibility-notification-observer" as NSString
        let callback: NotificationCallbackBlock = { code, notificationData, associatedElement in
            // Apple calls this from the broadcast path, normally on main after
            // `AXPerformBlockOnMainThreadAfterDelay(..., 0)`. Keep the
            // no-subscriber path close to a no-op: do not wrap objects or log.
            guard shouldCapture() else { return }

            autoreleasepool {
                handler(CapturedAccessibilityNotification(
                    code: code,
                    notificationData: CapturedAccessibilityNotificationPayload(notificationData),
                    associatedElement: CapturedAccessibilityNotificationPayload(associatedElement)
                ))
            }
        }

        symbols.addCallback(callback, observerKey)
        return InstalledCallback(
            source: symbols.source,
            frameworkHandle: symbols.handle,
            remove: { key in symbols.removeCallback(key) },
            key: observerKey,
            retainedCallback: callback
        )
    }

    private static func resolveSymbols() throws -> ResolvedSymbols {
        var checkedSources: [String] = []

        if let processHandle = ButtonHeistPrivateSPI.processHandle() {
            checkedSources.append("process")
            if let symbols = symbols(in: processHandle, source: "process") {
                return symbols
            }
        }

        for imagePath in ButtonHeistPrivateSPI.loadedImagePaths() {
            checkedSources.append(imagePath)
            guard let handle = ButtonHeistPrivateSPI.openLibrary(at: imagePath),
                  let symbols = symbols(in: handle, source: imagePath)
            else {
                continue
            }
            return symbols
        }

        let fallbackSearchOrder = ButtonHeistPrivateSPI.SPIFrameworkPath
            .accessibilityNotificationCallbackFallbackSearchOrder
        for frameworkPath in fallbackSearchOrder {
            let path = ButtonHeistPrivateSPI.path(frameworkPath)
            checkedSources.append(path)
            guard let handle = ButtonHeistPrivateSPI.open(frameworkPath),
                  let symbols = symbols(in: handle, source: path)
            else {
                continue
            }
            return symbols
        }

        throw InstallError.callbackSymbolsUnavailable(
            checkedSources: ButtonHeistPrivateSPI.uniquePreservingOrder(checkedSources)
        )
    }

    private static func symbols(
        in handle: UnsafeMutableRawPointer,
        source: String
    ) -> ResolvedSymbols? {
        guard let addCallback: AddNotificationCallbackFunction = ButtonHeistPrivateSPI.function(
            .accessibilityAddNotificationCallback,
            in: handle,
            as: AddNotificationCallbackFunction.self
        ),
              let removeCallback: RemoveNotificationCallbackFunction = ButtonHeistPrivateSPI.function(
                .accessibilityRemoveNotificationCallback,
                in: handle,
                as: RemoveNotificationCallbackFunction.self
              )
        else {
            return nil
        }

        return ResolvedSymbols(
            source: source,
            handle: handle,
            addCallback: addCallback,
            removeCallback: removeCallback
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
