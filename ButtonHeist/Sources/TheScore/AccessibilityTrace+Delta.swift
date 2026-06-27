import ThePlans
import Foundation

// MARK: - Accessibility Trace Delta

/// Compact description of what changed in the accessibility hierarchy after
/// an action. Each case carries exactly the data valid for that phase.
public extension AccessibilityTrace {
    /// Payload for `.noChange`.
    struct NoChange: Sendable, Equatable {
        public let elementCount: Int
        /// Capture edge this delta was derived from. nil only for standalone
        /// projection values that are not stored as action-result truth.
        public let captureEdge: CaptureEdge?
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge? = nil,
            transient: [HeistElement] = []
        ) {
            self.elementCount = elementCount
            self.captureEdge = captureEdge
            self.transient = transient
        }
    }

    /// Payload for `.elementsChanged`.
    struct ElementsChanged: Sendable, Equatable {
        public let elementCount: Int
        public let edits: ElementEdits
        /// Capture edge this delta was derived from. nil only for standalone
        /// projection values that are not stored as action-result truth.
        public let captureEdge: CaptureEdge?
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]

        public init(
            elementCount: Int,
            edits: ElementEdits,
            captureEdge: CaptureEdge? = nil,
            transient: [HeistElement] = []
        ) {
            self.elementCount = elementCount
            self.edits = edits
            self.captureEdge = captureEdge
            self.transient = transient
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
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge? = nil,
            newInterface: Interface,
            transient: [HeistElement] = []
        ) {
            self.elementCount = elementCount
            self.captureEdge = captureEdge
            self.newInterface = newInterface
            self.transient = transient
        }
    }

    /// On-the-wire `kind` discriminator. Product code should switch over
    /// `Delta`; this type exists only at the Codable/public projection edge.
    enum DeltaKind: String, Codable, Sendable {
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

    struct AccumulatedDelta: Sendable, Equatable {
        public let elementCount: Int
        public let captureEdge: CaptureEdge
        public let screenChanged: ScreenChanged?
        public let elementsChanged: ElementsChanged?
        public let transient: [HeistElement]

        public var isNoChange: Bool {
            screenChanged == nil && elementsChanged == nil
        }

        public var isSemanticChange: Bool {
            !isNoChange
        }

        public var kindDescription: String {
            if screenChanged != nil { return DeltaKind.screenChanged.rawValue }
            if elementsChanged != nil { return DeltaKind.elementsChanged.rawValue }
            return DeltaKind.noChange.rawValue
        }

        public init(
            elementCount: Int,
            captureEdge: CaptureEdge,
            screenChanged: ScreenChanged?,
            elementsChanged: ElementsChanged?,
            transient: [HeistElement]
        ) {
            self.elementCount = elementCount
            self.captureEdge = captureEdge
            self.screenChanged = screenChanged
            self.elementsChanged = elementsChanged
            self.transient = transient
        }

        public var projectedDelta: Delta {
            if let screenChanged { return .screenChanged(screenChanged) }
            if let elementsChanged { return .elementsChanged(elementsChanged) }
            return .noChange(NoChange(
                elementCount: elementCount,
                captureEdge: captureEdge,
                transient: transient
            ))
        }
    }

    /// The cumulative change facts across every edge in this trace.
    ///
    /// Unlike `endpointDelta`, this can represent screen and element changes
    /// that happened in the same wait window.
    var accumulatedDelta: AccumulatedDelta? {
        guard captures.count >= 2,
              let first = captures.first,
              let last = captures.last
        else { return nil }
        return AccessibilityTraceAccumulatedDelta.project(
            captures: captures,
            first: first,
            last: last
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
        case transient
        case edits
        case newInterface
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownDeltaKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AccessibilityTrace.DeltaKind.self, forKey: .kind)
        let elementCount = try container.decode(Int.self, forKey: .elementCount)
        let captureEdge = try container.decodeIfPresent(AccessibilityTrace.CaptureEdge.self, forKey: .captureEdge)
        let transient = try container.decodeIfPresent([HeistElement].self, forKey: .transient) ?? []

        switch kind {
        case .noChange:
            self = .noChange(AccessibilityTrace.NoChange(
                elementCount: elementCount,
                captureEdge: captureEdge,
                transient: transient
            ))

        case .elementsChanged:
            let edits = try container.decodeIfPresent(ElementEdits.self, forKey: .edits) ?? ElementEdits()
            self = .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: elementCount,
                edits: edits,
                captureEdge: captureEdge,
                transient: transient
            ))

        case .screenChanged:
            let newInterface = try container.decode(Interface.self, forKey: .newInterface)
            self = .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: elementCount,
                captureEdge: captureEdge,
                newInterface: newInterface,
                transient: transient
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
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }

        case .elementsChanged(let payload):
            try container.encode(AccessibilityTrace.DeltaKind.elementsChanged, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try container.encodeIfPresent(payload.captureEdge, forKey: .captureEdge)
            if !payload.edits.isEmpty {
                try container.encode(payload.edits, forKey: .edits)
            }
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }

        case .screenChanged(let payload):
            try container.encode(AccessibilityTrace.DeltaKind.screenChanged, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try container.encodeIfPresent(payload.captureEdge, forKey: .captureEdge)
            try container.encode(payload.newInterface, forKey: .newInterface)
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
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
        last: AccessibilityTrace.Capture
    ) -> AccessibilityTrace.AccumulatedDelta {
        let allDeltas = zip(captures, captures.dropFirst()).map(AccessibilityTrace.Delta.between)
        let transient = allDeltas.flatMap(\.transientElements)
        let captureEdge = AccessibilityTrace.CaptureEdge(before: first, after: last)

        let screenChanged = allDeltas.contains(where: \.isScreenChange)
            ? AccessibilityTrace.ScreenChanged(
                elementCount: last.interface.projectedElements.count,
                captureEdge: captureEdge,
                newInterface: last.interface,
                transient: transient
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
                transient: transient
            )
            : nil

        return AccessibilityTrace.AccumulatedDelta(
            elementCount: last.interface.projectedElements.count,
            captureEdge: captureEdge,
            screenChanged: screenChanged,
            elementsChanged: elementsChanged,
            transient: transient
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
}
