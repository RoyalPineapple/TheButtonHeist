import ThePlans
import Foundation

// MARK: - Accessibility Trace Delta

/// Compact description of what changed in the accessibility hierarchy after
/// an action. Each case carries exactly the data valid for that phase.
public extension AccessibilityTrace {
    enum DeltaProjection: Sendable, Equatable {
        case semantic
        case geometryAware

        var includesGeometry: Bool {
            self == .geometryAware
        }
    }

    /// Capture-level facts that can be trusted without consulting bounded
    /// render projections or element edit pairing.
    struct InteractionDigest: Codable, Sendable, Equatable {
        public let elementCountBefore: Int
        public let elementCountAfter: Int
        public let elementCountChanged: Bool
        public let elementSetChanged: Bool
        public let screenIdBefore: String?
        public let screenIdAfter: String?
        public let screenIdChanged: Bool
        /// True when direct first-responder identity or software keyboard
        /// visibility changes. Keyboard movement is focus evidence for
        /// transition-heavy text-entry activations where the final responder
        /// target may be rebuilt under a new screen.
        public let firstResponderChanged: Bool

        public init(
            elementCountBefore: Int,
            elementCountAfter: Int,
            elementSetChanged: Bool,
            screenIdBefore: String?,
            screenIdAfter: String?,
            firstResponderChanged: Bool
        ) {
            self.elementCountBefore = elementCountBefore
            self.elementCountAfter = elementCountAfter
            self.elementCountChanged = elementCountBefore != elementCountAfter
            self.elementSetChanged = elementSetChanged
            self.screenIdBefore = screenIdBefore
            self.screenIdAfter = screenIdAfter
            self.screenIdChanged = screenIdBefore != screenIdAfter
            self.firstResponderChanged = firstResponderChanged
        }
    }

