#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import AccessibilitySnapshotParser
import UIKit

import TheScore

extension TheStash {

    struct LiveActionTarget {
        let treeElement: InterfaceTree.Element
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint
        let captureToken: InterfaceCaptureToken

        var element: AccessibilityElement { treeElement.element }

    }

    enum LiveActionTargetResolution {
        case resolved(LiveActionTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    enum LiveTargetStaleness<Identity: Equatable & Sendable>: Error, Equatable, Sendable {
        case semanticTargetUnavailable(Identity)
        case objectUnavailable(Identity)
        case geometryUnavailable(Identity)
    }

    struct LiveContainerTarget {
        let containerTarget: InterfaceTree.Container
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint
        let captureToken: InterfaceCaptureToken

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
        let captureToken = latestObservation.captureToken
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
            activationPoint: geometry.activationPoint,
            captureToken: captureToken
        ))
    }

    func dispatchOnFreshLiveActionTarget<Value>(
        _ target: LiveActionTarget,
        operation: (LiveActionTarget) -> Value
    ) -> Result<Value, LiveTargetStaleness<HeistId>> {
        let heistId = target.treeElement.heistId
        guard let currentTreeElement = latestObservation.tree.findElement(heistId: heistId) else {
            return .failure(.semanticTargetUnavailable(heistId))
        }
        switch resolveLiveActionTarget(for: currentTreeElement) {
        case .resolved(let currentTarget):
            return .success(operation(currentTarget))
        case .objectUnavailable:
            return .failure(.objectUnavailable(heistId))
        case .geometryUnavailable:
            return .failure(.geometryUnavailable(heistId))
        }
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
        let captureToken = latestObservation.captureToken
        guard let currentContainer = latestObservation.tree.containers[containerTarget.path],
              Self.container(currentContainer, matches: containerTarget) else {
            return .objectUnavailable
        }
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
            activationPoint: geometry.activationPoint,
            captureToken: captureToken
        ))
    }

    func dispatchOnFreshLiveContainerTarget<Value>(
        _ target: LiveContainerTarget,
        operation: (LiveContainerTarget) -> Value
    ) -> Result<Value, LiveTargetStaleness<TreePath>> {
        let path = target.containerTarget.path
        guard let currentContainer = latestObservation.tree.containers[path],
              Self.container(currentContainer, matches: target.containerTarget) else {
            return .failure(.semanticTargetUnavailable(path))
        }
        switch resolveLiveContainerTarget(for: currentContainer) {
        case .resolved(let currentTarget):
            return .success(operation(currentTarget))
        case .objectUnavailable:
            return .failure(.objectUnavailable(path))
        case .geometryUnavailable:
            return .failure(.geometryUnavailable(path))
        }
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

extension TheStash.LiveTargetStaleness where Identity == HeistId {
    var message: String {
        switch self {
        case .semanticTargetUnavailable(let heistId):
            "Live target \(heistId.rawValue) left the current capture before dispatch"
        case .objectUnavailable(let heistId):
            "Live target \(heistId.rawValue) has no current UIKit object at dispatch"
        case .geometryUnavailable(let heistId):
            "Live target \(heistId.rawValue) has no current actionable geometry at dispatch"
        }
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
