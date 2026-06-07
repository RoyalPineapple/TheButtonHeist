#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Live Capture

/// Latest parsed interface and disposable UIKit evidence.
///
/// **Ownership.** Owned by `TheStash` as latest observed live evidence; carried
/// by `Screen` only as an observation value. Ephemeral index, not source of
/// truth: keyed by `TreePath` / `AccessibilityElement` / `HeistId`, rebuilt
/// wholesale on every parse, and invalidated by the next parse (last-read-wins).
/// It carries weak UIKit refs and per-path lookups but is **never** unioned
/// across exploration pages and must never be treated as stable identity. See
/// `docs/DATA-OWNERSHIP.md`.
struct LiveCapture: Equatable {
    let hierarchy: [AccessibilityHierarchy]
    let containerNames: [AccessibilityContainer: ContainerName]
    let containerNamesByPath: [TreePath: ContainerName]
    let heistIdByElement: [AccessibilityElement: HeistId]
    let elementRefs: [HeistId: ElementRef]
    let containerRefsByPath: [TreePath: ContainerRef]
    let containerContentFramesByPath: [TreePath: CGRect]
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
        self.firstResponderHeistId = firstResponderHeistId
        self.scrollableContainerViews = scrollableContainerViews
        self.scrollableContainerViewsByPath = scrollableContainerViewsByPath
        self.scrollableViewsByContainerName = scrollableViewsByContainerName ?? Self.scrollableViewsByContainerName(
            hierarchy: hierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
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

    func containerObject(forPath path: TreePath) -> NSObject? {
        containerRefsByPath[path]?.object
    }

    func containerContentFrame(forPath path: TreePath) -> CGRect? {
        containerContentFramesByPath[path]
    }

    func scrollView(for element: SemanticScreen.Element) -> UIScrollView? {
        let visibleScrollView = contains(heistId: element.heistId) ? scrollView(for: element.heistId) : nil
        return visibleScrollView
            ?? element.scrollContentLocation.map { $0.scrollContainer }.flatMap(scrollView(forContainer:))
    }

    /// Value-only copy for settled interface projection. It preserves the
    /// parsed hierarchy and id maps but drops UIKit refs and dispatch views.
    func strippingDispatchReferences() -> LiveCapture {
        LiveCapture(
            hierarchy: hierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
            heistIdByElement: heistIdByElement,
            elementRefs: [:],
            containerRefsByPath: [:],
            containerContentFramesByPath: containerContentFramesByPath,
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
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]
    ) -> [ContainerName: ScrollableViewRef] {
        var result: [ContainerName: ScrollableViewRef] = [:]
        var ambiguousNames = Set<ContainerName>()

        for (container, path) in hierarchy.containerPaths {
            guard let ref = scrollableContainerViewsByPath[path] ?? scrollableContainerViews[container] else { continue }
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
}

#endif // DEBUG
#endif // canImport(UIKit)
