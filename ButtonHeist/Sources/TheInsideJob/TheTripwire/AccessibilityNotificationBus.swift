#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore

/// `@unchecked Sendable` justification: all mutable state is protected by
/// `lock`; waiter continuations are resumed outside the lock and timeout
/// tasks reference the bus weakly.
final class AccessibilityNotificationBus: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    /// Transition-completion notifications: the app announcing that a screen
    /// or layout change has finished landing. `screenChanged` (1000) is the
    /// strong per-screen claim; `layoutChanged` (1001) often precedes it
    /// during multi-stage transitions and also fires for in-place updates.
    static let transitionCompletionCodes: Set<UInt32> = [1000, 1001]
    private static let screenChangedCode: UInt32 = 1000

    private final class TransitionWaiter {
        let afterSequence: UInt64
        let continuation: CheckedContinuation<AccessibilityNotificationCursor?, Never>
        var timeoutTask: Task<Void, Never>?

        init(
            afterSequence: UInt64,
            continuation: CheckedContinuation<AccessibilityNotificationCursor?, Never>
        ) {
            self.afterSequence = afterSequence
            self.continuation = continuation
        }
    }

    private let maxBufferedEvents = 64
    private let lock = NSLock()
    private var bufferedEvents: [PendingAccessibilityNotificationEvent] = []
    private var latestSequenceStorage: UInt64 = 0
    private var latestTransitionSequenceStorage: UInt64 = 0
    private var latestScreenChangedSequenceStorage: UInt64 = 0
    private var activeHeistScopes = 0
    private var activeActionWindows = 0
    private var transitionWaiters: [UInt64: TransitionWaiter] = [:]
    private var nextTransitionWaiterId: UInt64 = 0

    var latestSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latestSequenceStorage
    }

    /// Sequence of the most recent `screenChanged` notification, or 0.
    var latestScreenChangedSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latestScreenChangedSequenceStorage
    }

    /// Cursor at the most recent transition-completion notification, for use
    /// with `waitForTransitionEvent(after:timeout:)`.
    func transitionCursor() -> AccessibilityNotificationCursor {
        lock.lock()
        defer { lock.unlock() }
        return AccessibilityNotificationCursor(sequence: latestTransitionSequenceStorage)
    }

    /// Suspend until a transition-completion notification is recorded after
    /// `cursor`, or the timeout elapses.
    ///
    /// Returns the advanced cursor on a hit (collapsing any backlog to the
    /// latest transition event), or nil on timeout. Presence of a notification
    /// is signal; absence proves nothing — callers must treat nil as "fall
    /// back to polling", never as "no change happened".
    func waitForTransitionEvent(
        after cursor: AccessibilityNotificationCursor,
        timeout: TimeInterval
    ) async -> AccessibilityNotificationCursor? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if latestTransitionSequenceStorage > cursor.sequence {
                let latest = latestTransitionSequenceStorage
                lock.unlock()
                continuation.resume(returning: AccessibilityNotificationCursor(sequence: latest))
                return
            }
            guard timeout > 0 else {
                lock.unlock()
                continuation.resume(returning: nil)
                return
            }
            nextTransitionWaiterId += 1
            let waiterId = nextTransitionWaiterId
            let waiter = TransitionWaiter(afterSequence: cursor.sequence, continuation: continuation)
            transitionWaiters[waiterId] = waiter
            lock.unlock()

            let timeoutTask = Task { [weak self] in
                await Task.cancellableSleep(for: .milliseconds(Int64(max(1, timeout * 1_000))))
                self?.expireTransitionWaiter(waiterId)
            }
            registerTransitionWaiterTimeout(timeoutTask, forWaiter: waiterId)
        }
    }

    private func registerTransitionWaiterTimeout(_ timeoutTask: Task<Void, Never>, forWaiter waiterId: UInt64) {
        lock.lock()
        guard let waiter = transitionWaiters[waiterId] else {
            // Resolved between registration and timeout arming — the sleep
            // is no longer needed.
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        waiter.timeoutTask = timeoutTask
        lock.unlock()
    }

    private func expireTransitionWaiter(_ waiterId: UInt64) {
        lock.lock()
        let waiter = transitionWaiters.removeValue(forKey: waiterId)
        lock.unlock()
        waiter?.continuation.resume(returning: nil)
    }

    private func recordTransitionEventLocked(code: UInt32, sequence: UInt64) -> [TransitionWaiter] {
        guard Self.transitionCompletionCodes.contains(code) else { return [] }
        latestTransitionSequenceStorage = sequence
        if code == Self.screenChangedCode {
            latestScreenChangedSequenceStorage = sequence
        }
        let resumed = transitionWaiters.values.filter { $0.afterSequence < sequence }
        transitionWaiters = transitionWaiters.filter { $0.value.afterSequence >= sequence }
        return Array(resumed)
    }

    var hasActiveNotificationScope: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeHeistScopes > 0 || activeActionWindows > 0
    }

    /// Opens the outer correlation window for a running heist.
    ///
    /// While this scope is active, action windows may claim attribution, but
    /// they do not drain the underlying stream. The heist owns stream lifetime.
    func beginHeistScope() -> AccessibilityNotificationHeistScope {
        lock.lock()
        defer { lock.unlock() }

        if activeHeistScopes == 0 && activeActionWindows == 0 {
            bufferedEvents.removeAll()
        }
        activeHeistScopes += 1
        return AccessibilityNotificationHeistScope(bus: self)
    }

    /// Opens the inner attribution window for one dispatched action.
    ///
    /// Events with sequence numbers greater than this cursor can be attached to
    /// the action receipt without stealing earlier heist-level context.
    func beginActionWindow() -> AccessibilityNotificationActionWindow {
        lock.lock()
        defer { lock.unlock() }

        activeActionWindows += 1
        return AccessibilityNotificationActionWindow(
            bus: self,
            cursor: AccessibilityNotificationCursor(sequence: latestSequenceStorage)
        )
    }

    func record(
        code: UInt32,
        notificationData data: CapturedAccessibilityNotificationPayload,
        associatedElement element: CapturedAccessibilityNotificationPayload
    ) {
        let name = Self.name(for: code)

        lock.lock()
        latestSequenceStorage += 1
        let event = PendingAccessibilityNotificationEvent(
            sequence: latestSequenceStorage,
            code: code,
            name: name,
            timestamp: Date(),
            notificationData: data.pendingPayload,
            associatedElement: element.pendingPayload
        )
        bufferedEvents.append(event)
        if bufferedEvents.count > maxBufferedEvents {
            bufferedEvents.removeFirst(bufferedEvents.count - maxBufferedEvents)
        }
        let resumedWaiters = recordTransitionEventLocked(code: code, sequence: event.sequence)
        lock.unlock()

        let cursor = AccessibilityNotificationCursor(sequence: event.sequence)
        for waiter in resumedWaiters {
            waiter.timeoutTask?.cancel()
            waiter.continuation.resume(returning: cursor)
        }
    }

    func pendingEvents(after cursor: AccessibilityNotificationCursor = .origin) -> [PendingAccessibilityNotificationEvent] {
        lock.lock()
        defer { lock.unlock() }
        return bufferedEvents.filter { $0.sequence > cursor.sequence }
    }

    /// Legacy whole-buffer claim for direct test and fallback paths.
    ///
    /// Normal action dispatch should prefer `AccessibilityNotificationActionWindow`.
    func claimPendingEvents() -> [PendingAccessibilityNotificationEvent] {
        lock.lock()
        defer { lock.unlock() }

        let events = bufferedEvents
        if activeHeistScopes == 0 {
            bufferedEvents.removeAll()
        }
        return events
    }

    func clearPendingEvents() {
        lock.lock()
        defer { lock.unlock() }
        bufferedEvents.removeAll()
    }

    fileprivate static func stringPayload(_ value: AnyObject?) -> String? {
        switch value {
        case let string as NSString:
            return normalized(string as String)
        case let attributed as NSAttributedString:
            return normalized(attributed.string)
        default:
            return nil
        }
    }

    fileprivate static func notificationPayloadObject(from object: AnyObject?) -> AnyObject? {
        guard let dictionary = object as? NSDictionary,
              let data = dictionary["data"]
        else {
            return object
        }
        if data is NSNull {
            return nil
        }
        return data as AnyObject
    }

    private static func normalized(_ string: String) -> String? {
        let normalized = string
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func name(for code: UInt32) -> String {
        switch code {
        case 1000:
            return "screenChanged"
        case 1001:
            return "layoutChanged"
        case 1005:
            return "valueChanged"
        case 1008:
            return "announcement"
        case 1009:
            return "pageScrolled"
        default:
            return "notification_\(code)"
        }
    }

    fileprivate static func className(for value: AnyObject?) -> String {
        guard let object = value else { return "nil" }
        return NSStringFromClass(type(of: object))
    }

    fileprivate static func summary(for value: AnyObject?) -> String? {
        switch value {
        case let dictionary as NSDictionary:
            return dictionarySummary(dictionary)
        case let array as NSArray:
            return arraySummary(array)
        case let string as NSString:
            return "string(\(truncated(string as String)))"
        case let attributed as NSAttributedString:
            return "attributedString(\(truncated(attributed.string)))"
        case let object as NSObject:
            return "object(class=\(NSStringFromClass(type(of: object))) description=\(truncated(String(describing: object))))"
        default:
            return nil
        }
    }

    private static func dictionarySummary(_ dictionary: NSDictionary) -> String {
        var entries: [String] = []
        for (key, value) in dictionary {
            let valueObject = value as AnyObject
            entries.append(
                "\(truncated(String(describing: key))):\(className(for: valueObject))=\(truncated(String(describing: value)))"
            )
            if entries.count == 8 { break }
        }
        let suffix = dictionary.count > entries.count ? ",..." : ""
        return "dictionary(count=\(dictionary.count) \(entries.joined(separator: ","))\(suffix))"
    }

    private static func arraySummary(_ array: NSArray) -> String {
        var entries: [String] = []
        for value in array {
            let valueObject = value as AnyObject
            entries.append("\(className(for: valueObject))=\(truncated(String(describing: value)))")
            if entries.count == 8 { break }
        }
        let suffix = array.count > entries.count ? ",..." : ""
        return "array(count=\(array.count) \(entries.joined(separator: ","))\(suffix))"
    }

    private static func truncated(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if singleLine.count <= 160 {
            return singleLine
        }
        return "\(singleLine.prefix(157))..."
    }

    fileprivate func finishActionWindow(after cursor: AccessibilityNotificationCursor) -> [PendingAccessibilityNotificationEvent] {
        lock.lock()
        defer { lock.unlock() }

        let events = bufferedEvents.filter { $0.sequence > cursor.sequence }
        let upperBound = events.last?.sequence ?? cursor.sequence
        if activeActionWindows > 0 {
            activeActionWindows -= 1
        }
        if activeHeistScopes == 0 {
            bufferedEvents.removeAll { $0.sequence <= upperBound }
        }
        return events
    }

    fileprivate func cancelActionWindow() {
        lock.lock()
        defer { lock.unlock() }

        if activeActionWindows > 0 {
            activeActionWindows -= 1
        }
    }

    fileprivate func endHeistScope() {
        lock.lock()
        defer { lock.unlock() }

        if activeHeistScopes > 0 {
            activeHeistScopes -= 1
        }
        if activeHeistScopes == 0 && activeActionWindows == 0 {
            bufferedEvents.removeAll()
        }
    }
}

