import Foundation

// MARK: - Interface Delta

/// Compact description of what changed in the accessibility hierarchy after
/// an action. Each case carries exactly the data valid for that phase.
public enum InterfaceDelta: Sendable {
    /// Hierarchy is unchanged. May still carry transient elements that
    /// appeared and disappeared during settle while baseline and final were
    /// otherwise identical.
    case noChange(NoChange)

    /// Element-level edits within the same screen.
    case elementsChanged(ElementsChanged)

    /// View controller identity changed — a brand new interface tree.
    /// May carry post-edit element changes folded in by
    /// `NetDeltaAccumulator.mergeAfterScreenChange` for batch merges.
    case screenChanged(ScreenChanged)

    // MARK: - Per-Case Payloads

    /// Payload for `.noChange`.
    public struct NoChange: Sendable {
        public let elementCount: Int
        /// Elements that appeared and disappeared during settle while
        /// baseline and final were otherwise identical.
        public let transient: [HeistElement]

        public init(elementCount: Int, transient: [HeistElement] = []) {
            self.elementCount = elementCount
            self.transient = transient
        }
    }

    /// Payload for `.elementsChanged`.
    public struct ElementsChanged: Sendable {
        public let elementCount: Int
        public let edits: ElementEdits
        public let transient: [HeistElement]

        public init(elementCount: Int, edits: ElementEdits, transient: [HeistElement] = []) {
            self.elementCount = elementCount
            self.edits = edits
            self.transient = transient
        }
    }

    /// Payload for `.screenChanged`.
    public struct ScreenChanged: Sendable {
        public let elementCount: Int
        public let newInterface: Interface
        /// Element edits that happened *after* the screen change, folded in
        /// by `NetDeltaAccumulator.mergeAfterScreenChange`. nil for
        /// per-action deltas; populated only for batch merges.
        public let postEdits: ElementEdits?
        public let transient: [HeistElement]

        public init(
            elementCount: Int,
            newInterface: Interface,
            postEdits: ElementEdits? = nil,
            transient: [HeistElement] = []
        ) {
            self.elementCount = elementCount
            self.newInterface = newInterface
            self.postEdits = postEdits
            self.transient = transient
        }
    }

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
        case .noChange: return Kind.noChange.rawValue
        case .elementsChanged: return Kind.elementsChanged.rawValue
        case .screenChanged: return Kind.screenChanged.rawValue
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

    /// Elements that appear in this delta — either because they were added
    /// in `.elementsChanged.edits.added` or they appear in
    /// `.screenChanged.postEdits.added`. Used by `ActionExpectation` for
    /// `elementAppeared` validation across element-level and post-screen-change
    /// edits.
    public var addedAcrossCases: [HeistElement] {
        switch self {
        case .noChange:
            return []
        case .elementsChanged(let payload):
            return payload.edits.added
        case .screenChanged(let payload):
            return payload.postEdits?.added ?? []
        }
    }

    /// HeistIds removed by this delta in either `.elementsChanged.edits.removed`
    /// or `.screenChanged.postEdits.removed`.
    public var removedAcrossCases: [String] {
        switch self {
        case .noChange:
            return []
        case .elementsChanged(let payload):
            return payload.edits.removed
        case .screenChanged(let payload):
            return payload.postEdits?.removed ?? []
        }
    }

    /// Element updates from either `.elementsChanged.edits.updated` or
    /// `.screenChanged.postEdits.updated`.
    public var updatedAcrossCases: [ElementUpdate] {
        switch self {
        case .noChange:
            return []
        case .elementsChanged(let payload):
            return payload.edits.updated
        case .screenChanged(let payload):
            return payload.postEdits?.updated ?? []
        }
    }

    /// New interface for `.screenChanged`, nil otherwise.
    public var newInterface: Interface? {
        if case .screenChanged(let payload) = self {
            return payload.newInterface
        }
        return nil
    }

    // MARK: - Wire Discriminator

    /// On-the-wire `kind` discriminator. Internal because the per-case
    /// switch is the canonical Swift API; the raw string is only meaningful
    /// at the Codable boundary and for logging via `kindRawValue`.
    enum Kind: String, Codable {
        case noChange
        case elementsChanged
        case screenChanged
    }
}

// MARK: - Element Edits

/// The per-edit payload shared between `.elementsChanged` and
/// `.screenChanged.postEdits`. Empty collections mean "no changes of that
/// flavour"; on the wire, empty collections are omitted.
public struct ElementEdits: Sendable {
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

// MARK: - InterfaceDelta Codable

extension InterfaceDelta: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case elementCount
        case transient
        case added, removed, updated, treeInserted, treeRemoved, treeMoved
        case newInterface
        case postEdits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindString = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: kindString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown InterfaceDelta kind: \"\(kindString)\""
            )
        }
        let elementCount = try container.decode(Int.self, forKey: .elementCount)
        let transient = try container.decodeIfPresent([HeistElement].self, forKey: .transient) ?? []

        switch kind {
        case .noChange:
            self = .noChange(NoChange(elementCount: elementCount, transient: transient))

        case .elementsChanged:
            let edits = try ElementEdits(from: decoder)
            self = .elementsChanged(ElementsChanged(
                elementCount: elementCount,
                edits: edits,
                transient: transient
            ))

        case .screenChanged:
            let newInterface = try container.decode(Interface.self, forKey: .newInterface)
            let postEdits = try container.decodeIfPresent(ElementEdits.self, forKey: .postEdits)
            self = .screenChanged(ScreenChanged(
                elementCount: elementCount,
                newInterface: newInterface,
                postEdits: postEdits,
                transient: transient
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noChange(let payload):
            try container.encode(Kind.noChange.rawValue, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }

        case .elementsChanged(let payload):
            try container.encode(Kind.elementsChanged.rawValue, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try payload.edits.encode(to: encoder)
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }

        case .screenChanged(let payload):
            try container.encode(Kind.screenChanged.rawValue, forKey: .kind)
            try container.encode(payload.elementCount, forKey: .elementCount)
            try container.encode(payload.newInterface, forKey: .newInterface)
            if let postEdits = payload.postEdits, !postEdits.isEmpty {
                try container.encode(postEdits, forKey: .postEdits)
            }
            if !payload.transient.isEmpty {
                try container.encode(payload.transient, forKey: .transient)
            }
        }
    }
}
