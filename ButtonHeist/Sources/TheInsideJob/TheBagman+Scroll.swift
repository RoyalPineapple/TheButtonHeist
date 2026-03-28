#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Scroll Command Execution

extension TheBagman {

    /// Execute a scroll command — resolve the element, scroll its ancestor.
    func executeScroll(_ target: ScrollTarget) -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }
        guard let resolved = resolveTarget(elementTarget) else {
            return .failure(.elementNotFound, message: elementNotFoundMessage(for: elementTarget))
        }

        let uiDirection: UIAccessibilityScrollDirection
        switch target.direction {
        case .up:       uiDirection = .up
        case .down:     uiDirection = .down
        case .left:     uiDirection = .left
        case .right:    uiDirection = .right
        case .next:     uiDirection = .next
        case .previous: uiDirection = .previous
        }

        let success = scroll(elementAt: resolved.traversalIndex, direction: uiDirection)
        return TheSafecracker.InteractionResult(
            success: success,
            method: .scroll,
            message: success ? nil : "No scrollable ancestor found for element",
            value: nil
        )
    }

    /// Execute a scroll-to-edge command.
    func executeScrollToEdge(_ target: ScrollToEdgeTarget) -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scrollToEdge, message: "Element target required for scroll_to_edge")
        }
        guard let resolved = resolveTarget(elementTarget) else {
            return .failure(.elementNotFound, message: elementNotFoundMessage(for: elementTarget))
        }

        let success = scrollToEdge(elementAt: resolved.traversalIndex, edge: target.edge)
        return TheSafecracker.InteractionResult(
            success: success,
            method: .scrollToEdge,
            message: success ? nil : "No scrollable ancestor found for element",
            value: nil
        )
    }

    /// Execute scroll-to-visible: find an element by scanning scroll content.
    /// Uses animated scrolling with layoutIfNeeded() for non-blocking parsing.
    func executeScrollToVisible(_ target: ScrollToVisibleTarget) -> TheSafecracker.InteractionResult {
        guard let searchTarget = target.elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }
        let maxScrolls = target.resolvedMaxScrolls
        let primaryDirection = target.resolvedDirection

        // Phase 0: check current tree
        refreshAccessibilityData()
        if let found = resolveTarget(searchTarget) {
            _ = scrollToVisible(elementAt: found.traversalIndex)
            let wireElement = convertAndAssignId(found.element, index: found.traversalIndex)
            return TheSafecracker.InteractionResult(
                success: true, method: .scrollToVisible, message: nil, value: nil,
                scrollSearchResult: ScrollSearchResult(
                    scrollCount: 0, uniqueElementsSeen: cachedElements.count,
                    totalItems: nil, exhaustive: false, foundElement: wireElement
                )
            )
        }

        guard let searchPreparation = beginScrollSearch() else {
            return .failure(.scrollToVisible, message: "No scroll view found on screen")
        }
        defer { endScrollSearch() }

        let totalItems = searchPreparation.totalItems
        var scrollCount = 0

        // Phase 1: scan in primary direction
        if let result = scanLoop(
            target: searchTarget, direction: primaryDirection,
            maxScrolls: maxScrolls, scrollCount: &scrollCount,
            totalItems: totalItems
        ) {
            return result
        }

        // Phase 2: jump to opposite edge, scan again
        if scrollCount < maxScrolls {
            moveActiveSearchContainerToOppositeEdge(from: primaryDirection)
            if let scrollView = activeScrollSearchView {
                scrollView.layoutIfNeeded()
            }
            refreshAccessibilityData()

            if let result = scanLoop(
                target: searchTarget, direction: primaryDirection,
                maxScrolls: maxScrolls, scrollCount: &scrollCount,
                totalItems: totalItems
            ) {
                return result
            }
        }

        // Phase 3: not found
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

    /// Scroll and parse in one direction. No waitForAllClear — layoutIfNeeded()
    /// is synchronous. screenElements accumulates discovered elements.
    private func scanLoop(
        target: ElementTarget,
        direction: ScrollSearchDirection,
        maxScrolls: Int,
        scrollCount: inout Int,
        totalItems: Int?
    ) -> TheSafecracker.InteractionResult? {
        // Track unique heistIds seen across all steps for end-of-content detection
        var allSeen = onScreen

        while scrollCount < maxScrolls {
            // Non-animated scroll — content offset changes instantly.
            // layoutIfNeeded() forces cell dequeue at the new position.
            let scrolled = scrollActiveSearchContainer(direction: direction, animated: false)
            if !scrolled { break }
            scrollCount += 1

            activeScrollSearchView?.layoutIfNeeded()

            // Parse + update screenElements inline
            refreshAccessibilityData()

            // Check for target
            if let found = resolveTarget(target) {
                _ = scrollToVisible(elementAt: found.traversalIndex)
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

            // End-of-content: no new heistIds appeared on screen
            let newIds = onScreen.subtracting(allSeen)
            allSeen.formUnion(onScreen)
            if newIds.isEmpty { break }

            // Exhaustive check for collection/table views
            if let totalItems, allSeen.count >= totalItems {
                return TheSafecracker.InteractionResult(
                    success: false, method: .scrollToVisible,
                    message: "Element not found (exhaustive search)", value: nil,
                    scrollSearchResult: ScrollSearchResult(
                        scrollCount: scrollCount,
                        uniqueElementsSeen: allSeen.count,
                        totalItems: totalItems, exhaustive: true
                    )
                )
            }
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
