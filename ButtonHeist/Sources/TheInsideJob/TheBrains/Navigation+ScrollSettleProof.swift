#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Scroll Settle Proof

extension Navigation {

    enum ScrollSettleResult: Equatable {
        case moved
        case unchanged
        case unavailable

        var didMove: Bool {
            self == .moved
        }
    }

    struct ScrollSettleProof {
        let result: ScrollSettleResult
        let previousVisibleIds: Set<HeistId>
    }

    func performViewportTransition(
        primitiveResult: TheSafecracker.ScrollPrimitiveResult,
        previousVisibleIds: Set<HeistId>,
        animated: Bool,
        commitViewportMoves: Bool,
        settleAfterMove: (() async -> ScrollSettleResult)? = nil
    ) async -> ScrollSettleProof {
        switch primitiveResult {
        case .moved:
            if let settleAfterMove {
                return ScrollSettleProof(
                    result: await settleAfterMove(),
                    previousVisibleIds: previousVisibleIds
                )
            }
            if animated {
                _ = await tripwire.waitForAllClear(timeout: 0.5)
            } else {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            }
            observeViewportAfterScroll(commitViewportMoves: commitViewportMoves)
            return ScrollSettleProof(result: .moved, previousVisibleIds: previousVisibleIds)
        case .alreadyInPosition:
            return ScrollSettleProof(result: .unchanged, previousVisibleIds: previousVisibleIds)
        case .unavailable:
            return ScrollSettleProof(result: .unavailable, previousVisibleIds: previousVisibleIds)
        }
    }

    /// Parse through post-gesture spring/inertia and consider the swipe settled
    /// when no new elements are discovered for a short consecutive frame window.
    func settleSwipeMotion(
        previousVisibleIds: Set<HeistId>,
        requireDirectionChangeSettle: Bool,
        commitViewportMoves: Bool = true
    ) async -> ScrollSettleResult {
        let profile: SettleSwipeProfile = requireDirectionChangeSettle
            ? .directionChange
            : .sameDirection
        var state = SettleSwipeLoopState(
            profile: profile,
            previousVisibleIds: previousVisibleIds
        )
        var seenVisibleIds = stash.viewportElementIDs

        while true {
            observeViewportAfterScroll(commitViewportMoves: commitViewportMoves)
            let currentVisibleIds = stash.viewportElementIDs
            let newHeistIds = currentVisibleIds.subtracting(seenVisibleIds)
            seenVisibleIds.formUnion(newHeistIds)

            let step = state.advance(
                visibleIds: currentVisibleIds,
                newHeistIds: newHeistIds
            )
            if case .done = step { break }
            await tripwire.yieldFrames(1)
        }
        return state.moved ? .moved : .unchanged
    }

    func swipeTargetKey(frame: CGRect, contentSize: CGSize) -> SwipeTargetKey {
        SwipeTargetKey(frame: frame, contentSize: contentSize)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
