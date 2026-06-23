#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    func scanPendingContainers(
        target: ElementTarget?,
        exploration: inout SemanticExploration
    ) async -> Bool {
        while !exploration.manifest.pendingContainers.isEmpty {
            guard exploration.manifest.scrollCount < ScreenManifest.maxScrollsPerDiscovery else {
                return false
            }
            let batch = sortedPendingContainers(in: exploration)

            for container in batch {
                guard exploration.manifest.scrollCount < ScreenManifest.maxScrollsPerDiscovery else {
                    return false
                }
                guard let containerExploration = await prepareContainerExploration(
                    for: container,
                    exploration: &exploration
                ) else {
                    exploration.markExplored(container)
                    continue
                }
                if await exploreContainer(
                    containerExploration,
                    target: target,
                    exploration: &exploration
                ) {
                    return true
                }
            }
        }
        return false
    }

    private func sortedPendingContainers(in exploration: SemanticExploration) -> [AccessibilityContainer] {
        exploration.manifest.pendingContainers
            .map { (container: $0, overflow: totalOverflow(of: $0)) }
            .sorted { $0.overflow > $1.overflow }
            .map(\.container)
    }

    private func prepareContainerExploration(
        for container: AccessibilityContainer,
        exploration: inout SemanticExploration
    ) async -> ContainerExploration? {
        guard case .scrollable(let contentSize) = container.type else { return nil }

        if let view = stash.scrollableContainerViews[container],
           view.window != nil,
           Self.isObscuredByPresentation(view: view) {
            return nil
        }

        let hasHOverflow = contentSize.width > container.frame.width + 1
        let hasVOverflow = contentSize.height > container.frame.height + 1
        guard hasHOverflow || hasVOverflow else { return nil }
        let semanticContainer = exploration.screen.orderedContainers.first { $0.container == container }
        var ancestorRestorations: [ViewportRestoration] = []
        if stash.scrollableContainerViews[container] == nil,
           let semanticContainer {
            _ = await revealSemanticContainerForExploration(
                semanticContainer,
                exploration: &exploration,
                ancestorRestorations: &ancestorRestorations,
                depth: 0
            )
        }
        guard let scrollTarget = scrollableTarget(
            for: container,
            path: semanticContainer?.path,
            contentSize: contentSize
        ) else {
            await restoreAncestorPositions(ancestorRestorations, ignoring: nil, exploration: &exploration)
            return nil
        }
        return ContainerExploration(
            container: container,
            scrollTarget: scrollTarget,
            hasHOverflow: hasHOverflow,
            hasVOverflow: hasVOverflow,
            ancestorRestorations: ancestorRestorations
        )
    }

    private func revealSemanticContainerForExploration(
        _ container: SemanticScreen.Container,
        exploration: inout SemanticExploration,
        ancestorRestorations: inout [ViewportRestoration],
        depth: Int
    ) async -> Bool {
        guard depth < ElementInflation.maxNestedRevealDepth else { return false }
        if let containerName = container.containerName,
           stash.capturedLiveScrollView(forContainerName: containerName) != nil {
            return true
        }
        guard let location = container.scrollContentLocation else { return false }
        return await revealSemanticLocationForExploration(
            location,
            exploration: &exploration,
            ancestorRestorations: &ancestorRestorations,
            depth: depth
        )
    }

    private func revealSemanticLocationForExploration(
        _ location: SemanticScreen.ScrollContentLocation,
        exploration: inout SemanticExploration,
        ancestorRestorations: inout [ViewportRestoration],
        depth: Int
    ) async -> Bool {
        guard depth < ElementInflation.maxNestedRevealDepth else { return false }
        if let scrollView = stash.capturedLiveScrollView(forContainerName: location.scrollContainer) {
            return await revealContentOriginForExploration(
                location.origin,
                in: scrollView,
                exploration: &exploration,
                ancestorRestorations: &ancestorRestorations
            )
        }

        guard let scrollContainer = stash.uniqueSemanticContainer(named: location.scrollContainer),
              scrollContainer.scrollContentLocation != nil
        else { return false }

        guard await revealSemanticContainerForExploration(
            scrollContainer,
            exploration: &exploration,
            ancestorRestorations: &ancestorRestorations,
            depth: depth + 1
        ) else {
            return false
        }

        guard let scrollView = stash.capturedLiveScrollView(forContainerName: location.scrollContainer) else {
            return false
        }
        return await revealContentOriginForExploration(
            location.origin,
            in: scrollView,
            exploration: &exploration,
            ancestorRestorations: &ancestorRestorations
        )
    }

    private func revealContentOriginForExploration(
        _ origin: CGPoint,
        in scrollView: UIScrollView,
        exploration: inout SemanticExploration,
        ancestorRestorations: inout [ViewportRestoration]
    ) async -> Bool {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return false }
        ancestorRestorations.append(
            ViewportRestoration(
                scrollView: scrollView,
                visualOrigin: visualOrigin(in: scrollView)
            )
        )
        scrollView.setContentOffset(
            ElementInflation.semanticRevealTargetOffset(for: origin, in: scrollView),
            animated: false
        )
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        exploration.absorb(stash.refreshTreeAfterViewportMove())
        return true
    }

    private func exploreContainer(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        exploration: inout SemanticExploration
    ) async -> Bool {
        let savedVisualOrigin = containerExploration.savedVisualOrigin
        await moveToLeadingEdge(containerExploration, exploration: &exploration)
        if let target, hasVisibleTerminalExplorationResolution(target) {
            exploration.markExplored(containerExploration.container)
            return true
        }

        var scan = preparePageScan(in: containerExploration)
        let foundTarget = await scanForwardPages(
            containerExploration,
            target: target,
            scan: &scan,
            exploration: &exploration
        )

        if foundTarget {
            exploration.markExplored(containerExploration.container)
            return true
        }

        await restoreContainerPosition(
            containerExploration,
            savedVisualOrigin: savedVisualOrigin,
            exploration: &exploration
        )
        await restoreAncestorPositions(containerExploration, exploration: &exploration)
        exploration.markExplored(containerExploration.container)

        exploration.addDiscoveredContainers(stash.latestObservedLiveHierarchy.scrollableContainers)
        return false
    }

    private func preparePageScan(in containerExploration: ContainerExploration) -> ContainerScan {
        let initialPage = visibleElementsInContainer(containerExploration.container)
        return ContainerScan(
            accumulated: initialPage.elements,
            accumulatedOrigins: initialPage.origins,
            originByElement: buildOriginIndex()
        )
    }

    private func scanForwardPages(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        scan: inout ContainerScan,
        exploration: inout SemanticExploration
    ) async -> Bool {
        for _ in 0..<ScreenManifest.maxScrollsPerContainer {
            guard exploration.manifest.scrollCount < ScreenManifest.maxScrollsPerDiscovery else {
                return false
            }
            let proof = await scrollOnePageAndSettle(
                containerExploration.scrollTarget,
                direction: containerExploration.direction,
                animated: false
            )
            guard proof.result == .moved else { return false }
            exploration.manifest.scrollCount += 1

            guard absorbVisiblePage(in: &exploration) else { return false }
            scan.originByElement = buildOriginIndex()

            if let target, hasVisibleTerminalExplorationResolution(target) {
                return true
            }

            let result = reconcileVisiblePage(in: containerExploration, scan: &scan)
            guard !result.inserted.isEmpty else { return false }
        }
        return false
    }

    private func moveToLeadingEdge(
        _ containerExploration: ContainerExploration,
        exploration: inout SemanticExploration
    ) async {
        switch containerExploration.scrollTarget {
        case .uiScrollView(let scrollView):
            if safecracker.scrollToEdge(scrollView, edge: containerExploration.leadingEdge, animated: false) {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                exploration.absorb(stash.refreshTreeAfterViewportMove())
            }
        case .swipeable:
            let toLeading = Self.edgeDirection(for: containerExploration.leadingEdge)
            for _ in 0..<50 {
                let proof = await scrollOnePageAndSettle(
                    containerExploration.scrollTarget,
                    direction: toLeading,
                    animated: false
                )
                if proof.result == .moved {
                    _ = absorbVisiblePage(in: &exploration)
                }
                if proof.result == .unchanged || stash.visibleIds == proof.previousVisibleIds {
                    break
                }
            }
        }
    }

    private func absorbVisiblePage(in exploration: inout SemanticExploration) -> Bool {
        guard let parsed = stash.refreshTreeAfterViewportMove() else { return false }
        exploration.absorb(parsed)
        return true
    }

    private func reconcileVisiblePage(
        in containerExploration: ContainerExploration,
        scan: inout ContainerScan
    ) -> PageReconciliation {
        let page = visibleElementsInContainer(containerExploration.container)
        let result = reconcilePage(
            accumulated: scan.accumulated,
            accumulatedOrigins: scan.accumulatedOrigins,
            page: page.elements,
            pageOrigins: page.origins,
            orderingAxis: containerExploration.hasHOverflow ? .horizontal : .vertical
        )
        scan.accumulated = result.elements
        scan.accumulatedOrigins = scan.accumulated.map { scan.originByElement[$0] ?? nil }
        return result
    }

    private func restoreContainerPosition(
        _ containerExploration: ContainerExploration,
        savedVisualOrigin: CGPoint?,
        exploration: inout SemanticExploration
    ) async {
        if case .uiScrollView(let scrollView) = containerExploration.scrollTarget,
           let savedVisualOrigin {
            Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
            await waitForRestoredViewportSettle()
            exploration.absorb(stash.refreshTreeAfterViewportMove())
        }
    }

    private func restoreAncestorPositions(
        _ containerExploration: ContainerExploration,
        exploration: inout SemanticExploration
    ) async {
        let ignoredScrollView: UIScrollView?
        switch containerExploration.scrollTarget {
        case .uiScrollView(let scrollView):
            ignoredScrollView = scrollView
        case .swipeable:
            ignoredScrollView = nil
        }
        await restoreAncestorPositions(
            containerExploration.ancestorRestorations,
            ignoring: ignoredScrollView,
            exploration: &exploration
        )
    }

    private func restoreAncestorPositions(
        _ restorations: [ViewportRestoration],
        ignoring ignoredScrollView: UIScrollView?,
        exploration: inout SemanticExploration
    ) async {
        for restoration in restorations.reversed() where restoration.scrollView !== ignoredScrollView {
            Self.restoreVisualOrigin(restoration.visualOrigin, in: restoration.scrollView)
            await waitForRestoredViewportSettle()
            exploration.absorb(stash.refreshTreeAfterViewportMove())
        }
    }

    private func waitForRestoredViewportSettle() async {
        guard tripwire.isPulseRunning else {
            await tripwire.yieldFrames(1)
            return
        }
        _ = await tripwire.waitForSettle(
            timeout: TheTripwire.singleTickSettleTimeout,
            requiredQuietFrames: 1
        )
    }

    private func visibleElementsInContainer(_ container: AccessibilityContainer) -> ContainerPage {
        let pairs = stash.latestObservedLiveHierarchy.compactMap(
            context: false,
            container: { isInside, current in isInside || current == container },
            element: { element, _, isInside -> (element: AccessibilityElement, origin: CGPoint?)? in
                guard isInside,
                      let entry = self.stash.screenElement(for: element, in: .visible) else { return nil }
                return (element: entry.element, origin: entry.contentSpaceOrigin)
            }
        )
        return ContainerPage(elements: pairs.map(\.element), origins: pairs.map(\.origin))
    }

    private func buildOriginIndex() -> [AccessibilityElement: CGPoint?] {
        stash.knownContentOriginIndex()
    }

    private static func restoreVisualOrigin(_ visualOrigin: CGPoint, in scrollView: UIScrollView) {
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

    private func visualOrigin(in scrollView: UIScrollView) -> CGPoint {
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
        let containerFrame = container.frame
        let hits: [Bool] = hierarchy.compactMap(
            first: 1,
            context: false,
            container: { isInside, current in isInside || current == container },
            element: { element, _, isInside -> Bool? in
                guard isInside else { return nil }
                let elementFrame = element.shape.frame
                let extendsBeyond =
                    elementFrame.minX < containerFrame.minX - tolerance
                    || elementFrame.minY < containerFrame.minY - tolerance
                    || elementFrame.maxX > containerFrame.maxX + tolerance
                    || elementFrame.maxY > containerFrame.maxY + tolerance
                return extendsBeyond ? true : nil
            }
        )
        return !hits.isEmpty
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
