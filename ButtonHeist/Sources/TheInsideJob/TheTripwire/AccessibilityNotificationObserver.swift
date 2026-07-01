#if canImport(UIKit)
#if DEBUG
import Darwin
import Foundation
import MachO
import os.log
import UIKit

private let accessibilityNotificationLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

// Private UIAccessibility registration API. The block signature is inferred
// from `_UIAXBroadcastMainThread`, which invokes each registered block as:
//   block(notificationCode, notificationData, associatedElement)
private typealias AccessibilityNotificationCallbackBlock = @convention(block) (
    UInt32,
    AnyObject?,
    AnyObject?
) -> Void

private typealias AddAccessibilityNotificationCallbackFunction = @convention(c) (
    AccessibilityNotificationCallbackBlock,
    AnyObject
) -> Void

private typealias RemoveAccessibilityNotificationCallbackFunction = @convention(c) (AnyObject) -> Void

// Darwin `dlsym` usually wants the C symbol spelling, not the leading Mach-O
// underscore shown by `nm`. These private symbols have appeared in both forms
// in notes/tools, so try the exact known spellings and nothing broader.
private let addAccessibilityNotificationCallbackSymbolNames = [
    "_AXAddNotificationCallback",
    "AXAddNotificationCallback",
]

private let removeAccessibilityNotificationCallbackSymbolNames = [
    "_AXRemoveNotificationCallback",
    "AXRemoveNotificationCallback",
]

// Private AccessibilitySupport switch that lets normal app processes pass
// `_UIAXBroadcastMainThread`'s notification gate. This is an arming step, not
// the observer mechanism itself.
private typealias SetUnitTestModeFunction = @convention(c) (Int32) -> Void

// Rationale: singleton state is protected by `lock`; callbacks copy weak subscribers before fan-out.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
final class AccessibilityNotificationObserver: @unchecked Sendable {
    static let shared = AccessibilityNotificationObserver()

    private static let uiAccessibilityInstallNames = [
        "/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility",
        "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore",
        "/System/Library/Frameworks/UIKit.framework/UIKit",
    ]

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
        setUnitTestModeIfAvailable()
        AccessibilityNotificationCallbackState.shared.install(
            candidatePaths: Self.uiAccessibilityCandidatePaths()
        )
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

    private func setUnitTestModeIfAvailable() {
        guard let symbol = Self.resolveSymbol(
            "_AXSSetInUnitTestMode",
            candidatePaths: Self.libAccessibilityCandidatePaths()
        ) else {
            accessibilityNotificationLogger.debug("_AXSSetInUnitTestMode not found")
            return
        }
        let setUnitTestMode = unsafeBitCast(symbol, to: SetUnitTestModeFunction.self)
        setUnitTestMode(1)
        accessibilityNotificationLogger.info("Armed accessibility notification callback via _AXSSetInUnitTestMode")
    }