    /// Payload for `.noChange`.
    struct NoChange: Sendable, Equatable {
        public let elementCount: Int
        /// Capture edge this delta was derived from. nil only for standalone
        /// projection values that are not stored as action-result truth.
        public let captureEdge: CaptureEdge?
        /// Stable before/after facts derived from raw captures, before any
        /// renderer limits or element edit omission.
        public let interactionDigest: InteractionDigest?
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge? = nil,
            interactionDigest: InteractionDigest? = nil,
            transient: [HeistElement] = []
        ) {
            self.elementCount = elementCount
            self.captureEdge = captureEdge
            self.interactionDigest = interactionDigest
            self.transient = transient
        }

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge? = nil,
            transient: [HeistElement] = []
        ) {
            self.init(
                elementCount: elementCount,
                captureEdge: captureEdge,
                interactionDigest: nil,
                transient: transient
            )
        }
    }

    /// Payload for `.elementsChanged`.
    struct ElementsChanged: Sendable, Equatable {
        public let elementCount: Int
        public let edits: ElementEdits
        /// Capture edge this delta was derived from. nil only for standalone
        /// projection values that are not stored as action-result truth.
        public let captureEdge: CaptureEdge?
        /// Stable before/after facts derived from raw captures, before any
        /// renderer limits or element edit omission.
        public let interactionDigest: InteractionDigest?
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]
        /// Scoped layout-change evidence that classified this edge as an
        /// element transition, including notification-only changes.
        public let accessibilityNotifications: [AccessibilityNotificationEvidence]

        public init(
            elementCount: Int,
            edits: ElementEdits,
            captureEdge: CaptureEdge? = nil,
            interactionDigest: InteractionDigest? = nil,
            transient: [HeistElement] = [],
            accessibilityNotifications: [AccessibilityNotificationEvidence] = []
        ) {
            self.elementCount = elementCount
            self.edits = edits
            self.captureEdge = captureEdge
            self.interactionDigest = interactionDigest
            self.transient = transient
            self.accessibilityNotifications = accessibilityNotifications
        }

        public init(
            elementCount: Int,
            edits: ElementEdits,
            captureEdge: CaptureEdge? = nil,
            transient: [HeistElement] = []
        ) {
            self.init(
                elementCount: elementCount,
                edits: edits,
                captureEdge: captureEdge,
                interactionDigest: nil,
                transient: transient
            )
        }
    }

    /// Payload for `.screenChanged`.
    struct ScreenChanged: Sendable, Equatable {
        public let elementCount: Int
        /// Capture edge this delta was derived from. nil only for standalone
        /// projection values that are not stored as action-result truth.
        public let captureEdge: CaptureEdge?
        /// Interface snapshot after the screen change.
        public let newInterface: Interface
        /// Stable before/after facts derived from raw captures, before any
        /// renderer limits or element edit omission.
        public let interactionDigest: InteractionDigest?
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]
        /// Scoped screen-appearance evidence that classified this edge as a
        /// screen transition.
        public let accessibilityNotifications: [AccessibilityNotificationEvidence]

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge? = nil,
            newInterface: Interface,
            interactionDigest: InteractionDigest? = nil,
            transient: [HeistElement] = [],
            accessibilityNotifications: [AccessibilityNotificationEvidence] = []
        ) {
            self.elementCount = elementCount
            self.captureEdge = captureEdge
            self.newInterface = newInterface
            self.interactionDigest = interactionDigest
            self.transient = transient
            self.accessibilityNotifications = accessibilityNotifications
        }

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge? = nil,
            newInterface: Interface,
            transient: [HeistElement] = []
        ) {
            self.init(
                elementCount: elementCount,
                captureEdge: captureEdge,
                newInterface: newInterface,
                interactionDigest: nil,
                transient: transient
            )
        }
    }

    /// On-the-wire `kind` discriminator. Product code should switch over
    /// `Delta`; this type exists only at the Codable/public projection edge.
    enum DeltaKind: String, Codable {
        case noChange
        case elementsChanged
        case screenChanged
    }

    enum Delta: Sendable, Equatable {
        /// Hierarchy is unchanged. May still carry transient elements that
        /// appeared and disappeared during settle while baseline and final were
        /// otherwise identical.
        case noChange(NoChange)

        /// Element-level edits within the same screen.
        case elementsChanged(ElementsChanged)

        /// View controller identity changed — a brand new interface tree.
        case screenChanged(ScreenChanged)
    }

    enum AccumulatedDeltaChange: Sendable, Equatable {
        case noChange
        case elementsChanged(ElementsChanged)
        case screenChanged(ScreenChanged)
        case screenAndElementsChanged(screen: ScreenChanged, elements: ElementsChanged)
    }

    struct AccumulatedDelta: Sendable, Equatable {
        public let elementCount: Int
        public let captureEdge: CaptureEdge
        public let change: AccumulatedDeltaChange
        public let interactionDigest: InteractionDigest?
        public let transient: [HeistElement]

        public var isNoChange: Bool {
            if case .noChange = change { return true }
            return false
        }

        public var isSemanticChange: Bool {
            !isNoChange
        }

        public var kindDescription: String {
            switch change {
            case .noChange:
                return DeltaKind.noChange.rawValue
            case .elementsChanged:
                return DeltaKind.elementsChanged.rawValue
            case .screenChanged, .screenAndElementsChanged:
                return DeltaKind.screenChanged.rawValue
            }
        }

        public var screenChanged: ScreenChanged? {
            switch change {
            case .screenChanged(let screenChanged):
                return screenChanged
            case .screenAndElementsChanged(let screenChanged, _):
                return screenChanged
            case .noChange, .elementsChanged:
                return nil
            }
        }

        public var elementsChanged: ElementsChanged? {
            switch change {
            case .elementsChanged(let elementsChanged):
                return elementsChanged
            case .screenAndElementsChanged(_, let elementsChanged):
                return elementsChanged
            case .noChange, .screenChanged:
                return nil
            }
        }

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge,
            change: AccumulatedDeltaChange,
            interactionDigest: InteractionDigest?,
            transient: [HeistElement]
        ) {
            self.elementCount = elementCount
            self.captureEdge = captureEdge
            self.change = change
            self.interactionDigest = interactionDigest
            self.transient = transient
        }

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge,
            transient: [HeistElement]
        ) {
            self.init(
                elementCount: elementCount,
                captureEdge: captureEdge,
                change: .noChange,
                interactionDigest: nil,
                transient: transient
            )
        }

        public var projectedDelta: Delta {
            switch change {
            case .screenChanged(let screenChanged),
                 .screenAndElementsChanged(let screenChanged, _):
                return .screenChanged(screenChanged)
            case .elementsChanged(let elementsChanged):
                return .elementsChanged(elementsChanged)
            case .noChange:
                return .noChange(NoChange(
                elementCount: elementCount,
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient
                ))
            }
        }
    }

    /// The cumulative change facts across every edge in this trace.
    ///
    /// Unlike `endpointDelta`, this can represent screen and element changes
    /// that happened in the same wait window.
    var accumulatedDelta: AccumulatedDelta? {
        accumulatedDelta(projection: .semantic)
    }

    func accumulatedDelta(projection: DeltaProjection) -> AccumulatedDelta? {
        guard captures.count >= 2,
              let first = captures.first,
              let last = captures.last
        else { return nil }
        return AccessibilityTraceAccumulatedDelta.project(
            captures: captures,
            first: first,
            last: last,
            projection: projection
        )
    }

    /// The cumulative delta across every edge in this trace.
    ///
    /// `endpointDelta` answers "what differs between the first and last capture".
    /// This answers "what changed at any point while moving from the first capture
    /// to the last capture", preserving intermediate element edits that later
    /// settled away.
    var accumulatedEndpointDelta: AccessibilityTrace.Delta? {
        accumulatedDelta?.projectedDelta
    }
}

