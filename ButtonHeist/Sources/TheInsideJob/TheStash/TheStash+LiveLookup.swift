#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans

// MARK: - Live Lookup Facade

extension TheStash {

    func liveHeistIds() -> Set<HeistId> {
        liveLookup.heistIds
    }

    func liveContains(heistId: HeistId) -> Bool {
        liveLookup.contains(heistId: heistId)
    }

    func liveHeistId(for element: AccessibilityElement) -> HeistId? {
        liveLookup.heistId(for: element)
    }

    func liveObject(for heistId: HeistId) -> NSObject? {
        liveLookup.object(for: heistId)
    }

    func liveScrollView(for screenElement: ScreenElement) -> UIScrollView? {
        liveLookup.scrollView(for: screenElement)
    }

    func capturedLiveScrollView(forContainerName containerName: ContainerName) -> UIScrollView? {
        liveLookup.scrollView(forContainerName: containerName)
    }

    func liveScrollView(forContainerName containerName: ContainerName) -> UIScrollView? {
        if let scrollView = liveLookup.scrollView(forContainerName: containerName) {
            return scrollView
        }
        return uniqueLiveScrollView(for: semanticContainers(named: containerName))
    }

    func liveScrollView(for container: SemanticScreen.Container) -> UIScrollView? {
        liveLookup.scrollView(for: container, tripwire: tripwire)
    }

    func uniqueSemanticContainer(named containerName: ContainerName) -> SemanticScreen.Container? {
        let matches = semanticContainers(named: containerName)
        return matches.count == 1 ? matches[0] : nil
    }

    func liveElementHeistId(matching object: NSObject) -> HeistId? {
        liveLookup.elementHeistId(matching: object)
    }

    func liveContainerObject(forPath path: TreePath) -> NSObject? {
        liveLookup.containerObject(forPath: path)
    }

    func liveContainer(forPath path: TreePath) -> AccessibilityContainer? {
        liveLookup.container(forPath: path)
    }

    func liveContainerName(for container: AccessibilityContainer) -> ContainerName? {
        liveLookup.containerName(for: container)
    }

    func liveContainerName(forPath path: TreePath) -> ContainerName? {
        liveLookup.containerName(forPath: path)
    }

    func liveScrollableContainerView(forPath path: TreePath) -> UIView? {
        liveLookup.scrollableContainerView(forPath: path)
    }

    func liveScrollContainerDiagnostics() -> String {
        liveLookup.scrollContainerDiagnostics()
    }

    private func semanticContainers(named containerName: ContainerName) -> [SemanticScreen.Container] {
        semanticContainersInTraversalOrder.filter { $0.containerName == containerName }
    }

    private func uniqueLiveScrollView(for containers: [SemanticScreen.Container]) -> UIScrollView? {
        var scrollViews = Set<UIScrollView>()
        for container in containers {
            guard let scrollView = liveLookup.scrollView(
                for: container,
                tripwire: tripwire
            ) else { continue }
            scrollViews.insert(scrollView)
        }
        return scrollViews.count == 1 ? scrollViews.first : nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
