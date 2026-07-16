#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    enum ScrollTargetDescription: Equatable, CustomStringConvertible {
        case label(String)
        case identifier(String)
        case element

        init(_ treeElement: InterfaceTree.Element) {
            if let label = treeElement.element.label, !label.isEmpty {
                self = .label(label)
            } else if let identifier = treeElement.element.identifier, !identifier.isEmpty {
                self = .identifier(identifier)
            } else {
                self = .element
            }
        }

        var description: String {
            switch self {
            case .label(let label):
                return "\"\(label)\""
            case .identifier(let identifier):
                return "identifier \"\(identifier)\""
            case .element:
                return "semantic element"
            }
        }
    }

    static func scrollableAxis(of container: AccessibilityContainer) -> ScrollAxis {
        guard let contentSize = container.scrollableContentSize else { return [] }
        return scrollableAxis(contentSize: contentSize.cgSize, frame: container.frame.cgRect)
    }

    static func scrollableAxis(contentSize: CGSize, frame: CGRect) -> ScrollAxis {
        var axis: ScrollAxis = []
        if contentSize.width > frame.width + 1 { axis.insert(.horizontal) }
        if contentSize.height > frame.height + 1 { axis.insert(.vertical) }
        return axis
    }

    static func requiredAxis(for direction: ScrollDirection) -> ScrollAxis {
        switch direction {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    static func requiredAxis(for edge: ScrollEdge) -> ScrollAxis {
        switch edge {
        case .top, .bottom: return .vertical
        case .left, .right: return .horizontal
        }
    }

    static func edgeDirection(for edge: ScrollEdge) -> UIAccessibilityScrollDirection {
        switch edge {
        case .top: return .up
        case .bottom: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    static func uiScrollDirection(for direction: ScrollDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
