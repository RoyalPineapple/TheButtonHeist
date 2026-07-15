#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

// MARK: - Page Scroll Commands

extension Navigation {

    func executeScroll(_ target: ResolvedScrollTarget) async -> TheSafecracker.ActionDispatchOutcome {
        await executeScroll(
            selection: target.selection,
            direction: target.direction
        )
    }

    func executeScroll(
        selection: ResolvedScrollContainerSelection,
        direction: ScrollDirection
    ) async -> TheSafecracker.ActionDispatchOutcome {
        stash.refreshLiveCapture()
        let axis = Self.requiredAxis(for: direction)
        switch resolveContainerScrollTarget(
            selection: selection,
            axis: axis,
            command: .scroll
        ) {
        case .resolved(let scrollTarget):
            let uiDirection = Self.uiScrollDirection(for: direction)
            let proof = await scrollOnePageAndSettle(
                scrollTarget, direction: uiDirection, animated: false
            )
            switch proof.result {
            case .moved:
                return .success(method: .scroll)
            case .unchanged:
                return .failure(.scroll, message: "scroll failed: observed target already at edge; try the opposite direction")
            case .unavailable:
                return .failure(.scroll, message: "scroll failed: selected container cannot be scrolled")
            }
        case .failed(let failure):
            return .failure(failure.command.method, message: failure.message, failureKind: .targetUnavailable)
        }
    }

    func executeScrollToEdge(_ target: ResolvedScrollToEdgeTarget) async -> TheSafecracker.ActionDispatchOutcome {
        await executeScrollToEdge(
            selection: target.selection,
            edge: target.edge
        )
    }

    func executeScrollToEdge(
        selection: ResolvedScrollContainerSelection,
        edge: ScrollEdge
    ) async -> TheSafecracker.ActionDispatchOutcome {
        stash.refreshLiveCapture()
        let axis = Self.requiredAxis(for: edge)
        switch resolveContainerScrollTarget(
            selection: selection,
            axis: axis,
            command: .scrollToEdge
        ) {
        case .resolved(let scrollTarget):
            let proof = await scrollToEdgeAndSettle(scrollTarget, edge: edge)
            switch proof.result {
            case .moved:
                return .success(method: .scrollToEdge)
            case .unchanged:
                return .success(method: .scrollToEdge)
            case .unavailable:
                return .failure(
                    .scrollToEdge,
                    message: "scroll_to_edge failed: selected container cannot be scrolled programmatically"
                )
            }
        case .failed(let failure):
            return .failure(failure.command.method, message: failure.message, failureKind: .targetUnavailable)
        }
    }

    func scrollToEdgeAndSettle(
        _ target: ScrollableTarget,
        edge: ScrollEdge
    ) async -> ViewportTransition {
        guard case .uiScrollView = target else {
            return .unavailable(previousVisibleIds: stash.viewportElementIDs)
        }
        return await performViewportTransition(.edge(target, edge: edge))
    }

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> ViewportTransition {
        switch target {
        case .uiScrollView:
            return await performViewportTransition(
                .page(target, direction: direction, animated: animated)
            )
        case .swipeable:
            return await performViewportTransition(
                .swipe(target, direction: direction)
            )
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
