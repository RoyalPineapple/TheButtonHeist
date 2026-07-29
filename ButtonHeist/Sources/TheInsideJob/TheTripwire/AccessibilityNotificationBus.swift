#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore

/// `@unchecked Sendable` justification: all mutable state is protected by
/// `lock`; waiter continuations are resumed outside the lock and timeout
/// tasks reference the bus weakly.
final class AccessibilityNotificationBus: @unchecked Sendable {
    private struct ActiveActionWindow {
        let id: AccessibilityNotificationActionWindowID
        var childLeaseCount: Int

        /// Set when the owner lease ends while child leases are still open.
        ///
        /// Owner and child leases end on independent tasks: active action observation owns
        /// the window, while a viewport transition or screen capture
        /// dispatched during that observation holds a child lease, so the
        /// owner can finish first. Ingress attributes events to the single
        /// active window, so the window must stay active - still claiming
        /// events and still absorbing new `beginActionWindow` callers as
        /// children - until the last child ends, at which point this
        /// deferred outcome is applied.
        var pendingOwnerOutcome: AccessibilityNotificationScopeOutcome?
    }

    private struct IngressLog {
        let retentionLimit: Int
        private(set) var retainedEvents: [PendingAccessibilityNotificationEvent] = []
        private(set) var latestSequence: UInt64 = 0
        private(set) var latestScopedScreenChangedSequence: UInt64 = 0
        private var evictedThroughSequence: UInt64 = 0

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
            pruneAmbientEvents()
        }

        func checkpoint(
            after cursor: AccessibilityNotificationCursor,
            selection: AccessibilityNotificationCheckpointSelection
        ) -> AccessibilityNotificationBatch {
            let selectedEvents = retainedEvents.filter {
                $0.sequence > cursor.sequence && selection.includes($0)
            }
            let selectedScreenChangedThrough = selectedEvents.last(where: {
                $0.kind == .screenChanged && $0.provenance == .scoped
            })?.sequence ?? 0
            let scopedScreenChangedThrough: UInt64 = switch selection {
            case .all, .scoped:
                latestScopedScreenChangedSequence
            case .unclaimedScoped, .actionWindow:
                selectedScreenChangedThrough
            }
            return AccessibilityNotificationBatch(
                events: selectedEvents,
                through: AccessibilityNotificationCursor(sequence: latestSequence),
                scopedScreenChangedThrough: scopedScreenChangedThrough,
                gap: selection.includesAmbient && cursor.sequence < evictedThroughSequence
                    ? AccessibilityNotificationGap(
                        droppedThroughSequence: evictedThroughSequence
                    )
                    : nil
            )
        }

        mutating func endActionWindow(
            _ actionWindowID: AccessibilityNotificationActionWindowID,
            admittedThrough: AccessibilityNotificationCursor?,
            activeHeistCursors: [UInt64: Int]
        ) {
            retainedEvents = retainedEvents.compactMap { event in
                guard event.actionWindowID == actionWindowID else { return event }
                if let admittedThrough, event.sequence <= admittedThrough.sequence {
                    return nil
                }
                var released = event
                released.actionWindowID = nil
                if !Self.isOwnedByHeist(released, activeHeistCursors: activeHeistCursors) {
                    released.provenance = .ambient
                }
                return released
            }
            pruneAmbientEvents()
        }

        mutating func endHeistScope(
            after cursor: AccessibilityNotificationCursor,
            admittedThrough: AccessibilityNotificationCursor?,
            activeHeistCursors: [UInt64: Int]
        ) {
            retainedEvents = retainedEvents.compactMap { event in
                guard event.provenance == .scoped, event.actionWindowID == nil else {
                    return event
                }
                if Self.isOwnedByHeist(event, activeHeistCursors: activeHeistCursors) {
                    return event
                }
                if let admittedThrough,
                   event.sequence > cursor.sequence,
                   event.sequence <= admittedThrough.sequence {
                    return nil
                }
                var released = event
                released.provenance = .ambient
                return released
            }
            pruneAmbientEvents()
        }

