#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Navigation {

    func executeScroll(
        _ target: ResolvedScrollTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        await executeScroll(
            selection: target.selection,
            direction: target.direction,
        )
    }

    func executeScroll(
        selection: ResolvedScrollContainerSelection,
        direction: ScrollDirection,
    ) async -> TheSafecracker.ActionDispatchResult {
        vault.refreshLiveCapture()
        let axis = Self.requiredAxis(for: direction)
        switch resolveContainerScrollTarget(
            selection: selection,
            axis: axis,
            command: .scroll
        ) {
        case .resolved(let scrollTarget):
            let uiDirection = Self.uiScrollDirection(for: direction)
            let transition = await scrollOnePageAndSettle(
                scrollTarget,
                direction: uiDirection,
                animated: false,
            )
            switch transition.outcome {
            case .moved:
                return .success(payload: .scroll)
            case .unchanged:
                return .failure(.scroll, message: "scroll failed: observed target already at edge; try the opposite direction")
            case .unavailable:
                return .failure(.scroll, message: "scroll failed: selected container cannot be scrolled")
            }
        case .failed(let failure):
            return .failure(
                failure.command.payload,
                message: failure.message,
                failureKind: .targetUnavailable
            )
        }
    }

    func executeScrollToEdge(
        _ target: ResolvedScrollToEdgeTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        await executeScrollToEdge(
            selection: target.selection,
            edge: target.edge,
        )
    }

    func executeScrollToEdge(
        selection: ResolvedScrollContainerSelection,
        edge: ScrollEdge,
    ) async -> TheSafecracker.ActionDispatchResult {
        vault.refreshLiveCapture()
        let axis = Self.requiredAxis(for: edge)
        switch resolveContainerScrollTarget(
            selection: selection,
            axis: axis,
            command: .scrollToEdge
        ) {
        case .resolved(let scrollTarget):
            let transition = await scrollToEdgeAndSettle(
                scrollTarget,
                edge: edge,
            )
            switch transition.outcome {
            case .moved:
                return .success(payload: .scrollToEdge)
            case .unchanged:
                return .success(payload: .scrollToEdge)
            case .unavailable:
                return .failure(
                    .scrollToEdge,
                    message: "scroll_to_edge failed: selected container cannot be scrolled programmatically"
                )
            }
        case .failed(let failure):
            return .failure(
                failure.command.payload,
                message: failure.message,
                failureKind: .targetUnavailable
            )
        }
    }

    func scrollToEdgeAndSettle(
        _ target: ScrollableTarget,
        edge: ScrollEdge,
    ) async -> ViewportTransition {
        guard case .uiScrollView = target else {
            return .unavailable(previousVisibleIds: vault.viewportElementIDs)
        }
        return await performViewportTransition(.edge(target, edge: edge))
    }

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true,
    ) async -> ViewportTransition {
        switch target {
        case .uiScrollView:
            return await performViewportTransition(
                .page(target, direction: direction, animated: animated),
            )
        case .swipeable:
            return await performViewportTransition(
                .swipe(target, direction: direction),
            )
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
