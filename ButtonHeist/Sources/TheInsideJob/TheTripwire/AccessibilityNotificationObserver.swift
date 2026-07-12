#if canImport(UIKit)
#if DEBUG
import Foundation
import os
import TheScore
import UIKit

private let accessibilityNotificationLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

private struct CapturedAccessibilityNotification {
    let code: UInt32
    let notificationData: CapturedAccessibilityNotificationPayload
    let associatedElement: CapturedAccessibilityNotificationPayload
}

private struct AccessibilityNotificationPublication: Sendable {
    let sequence: UInt64
    let subscribers: [AccessibilityNotificationBus]
}

enum AccessibilityNotificationObserverLifecycleState: Equatable {
    case unsubscribed
    case subscribed(callbackInstalled: Bool)
}

private struct WeakAccessibilityNotificationSubscriber {
    weak var subscriber: AccessibilityNotificationBus?

    init(_ subscriber: AccessibilityNotificationBus) {
        self.subscriber = subscriber
    }
}

private final class AccessibilityNotificationFanout: Sendable {
    private struct State {
        var subscribers: [ObjectIdentifier: WeakAccessibilityNotificationSubscriber] = [:]
        var latestSequence: UInt64 = 0

        mutating func removeExpiredSubscribers() {
            subscribers = subscribers.filter { $0.value.subscriber != nil }
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var latestSequence: UInt64 {
        state.withLock { $0.latestSequence }
    }

    var hasSubscribers: Bool {
        state.withLock { state in
            state.removeExpiredSubscribers()
            return !state.subscribers.isEmpty
        }
    }

    func add(_ subscriber: AccessibilityNotificationBus) {
        state.withLock { state in
            state.removeExpiredSubscribers()
            state.subscribers[ObjectIdentifier(subscriber)] = WeakAccessibilityNotificationSubscriber(subscriber)
        }
    }

    func remove(_ subscriber: AccessibilityNotificationBus) {
        state.withLock { state in
            state.subscribers[ObjectIdentifier(subscriber)] = nil
            state.removeExpiredSubscribers()
        }
    }

    func removeAll() {
        state.withLock { $0.subscribers.removeAll() }
    }

    func rebroadcast(_ notification: CapturedAccessibilityNotification) {
        guard let publication = reservePublication() else { return }
        let event = PendingAccessibilityNotificationEvent(
            sequence: publication.sequence,
            rawCode: notification.code,
            timestamp: Date(),
            notificationData: notification.notificationData.pendingPayload,
            associatedElement: notification.associatedElement.pendingPayload
        )
        for subscriber in publication.subscribers {
            subscriber.record(event)
        }
    }

    private func reservePublication() -> AccessibilityNotificationPublication? {
        state.withLock { state in
            state.removeExpiredSubscribers()
            let subscribers = state.subscribers.values.compactMap(\.subscriber)
            guard !subscribers.isEmpty else { return nil }

            state.latestSequence += 1
            return AccessibilityNotificationPublication(
                sequence: state.latestSequence,
                subscribers: subscribers
            )
        }
    }
}

@MainActor
final class AccessibilityNotificationObserver {
    private struct InstalledRegistration {
        let source: String
        let uninstall: @MainActor () -> Void
    }

    private enum RegistrationPhase {
        case uninstalled
        case installing
        case installed(InstalledRegistration)
        case uninstalling(InstalledRegistration)
        case installationUnavailable

        var isInstalled: Bool {
            switch self {
            case .installed, .uninstalling:
                return true
            case .uninstalled, .installing, .installationUnavailable:
                return false
            }
        }
    }

    private typealias CallbackInstaller = @MainActor (
        _ shouldCapture: @escaping () -> Bool,
        _ handler: @escaping (CapturedAccessibilityNotification) -> Void
    ) throws -> InstalledRegistration

    static let shared = AccessibilityNotificationObserver()

    private let fanout = AccessibilityNotificationFanout()
    private let callbackInstaller: CallbackInstaller
    private var registrationPhase: RegistrationPhase = .uninstalled

    var latestSequence: UInt64 {
        fanout.latestSequence
    }

    var hasSubscribers: Bool {
        reconcileRegistration()
        return fanout.hasSubscribers
    }

    var isInstalled: Bool {
        reconcileRegistration()
        return registrationPhase.isInstalled
    }

    var lifecycleState: AccessibilityNotificationObserverLifecycleState {
        reconcileRegistration()
        guard fanout.hasSubscribers else { return .unsubscribed }
        return .subscribed(callbackInstalled: registrationPhase.isInstalled)
    }

    private convenience init() {
        self.init { shouldCapture, handler in
            if AccessibilityNotificationPrivateSPI.enableUnitTestModeIfAvailable() {
                accessibilityNotificationLogger.info("Armed accessibility notification callback via private unit-test mode SPI")
            } else {
                accessibilityNotificationLogger.debug("Private accessibility unit-test mode SPI is unavailable")
            }
            let callback = try AccessibilityNotificationPrivateSPI.installNotificationCallback(
                shouldCapture: shouldCapture,
                handler: handler
            )
            return InstalledRegistration(source: callback.source) {
                callback.uninstall()
            }
        }
    }

    private init(callbackInstaller: @escaping CallbackInstaller) {
        self.callbackInstaller = callbackInstaller
    }

    convenience init(
        installCallbackForTesting: @escaping @MainActor () -> Void,
        uninstallCallbackForTesting: @escaping @MainActor () -> Void
    ) {
        self.init { _, _ in
            installCallbackForTesting()
            return InstalledRegistration(
                source: "test",
                uninstall: uninstallCallbackForTesting
            )
        }
    }

