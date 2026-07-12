import TheScore

struct ElementProjectionBucket: Sendable {
    let elements: [HeistElement]
    let omittedCount: Int?
    let omittedKeys: [String]?

    init(elements: [HeistElement], limit: Int) {
        let visible = Array(elements.prefix(max(0, limit)))
        self.elements = visible
        let omittedElements = Array(elements.dropFirst(visible.count))
        omittedCount = omittedElements.isEmpty ? nil : omittedElements.count
        omittedKeys = omittedElements.isEmpty
            ? nil
            : omittedElements.map(Self.omissionKey(for:))
    }

    var isEmpty: Bool {
        elements.isEmpty
    }

    static func omissionKey(for element: HeistElement) -> String {
        if let identifier = element.identifier, !identifier.isEmpty {
            return "identifier:\(identifier)"
        }
        if let label = element.label, !label.isEmpty {
            return "label:\(label)"
        }
        if let value = element.value, !value.isEmpty {
            return "value:\(value)"
        }
        return "description:\(element.description)"
    }
}

struct ElementUpdateProjectionBucket: Sendable {
    let updates: [ElementUpdate]
    let omittedCount: Int?
    let omittedKeys: [String]?

    init(updates: [ElementUpdate], limit: Int) {
        let visible = Array(updates.prefix(max(0, limit)))
        self.updates = visible
        let omittedUpdates = Array(updates.dropFirst(visible.count))
        omittedCount = omittedUpdates.isEmpty ? nil : omittedUpdates.count
        omittedKeys = omittedUpdates.isEmpty
            ? nil
            : omittedUpdates.map { ElementProjectionBucket.omissionKey(for: $0.after) }
    }

    var isEmpty: Bool {
        updates.isEmpty
    }
}

struct DeltaEditsProjection: Sendable {
    let added: ElementProjectionBucket
    let removed: ElementProjectionBucket
    let updated: ElementUpdateProjectionBucket

    init(edits: ElementEdits, profile: ProjectionProfile) {
        let limit = profile.limits.deltaElementsPerBucket
        added = ElementProjectionBucket(elements: edits.added, limit: limit)
        removed = ElementProjectionBucket(elements: edits.removed, limit: limit)
        let meaningfulUpdates = edits.updated.compactMap { update -> ElementUpdate? in
            let changes = update.changes.filter { !$0.property.isGeometry }
            guard !changes.isEmpty else { return nil }
            return ElementUpdate(before: update.before, after: update.after, changes: changes)
        }
        updated = ElementUpdateProjectionBucket(updates: meaningfulUpdates, limit: limit)
    }

    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

struct DeltaScreenProjection: Sendable {
    let screenDescription: String
    let screenId: String?
    let elementCount: Int
    let elements: [HeistElement]
    let omittedElementCount: Int?
    let interface: InterfaceProjection?

    init(interface: Interface, profile: ProjectionProfile, includeInterface: Bool) {
        let projectedElements = interface.projectedElements
        let visible = Array(projectedElements.prefix(max(0, profile.limits.screenPreviewElements)))
        screenDescription = InterfaceSummary.screenDescription(for: interface)
        screenId = InterfaceSummary.screenId(for: interface)
        elementCount = projectedElements.count
        elements = visible
        let omitted = projectedElements.count - visible.count
        omittedElementCount = omitted > 0 ? omitted : nil
        self.interface = includeInterface
            ? InterfaceProjection(interface: interface, profile: profile)
            : nil
    }
}

enum ScreenshotProjectionStorage: Sendable {
    case artifact(path: String)
    case inlinePNG(String)
}

struct ScreenshotProjection: Sendable {
    let width: Double
    let height: Double
    let storage: ScreenshotProjectionStorage
    let interface: InterfaceProjection?

