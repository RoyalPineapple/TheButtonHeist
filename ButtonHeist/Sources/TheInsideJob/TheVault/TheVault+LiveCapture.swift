#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans

// MARK: - Live Capture

extension TheVault {

    func liveHeistIds() -> Set<HeistId> {
        currentLiveCapture.heistIds
    }

    func liveContains(heistId: HeistId) -> Bool {
        currentLiveCapture.contains(heistId: heistId)
    }

    func liveObject(for heistId: HeistId) -> NSObject? {
        currentLiveCapture.object(for: heistId)
    }

    func liveScrollView(for element: InterfaceTree.Element) -> UIScrollView? {
        currentLiveCapture.scrollView(for: element)
    }

    func liveElementHeistId(matching object: NSObject) -> HeistId? {
        currentLiveCapture.heistId(matching: object)
    }

    func liveContainer(forPath path: TreePath) -> AccessibilityContainer? {
        guard case .container(let container, _) = currentLiveCapture.hierarchy.node(at: path) else {
            return nil
        }
        return container
    }

    func liveScrollableContainerView(forPath path: TreePath) -> UIScrollView? {
        currentLiveCapture.scrollView(forContainerPath: path)
    }

    func isDirectLiveScrollChild(at path: TreePath, of parent: UIScrollView) -> Bool {
        currentLiveCapture.isDirectScrollChild(at: path, of: parent)
    }

    func liveScrollContainerDiagnostics() -> String {
        let summaries = currentLiveCapture.hierarchy.scrollablePathIndexedContainers.map { item in
            let containerName = interfaceTree.containers[item.path]?.containerName
            let hasLiveScrollView = currentLiveCapture.scrollView(forContainerPath: item.path) != nil
            let pathView = currentLiveCapture.scrollableContainerViewsByPath[item.path]?.view
            let containerObject = currentLiveCapture.containerRefsByPath[item.path]?.object
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
