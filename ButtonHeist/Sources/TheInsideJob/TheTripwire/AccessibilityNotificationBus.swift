#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore

/// `@unchecked Sendable` justification: all mutable state is protected by
/// `lock`; waiter continuations are resumed outside the lock and timeout
/// tasks reference the bus weakly.
final class AccessibilityNotificationBus: @unchecked Sendable {
    private enum CycleClaimant: Equatable {
        case observation
        case scope(
            AccessibilityNotificationScopeOwnership,
            AccessibilityNotificationCursor
        )
    }

    private enum CycleClaimSelection {
        case observation(
            after: AccessibilityNotificationCursor,
            excluding: AccessibilityNotificationActionWindowID?
        )
        case scope(
            AccessibilityNotificationScopeOwnership,
            after: AccessibilityNotificationCursor
        )

        func includes(_ event: PendingAccessibilityNotificationEvent) -> Bool {
            switch self {
            case .observation(let cursor, let activeActionWindowID):
                event.owner.isEligibleForCycleClaim(
                    sequence: event.sequence,
                    after: cursor,
                    excluding: activeActionWindowID
                )
            case .scope(let ownership, let cursor):
                event.sequence > cursor.sequence
                    && ownership.checkpointSelection.includes(event)
            }
        }

        var includesAmbient: Bool {
            if case .observation = self { true } else { false }
        }
    }

    private struct ActiveActionWindow {
        let id: AccessibilityNotificationActionWindowID
        let cursor: AccessibilityNotificationCursor
        var childLeaseCount: Int
        var ownerEnded: Bool
    }

    private struct FrozenCycleClaim {
        let id: AccessibilityNotificationCycleClaim.ID
        var claimant: CycleClaimant
        let advancesAmbientCursor: Bool
        let batch: AccessibilityNotificationBatch
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
            if case .screenChanged = event.kind, event.owner.provenance == .scoped {
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
                $0.kind == .screenChanged && $0.owner.provenance == .scoped
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

        mutating func freezeCycleClaim(
            id: AccessibilityNotificationCycleClaim.ID,
            selection: CycleClaimSelection
        ) -> AccessibilityNotificationBatch {
            let cutoff = AccessibilityNotificationCursor(sequence: latestSequence)
            var claimedEvents: [PendingAccessibilityNotificationEvent] = []
            for index in retainedEvents.indices {
                let event = retainedEvents[index]
                guard event.sequence <= cutoff.sequence,
                      selection.includes(event)
                else {
                    continue
                }
                retainedEvents[index].owner = .cycle(
                    id,
                    provenance: event.owner.provenance
                )
                claimedEvents.append(retainedEvents[index])
            }
            let scopedScreenChangedThrough = claimedEvents.last(where: {
                $0.kind == .screenChanged && $0.owner.provenance == .scoped
            })?.sequence ?? 0
            return AccessibilityNotificationBatch(
                events: claimedEvents,
                through: cutoff,
                scopedScreenChangedThrough: scopedScreenChangedThrough,
                gap: selection.includesAmbient
                    && admittedAmbientThrough(selection) < evictedThroughSequence
                    ? AccessibilityNotificationGap(
                        droppedThroughSequence: evictedThroughSequence
                    )
                    : nil
            )
        }

        mutating func acknowledgeCycleClaim(_ id: AccessibilityNotificationCycleClaim.ID) {
            retainedEvents.removeAll { event in
                guard case .cycle(let ownerID, _) = event.owner else { return false }
                return ownerID == id
            }
        }

        private func admittedAmbientThrough(_ selection: CycleClaimSelection) -> UInt64 {
            guard case .observation(let cursor, _) = selection else { return 0 }
            return cursor.sequence
        }

        private mutating func pruneAmbientEvents() {
            var remaining = retainedEvents.count(where: { $0.owner == .ambient })
                - retentionLimit
            guard remaining > 0 else { return }

            var newestEvictedSequence: UInt64 = 0
            retainedEvents.removeAll { event in
                guard remaining > 0, event.owner == .ambient else { return false }
                remaining -= 1
                newestEvictedSequence = max(newestEvictedSequence, event.sequence)
                return true
            }
            evictedThroughSequence = max(evictedThroughSequence, newestEvictedSequence)
        }
    }

