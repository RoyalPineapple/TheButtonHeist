#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotModel
import TheScore

extension UIAccessibilityTraits {
    static func fromNames(_ names: [String]) -> UIAccessibilityTraits {
        UIAccessibilityTraits(rawValue: AccessibilityTraits.fromNames(names).rawValue)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
