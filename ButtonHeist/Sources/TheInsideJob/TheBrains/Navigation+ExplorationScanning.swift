#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    private enum ScanResult: Equatable {
        case foundTarget
        case completed
        case omitted(ExplorationOmissionReason)
    }

    func scanForHeistId(_ heistId: HeistId) async -> Screen? {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(
            baseline: stash.actionDiscoveryBaseline()
        )
        exploration.absorb(stash.refreshLiveCapture())
        if stash.liveContains(heistId: heistId) {
            return exploration.finish(startTime: startTime).screen
        }

        exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
        if await scanPendingContainers(target: nil, targetHeistId: heistId, exploration: &exploration) {
            return exploration.finish(startTime: startTime).screen
        }
        return nil
    }

    func scanPendingContainers(
        target: ElementTarget?,
        targetHeistId: HeistId? = nil,
        exploration: inout SemanticExploration
    ) async -> Bool {
        while !exploration.manifest.pendingContainerPaths.isEmpty {
            guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                exploration.manifest.discoveryLimitHit = true
                return false
            }

            let batch = sortedPendingContainers(in: exploration)
            guard !batch.isEmpty else {
                exploration.manifest.pendingContainerPaths.removeAll()
                return false
            }

            for container in batch {
                guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                    exploration.manifest.discoveryLimitHit = true
                    return false
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
                case .foundTarget:
                    exploration.markExplored(containerExploration.semanticContainer)
                    return true
                case .completed:
                    exploration.markExplored(containerExploration.semanticContainer)
                case .omitted(let reason):
                    exploration.manifest.markOmitted(containerExploration.path, reason: reason)
                }
                exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
            }
        }
        return false
    }

    private func sortedPendingContainers(in exploration: SemanticExploration) -> [SemanticScreen.Container] {
        exploration.manifest.pendingContainerPaths
            .compactMap { exploration.screen.semantic.containers[$0] }
            .map { PendingContainer(container: $0, overflow: totalOverflow(of: $0.container)) }
            .sorted { $0.overflow > $1.overflow }
            .map(\.container)
    }

    private func prepareContainerExploration(
        for semanticContainer: SemanticScreen.Container
    ) -> ContainerExploration? {
        let container = semanticContainer.container
        guard case .scrollable(let contentSize) = container.type else { return nil }

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
        target: ElementTarget?,
        targetHeistId: HeistId?,
        exploration: inout SemanticExploration
    ) async -> ScanResult {
        let savedVisualOrigin = containerExploration.savedVisualOrigin

        if shouldSkipFullScanByInventory(containerExploration, target: target, targetHeistId: targetHeistId, exploration: exploration) {
            return .omitted(.containerScrollLimit)
        }

        for offset in scanOffsets(for: containerExploration) {
            if let reason = exploration.manifest.recordScrollAttempt(in: containerExploration.path) {
                await restoreContainerPosition(containerExploration, savedVisualOrigin: savedVisualOrigin, exploration: &exploration)
                return .omitted(reason)
            }
            containerExploration.scrollView.setContentOffset(offset, animated: false)
            await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            absorbExplorationPage(in: &exploration)

            if targetWasFound(target: target, targetHeistId: targetHeistId, in: exploration.screen) {
                return .foundTarget
            }
        }

        await restoreContainerPosition(containerExploration, savedVisualOrigin: savedVisualOrigin, exploration: &exploration)
        return .completed
    }

    private func shouldSkipFullScanByInventory(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        targetHeistId: HeistId?,
        exploration: SemanticExploration
    ) -> Bool {
        guard target == nil,
              targetHeistId == nil,
              let totalElementCount = containerExploration.semanticContainer.scrollInventory?.totalElementCount
        else { return false }
        let visibleCount = max(1, containerExploration.semanticContainer.scrollInventory?.visibleIndices.count ?? 1)
        return totalElementCount > visibleCount * exploration.manifest.maxScrollsPerContainer
    }

    private func scanOffsets(for containerExploration: ContainerExploration) -> [CGPoint] {
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
                axis: .vertical
            )
        }

        let step = max(1, bounds.width * 0.8)
        return axisOffsets(
            current: current,
            minOffset: minOffset,
            maxOffset: maxOffset,
            step: step,
            axis: .horizontal
        )
    }

    private func axisOffsets(
        current: CGPoint,
        minOffset: CGPoint,
        maxOffset: CGPoint,
        step: CGFloat,
        axis: ScanAxis
    ) -> [CGPoint] {
        let currentScalar = axis.scalar(from: current)
        let minScalar = axis.scalar(from: minOffset)
        let maxScalar = axis.scalar(from: maxOffset)

        let forward = strideOffsets(
            from: currentScalar + step,
            through: maxScalar,
            by: step,
            current: current,
            axis: axis
        )
        let backward = strideOffsets(
            from: currentScalar - step,
            through: minScalar,
            by: -step,
            current: current,
            axis: axis
        )
        let edgeForward = axis.point(updating: current, scalar: maxScalar)
        let edgeBackward = axis.point(updating: current, scalar: minScalar)

        return dedupedOffsets(forward + [edgeForward] + backward + [edgeBackward])
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
        var seen = Set<CoarseOffset>()
        return offsets.filter { seen.insert(CoarseOffset($0)).inserted }
    }

    private func targetWasFound(
        target: ElementTarget?,
        targetHeistId: HeistId?,
        in screen: Screen
    ) -> Bool {
        if let targetHeistId, screen.liveCapture.contains(heistId: targetHeistId) {
            return true
        }
        if let target {
            return hasVisibleTerminalExplorationResolution(target)
        }
        return false
    }

    private func absorbExplorationPage(in exploration: inout SemanticExploration) {
        exploration.absorb(stash.semanticPageForExploration())
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
        guard case .scrollable(let contentSize) = container.type else { return 0 }
        return max(0, contentSize.width - container.frame.width)
            + max(0, contentSize.height - container.frame.height)
    }

    static func hasContentBeyondFrame(
        of container: AccessibilityContainer,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let path = hierarchy.containerPaths.first(where: { $0.container == container })?.path else {
            return false
        }
        return hasContentBeyondFrame(of: path, in: hierarchy, tolerance: tolerance)
    }

    static func hasContentBeyondFrame(
        of containerPath: TreePath,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        guard case .container(let container, _) = hierarchy.node(at: containerPath) else {
            return false
        }
        let containerFrame = container.frame
        let hits: [Bool] = hierarchy.compactMapSubtrees { node, path -> Bool? in
            guard path != containerPath,
                  path.hasPrefix(containerPath),
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
        let container: SemanticScreen.Container
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

private extension Array where Element == AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return nil }
        guard path.indices.count > 1 else { return self[rootIndex] }
        return self[rootIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }
}

private extension AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard !path.indices.isEmpty else { return self }
        guard case .container(_, let children) = self,
              let childIndex = path.indices.first,
              children.indices.contains(childIndex)
        else { return nil }
        return children[childIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
