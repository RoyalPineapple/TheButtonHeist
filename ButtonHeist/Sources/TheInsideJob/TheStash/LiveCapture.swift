#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Live Capture

/// Visible live view from the latest observed capture.
///
/// **Ownership.** Owned by `TheStash` as viewport-tied live state; carried by
/// `Screen` only as part of an observed capture. Ephemeral index, not source of
/// truth: keyed by `TreePath` / `AccessibilityElement` / `HeistId`, rebuilt
/// wholesale on every parse, and invalidated by the next parse (last-read-wins).
/// It carries weak UIKit refs, live geometry, and per-path lookups but is
/// **never** unioned across exploration pages and must never be treated as
/// stable identity. See `docs/DATA-OWNERSHIP.md`.
struct LiveCapture: Equatable {
    let hierarchy: [AccessibilityHierarchy]
    let containerNames: [AccessibilityContainer: ContainerName]
    let containerNamesByPath: [TreePath: ContainerName]
    let heistIdByElement: [AccessibilityElement: HeistId]
    let elementRefs: [HeistId: ElementRef]
    let containerRefsByPath: [TreePath: ContainerRef]
    let containerContentFramesByPath: [TreePath: CGRect]
    let containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation]
    let firstResponderHeistId: HeistId?
    let scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]
    private let scrollableViewsByContainerName: [ContainerName: ScrollableViewRef]

    init(
        hierarchy: [AccessibilityHierarchy],
        containerNames: [AccessibilityContainer: ContainerName],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdByElement: [AccessibilityElement: HeistId],
        elementRefs: [HeistId: ElementRef],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:],
        scrollableViewsByContainerName: [ContainerName: ScrollableViewRef]? = nil
    ) {
        self.hierarchy = hierarchy
        self.containerNames = containerNames
        self.containerNamesByPath = containerNamesByPath
        self.heistIdByElement = heistIdByElement
        self.elementRefs = elementRefs
        self.containerRefsByPath = containerRefsByPath
        self.containerContentFramesByPath = containerContentFramesByPath
        self.containerScrollContentLocationsByPath = containerScrollContentLocationsByPath
        self.firstResponderHeistId = firstResponderHeistId
        self.scrollableContainerViews = scrollableContainerViews
        self.scrollableContainerViewsByPath = scrollableContainerViewsByPath
        self.scrollableViewsByContainerName = scrollableViewsByContainerName ?? Self.scrollableViewsByContainerName(
            hierarchy: hierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
            containerRefsByPath: containerRefsByPath,
            scrollableContainerViews: scrollableContainerViews,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
    }

    static let empty = LiveCapture(
        hierarchy: [],
        containerNames: [:],
        heistIdByElement: [:],
        elementRefs: [:],
        containerRefsByPath: [:],
        containerContentFramesByPath: [:],
        containerScrollContentLocationsByPath: [:],
        firstResponderHeistId: nil,
        scrollableContainerViews: [:]
    )

    var heistIds: Set<HeistId> {
        Set(heistIdByElement.values)
    }

    func contains(heistId: HeistId) -> Bool {
        heistIds.contains(heistId)
    }

    func heistId(for element: AccessibilityElement) -> HeistId? {
        heistIdByElement[element]
    }

    func element(for heistId: HeistId) -> AccessibilityElement? {
        heistIdByElement.first { $0.value == heistId }?.key
    }

    func object(for heistId: HeistId) -> NSObject? {
        elementRefs[heistId]?.object
    }

    func scrollView(for heistId: HeistId) -> UIScrollView? {
        elementRefs[heistId]?.scrollView
    }

    func scrollView(forContainer containerName: ContainerName) -> UIScrollView? {
        scrollableViewsByContainerName[containerName]?.view as? UIScrollView
    }

    func scrollView(for container: SemanticScreen.Container) -> UIScrollView? {
        if let containerName = container.containerName,
           let scrollView = scrollView(forContainer: containerName) {
            return scrollView
        }
        return scrollableContainerViewsByPath[container.path]?.view as? UIScrollView
            ?? containerRefsByPath[container.path]?.object as? UIScrollView
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        containerRefsByPath[path]?.object
    }

    func containerContentFrame(forPath path: TreePath) -> CGRect? {
        containerContentFramesByPath[path]
    }

    func containerScrollContentLocation(forPath path: TreePath) -> SemanticScreen.ScrollContentLocation? {
        containerScrollContentLocationsByPath[path]
    }

    func scrollView(for element: SemanticScreen.Element) -> UIScrollView? {
        let visibleScrollView = contains(heistId: element.heistId) ? scrollView(for: element.heistId) : nil
        let namedScrollView = element.scrollContentLocation
            .map { $0.scrollContainer }
            .flatMap(scrollView(forContainer:))
        return visibleScrollView
            ?? namedScrollView
    }

    /// Value-only copy for settled semantic projection. It preserves the parsed
    /// hierarchy and id maps but drops UIKit refs and dispatch views.
    func strippingDispatchReferences() -> LiveCapture {
        LiveCapture(
            hierarchy: hierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
            heistIdByElement: heistIdByElement,
            elementRefs: [:],
            containerRefsByPath: [:],
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollContentLocationsByPath: containerScrollContentLocationsByPath,
            firstResponderHeistId: nil,
            scrollableContainerViews: [:],
            scrollableContainerViewsByPath: [:],
            scrollableViewsByContainerName: [:]
        )
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

    private static func scrollableViewsByContainerName(
        hierarchy: [AccessibilityHierarchy],
        containerNames: [AccessibilityContainer: ContainerName],
        containerNamesByPath: [TreePath: ContainerName],
        containerRefsByPath: [TreePath: ContainerRef],
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]
    ) -> [ContainerName: ScrollableViewRef] {
        var result: [ContainerName: ScrollableViewRef] = [:]
        var ambiguousNames = Set<ContainerName>()

        for (container, path) in hierarchy.containerPaths {
            guard let ref = scrollableContainerViewsByPath[path]
                ?? scrollableContainerViews[container]
                ?? scrollableContainerRefFromContainerObject(containerRefsByPath[path])
            else { continue }
            guard let containerName = containerNamesByPath[path] ?? containerNames[container] else { continue }
            guard !ambiguousNames.contains(containerName) else { continue }
            if result[containerName] != nil {
                result[containerName] = nil
                ambiguousNames.insert(containerName)
            } else {
                result[containerName] = ref
            }
        }
        return result
    }

    private static func scrollableContainerRefFromContainerObject(
        _ ref: ContainerRef?
    ) -> ScrollableViewRef? {
        guard let scrollView = ref?.object as? UIScrollView else { return nil }
        return ScrollableViewRef(view: scrollView)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
