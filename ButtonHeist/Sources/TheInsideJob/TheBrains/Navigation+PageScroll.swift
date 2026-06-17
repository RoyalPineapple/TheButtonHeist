#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

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
            return .failure(.scroll, message: message)
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
                return .failure(.scrollToEdge, message: "scroll_to_edge failed: selected container has no live UIScrollView")
            }
            let moved = safecracker.scrollToEdge(scrollView, edge: edge)
            if moved {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                stash.refreshTreeAfterViewportMove()
            }

            return moved
                ? .success(method: .scrollToEdge)
                : .failure(
                    .scrollToEdge,
                    message: "scroll_to_edge failed: observed target already at requested edge"
                )
        case .failed(let message):
            return .failure(.scrollToEdge, message: message)
        }
    }

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> ScrollSettleProof {
        let before = stash.visibleIds
        let beforeAnchor = visibleAnchorSignature()

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
            stash.refreshTreeAfterViewportMove()
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
                previousAnchor: beforeAnchor,
                requireDirectionChangeSettle: isDirectionChange
            )
            lastSwipeDirectionByTarget[targetKey] = direction
            return ScrollSettleProof(result: result, previousVisibleIds: before)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
