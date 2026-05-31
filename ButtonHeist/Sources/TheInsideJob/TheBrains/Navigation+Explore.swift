#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Exploration

extension Navigation {

    fileprivate struct ContainerPage {
        let elements: [AccessibilityElement]
        let origins: [CGPoint?]
    }

    fileprivate struct ContainerExploration {
        let container: AccessibilityContainer
        let scrollTarget: ScrollableTarget
        let hasHOverflow: Bool
        let hasVOverflow: Bool

        var direction: UIAccessibilityScrollDirection { hasHOverflow ? .right : .down }

        var leadingEdge: ScrollEdge { hasHOverflow ? .left : .top }

        @MainActor
        var savedVisualOrigin: CGPoint? {
            guard case .uiScrollView(let scrollView) = scrollTarget else { return nil }
            return CGPoint(
                x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
                y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            )
        }
    }

    struct ExploredScreen {
        let screen: Screen
        let manifest: ScreenManifest
    }

    fileprivate struct SemanticExploration {
        var screen: Screen
        var manifest = ScreenManifest()

        init(baseline: Screen) {
            screen = baseline
        }

        mutating func absorb(_ parsed: Screen?) {
            guard let parsed else { return }
            screen = screen.merging(parsed)
        }

        mutating func markExplored(_ container: AccessibilityContainer) {
            manifest.markExplored(container)
        }

        mutating func addDiscoveredContainers(_ containers: [AccessibilityContainer]) {
            let newContainers = containers.filter {
                !manifest.exploredContainers.contains($0)
                    && !manifest.pendingContainers.contains($0)
            }
            manifest.addPendingContainers(newContainers)
        }

        mutating func finish(startTime: CFTimeInterval) -> ExploredScreen {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return ExploredScreen(screen: screen, manifest: manifest)
        }
    }

    func exploreAndPrune(target: ElementTarget? = nil) async -> ScreenManifest {
        let exploration = await exploreScreen(target: target)
        stash.commitExploredScreen(exploration.screen)
        return exploration.manifest
    }

    func exploreScreen(target: ElementTarget? = nil) async -> ExploredScreen {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(baseline: stash.explorationBaseline())

        exploration.absorb(stash.refresh())

        if let target, hasTerminalExplorationResolution(target) {
            return exploration.finish(startTime: startTime)
        }

        exploration.manifest.addPendingContainers(stash.currentHierarchy.scrollableContainers)
        while !exploration.manifest.pendingContainers.isEmpty {
            let batch = sortedPendingContainers(in: exploration)

            for container in batch {
                guard let containerExploration = containerExploration(for: container) else {
                    exploration.markExplored(container)
                    continue
                }
                let found = await exploreContainer(
                    containerExploration,
                    target: target,
                    exploration: &exploration
                )
                if found {
                    return exploration.finish(startTime: startTime)
                }
            }
        }

        return exploration.finish(startTime: startTime)
    }

    private func exploreContainer(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        exploration: inout SemanticExploration
    ) async -> Bool {
        let savedVisualOrigin = containerExploration.savedVisualOrigin
        await moveToLeadingEdge(containerExploration, exploration: &exploration)

        var originByElement = buildOriginIndex()

        let initialPage = visibleElementsInContainer(containerExploration.container)
        var accumulated = initialPage.elements
        var accumulatedOrigins = initialPage.origins

        for _ in 0..<ScreenManifest.maxScrollsPerContainer {
            let proof = await scrollOnePageAndSettle(
                containerExploration.scrollTarget,
                direction: containerExploration.direction,
                animated: false
            )
            guard proof.result == .moved else { break }
            exploration.manifest.scrollCount += 1
            parseVisiblePage(into: &exploration)
            originByElement = buildOriginIndex()

            let page = visibleElementsInContainer(containerExploration.container)
            let result = reconcilePage(
                accumulated: accumulated,
                accumulatedOrigins: accumulatedOrigins,
                page: page.elements,
                pageOrigins: page.origins,
                orderingAxis: containerExploration.hasHOverflow ? .horizontal : .vertical
            )
            accumulated = result.elements
            accumulatedOrigins = accumulated.map { originByElement[$0] ?? nil }

            if result.inserted.isEmpty { break }

            if let target, hasTerminalExplorationResolution(target) {
                await restoreAndMarkExplored(
                    containerExploration,
                    savedVisualOrigin: savedVisualOrigin,
                    exploration: &exploration
                )
                return true
            }
        }

        await restoreAndMarkExplored(
            containerExploration,
            savedVisualOrigin: savedVisualOrigin,
            exploration: &exploration
        )
        exploration.addDiscoveredContainers(stash.currentHierarchy.scrollableContainers)
        return false
    }

