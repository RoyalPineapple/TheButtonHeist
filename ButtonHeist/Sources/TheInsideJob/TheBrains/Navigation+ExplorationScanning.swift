#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ButtonHeistSupport

import TheScore
import ThePlans

extension Navigation {

    func scanForHeistId(
        _ heistId: HeistId,
        deadline: SemanticObservationDeadline
    ) async -> ExploredScreen? {
        guard !Task.isCancelled,
              deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(
            baseline: stash.actionDiscoveryBaseline(),
            knownTargetDeadline: deadline
        )
        guard let settledPage = await settledKnownTargetPage(deadline: deadline),
              !Task.isCancelled,
              deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        exploration.absorb(settledPage)
        if stash.liveContains(heistId: heistId) {
            return exploration.finish(startTime: startTime)
        }

        exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
        let terminal = await scanPendingContainers(target: nil, targetHeistId: heistId, exploration: &exploration)
        guard !Task.isCancelled,
              deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        if terminal != nil {
            return exploration.finish(startTime: startTime)
        }
        return nil
    }

    func scanPendingContainers(
        target: ResolvedAccessibilityTarget?,
        targetHeistId: HeistId? = nil,
        exploration: inout SemanticExploration
    ) async -> ScrollTraversalTerminal? {
        while !exploration.manifest.pendingScrollPaths.isEmpty {
            guard !Task.isCancelled, exploration.hasTimeRemaining else { return nil }
            guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                exploration.manifest.markDiscoveryLimitHit()
                return nil
            }

            let batch = sortedPendingContainers(in: exploration)
            guard !batch.isEmpty else {
                exploration.manifest.clearPendingContainers()
                return nil
            }

            containerBatch: for container in batch {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return nil }
                guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                    exploration.manifest.markDiscoveryLimitHit()
                    return nil
                }
                guard let containerExploration = prepareContainerExploration(for: container) else {
                    exploration.markExplored(container)
                    continue
                }

