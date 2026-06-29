#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

// MARK: - Page Scroll Commands

extension Navigation {

    func executeScroll(_ target: ScrollTarget) async -> TheSafecracker.InteractionResult {
        await executeScroll(
            selection: target.selection,
            direction: target.direction
        )
    }

    func executeScroll(
        selection: ScrollContainerSelection,
        direction: ScrollDirection
    ) async -> TheSafecracker.InteractionResult {
        stash.refreshLiveCapture()
        let axis = Self.requiredAxis(for: direction)
        switch resolveContainerScrollTarget(
            selection: selection,
            axis: axis,
            commandName: "scroll"
        ) {
        case .resolved(let scrollTarget):
            let uiDirection = Self.uiScrollDirection(for: direction)
            let proof = await scrollOnePageAndSettle(
                scrollTarget, direction: uiDirection
            )
            return proof.result == .moved
                ? .success(method: .scroll)
                : .failure(.scroll, message: "scroll failed: observed target already at edge; try the opposite direction")
        case .failed(let message):
            return .failure(.scroll, message: message, failureKind: .targetUnavailable)
        }
    }

    func executeScrollToEdge(_ target: ScrollToEdgeTarget) async -> TheSafecracker.InteractionResult {
        await executeScrollToEdge(
            selection: target.selection,
            edge: target.edge
        )
    }

    func executeScrollToEdge(
        selection: ScrollContainerSelection,
        edge: ScrollEdge
    ) async -> TheSafecracker.InteractionResult {
        stash.refreshLiveCapture()
        let axis = Self.requiredAxis(for: edge)
        switch resolveContainerScrollTarget(
            selection: selection,
            axis: axis,
            commandName: "scroll_to_edge"
        ) {
        case .resolved(let scrollTarget):
            guard case .uiScrollView(let scrollView) = scrollTarget else {
                return .failure(
                    .scrollToEdge,
                    message: "scroll_to_edge failed: selected container has no live UIScrollView",
                    failureKind: .targetUnavailable
                )
            }
            switch safecracker.scrollToEdge(scrollView, edge: edge) {
            case .moved:
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                stash.refreshTreeAfterViewportMove()
                return .success(method: .scrollToEdge)
            case .alreadyAtEdge:
                return .success(method: .scrollToEdge)
            case .unavailable:
                return .failure(
                    .scrollToEdge,
                    message: "scroll_to_edge failed: selected container cannot be scrolled programmatically"
                )
            }
        case .failed(let message):
            return .failure(.scrollToEdge, message: message, failureKind: .targetUnavailable)
        }
    }

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true,
        commitViewportMoves: Bool = true
    ) async -> ScrollSettleProof {
        let before = stash.visibleIds

        switch target {
        case .uiScrollView(let sv):
            let moved = safecracker.scrollByPage(sv, direction: direction, animated: animated)
            guard moved else {
                return ScrollSettleProof(result: .unchanged, previousVisibleIds: before)
            }
            if animated {
                _ = await tripwire.waitForAllClear(timeout: 0.5)
            } else {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            }
            observeViewportAfterScroll(commitViewportMoves: commitViewportMoves)
            return ScrollSettleProof(result: .moved, previousVisibleIds: before)
        case .swipeable(let frame, let contentSize):
            let targetKey = swipeTargetKey(frame: frame, contentSize: contentSize)
            let isDirectionChange = lastSwipeDirectionByTarget[targetKey].map { $0 != direction } ?? false
            let dispatched = await safecracker.scrollBySwipe(
                frame: frame,
                direction: direction,
                duration: Self.swipeGestureDuration
            )
            guard dispatched else {
                return ScrollSettleProof(result: .unchanged, previousVisibleIds: before)
            }
            let result = await settleSwipeMotion(
                previousVisibleIds: before,
                requireDirectionChangeSettle: isDirectionChange,
                commitViewportMoves: commitViewportMoves
            )
            lastSwipeDirectionByTarget[targetKey] = direction
            return ScrollSettleProof(result: result, previousVisibleIds: before)
        }
    }

    @discardableResult
    func observeViewportAfterScroll(commitViewportMoves: Bool) -> Screen? {
        commitViewportMoves
            ? stash.refreshTreeAfterViewportMove()
            : stash.semanticPageForExploration()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
