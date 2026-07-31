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
        let captureID: InterfaceCaptureID

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
        let captureID: InterfaceCaptureID

        var container: AccessibilityContainer { containerTarget.container }

    }

    struct LiveScrollTarget {
        let container: LiveContainerTarget
        let scrollView: UIScrollView

        var scrollViewID: ObjectIdentifier { ObjectIdentifier(scrollView) }
    }

    private struct LiveGeometry {
        let frame: CGRect
        let activationPoint: CGPoint
    }

    func resolveLiveActionTarget(for treeElement: InterfaceTree.Element) -> LiveTargetResolution<LiveActionTarget> {
        guard let semanticElement = interfaceTree.findElement(heistId: treeElement.heistId) else {
            return .objectUnavailable
        }
        return resolveLiveActionTarget(forCanonical: semanticElement)
    }

    private func resolveLiveActionTarget(
        forCanonical semanticElement: InterfaceTree.Element
    ) -> LiveTargetResolution<LiveActionTarget> {
        let currentCaptureID = captureID
        guard let liveEvidence = liveElementEvidence(aliasedTo: semanticElement),
              let object = currentLiveCapture.object(for: semanticElement.heistId) else {
            return .objectUnavailable
        }
        guard let geometry = Self.liveGeometry(for: liveEvidence.element) else {
            return .geometryUnavailable
        }
        return .resolved(LiveActionTarget(
            treeElement: semanticElement,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint,
            captureID: currentCaptureID
        ))
    }

    func dispatchOnFreshLiveActionTarget<Value>(
        _ target: LiveActionTarget,
        operation: (LiveActionTarget) -> Value
    ) -> Result<Value, LiveTargetStaleness<HeistId>> {
        let heistId = target.treeElement.heistId
        guard let semanticElement = interfaceTree.findElement(heistId: heistId) else {
            return .failure(.semanticTargetUnavailable(heistId))
        }
        switch resolveLiveActionTarget(forCanonical: semanticElement) {
        case .resolved(let currentTarget):
            return .success(operation(currentTarget))
        case .objectUnavailable:
            return .failure(.objectUnavailable(heistId))
        case .geometryUnavailable:
            return .failure(.geometryUnavailable(heistId))
        }
    }

    func visibleLiveElementAliasing(_ treeElement: InterfaceTree.Element) -> InterfaceTree.Element? {
        guard let semanticElement = interfaceTree.findElement(heistId: treeElement.heistId),
              liveElementEvidence(aliasedTo: semanticElement) != nil
        else { return nil }
        return semanticElement
    }

    private func liveElementEvidence(
        aliasedTo semanticElement: InterfaceTree.Element
    ) -> InterfaceTree.Element? {
        guard interfaceTree.viewportElementIDs.contains(semanticElement.heistId),
              currentLiveCapture.contains(heistId: semanticElement.heistId),
              let evidence = currentInterfaceObservation.tree.findElement(heistId: semanticElement.heistId)
        else { return nil }
        let semanticIdentity = AccessibilityPolicy.matcherIdentityFacts(
            for: WireConversion.convert(semanticElement.element, geometry: semanticElement.geometry)
        )
        let evidenceIdentity = AccessibilityPolicy.matcherIdentityFacts(
            for: WireConversion.convert(evidence.element, geometry: evidence.geometry)
        )
        guard evidenceIdentity == semanticIdentity else { return nil }
        return evidence
    }

    func resolveLiveContainerTarget(
        for containerTarget: InterfaceTree.Container
    ) -> LiveTargetResolution<LiveContainerTarget> {
        guard let semanticContainer = interfaceTree.containers[containerTarget.path],
              Self.container(semanticContainer, matches: containerTarget) else {
            return .objectUnavailable
        }
        return resolveLiveContainerTarget(forCanonical: semanticContainer)
    }

    private func resolveLiveContainerTarget(
        forCanonical semanticContainer: InterfaceTree.Container
    ) -> LiveTargetResolution<LiveContainerTarget> {
        let currentCaptureID = captureID
        guard let liveEvidence = liveContainerEvidence(aliasedTo: semanticContainer),
              let object = currentLiveCapture.containerObject(forPath: semanticContainer.path) else {
            return .objectUnavailable
        }
        guard let geometry = Self.liveGeometry(for: liveEvidence) else {
            return .geometryUnavailable
        }
        return .resolved(LiveContainerTarget(
            containerTarget: semanticContainer,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint,
            captureID: currentCaptureID
        ))
    }

    func dispatchOnFreshLiveContainerTarget<Value>(
        _ target: LiveContainerTarget,
        operation: (LiveContainerTarget) -> Value
    ) -> Result<Value, LiveTargetStaleness<TreePath>> {
        let path = target.containerTarget.path
        guard let semanticContainer = interfaceTree.containers[path],
              Self.container(semanticContainer, matches: target.containerTarget) else {
            return .failure(.semanticTargetUnavailable(path))
        }
        switch resolveLiveContainerTarget(forCanonical: semanticContainer) {
        case .resolved(let currentTarget):
            return .success(operation(currentTarget))
        case .objectUnavailable:
            return .failure(.objectUnavailable(path))
        case .geometryUnavailable:
            return .failure(.geometryUnavailable(path))
        }
    }

    func liveObject(for treeElement: InterfaceTree.Element) -> NSObject? {
        guard let semanticElement = interfaceTree.findElement(heistId: treeElement.heistId),
              liveElementEvidence(aliasedTo: semanticElement) != nil else {
            return nil
        }
        return currentLiveCapture.object(for: semanticElement.heistId)
    }

    /// Why a path names no live scroll target.
    enum LiveScrollTargetFailure: Error, Equatable {
        /// The current reading describes nothing at that path.
        case noSemanticContainer
        /// The reading has a container there and no live object answers to it.
        case liveContainerUnresolved
        /// The live object there is not a scroll view.
        case notScrollable
    }

    func liveScrollTarget(
        at path: TreePath
    ) -> Result<LiveScrollTarget, LiveScrollTargetFailure> {
        guard let semanticContainer = interfaceTree.containers[path] else {
            return .failure(.noSemanticContainer)
        }
        guard case .resolved(let liveContainer) =
            resolveLiveContainerTarget(forCanonical: semanticContainer) else {
            return .failure(.liveContainerUnresolved)
        }
        guard let scrollView = currentLiveCapture.scrollView(forContainerPath: path) else {
            return .failure(.notScrollable)
        }
        return .success(LiveScrollTarget(container: liveContainer, scrollView: scrollView))
    }

    func liveScrollTarget(matching scrollViewID: ObjectIdentifier) -> LiveScrollTarget? {
        for entry in currentLiveCapture.scrollEntries(matching: scrollViewID) {
            if case .success(let target) = liveScrollTarget(at: entry.path) { return target }
        }
        return nil
    }

    func liveScrollViewIDForRevealing(heistId: HeistId) -> ObjectIdentifier? {
        guard let membership = interfaceElement(heistId: heistId)?.scrollMembership else { return nil }
        var visitedPaths = Set<TreePath>()
        var path: TreePath? = membership.containerPath
        while let currentPath = path, visitedPaths.insert(currentPath).inserted {
            if case .success(let target) = liveScrollTarget(at: currentPath),
               !target.scrollView.bhIsUnsafeForProgrammaticScrolling {
                return target.scrollViewID
            }
            path = interfaceTree.containers[currentPath]?.scrollMembership?.containerPath
        }
        return nil
    }

    func refreshedLiveScrollView(
        for semanticContainer: InterfaceTree.Container,
        directChildOf parent: UIScrollView? = nil
    ) -> UIScrollView? {
        var matches = interfaceTree.orderedContainers.compactMap { candidate -> LiveCapture.ScrollEntry? in
            guard Self.container(candidate, matches: semanticContainer),
                  case .success(let target) = liveScrollTarget(at: candidate.path)
            else { return nil }
            return LiveCapture.ScrollEntry(path: candidate.path, view: target.scrollView)
        }
        if let parent {
            matches = matches.filter { match in
                isDirectLiveScrollChild(at: match.path, of: parent)
            }
        }
        guard matches.count == 1 else { return nil }
        return matches[0].view
    }

    private func liveContainerEvidence(
        aliasedTo semanticContainer: InterfaceTree.Container
    ) -> AccessibilityContainer? {
        let path = semanticContainer.path
        guard let observedContainer = currentInterfaceObservation.tree.containers[path],
              Self.container(observedContainer, matches: semanticContainer),
              case .container(let evidence, _) = currentLiveCapture.hierarchy.node(at: path),
              Self.container(evidence, matches: semanticContainer)
        else {
            return nil
        }
        return evidence
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

    private static func container(
        _ candidate: AccessibilityContainer,
        matches semanticContainer: InterfaceTree.Container
    ) -> Bool {
        candidate.containerPredicateFacts == semanticContainer.container.containerPredicateFacts
            && candidate.scrollableContentSize == semanticContainer.container.scrollableContentSize
    }

    private static func viewportSize(of container: InterfaceTree.Container) -> CGSize {
        container.viewSpace.frame?.cgRect.size ?? container.container.frame.cgRect.size
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
