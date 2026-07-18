#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import AccessibilitySnapshotParser
import UIKit

import TheScore

extension TheVault {

    struct LiveActionTarget {
        let treeElement: InterfaceTree.Element
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint
        let captureToken: InterfaceCaptureToken

        var element: AccessibilityElement { treeElement.element }

    }

    enum LiveTargetResolution<Target> {
        case resolved(Target)
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

    struct LiveScrollTarget {
        let container: LiveContainerTarget
        let scrollView: UIScrollView

        var path: TreePath { container.containerTarget.path }
        var scrollViewID: ObjectIdentifier { ObjectIdentifier(scrollView) }
    }

    private struct LiveGeometry {
        let frame: CGRect
        let activationPoint: CGPoint
    }

    func resolveLiveActionTarget(for treeElement: InterfaceTree.Element) -> LiveTargetResolution<LiveActionTarget> {
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

    func resolveLiveContainerTarget(
        for containerTarget: InterfaceTree.Container
    ) -> LiveTargetResolution<LiveContainerTarget> {
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

    func liveScrollTarget(at path: TreePath) -> LiveScrollTarget? {
        guard let semanticContainer = latestObservation.tree.containers[path],
              case .resolved(let liveContainer) = resolveLiveContainerTarget(for: semanticContainer),
              let scrollView = liveScrollableContainerView(forPath: path)
        else { return nil }
        return LiveScrollTarget(container: liveContainer, scrollView: scrollView)
    }

    func nearestLiveScrollTarget(for path: TreePath) -> LiveScrollTarget? {
        guard let containerPath = nearestLiveScrollContainerPath(for: path) else { return nil }
        return liveScrollTarget(at: containerPath)
    }

    func liveScrollTarget(matching scrollViewID: ObjectIdentifier) -> LiveScrollTarget? {
        for entry in currentLiveCapture.scrollEntries(matching: scrollViewID) {
            if let target = liveScrollTarget(at: entry.path) { return target }
        }
        return nil
    }

    func liveProgrammaticScrollTargets(
        descendedFrom rootScrollViewID: ObjectIdentifier? = nil
    ) -> [LiveScrollTarget] {
        var admittedScrollViewIDs = Set<ObjectIdentifier>()
        let targets = currentLiveCapture.scrollEntries().compactMap { entry -> LiveScrollTarget? in
            guard !admittedScrollViewIDs.contains(entry.scrollViewID),
                  let target = liveScrollTarget(at: entry.path),
                  !target.scrollView.bhIsUnsafeForProgrammaticScrolling
            else { return nil }
            admittedScrollViewIDs.insert(entry.scrollViewID)
            return target
        }
        guard let rootScrollViewID else { return targets }

        return targets.filter { target in
            var current = target.scrollViewID
            var visited = Set<ObjectIdentifier>()
            while visited.insert(current).inserted {
                if current == rootScrollViewID { return true }
                guard admittedScrollViewIDs.contains(current),
                      let parent = currentLiveCapture.parentScrollViewID(of: current) else { return false }
                current = parent
            }
            return false
        }
    }

    func liveScrollViewIDForRevealing(heistId: HeistId) -> ObjectIdentifier? {
        guard let membership = interfaceElement(heistId: heistId)?.scrollMembership else { return nil }
        var visitedPaths = Set<TreePath>()
        var path: TreePath? = membership.containerPath
        while let currentPath = path, visitedPaths.insert(currentPath).inserted {
            if let scrollView = liveScrollableContainerView(forPath: currentPath),
               liveContainerObject(forPath: currentPath) != nil,
               liveContainer(forPath: currentPath) != nil,
               !scrollView.bhIsUnsafeForProgrammaticScrolling {
                return ObjectIdentifier(scrollView)
            }
            path = interfaceTree.containers[currentPath]?.scrollMembership?.containerPath
        }
        return nil
    }

    func refreshedLiveScrollView(
        for semanticContainer: InterfaceTree.Container,
        directChildOf parent: UIScrollView? = nil
    ) -> UIScrollView? {
        var matches = latestObservation.tree.orderedContainers.compactMap { candidate -> LiveCapture.ScrollEntry? in
            guard Self.container(candidate, matches: semanticContainer),
                  let view = liveScrollableContainerView(forPath: candidate.path) else { return nil }
            return LiveCapture.ScrollEntry(path: candidate.path, view: view)
        }
        if let parent {
            matches = matches.filter { match in
                isDirectLiveScrollChild(at: match.path, of: parent)
            }
        }
        guard matches.count == 1 else { return nil }
        return matches[0].view
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

extension TheVault.LiveTargetStaleness where Identity == HeistId {
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

#endif // DEBUG
#endif // canImport(UIKit)