    func subscribe(_ subscriber: AccessibilityNotificationBus) {
        fanout.add(subscriber)
        reconcileRegistration()
    }

    func unsubscribe(_ subscriber: AccessibilityNotificationBus) {
        fanout.remove(subscriber)
        reconcileRegistration()
    }

    func uninstall() {
        fanout.removeAll()
        reconcileRegistration()
    }

    private func reconcileRegistration() {
        switch (fanout.hasSubscribers, registrationPhase) {
        case (true, .uninstalled):
            installRegistration()
        case (false, .installed(let registration)):
            uninstallRegistration(registration)
        case (false, .installationUnavailable):
            registrationPhase = .uninstalled
        case (false, .uninstalled),
             (true, .installed),
             (true, .installationUnavailable),
             (_, .installing),
             (_, .uninstalling):
            return
        }
    }

    private func installRegistration() {
        registrationPhase = .installing
        let fanout = fanout
        do {
            let registration = try callbackInstaller(
                { fanout.hasSubscribers },
                { fanout.rebroadcast($0) }
            )
            registrationPhase = .installed(registration)
            accessibilityNotificationLogger.info(
                "Installed accessibility notification callback source=\(registration.source, privacy: .public)"
            )
            reconcileRegistration()
        } catch {
            registrationPhase = .installationUnavailable
            accessibilityNotificationLogger.info(
                "accessibility notification callback install failed: \(String(describing: error), privacy: .public)"
            )
            reconcileRegistration()
        }
    }

    private func uninstallRegistration(_ registration: InstalledRegistration) {
        registrationPhase = .uninstalling(registration)
        registration.uninstall()
        registrationPhase = .uninstalled
        accessibilityNotificationLogger.info("Removed accessibility notification callback")
        reconcileRegistration()
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
    enum InstallError: Error, CustomStringConvertible {
        case callbackSymbolsUnavailable(checkedSources: [String])

        var description: String {
            switch self {
            case .callbackSymbolsUnavailable(let checkedSources):
                let sample = checkedSources.prefix(8).joined(separator: ", ")
                return "callbackSymbolsUnavailable(checked=\(checkedSources.count), sample=[\(sample)])"
            }
        }
    }

    private struct ResolvedSymbols {
        let source: String
        let handle: ButtonHeistPrivateSPI.LibraryHandle
        let addCallback: ButtonHeistPrivateSPI.AddAccessibilityNotificationCallbackFunction
        let removeCallback: ButtonHeistPrivateSPI.RemoveAccessibilityNotificationCallbackFunction
    }

    @MainActor
    final class InstalledCallback {
        let source: String

        private let frameworkHandle: ButtonHeistPrivateSPI.LibraryHandle
        private let remove: (NSString) -> Void
        private let key: NSString
        private let retainedCallback: ButtonHeistPrivateSPI.AccessibilityNotificationCallbackBlock
        private var isInstalled = true

        fileprivate init(
            source: String,
            frameworkHandle: ButtonHeistPrivateSPI.LibraryHandle,
            remove: @escaping (NSString) -> Void,
            key: NSString,
            retainedCallback: @escaping ButtonHeistPrivateSPI.AccessibilityNotificationCallbackBlock
        ) {
            self.source = source
            self.frameworkHandle = frameworkHandle
            self.remove = remove
            self.key = key
            self.retainedCallback = retainedCallback
        }

        func uninstall() {
            guard isInstalled else { return }

            remove(key)
            isInstalled = false

            // Keep the framework loaded. UIAccessibility owns process-global
            // state and may still have internal references to the dictionary.
            _ = frameworkHandle
            _ = retainedCallback
        }
    }

    @discardableResult
    @MainActor
    static func enableUnitTestModeIfAvailable() -> Bool {
        guard let setUnitTestMode = ButtonHeistPrivateSPI.function(
            .accessibilitySetUnitTestMode,
            in: .libAccessibility
        ) else {
            return false
        }
        setUnitTestMode(1)
        return true
    }

    @MainActor
    static func installNotificationCallback(
        shouldCapture: @escaping () -> Bool,
        handler: @escaping (CapturedAccessibilityNotification) -> Void
    ) throws -> InstalledCallback {
        let symbols = try resolveSymbols()
        let observerKey = "com.buttonheist.accessibility-notification-observer" as NSString
        let callback: ButtonHeistPrivateSPI.AccessibilityNotificationCallbackBlock = { code, notificationData, associatedElement in
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

        let searchOrder = ButtonHeistPrivateSPI.SPIFrameworkPath
            .accessibilityNotificationCallbackFallbackSearchOrder
        for frameworkPath in searchOrder {
            let path = ButtonHeistPrivateSPI.path(frameworkPath)
            checkedSources.append(path)
            guard let handle = ButtonHeistPrivateSPI.open(frameworkPath),
                  let symbols = symbols(in: handle)
            else {
                continue
            }
            return symbols
        }

        throw InstallError.callbackSymbolsUnavailable(
            checkedSources: checkedSources.uniqued(on: \.self)
        )
    }

    private static func symbols(in handle: ButtonHeistPrivateSPI.LibraryHandle) -> ResolvedSymbols? {
        guard let addCallback = ButtonHeistPrivateSPI.function(
            .accessibilityAddNotificationCallback,
            in: handle
        ),
              let removeCallback = ButtonHeistPrivateSPI.function(
                .accessibilityRemoveNotificationCallback,
                in: handle
              )
        else {
            return nil
        }

        return ResolvedSymbols(
            source: handle.source,
            handle: handle,
            addCallback: addCallback,
            removeCallback: removeCallback
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