// MARK: - Element Edits

/// The per-edit payload for `.elementsChanged`. Empty collections mean
/// "no changes of that flavour"; on the wire, empty collections are omitted.
public struct ElementEdits: Sendable, Equatable {
    public let added: [HeistElement]
    public let removed: [HeistElement]
    public let updated: [ElementUpdate]

    public init(
        added: [HeistElement] = [],
        removed: [HeistElement] = [],
        updated: [ElementUpdate] = []
    ) {
        self.added = added
        self.removed = removed
        self.updated = updated
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

// MARK: - ElementEdits Codable

extension ElementEdits: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case added, removed, updated
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ElementEdits")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.added = try container.decodeIfPresent([HeistElement].self, forKey: .added) ?? []
        self.removed = try container.decodeIfPresent([HeistElement].self, forKey: .removed) ?? []
        self.updated = try container.decodeIfPresent([ElementUpdate].self, forKey: .updated) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !added.isEmpty { try container.encode(added, forKey: .added) }
        if !removed.isEmpty { try container.encode(removed, forKey: .removed) }
        if !updated.isEmpty { try container.encode(updated, forKey: .updated) }
    }
}

// MARK: - AccessibilityTrace.Delta Codable

extension AccessibilityTrace.Delta: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case elementCount
        case captureEdge
        case interactionDigest
        case transient
        case accessibilityNotifications
        case edits
        case newInterface
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownDeltaKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AccessibilityTrace.DeltaKind.self, forKey: .kind)
        let elementCount = try container.decode(Int.self, forKey: .elementCount)
        let captureEdge = try container.decodeIfPresent(AccessibilityTrace.CaptureEdge.self, forKey: .captureEdge)
        let interactionDigest = try container.decodeIfPresent(
            AccessibilityTrace.InteractionDigest.self,
            forKey: .interactionDigest
        )
        let transient = try container.decodeIfPresent([HeistElement].self, forKey: .transient) ?? []
        let accessibilityNotifications = try container.decodeIfPresent(
            [AccessibilityNotificationEvidence].self,
            forKey: .accessibilityNotifications
        ) ?? []

        switch kind {
        case .noChange:
            self = .noChange(AccessibilityTrace.NoChange(
                elementCount: elementCount,
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient
            ))

        case .elementsChanged:
            let edits = try container.decodeIfPresent(ElementEdits.self, forKey: .edits) ?? ElementEdits()
            self = .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: elementCount,
                edits: edits,
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications
            ))

        case .screenChanged:
            let newInterface = try container.decode(Interface.self, forKey: .newInterface)
            self = .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: elementCount,
                captureEdge: captureEdge,
                newInterface: newInterface,
                interactionDigest: interactionDigest,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noChange(let payload):
            try container.encode(AccessibilityTrace.DeltaKind.noChange, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try container.encodeIfPresent(payload.captureEdge, forKey: .captureEdge)
            try container.encodeIfPresent(payload.interactionDigest, forKey: .interactionDigest)
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }

        case .elementsChanged(let payload):
            try container.encode(AccessibilityTrace.DeltaKind.elementsChanged, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try container.encodeIfPresent(payload.captureEdge, forKey: .captureEdge)
            try container.encodeIfPresent(payload.interactionDigest, forKey: .interactionDigest)
            if !payload.edits.isEmpty {
                try container.encode(payload.edits, forKey: .edits)
            }
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }
            if !payload.accessibilityNotifications.isEmpty {
                try container.encode(payload.accessibilityNotifications, forKey: .accessibilityNotifications)
            }

        case .screenChanged(let payload):
            try container.encode(AccessibilityTrace.DeltaKind.screenChanged, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try container.encodeIfPresent(payload.captureEdge, forKey: .captureEdge)
            try container.encodeIfPresent(payload.interactionDigest, forKey: .interactionDigest)
            try container.encode(payload.newInterface, forKey: .newInterface)
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }
            if !payload.accessibilityNotifications.isEmpty {
                try container.encode(payload.accessibilityNotifications, forKey: .accessibilityNotifications)
            }
        }
    }

    private static func rejectUnknownDeltaKeys(_ decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "accessibility delta")
    }
}

