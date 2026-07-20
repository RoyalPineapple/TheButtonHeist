import AccessibilitySnapshotModel

package extension AccessibilityElement {
    /// Identity hash based on content only: no traversal index.
    func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(label)
        hasher.combine(identifier)
        hasher.combine(value)
        hasher.combine(traits)
        hasher.combine(GeometryFingerprint(ScreenFrameEvidence(shape)))
        return hasher.finalize()
    }

    /// Convenience fingerprint using window-space geometry.
    var contentFingerprint: Int {
        fingerprint()
    }
}

package extension AccessibilityHierarchy {
    /// Content-only fingerprint for a hierarchy node. Ignores traversal indices.
    var contentFingerprint: Int {
        folded(
            onElement: { element, _ in hierarchyContentFingerprint(for: element) },
            onContainer: { container, childFingerprints in
                hierarchyContentFingerprint(
                    for: container,
                    childFingerprints: childFingerprints
                )
            }
        )
    }
}

package func hierarchyContentFingerprint(for element: AccessibilityElement) -> Int {
    var hasher = Hasher()
    hasher.combine(0)
    hasher.combine(element.contentFingerprint)
    return hasher.finalize()
}

package func hierarchyContentFingerprint(
    for container: AccessibilityContainer,
    childFingerprints: [Int]
) -> Int {
    var hasher = Hasher()
    hasher.combine(1)
    hasher.combine(container)
    for childFingerprint in childFingerprints {
        hasher.combine(childFingerprint)
    }
    return hasher.finalize()
}

package func contentFingerprints(
    for elements: [AccessibilityElement]
) -> [Int] {
    elements.map { $0.fingerprint() }
}

private enum GeometryFingerprint: Hashable {
    case available(x: Component, y: Component, width: Component, height: Component)
    case unavailable

    init(_ evidence: ScreenFrameEvidence) {
        guard let rect = evidence.rect else {
            self = .unavailable
            return
        }
        self = .available(
            x: Component(rect.x.value),
            y: Component(rect.y.value),
            width: Component(rect.width.value),
            height: Component(rect.height.value)
        )
    }

    enum Component: Hashable {
        case belowRange
        case value(Int)
        case aboveRange

        init(_ value: Double) {
            if value >= Double(Int.max) {
                self = .aboveRange
            } else if value <= Double(Int.min) {
                self = .belowRange
            } else {
                self = .value(Int(value))
            }
        }
    }
}
