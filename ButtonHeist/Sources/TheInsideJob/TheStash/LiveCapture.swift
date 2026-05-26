#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Live Capture

/// Latest parsed interface and disposable UIKit evidence.
///
/// `LiveCapture` is viewport-shaped. It may contain weak UIKit refs and live
/// indices, but it is not semantic memory and is never unioned across
/// exploration pages.
struct LiveCapture: Equatable {
    let hierarchy: [AccessibilityHierarchy]
    let containerStableIds: [AccessibilityContainer: HeistContainer]
    let containerStableIdsByPath: [TreePath: HeistContainer]
    let heistIdByElement: [AccessibilityElement: HeistId]
    let heistIdByElementPath: [TreePath: HeistId]
    let elementRefs: [HeistId: ElementRef]
    let containerRefsByPath: [TreePath: ContainerRef]
    let containerContentFramesByPath: [TreePath: CGRect]
    let firstResponderHeistId: HeistId?
    let scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]
    private let scrollableViewsByStableId: [HeistContainer: ScrollableViewRef]

    init(
        hierarchy: [AccessibilityHierarchy],
        containerStableIds: [AccessibilityContainer: HeistContainer],
        containerStableIdsByPath: [TreePath: HeistContainer] = [:],
        heistIdByElement: [AccessibilityElement: HeistId],
        heistIdByElementPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:],
        scrollableViewsByStableId: [HeistContainer: ScrollableViewRef]? = nil
    ) {
        self.hierarchy = hierarchy
        self.containerStableIds = containerStableIds
        self.containerStableIdsByPath = containerStableIdsByPath
        self.heistIdByElement = heistIdByElement
        self.heistIdByElementPath = heistIdByElementPath
        self.elementRefs = elementRefs
        self.containerRefsByPath = containerRefsByPath
        self.containerContentFramesByPath = containerContentFramesByPath
        self.firstResponderHeistId = firstResponderHeistId
        self.scrollableContainerViews = scrollableContainerViews
        self.scrollableContainerViewsByPath = scrollableContainerViewsByPath
        self.scrollableViewsByStableId = scrollableViewsByStableId ?? Self.scrollableViewsByStableId(
            hierarchy: hierarchy,
            containerStableIds: containerStableIds,
            containerStableIdsByPath: containerStableIdsByPath,
            scrollableContainerViews: scrollableContainerViews,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
    }

    static let empty = LiveCapture(
        hierarchy: [],
        containerStableIds: [:],
        heistIdByElement: [:],
        heistIdByElementPath: [:],
        elementRefs: [:],
        containerRefsByPath: [:],
        containerContentFramesByPath: [:],
        firstResponderHeistId: nil,
        scrollableContainerViews: [:]
    )

    var heistIds: Set<HeistId> {
        Set(heistIdByElement.values).union(heistIdByElementPath.values)
    }

    func contains(heistId: HeistId) -> Bool {
        heistIdByElement.values.contains(heistId)
    }

    func heistId(for element: AccessibilityElement) -> HeistId? {
        heistIdByElement[element]
    }

    func heistId(forPath path: TreePath) -> HeistId? {
        heistIdByElementPath[path]
    }

    func object(for heistId: HeistId) -> NSObject? {
        elementRefs[heistId]?.object
    }

    func scrollView(for heistId: HeistId) -> UIScrollView? {
        elementRefs[heistId]?.scrollView
    }

    func scrollView(forContainer stableId: HeistContainer) -> UIScrollView? {
        scrollableViewsByStableId[stableId]?.view as? UIScrollView
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        containerRefsByPath[path]?.object
    }

    func containerContentFrame(forPath path: TreePath) -> CGRect? {
        containerContentFramesByPath[path]
    }

    func scrollView(for element: SemanticScreen.Element) -> UIScrollView? {
        scrollView(for: element.heistId)
            ?? element.scrollContentLocation.map { $0.scrollContainer }.flatMap(scrollView(forContainer:))
    }

    // MARK: - Refs

    // `@unchecked Sendable` rationale: UIView is non-Sendable but the wrapper
    // is only touched on `@MainActor`.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ScrollableViewRef: @unchecked Sendable, Equatable {
        weak var view: UIView?

        static func == (lhs: ScrollableViewRef, rhs: ScrollableViewRef) -> Bool {
            switch (lhs.view, rhs.view) {
            case (nil, nil):
                return true
            case let (left?, right?):
                return left === right
            default:
                return false
            }
        }
    }

    // `@unchecked Sendable` rationale: weak UIKit refs are only observed
    // behind TheStash on the main actor.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ElementRef: @unchecked Sendable, Equatable {
        /// Live UIKit object for action dispatch. Weak — nils on reuse.
        weak var object: NSObject?
        /// Nearest live scroll view for coordinate conversion.
        weak var scrollView: UIScrollView?

        static func == (lhs: ElementRef, rhs: ElementRef) -> Bool {
            lhs.object === rhs.object && lhs.scrollView === rhs.scrollView
        }
    }

    // `@unchecked Sendable` rationale: weak UIKit refs are only observed
    // behind TheStash on the main actor.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ContainerRef: @unchecked Sendable, Equatable {
        weak var object: NSObject?

        static func == (lhs: ContainerRef, rhs: ContainerRef) -> Bool {
            lhs.object === rhs.object
        }
    }

    private static func scrollableViewsByStableId(
        hierarchy: [AccessibilityHierarchy],
        containerStableIds: [AccessibilityContainer: HeistContainer],
        containerStableIdsByPath: [TreePath: HeistContainer],
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]
    ) -> [HeistContainer: ScrollableViewRef] {
        var result: [HeistContainer: ScrollableViewRef] = [:]
        var ambiguousIds = Set<HeistContainer>()

        for (container, path) in hierarchy.containerPaths {
            guard let ref = scrollableContainerViewsByPath[path] ?? scrollableContainerViews[container] else { continue }
            guard let stableId = containerStableIdsByPath[path] ?? containerStableIds[container] else { continue }
            guard !ambiguousIds.contains(stableId) else { continue }
            if result[stableId] != nil {
                result[stableId] = nil
                ambiguousIds.insert(stableId)
            } else {
                result[stableId] = ref
            }
        }
        return result
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
