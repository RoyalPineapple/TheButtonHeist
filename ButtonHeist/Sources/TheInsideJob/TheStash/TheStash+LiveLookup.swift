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
        liveLookup.scrollView(
            for: containerName,
            semanticContainer: uniqueSemanticContainer(named: containerName),
            tripwire: tripwire
        )
    }

    func liveScrollView(for container: SemanticScreen.Container) -> UIScrollView? {
        liveLookup.scrollView(for: container, tripwire: tripwire)
    }

    func uniqueSemanticContainer(named containerName: ContainerName) -> SemanticScreen.Container? {
        let matches = semanticContainersInTraversalOrder.filter { $0.containerName == containerName }
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

    func liveScrollContainer(matching scrollView: UIScrollView) -> AccessibilityContainer? {
        liveLookup.scrollContainer(matching: scrollView)
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
}

#endif // DEBUG
#endif // canImport(UIKit)
