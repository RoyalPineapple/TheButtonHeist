#if canImport(UIKit) && DEBUG
import AccessibilitySnapshotModel
import ThePlans
import UIKit

extension ElementInflation {

    static let maxNestedRevealDepth = 8

    enum SemanticRevealFailure: Equatable, Sendable {
        case missingScrollMembership
        case noLiveScrollableAncestor
        case scanDidNotRevealTarget
    }

    enum SemanticRevealResult: Sendable {
        case alreadyVisible
        case revealed
        case failed(SemanticRevealFailure)
        case cancelled
        case timedOut

        var didReveal: Bool {
            if case .revealed = self { return true }
            return false
        }
    }

    /// Reveal an off-viewport target from the interface tree. Off-viewport
    /// elements carry no executable scroll authority unless the parser
    /// retained a live scroll ancestor.
    @discardableResult
    func revealSemanticTarget(
        _ treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline
    ) async -> SemanticRevealResult {
        let transaction = RevealTransaction()
        transaction.captureScrollableHierarchy(in: stash)
        let result = await revealSemanticTarget(
            treeElement,
            deadline: deadline,
            transaction: transaction
        )
        switch result {
        case .alreadyVisible, .revealed:
            transaction.commit()
        case .failed, .cancelled, .timedOut:
            transaction.rollBack()
        }
        return result
    }

    func revealSemanticTarget(
        _ treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> SemanticRevealResult {
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        if stash.visibleLiveElementAliasing(treeElement) != nil {
            return .alreadyVisible
        }

        guard treeElement.scrollMembership != nil else {
            return .failed(.missingScrollMembership)
        }
        if let scrollView = await revealScrollAncestors(
            for: treeElement,
            deadline: deadline,
            transaction: transaction
        ), await moveToObservedContentActivationPoint(
            treeElement,
            in: scrollView,
            deadline: deadline,
            transaction: transaction
        ) {
            return .revealed
        }
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        for _ in 0..<2 {
            transaction.captureScrollableHierarchy(in: stash)
            guard let exploredScreen = await exploration.revealKnownTarget(.init(
                heistId: treeElement.heistId,
                deadline: deadline
            )) else {
                return semanticRevealInterruption(deadline: deadline)
                    ?? .failed(.noLiveScrollableAncestor)
            }
            guard stash.semanticObservationStream.commitExploredDiscoveryObservation(exploredScreen) != nil else {
                continue
            }
            if let interruption = semanticRevealInterruption(deadline: deadline) {
                return interruption
            }
            guard stash.visibleLiveElementAliasing(treeElement) != nil else {
                return .failed(.scanDidNotRevealTarget)
            }
            return .revealed
        }
        return .failed(.scanDidNotRevealTarget)
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

    private func moveToObservedContentActivationPoint(
        _ treeElement: InterfaceTree.Element,
        in scrollView: UIScrollView,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> Bool {
        guard semanticRevealInterruption(deadline: deadline) == nil,
              let observedActivationPoint = treeElement.observedScrollContentActivationPoint else { return false }

        transaction.record(scrollView)
        scrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: scrollView),
            animated: false
        )
        guard semanticRevealInterruption(deadline: deadline) == nil else { return false }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        guard semanticRevealInterruption(deadline: deadline) == nil else { return false }
        guard stash.refreshLiveCapture() != nil else { return false }
        return semanticRevealInterruption(deadline: deadline) == nil
            && stash.visibleLiveElementAliasing(treeElement) != nil
    }

    private func revealScrollAncestors(
        for treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> UIScrollView? {
        guard semanticRevealInterruption(deadline: deadline) == nil,
              let scrollContainerPath = treeElement.scrollContainerPath else { return nil }
        return await revealScrollContainer(
            at: scrollContainerPath,
            depth: 0,
            deadline: deadline,
            transaction: transaction
        )
    }

    private func revealScrollContainer(
        at path: TreePath,
        depth: Int,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> UIScrollView? {
        guard semanticRevealInterruption(deadline: deadline) == nil,
              depth < Self.maxNestedRevealDepth else { return nil }
        guard let container = semanticContainer(at: path) else { return nil }
        guard let membership = container.scrollMembership else {
            return stash.refreshedLiveScrollView(for: container)
        }
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        guard let parentScrollView = await revealScrollContainer(
            at: membership.containerPath,
            depth: depth + 1,
            deadline: deadline,
            transaction: transaction
        ) else { return nil }
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        guard let observedActivationPoint = container.observedScrollContentActivationPoint else {
            return nil
        }

        transaction.record(parentScrollView)
        parentScrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: parentScrollView),
            animated: false
        )
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        guard semanticRevealInterruption(deadline: deadline) == nil,
              stash.refreshLiveCapture() != nil else { return nil }
        transaction.captureScrollableHierarchy(in: stash)
        return directNestedLiveScrollView(for: container, in: parentScrollView)
    }

    private func semanticRevealInterruption(
        deadline: SemanticObservationDeadline
    ) -> SemanticRevealResult? {
        if Task.isCancelled { return .cancelled }
        return deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) ? nil : .timedOut
    }

    private func directNestedLiveScrollView(
        for semanticContainer: InterfaceTree.Container,
        in parent: UIScrollView
    ) -> UIScrollView? {
        stash.refreshedLiveScrollView(for: semanticContainer, directChildOf: parent)
    }

    private func semanticContainer(at path: TreePath) -> InterfaceTree.Container? {
        stash.interfaceTree.containers[path]
    }
}

#endif // canImport(UIKit) && DEBUG
