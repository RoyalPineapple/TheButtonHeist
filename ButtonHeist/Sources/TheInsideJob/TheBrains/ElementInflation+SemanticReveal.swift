#if canImport(UIKit) && DEBUG
import AccessibilitySnapshotModel
import ThePlans
import UIKit

extension ElementInflation {

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
            await transaction.rollBack(using: exploration.moveViewport)
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
        ), let observedPoint = treeElement.observedScrollContentActivationPoint,
           await moveToObservedContentPoint(
               observedPoint,
               in: scrollView,
               deadline: deadline,
               transaction: transaction
           ), stash.visibleLiveElementAliasing(treeElement) != nil {
            return .revealed
        }
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        transaction.captureScrollableHierarchy(in: stash)
        guard await exploration.revealKnownTarget(.init(
            heistId: treeElement.heistId,
            deadline: deadline
        )) != nil else {
            return semanticRevealInterruption(deadline: deadline)
                ?? .failed(.noLiveScrollableAncestor)
        }
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        guard stash.visibleLiveElementAliasing(treeElement) != nil else {
            return .failed(.scanDidNotRevealTarget)
        }
        return .revealed
    }

    private func revealScrollAncestors(
        for treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> UIScrollView? {
        guard let path = treeElement.scrollContainerPath else { return nil }
        return await revealScrollContainer(
            at: path,
            visited: [],
            deadline: deadline,
            transaction: transaction
        )
    }

    private func revealScrollContainer(
        at path: TreePath,
        visited: Set<TreePath>,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> UIScrollView? {
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        var visited = visited
        guard visited.insert(path).inserted,
              let container = stash.interfaceTree.containers[path]
        else { return nil }
        guard let membership = container.scrollMembership else {
            return stash.refreshedLiveScrollView(for: container)
        }
        guard let parent = await revealScrollContainer(
            at: membership.containerPath,
            visited: visited,
            deadline: deadline,
            transaction: transaction
        ), let observedPoint = container.observedScrollContentActivationPoint,
           await moveToObservedContentPoint(
               observedPoint,
               in: parent,
               deadline: deadline,
               transaction: transaction
           )
        else { return nil }

        transaction.captureScrollableHierarchy(in: stash)
        return stash.refreshedLiveScrollView(for: container, directChildOf: parent)
    }

    private func moveToObservedContentPoint(
        _ observedPoint: InterfaceTree.ObservedScrollContentActivationPoint,
        in scrollView: UIScrollView,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> Bool {
        guard semanticRevealInterruption(deadline: deadline) == nil else { return false }
        transaction.record(scrollView)
        let transition = await exploration.moveViewport(
            .revealContentPoint(observedPoint.point, in: scrollView)
        )
        guard semanticRevealInterruption(deadline: deadline) == nil else { return false }
        switch transition.result {
        case .unavailable:
            return false
        case .unchanged:
            return true
        case .moved:
            guard let event = transition.event else { return false }
            return !event.continuity.isReplacement
        }
    }

    private func semanticRevealInterruption(
        deadline: SemanticObservationDeadline
    ) -> SemanticRevealResult? {
        if Task.isCancelled { return .cancelled }
        return deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) ? nil : .timedOut
    }
}

#endif // canImport(UIKit) && DEBUG
