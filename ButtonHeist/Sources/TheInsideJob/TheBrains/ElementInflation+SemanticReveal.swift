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

    /// Reveal a known target from the current graph. Known-only semantic
    /// elements carry no executable scroll authority unless the parser
    /// retained a live scroll ancestor.
    @discardableResult
    func revealSemanticTarget(_ screenElement: TheStash.ScreenElement) async -> SemanticRevealResult {
        if let visible = stash.liveScreenElement(heistId: screenElement.heistId),
           visible.element.representsSameSemanticElement(as: screenElement.element) {
            return .alreadyVisible
        }

        guard screenElement.scrollMembership != nil else {
            return .failed(.missingScrollMembership)
        }
        if await revealScrollAncestors(for: screenElement),
           await moveToObservedContentActivationPoint(screenElement) {
            return .revealed
        }
        guard let revealedScreen = await revealKnownTarget?(screenElement.heistId) else {
            return .failed(.noLiveScrollableAncestor)
        }
        stash.semanticObservationStream.commitSettledDiscoveryObservation(revealedScreen)
        guard let visible = stash.liveScreenElement(heistId: screenElement.heistId),
              visible.element.representsSameSemanticElement(as: screenElement.element)
        else {
            return .failed(.scanDidNotRevealTarget)
        }
        return .revealed
    }

    static func semanticRevealTargetOffset(
        for observedActivationPoint: Screen.ObservedScrollContentActivationPoint,
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

    private func moveToObservedContentActivationPoint(_ screenElement: TheStash.ScreenElement) async -> Bool {
        guard let observedActivationPoint = screenElement.observedScrollContentActivationPoint,
              let scrollView = liveScrollView(for: screenElement)
        else { return false }

        scrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: scrollView),
            animated: false
        )
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        stash.refreshTreeAfterViewportMove()
        return true
    }

    private func revealScrollAncestors(for screenElement: TheStash.ScreenElement) async -> Bool {
        guard let scrollContainerPath = screenElement.scrollContainerPath else { return false }
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

    private func liveScrollView(for screenElement: TheStash.ScreenElement) -> UIScrollView? {
        guard let scrollContainerPath = screenElement.scrollContainerPath else {
            return stash.liveScrollView(for: screenElement)
        }
        return liveScrollView(forScrollContainerPath: scrollContainerPath)
            ?? stash.liveScrollView(for: screenElement)
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

    private func semanticContainer(at path: TreePath) -> SemanticScreen.Container? {
        stash.settledSemanticScreen.semantic.containers[path]
            ?? stash.latestObservedSemanticWorld.containers[path]
    }
}

private extension SemanticScreen.Container {
    func matchesScrollIdentity(of other: SemanticScreen.Container) -> Bool {
        container.semanticRevealScrollContentSize == other.container.semanticRevealScrollContentSize
            && contentFrame == other.contentFrame
    }
}

private extension AccessibilityContainer {
    var isSemanticRevealScrollable: Bool {
        semanticRevealScrollContentSize != nil
    }

    var semanticRevealScrollContentSize: AccessibilitySize? {
        guard case .scrollable(let contentSize) = type else { return nil }
        return contentSize
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
