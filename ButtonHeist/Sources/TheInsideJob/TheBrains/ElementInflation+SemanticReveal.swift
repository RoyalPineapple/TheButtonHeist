#if canImport(UIKit) && DEBUG
import AccessibilitySnapshotModel
import ThePlans
import UIKit

extension ElementInflation {

    static let maxNestedRevealDepth = 8

    enum SemanticRevealFailure: Equatable {
        case missingScrollMembership
        case noLiveScrollableAncestor
        case scanDidNotRevealTarget
    }

    enum SemanticRevealResult {
        case alreadyVisible
        case revealed
        case failed(SemanticRevealFailure)

        var didReveal: Bool {
            if case .revealed = self { return true }
            return false
        }
    }

    /// Reveal an off-viewport target from the interface tree. Off-viewport
    /// elements carry no executable scroll authority unless the parser
    /// retained a live scroll ancestor.
    @discardableResult
    func revealSemanticTarget(_ treeElement: InterfaceTree.Element) async -> SemanticRevealResult {
        if let visible = stash.liveInterfaceElement(heistId: treeElement.heistId),
           visible.element.representsSameSemanticElement(as: treeElement.element) {
            return .alreadyVisible
        }

        guard treeElement.scrollMembership != nil else {
            return .failed(.missingScrollMembership)
        }
        if await revealScrollAncestors(for: treeElement),
           await moveToObservedContentActivationPoint(treeElement) {
            return .revealed
        }
        guard let exploredScreen = await exploration.revealKnownTarget(treeElement.heistId) else {
            return .failed(.noLiveScrollableAncestor)
        }
        stash.semanticObservationStream.commitSettledDiscoveryObservation(.explored(exploredScreen))
        guard let visible = stash.liveInterfaceElement(heistId: treeElement.heistId),
              visible.element.representsSameSemanticElement(as: treeElement.element)
        else {
            return .failed(.scanDidNotRevealTarget)
        }
        return .revealed
    }

    static func semanticRevealTargetOffset(
        for observedActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint,
        in scrollView: UIScrollView
    ) -> CGPoint {
        let contentActivationPoint = observedActivationPoint.point.cgPoint
        let insets = scrollView.adjustedContentInset
        let visibleWidth = max(1, scrollView.bounds.width - insets.left - insets.right)
        let visibleHeight = max(1, scrollView.bounds.height - insets.top - insets.bottom)

        let minX = -insets.left
        let minY = -insets.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + insets.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)

        let targetX = contentActivationPoint.x - visibleWidth / 2 - insets.left
        let targetY = contentActivationPoint.y - visibleHeight / 2 - insets.top

        return CGPoint(
            x: min(max(targetX, minX), maxX),
            y: min(max(targetY, minY), maxY)
        )
    }

    private func moveToObservedContentActivationPoint(_ treeElement: InterfaceTree.Element) async -> Bool {
        guard let observedActivationPoint = treeElement.observedScrollContentActivationPoint,
              let scrollView = liveScrollView(for: treeElement)
        else { return false }

        scrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: scrollView),
            animated: false
        )
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        stash.refreshLiveCapture()
        return true
    }

    private func revealScrollAncestors(for treeElement: InterfaceTree.Element) async -> Bool {
        guard let scrollContainerPath = treeElement.scrollContainerPath else { return false }
        return await revealScrollContainer(at: scrollContainerPath, depth: 0)
    }

    private func revealScrollContainer(at path: TreePath, depth: Int) async -> Bool {
        if hasLiveScrollContainer(at: path) {
            return true
        }
        guard depth < Self.maxNestedRevealDepth else { return false }
        guard let container = semanticContainer(at: path),
              let membership = container.scrollMembership,
              let observedActivationPoint = container.observedScrollContentActivationPoint
        else { return false }
        guard await revealScrollContainer(at: membership.containerPath, depth: depth + 1),
              let parentScrollView = liveScrollView(forScrollContainerPath: membership.containerPath)
        else { return false }

        parentScrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: parentScrollView),
            animated: false
        )
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        guard stash.refreshLiveCapture() != nil else { return false }
        return hasLiveScrollContainer(at: path)
    }

    private func liveScrollView(for treeElement: InterfaceTree.Element) -> UIScrollView? {
        guard let scrollContainerPath = treeElement.scrollContainerPath else {
            return stash.liveScrollView(for: treeElement)
        }
        return liveScrollView(forScrollContainerPath: scrollContainerPath)
            ?? stash.liveScrollView(for: treeElement)
    }

    private func liveScrollView(forScrollContainerPath path: TreePath) -> UIScrollView? {
        stash.liveScrollView(forContainerPath: path)
    }

    private func hasLiveScrollContainer(at path: TreePath) -> Bool {
        guard let livePath = stash.nearestLiveScrollContainerPath(for: path) else { return false }
        guard let parentPath = semanticContainer(at: path)?.scrollMembership?.containerPath else { return true }
        return livePath != stash.nearestLiveScrollContainerPath(for: parentPath)
    }

    private func semanticContainer(at path: TreePath) -> InterfaceTree.Container? {
        stash.interfaceTree.containers[path]
    }
}

private extension AccessibilityElement {
    func representsSameSemanticElement(as other: AccessibilityElement) -> Bool {
        label == other.label
            && identifier == other.identifier
            && value == other.value
            && traits == other.traits
    }
}

#endif // canImport(UIKit) && DEBUG
