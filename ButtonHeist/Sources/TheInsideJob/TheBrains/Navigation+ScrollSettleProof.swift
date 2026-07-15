#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

extension Navigation {

    @MainActor enum ViewportMovementIntent { // swiftlint:disable:this agent_main_actor_value_type
        case page(ScrollableTarget, direction: UIAccessibilityScrollDirection, animated: Bool)
        case edge(ScrollableTarget, edge: ScrollEdge)
        case swipe(ScrollableTarget, direction: UIAccessibilityScrollDirection)
        case revealPoint(
            CGPoint,
            in: UIScrollView,
            preferredScreenRect: CGRect,
            minimumScreenRect: CGRect
        )
        case revealContentPoint(ScrollContentPoint, in: UIScrollView)
        case restoreVisualOrigin(CGPoint, in: UIScrollView)

    }

    enum ScrollSettleResult: Equatable {
        case moved
        case unchanged
        case unavailable

        var didMove: Bool {
            self == .moved
        }
    }

    struct ViewportTransition {
        let result: ScrollSettleResult
        let previousVisibleIds: Set<HeistId>
        let event: SettledSemanticObservationEvent?

        static func unavailable(previousVisibleIds: Set<HeistId> = []) -> ViewportTransition {
            ViewportTransition(
                result: .unavailable,
                previousVisibleIds: previousVisibleIds,
                event: nil
            )
        }
    }

    /// The only viewport-movement pipeline. It owns dispatch, the minimal
    /// movement-specific settle, parser proof, graph reduction, and stream
    /// publication in that order.
    func performViewportTransition(
        _ intent: ViewportMovementIntent,
        deadline: SemanticObservationDeadline? = nil,
        discoveryCommitPolicy: DiscoveryCommitPolicy = .mergeIntoInterface
    ) async -> ViewportTransition {
        let previousVisibleIds = stash.viewportElementIDs
        let notificationWindow = stash.accessibilityNotifications.beginActionWindow()
        let primitiveResult = await dispatchViewportMovement(intent)
        switch primitiveResult {
        case .moved:
            // Once UIKit accepts a movement, its resulting viewport must be
            // committed even when the initiating task is cancelled.
            return await Task { @MainActor in
                let event = await self.settledExplorationPage(
                    deadline: deadline,
                    discoveryCommitPolicy: discoveryCommitPolicy,
                    notificationWindow: notificationWindow,
                    requiredAfterMovement: true
                )
                guard let event else {
                    return .unavailable(previousVisibleIds: previousVisibleIds)
                }
                return ViewportTransition(
                    result: self.movementResult(
                        for: intent,
                        previousVisibleIds: previousVisibleIds
                    ),
                    previousVisibleIds: previousVisibleIds,
                    event: event
                )
            }.value
        case .alreadyInPosition:
            notificationWindow.cancel()
            return ViewportTransition(
                result: .unchanged,
                previousVisibleIds: previousVisibleIds,
                event: nil
            )
        case .unavailable:
            notificationWindow.cancel()
            return .unavailable(previousVisibleIds: previousVisibleIds)
        }
    }

    private func dispatchViewportMovement(
        _ intent: ViewportMovementIntent
    ) async -> TheSafecracker.ScrollPrimitiveResult {
        switch intent {
        case .page(let target, let direction, let animated):
            guard case .uiScrollView(_, _, let scrollView) = current(target) else {
                return .unavailable
            }
            return safecracker.scrollByPage(scrollView, direction: direction, animated: animated)
        case .edge(let target, let edge):
            guard case .uiScrollView(_, _, let scrollView) = current(target) else {
                return .unavailable
            }
            return safecracker.scrollToEdge(scrollView, edge: edge, animated: false)
        case .swipe(let target, let direction):
            guard case .swipeable(_, let frame, _) = current(target) else {
                return .unavailable
            }
            return await safecracker.scrollBySwipe(
                frame: frame,
                direction: direction,
                duration: Self.swipeGestureDuration
            )
        case .revealPoint(let point, let scrollView, let preferredScreenRect, let minimumScreenRect):
            return safecracker.scrollToMakeScreenPointVisible(
                point,
                in: scrollView,
                animated: false,
                preferredScreenRect: preferredScreenRect,
                minimumScreenRect: minimumScreenRect
            )
        case .revealContentPoint(let point, let scrollView):
            return safecracker.revealContentPoint(point, in: scrollView)
        case .restoreVisualOrigin(let origin, let scrollView):
            return safecracker.restoreVisualOrigin(origin, in: scrollView)
        }
    }

    private func current(_ target: ScrollableTarget) -> ScrollableTarget? {
        guard let currentObject = stash.liveContainerObject(forPath: target.containerTarget.path),
              currentObject === target.object else { return nil }
        switch target {
        case .uiScrollView(let containerTarget, _, let scrollView):
            guard stash.liveScrollableContainerView(
                forPath: containerTarget.path
            ) === scrollView else { return nil }
            return .uiScrollView(
                containerTarget: containerTarget,
                object: currentObject,
                scrollView: scrollView
            )
        case .swipeable(_, let frame, let contentSize):
            guard case .resolved(let currentContainer) = stash.resolveLiveContainerTarget(
                for: target.containerTarget
            ) else { return nil }
            return .swipeable(container: currentContainer, frame: frame, contentSize: contentSize)
        }
    }

    private func movementResult(
        for intent: ViewportMovementIntent,
        previousVisibleIds: Set<HeistId>
    ) -> ScrollSettleResult {
        guard case .swipe = intent else { return .moved }
        return stash.viewportElementIDs == previousVisibleIds ? .unchanged : .moved
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
