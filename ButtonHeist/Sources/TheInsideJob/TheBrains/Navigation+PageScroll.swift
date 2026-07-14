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
            guard case .uiScrollView(let scrollView) = scrollTarget else {
                return .failure(
                    .scrollToEdge,
                    message: "scroll_to_edge failed: selected container has no live UIScrollView",
                    failureKind: .targetUnavailable
                )
            }
            let proof = await performViewportTransition(
                primitiveResult: safecracker.scrollToEdge(scrollView, edge: edge, animated: false),
                previousVisibleIds: stash.viewportElementIDs,
                animated: false,
                commitViewportMoves: true
            )
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

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true,
        commitViewportMoves: Bool = true
    ) async -> ScrollSettleProof {
        let before = stash.viewportElementIDs

        switch target {
        case .uiScrollView(let sv):
            return await performViewportTransition(
                primitiveResult: safecracker.scrollByPage(sv, direction: direction, animated: animated),
                previousVisibleIds: before,
                animated: animated,
                commitViewportMoves: commitViewportMoves
            )
        case .swipeable(let frame, let contentSize):
            let targetKey = swipeTargetKey(frame: frame, contentSize: contentSize)
            let isDirectionChange = lastSwipeDirectionByTarget[targetKey].map { $0 != direction } ?? false
            let proof = await performViewportTransition(
                primitiveResult: await safecracker.scrollBySwipe(
                    frame: frame,
                    direction: direction,
                    duration: Self.swipeGestureDuration
                ),
                previousVisibleIds: before,
                animated: false,
                commitViewportMoves: commitViewportMoves,
                settleAfterMove: {
                    await self.settleSwipeMotion(
                        previousVisibleIds: before,
                        requireDirectionChangeSettle: isDirectionChange,
                        commitViewportMoves: commitViewportMoves
                    )
                }
            )
            if proof.result != .unavailable {
                lastSwipeDirectionByTarget[targetKey] = direction
            }
            return proof
        }
    }

    @discardableResult
    func observeViewportAfterScroll(commitViewportMoves: Bool) -> InterfaceObservation? {
        stash.semanticPageForExploration()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
