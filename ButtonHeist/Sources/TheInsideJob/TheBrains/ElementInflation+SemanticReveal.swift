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
        guard let revealedScreen = await revealKnownTarget?(treeElement.heistId) else {
            return .failed(.noLiveScrollableAncestor)
        }
        stash.semanticObservationStream.commitSettledDiscoveryObservation(revealedScreen)
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
        stash.refreshTreeAfterViewportMove()
        return true
    }

    private func revealScrollAncestors(for treeElement: InterfaceTree.Element) async -> Bool {
        guard let scrollContainerPath = treeElement.scrollContainerPath else { return false }
        return await revealScrollContainer(at: scrollContainerPath, depth: 0)
    }

    private func revealScrollContainer(at path: TreePath, depth: Int) async -> Bool {
        if liveScrollView(forScrollContainerPath: path) != nil {
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
        guard stash.refreshTreeAfterViewportMove() != nil else { return false }
        return liveScrollView(forScrollContainerPath: path) != nil
    }

    private func liveScrollView(for treeElement: InterfaceTree.Element) -> UIScrollView? {
        guard let scrollContainerPath = treeElement.scrollContainerPath else {
            return stash.liveScrollView(for: treeElement)
        }
        return liveScrollView(forScrollContainerPath: scrollContainerPath)
            ?? stash.liveScrollView(for: treeElement)
    }

    private func liveScrollView(forScrollContainerPath path: TreePath) -> UIScrollView? {
        if let scrollView = stash.capturedLiveScrollView(forContainerPath: path) {
            return scrollView
        }
        guard let remappedPath = remappedLiveScrollContainerPath(for: path) else {
            return nil
        }
        return stash.capturedLiveScrollView(forContainerPath: remappedPath)
    }

    private func remappedLiveScrollContainerPath(for path: TreePath) -> TreePath? {
        guard let expectedContainer = semanticContainer(at: path),
              expectedContainer.scrollMembership != nil,
              expectedContainer.container.isSemanticRevealScrollable
        else { return nil }

        let matches = stash.scrollableContainerViewsByPath.keys
            .sorted()
            .filter { candidatePath in
                guard candidatePath != path,
                      candidatePath.parent == path.parent,
                      let candidate = semanticContainer(at: candidatePath),
                      candidate.scrollMembership == expectedContainer.scrollMembership,
                      candidate.matchesScrollIdentity(of: expectedContainer)
                else { return false }
                return true
            }
        return matches.count == 1 ? matches[0] : nil
    }

    private func semanticContainer(at path: TreePath) -> InterfaceTree.Container? {
        stash.interfaceTree.containers[path]
            ?? stash.latestObservation.tree.containers[path]
    }
}

private extension InterfaceTree.Container {
    func matchesScrollIdentity(of other: InterfaceTree.Container) -> Bool {
        container.semanticRevealScrollContentSize == other.container.semanticRevealScrollContentSize
            && contentFrame == other.contentFrame
    }
}

private extension AccessibilityContainer {
    var isSemanticRevealScrollable: Bool {
        semanticRevealScrollContentSize != nil
    }

    var semanticRevealScrollContentSize: AccessibilitySize? {
        scrollableContentSize
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
