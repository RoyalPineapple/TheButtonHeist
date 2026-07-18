#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// A parsed hierarchy node that smuggles the live accessibility object alongside the value-type
/// representation.
///
/// TheVault builds this by instantiating the parser's generic fold with constructors that retain
/// the source object. It exists only inside the parse pass: the value tree (`AccessibilityHierarchy`)
/// and the path-keyed live-object maps are derived from it, and it is never stored or sent across an
/// actor boundary. Because each node owns its source, there is no value-collision to reconcile — the
/// `TreePath` is assigned structurally during the derivation walk.
extension TheVault {
    indirect enum CaptureNode {

        // MARK: - Nested Types

        case element(AccessibilityElement, traversalIndex: Int, source: NSObject)
        case container(AccessibilityContainer, children: [CaptureNode], source: NSObject)

        // MARK: - Derivations

        /// The pointer-free value tree for this subtree.
        var hierarchy: AccessibilityHierarchy {
            switch self {
            case let .element(element, traversalIndex, _):
                return .element(element, traversalIndex: traversalIndex)
            case let .container(container, children, _):
                return .container(container, children: children.map(\.hierarchy))
            }
        }

        /// Whether this subtree contains an accessibility modal boundary.
        var containsModalBoundary: Bool {
            switch self {
            case .element:
                return false
            case let .container(container, children, _):
                return container.isModalBoundary || children.contains { $0.containsModalBoundary }
            }
        }

        /// The first element in this subtree whose live source is identical to `object`.
        func firstElement(matchingSource object: NSObject) -> AccessibilityElement? {
            switch self {
            case let .element(element, _, source):
                return source === object ? element : nil
            case let .container(_, children, _):
                for child in children {
                    if let match = child.firstElement(matchingSource: object) {
                        return match
                    }
                }
                return nil
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