struct AccessibilityNotificationCursor: Sendable, Equatable {
    static let origin = AccessibilityNotificationCursor(sequence: 0)

    let sequence: UInt64
}

/// Lifetime token for a heist-level notification stream.
/// `@unchecked Sendable` justification: mutable `bus` access is protected by `lock`;
/// cancellation may cross task boundaries while closing scoped observation.
final class AccessibilityNotificationHeistScope: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private weak var bus: AccessibilityNotificationBus?

    fileprivate init(bus: AccessibilityNotificationBus) {
        self.bus = bus
    }

    deinit {
        cancel()
    }

    func cancel() {
        let bus: AccessibilityNotificationBus?
        lock.lock()
        bus = self.bus
        self.bus = nil
        lock.unlock()

        bus?.endHeistScope()
    }
}

/// Lifetime token for a single action's notification attribution window.
/// `@unchecked Sendable` justification: mutable `bus` access is protected by `lock`;
/// cancellation may cross task boundaries while closing the action window.
final class AccessibilityNotificationActionWindow: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    let cursor: AccessibilityNotificationCursor

    private let lock = NSLock()
    private weak var bus: AccessibilityNotificationBus?

    fileprivate init(bus: AccessibilityNotificationBus, cursor: AccessibilityNotificationCursor) {
        self.bus = bus
        self.cursor = cursor
    }

    deinit {
        cancel()
    }

    func finishAndClaimEvents() -> [PendingAccessibilityNotificationEvent] {
        let bus: AccessibilityNotificationBus?
        lock.lock()
        bus = self.bus
        self.bus = nil
        lock.unlock()

        return bus?.finishActionWindow(after: cursor) ?? []
    }

    func cancel() {
        let bus: AccessibilityNotificationBus?
        lock.lock()
        bus = self.bus
        self.bus = nil
        lock.unlock()

        bus?.cancelActionWindow()
    }
}

