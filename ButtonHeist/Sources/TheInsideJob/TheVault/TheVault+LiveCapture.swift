#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans

// MARK: - Live Capture

extension TheVault {

    func liveContains(heistId: HeistId) -> Bool {
        interfaceTree.viewportCapture.contains(heistId: heistId)
    }

    func liveScrollView(for element: InterfaceTree.Element) -> UIScrollView? {
        let visibleScrollView = interfaceTree.viewportCapture.contains(heistId: element.heistId)
            ? currentLiveCapture.scrollView(for: element.heistId)
            : nil
        let pathScrollView = element.scrollContainerPath
            .flatMap { currentLiveCapture.scrollView(forContainerPath: $0) }
        return visibleScrollView ?? pathScrollView
    }

    func liveElementHeistId(matching object: NSObject) -> HeistId? {
        interfaceTree.viewportCapture.orderedHeistIds.first { heistId in
            currentLiveCapture.object(for: heistId) === object
        }
    }

    func liveContainer(forPath path: TreePath) -> AccessibilityContainer? {
        guard case .container(let container, _) = interfaceTree.viewportCapture.hierarchy.node(at: path) else {
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
        let summaries = interfaceTree.viewportCapture.hierarchy.scrollablePathIndexedContainers.map { item in
            let containerName = interfaceTree.containers[item.path]?.containerName
            let hasLiveScrollView = currentLiveCapture.scrollView(forContainerPath: item.path) != nil
            let pathView = currentLiveCapture.dispatchReferences.scrollableContainerViewsByPath[item.path]?.view
            let containerObject = currentLiveCapture.dispatchReferences.containerRefsByPath[item.path]?.object
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
