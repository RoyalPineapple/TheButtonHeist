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
        previousAnchor: Int?,
        requireDirectionChangeSettle: Bool
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
            stash.refreshTreeAfterViewportMove()
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
    ///
    /// The returned hash is **in-process only** — Swift's hash seed is
    /// randomized per launch, so never persist, log, or compare these values
    /// across processes.
    func visibleAnchorSignature() -> Int? {
        let anchors = stash.visibleContentOriginAnchors().map { anchor in
            let origin = anchor.origin
            return "\(anchor.heistId):\(Int(origin.x.rounded())):\(Int(origin.y.rounded()))"
        }.sorted()
        guard !anchors.isEmpty else { return nil }
        return anchors.joined(separator: "|").hashValue
    }

    func swipeTargetKey(frame: CGRect, contentSize: CGSize) -> String {
        let values = [
            Int(frame.minX.rounded()),
            Int(frame.minY.rounded()),
            Int(frame.width.rounded()),
            Int(frame.height.rounded()),
            Int(contentSize.width.rounded()),
            Int(contentSize.height.rounded())
        ]
        return values.map(String.init).joined(separator: ":")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