    private let lock = NSLock()
    private var ingressLog = IngressLog(retentionLimit: 64)
    private var activeHeistCursor: AccessibilityNotificationCursor?
    private var nextActionWindowID: UInt64 = 0
    private var activeActionWindow: ActiveActionWindow?
    private var nextCycleClaimID: UInt64 = 0
    private var frozenCycleClaim: FrozenCycleClaim?
    private var admittedAmbientThrough = AccessibilityNotificationCursor.origin

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
            return beginScopeLeaseLocked(
                ownership: .actionChild(activeActionWindow.id),
                cursor: activeActionWindow.cursor
            )
        }
        nextActionWindowID += 1
        let actionWindowID = AccessibilityNotificationActionWindowID(rawValue: nextActionWindowID)
        let cursor = AccessibilityNotificationCursor(sequence: ingressLog.latestSequence)
        activeActionWindow = ActiveActionWindow(
            id: actionWindowID,
            cursor: cursor,
            childLeaseCount: 0,
            ownerEnded: false
        )
        return beginScopeLeaseLocked(
            ownership: .actionOwner(actionWindowID),
            cursor: cursor
        )
    }

    private func beginScopeLease(
        ownership: AccessibilityNotificationScopeOwnership
    ) -> AccessibilityNotificationScopeLease {
        lock.lock()
        defer { lock.unlock() }

        return beginScopeLeaseLocked(ownership: ownership)
    }

    private func beginScopeLeaseLocked(
        ownership: AccessibilityNotificationScopeOwnership,
        cursor: AccessibilityNotificationCursor? = nil
    ) -> AccessibilityNotificationScopeLease {
        let cursor = cursor ?? AccessibilityNotificationCursor(sequence: ingressLog.latestSequence)
        if ownership == .heist {
            precondition(activeHeistCursor == nil, "Only one heist notification scope may be active")
            activeHeistCursor = cursor
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
            owner: ownerLocked
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

    func freezeObservationCycleClaim() -> AccessibilityNotificationCycleClaim? {
        lock.lock()
        defer { lock.unlock() }

        if let frozenCycleClaim {
            guard frozenCycleClaim.claimant == .observation else { return nil }
            return AccessibilityNotificationCycleClaim(
                bus: self,
                id: frozenCycleClaim.id,
                batch: frozenCycleClaim.batch
            )
        }
        nextCycleClaimID += 1
        let id = AccessibilityNotificationCycleClaim.ID(rawValue: nextCycleClaimID)
        let batch = ingressLog.freezeCycleClaim(
            id: id,
            selection: .observation(
                after: admittedAmbientThrough,
                excluding: activeActionWindow?.id
            )
        )
        frozenCycleClaim = FrozenCycleClaim(
            id: id,
            claimant: .observation,
            advancesAmbientCursor: true,
            batch: batch
        )
        return AccessibilityNotificationCycleClaim(bus: self, id: id, batch: batch)
    }

    fileprivate func freezeCycleClaim(
        for ownership: AccessibilityNotificationScopeOwnership,
        after cursor: AccessibilityNotificationCursor
    ) -> AccessibilityNotificationCycleClaim? {
        lock.lock()
        defer { lock.unlock() }

        let claimant = CycleClaimant.scope(ownership, cursor)
        if let frozenCycleClaim {
            guard frozenCycleClaim.claimant == claimant else { return nil }
            return AccessibilityNotificationCycleClaim(
                bus: self,
                id: frozenCycleClaim.id,
                batch: frozenCycleClaim.batch
            )
        }
        nextCycleClaimID += 1
        let id = AccessibilityNotificationCycleClaim.ID(rawValue: nextCycleClaimID)
        let batch = ingressLog.freezeCycleClaim(
            id: id,
            selection: .scope(ownership, after: cursor)
        )
        frozenCycleClaim = FrozenCycleClaim(
            id: id,
            claimant: claimant,
            advancesAmbientCursor: false,
            batch: batch
        )
        return AccessibilityNotificationCycleClaim(bus: self, id: id, batch: batch)
    }

    fileprivate func acknowledgeCycleClaim(
        _ id: AccessibilityNotificationCycleClaim.ID
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard frozenCycleClaim?.id == id else { return false }
        ingressLog.acknowledgeCycleClaim(id)
        if frozenCycleClaim?.advancesAmbientCursor == true {
            admittedAmbientThrough = frozenCycleClaim?.batch.through ?? admittedAmbientThrough
        }
        frozenCycleClaim = nil
        return true
    }

    fileprivate func endScopeLease(
        _ ownership: AccessibilityNotificationScopeOwnership,
        after cursor: AccessibilityNotificationCursor
    ) {
        lock.lock()
        defer { lock.unlock() }

        switch ownership {
        case .heist:
            precondition(
                activeHeistCursor == cursor,
                "Cannot end an inactive heist notification scope"
            )
            activeHeistCursor = nil
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
            activeActionWindow?.ownerEnded = true
            closeActionWindowIfDrainedLocked()
        }
        if frozenCycleClaim?.claimant == .scope(ownership, cursor) {
            frozenCycleClaim?.claimant = .observation
        }
    }

    private func closeActionWindowIfDrainedLocked() {
        guard
            let window = activeActionWindow,
            window.ownerEnded,
            window.childLeaseCount == 0
        else { return }
        activeActionWindow = nil
    }

    private var ownerLocked: PendingAccessibilityNotificationEvent.Owner {
        if let actionWindowID = activeActionWindow?.id {
            return .action(actionWindowID)
        }
        if let activeHeistCursor {
            return .heist(activeHeistCursor)
        }
        return .ambient
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
            event.owner.provenance == .scoped
        case .unclaimedScoped:
            if case .heist = event.owner { true } else { false }
        case .actionWindow(let actionWindowID):
            event.owner.actionWindowID == actionWindowID
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

struct AccessibilityNotificationBatch {
    let events: [PendingAccessibilityNotificationEvent]
    let through: AccessibilityNotificationCursor
    let scopedScreenChangedThrough: UInt64
    let gap: AccessibilityNotificationGap?
}

final class AccessibilityNotificationCycleClaim {
    struct ID: RawRepresentable, Sendable, Equatable {
        let rawValue: UInt64
    }

    let id: ID
    let batch: AccessibilityNotificationBatch

    private weak var bus: AccessibilityNotificationBus?

    fileprivate init(
        bus: AccessibilityNotificationBus,
        id: ID,
        batch: AccessibilityNotificationBatch
    ) {
        self.bus = bus
        self.id = id
        self.batch = batch
    }

    @discardableResult
    func acknowledge() -> Bool {
        bus?.acknowledgeCycleClaim(id) ?? false
    }
}

enum AccessibilityNotificationProvenance: Sendable, Equatable {
    case scoped
    case ambient
}

/// Lifetime token for scoped notification attribution.
/// `@unchecked Sendable` justification: mutable `bus` access is protected by `lock`;
/// cancellation may cross task boundaries while closing scoped observation.
final class AccessibilityNotificationScopeLease: @unchecked Sendable {
    private enum State: Equatable {
        case active
        case admitting
        case finished
    }

    let cursor: AccessibilityNotificationCursor

    private let lock = NSLock()
    private weak var bus: AccessibilityNotificationBus?
    private let ownership: AccessibilityNotificationScopeOwnership
    private var state = State.active

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
        let bus = lock.withLock { self.bus }
        return bus?.freezeCycleClaim(for: ownership, after: cursor)?.batch
    }

    @MainActor
    func admitCausallyCaptured<Result>(
        _ commit: (AccessibilityNotificationBatch) async -> Result?
    ) async -> Result? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        return await admitCaptured(commit)
    }

    @MainActor
    func admitCaptured<Result>(
        _ commit: (AccessibilityNotificationBatch) async -> Result?
    ) async -> Result? {
        guard let bus = lock.withLock({ () -> AccessibilityNotificationBus? in
            guard state == .active, let bus else { return nil }
            state = .admitting
            return bus
        }) else {
            return nil
        }

        guard let claim = bus.freezeCycleClaim(for: ownership, after: cursor) else {
            lock.withLock {
                if state == .admitting {
                    state = .active
                }
            }
            return nil
        }
        guard let result = await commit(claim.batch) else {
            lock.withLock {
                if state == .admitting {
                    state = .active
                }
            }
            return nil
        }
        guard claim.acknowledge() else {
            lock.withLock {
                if state == .admitting {
                    state = .active
                }
            }
            return nil
        }
        finish()
        return result
    }

    func cancel() {
        finish()
    }

    private func finish() {
        let bus = lock.withLock { () -> AccessibilityNotificationBus? in
            guard state != .finished else { return nil }
            state = .finished
            let bus = self.bus
            self.bus = nil
            return bus
        }

        bus?.endScopeLease(ownership, after: cursor)
    }
}

struct PendingAccessibilityNotificationEvent {
    enum Owner: Sendable, Equatable {
        case ambient
        case heist(AccessibilityNotificationCursor)
        case action(AccessibilityNotificationActionWindowID)
        case cycle(
            AccessibilityNotificationCycleClaim.ID,
            provenance: AccessibilityNotificationProvenance
        )

        var provenance: AccessibilityNotificationProvenance {
            switch self {
            case .ambient:
                .ambient
            case .heist, .action:
                .scoped
            case .cycle(_, let provenance):
                provenance
            }
        }

        var actionWindowID: AccessibilityNotificationActionWindowID? {
            guard case .action(let id) = self else { return nil }
            return id
        }

        func isEligibleForCycleClaim(
            sequence: UInt64,
            after ambientCursor: AccessibilityNotificationCursor,
            excluding activeActionWindowID: AccessibilityNotificationActionWindowID?
        ) -> Bool {
            switch self {
            case .ambient:
                sequence > ambientCursor.sequence
            case .heist:
                true
            case .action(let id):
                id != activeActionWindowID
            case .cycle:
                false
            }
        }
    }

    let sequence: UInt64
    let kind: AccessibilityNotificationKind
    let timestamp: Date
    /// The argument posted with the accessibility notification.
    let notificationData: PendingAccessibilityNotificationPayload
    /// UIKit's correlation subject. It is notification content only for
    /// element-change notifications.
    let associatedElement: PendingAccessibilityNotificationPayload
    var owner: Owner

    var provenance: AccessibilityNotificationProvenance {
        owner.provenance
    }

    var actionWindowID: AccessibilityNotificationActionWindowID? {
        owner.actionWindowID
    }

    init(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        provenance: AccessibilityNotificationProvenance,
        actionWindowID: AccessibilityNotificationActionWindowID? = nil
    ) {
        let owner: Owner = if let actionWindowID {
            .action(actionWindowID)
        } else {
            switch provenance {
            case .scoped:
                .heist(.origin)
            case .ambient:
                .ambient
            }
        }
        self.init(
            sequence: sequence,
            kind: kind,
            timestamp: timestamp,
            notificationData: notificationData,
            associatedElement: associatedElement,
            owner: owner
        )
    }

    fileprivate init(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        owner: Owner
    ) {
        self.sequence = sequence
        self.kind = kind
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
        self.owner = owner
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

    fileprivate init(
        sequence: UInt64,
        rawCode: UInt32,
        timestamp: Date,
        notificationData: PendingAccessibilityNotificationPayload,
        associatedElement: PendingAccessibilityNotificationPayload,
        owner: Owner
    ) {
        self.init(
            sequence: sequence,
            kind: AccessibilityNotificationKind(rawCode: rawCode),
            timestamp: timestamp,
            notificationData: notificationData,
            associatedElement: associatedElement,
            owner: owner
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
