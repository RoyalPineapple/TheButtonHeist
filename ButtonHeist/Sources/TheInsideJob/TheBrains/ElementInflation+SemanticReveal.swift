#if canImport(UIKit) && DEBUG
import AccessibilitySnapshotModel
import ThePlans
import UIKit

extension ElementInflation {

    private struct SemanticRevealMovement {
        let scrollView: UIScrollView
        let visualOrigin: CGPoint
    }

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
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        if let visible = stash.liveInterfaceElement(heistId: treeElement.heistId),
           visible.element.representsSameSemanticElement(as: treeElement.element) {
            return .alreadyVisible
        }

        guard treeElement.scrollMembership != nil else {
            return .failed(.missingScrollMembership)
        }
        var movements: [SemanticRevealMovement] = []
        if let scrollView = await revealScrollAncestors(
            for: treeElement,
            deadline: deadline,
            movements: &movements
        ), await moveToObservedContentActivationPoint(
            treeElement,
            in: scrollView,
            deadline: deadline,
            movements: &movements
        ) {
            return .revealed
        }
        restoreSemanticRevealMovements(movements)
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        guard let exploredScreen = await exploration.revealKnownTarget(.init(
            heistId: treeElement.heistId,
            deadline: deadline
        )) else {
            return semanticRevealInterruption(deadline: deadline)
                ?? .failed(.noLiveScrollableAncestor)
        }
        stash.semanticObservationStream.commitSettledDiscoveryObservation(.explored(exploredScreen))
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
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

    private func moveToObservedContentActivationPoint(
        _ treeElement: InterfaceTree.Element,
        in scrollView: UIScrollView,
        deadline: SemanticObservationDeadline,
        movements: inout [SemanticRevealMovement]
    ) async -> Bool {
        guard semanticRevealInterruption(deadline: deadline) == nil,
              let observedActivationPoint = treeElement.observedScrollContentActivationPoint else { return false }

        recordSemanticRevealMovement(of: scrollView, in: &movements)
        scrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: scrollView),
            animated: false
        )
        guard semanticRevealInterruption(deadline: deadline) == nil else { return false }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        guard semanticRevealInterruption(deadline: deadline) == nil else { return false }
        guard stash.refreshLiveCapture() != nil else { return false }
        return semanticRevealInterruption(deadline: deadline) == nil
    }

    private func revealScrollAncestors(
        for treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline,
        movements: inout [SemanticRevealMovement]
    ) async -> UIScrollView? {
        guard semanticRevealInterruption(deadline: deadline) == nil,
              let scrollContainerPath = treeElement.scrollContainerPath else { return nil }
        return await revealScrollContainer(
            at: scrollContainerPath,
            depth: 0,
            deadline: deadline,
            movements: &movements
        )
    }

    private func revealScrollContainer(
        at path: TreePath,
        depth: Int,
        deadline: SemanticObservationDeadline,
        movements: inout [SemanticRevealMovement]
    ) async -> UIScrollView? {
        guard semanticRevealInterruption(deadline: deadline) == nil,
              depth < Self.maxNestedRevealDepth else { return nil }
        guard let container = semanticContainer(at: path) else { return nil }
        guard let membership = container.scrollMembership else {
            return stash.liveScrollView(forContainerPath: path)
        }
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        guard let parentScrollView = await revealScrollContainer(
            at: membership.containerPath,
            depth: depth + 1,
            deadline: deadline,
            movements: &movements
        ) else { return nil }
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        if stash.liveScrollableContainerView(forPath: path) === parentScrollView {
            return parentScrollView
        }
        guard let observedActivationPoint = container.observedScrollContentActivationPoint else {
            return nil
        }

        recordSemanticRevealMovement(of: parentScrollView, in: &movements)
        parentScrollView.setContentOffset(
            Self.semanticRevealTargetOffset(for: observedActivationPoint, in: parentScrollView),
            animated: false
        )
        guard semanticRevealInterruption(deadline: deadline) == nil else { return nil }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        guard semanticRevealInterruption(deadline: deadline) == nil,
              stash.refreshLiveCapture() != nil else { return nil }
        return directNestedLiveScrollView(in: parentScrollView)
    }

    private func recordSemanticRevealMovement(
        of scrollView: UIScrollView,
        in movements: inout [SemanticRevealMovement]
    ) {
        guard !movements.contains(where: { $0.scrollView === scrollView }) else { return }
        movements.append(SemanticRevealMovement(
            scrollView: scrollView,
            visualOrigin: Navigation.visualOrigin(in: scrollView)
        ))
    }

    private func restoreSemanticRevealMovements(_ movements: [SemanticRevealMovement]) {
        for movement in movements.reversed() {
            Navigation.restoreVisualOrigin(movement.visualOrigin, in: movement.scrollView)
        }
    }

    private func semanticRevealInterruption(
        deadline: SemanticObservationDeadline
    ) -> SemanticRevealResult? {
        if Task.isCancelled { return .cancelled }
        return deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) ? nil : .timedOut
    }

    private func directNestedLiveScrollView(in parent: UIScrollView) -> UIScrollView? {
        let currentScrollViews = Array(stash.scrollableContainerViewsByPath.values)
        guard currentScrollViews.contains(where: { $0 === parent }) else { return nil }

        var seen = Set<ObjectIdentifier>()
        let matches = currentScrollViews.filter { candidate in
            guard candidate !== parent,
                  seen.insert(ObjectIdentifier(candidate)).inserted
            else { return false }
            return candidate.nearestScrollableSuperview === parent
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func semanticContainer(at path: TreePath) -> InterfaceTree.Container? {
        stash.interfaceTree.containers[path]
    }
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

private extension AccessibilityElement {
    func representsSameSemanticElement(as other: AccessibilityElement) -> Bool {
        label == other.label
            && identifier == other.identifier
            && value == other.value
            && traits == other.traits
    }
}

#endif // canImport(UIKit) && DEBUG