private enum AccessibilityTraceAccumulatedDelta {
    static func project(
        captures: [AccessibilityTrace.Capture],
        first: AccessibilityTrace.Capture,
        last: AccessibilityTrace.Capture,
        projection: AccessibilityTrace.DeltaProjection
    ) -> AccessibilityTrace.AccumulatedDelta {
        let allDeltas = zip(captures, captures.dropFirst()).map { before, after in
            AccessibilityTrace.Delta.between(before, after, projection: projection)
        }
        let transient = allDeltas.flatMap(\.transientElements)
        let accessibilityNotifications = allDeltas.flatMap(\.accessibilityNotifications)
        let captureEdge = AccessibilityTrace.CaptureEdge(before: first, after: last)
        let interactionDigest = AccessibilityTrace.InteractionDigest(between: first, and: last)

        let screenChanged = allDeltas.contains(where: \.isScreenChange)
            ? AccessibilityTrace.ScreenChanged(
                elementCount: last.interface.projectedElements.count,
                captureEdge: captureEdge,
                newInterface: last.interface,
                interactionDigest: interactionDigest,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications.filter {
                    $0.kind == .screenChanged
                }
            )
            : nil

        let elementDeltas = allDeltas.compactMap(\.elementChangePayload)
        let edits = ElementEdits(
            added: elementDeltas.flatMap(\.edits.added),
            removed: elementDeltas.flatMap(\.edits.removed),
            updated: elementDeltas.flatMap(\.edits.updated)
        )
        let elementsChanged = !elementDeltas.isEmpty || !edits.isEmpty
            ? AccessibilityTrace.ElementsChanged(
                elementCount: last.interface.projectedElements.count,
                edits: edits,
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications.filter {
                    $0.kind.isElementTransition
                }
            )
            : nil

        let change: AccessibilityTrace.AccumulatedDeltaChange
        switch (screenChanged, elementsChanged) {
        case (.some(let screenChanged), .some(let elementsChanged)):
            change = .screenAndElementsChanged(screen: screenChanged, elements: elementsChanged)
        case (.some(let screenChanged), nil):
            change = .screenChanged(screenChanged)
        case (nil, .some(let elementsChanged)):
            change = .elementsChanged(elementsChanged)
        case (nil, nil):
            change = .noChange
        }

        return AccessibilityTrace.AccumulatedDelta(
            elementCount: last.interface.projectedElements.count,
            captureEdge: captureEdge,
            change: change,
            interactionDigest: interactionDigest,
            transient: transient
        )
    }
}

extension AccessibilityTrace.InteractionDigest {
    init(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture
    ) {
        let beforeRecords = before.interface.projectedElementRecords.map(ElementDiffRecord.init)
        let afterRecords = after.interface.projectedElementRecords.map(ElementDiffRecord.init)
        self.init(
            elementCountBefore: beforeRecords.count,
            elementCountAfter: afterRecords.count,
            elementSetChanged: AccessibilityTraceElementDiff.pairingKeyMultisetDiffers(
                beforeRecords: beforeRecords,
                afterRecords: afterRecords
            ),
            screenIdBefore: before.screenId,
            screenIdAfter: after.screenId,
            firstResponderChanged: before.context.firstResponder != after.context.firstResponder
                || before.context.keyboardVisible != after.context.keyboardVisible
        )
    }
}

private extension AccessibilityTrace.Delta {
    var isScreenChange: Bool {
        if case .screenChanged = self { return true }
        return false
    }

    var elementChangePayload: AccessibilityTrace.ElementsChanged? {
        if case .elementsChanged(let payload) = self { return payload }
        return nil
    }

    var transientElements: [HeistElement] {
        switch self {
        case .noChange(let payload):
            return payload.transient
        case .elementsChanged(let payload):
            return payload.transient
        case .screenChanged(let payload):
            return payload.transient
        }
    }

    var accessibilityNotifications: [AccessibilityNotificationEvidence] {
        switch self {
        case .noChange:
            return []
        case .elementsChanged(let payload):
            return payload.accessibilityNotifications
        case .screenChanged(let payload):
            return payload.accessibilityNotifications
        }
    }
}
