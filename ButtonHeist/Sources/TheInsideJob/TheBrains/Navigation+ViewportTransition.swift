#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

extension Navigation {

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
        case revealContentPoint(ScrollContentPoint, in: ScrollableTarget)
        case restoreVisualOrigin(CGPoint, in: ScrollableTarget)

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
        let event: SettledObservationEvent?

        static func unavailable(previousVisibleIds: Set<HeistId> = []) -> ViewportTransition {
            ViewportTransition(
                outcome: .unavailable,
                previousVisibleIds: previousVisibleIds,
                event: nil
            )
        }
    }

    func performViewportTransition(
        _ intent: ViewportMovementIntent,
        deadline: SemanticObservationDeadline? = nil,
        discoveryCommitPolicy: DiscoveryCommitPolicy = .mergeIntoInterface
    ) async -> ViewportTransition {
        guard !Task.isCancelled,
              deadline.map({
                  $0.remainingSeconds() >= Double(SettleSession.viewportTransitionMinimumBudgetMs) / 1_000
              }) ?? true
        else { return .unavailable() }
        let previousViewportHash = vault.latestObservation.tree.viewportOnly.interfaceHash
        let previousVisibleIds = vault.viewportElementIDs
        let notificationWindow = vault.accessibilityNotifications.beginActionWindow()
        let primitiveOutcome = await dispatchViewportMovement(intent)
        switch primitiveOutcome {
        case .moved:
            let event = await settledExplorationPage(
                deadline: deadline,
                discoveryCommitPolicy: discoveryCommitPolicy,
                notificationWindow: notificationWindow,
                previousViewportHash: previousViewportHash
            )
            guard let event else {
                return .unavailable(previousVisibleIds: previousVisibleIds)
            }
            return ViewportTransition(
                outcome: movementOutcome(
                    for: intent,
                    previousVisibleIds: previousVisibleIds
                ),
                previousVisibleIds: previousVisibleIds,
                event: event
            )
        case .alreadyInPosition:
            notificationWindow.cancel()
            return ViewportTransition(
                outcome: .unchanged,
                previousVisibleIds: previousVisibleIds,
                event: nil
            )
        case .unavailable:
            notificationWindow.cancel()
            return .unavailable(previousVisibleIds: previousVisibleIds)
        }
    }

    private func dispatchViewportMovement(
        _ intent: ViewportMovementIntent,
    ) async -> TheSafecracker.ScrollPrimitiveResult {
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
        case .revealContentPoint(let point, let target):
            return target.dispatchOnFreshScrollView(in: vault) { scrollView in
                safecracker.revealContentPoint(point, in: scrollView)
            } ?? .unavailable
        case .restoreVisualOrigin(let origin, let target):
            return target.dispatchOnFreshScrollView(in: vault) { scrollView in
                safecracker.restoreVisualOrigin(origin, in: scrollView)
            } ?? .unavailable
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
