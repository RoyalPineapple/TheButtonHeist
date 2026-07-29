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
        let assertable = element.semantics.assertable
        if let identifier = assertable.identifier, !identifier.isEmpty {
            return "identifier:\(identifier)"
        }
        if let label = assertable.label, !label.isEmpty {
            return "label:\(label)"
        }
        if let value = assertable.value, !value.isEmpty {
            return "value:\(value)"
        }
        return "description:\(element.semantics.spokenDescription)"
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
    /// observation window. Predicate evaluation never consumes this shape.
    init?(
        evidence: Observation.Evidence,
        profile: ProjectionProfile,
        includeScreenInterface: Bool = false
    ) {
        guard let current = evidence.current ?? evidence.baseline else { return nil }
        let folded = DeltaObservationFold(evidence: evidence).result
        let metadata = DeltaProjectionMetadata(
            elementCount: current.interface.projectedElements.count
        )

        if folded.screenChanged {
            self = .screenChanged(DeltaScreenChangedProjection(
                metadata: metadata,
                screen: DeltaScreenProjection(
                    interface: current.interface,
                    profile: profile,
                    includeInterface: includeScreenInterface
                )
            ))
        } else if folded.elementsChanged {
            self = .elementsChanged(DeltaElementsChangedProjection(
                metadata: metadata,
                edits: DeltaEditsProjection(edits: folded.edits, profile: profile)
            ))
        } else if evidence.completeness == .complete {
            self = .noChange(metadata)
        } else {
            return nil
        }
    }
}

private struct DeltaObservationFold {
    let result: Result

    init(evidence: Observation.Evidence) {
        var previous = evidence.baseline
        var accumulator = Accumulator()
        for event in evidence.events {
            switch event {
            case .elementsChanged(let snapshot):
                let edits = previous.map {
                    ElementEdits.between($0.interface, snapshot.interface)
                } ?? ElementEdits(
                    added: snapshot.interface.projectedElements,
                    removed: [],
                    updated: []
                )
                accumulator.elementsChanged = true
                edits.removed.forEach { accumulator.applyDisappearance($0) }
                edits.added.forEach { accumulator.applyAppearance($0) }
                edits.updated.forEach { accumulator.applyUpdate($0) }
                previous = snapshot
            case .screenChanged:
                accumulator.screenChanged = true
            case .notification, .noChange:
                break
            }
        }
        result = accumulator.result
    }

    struct Result {
        let edits: ElementEdits
        let elementsChanged: Bool
        let screenChanged: Bool
    }

    private struct Accumulator {
        var added: [HeistElement] = []
        var removed: [HeistElement] = []
        var updated: [ElementUpdate] = []
        var elementsChanged = false
        var screenChanged = false

        mutating func applyAppearance(_ element: HeistElement) {
            if let index = removed.firstIndex(of: element) {
                removed.remove(at: index)
            } else {
                added.append(element)
            }
        }

        mutating func applyDisappearance(_ element: HeistElement) {
            if let index = added.firstIndex(of: element) {
                added.remove(at: index)
            } else if let index = updated.firstIndex(where: { $0.after == element }) {
                removed.append(updated.remove(at: index).before)
            } else {
                removed.append(element)
            }
        }

        mutating func applyUpdate(_ update: ElementUpdate) {
            if let index = added.firstIndex(of: update.before) {
                added[index] = update.after
            } else if let index = updated.firstIndex(where: { $0.after == update.before }) {
                let before = updated[index].before
                if let composite = ElementEdits.between(before, update.after).updated.first {
                    updated[index] = composite
                } else {
                    updated.remove(at: index)
                }
            } else {
                updated.append(update)
            }
        }

        var result: Result {
            Result(
                edits: ElementEdits(added: added, removed: removed, updated: updated),
                elementsChanged: elementsChanged,
                screenChanged: screenChanged
            )
        }
    }
}
