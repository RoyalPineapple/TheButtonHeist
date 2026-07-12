import ThePlans
import Foundation
import AccessibilitySnapshotModel

// MARK: - Accessibility Trace Change Facts

/// Canonical facts derived from raw accessibility captures.
///
/// Captures remain the durable truth. Change facts are the single compact
/// projection for consumers that need to reason about what happened inside an
/// observation window.
public extension AccessibilityTrace {
    /// Capture-level facts that can be trusted without consulting bounded
    /// render projections or element edit pairing.
    struct InteractionDigest: Codable, Sendable, Equatable {
        public let nodeCountBefore: Int
        public let nodeCountAfter: Int
        public let nodeCountChanged: Bool
        public let elementSetChanged: Bool
        public let screenIdBefore: String?
        public let screenIdAfter: String?
        public let screenIdChanged: Bool
        /// True when direct first-responder identity or software keyboard
        /// visibility changes.
        public let firstResponderChanged: Bool

        public init(
            nodeCountBefore: Int,
            nodeCountAfter: Int,
            elementSetChanged: Bool,
            screenIdBefore: String?,
            screenIdAfter: String?,
            firstResponderChanged: Bool
        ) {
            self.nodeCountBefore = nodeCountBefore
            self.nodeCountAfter = nodeCountAfter
            self.nodeCountChanged = nodeCountBefore != nodeCountAfter
            self.elementSetChanged = elementSetChanged
            self.screenIdBefore = screenIdBefore
            self.screenIdAfter = screenIdAfter
            self.screenIdChanged = screenIdBefore != screenIdAfter
            self.firstResponderChanged = firstResponderChanged
        }
    }

    struct ChangeFactMetadata: Sendable, Equatable {
        public static let empty = ChangeFactMetadata()

        /// Capture edge this fact was derived from. nil only for standalone
        /// projection values that are not stored as action-result truth.
        public let captureEdge: CaptureEdge?
        /// Stable before/after facts derived from raw captures, before any
        /// renderer limits or element edit omission.
        public let interactionDigest: InteractionDigest?
        /// Compact projection of `Capture.transition.transient`.
        public let transient: [HeistElement]
        /// Scoped UIKit/SwiftUI notification evidence attached to this fact.
        public let accessibilityNotifications: [AccessibilityNotificationEvidence]

        public init(
            captureEdge: CaptureEdge? = nil,
            interactionDigest: InteractionDigest? = nil,
            transient: [HeistElement] = [],
            accessibilityNotifications: [AccessibilityNotificationEvidence] = []
        ) {
            self.captureEdge = captureEdge
            self.interactionDigest = interactionDigest
            self.transient = transient
            self.accessibilityNotifications = accessibilityNotifications
        }

        func filteringNotifications(
            _ isIncluded: (AccessibilityNotificationEvidence) -> Bool
        ) -> Self {
            Self(
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications.filter(isIncluded)
            )
        }
    }

    enum InterfaceChangeNodeKind: String, Codable, Sendable, Equatable {
        case element
        case container
    }

    /// A delivered interface node participating in a lifecycle phase.
    ///
    /// This is projected directly from `InterfaceGraphNodeRecord`; it keeps the
    /// delivered `AccessibilityHierarchy` node so containers remain first-class
    /// departure/arrival evidence.
    struct InterfaceChangeNode: Sendable, Equatable {
        public let kind: InterfaceChangeNodeKind
        public let path: TreePath
        public let traversalIndex: Int?
        public let node: AccessibilityHierarchy

        init(record: InterfaceGraphNodeRecord) {
            switch record.kind {
            case .element:
                kind = .element
            case .container:
                kind = .container
            }
            path = record.path
            traversalIndex = record.traversalIndex
            node = record.node
        }
    }

    struct ElementsChangeFact: Sendable, Equatable {
        public let appeared: [InterfaceChangeNode]
        public let disappeared: [InterfaceChangeNode]
        public let updated: [ElementUpdate]
        public let metadata: ChangeFactMetadata

        public init(
            appeared: [InterfaceChangeNode] = [],
            disappeared: [InterfaceChangeNode] = [],
            updated: [ElementUpdate] = [],
            metadata: ChangeFactMetadata = .empty
        ) {
            self.appeared = appeared
            self.disappeared = disappeared
            self.updated = updated
            self.metadata = metadata
        }

        public var hasLifecycleOrUpdateFacts: Bool {
            !appeared.isEmpty || !disappeared.isEmpty || !updated.isEmpty
        }

        public var isNotificationOnly: Bool {
            !hasLifecycleOrUpdateFacts && !metadata.accessibilityNotifications.isEmpty
        }
    }

    struct ScreenChangeFact: Sendable, Equatable {
        public let metadata: ChangeFactMetadata

        public init(
            metadata: ChangeFactMetadata = .empty
        ) {
            self.metadata = metadata
        }
    }

    enum ChangeFactKind: String, Codable, Sendable, Equatable, CaseIterable {
        case elementsChanged
        case screenChanged
    }

    enum ChangeFact: Sendable, Equatable {
        case elementsChanged(ElementsChangeFact)
        case screenChanged(ScreenChangeFact)

        public var kind: ChangeFactKind {
            switch self {
            case .elementsChanged:
                return .elementsChanged
            case .screenChanged:
                return .screenChanged
            }
        }

        public var metadata: ChangeFactMetadata {
            switch self {
            case .elementsChanged(let fact):
                return fact.metadata
            case .screenChanged(let fact):
                return fact.metadata
            }
        }
    }

