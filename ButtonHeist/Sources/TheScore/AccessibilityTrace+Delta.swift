import Foundation

// MARK: - Accessibility Trace Delta

/// Compact description of what changed in the accessibility hierarchy after
/// an action. Each case carries exactly the data valid for that phase.
public extension AccessibilityTrace {
    /// Payload for `.noChange`.
    struct NoChange: Sendable, Equatable {
        public let elementCount: Int
        /// Capture edge this delta was derived from. nil for manually
        /// constructed or historically decoded compact deltas.
        public let captureEdge: CaptureEdge?
        /// Compatibility projection of `Capture.transition.transient` for
        /// older clients that read only `accessibilityDelta`.
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
        /// Capture edge this delta was derived from. nil for manually
        /// constructed or historically decoded compact deltas.
        public let captureEdge: CaptureEdge?
        /// Compatibility projection of `Capture.transition.transient` for
        /// older clients that read only `accessibilityDelta`.
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
        /// Capture edge this delta was derived from. nil for manually
        /// constructed or historically decoded compact deltas.
        public let captureEdge: CaptureEdge?
        /// Interface snapshot after the screen change.
        public let newInterface: Interface
        /// Compatibility projection of `Capture.transition.transient` for
        /// older clients that read only `accessibilityDelta`.
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

    /// On-the-wire `kind` discriminator. The per-case switch is the canonical
    /// Swift API; the raw string is only meaningful at the Codable boundary
    /// and for logging via `kindRawValue`.
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

        // MARK: - Cross-Case Accessors

        /// Element count for whichever phase this delta represents.
        public var elementCount: Int {
            switch self {
            case .noChange(let payload): return payload.elementCount
            case .elementsChanged(let payload): return payload.elementCount
            case .screenChanged(let payload): return payload.elementCount
            }
        }

        /// String form of the discriminator. Used by `BatchStepSummary` and
        /// other consumers that need to log the kind without switching.
        public var kindRawValue: String {
            switch self {
            case .noChange: return DeltaKind.noChange.rawValue
            case .elementsChanged: return DeltaKind.elementsChanged.rawValue
            case .screenChanged: return DeltaKind.screenChanged.rawValue
            }
        }

        /// True iff this delta is a screen change.
        public var isScreenChanged: Bool {
            if case .screenChanged = self { return true }
            return false
        }

        /// Transient elements carried by this delta, regardless of case.
        public var transient: [HeistElement] {
            switch self {
            case .noChange(let payload): return payload.transient
            case .elementsChanged(let payload): return payload.transient
            case .screenChanged(let payload): return payload.transient
            }
        }

        /// Capture edge this delta was derived from, when emitted by a
        /// capture-backed factory. nil indicates a manually constructed or
        /// historically decoded compact delta.
        public var captureEdge: CaptureEdge? {
            switch self {
            case .noChange(let payload): return payload.captureEdge
            case .elementsChanged(let payload): return payload.captureEdge
            case .screenChanged(let payload): return payload.captureEdge
            }
        }

        /// Element edits carried by this delta. Only `.elementsChanged`
        /// carries edit lists; `.screenChanged` carries a full new interface.
        public var elementEdits: ElementEdits? {
            switch self {
            case .noChange, .screenChanged:
                return nil
            case .elementsChanged(let payload):
                return payload.edits
            }
        }

        public func withCaptureEdge(_ edge: CaptureEdge) -> AccessibilityTrace.Delta {
            switch self {
            case .noChange(let payload):
                return .noChange(NoChange(
                    elementCount: payload.elementCount,
                    captureEdge: edge,
                    transient: payload.transient
                ))
            case .elementsChanged(let payload):
                return .elementsChanged(ElementsChanged(
                    elementCount: payload.elementCount,
                    edits: payload.edits,
                    captureEdge: edge,
                    transient: payload.transient
                ))
            case .screenChanged(let payload):
                return .screenChanged(ScreenChanged(
                    elementCount: payload.elementCount,
                    captureEdge: edge,
                    newInterface: payload.newInterface,
                    transient: payload.transient
                ))
            }
        }

        public func withTransient(_ transient: [HeistElement]) -> AccessibilityTrace.Delta {
            switch self {
            case .noChange(let payload):
                return .noChange(NoChange(
                    elementCount: payload.elementCount,
                    captureEdge: payload.captureEdge,
                    transient: transient
                ))
            case .elementsChanged(let payload):
                return .elementsChanged(ElementsChanged(
                    elementCount: payload.elementCount,
                    edits: payload.edits,
                    captureEdge: payload.captureEdge,
                    transient: transient
                ))
            case .screenChanged(let payload):
                return .screenChanged(ScreenChanged(
                    elementCount: payload.elementCount,
                    captureEdge: payload.captureEdge,
                    newInterface: payload.newInterface,
                    transient: transient
                ))
            }
        }
    }
}

// MARK: - Element Edits

/// The per-edit payload for `.elementsChanged`. Empty collections mean
/// "no changes of that flavour"; on the wire, empty collections are omitted.
public struct ElementEdits: Sendable, Equatable {
    public let added: [HeistElement]
    public let removed: [String]
    public let updated: [ElementUpdate]
    public let treeInserted: [TreeInsertion]
    public let treeRemoved: [TreeRemoval]
    public let treeMoved: [TreeMove]

    public init(
        added: [HeistElement] = [],
        removed: [String] = [],
        updated: [ElementUpdate] = [],
        treeInserted: [TreeInsertion] = [],
        treeRemoved: [TreeRemoval] = [],
        treeMoved: [TreeMove] = []
    ) {
        self.added = added
        self.removed = removed
        self.updated = updated
        self.treeInserted = treeInserted
        self.treeRemoved = treeRemoved
        self.treeMoved = treeMoved
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
            && treeInserted.isEmpty && treeRemoved.isEmpty && treeMoved.isEmpty
    }
}

// MARK: - ElementEdits Codable

extension ElementEdits: Codable {
    private enum CodingKeys: String, CodingKey {
        case added, removed, updated, treeInserted, treeRemoved, treeMoved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.added = try container.decodeIfPresent([HeistElement].self, forKey: .added) ?? []
        self.removed = try container.decodeIfPresent([String].self, forKey: .removed) ?? []
        self.updated = try container.decodeIfPresent([ElementUpdate].self, forKey: .updated) ?? []
        self.treeInserted = try container.decodeIfPresent([TreeInsertion].self, forKey: .treeInserted) ?? []
        self.treeRemoved = try container.decodeIfPresent([TreeRemoval].self, forKey: .treeRemoved) ?? []
        self.treeMoved = try container.decodeIfPresent([TreeMove].self, forKey: .treeMoved) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !added.isEmpty { try container.encode(added, forKey: .added) }
        if !removed.isEmpty { try container.encode(removed, forKey: .removed) }
        if !updated.isEmpty { try container.encode(updated, forKey: .updated) }
        if !treeInserted.isEmpty { try container.encode(treeInserted, forKey: .treeInserted) }
        if !treeRemoved.isEmpty { try container.encode(treeRemoved, forKey: .treeRemoved) }
        if !treeMoved.isEmpty { try container.encode(treeMoved, forKey: .treeMoved) }
    }
}

// MARK: - AccessibilityTrace.Delta Codable

extension AccessibilityTrace.Delta: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case elementCount
        case captureEdge
        case transient
        case edits
        case newInterface
    }

    public init(from decoder: Decoder) throws {
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
}
