#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Scroll Orchestration
//
// TheBagman finds scroll views from the accessibility hierarchy and drives
// TheSafecracker's scroll primitives. TheSafecracker knows nothing about
// elements — it takes a UIScrollView and moves it.

extension TheBagman {

    // MARK: - Scroll Command Execution

    func executeScroll(_ target: ScrollTarget) -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }
        guard let resolved = resolveTarget(elementTarget) else {
            return .failure(.elementNotFound, message: elementNotFoundMessage(for: elementTarget))
        }
        guard let object = resolved.screenElement.object,
              let scrollView = scrollableAncestor(of: object, includeSelf: true),
              let safecracker else {
            return .failure(.scroll, message: "No scrollable ancestor found for element")
        }

        let uiDirection = uiScrollDirection(for: target.direction)
        let success = safecracker.scrollByPage(scrollView, direction: uiDirection)
        return TheSafecracker.InteractionResult(
            success: success, method: .scroll,
            message: success ? nil : "Already at edge",
            value: nil
        )
    }

    func executeScrollToEdge(_ target: ScrollToEdgeTarget) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scrollToEdge, message: "Element target required for scroll_to_edge")
        }
        guard let resolved = resolveTarget(elementTarget) else {
            return .failure(.elementNotFound, message: elementNotFoundMessage(for: elementTarget))
        }
        guard let object = resolved.screenElement.object,
              let scrollView = scrollableAncestor(of: object, includeSelf: true),
              let safecracker else {
            return .failure(.scrollToEdge, message: "No scrollable ancestor found for element")
        }

        let success = safecracker.scrollToEdge(scrollView, edge: target.edge)

        // Content may grow after the jump (lazy containers materialise on
        // scroll). Yield a couple of frames, then re-jump until contentSize
        // stops changing.
        if success {
            for _ in 0..<20 {
                await tripwire.yieldFrames(2)
                let prev = scrollView.contentSize
                let moved = safecracker.scrollToEdge(scrollView, edge: target.edge)
                if moved { await tripwire.yieldFrames(2) }
                if !moved && scrollView.contentSize == prev { break }
            }
        }

        return TheSafecracker.InteractionResult(
            success: success, method: .scrollToEdge,
            message: success ? nil : "Already at edge",
            value: nil
        )
    }

    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.InteractionResult {
        guard let searchTarget = target.elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }
        let maxScrolls = target.resolvedMaxScrolls
        let primaryDirection = target.resolvedDirection

        // Phase 0: check current tree
        refreshAccessibilityData()
        if let found = resolveFirstMatch(searchTarget) {
            ensureOnScreenSync(found)
            let wireElement = convertAndAssignId(found.element, index: found.traversalIndex)
            return TheSafecracker.InteractionResult(
                success: true, method: .scrollToVisible, message: nil, value: nil,
                scrollSearchResult: ScrollSearchResult(
                    scrollCount: 0, uniqueElementsSeen: cachedElements.count,
                    totalItems: nil, exhaustive: false, foundElement: wireElement
                )
            )
        }

        guard let scrollView = findFirstScrollView(),
              let safecracker else {
            return .failure(.scrollToVisible, message: "No scroll view found on screen")
        }

        let totalItems = safecracker.queryCollectionTotalItems(scrollView)
        var scrollCount = 0

        // Phase 1: scan in primary direction
        if let result = await scanLoop(
            target: searchTarget, scrollView: scrollView, direction: primaryDirection,
            maxScrolls: maxScrolls, scrollCount: &scrollCount, totalItems: totalItems
        ) { return result }

        // Phase 2: jump to opposite edge, scan again
        if scrollCount < maxScrolls {
            safecracker.scrollToOppositeEdge(scrollView, from: primaryDirection)
            await tripwire.yieldFrames(2)
            refreshAccessibilityData()

            if let result = await scanLoop(
                target: searchTarget, scrollView: scrollView, direction: primaryDirection,
                maxScrolls: maxScrolls, scrollCount: &scrollCount, totalItems: totalItems
            ) { return result }
        }

        let totalSeen = screenElements.count
        let exhaustive = totalItems.map { totalSeen >= $0 } ?? false
        return TheSafecracker.InteractionResult(
            success: false, method: .scrollToVisible,
            message: "Element not found after \(scrollCount) scrolls", value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: totalSeen,
                totalItems: totalItems, exhaustive: exhaustive
            )
        )
    }

    // MARK: - Scan Loop

    private func scanLoop(
        target: ElementTarget,
        scrollView: UIScrollView,
        direction: ScrollSearchDirection,
        maxScrolls: Int,
        scrollCount: inout Int,
        totalItems: Int?
    ) async -> TheSafecracker.InteractionResult? {
        var allSeen = onScreen

        let pageStep = scrollPageStep(scrollView, direction: direction)

        while scrollCount < maxScrolls {
            // Advance by one page. Animated so it looks human — iOS rubber-bands
            // naturally if we overshoot contentSize. Stagnation (no new elements)
            // is the only termination signal, so clamping is unnecessary.
            let offset = scrollView.contentOffset
            scrollView.setContentOffset(
                CGPoint(x: offset.x + pageStep.x, y: offset.y + pageStep.y),
                animated: true
            )

            // Yield a few frames for layout to materialise new content.
            await tripwire.yieldFrames(3)

            scrollCount += 1
            refreshAccessibilityData()

            if let found = resolveFirstMatch(target) {
                ensureOnScreenSync(found)
                let wireElement = convertAndAssignId(found.element, index: found.traversalIndex)
                return TheSafecracker.InteractionResult(
                    success: true, method: .scrollToVisible, message: nil, value: nil,
                    scrollSearchResult: ScrollSearchResult(
                        scrollCount: scrollCount,
                        uniqueElementsSeen: allSeen.union(onScreen).count,
                        totalItems: totalItems, exhaustive: false, foundElement: wireElement
                    )
                )
            }

            // No new elements → content exhausted in this direction.
            let newIds = onScreen.subtracting(allSeen)
            allSeen.formUnion(onScreen)
            if newIds.isEmpty { break }
        }
        return nil
    }

    // MARK: - Ensure On Screen

    func ensureOnScreen(for target: ElementTarget) async {
        guard let resolved = resolveTarget(target),
              let object = resolved.screenElement.object else { return }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        guard let scrollView = scrollableAncestor(of: object, includeSelf: false),
              let safecracker else { return }
        if safecracker.scrollToMakeVisible(frame, in: scrollView) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refreshAccessibilityData()
        }
    }

    func ensureFirstResponderOnScreen() async {
        guard let responder = tripwire.currentFirstResponder() else { return }
        let frame = responder.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        guard let scrollView = scrollableAncestor(of: responder, includeSelf: false),
              let safecracker else { return }
        if safecracker.scrollToMakeVisible(frame, in: scrollView) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refreshAccessibilityData()
        }
    }

    private func ensureOnScreenSync(_ resolved: ResolvedTarget) {
        guard let object = resolved.screenElement.object,
              let safecracker else { return }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        guard let scrollView = scrollableAncestor(of: object, includeSelf: false) else { return }
        _ = safecracker.scrollToMakeVisible(frame, in: scrollView)
    }

    // MARK: - Scroll View Discovery

    func findFirstScrollView() -> UIScrollView? {
        for (heistId, entry) in screenElements where onScreen.contains(heistId) {
            guard let object = entry.object,
                  let scrollView = scrollableAncestor(of: object, includeSelf: true) else { continue }
            return scrollView
        }
        return nil
    }

    func scrollableAncestor(of object: NSObject, includeSelf: Bool) -> UIScrollView? {
        var current: NSObject? = includeSelf ? object : nextAncestor(of: object)
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView, scrollView.isScrollEnabled {
                return scrollView
            }
            current = nextAncestor(of: candidate)
        }
        return nil
    }

    private func nextAncestor(of candidate: NSObject) -> NSObject? {
        if let view = candidate as? UIView { return view.superview }
        if let element = candidate as? UIAccessibilityElement {
            return element.accessibilityContainer as? NSObject
        }
        if candidate.responds(to: Selector(("accessibilityContainer"))) {
            return candidate.value(forKey: "accessibilityContainer") as? NSObject
        }
        return nil
    }

    // MARK: - Page Step

    /// One page of scroll travel (with 44pt overlap) as a signed delta vector.
    /// Used by the scan loop to advance the offset directly without contentSize clamping.
    private func scrollPageStep(_ scrollView: UIScrollView, direction: ScrollSearchDirection) -> CGPoint {
        let overlap: CGFloat = 44
        let size = scrollView.frame.size
        switch direction {
        case .down:  return CGPoint(x: 0, y: size.height - overlap)
        case .up:    return CGPoint(x: 0, y: -(size.height - overlap))
        case .right: return CGPoint(x: size.width - overlap, y: 0)
        case .left:  return CGPoint(x: -(size.width - overlap), y: 0)
        }
    }

    // MARK: - Direction Mapping

    func uiScrollDirection(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .down
        case .up: return .up
        case .left: return .left
        case .right: return .right
        }
    }

    func uiScrollDirection(for direction: ScrollDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .next: return .next
        case .previous: return .previous
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
