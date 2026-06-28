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

    private func sortedPendingContainers(in exploration: SemanticExploration) -> [SemanticScreen.Container] {
        exploration.manifest.pendingContainerPaths
            .compactMap { exploration.screen.semantic.containers[$0] }
            .map { (container: $0, overflow: totalOverflow(of: $0.container)) }
            .sorted { $0.overflow > $1.overflow }
            .map(\.container)
    }

    private func prepareContainerExploration(
        for semanticContainer: SemanticScreen.Container,
        exploration: inout SemanticExploration
    ) async -> ContainerExploration? {
        let container = semanticContainer.container
        guard case .scrollable(let contentSize) = container.type else { return nil }

        if let view = stash.liveScrollableContainerView(forPath: semanticContainer.path),
           view.window != nil,
           Self.isObscuredByPresentation(view: view) {
            return nil
        }

        let hasHOverflow = contentSize.width > container.frame.width + 1
        let hasVOverflow = contentSize.height > container.frame.height + 1
        guard hasHOverflow || hasVOverflow else { return nil }
        var ancestorRestorations: [ViewportRestoration] = []
        let hasLiveScrollView = stash.liveScrollableContainerView(forPath: semanticContainer.path) != nil
        if !hasLiveScrollView {
            _ = await revealSemanticContainerForExploration(
                semanticContainer,
                exploration: &exploration,
                ancestorRestorations: &ancestorRestorations,
                depth: 0
            )
        }
        guard let scrollTarget = scrollableTarget(
            for: container,
            path: semanticContainer.path,
            contentSize: contentSize
        ) else {
            await restoreAncestorPositions(ancestorRestorations, ignoring: nil, exploration: &exploration)
            return nil
        }
        return ContainerExploration(
            semanticContainer: semanticContainer,
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
        if stash.capturedLiveScrollView(forContainerPath: container.path) != nil {
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
        if let scrollView = stash.capturedLiveScrollView(forContainerPath: location.scrollContainerPath) {
            return await revealContentOriginForExploration(
                location.origin,
                in: scrollView,
                exploration: &exploration,
                ancestorRestorations: &ancestorRestorations
            )
        }

        guard let scrollContainer = exploration.screen.semantic.containers[location.scrollContainerPath],
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

        guard let scrollView = stash.capturedLiveScrollView(forContainerPath: location.scrollContainerPath) else {
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
        absorbExplorationPage(in: &exploration)
        return true
    }

    private func exploreContainer(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        exploration: inout SemanticExploration
    ) async -> Bool {
        let savedVisualOrigin = containerExploration.savedVisualOrigin
        let leadingEdgeResult = await moveToLeadingEdge(containerExploration, exploration: &exploration)
        if case .omitted(let reason) = leadingEdgeResult {
            await restoreContainerPosition(
                containerExploration,
                savedVisualOrigin: savedVisualOrigin,
                exploration: &exploration
            )
            await restoreAncestorPositions(containerExploration, exploration: &exploration)
            exploration.manifest.markOmitted(containerExploration.path, reason: reason)
            exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
            return false
        }

        if let target, hasVisibleTerminalExplorationResolution(target) {
            exploration.markExplored(containerExploration.semanticContainer)
            return true
        }

        var scan = preparePageScan(in: containerExploration)
        let scanResult = await scanForwardPages(
            containerExploration,
            target: target,
            scan: &scan,
            exploration: &exploration
        )

        if scanResult == .foundTarget {
            exploration.markExplored(containerExploration.semanticContainer)
            return true
        }

        await restoreContainerPosition(
            containerExploration,
            savedVisualOrigin: savedVisualOrigin,
            exploration: &exploration
        )
        await restoreAncestorPositions(containerExploration, exploration: &exploration)
        if case .omitted(let reason) = scanResult {
            exploration.manifest.markOmitted(containerExploration.path, reason: reason)
        } else {
            exploration.markExplored(containerExploration.semanticContainer)
        }

        exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
        return false
    }

    private func preparePageScan(in containerExploration: ContainerExploration) -> ContainerScan {
        let initialPage = visibleElementsInContainer(containerExploration.path)
        return ContainerScan(
            accumulated: initialPage.entries
        )
    }

    private func scanForwardPages(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        scan: inout ContainerScan,
        exploration: inout SemanticExploration
    ) async -> ContainerScanResult {
        for _ in 0..<exploration.manifest.maxScrollsPerContainer {
            if let reason = exploration.manifest.recordScrollAttempt(in: containerExploration.path) {
                return .omitted(reason)
            }
            let proof = await scrollOnePageAndSettle(
                containerExploration.scrollTarget,
                direction: containerExploration.direction,
                animated: false,
                commitViewportMoves: false
            )
            guard proof.result == .moved else { return .completed }

            guard absorbVisiblePage(in: &exploration) else { return .completed }

            if let target, hasVisibleTerminalExplorationResolution(target) {
                return .foundTarget
            }

            let result = reconcileVisiblePage(in: containerExploration, scan: &scan)
            // Full discovery can stop once a page contributes nothing new.
            // Targeted discovery must keep going: the current page may have
            // been known from the starting viewport while the target is still
            // between here and the edge.
            guard target != nil || !result.inserted.isEmpty else { return .completed }
        }
        if exploration.manifest.scrollCount >= exploration.manifest.maxScrollsPerDiscovery {
            return .omitted(.discoveryScrollLimit)
        }
        return .omitted(.containerScrollLimit)
    }

    private func moveToLeadingEdge(
        _ containerExploration: ContainerExploration,
        exploration: inout SemanticExploration
    ) async -> ContainerScanResult {
        switch containerExploration.scrollTarget {
        case .uiScrollView(let scrollView):
            if let reason = exploration.manifest.recordScrollAttempt(in: containerExploration.path) {
                return .omitted(reason)
            }
            if safecracker.scrollToEdge(scrollView, edge: containerExploration.leadingEdge, animated: false) == .moved {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                absorbExplorationPage(in: &exploration)
            }
            return .completed
        case .swipeable:
            let toLeading = Self.edgeDirection(for: containerExploration.leadingEdge)
            for _ in 0..<50 {
                if let reason = exploration.manifest.recordScrollAttempt(in: containerExploration.path) {
                    return .omitted(reason)
                }
                let proof = await scrollOnePageAndSettle(
                    containerExploration.scrollTarget,
                    direction: toLeading,
                    animated: false,
                    commitViewportMoves: false
                )
                if proof.result == .moved {
                    _ = absorbVisiblePage(in: &exploration)
                }
                if proof.result == .unchanged || stash.visibleIds == proof.previousVisibleIds {
                    return .completed
                }
            }
            return .omitted(.leadingEdgeResetLimit)
        }
    }

    private func absorbVisiblePage(in exploration: inout SemanticExploration) -> Bool {
        guard let parsed = stash.semanticPageForExploration() else { return false }
        exploration.absorb(parsed)
        return true
    }

    private func absorbExplorationPage(in exploration: inout SemanticExploration) {
        exploration.absorb(stash.semanticPageForExploration())
    }

    private func reconcileVisiblePage(
        in containerExploration: ContainerExploration,
        scan: inout ContainerScan
    ) -> ContainerPageReconciliation {
        let page = visibleElementsInContainer(containerExploration.path)
        let result = reconcileContainerPage(
            accumulated: scan.accumulated,
            page: page.entries,
            orderingAxis: containerExploration.hasHOverflow ? .horizontal : .vertical
        )
        scan.accumulated = result.entries
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
            absorbExplorationPage(in: &exploration)
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
            absorbExplorationPage(in: &exploration)
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

    private func visibleElementsInContainer(_ containerPath: TreePath) -> ContainerPage {
        let entries = stash.latestObservedLiveHierarchy.compactMapSubtrees { node, path -> ContainerPageEntry? in
            guard path != containerPath,
                  path.hasPrefix(containerPath),
                  case .element = node,
                  let heistId = self.stash.liveHeistId(forPath: path),
                  let entry = self.stash.screenElement(heistId: heistId, in: .visible)
            else {
                return nil
            }
            return ContainerPageEntry(
                path: path,
                heistId: heistId,
                element: entry.element,
                origin: entry.contentSpaceOrigin
            )
        }
        return ContainerPage(entries: entries)
    }

    private func reconcileContainerPage(
        accumulated: [ContainerPageEntry],
        page: [ContainerPageEntry],
        orderingAxis: ContentOrderingAxis?
    ) -> ContainerPageReconciliation {
        guard !page.isEmpty else {
            return ContainerPageReconciliation(
                entries: accumulated,
                overlap: OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0),
                inserted: [],
                previousCount: accumulated.count
            )
        }

        guard !accumulated.isEmpty else {
            return ContainerPageReconciliation(
                entries: page,
                overlap: OverlapResult(accumulatedStart: 0, pageStart: 0, length: 0),
                inserted: page,
                previousCount: 0
            )
        }

        let accumulatedFingerprints = contentFingerprints(for: accumulated.elements, origins: accumulated.origins)
        let pageFingerprints = contentFingerprints(for: page.elements, origins: page.origins)
        let overlap = findOverlap(
            accumulated: accumulatedFingerprints,
            page: pageFingerprints
        )

        if let ordered = reconcileContainerPageByContentOrigin(
            accumulated: accumulated,
            page: page,
            overlap: overlap,
            orderingAxis: orderingAxis
        ) {
            return ordered
        }

        return reconcileContainerPageByOverlap(
            accumulated: accumulated,
            page: page,
            overlap: overlap
        )
    }

    private func reconcileContainerPageByContentOrigin(
        accumulated: [ContainerPageEntry],
        page: [ContainerPageEntry],
        overlap: OverlapResult,
        orderingAxis: ContentOrderingAxis?
    ) -> ContainerPageReconciliation? {
        guard let orderingAxis,
              accumulated.allSatisfy({ $0.origin != nil }),
              page.allSatisfy({ $0.origin != nil })
        else { return nil }

        let accumulatedHeistIds = Set(accumulated.map(\.heistId))
        var entriesByHeistId: [HeistId: (entry: ContainerPageEntry, order: Int)] = [:]
        for index in accumulated.indices {
            entriesByHeistId[accumulated[index].heistId] = (accumulated[index], index)
        }

        var inserted: [ContainerPageEntry] = []
        for index in page.indices {
            let entry = page[index]
            if !accumulatedHeistIds.contains(entry.heistId) {
                inserted.append(entry)
            }
            entriesByHeistId[entry.heistId] = (entry, accumulated.count + index)
        }

        let orderedEntries = entriesByHeistId.values.sorted { lhs, rhs in
            guard let leftOrigin = lhs.entry.origin,
                  let rightOrigin = rhs.entry.origin
            else { return lhs.order < rhs.order }
            switch orderingAxis {
            case .horizontal:
                if leftOrigin.x != rightOrigin.x { return leftOrigin.x < rightOrigin.x }
                if leftOrigin.y != rightOrigin.y { return leftOrigin.y < rightOrigin.y }
            case .vertical:
                if leftOrigin.y != rightOrigin.y { return leftOrigin.y < rightOrigin.y }
                if leftOrigin.x != rightOrigin.x { return leftOrigin.x < rightOrigin.x }
            }
            return lhs.order < rhs.order
        }.map(\.entry)

        return ContainerPageReconciliation(
            entries: orderedEntries,
            overlap: overlap,
            inserted: inserted,
            previousCount: accumulated.count
        )
    }

    private func reconcileContainerPageByOverlap(
        accumulated: [ContainerPageEntry],
        page: [ContainerPageEntry],
        overlap: OverlapResult
    ) -> ContainerPageReconciliation {
        guard overlap.length > 0 else {
            return ContainerPageReconciliation(
                entries: accumulated + page,
                overlap: overlap,
                inserted: page,
                previousCount: accumulated.count
            )
        }

        var entries: [ContainerPageEntry] = []
        entries.reserveCapacity(accumulated.count + page.count - overlap.length)
        entries.append(contentsOf: accumulated[..<overlap.accumulatedStart])
        entries.append(contentsOf: page[..<overlap.pageStart])
        entries.append(contentsOf: page[overlap.pageStart..<overlap.pageEnd])
        entries.append(contentsOf: page[overlap.pageEnd..<page.endIndex])
        entries.append(contentsOf: accumulated[overlap.accumulatedEnd..<accumulated.endIndex])

        let inserted = Array(page[..<overlap.pageStart])
            + Array(page[overlap.pageEnd..<page.endIndex])

        return ContainerPageReconciliation(
            entries: entries,
            overlap: overlap,
            inserted: inserted,
            previousCount: accumulated.count
        )
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
}

private extension Array where Element == Navigation.ContainerPageEntry {
    var elements: [AccessibilityElement] {
        map(\.element)
    }

    var origins: [CGPoint?] {
        map(\.origin)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
