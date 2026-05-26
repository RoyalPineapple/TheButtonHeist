#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotParser
import CoreGraphics

extension AccessibilityElement {
    var bhFrame: CGRect {
        shape.frame
    }

    var bhResolvedActivationPoint: CGPoint {
        let frame = bhFrame
        if usesDefaultActivationPoint {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return activationPoint.cgPoint
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