    init(
        storage: ScreenshotProjectionStorage,
        payload: ScreenPayload,
        includeInterface: Bool,
        profile: ProjectionProfile
    ) {
        width = payload.width
        height = payload.height
        self.storage = storage
        interface = includeInterface
            ? payload.interface.map { InterfaceProjection(interface: $0, profile: profile) }
            : nil
    }
}

enum DeltaProjectionKind: String, Sendable {
    case noChange
    case elementsChanged
    case screenChanged
}

struct DeltaProjectionMetadata: Sendable {
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let interactionDigest: AccessibilityTrace.InteractionDigest?
    let transient: ElementProjectionBucket
    let accessibilityNotifications: [AccessibilityNotificationEvidence]

    init(
        elementCount: Int,
        captureEdge: AccessibilityTrace.CaptureEdge?,
        interactionDigest: AccessibilityTrace.InteractionDigest?,
        transient: [HeistElement],
        accessibilityNotifications: [AccessibilityNotificationEvidence],
        profile: ProjectionProfile
    ) {
        self.elementCount = elementCount
        self.captureEdge = captureEdge
        self.interactionDigest = interactionDigest
        self.transient = ElementProjectionBucket(
            elements: transient,
            limit: profile.limits.deltaElementsPerBucket
        )
        self.accessibilityNotifications = accessibilityNotifications
    }
}

struct DeltaElementsChangedProjection: Sendable {
    let metadata: DeltaProjectionMetadata
    let edits: DeltaEditsProjection
}

struct DeltaScreenChangedProjection: Sendable {
    let metadata: DeltaProjectionMetadata
    let screen: DeltaScreenProjection
}

enum DeltaProjection: Sendable {
    case noChange(DeltaProjectionMetadata)
    case elementsChanged(DeltaElementsChangedProjection)
    case screenChanged(DeltaScreenChangedProjection)

    var kind: DeltaProjectionKind {
        switch self {
        case .noChange:
            return .noChange
        case .elementsChanged:
            return .elementsChanged
        case .screenChanged:
            return .screenChanged
        }
    }

    /// Public endpoint summary derived exclusively by folding the canonical
    /// temporal fact stream. Predicate evaluation never consumes this shape.
    init?(
        trace: AccessibilityTrace,
        isComplete: Bool,
        profile: ProjectionProfile,
        includeScreenInterface: Bool = false
    ) {
        guard let finalCapture = trace.captures.last else { return nil }
        let facts = trace.changeFacts
        guard !facts.isEmpty || (isComplete && trace.captures.count >= 2) else { return nil }

        let folded = DeltaFactFold(trace: trace).folding(facts)
        let metadata = DeltaProjectionMetadata(
            elementCount: finalCapture.interface.projectedElements.count,
            captureEdge: folded.captureEdge,
            interactionDigest: folded.interactionDigest,
            transient: folded.transient,
            accessibilityNotifications: folded.accessibilityNotifications,
            profile: profile
        )

        if folded.screenChanged {
            self = .screenChanged(DeltaScreenChangedProjection(
                metadata: metadata,
                screen: DeltaScreenProjection(
                    interface: finalCapture.interface,
                    profile: profile,
                    includeInterface: includeScreenInterface
                )
            ))
        } else if !facts.isEmpty {
            self = .elementsChanged(DeltaElementsChangedProjection(
                metadata: metadata,
                edits: DeltaEditsProjection(edits: folded.edits, profile: profile)
            ))
        } else {
            self = .noChange(metadata)
        }
    }
}

private struct DeltaFactFold {
    private let trace: AccessibilityTrace

    init(trace: AccessibilityTrace) {
        self.trace = trace
    }

    func folding(_ facts: [AccessibilityTrace.ChangeFact]) -> DeltaFoldResult {
        facts.reduce(into: DeltaFoldAccumulator()) { accumulator, fact in
            accumulator.captureEdges.append(contentsOf: fact.metadata.captureEdge.map { [$0] } ?? [])
            accumulator.interactionDigests.append(contentsOf: fact.metadata.interactionDigest.map { [$0] } ?? [])
            accumulator.metadataTransient.append(contentsOf: fact.metadata.transient)
            accumulator.accessibilityNotifications.append(contentsOf: fact.metadata.accessibilityNotifications)

            switch fact {
            case .screenChanged:
                accumulator.screenChanged = true
            case .elementsChanged(let elements):
                elements.disappeared.compactMap {
                    projectedElement(for: $0, edge: elements.metadata.captureEdge, useAfterCapture: false)
                }.forEach { accumulator.applyDisappearance($0) }
                elements.appeared.compactMap {
                    projectedElement(for: $0, edge: elements.metadata.captureEdge, useAfterCapture: true)
                }.forEach { accumulator.applyAppearance($0) }
                elements.updated.forEach { accumulator.applyUpdate($0) }
            }
        }.result
    }

