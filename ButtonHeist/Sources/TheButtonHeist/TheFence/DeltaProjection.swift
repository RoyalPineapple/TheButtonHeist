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

struct ScreenshotProjection: Sendable {
    let width: Double
    let height: Double
    let pngData: String?
    let interface: InterfaceProjection?
    let path: String?

    init(
        path: String?,
        payload: ScreenPayload,
        includePNGData: Bool,
        includeInterface: Bool,
        profile: ProjectionProfile
    ) {
        width = payload.width
        height = payload.height
        pngData = includePNGData ? payload.pngData : nil
        interface = includeInterface
            ? payload.interface.map { InterfaceProjection(interface: $0, profile: profile) }
            : nil
        self.path = path
    }
}

enum DeltaProjectionKind: String, Sendable {
    case noChange
    case elementsChanged
    case screenChanged
}

struct DeltaProjection: Sendable {
    let kind: DeltaProjectionKind
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let interactionDigest: AccessibilityTrace.InteractionDigest?
    let transient: ElementProjectionBucket
    let edits: DeltaEditsProjection?
    let screen: DeltaScreenProjection?

    init(delta: AccessibilityTrace.Delta, profile: ProjectionProfile, includeScreenInterface: Bool = false) {
        switch delta {
        case .noChange(let payload):
            kind = .noChange
            elementCount = payload.elementCount
            captureEdge = payload.captureEdge
            interactionDigest = payload.interactionDigest
            transient = ElementProjectionBucket(
                elements: payload.transient,
                limit: profile.limits.deltaElementsPerBucket
            )
            edits = nil
            screen = nil
        case .elementsChanged(let payload):
            kind = .elementsChanged
            elementCount = payload.elementCount
            captureEdge = payload.captureEdge
            interactionDigest = payload.interactionDigest
            transient = ElementProjectionBucket(
                elements: payload.transient,
                limit: profile.limits.deltaElementsPerBucket
            )
            let editProjection = DeltaEditsProjection(edits: payload.edits, profile: profile)
            edits = editProjection.isEmpty ? nil : editProjection
            screen = nil
        case .screenChanged(let payload):
            kind = .screenChanged
            elementCount = payload.elementCount
            captureEdge = payload.captureEdge
            interactionDigest = payload.interactionDigest
            transient = ElementProjectionBucket(
                elements: payload.transient,
                limit: profile.limits.deltaElementsPerBucket
            )
            edits = nil
            screen = DeltaScreenProjection(
                interface: payload.newInterface,
                profile: profile,
                includeInterface: includeScreenInterface
            )
        }
    }
}
