#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import ButtonHeistSupport
import ThePlans
import TheScore

/// `@unchecked Sendable` justification: all mutable state is protected by
/// `lock`; waiter continuations are resumed outside the lock and timeout
/// tasks reference the bus weakly.
final class AccessibilityNotificationBus: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private struct IngressLog {
        let retentionLimit: Int
        private(set) var retainedEvents: [PendingAccessibilityNotificationEvent] = []
        private(set) var latestSequence: UInt64 = 0
        private(set) var latestScopedScreenChangedSequence: UInt64 = 0
        private var evictedThroughSequence: UInt64 = 0
        private var evictedScopedThroughSequence: UInt64 = 0

        init(retentionLimit: Int) {
            precondition(retentionLimit > 0, "Notification retention must be positive")
            self.retentionLimit = retentionLimit
        }

        mutating func append(_ event: PendingAccessibilityNotificationEvent) {
            precondition(
                event.sequence > latestSequence,
                "Accessibility notification sequence must advance"
            )
            latestSequence = event.sequence
            if case .screenChanged = event.kind, event.provenance == .scoped {
                latestScopedScreenChangedSequence = event.sequence
            }
            retainedEvents.append(event)
            guard retainedEvents.count > retentionLimit else { return }

            let overflow = retainedEvents.count - retentionLimit
            let evicted = retainedEvents.prefix(overflow)
            evictedThroughSequence = max(evictedThroughSequence, evicted.last?.sequence ?? 0)
            evictedScopedThroughSequence = max(
                evictedScopedThroughSequence,
                evicted.last(where: { $0.provenance == .scoped })?.sequence ?? 0
            )
            retainedEvents.removeFirst(overflow)
        }

