#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ButtonHeistSupport

import TheScore
import ThePlans

extension Navigation {

    func scanForHeistId(_ heistId: HeistId) async -> ExploredScreen? {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(
            baseline: stash.actionDiscoveryBaseline()
        )
        exploration.absorb(stash.refreshLiveCapture())
        if stash.liveContains(heistId: heistId) {
            return exploration.finish(startTime: startTime)
        }

        exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
        if await scanPendingContainers(target: nil, targetHeistId: heistId, exploration: &exploration) != nil {
            return exploration.finish(startTime: startTime)
        }
        return nil
    }

    func scanPendingContainers(
        target: AccessibilityTarget?,
        targetHeistId: HeistId? = nil,
        exploration: inout SemanticExploration
    ) async -> ScrollTraversalTerminal? {
        while !exploration.manifest.pendingScrollPaths.isEmpty {
            guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                exploration.manifest.markDiscoveryLimitHit()
                return nil
            }

            let batch = sortedPendingContainers(in: exploration)
            guard !batch.isEmpty else {
                exploration.manifest.clearPendingContainers()
                return nil
            }

            for container in batch {
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
        target: AccessibilityTarget?,
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
            switch effect {
            case .run(let direction):
                let outcome = await runScrollScan(
                    ScrollScanPlan(container: containerExploration, direction: direction, goal: goal),
                    exploration: &exploration
                )
                effect = driver.send(.scanCompleted(outcome)).scrollContainerScanEffect

            case .restore:
                await restoreContainerPosition(
                    containerExploration,
                    savedVisualOrigin: savedVisualOrigin,
                    exploration: &exploration
                )
                effect = driver.send(.restoreCompleted).scrollContainerScanEffect

            case .finish(let result):
                return result
            }
        }
    }

    private func scanGoal(target: AccessibilityTarget?, targetHeistId: HeistId?) -> ScrollScanGoal {
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
        if let terminal = scanGoalTerminal(plan.goal, in: exploration.screen) {
            return .terminal(terminal)
        }

        for offset in scanOffsets(for: plan.container, direction: plan.direction) {
            if let reason = exploration.manifest.recordScrollAttempt(in: plan.container.path) {
                return .limitHit(reason)
            }
            plan.container.scrollView.setContentOffset(offset, animated: plan.animated)
            if plan.animated {
                _ = await tripwire.waitForAllClear(timeout: 0.5)
            } else {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            }
            absorbExplorationPage(in: &exploration)

            if let terminal = scanGoalTerminal(plan.goal, in: exploration.screen) {
                return .terminal(terminal)
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

    private func scanOffsets(for containerExploration: ContainerExploration, direction: ScrollScanDirection) -> [CGPoint] {
        let scrollView = containerExploration.scrollView
        let current = scrollView.contentOffset
        let bounds = scrollView.bounds
        let insets = scrollView.adjustedContentInset
        let minOffset = CGPoint(x: -insets.left, y: -insets.top)
        let maxOffset = CGPoint(
            x: max(scrollView.contentSize.width + insets.right - bounds.width, -insets.left),
            y: max(scrollView.contentSize.height + insets.bottom - bounds.height, -insets.top)
        )

        if containerExploration.hasVOverflow {
            let step = max(1, bounds.height * 0.8)
            return axisOffsets(
                current: current,
                minOffset: minOffset,
                maxOffset: maxOffset,
                step: step,
                axis: .vertical,
                direction: direction
            )
        }

        let step = max(1, bounds.width * 0.8)
        return axisOffsets(
            current: current,
            minOffset: minOffset,
            maxOffset: maxOffset,
            step: step,
            axis: .horizontal,
            direction: direction
        )
    }

    private func axisOffsets(
        current: CGPoint,
        minOffset: CGPoint,
        maxOffset: CGPoint,
        step: CGFloat,
        axis: ScanAxis,
        direction: ScrollScanDirection
    ) -> [CGPoint] {
        let currentScalar = axis.scalar(from: current)
        let minScalar = axis.scalar(from: minOffset)
        let maxScalar = axis.scalar(from: maxOffset)

        let offsets: [CGPoint]
        let edge: CGPoint
        switch direction {
        case .forward:
            offsets = strideOffsets(
                from: currentScalar + step,
                through: maxScalar,
                by: step,
                current: current,
                axis: axis
            )
            edge = axis.point(updating: current, scalar: maxScalar)
        case .back:
            offsets = strideOffsets(
                from: currentScalar - step,
                through: minScalar,
                by: -step,
                current: current,
                axis: axis
            )
            edge = axis.point(updating: current, scalar: minScalar)
        }

        return dedupedOffsets(offsets + [edge])
            .filter { axis.scalar(from: $0) >= minScalar && axis.scalar(from: $0) <= maxScalar }
            .filter { axis.scalar(from: $0) != currentScalar }
    }

    private func strideOffsets(
        from start: CGFloat,
        through end: CGFloat,
        by step: CGFloat,
        current: CGPoint,
        axis: ScanAxis
    ) -> [CGPoint] {
        guard step != 0 else { return [] }
        var values: [CGPoint] = []
        var value = start
        if step > 0 {
            while value <= end {
                values.append(axis.point(updating: current, scalar: value))
                value += step
            }
        } else {
            while value >= end {
                values.append(axis.point(updating: current, scalar: value))
                value += step
            }
        }
        return values
    }

    private func dedupedOffsets(_ offsets: [CGPoint]) -> [CGPoint] {
        offsets.uniqued(on: CoarseOffset.init)
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

    private func absorbExplorationPage(in exploration: inout SemanticExploration) {
        exploration.absorb(stash.semanticPageForExploration())
        stash.semanticObservationStream.commitSettledDiscoveryObservation(exploration.screen)
    }

    private func restoreContainerPosition(
        _ containerExploration: ContainerExploration,
        savedVisualOrigin: CGPoint,
        exploration: inout SemanticExploration
    ) async {
        Self.restoreVisualOrigin(savedVisualOrigin, in: containerExploration.scrollView)
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        absorbExplorationPage(in: &exploration)
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
        return hasContentBeyondFrame(of: path, in: hierarchy, tolerance: tolerance)
    }

    static func hasContentBeyondFrame(
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

    private enum ScanAxis {
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

    private struct CoarseOffset: Hashable {
        let x: Int
        let y: Int

        init(_ point: CGPoint) {
            x = Int(point.x.rounded())
            y = Int(point.y.rounded())
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
