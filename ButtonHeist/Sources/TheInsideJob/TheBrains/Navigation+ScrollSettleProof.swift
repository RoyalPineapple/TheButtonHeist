#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Scroll Settle Proof

extension Navigation {

    enum ScrollSettleResult: Equatable {
        case moved
        case unchanged

        var didMove: Bool {
            self == .moved
        }
    }

    struct ScrollSettleProof {
        let result: ScrollSettleResult
        let previousVisibleIds: Set<HeistId>
    }

    /// Parse through post-gesture spring/inertia and consider the swipe settled
    /// when no new elements are discovered for a short consecutive frame window.
    func settleSwipeMotion(
        previousVisibleIds: Set<HeistId>,
        previousAnchor: VisibleAnchorSignature?,
        requireDirectionChangeSettle: Bool,
        commitViewportMoves: Bool = true
    ) async -> ScrollSettleResult {
        let profile: SettleSwipeProfile = requireDirectionChangeSettle
            ? .directionChange
            : .sameDirection
        var state = SettleSwipeLoopState(
            profile: profile,
            previousVisibleIds: previousVisibleIds,
            previousAnchor: previousAnchor
        )
        var seenVisibleIds = stash.visibleIds

        while true {
            observeViewportAfterScroll(commitViewportMoves: commitViewportMoves)
            let currentVisibleIds = stash.visibleIds
            let newHeistIds = currentVisibleIds.subtracting(seenVisibleIds)
            seenVisibleIds.formUnion(newHeistIds)

            let step = state.advance(
                visibleIds: currentVisibleIds,
                anchorSignature: visibleAnchorSignature(),
                newHeistIds: newHeistIds
            )
            if case .done = step { break }
            await tripwire.yieldFrames(1)
        }
        return state.moved ? .moved : .unchanged
    }

    /// Stable signature for the viewport based on content-space origins.
    /// Avoids treating edge bounces/re-parses as true movement.
    func visibleAnchorSignature() -> VisibleAnchorSignature? {
        let anchors = stash.visibleContentOriginAnchors()
        guard !anchors.isEmpty else { return nil }
        return VisibleAnchorSignature(anchors: anchors)
    }

    func swipeTargetKey(frame: CGRect, contentSize: CGSize) -> SwipeTargetKey {
        SwipeTargetKey(frame: frame, contentSize: contentSize)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