        private mutating func pruneAmbientEvents() {
            var remaining = retainedEvents.count(where: { $0.provenance == .ambient })
                - retentionLimit
            guard remaining > 0 else { return }

            var newestEvictedSequence: UInt64 = 0
            retainedEvents.removeAll { event in
                guard remaining > 0, event.provenance == .ambient else { return false }
                remaining -= 1
                newestEvictedSequence = max(newestEvictedSequence, event.sequence)
                return true
            }
            evictedThroughSequence = max(evictedThroughSequence, newestEvictedSequence)
        }

        private static func isOwnedByHeist(
            _ event: PendingAccessibilityNotificationEvent,
            activeHeistCursors: [UInt64: Int]
        ) -> Bool {
            activeHeistCursors.contains { entry in
                entry.value > 0 && entry.key < event.sequence
            }
        }
    }

    private let lock = NSLock()
    private var ingressLog = IngressLog(retentionLimit: 64)
    private var activeScopeLeases = 0
    private var activeHeistCursors: [UInt64: Int] = [:]
    private var nextActionWindowID: UInt64 = 0
    private var activeActionWindow: ActiveActionWindow?

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

    /// The full retained notification stream, including events whose payload
    /// carries no spoken text.
    func notifications(
        after cursor: AccessibilityNotificationCursor = .origin
    ) -> [PendingAccessibilityNotificationEvent] {
        lock.lock()
        defer { lock.unlock() }
        return ingressLog.checkpoint(after: cursor, selection: .all).events
    }

    /// Opens the outer correlation window for a running heist.
    ///
    /// While this scope is active, action windows may claim attribution. Unclaimed
    /// ingress remains owned by this scope until its admitted cutoff is released.
    func beginHeistScope() -> AccessibilityNotificationScopeLease {
        beginScopeLease(ownership: .heist)
    }

    /// Opens the inner attribution window for one dispatched action.
    ///
    /// Events with sequence numbers greater than this cursor can be attached to
    /// the action evidence without stealing earlier heist-level context.
    func beginActionWindow() -> AccessibilityNotificationScopeLease {
        lock.lock()
        defer { lock.unlock() }

        if var activeActionWindow {
            activeActionWindow.childLeaseCount += 1
            self.activeActionWindow = activeActionWindow
            return beginScopeLeaseLocked(ownership: .actionChild(activeActionWindow.id))
        }
        nextActionWindowID += 1
        let actionWindowID = AccessibilityNotificationActionWindowID(rawValue: nextActionWindowID)
        activeActionWindow = ActiveActionWindow(id: actionWindowID, childLeaseCount: 0)
        return beginScopeLeaseLocked(ownership: .actionOwner(actionWindowID))
    }

    private func beginScopeLease(
        ownership: AccessibilityNotificationScopeOwnership
    ) -> AccessibilityNotificationScopeLease {
        lock.lock()
        defer { lock.unlock() }

        return beginScopeLeaseLocked(ownership: ownership)
    }

    private func beginScopeLeaseLocked(
        ownership: AccessibilityNotificationScopeOwnership
    ) -> AccessibilityNotificationScopeLease {
        activeScopeLeases += 1
        let cursor = AccessibilityNotificationCursor(sequence: ingressLog.latestSequence)
        if ownership == .heist {
            activeHeistCursors[cursor.sequence, default: 0] += 1
        }
        return AccessibilityNotificationScopeLease(
            bus: self,
            cursor: cursor,
            ownership: ownership
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
            provenance: provenanceLocked,
            actionWindowID: activeActionWindow?.id
        )
        ingressLog.append(event)
        lock.unlock()
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

    fileprivate func endScopeLease(
        _ ownership: AccessibilityNotificationScopeOwnership,
        after cursor: AccessibilityNotificationCursor,
        outcome: AccessibilityNotificationScopeOutcome
    ) {
        lock.lock()
        defer { lock.unlock() }

        precondition(activeScopeLeases > 0, "Cannot end an inactive notification scope lease")
        activeScopeLeases -= 1
        switch ownership {
        case .heist:
            let remaining = activeHeistCursors[cursor.sequence, default: 0] - 1
            precondition(remaining >= 0, "Cannot end an inactive heist notification scope")
            if remaining == 0 {
                activeHeistCursors[cursor.sequence] = nil
            } else {
                activeHeistCursors[cursor.sequence] = remaining
            }
            ingressLog.endHeistScope(
                after: cursor,
                admittedThrough: outcome.admittedThrough,
                activeHeistCursors: activeHeistCursors
            )
        case .actionChild(let actionWindowID):
            precondition(
                activeActionWindow?.id == actionWindowID,
                "Cannot end a child action notification window without its owner"
            )
            precondition(
                activeActionWindow?.childLeaseCount ?? 0 > 0,
                "Cannot end an inactive child action notification window"
            )
            activeActionWindow?.childLeaseCount -= 1
            closeActionWindowIfDrainedLocked()
        case .actionOwner(let actionWindowID):
            precondition(
                activeActionWindow?.id == actionWindowID,
                "Cannot end an action notification window that is not active"
            )
            activeActionWindow?.pendingOwnerOutcome = outcome
            closeActionWindowIfDrainedLocked()
        }
    }

    private func closeActionWindowIfDrainedLocked() {
        guard
            let window = activeActionWindow,
            let outcome = window.pendingOwnerOutcome,
            window.childLeaseCount == 0
        else { return }
        ingressLog.endActionWindow(
            window.id,
            admittedThrough: outcome.admittedThrough,
            activeHeistCursors: activeHeistCursors
        )
        activeActionWindow = nil
    }

    private var provenanceLocked: AccessibilityNotificationProvenance {
        activeScopeLeases > 0 ? .scoped : .ambient
    }
}

