#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotParser

extension AccessibilityElement {
    func matchesCapturedFacts(of other: AccessibilityElement) -> Bool {
        description == other.description
            && label == other.label
            && value == other.value
            && traits == other.traits
            && identifier == other.identifier
            && hint == other.hint
            && userInputLabels == other.userInputLabels
            && shape.matchesCapturedGeometry(of: other.shape)
            && activationPoint.matchesCapturedGeometry(of: other.activationPoint)
            && usesDefaultActivationPoint == other.usesDefaultActivationPoint
            && customActions == other.customActions
            && customContent == other.customContent
            && customRotors.matchesCapturedFacts(of: other.customRotors)
            && accessibilityLanguage == other.accessibilityLanguage
            && respondsToUserInteraction == other.respondsToUserInteraction
            && visibility == other.visibility
    }
}

private extension Array where Element == AccessibilityElement.CustomRotor {
    func matchesCapturedFacts(of other: Self) -> Bool {
        count == other.count && zip(self, other).allSatisfy { lhs, rhs in
            lhs.matchesCapturedFacts(of: rhs)
        }
    }
}

private extension AccessibilityElement.CustomRotor {
    func matchesCapturedFacts(of other: Self) -> Bool {
        name == other.name
            && limit == other.limit
            && resultMarkers.count == other.resultMarkers.count
            && zip(resultMarkers, other.resultMarkers).allSatisfy { lhs, rhs in
                lhs.matchesCapturedFacts(of: rhs)
            }
    }
}

private extension AccessibilityElement.CustomRotor.ResultMarker {
    func matchesCapturedFacts(of other: Self) -> Bool {
        guard elementDescription == other.elementDescription,
              rangeDescription == other.rangeDescription else { return false }
        switch (shape, other.shape) {
        case (nil, nil):
            return true
        case let (.some(lhs), .some(rhs)):
            return lhs.matchesCapturedGeometry(of: rhs)
        case (.some, nil), (nil, .some):
            return false
        }
    }
}

private extension AccessibilityShape {
    func matchesCapturedGeometry(of other: Self) -> Bool {
        switch (self, other) {
        case let (.frame(lhs), .frame(rhs)):
            return lhs.matchesCapturedGeometry(of: rhs)
        case let (.path(lhs), .path(rhs)):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { lhs, rhs in
                lhs.matchesCapturedGeometry(of: rhs)
            }
        case (.frame, .path), (.path, .frame):
            return false
        }
    }
}

private extension AccessibilityPathElement {
    func matchesCapturedGeometry(of other: Self) -> Bool {
        switch (self, other) {
        case let (.move(lhs), .move(rhs)),
             let (.line(lhs), .line(rhs)):
            return lhs.matchesCapturedGeometry(of: rhs)
        case let (.quadCurve(lhs, lhsControl), .quadCurve(rhs, rhsControl)):
            return lhs.matchesCapturedGeometry(of: rhs)
                && lhsControl.matchesCapturedGeometry(of: rhsControl)
        case let (.curve(lhs, lhsControl1, lhsControl2), .curve(rhs, rhsControl1, rhsControl2)):
            return lhs.matchesCapturedGeometry(of: rhs)
                && lhsControl1.matchesCapturedGeometry(of: rhsControl1)
                && lhsControl2.matchesCapturedGeometry(of: rhsControl2)
        case (.closeSubpath, .closeSubpath):
            return true
        default:
            return false
        }
    }
}

private extension AccessibilityRect {
    func matchesCapturedGeometry(of other: Self) -> Bool {
        origin.matchesCapturedGeometry(of: other.origin)
            && size.matchesCapturedGeometry(of: other.size)
    }
}

private extension AccessibilityPoint {
    func matchesCapturedGeometry(of other: Self) -> Bool {
        x.matchesCapturedGeometry(of: other.x)
            && y.matchesCapturedGeometry(of: other.y)
    }
}

private extension AccessibilitySize {
    func matchesCapturedGeometry(of other: Self) -> Bool {
        width.matchesCapturedGeometry(of: other.width)
            && height.matchesCapturedGeometry(of: other.height)
    }
}

private extension Double {
    func matchesCapturedGeometry(of other: Self) -> Bool {
        self == other || (isNaN && other.isNaN)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
