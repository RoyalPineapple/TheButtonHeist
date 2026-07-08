#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans
import TheScore

/// Viewport-tied live capture and UIKit lookup surface.
///
/// `LiveLookup` is rebuilt from the latest parse. It may carry weak UIKit refs
/// and live geometry, so it must not be used as settled semantic truth.
struct LiveLookup {
    private var capture: LiveCapture = .empty

    var liveCapture: LiveCapture {
        capture
    }

    var hierarchy: [AccessibilityHierarchy] {
        capture.hierarchy
    }

    var heistIds: Set<HeistId> {
        capture.heistIds
    }

    var firstResponderHeistId: HeistId? {
        capture.firstResponderHeistId
    }

    var scrollableContainerViewsByPath: [TreePath: UIScrollView] {
        var result: [TreePath: UIScrollView] = [:]
        for (path, ref) in capture.scrollableContainerViewsByPath {
            if let view = ref.view {
                result[path] = view
            }
        }
        return result
    }

    mutating func record(_ screen: Screen) {
        capture = screen.liveCapture
    }

    mutating func reset() {
        capture = .empty
    }

    func visibleScreen(observedSemanticWorld: SemanticScreen) -> Screen {
        let visibleElements = Dictionary(
            uniqueKeysWithValues: capture.orderedElementEntries().map { entry in
                let observedEntry = observedSemanticWorld.elements[entry.heistId]
                return (
                    entry.heistId,
                    Screen.ScreenElement(
                        heistId: entry.heistId,
                        path: entry.path,
                        scrollMembership: observedEntry?.scrollMembership,
                        observedScrollContentActivationPoint: observedEntry?.observedScrollContentActivationPoint,
                        element: entry.element
                    )
                )
            }
        )
        let visibleContainerPaths = Set(capture.hierarchy.pathIndexedContainers.map(\.path))
        return Screen(
            semantic: SemanticScreen(
                elements: visibleElements,
                containers: observedSemanticWorld.containers.filter { visibleContainerPaths.contains($0.key) }
            ),
            liveCapture: capture
        )
    }

    func screenElement(
        heistId: HeistId,
        observedSemanticWorld: SemanticScreen
    ) -> Screen.ScreenElement? {
        guard let liveEntry = capture.elementEntry(for: heistId),
              let observedEntry = observedSemanticWorld.elements[heistId] else { return nil }
        return Screen.ScreenElement(
            heistId: heistId,
            path: liveEntry.path,
            scrollMembership: observedEntry.scrollMembership,
            observedScrollContentActivationPoint: observedEntry.observedScrollContentActivationPoint,
            element: liveEntry.element
        )
    }

    func contains(heistId: HeistId) -> Bool {
        capture.contains(heistId: heistId)
    }

    func heistId(forPath path: TreePath) -> HeistId? {
        capture.heistId(forPath: path)
    }

    func object(for heistId: HeistId) -> NSObject? {
        capture.object(for: heistId)
    }

    func elementHeistId(matching object: NSObject) -> HeistId? {
        capture.heistId(matching: object)
    }

    func scrollView(for screenElement: SemanticScreen.Element) -> UIScrollView? {
        capture.scrollView(for: screenElement)
    }

    @MainActor
    func scrollView(for container: SemanticScreen.Container, tripwire _: TheTripwire) -> UIScrollView? {
        capture.scrollView(for: container)
    }

    func scrollView(forContainerPath path: TreePath) -> UIScrollView? {
        capture.scrollView(forContainerPath: path)
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        capture.containerObject(forPath: path)
    }

    func container(forPath path: TreePath) -> AccessibilityContainer? {
        guard case .container(let container, _) = capture.hierarchy.node(at: path) else {
            return nil
        }
        return container
    }

    func containerName(forPath path: TreePath) -> ContainerName? {
        capture.containerNamesByPath[path]
    }

    func scrollableContainerView(forPath path: TreePath) -> UIScrollView? {
        capture.scrollableContainerViewsByPath[path]?.view
    }

    func scrollContainerDiagnostics() -> String {
        let summaries = capture.hierarchy.scrollablePathIndexedContainers
            .map { item -> String in
                let containerName = capture.containerNamesByPath[item.path]
                let hasLiveScrollView = capture.scrollView(forContainerPath: item.path) != nil
                let pathView = capture.scrollableContainerViewsByPath[item.path]?.view
                let containerObject = capture.containerRefsByPath[item.path]?.object
                let objectType = containerObject.map { String(describing: type(of: $0)) } ?? "<nil>"
                return "path=\(item.path.indices) name=\(containerName?.rawValue ?? "<nil>") "
                    + "liveScroll=\(hasLiveScrollView) pathView=\(pathView != nil) "
                    + "object=\(objectType)"
            }
        return summaries.isEmpty
            ? "available live scroll containers: none"
            : "available live scroll containers: \(summaries.joined(separator: "; "))"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