struct AccessibilityNotificationCursor: Sendable, Equatable {
    static let origin = AccessibilityNotificationCursor(sequence: 0)

    let sequence: UInt64
}

enum AccessibilityNotificationCheckpointSelection: Sendable {
    case all
    case scoped
    case unclaimedScoped
    case actionWindow(AccessibilityNotificationActionWindowID)

    fileprivate func includes(_ event: PendingAccessibilityNotificationEvent) -> Bool {
        switch self {
        case .all:
            true
        case .scoped:
            event.provenance == .scoped
        case .unclaimedScoped:
            event.provenance == .scoped && event.actionWindowID == nil
        case .actionWindow(let actionWindowID):
            event.actionWindowID == actionWindowID
        }
    }

    fileprivate var includesAmbient: Bool {
        switch self {
        case .all:
            true
        case .scoped, .unclaimedScoped, .actionWindow:
            false
        }
    }
}

struct AccessibilityNotificationActionWindowID: RawRepresentable, Sendable, Equatable {
    let rawValue: UInt64
}

enum AccessibilityNotificationScopeOwnership: Sendable, Equatable {
    case heist
    case actionOwner(AccessibilityNotificationActionWindowID)
    case actionChild(AccessibilityNotificationActionWindowID)

    var checkpointSelection: AccessibilityNotificationCheckpointSelection {
        switch self {
        case .heist:
            .unclaimedScoped
        case .actionOwner(let actionWindowID), .actionChild(let actionWindowID):
            .actionWindow(actionWindowID)
        }
    }
}

enum AccessibilityNotificationScopeOutcome: Sendable, Equatable {
    case admitted(through: AccessibilityNotificationCursor)
    case released

    var admittedThrough: AccessibilityNotificationCursor? {
        guard case .admitted(let through) = self else { return nil }
        return through
    }
}