    static func uiAccessibilityCandidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        candidatePaths(
            installNames: uiAccessibilityInstallNames,
            environment: environment
        )
    }

    private static func libAccessibilityCandidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        candidatePaths(
            installNames: ["/usr/lib/libAccessibility.dylib"],
            environment: environment
        )
    }

    private static func candidatePaths(
        installNames: [String],
        environment: [String: String]
    ) -> [String] {
        let roots = [
            environment[AccessibilityEnvironmentKey.iPhoneSimulatorRoot.rawValue],
            environment["SIMULATOR_ROOT"],
            environment["DYLD_ROOT_PATH"],
        ].compactMap { $0 }

        let rootedPaths = roots.flatMap { root in
            installNames.map { (root as NSString).appendingPathComponent($0) }
        }
        return uniquePreservingOrder(installNames + rootedPaths)
    }

    private static func resolveSymbol(_ name: String, candidatePaths: [String]) -> UnsafeMutableRawPointer? {
        if let processHandle = dlopen(nil, RTLD_NOW),
           let symbol = dlsym(processHandle, name) {
            return symbol
        }

        for path in candidatePaths {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
                  let symbol = dlsym(handle, name)
            else {
                continue
            }
            return symbol
        }

        return nil
    }

    fileprivate static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
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
    private var installedRegistration: AccessibilityNotificationCallbackRegistrar.InstalledRegistration?

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installedRegistration != nil
    }

    func install(candidatePaths: [String]) {
        lock.lock()
        defer { lock.unlock() }

        guard installedRegistration == nil else {
            return
        }

        do {
            let callbackBlock: AccessibilityNotificationCallbackBlock = { code, notificationData, associatedElement in
                AccessibilityNotificationCallbackState.shared.record(
                    code: code,
                    notificationData: notificationData,
                    associatedElement: associatedElement
                )
            }
            installedRegistration = try AccessibilityNotificationCallbackRegistrar.install(
                candidatePaths: candidatePaths,
                callback: callbackBlock
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

    private func record(
        code: UInt32,
        notificationData: AnyObject?,
        associatedElement: AnyObject?
    ) {
        // Apple calls the observer block from the broadcast path, normally on
        // main after `AXPerformBlockOnMainThreadAfterDelay(..., 0)`. Keep the
        // no-subscriber path close to a no-op: do not wrap objects or log.
        guard AccessibilityNotificationObserver.shared.hasSubscribers else {
            return
        }

        autoreleasepool {
            AccessibilityNotificationObserver.shared.rebroadcast(
                code: code,
                notificationData: CapturedAccessibilityNotificationPayload(notificationData),
                associatedElement: CapturedAccessibilityNotificationPayload(associatedElement)
            )
        }
    }

}

/// Sealed unsafe container for registering with UIAccessibility's notification
/// observer dictionary.
///
/// This is intentionally much smaller than the old inline patching path. Apple
/// already has an in-process fan-out table inside `_UIAXBroadcastMainThread`.
/// We only resolve the private registration symbols, install one keyed block,
/// and remove that key on uninstall.
///
/// Guarantees:
/// - Exact symbol names only; no fuzzy search and no executable-memory writes.
/// - Main-thread registration/removal, matching the apparent framework usage.
/// - The Swift block is retained both by UIAccessibility and by our installed
///   registration token for the lifetime of the observer.
/// - If any symbol is absent, installation fails closed and Button Heist simply
///   loses this notification signal.
private enum AccessibilityNotificationCallbackRegistrar {
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
        let addCallback: AddAccessibilityNotificationCallbackFunction
        let removeCallback: RemoveAccessibilityNotificationCallbackFunction
    }

    final class InstalledRegistration {
        let source: String

        private let frameworkHandle: UnsafeMutableRawPointer
        private let removeCallback: RemoveAccessibilityNotificationCallbackFunction
        private let key: NSString
        private let callback: AccessibilityNotificationCallbackBlock
        private var isInstalled = true

        fileprivate init(
            source: String,
            frameworkHandle: UnsafeMutableRawPointer,
            removeCallback: RemoveAccessibilityNotificationCallbackFunction,
            key: NSString,
            callback: @escaping AccessibilityNotificationCallbackBlock
        ) {
            self.source = source
            self.frameworkHandle = frameworkHandle
            self.removeCallback = removeCallback
            self.key = key
            self.callback = callback
        }

        deinit {
            try? uninstall()
        }

        func uninstall() throws {
            guard isInstalled else { return }
            guard Thread.isMainThread else {
                throw InstallError.notMainThread
            }

            removeCallback(key)
            isInstalled = false

            // Keep the framework loaded. UIAccessibility owns process-global
            // state and may still have internal references to the dictionary.
            _ = frameworkHandle
            _ = callback
        }
    }

    static func install(
        candidatePaths: [String],
        callback: @escaping AccessibilityNotificationCallbackBlock
    ) throws -> InstalledRegistration {
        guard Thread.isMainThread else {
            throw InstallError.notMainThread
        }

        let symbols = try resolveSymbols(candidatePaths: candidatePaths)
        let observerKey = "com.buttonheist.accessibility-notification-observer" as NSString

        symbols.addCallback(callback, observerKey)
        return InstalledRegistration(
            source: symbols.source,
            frameworkHandle: symbols.handle,
            removeCallback: symbols.removeCallback,
            key: observerKey,
            callback: callback
        )
    }

    private static func resolveSymbols(candidatePaths: [String]) throws -> ResolvedSymbols {
        var checkedSources: [String] = []

        if let processHandle = dlopen(nil, RTLD_NOW) {
            checkedSources.append("process")
            if let symbols = symbols(in: processHandle, source: "process") {
                return symbols
            }
        }

        for imagePath in loadedImagePaths() {
            checkedSources.append(imagePath)
            guard let handle = dlopen(imagePath, RTLD_NOW | RTLD_LOCAL),
                  let symbols = symbols(in: handle, source: imagePath)
            else {
                continue
            }
            return symbols
        }

        for path in candidatePaths {
            checkedSources.append(path)
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
                  let symbols = symbols(in: handle, source: path)
            else {
                continue
            }
            return symbols
        }

        throw InstallError.callbackSymbolsUnavailable(
            checkedSources: AccessibilityNotificationObserver.uniquePreservingOrder(checkedSources)
        )
    }

    private static func loadedImagePaths() -> [String] {
        var paths: [String] = []
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index) else { continue }
            paths.append(String(cString: name))
        }
        return AccessibilityNotificationObserver.uniquePreservingOrder(paths)
    }

    private static func symbols(
        in handle: UnsafeMutableRawPointer,
        source: String
    ) -> ResolvedSymbols? {
        guard let addSymbol = symbol(in: handle, names: addAccessibilityNotificationCallbackSymbolNames),
              let removeSymbol = symbol(in: handle, names: removeAccessibilityNotificationCallbackSymbolNames)
        else {
            return nil
        }

        return ResolvedSymbols(
            source: source,
            handle: handle,
            addCallback: unsafeBitCast(addSymbol, to: AddAccessibilityNotificationCallbackFunction.self),
            removeCallback: unsafeBitCast(removeSymbol, to: RemoveAccessibilityNotificationCallbackFunction.self)
        )
    }

    private static func symbol(
        in handle: UnsafeMutableRawPointer,
        names: [String]
    ) -> UnsafeMutableRawPointer? {
        for name in names {
            if let symbol = dlsym(handle, name) {
                return symbol
            }
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