    private func hasTerminalExplorationResolution(_ target: ElementTarget) -> Bool {
        switch stash.resolveTarget(target) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    private func sortedPendingContainers(in exploration: SemanticExploration) -> [AccessibilityContainer] {
        exploration.manifest.pendingContainers
            .map { (container: $0, overflow: Self.totalOverflow(of: $0)) }
            .sorted { $0.overflow > $1.overflow }
            .map(\.container)
    }

    private func containerExploration(for container: AccessibilityContainer) -> ContainerExploration? {
        guard case .scrollable(let contentSize) = container.type else { return nil }

        if let view = stash.scrollableContainerViews[container],
           view.window != nil,
           Self.isObscuredByPresentation(view: view) {
            return nil
        }

        let hasHOverflow = contentSize.width > container.frame.width + 1
        let hasVOverflow = contentSize.height > container.frame.height + 1
        guard hasHOverflow || hasVOverflow else { return nil }
        guard Self.hasContentBeyondFrame(of: container, in: stash.currentHierarchy) else { return nil }
        guard let scrollTarget = scrollableTarget(for: container, contentSize: contentSize) else { return nil }
        return ContainerExploration(
            container: container,
            scrollTarget: scrollTarget,
            hasHOverflow: hasHOverflow,
            hasVOverflow: hasVOverflow
        )
    }

    private func moveToLeadingEdge(
        _ containerExploration: ContainerExploration,
        exploration: inout SemanticExploration
    ) async {
        switch containerExploration.scrollTarget {
        case .uiScrollView(let scrollView):
            if safecracker.scrollToEdge(scrollView, edge: containerExploration.leadingEdge, animated: false) {
                await tripwire.yieldFrames(2)
                exploration.absorb(stash.refresh())
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
                    parseVisiblePage(into: &exploration)
                }
                if proof.result == .unchanged || stash.visibleIds == proof.previousVisibleIds {
                    break
                }
            }
        }
    }

    private func parseVisiblePage(into exploration: inout SemanticExploration) {
        guard let parsed = stash.parse() else { return }
        stash.commitVisiblePage(parsed)
        exploration.absorb(parsed)
    }

    private func restoreAndMarkExplored(
        _ containerExploration: ContainerExploration,
        savedVisualOrigin: CGPoint?,
        exploration: inout SemanticExploration
    ) async {
        if case .uiScrollView(let scrollView) = containerExploration.scrollTarget,
           let savedVisualOrigin {
            Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
            await tripwire.yieldFrames(2)
            exploration.absorb(stash.refresh())
        }
        exploration.markExplored(containerExploration.container)
    }

    private func visibleElementsInContainer(_ container: AccessibilityContainer) -> ContainerPage {
        let pairs = stash.currentHierarchy.compactMap(
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

    static func totalOverflow(of container: AccessibilityContainer) -> CGFloat {
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

    static func isObscuredByPresentation(view: UIView) -> Bool {
        guard let window = view.window,
              let rootVC = window.rootViewController else {
            return false
        }

        guard let topPresented = Self.topmostPresentedViewController(from: rootVC) else {
            return false
        }

        guard let viewVC = view.nearestViewController else {
            return false
        }
        return !viewVC.isDescendant(of: topPresented)
    }

    private static func topmostPresentedViewController(
        from root: UIViewController
    ) -> UIViewController? {
        var topPresented: UIViewController?

        var queue: [UIViewController] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()

            if let presented = current.presentedViewController {
                var top = presented
                while let next = top.presentedViewController {
                    top = next
                }
                topPresented = top
            }

            queue.append(contentsOf: current.children)
        }

        return topPresented
    }
}

extension UIView {

    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController { return viewController }
            responder = next
        }
        return nil
    }
}

extension UIViewController {

    func isDescendant(of ancestor: UIViewController) -> Bool {
        var queue: [UIViewController] = [ancestor]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current === self { return true }
            queue.append(contentsOf: current.children)
        }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