struct AccessibilityNotificationBatch {
    let events: [PendingAccessibilityNotificationEvent]
    let through: AccessibilityNotificationCursor
    let scopedScreenChangedThrough: UInt64
    let gap: AccessibilityNotificationGap?
}

/// A batch captured only after notification callbacks already queued on the
/// main run loop have reached the ingress log.
@MainActor
struct AccessibilityNotificationCausalCheckpoint {
    let batch: AccessibilityNotificationBatch
}

enum AccessibilityNotificationProvenance: Sendable, Equatable {
    case scoped
    case ambient
}

/// Lifetime token for scoped notification attribution.
/// `@unchecked Sendable` justification: mutable `bus` access is protected by `lock`;
/// cancellation may cross task boundaries while closing scoped observation.
final class AccessibilityNotificationScopeLease: @unchecked Sendable {
    let cursor: AccessibilityNotificationCursor

    private let lock = NSLock()
    private weak var bus: AccessibilityNotificationBus?
    private let ownership: AccessibilityNotificationScopeOwnership
    private var capturedThrough: AccessibilityNotificationCursor?

    fileprivate init(
        bus: AccessibilityNotificationBus,
        cursor: AccessibilityNotificationCursor,
        ownership: AccessibilityNotificationScopeOwnership
    ) {
        self.bus = bus
        self.cursor = cursor
        self.ownership = ownership
    }

    deinit {
        cancel()
    }

    func capture() -> AccessibilityNotificationBatch? {
        lock.lock()
        guard let bus else {
            lock.unlock()
            return nil
        }
        let batch = bus.checkpoint(after: cursor, selection: ownership.checkpointSelection)
        capturedThrough = batch.through
        lock.unlock()
        return batch
    }

    @MainActor
    func causalCheckpoint() async -> AccessibilityNotificationCausalCheckpoint? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        return capture().map(AccessibilityNotificationCausalCheckpoint.init(batch:))
    }

    func cancel() {
        finish(outcome: .released)
    }

    /// Releases the transient ingress cutoff only after its captured batch has
    /// been admitted to durable semantic history.
    func admitCaptured() {
        lock.lock()
        let capturedThrough = capturedThrough
        lock.unlock()
        finish(
            outcome: capturedThrough.map {
                AccessibilityNotificationScopeOutcome.admitted(through: $0)
            }
                ?? .released
        )
    }

    private func finish(outcome: AccessibilityNotificationScopeOutcome) {
        let bus: AccessibilityNotificationBus?
        lock.lock()
        bus = self.bus
        self.bus = nil
        lock.unlock()

        bus?.endScopeLease(ownership, after: cursor, outcome: outcome)
    }
}

struct PendingAccessibilityNotificationEvent {
    let sequence: UInt64
    let kind: AccessibilityNotificationKind
    let timestamp: Date
    /// The argument posted with the accessibility notification.
    let notificationData: PendingAccessibilityNotificationPayload
    /// UIKit's correlation subject. It is notification content only for
    /// element-change notifications.
    let associatedElement: PendingAccessibilityNotificationPayload
    var provenance: AccessibilityNotificationProvenance
    var actionWindowID: AccessibilityNotificationActionWindowID?

    init(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        provenance: AccessibilityNotificationProvenance,
        actionWindowID: AccessibilityNotificationActionWindowID? = nil
    ) {
        self.sequence = sequence
        self.kind = kind
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
        self.provenance = provenance
        self.actionWindowID = actionWindowID
    }

    init(
        sequence: UInt64,
        rawCode: UInt32,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        provenance: AccessibilityNotificationProvenance,
        actionWindowID: AccessibilityNotificationActionWindowID? = nil
    ) {
        self.init(
            sequence: sequence,
            kind: AccessibilityNotificationKind(rawCode: rawCode),
            timestamp: timestamp,
            notificationData: notificationData,
            associatedElement: associatedElement,
            provenance: provenance,
            actionWindowID: actionWindowID
        )
    }

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
