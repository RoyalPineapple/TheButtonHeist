#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import AccessibilitySnapshotParser
import UIKit

import TheScore

// MARK: - Live Geometry Resolution

extension TheStash {

    /// Dispatch-only action target.
    ///
    /// The `treeElement` is committed semantic truth; only `object`, `frame`,
    /// and `activationPoint` come from the latest live capture.
    struct LiveActionTarget {
        let treeElement: InterfaceTree.Element
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var element: AccessibilityElement { treeElement.element }
    }

    enum LiveActionTargetResolution {
        case resolved(LiveActionTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    /// Dispatch-only container target.
    ///
    /// `containerTarget` is semantic container identity. The backing object is
    /// acquired from the latest live interface immediately before dispatch.
    struct LiveContainerTarget {
        let containerTarget: InterfaceTree.Container
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var container: AccessibilityContainer { containerTarget.container }
    }

    enum LiveContainerTargetResolution {
        case resolved(LiveContainerTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    private struct LiveGeometry {
        let frame: CGRect
        let activationPoint: CGPoint
    }

    func resolveLiveActionTarget(for treeElement: InterfaceTree.Element) -> LiveActionTargetResolution {
        guard let liveElement = visibleLiveElementAliasing(treeElement),
              let object = dispatchObject(for: liveElement) else {
            return .objectUnavailable
        }
        guard let geometry = Self.liveGeometry(for: liveElement.element) else {
            return .geometryUnavailable
        }
        return .resolved(LiveActionTarget(
            treeElement: treeElement,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint
        ))
    }

    func visibleLiveElementAliasing(_ treeElement: InterfaceTree.Element) -> InterfaceTree.Element? {
        guard viewportElementIDs.contains(treeElement.heistId) else { return nil }
        guard let liveElement = liveInterfaceElement(heistId: treeElement.heistId) else { return nil }
        let committedIdentity = AccessibilityPolicy.matcherIdentityFacts(
            for: WireConversion.convert(treeElement.element)
        )
        let liveIdentity = AccessibilityPolicy.matcherIdentityFacts(
            for: WireConversion.convert(liveElement.element)
        )
        guard liveIdentity == committedIdentity else { return nil }
        return liveElement
    }

    func resolveLiveContainerTarget(for containerTarget: InterfaceTree.Container) -> LiveContainerTargetResolution {
        guard let object = liveContainerObject(forPath: containerTarget.path) else {
            return .objectUnavailable
        }
        guard let liveContainer = liveContainer(forPath: containerTarget.path),
              let geometry = Self.liveGeometry(for: liveContainer) else {
            return .geometryUnavailable
        }
        return .resolved(LiveContainerTarget(
            containerTarget: containerTarget,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint
        ))
    }

    func liveObject(for treeElement: InterfaceTree.Element) -> NSObject? {
        dispatchObject(for: treeElement)
    }

    func nearestLiveScrollContainerPath(for path: TreePath) -> TreePath? {
        var candidatePath: TreePath? = path
        while let candidate = candidatePath {
            if liveScrollableContainerView(forPath: candidate) != nil {
                return candidate
            }
            candidatePath = candidate.parent
        }
        return nil
    }

    func liveScrollView(forContainerPath path: TreePath) -> UIScrollView? {
        nearestLiveScrollContainerPath(for: path)
            .flatMap { liveScrollableContainerView(forPath: $0) }
    }

    func refreshedLiveScrollView(
        for semanticContainer: InterfaceTree.Container,
        directChildOf parent: UIScrollView? = nil
    ) -> UIScrollView? {
        var matches = latestObservation.tree.containers.values.compactMap { candidate -> LiveContainerMatch? in
            guard Self.container(candidate, matches: semanticContainer),
                  let view = liveScrollableContainerView(forPath: candidate.path) else { return nil }
            return LiveContainerMatch(path: candidate.path, view: view)
        }
        if let parent {
            guard scrollableContainerViewsByPath.values.contains(where: { $0 === parent }) else { return nil }
            matches = matches.filter { match in
                match.view.nearestScrollableSuperview === parent
                    || (match.view === parent && livePathHasAncestor(match.path, backedBy: parent))
            }
        }
        guard matches.count == 1 else { return nil }
        return matches[0].view
    }

    private func livePathHasAncestor(_ path: TreePath, backedBy scrollView: UIScrollView) -> Bool {
        var ancestor = path.parent
        while let current = ancestor {
            if liveScrollableContainerView(forPath: current) === scrollView {
                return true
            }
            ancestor = current.parent
        }
        return false
    }

    private func dispatchObject(for treeElement: InterfaceTree.Element) -> NSObject? {
        if viewportElementIDs.contains(treeElement.heistId) {
            return liveObject(for: treeElement.heistId)
        }
        return nil
    }

    private static func liveGeometry(for element: AccessibilityElement) -> LiveGeometry? {
        let frame = element.bhFrame
        let activationPoint = element.bhResolvedActivationPoint
        guard isUsableFrame(frame),
              isUsablePoint(activationPoint) else {
            return nil
        }
        return LiveGeometry(frame: frame, activationPoint: activationPoint)
    }

    private static func liveGeometry(for container: AccessibilityContainer) -> LiveGeometry? {
        let frame = container.frame.cgRect
        let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
        guard isUsableFrame(frame),
              isUsablePoint(activationPoint) else {
            return nil
        }
        return LiveGeometry(frame: frame, activationPoint: activationPoint)
    }

    private static func container(
        _ candidate: InterfaceTree.Container,
        matches semanticContainer: InterfaceTree.Container
    ) -> Bool {
        candidate.container.containerPredicateFacts == semanticContainer.container.containerPredicateFacts
            && candidate.container.scrollableContentSize == semanticContainer.container.scrollableContentSize
            && viewportSize(of: candidate) == viewportSize(of: semanticContainer)
    }

    private static func viewportSize(of container: InterfaceTree.Container) -> CGSize {
        container.contentFrame?.cgRect.size ?? container.container.frame.cgRect.size
    }

    private static func isUsableFrame(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isEmpty
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
    }

    private static func isUsablePoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}

private struct LiveContainerMatch {
    let path: TreePath
    let view: UIScrollView
}

private extension UIView {
    var nearestScrollableSuperview: UIScrollView? {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            ancestor = current.superview
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
