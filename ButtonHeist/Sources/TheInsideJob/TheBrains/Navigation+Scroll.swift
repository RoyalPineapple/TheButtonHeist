#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore

// MARK: - Scroll Vocabulary
//
// This extension holds only behavior-neutral scroll vocabulary shared by the
// concrete flows:
//
// - `Navigation+PageScroll.swift`: one-page and edge scroll commands.
// - `Navigation+ScrollToVisible.swift`: explicit viewport wrapper over SemanticActionability.
// - `Navigation+ElementSearch.swift`: search by paging, never by semantic actionability.
// - `Navigation+ScrollSettleProof.swift`: the explicit moved/unchanged proof.
// - `Navigation+ScrollContainers.swift`: live container resolution.

extension Navigation {

    enum ScrollTargetDescription: Equatable, CustomStringConvertible {
        case label(String, heistId: HeistId)
        case identifier(String, heistId: HeistId)
        case heistId(HeistId)

        init(_ screenElement: TheStash.ScreenElement) {
            if let label = screenElement.element.label, !label.isEmpty {
                self = .label(label, heistId: screenElement.heistId)
            } else if let identifier = screenElement.element.identifier, !identifier.isEmpty {
                self = .identifier(identifier, heistId: screenElement.heistId)
            } else {
                self = .heistId(screenElement.heistId)
            }
        }

        var description: String {
            switch self {
            case .label(let label, let heistId):
                return "\"\(label)\" (heistId: \(heistId))"
            case .identifier(let identifier, let heistId):
                return "identifier \"\(identifier)\" (heistId: \(heistId))"
            case .heistId(let heistId):
                return "heistId \(heistId)"
            }
        }
    }

    // MARK: - Scroll Axis Detection

    static func scrollableAxis(of container: AccessibilityContainer) -> ScrollAxis {
        guard case .scrollable(let contentSize) = container.type else { return [] }
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

    static func requiredAxis(for direction: ScrollSearchDirection) -> ScrollAxis {
        switch direction {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    // MARK: - Direction Mapping

    static func edgeDirection(for edge: ScrollEdge) -> UIAccessibilityScrollDirection {
        switch edge {
        case .top: return .up
        case .bottom: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    static func uiScrollDirection(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .down
        case .up: return .up
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
