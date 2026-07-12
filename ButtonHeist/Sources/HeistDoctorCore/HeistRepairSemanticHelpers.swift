import Foundation
import ThePlans
import TheScore

extension AccessibilityTarget {
    var hasOrdinal: Bool {
        switch self {
        case .predicate(_, let ordinal):
            return ordinal != nil
        case .container, .ref:
            return false
        case .within(_, let target):
            return target.hasOrdinal
        }
    }
}

func stableIdentifier(_ identifier: String?) -> String? {
    guard let identifier = nonEmpty(identifier), isStableIdentifier(identifier) else { return nil }
    return identifier
}

func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

func primaryText(_ element: HeistElement) -> String? {
    nonEmpty(element.label) ?? nonEmpty(element.value) ?? stableIdentifier(element.identifier)
}

func repairFingerprintsAreCompatible(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs else { return true }
    return lhs == rhs
}