struct PendingAccessibilityNotificationEvent {
    let sequence: UInt64
    let code: UInt32
    let name: String
    let timestamp: Date
    let notificationData: PendingAccessibilityNotificationPayload
    let associatedElement: PendingAccessibilityNotificationPayload
}

enum PendingAccessibilityNotificationPayload {
    case none
    case string(String)
    case object(AccessibilityNotificationObjectIdentity)
}

struct CapturedAccessibilityNotificationPayload {
    static var none: CapturedAccessibilityNotificationPayload {
        CapturedAccessibilityNotificationPayload(
            pendingPayload: .none,
            className: "nil",
            summary: nil,
            objectIdentifier: nil
        )
    }

    let pendingPayload: PendingAccessibilityNotificationPayload
    let className: String
    let summary: String?
    let objectIdentifier: ObjectIdentifier?

    init(_ object: AnyObject?) {
        guard let object else {
            self = .none
            return
        }
        let className = AccessibilityNotificationBus.className(for: object)
        let summary = AccessibilityNotificationBus.summary(for: object)
        guard let payloadObject = AccessibilityNotificationBus.notificationPayloadObject(from: object) else {
            self.init(
                pendingPayload: .none,
                className: className,
                summary: summary,
                objectIdentifier: nil
            )
            return
        }
        if let value = AccessibilityNotificationBus.stringPayload(payloadObject) {
            self.init(
                pendingPayload: .string(value),
                className: className,
                summary: summary,
                objectIdentifier: nil
            )
        } else {
            let identity = AccessibilityNotificationObjectIdentity(
                object: payloadObject,
                className: className,
                summary: summary
            )
            self.init(
                pendingPayload: .object(identity),
                className: className,
                summary: summary,
                objectIdentifier: identity.objectIdentifier
            )
        }
    }

    private init(
        pendingPayload: PendingAccessibilityNotificationPayload,
        className: String,
        summary: String?,
        objectIdentifier: ObjectIdentifier?
    ) {
        self.pendingPayload = pendingPayload
        self.className = className
        self.summary = summary
        self.objectIdentifier = objectIdentifier
    }
}

final class AccessibilityNotificationObjectIdentity {
    let objectIdentifier: ObjectIdentifier
    let className: String
    let summary: String?
    weak var object: AnyObject?

    init(_ object: AnyObject) {
        self.objectIdentifier = ObjectIdentifier(object)
        self.className = AccessibilityNotificationBus.className(for: object)
        self.summary = AccessibilityNotificationBus.summary(for: object)
        self.object = object
    }

    init(object: AnyObject, className: String, summary: String?) {
        self.objectIdentifier = ObjectIdentifier(object)
        self.className = className
        self.summary = summary
        self.object = object
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
