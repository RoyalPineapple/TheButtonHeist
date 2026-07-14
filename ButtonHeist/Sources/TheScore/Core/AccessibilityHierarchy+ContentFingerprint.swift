import AccessibilitySnapshotModel

package func safeInt<T: BinaryFloatingPoint>(_ value: T) -> Int {
    guard value.isFinite else { return 0 }
    if value >= T(Int.max) { return Int.max }
    if value <= T(Int.min) { return Int.min }
    return Int(value)
}

package extension AccessibilityElement {
    /// Identity hash based on content only: no traversal index.
    func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(label)
        hasher.combine(identifier)
        hasher.combine(value)
        hasher.combine(traits)
        switch shape {
        case let .frame(rect):
            hasher.combine(safeInt(rect.origin.x))
            hasher.combine(safeInt(rect.origin.y))
            hasher.combine(safeInt(rect.size.width))
            hasher.combine(safeInt(rect.size.height))
        case let .path(path):
            let bounds = path.safeFingerprintBounds
            hasher.combine(safeInt(bounds.origin.x))
            hasher.combine(safeInt(bounds.origin.y))
            hasher.combine(safeInt(bounds.size.width))
            hasher.combine(safeInt(bounds.size.height))
        }
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

private extension Array where Element == AccessibilityPathElement {
    var safeFingerprintBounds: AccessibilityRect {
        let points = flatMap(\.fingerprintPoints).filter(\.isFinite)
        guard let first = points.first else { return .zero }
        let bounds = points.dropFirst().reduce(
            (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        ) { bounds, point in
            (
                minX: Swift.min(bounds.minX, point.x),
                minY: Swift.min(bounds.minY, point.y),
                maxX: Swift.max(bounds.maxX, point.x),
                maxY: Swift.max(bounds.maxY, point.y)
            )
        }
        return AccessibilityRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.maxX - bounds.minX,
            height: bounds.maxY - bounds.minY
        )
    }
}

private extension AccessibilityPathElement {
    var fingerprintPoints: [AccessibilityPoint] {
        switch self {
        case .move(let point), .line(let point):
            return [point]
        case .quadCurve(let point, let control):
            return [point, control]
        case .curve(let point, let control1, let control2):
            return [point, control1, control2]
        case .closeSubpath:
            return []
        }
    }
}