    private func projectedElement(
        for node: AccessibilityTrace.InterfaceChangeNode,
        edge: AccessibilityTrace.CaptureEdge?,
        useAfterCapture: Bool
    ) -> HeistElement? {
        guard node.kind == .element,
              let edge,
              let capture = trace.capture(ref: useAfterCapture ? edge.after : edge.before)
        else { return nil }
        return capture.interface.graph.elementsInTraversalOrder
            .first { $0.path == node.path }?
            .projectedElement
    }
}

private struct DeltaFoldAccumulator {
    var added: [HeistElement] = []
    var removed: [HeistElement] = []
    var updated: [ElementUpdate] = []
    var metadataTransient: [HeistElement] = []
    var lifecycleTransient: [HeistElement] = []
    var captureEdges: [AccessibilityTrace.CaptureEdge] = []
    var interactionDigests: [AccessibilityTrace.InteractionDigest] = []
    var accessibilityNotifications: [AccessibilityNotificationEvidence] = []
    var screenChanged = false

    mutating func applyAppearance(_ element: HeistElement) {
        if let index = removed.firstIndex(of: element) {
            removed.remove(at: index)
            appendTransient(element)
        } else {
            added.append(element)
        }
    }

    mutating func applyDisappearance(_ element: HeistElement) {
        if let index = added.firstIndex(of: element) {
            added.remove(at: index)
            appendTransient(element)
        } else if let index = updated.firstIndex(where: { $0.after == element }) {
            removed.append(updated.remove(at: index).before)
        } else {
            removed.append(element)
        }
    }

    mutating func applyUpdate(_ update: ElementUpdate) {
        if let index = added.firstIndex(of: update.before) {
            added[index] = update.after
            return
        }
        if let index = updated.firstIndex(where: { $0.after == update.before }) {
            let before = updated[index].before
            if let composite = ElementEdits.between(before, update.after).updated.first {
                updated[index] = composite
            } else {
                updated.remove(at: index)
                appendTransient(update.after)
            }
            return
        }
        updated.append(update)
    }

    var result: DeltaFoldResult {
        let transientElements = metadataTransient + lifecycleTransient
        return DeltaFoldResult(
            edits: ElementEdits(added: added, removed: removed, updated: updated),
            transient: transientElements.uniqued(),
            captureEdge: captureEdges.first.map { first in
                AccessibilityTrace.CaptureEdge(
                    before: first.before,
                    after: captureEdges.last?.after ?? first.after
                )
            },
            interactionDigest: interactionDigests.first.map { first in
                let last = interactionDigests.last ?? first
                return AccessibilityTrace.InteractionDigest(
                    nodeCountBefore: first.nodeCountBefore,
                    nodeCountAfter: last.nodeCountAfter,
                    elementSetChanged: interactionDigests.contains { $0.elementSetChanged },
                    screenIdBefore: first.screenIdBefore,
                    screenIdAfter: last.screenIdAfter,
                    firstResponderChanged: interactionDigests.contains { $0.firstResponderChanged }
                )
            },
            accessibilityNotifications: accessibilityNotifications.uniqued().sorted {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.timestamp < $1.timestamp
            },
            screenChanged: screenChanged
        )
    }

    private mutating func appendTransient(_ element: HeistElement) {
        lifecycleTransient.append(element)
    }
}

private struct DeltaFoldResult {
    let edits: ElementEdits
    let transient: [HeistElement]
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let interactionDigest: AccessibilityTrace.InteractionDigest?
    let accessibilityNotifications: [AccessibilityNotificationEvidence]
    let screenChanged: Bool
}
