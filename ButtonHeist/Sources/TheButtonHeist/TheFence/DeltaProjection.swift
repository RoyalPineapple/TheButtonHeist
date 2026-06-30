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

    init(
        elementCount: Int,
        captureEdge: AccessibilityTrace.CaptureEdge?,
        interactionDigest: AccessibilityTrace.InteractionDigest?,
        transient: [HeistElement],
        profile: ProjectionProfile
    ) {
        self.elementCount = elementCount
        self.captureEdge = captureEdge
        self.interactionDigest = interactionDigest
        self.transient = ElementProjectionBucket(
            elements: transient,
            limit: profile.limits.deltaElementsPerBucket
        )
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

    init(delta: AccessibilityTrace.Delta, profile: ProjectionProfile, includeScreenInterface: Bool = false) {
        switch delta {
        case .noChange(let payload):
            self = .noChange(DeltaProjectionMetadata(
                elementCount: payload.elementCount,
                captureEdge: payload.captureEdge,
                interactionDigest: payload.interactionDigest,
                transient: payload.transient,
                profile: profile
            ))
        case .elementsChanged(let payload):
            self = .elementsChanged(DeltaElementsChangedProjection(
                metadata: DeltaProjectionMetadata(
                    elementCount: payload.elementCount,
                    captureEdge: payload.captureEdge,
                    interactionDigest: payload.interactionDigest,
                    transient: payload.transient,
                    profile: profile
                ),
                edits: DeltaEditsProjection(edits: payload.edits, profile: profile)
            ))
        case .screenChanged(let payload):
            self = .screenChanged(DeltaScreenChangedProjection(
                metadata: DeltaProjectionMetadata(
                    elementCount: payload.elementCount,
                    captureEdge: payload.captureEdge,
                    interactionDigest: payload.interactionDigest,
                    transient: payload.transient,
                    profile: profile
                ),
                screen: DeltaScreenProjection(
                    interface: payload.newInterface,
                    profile: profile,
                    includeInterface: includeScreenInterface
                )
            ))
        }
    }
}
