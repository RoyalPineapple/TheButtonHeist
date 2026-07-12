#if canImport(UIKit)
#if DEBUG
import Foundation
import os
import TheScore
import UIKit

private let accessibilityNotificationLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

typealias AccessibilityNotificationCallback = @MainActor (
    UInt32,
    AnyObject?,
    AnyObject?
) -> Void

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

@MainActor
final class AccessibilityNotificationObserver {
    private struct CallbackInstallation {
        let source: String
        let uninstall: @MainActor () -> Void
    }

    private struct InstalledRegistration {
        let generation: UInt64
        let installation: CallbackInstallation
    }

    private enum RegistrationPhase {
        case uninstalled
        case installing(generation: UInt64)
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
        _ callback: @escaping AccessibilityNotificationCallback
    ) throws -> CallbackInstallation

    static let shared = AccessibilityNotificationObserver()

    private let callbackInstaller: CallbackInstaller
    private var subscribers: [ObjectIdentifier: WeakAccessibilityNotificationSubscriber] = [:]
    private var latestSequenceStorage: UInt64 = 0
    private var nextGeneration: UInt64 = 0
    private var registrationPhase: RegistrationPhase = .uninstalled

    var latestSequence: UInt64 {
        latestSequenceStorage
    }

    var hasSubscribers: Bool {
        removeExpiredSubscribers()
        reconcileRegistration()
        return !subscribers.isEmpty
    }

    var isInstalled: Bool {
        reconcileRegistration()
        return registrationPhase.isInstalled
    }

    var lifecycleState: AccessibilityNotificationObserverLifecycleState {
        removeExpiredSubscribers()
        reconcileRegistration()
        guard !subscribers.isEmpty else { return .unsubscribed }
        return .subscribed(callbackInstalled: registrationPhase.isInstalled)
    }

    private convenience init() {
        self.init { callback in
            if AccessibilityNotificationPrivateSPI.enableUnitTestModeIfAvailable() {
                accessibilityNotificationLogger.info("Armed accessibility notification callback via private unit-test mode SPI")
            } else {
                accessibilityNotificationLogger.debug("Private accessibility unit-test mode SPI is unavailable")
            }
            let callback = try AccessibilityNotificationPrivateSPI.installNotificationCallback(
                callback
            )
            return CallbackInstallation(source: callback.source) {
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
        self.init { _ in
            installCallbackForTesting()
            return CallbackInstallation(
                source: "test",
                uninstall: uninstallCallbackForTesting
            )
        }
    }

    convenience init(
        installCallbackForTesting: @escaping @MainActor (
            _ callback: @escaping AccessibilityNotificationCallback
        ) -> Void,
        uninstallCallbackForTesting: @escaping @MainActor () -> Void
    ) {
        self.init { callback in
            installCallbackForTesting(callback)
            return CallbackInstallation(
                source: "test",
                uninstall: uninstallCallbackForTesting
            )
        }
    }

    func subscribe(_ subscriber: AccessibilityNotificationBus) {
        removeExpiredSubscribers()
        subscribers[ObjectIdentifier(subscriber)] = WeakAccessibilityNotificationSubscriber(subscriber)
        reconcileRegistration()
    }

    func unsubscribe(_ subscriber: AccessibilityNotificationBus) {
        subscribers[ObjectIdentifier(subscriber)] = nil
        removeExpiredSubscribers()
        reconcileRegistration()
    }

    func uninstall() {
        subscribers.removeAll()
        reconcileRegistration()
    }

    private func reconcileRegistration() {
        removeExpiredSubscribers()
        switch (!subscribers.isEmpty, registrationPhase) {
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
        nextGeneration += 1
        let generation = nextGeneration
        registrationPhase = .installing(generation: generation)
        do {
            let installation = try callbackInstaller { [weak self] code, notificationData, associatedElement in
                self?.publish(
                    code: code,
                    notificationData: notificationData,
                    associatedElement: associatedElement,
                    generation: generation
                )
            }
            let registration = InstalledRegistration(
                generation: generation,
                installation: installation
            )
            registrationPhase = .installed(registration)
            accessibilityNotificationLogger.info(
                "Installed accessibility notification callback source=\(installation.source, privacy: .public)"
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
        registration.installation.uninstall()
        registrationPhase = .uninstalled
        accessibilityNotificationLogger.info("Removed accessibility notification callback")
        reconcileRegistration()
    }

    private func publish(
        code: UInt32,
        notificationData: AnyObject?,
        associatedElement: AnyObject?,
        generation: UInt64
    ) {
        guard acceptsCallback(generation: generation) else { return }
        removeExpiredSubscribers()
        let subscribers = subscribers.values.compactMap(\.subscriber)
        guard !subscribers.isEmpty else { return }

        latestSequenceStorage += 1
        let event = PendingAccessibilityNotificationEvent(
            sequence: latestSequenceStorage,
            rawCode: code,
            timestamp: Date(),
            notificationData: CapturedAccessibilityNotificationPayload(notificationData).pendingPayload,
            associatedElement: CapturedAccessibilityNotificationPayload(associatedElement).pendingPayload
        )
        for subscriber in subscribers {
            subscriber.record(event)
        }
    }

    private func acceptsCallback(generation: UInt64) -> Bool {
        switch registrationPhase {
        case .installing(let activeGeneration):
            activeGeneration == generation
        case .installed(let registration):
            registration.generation == generation
        case .uninstalled, .uninstalling, .installationUnavailable:
            false
        }
    }

    private func removeExpiredSubscribers() {
        subscribers = subscribers.filter { $0.value.subscriber != nil }
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
/// `enableUnitTestModeIfAvailable()`, `installNotificationCallback(...)`, and
/// an `InstalledCallback` token.
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
        _ handler: @escaping AccessibilityNotificationCallback
    ) throws -> InstalledCallback {
        let symbols = try resolveSymbols()
        let observerKey = "com.buttonheist.accessibility-notification-observer" as NSString
        let callback: ButtonHeistPrivateSPI.AccessibilityNotificationCallbackBlock = { code, notificationData, associatedElement in
            autoreleasepool {
                // UIAccessibility invokes registered callbacks on main; assert that contract before normalization.
                MainActor.assumeIsolated {
                    handler(code, notificationData, associatedElement)
                }
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
