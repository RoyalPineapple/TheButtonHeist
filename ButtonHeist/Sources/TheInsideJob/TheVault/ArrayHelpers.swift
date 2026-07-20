#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

// MARK: - Array Helpers

// MARK: - Shape Helper

extension AccessibilityShape {
    var frame: CGRect {
        ScreenFrameEvidence(self).rect?.cgRect ?? .null
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
