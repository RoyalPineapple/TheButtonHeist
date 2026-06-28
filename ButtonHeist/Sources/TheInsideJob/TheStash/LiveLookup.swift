#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans

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

    var scrollableContainerViews: [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, ref) in capture.scrollableContainerViews {
            if let view = ref.view {
                result[container] = view
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
                        scrollContentLocation: observedEntry?.scrollContentLocation,
                        element: entry.element
                    )
                )
            }
        )
        let visibleContainerPaths = Set(capture.hierarchy.containerPaths.map(\.path))
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
        guard let liveElement = capture.element(for: heistId),
              let observedEntry = observedSemanticWorld.elements[heistId] else { return nil }
        return Screen.ScreenElement(
            heistId: heistId,
            scrollContentLocation: observedEntry.scrollContentLocation,
            element: liveElement
        )
    }

    func contains(heistId: HeistId) -> Bool {
        capture.contains(heistId: heistId)
    }

    func heistId(for element: AccessibilityElement) -> HeistId? {
        capture.heistId(for: element)
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

    func scrollView(forContainerName containerName: ContainerName) -> UIScrollView? {
        capture.scrollView(forContainer: containerName)
    }

    @MainActor
    func scrollView(
        for containerName: ContainerName,
        semanticContainer: @autoclosure () -> SemanticScreen.Container?,
        tripwire _: TheTripwire
    ) -> UIScrollView? {
        capture.scrollView(forContainer: containerName)
            ?? semanticContainer().flatMap { capture.scrollView(for: $0) }
    }

    @MainActor
    func scrollView(for container: SemanticScreen.Container, tripwire _: TheTripwire) -> UIScrollView? {
        capture.scrollView(for: container)
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        capture.containerObject(forPath: path)
    }

    func container(forPath path: TreePath) -> AccessibilityContainer? {
        capture.hierarchy.containerPaths.first { $0.path == path }?.container
    }

    func containerName(for container: AccessibilityContainer) -> ContainerName? {
        capture.containerNames[container]
    }

    func containerName(forPath path: TreePath) -> ContainerName? {
        capture.containerNamesByPath[path]
    }

    func scrollableContainerView(forPath path: TreePath) -> UIView? {
        if let view = capture.scrollableContainerViewsByPath[path]?.view {
            return view
        }
        guard let container = container(forPath: path) else { return nil }
        return capture.scrollableContainerViews[container]?.view
    }

    func scrollContainerDiagnostics() -> String {
        let summaries = capture.hierarchy.containerPaths
            .filter { $0.container.isScrollable }
            .map { item -> String in
                let containerName = capture.containerNamesByPath[item.path]
                    ?? capture.containerNames[item.container]
                let hasLiveScrollView = containerName
                    .flatMap { capture.scrollView(forContainer: $0) } != nil
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