        func checkpoint(
            after cursor: AccessibilityNotificationCursor,
            selection: AccessibilityNotificationCheckpointSelection
        ) -> AccessibilityNotificationBatch {
            let evictedThrough = switch selection {
            case .all:
                evictedThroughSequence
            case .scoped:
                evictedScopedThroughSequence
            }
            return AccessibilityNotificationBatch(
                events: retainedEvents.filter {
                    $0.sequence > cursor.sequence && selection.includes($0.provenance)
                },
                through: AccessibilityNotificationCursor(sequence: latestSequence),
                scopedScreenChangedThrough: latestScopedScreenChangedSequence,
                gap: cursor.sequence < evictedThrough
                    ? AccessibilityNotificationGap(droppedThroughSequence: evictedThrough)
                    : nil
            )
        }
    }

    private struct AnnouncementWaiter {
        let afterSequence: UInt64
        let predicate: ResolvedAnnouncementPredicate
        let continuation: TimedOneShot<CapturedAnnouncement?>
    }

    private struct NotificationResumptions {
        let announcementWaiters: [(AnnouncementWaiter, CapturedAnnouncement)]
    }

    private let lock = NSLock()
    private var ingressLog = IngressLog(retentionLimit: 64)
    private var activeHeistScopes = 0
    private var activeActionWindows = 0
    private var announcementWaiters = WaiterStore<UInt64, AnnouncementWaiter>()

    var latestSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return ingressLog.latestSequence
    }

    /// Sequence of the most recent `screenChanged` notification recorded
    /// inside a heist or action notification scope, or 0.
    var latestScopedScreenChangedSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return ingressLog.latestScopedScreenChangedSequence
    }

    func cursor() -> AccessibilityNotificationCursor {
        lock.lock()
        defer { lock.unlock() }
        return AccessibilityNotificationCursor(sequence: ingressLog.latestSequence)
    }

    func announcements(after cursor: AccessibilityNotificationCursor = .origin) -> [CapturedAnnouncement] {
        lock.lock()
        defer { lock.unlock() }
        return ingressLog.checkpoint(after: cursor, selection: .all).events.compactMap(\.capturedAnnouncement)
    }

    var announcementWaiterCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return announcementWaiters.count
    }

    func waitForAnnouncement(
        after cursor: AccessibilityNotificationCursor,
        matching predicate: ResolvedAnnouncementPredicate,
        timeout: TimeInterval
    ) async -> CapturedAnnouncement? {
        let waiterId = reserveAnnouncementWaiterIdentifier()
        let continuationBox = TimedOneShot<CapturedAnnouncement?>()

        let result: CapturedAnnouncement? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CapturedAnnouncement?, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                guard continuationBox.register(continuation) else {
                    continuation.resume(returning: nil)
                    return
                }

                lock.lock()
                if let announcement = firstAnnouncementLocked(after: cursor, matching: predicate) {
                    lock.unlock()
                    continuationBox.resolve(returning: announcement)
                    return
                }
                guard timeout > 0 else {
                    lock.unlock()
                    continuationBox.resolve(returning: nil)
                    return
                }

                let timeoutMilliseconds = Int64(max(1, timeout * 1_000))
                announcementWaiters.insert(AnnouncementWaiter(
                    afterSequence: cursor.sequence,
                    predicate: predicate,
                    continuation: continuationBox
                ), id: waiterId)
                continuationBox.armTimeout(after: .milliseconds(timeoutMilliseconds)) { [weak self] in
                    self?.completeAnnouncementWaiter(waiterId, returning: nil)
                }
                lock.unlock()
            }
        } onCancel: {
            continuationBox.resolve(returning: nil)
        }
        completeAnnouncementWaiter(waiterId, returning: nil)
        return result
    }

    private func recordAnnouncementEventLocked(_ event: PendingAccessibilityNotificationEvent) -> [(AnnouncementWaiter, CapturedAnnouncement)] {
        guard let announcement = event.capturedAnnouncement else { return [] }
        let waiters = announcementWaiters.removeAll { waiter in
            waiter.afterSequence < event.sequence && waiter.predicate.matches(announcement.text)
        }
        return waiters.map { ($0, announcement) }
    }

    var hasActiveNotificationScope: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeHeistScopes > 0 || activeActionWindows > 0
    }

    private var hasActiveNotificationScopeLocked: Bool {
        activeHeistScopes > 0 || activeActionWindows > 0
    }

    private func reserveAnnouncementWaiterIdentifier() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        return announcementWaiters.reserveID()
    }

    private func completeAnnouncementWaiter(
        _ waiterId: UInt64,
        returning announcement: CapturedAnnouncement?
    ) {
        lock.lock()
        let waiter = announcementWaiters.remove(id: waiterId)
        lock.unlock()

        waiter?.continuation.resolve(returning: announcement)
    }

    /// Opens the outer correlation window for a running heist.
    ///
    /// While this scope is active, action windows may claim attribution. Scope
    /// lifetime only tags provenance; retained history belongs to the ingress log.
    func beginHeistScope() -> AccessibilityNotificationHeistScope {
        lock.lock()
        defer { lock.unlock() }

        activeHeistScopes += 1
        return AccessibilityNotificationHeistScope(
            bus: self,
            cursor: AccessibilityNotificationCursor(sequence: ingressLog.latestSequence)
        )
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
            cursor: AccessibilityNotificationCursor(sequence: ingressLog.latestSequence)
        )
    }

    func record(
        sequence: UInt64,
        rawCode: UInt32,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload
    ) {
        lock.lock()
        let event = PendingAccessibilityNotificationEvent(
            sequence: sequence,
            rawCode: rawCode,
            timestamp: timestamp,
            notificationData: notificationData,
            associatedElement: associatedElement,
            provenance: provenanceLocked
        )
        let resumptions = recordLocked(event)
        lock.unlock()

        resume(resumptions)
    }

    private func recordLocked(_ event: PendingAccessibilityNotificationEvent) -> NotificationResumptions {
        ingressLog.append(event)
        return NotificationResumptions(
            announcementWaiters: recordAnnouncementEventLocked(event)
        )
    }

    private func resume(_ resumptions: NotificationResumptions) {
        for (waiter, announcement) in resumptions.announcementWaiters {
            waiter.continuation.resolve(returning: announcement)
        }
    }

    private func firstAnnouncementLocked(
        after cursor: AccessibilityNotificationCursor,
        matching predicate: ResolvedAnnouncementPredicate
    ) -> CapturedAnnouncement? {
        let events = ingressLog.checkpoint(after: cursor, selection: .all).events
        for event in events {
            guard let announcement = event.capturedAnnouncement,
                  predicate.matches(announcement.text)
            else { continue }
            return announcement
        }
        return nil
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

    func checkpoint(
        after cursor: AccessibilityNotificationCursor,
        selection: AccessibilityNotificationCheckpointSelection = .scoped
    ) -> AccessibilityNotificationBatch {
        lock.lock()
        defer { lock.unlock() }
        return ingressLog.checkpoint(after: cursor, selection: selection)
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

        guard activeHeistScopes > 0 else { return }
        activeHeistScopes -= 1
    }

    private var provenanceLocked: AccessibilityNotificationProvenance {
        hasActiveNotificationScopeLocked ? .scoped : .ambient
    }
}

