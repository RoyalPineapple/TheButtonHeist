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

    func liveScrollView(for container: SemanticScreen.Container) -> UIScrollView? {
        liveLookup.scrollView(for: container, tripwire: tripwire)
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

    func capturedLiveScrollView(forContainerPath path: TreePath) -> UIScrollView? {
        liveLookup.scrollView(forContainerPath: path)
    }

    func liveScrollContainerDiagnostics() -> String {
        liveLookup.scrollContainerDiagnostics()
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