    /// Flattened facts across adjacent captures.
    ///
    /// When the owning observation window is complete, an empty fact stream
    /// proves no change; no separate no-change fact is emitted.
    var changeFacts: [ChangeFact] {
        zip(captures, captures.dropFirst()).flatMap { before, after in
            ChangeFact.between(before, after)
        }
    }
}

// MARK: - Element Edits

/// Same-screen element edit payload produced by the existing element diff.
///
/// This remains an internal building block for update inference; public change
/// facts expose batched appeared/disappeared/updated facts instead of this
/// grouped shape.
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

// MARK: - Change Fact Codable

extension AccessibilityTrace.ChangeFactMetadata: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case captureEdge
        case interactionDigest
        case transient
        case accessibilityNotifications
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ChangeFactMetadata")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            captureEdge: try container.decodeIfPresent(AccessibilityTrace.CaptureEdge.self, forKey: .captureEdge),
            interactionDigest: try container.decodeIfPresent(
                AccessibilityTrace.InteractionDigest.self,
                forKey: .interactionDigest
            ),
            transient: try container.decodeIfPresent([HeistElement].self, forKey: .transient) ?? [],
            accessibilityNotifications: try container.decodeIfPresent(
                [AccessibilityNotificationEvidence].self,
                forKey: .accessibilityNotifications
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(captureEdge, forKey: .captureEdge)
        try container.encodeIfPresent(interactionDigest, forKey: .interactionDigest)
        if !transient.isEmpty {
            try container.encode(transient, forKey: .transient)
        }
        if !accessibilityNotifications.isEmpty {
            try container.encode(accessibilityNotifications, forKey: .accessibilityNotifications)
        }
    }
}

extension AccessibilityTrace.InterfaceChangeNode: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case path
        case traversalIndex
        case node
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "InterfaceChangeNode")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(AccessibilityTrace.InterfaceChangeNodeKind.self, forKey: .kind)
        self.path = try container.decode(TreePath.self, forKey: .path)
        self.traversalIndex = try container.decodeIfPresent(Int.self, forKey: .traversalIndex)
        self.node = try container.decode(AccessibilityHierarchy.self, forKey: .node)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(traversalIndex, forKey: .traversalIndex)
        try container.encode(node, forKey: .node)
    }
}

extension AccessibilityTrace.ElementsChangeFact: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case appeared
        case disappeared
        case updated
        case metadata
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ElementsChangeFact")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appeared: try container.decodeIfPresent(
                [AccessibilityTrace.InterfaceChangeNode].self,
                forKey: .appeared
            ) ?? [],
            disappeared: try container.decodeIfPresent(
                [AccessibilityTrace.InterfaceChangeNode].self,
                forKey: .disappeared
            ) ?? [],
            updated: try container.decodeIfPresent([ElementUpdate].self, forKey: .updated) ?? [],
            metadata: try container.decode(AccessibilityTrace.ChangeFactMetadata.self, forKey: .metadata)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !appeared.isEmpty { try container.encode(appeared, forKey: .appeared) }
        if !disappeared.isEmpty { try container.encode(disappeared, forKey: .disappeared) }
        if !updated.isEmpty { try container.encode(updated, forKey: .updated) }
        try container.encode(metadata, forKey: .metadata)
    }
}

extension AccessibilityTrace.ScreenChangeFact: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case metadata
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ScreenChangeFact")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metadata: try container.decode(AccessibilityTrace.ChangeFactMetadata.self, forKey: .metadata)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata, forKey: .metadata)
    }
}

extension AccessibilityTrace.ChangeFact: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case metadata
        case appeared
        case disappeared
        case updated
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownChangeFactKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AccessibilityTrace.ChangeFactKind.self, forKey: .kind)
        let metadata = try container.decode(AccessibilityTrace.ChangeFactMetadata.self, forKey: .metadata)

        switch kind {
        case .elementsChanged:
            self = .elementsChanged(AccessibilityTrace.ElementsChangeFact(
                appeared: try container.decodeIfPresent(
                    [AccessibilityTrace.InterfaceChangeNode].self,
                    forKey: .appeared
                ) ?? [],
                disappeared: try container.decodeIfPresent(
                    [AccessibilityTrace.InterfaceChangeNode].self,
                    forKey: .disappeared
                ) ?? [],
                updated: try container.decodeIfPresent([ElementUpdate].self, forKey: .updated) ?? [],
                metadata: metadata
            ))
        case .screenChanged:
            try Self.rejectIfPresent(.appeared, in: container, kind: kind)
            try Self.rejectIfPresent(.disappeared, in: container, kind: kind)
            try Self.rejectIfPresent(.updated, in: container, kind: kind)
            self = .screenChanged(AccessibilityTrace.ScreenChangeFact(metadata: metadata))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(metadata, forKey: .metadata)

        switch self {
        case .elementsChanged(let payload):
            if !payload.appeared.isEmpty { try container.encode(payload.appeared, forKey: .appeared) }
            if !payload.disappeared.isEmpty { try container.encode(payload.disappeared, forKey: .disappeared) }
            if !payload.updated.isEmpty { try container.encode(payload.updated, forKey: .updated) }
        case .screenChanged:
            break
        }
    }

    private static func rejectUnknownChangeFactKeys(_ decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "accessibility change fact")
    }

    private static func rejectIfPresent(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        kind: AccessibilityTrace.ChangeFactKind
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(kind.rawValue) accessibility change fact must not include \(key.stringValue)"
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
            nodeCountBefore: before.interface.graph.nodesInPathOrder.count,
            nodeCountAfter: after.interface.graph.nodesInPathOrder.count,
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