struct AccessibilityNotificationCursor: Sendable, Equatable {
    static let origin = AccessibilityNotificationCursor(sequence: 0)

    let sequence: UInt64
}

enum AccessibilityNotificationCheckpointSelection: Sendable {
    case all
    case scoped

    fileprivate func includes(_ provenance: AccessibilityNotificationProvenance) -> Bool {
        switch self {
        case .all:
            true
        case .scoped:
            provenance == .scoped
        }
    }
}

struct AccessibilityNotificationBatch {
    let events: [PendingAccessibilityNotificationEvent]
    let through: AccessibilityNotificationCursor
    let scopedScreenChangedThrough: UInt64
    let gap: AccessibilityNotificationGap?
}

enum AccessibilityNotificationProvenance: Sendable, Equatable {
    case scoped
    case ambient
}

/// Lifetime token for a heist-level notification stream.
/// `@unchecked Sendable` justification: mutable `bus` access is protected by `lock`;
/// cancellation may cross task boundaries while closing scoped observation.
final class AccessibilityNotificationHeistScope: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
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

    func capture() -> AccessibilityNotificationBatch? {
        lock.lock()
        let bus = self.bus
        lock.unlock()
        return bus?.checkpoint(after: cursor)
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
    let kind: AccessibilityNotificationKind
    let timestamp: Date
    let notificationData: PendingAccessibilityNotificationPayload
    let associatedElement: PendingAccessibilityNotificationPayload
    let provenance: AccessibilityNotificationProvenance

    init(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        provenance: AccessibilityNotificationProvenance
    ) {
        self.sequence = sequence
        self.kind = kind
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
        self.provenance = provenance
    }

    init(
        sequence: UInt64,
        rawCode: UInt32,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        provenance: AccessibilityNotificationProvenance
    ) {
        self.init(
            sequence: sequence,
            kind: AccessibilityNotificationKind(rawCode: rawCode),
            timestamp: timestamp,
            notificationData: notificationData,
            associatedElement: associatedElement,
            provenance: provenance
        )
    }

    var capturedAnnouncement: CapturedAnnouncement? {
        guard case .string(let text) = notificationData else { return nil }
        return CapturedAnnouncement(
            sequence: sequence,
            text: text,
            timestamp: timestamp,
            kind: kind,
            associatedElement: associatedElement.publicPayload
        )
    }

}

enum PendingAccessibilityNotificationPayload {
    case none
    case string(String)
    case object(AccessibilityNotificationObjectIdentity)

    var publicPayload: AccessibilityNotificationPayload {
        switch self {
        case .none:
            return .none
        case .string(let value):
            return .string(value)
        case .object(let identity):
            return .unresolvedObject(AccessibilityNotificationObjectPayload(
                className: identity.className,
                summary: identity.summary
            ))
        }
    }
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