                let result = await scanContainer(
                    containerExploration,
                    target: target,
                    targetHeistId: targetHeistId,
                    exploration: &exploration
                )
                switch result {
                case .terminal(let terminal):
                    exploration.markExplored(containerExploration.semanticContainer)
                    return terminal
                case .completed:
                    exploration.markExplored(containerExploration.semanticContainer)
                case .screenReplaced:
                    if let terminal = scanGoalTerminal(
                        scanGoal(target: target, targetHeistId: targetHeistId),
                        in: exploration.screen
                    ) {
                        return terminal
                    }
                    break containerBatch
                case .omitted(let reason):
                    exploration.manifest.markOmitted(containerExploration.path, reason: reason)
                }
                exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
            }
        }
        return nil
    }

    private func sortedPendingContainers(in exploration: SemanticExploration) -> [InterfaceTree.Container] {
        exploration.manifest.pendingScrollPaths
            .compactMap { exploration.screen.tree.containers[$0] }
            .map { PendingContainer(container: $0, overflow: totalOverflow(of: $0.container)) }
            .sorted { $0.overflow > $1.overflow }
            .map(\.container)
    }

    private func prepareContainerExploration(
        for semanticContainer: InterfaceTree.Container
    ) -> ContainerExploration? {
        let container = semanticContainer.container
        guard let contentSize = container.scrollableContentSize else { return nil }

        guard let scrollView = stash.liveScrollableContainerView(forPath: semanticContainer.path),
              scrollView.window != nil,
              !scrollView.bhIsUnsafeForProgrammaticScrolling,
              !Self.isObscuredByPresentation(view: scrollView)
        else { return nil }

        let hasHOverflow = contentSize.width > container.frame.width + 1
        let hasVOverflow = contentSize.height > container.frame.height + 1
        guard hasHOverflow || hasVOverflow else { return nil }

        return ContainerExploration(
            semanticContainer: semanticContainer,
            scrollView: scrollView,
            hasHOverflow: hasHOverflow,
            hasVOverflow: hasVOverflow
        )
    }

    private func scanContainer(
        _ containerExploration: ContainerExploration,
        target: ResolvedAccessibilityTarget?,
        targetHeistId: HeistId?,
        exploration: inout SemanticExploration
    ) async -> ScrollContainerScanResult {
        let savedVisualOrigin = containerExploration.savedVisualOrigin
        let goal = scanGoal(target: target, targetHeistId: targetHeistId)

        if shouldSkipFullScanByInventory(containerExploration, goal: goal, exploration: exploration) {
            return .omitted(.containerScrollLimit)
        }

        var driver = StateDriver(
            initial: ScrollContainerScanState.idle,
            machine: ScrollContainerScanMachine()
        )
        var effect = driver.send(.begin).scrollContainerScanEffect
        while true {
            guard !Task.isCancelled, exploration.hasTimeRemaining else {
                restoreKnownTargetOriginIfNeeded(
                    savedVisualOrigin,
                    containerExploration: containerExploration,
                    exploration: exploration
                )
                return .completed
            }
            switch effect {
            case .run(let direction):
                let outcome = await runScrollScan(
                    ScrollScanPlan(container: containerExploration, direction: direction, goal: goal),
                    exploration: &exploration
                )
                effect = driver.send(.scanCompleted(outcome)).scrollContainerScanEffect

            case .restore:
                let classification = await restoreContainerPosition(
                    containerExploration,
                    savedVisualOrigin: savedVisualOrigin,
                    exploration: &exploration
                )
                if classification?.isScreenReplacement == true {
                    return .screenReplaced
                }
                effect = driver.send(.restoreCompleted).scrollContainerScanEffect

            case .finish(let result):
                return result
            }
        }
    }

    private func restoreKnownTargetOriginIfNeeded(
        _ savedVisualOrigin: CGPoint,
        containerExploration: ContainerExploration,
        exploration: SemanticExploration
    ) {
        guard case .knownTargetReveal = exploration.scope else { return }
        Self.restoreVisualOrigin(savedVisualOrigin, in: containerExploration.scrollView)
    }

    private func scanGoal(target: ResolvedAccessibilityTarget?, targetHeistId: HeistId?) -> ScrollScanGoal {
        if let target {
            return .findTarget(target)
        }
        if let targetHeistId {
            return .findHeistId(targetHeistId)
        }
        return .exhaust
    }

    private func runScrollScan(
        _ plan: ScrollScanPlan,
        exploration: inout SemanticExploration
    ) async -> ScrollScanOutcome {
        guard !Task.isCancelled, exploration.hasTimeRemaining else { return .exhausted }
        if let terminal = scanGoalTerminal(plan.goal, in: exploration.screen) {
            return .terminal(terminal)
        }

        // Lazy containers can revise contentSize as each viewport materializes.
        // Derive one offset at a time from the geometry proven by the last page.
        while let offset = Self.nextExplorationScanOffset(
            in: plan.container.scrollView,
            axis: plan.container.hasVOverflow ? .vertical : .horizontal,
            direction: plan.direction
        ) {
            observeOffset: while true {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .exhausted }
                if let reason = exploration.manifest.recordScrollAttempt(in: plan.container.path) {
                    return .limitHit(reason)
                }
                let classification: ScreenClassifier.Classification?
                do {
                    let notificationWindow = stash.accessibilityNotifications.beginActionWindow()
                    defer { notificationWindow.cancel() }
                    plan.container.scrollView.setContentOffset(offset, animated: plan.animated)
                    guard !Task.isCancelled, exploration.hasTimeRemaining else { return .exhausted }
                    if plan.animated {
                        _ = await tripwire.waitForAllClear(timeout: exploration.cappedAnimatedWait(0.5))
                    } else {
                        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                    }
                    guard !Task.isCancelled, exploration.hasTimeRemaining else { return .exhausted }
                    classification = await absorbExplorationPage(
                        in: &exploration,
                        notificationBatch: notificationWindow.capture()
                    )
                }
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .exhausted }
                guard let classification else { continue observeOffset }
                if classification.isScreenReplacement { return .screenReplaced }

                if let terminal = scanGoalTerminal(plan.goal, in: exploration.screen) {
                    return .terminal(terminal)
                }
                break observeOffset
            }
        }

        return .exhausted
    }

    private func shouldSkipFullScanByInventory(
        _ containerExploration: ContainerExploration,
        goal: ScrollScanGoal,
        exploration: SemanticExploration
    ) -> Bool {
        guard goal == .exhaust,
              let totalElementCount = containerExploration.semanticContainer.scrollInventory?.totalElementCount
        else { return false }
        let visibleCount = max(1, containerExploration.semanticContainer.scrollInventory?.visibleIndices.count ?? 1)
        return totalElementCount > visibleCount * exploration.manifest.maxScrollsPerContainer
    }

    static func nextExplorationScanOffset(
        in scrollView: UIScrollView,
        axis: ScanAxis,
        direction: ScrollScanDirection
    ) -> CGPoint? {
        let current = scrollView.contentOffset
        let bounds = scrollView.bounds
        let insets = scrollView.adjustedContentInset
        let minOffset = CGPoint(x: -insets.left, y: -insets.top)
        let maxOffset = CGPoint(
            x: max(scrollView.contentSize.width + insets.right - bounds.width, -insets.left),
            y: max(scrollView.contentSize.height + insets.bottom - bounds.height, -insets.top)
        )
        let currentScalar = axis.scalar(from: current)
        let minScalar = axis.scalar(from: minOffset)
        let maxScalar = axis.scalar(from: maxOffset)
        let clampedCurrent = min(max(currentScalar, minScalar), maxScalar)
        let step = max(1, axis.scalar(from: CGPoint(x: bounds.width, y: bounds.height)) * 0.8)
        let nextScalar: CGFloat = switch direction {
        case .forward:
            min(clampedCurrent + step, maxScalar)
        case .back:
            max(clampedCurrent - step, minScalar)
        }
        guard Int(nextScalar.rounded()) != Int(currentScalar.rounded()) else { return nil }
        return axis.point(updating: current, scalar: nextScalar)
    }

    private func scanGoalTerminal(
        _ goal: ScrollScanGoal,
        in screen: InterfaceObservation
    ) -> ScrollTraversalTerminal? {
        switch goal {
        case .exhaust:
            return nil
        case .findHeistId(let targetHeistId):
            guard screen.liveCapture.contains(heistId: targetHeistId) else { return nil }
            return .foundHeistId(targetHeistId)
        case .findTarget(let target):
            guard hasVisibleTerminalExplorationResolution(target, in: screen.tree) else { return nil }
            return .foundTarget(target)
        }
    }

    private func absorbExplorationPage(
        in exploration: inout SemanticExploration,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> ScreenClassifier.Classification? {
        guard !Task.isCancelled, exploration.hasTimeRemaining else { return nil }
        let page: InterfaceObservation?
        switch exploration.scope {
        case .manifestBoundedDiscovery:
            page = await settledExplorationPage()
        case .knownTargetReveal(let deadline):
            page = await settledKnownTargetPage(deadline: deadline)
        }
        guard !Task.isCancelled, exploration.hasTimeRemaining else { return nil }
        guard let page else { return nil }
        return exploration.absorbScrolledPage(page, notificationBatch: notificationBatch)
    }

    private func restoreContainerPosition(
        _ containerExploration: ContainerExploration,
        savedVisualOrigin: CGPoint,
        exploration: inout SemanticExploration
    ) async -> ScreenClassifier.Classification? {
        let notificationWindow = stash.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        Self.restoreVisualOrigin(savedVisualOrigin, in: containerExploration.scrollView)
        guard !Task.isCancelled, exploration.hasTimeRemaining else { return nil }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        guard !Task.isCancelled, exploration.hasTimeRemaining else { return nil }
        return await absorbExplorationPage(
            in: &exploration,
            notificationBatch: notificationWindow.capture()
        )
    }

    private func settledKnownTargetPage(
        deadline: SemanticObservationDeadline
    ) async -> InterfaceObservation? {
        guard !Task.isCancelled,
              deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        let timeoutMs = min(
            SettleSession.defaultTimeoutMs,
            max(1, Int((deadline.remainingSeconds() * 1_000).rounded(.up)))
        )
        let settle = await SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: timeoutMs
        ).run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: tripwire.tripwireSignal()
        )
        guard !Task.isCancelled,
              deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        return InterfaceObservationProof.settled(settle, stash: stash)?.screen
    }

    static func restoreVisualOrigin(_ visualOrigin: CGPoint, in scrollView: UIScrollView) {
        let insets = scrollView.adjustedContentInset
        let restoredOffset = CGPoint(
            x: visualOrigin.x - insets.left,
            y: visualOrigin.y - insets.top
        )
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        let clampedOffset = CGPoint(
            x: max(-insets.left, min(restoredOffset.x, maxX)),
            y: max(-insets.top, min(restoredOffset.y, maxY))
        )
        scrollView.setContentOffset(clampedOffset, animated: false)
    }

    static func visualOrigin(in scrollView: UIScrollView) -> CGPoint {
        CGPoint(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        )
    }

    private func totalOverflow(of container: AccessibilityContainer) -> CGFloat {
        guard let contentSize = container.scrollableContentSize else { return 0 }
        return max(0, contentSize.width - container.frame.width)
            + max(0, contentSize.height - container.frame.height)
    }

    static func hasContentBeyondFrame(
        of container: AccessibilityContainer,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let path = hierarchy.pathIndexedContainers.first(where: { $0.container == container })?.path else {
            return false
        }
        return hasDescendantBeyondFrame(of: path, in: hierarchy, tolerance: tolerance)
    }

    private static func hasDescendantBeyondFrame(
        of containerPath: TreePath,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let subtree = hierarchy.node(at: containerPath),
              case .container(let container, _) = subtree
        else {
            return false
        }
        let containerFrame = container.frame
        let hits: [Bool] = subtree.compactMapSubtrees(path: containerPath) { node, path -> Bool? in
            guard path != containerPath,
                  case .element(let element, _) = node
            else {
                return nil
            }
            let elementFrame = element.shape.frame
            let extendsBeyond =
                elementFrame.minX < containerFrame.minX - tolerance
                || elementFrame.minY < containerFrame.minY - tolerance
                || elementFrame.maxX > containerFrame.maxX + tolerance
                || elementFrame.maxY > containerFrame.maxY + tolerance
            return extendsBeyond ? true : nil
        }
        return !hits.isEmpty
    }

    private struct PendingContainer {
        let container: InterfaceTree.Container
        let overflow: CGFloat
    }

    enum ScanAxis {
        case horizontal
        case vertical

        func scalar(from point: CGPoint) -> CGFloat {
            switch self {
            case .horizontal:
                return point.x
            case .vertical:
                return point.y
            }
        }

        func point(updating point: CGPoint, scalar: CGFloat) -> CGPoint {
            switch self {
            case .horizontal:
                return CGPoint(x: scalar, y: point.y)
            case .vertical:
                return CGPoint(x: point.x, y: scalar)
            }
        }
    }

}

private extension StateChange
where State == Navigation.ScrollContainerScanState,
      Effect == Navigation.ScrollContainerScanEffect,
      Rejection == Navigation.ScrollContainerScanRejection {

    var scrollContainerScanEffect: Navigation.ScrollContainerScanEffect {
        guard let effect = singleEffect else {
            preconditionFailure("ScrollContainerScanMachine must emit exactly one effect per accepted event.")
        }
        return effect
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
