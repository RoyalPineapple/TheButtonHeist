#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

extension Navigation {

    @MainActor enum ViewportRestorationTarget {
        case semantic(ScrollableTarget)
        case original(UIScrollView)
    }

    @MainActor enum ViewportMovementIntent {
        case page(ScrollableTarget, direction: UIAccessibilityScrollDirection, animated: Bool)
        case edge(ScrollableTarget, edge: ScrollEdge)
        case swipe(ScrollableTarget, direction: UIAccessibilityScrollDirection)
        case revealPoint(
            CGPoint,
            in: ScrollableTarget,
            preferredScreenRect: CGRect,
            minimumScreenRect: CGRect
        )
        case revealViewPoint(ViewPoint, in: ScrollableTarget)
        case restoreVisualOrigin(CGPoint, in: ViewportRestorationTarget)

    }

    enum ScrollSettleOutcome: Equatable {
        case moved
        case unchanged
        case unavailable

        var didMove: Bool {
            self == .moved
        }
    }

    struct ViewportTransition {
        let outcome: ScrollSettleOutcome
        let previousVisibleIds: Set<HeistId>
        let current: TheVault.State.Current?

        static func unavailable(previousVisibleIds: Set<HeistId> = []) -> ViewportTransition {
            ViewportTransition(
                outcome: .unavailable,
                previousVisibleIds: previousVisibleIds,
                current: nil
            )
        }
    }

    func performViewportTransition(
        _ intent: ViewportMovementIntent,
        deadline: SemanticObservationDeadline? = nil,
        discoveryCommitPolicy: DiscoveryCommitPolicy = .mergeIntoInterface
    ) async -> ViewportTransition {
        await vault.semanticObservationStream.movingViewport {
            await performViewportTransitionMovingViewport(
                intent,
                deadline: deadline,
                discoveryCommitPolicy: discoveryCommitPolicy
            )
        }
    }

    /// Every viewport move Button Heist makes runs here, so a reading taken
    /// while one is in flight can say the viewport moved and be believed.
    private func performViewportTransitionMovingViewport(
        _ intent: ViewportMovementIntent,
        deadline: SemanticObservationDeadline?,
        discoveryCommitPolicy: DiscoveryCommitPolicy
    ) async -> ViewportTransition {
        if Task.isCancelled {
            guard case .restoreVisualOrigin = intent else { return .unavailable() }
        }
        guard deadline.map({
                  $0.remainingSeconds() >= Double(SemanticObservationTiming.viewportTransitionMinimumBudgetMs) / 1_000
              }) ?? true
        else { return .unavailable() }
        let previousVisibleIds = vault.viewportElementIDs
        let primitiveOutcome = await dispatchViewportMovement(intent)
        switch primitiveOutcome {
        case .moved:
            let current = await settledExplorationPage(
                deadline: deadline,
                discoveryCommitPolicy: discoveryCommitPolicy,
                afterViewportMovement: true
            )
            guard let current else {
                return .unavailable(previousVisibleIds: previousVisibleIds)
            }
            return ViewportTransition(
                outcome: movementOutcome(
                    for: intent,
                    previousVisibleIds: previousVisibleIds
                ),
                previousVisibleIds: previousVisibleIds,
                current: current
            )
        case .alreadyInPosition:
            return ViewportTransition(
                outcome: .unchanged,
                previousVisibleIds: previousVisibleIds,
                current: nil
            )
        case .unavailable:
            return .unavailable(previousVisibleIds: previousVisibleIds)
        }
    }

    private func dispatchViewportMovement(
        _ intent: ViewportMovementIntent,
    ) async -> TheSafecracker.ScrollPrimitiveOutcome {
        switch intent {
        case .page(let target, let direction, let animated):
            return target.dispatchOnFreshScrollView(in: vault) { scrollView in
                safecracker.scrollByPage(scrollView, direction: direction, animated: animated)
            } ?? .unavailable
        case .edge(let target, let edge):
            return target.dispatchOnFreshScrollView(in: vault) { scrollView in
                safecracker.scrollToEdge(scrollView, edge: edge, animated: false)
            } ?? .unavailable
        case .swipe(let target, let direction):
            guard case .swipeable(let container, _) = target else {
                return .unavailable
            }
            let preparation = vault.dispatchOnFreshLiveContainerTarget(
                container,
            ) { currentContainer -> TheSafecracker.PreparedTouchDispatch? in
                guard let frame = self.safeSwipeFrame(from: currentContainer.frame) else {
                    return nil
                }
                return self.safecracker.prepareScrollBySwipe(
                    frame: frame,
                    direction: direction,
                    duration: Self.swipeGestureDuration
                )
            }
            guard case .success(let dispatch) = preparation,
                  let dispatch else { return .unavailable }
            return await safecracker.completePreparedTouch(dispatch) ? .moved : .unavailable
        case .revealPoint(let point, let target, let preferredScreenRect, let minimumScreenRect):
            return target.dispatchOnFreshScrollView(in: vault) { scrollView in
                safecracker.scrollToMakeScreenPointVisible(
                    point,
                    in: scrollView,
                    animated: false,
                    preferredScreenRect: preferredScreenRect,
                    minimumScreenRect: minimumScreenRect
                )
            } ?? .unavailable
        case .revealViewPoint(let point, let target):
            return target.dispatchOnFreshScrollView(in: vault) { scrollView in
                safecracker.revealViewPoint(point, in: scrollView)
            } ?? .unavailable
        case .restoreVisualOrigin(let origin, let target):
            switch target {
            case .semantic(let semantic):
                return semantic.dispatchOnFreshScrollView(in: vault) { scrollView in
                    safecracker.restoreVisualOrigin(origin, in: scrollView)
                } ?? .unavailable
            case .original(let scrollView):
                guard scrollView.window != nil,
                      !scrollView.bhIsUnsafeForProgrammaticScrolling,
                      !Navigation.isObscuredByPresentation(view: scrollView)
                else { return .unavailable }
                return safecracker.restoreVisualOrigin(origin, in: scrollView)
            }
        }
    }

    private func movementOutcome(
        for intent: ViewportMovementIntent,
        previousVisibleIds: Set<HeistId>
    ) -> ScrollSettleOutcome {
        guard case .swipe = intent else { return .moved }
        return vault.viewportElementIDs == previousVisibleIds ? .unchanged : .moved
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
