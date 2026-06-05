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
