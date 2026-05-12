#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// Navigation — scroll orchestration and screen exploration.
///
/// Internal component of TheBrains. Owns the scroll engine
/// (`ScrollableTarget`, `SettleSwipeLoopState`, swipe settle) and
/// the explore engine (`ScreenManifest`, `ContainerExploreState`,
/// container fingerprint caching). Drives TheSafecracker's scroll
/// primitives against TheStash's hierarchy view.
@MainActor
final class Navigation {

    // MARK: - Properties

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire

    /// Last dispatched swipe direction per swipeable target key.
    var lastSwipeDirectionByTarget: [String: UIAccessibilityScrollDirection] = [:]

    /// Cached state from the last explore of each scrollable container.
    var containerExploreStates: [AccessibilityContainer: ContainerExploreState] = [:]

    // MARK: - Init

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
    }

    // MARK: - Nested Types

    /// Keep swipe gesture timing stable; scrolling cadence is frame-driven.
    static let swipeGestureDuration: TimeInterval = 0.12

    /// Layout frames to yield after a non-animated UIScrollView scroll or
    /// `scrollToMakeVisible` before re-reading the accessibility tree.
    /// Empirical: 3 frames covers a CATransaction flush plus a UIKit layout
    /// pass without waiting for animations.
    static let postScrollLayoutFrames: Int = 3

    /// Real (CADisplayLink-paced) frames to yield after an accessibility-SPI
    /// scroll jump (`jumpToRecordedPosition`, `restoreScrollPosition`,
    /// `scrollToMakeVisible`-animated). The SPI queues an animated scroll;
    /// `Task.yield` alone won't advance it, so this uses `yieldRealFrames`
    /// (Task.sleep at 16ms intervals). 20 frames is the empirical budget for
    /// that animation to land.
    static let postJumpRealFrames: Int = 20

    /// Maximum pages `scroll_to_edge` will walk before declaring the edge
    /// unreachable. Paired with `element_search`'s 200-page cap declared
    /// locally; the asymmetry is intentional (search is broader than edge-seek).
    static let scrollToEdgeMaxPages: Int = 50

    /// Settle window after `jumpToRecordedPosition` before reading geometry
    /// for the comfort-zone check. Paired with `postJumpRealFrames` — the SPI
    /// jump animates, this is the upper bound on waiting for it to land.
    static let postJumpSettleTimeout: TimeInterval = 1.0

    /// Settle-loop pacing parameters. Two canned profiles: `.directionChange`
    /// is the conservative budget for reversals (spring/inertia takes longer);
    /// `.sameDirection` is the aggressive budget for continuing scrolls.
    struct SettleSwipeProfile: Sendable, Equatable {
        /// Earliest frame at which exit conditions can be evaluated.
        var minFrames: Int
        /// Hard cap on settle polling to avoid long stalls on spring animations.
        var maxFrames: Int
        /// Consecutive frames with no newly-discovered elements needed to exit.
        var requiredIdleFrames: Int
        /// Consecutive frames with an unchanged viewport set needed to exit.
        var requiredStableViewportFrames: Int

        static let directionChange = SettleSwipeProfile(
            minFrames: 6, maxFrames: 24,
            requiredIdleFrames: 2, requiredStableViewportFrames: 3
        )
        static let sameDirection = SettleSwipeProfile(
            minFrames: 1, maxFrames: 3,
            requiredIdleFrames: 1, requiredStableViewportFrames: 1
        )
    }

    /// Return value from `SettleSwipeLoopState.advance(...)` — whether the
    /// caller should feed another frame or treat the swipe as settled.
    enum SettleSwipeStep: Equatable { case `continue`, done }

    /// Pure stepwise driver for the swipe-settle loop. Tracks motion-detected
    /// state, idle/stable counters, and exit conditions given a sequence of
    /// per-frame observations. `moved` only latches from false to true.
    struct SettleSwipeLoopState: Equatable {
        let profile: SettleSwipeProfile
        let previousViewport: Set<String>
        let previousAnchor: Int?

        private(set) var moved = false
        private(set) var frame = 0
        private var lastViewport: Set<String>
        private var idleFramesWithoutNew = 0
        private var stableViewportFrames = 0

        init(
            profile: SettleSwipeProfile,
            previousViewport: Set<String>,
            previousAnchor: Int?
        ) {
            self.profile = profile
            self.previousViewport = previousViewport
            self.previousAnchor = previousAnchor
            self.lastViewport = previousViewport
        }

        /// Advance one frame. Pass the current viewport id set, the current
        /// anchor signature (nil if content-space origins unavailable), and
        /// the heistIds newly discovered this frame.
        mutating func advance(
            viewportIds: Set<String>,
            anchorSignature: Int?,
            newHeistIds: Set<String>
        ) -> SettleSwipeStep {
            if let previousAnchor, let anchorSignature {
                if anchorSignature != previousAnchor { moved = true }
            } else if viewportIds != previousViewport {
                moved = true
            }

            if viewportIds == lastViewport {
                stableViewportFrames += 1
            } else {
                lastViewport = viewportIds
                stableViewportFrames = 0
            }

            if newHeistIds.isEmpty {
                idleFramesWithoutNew += 1
            } else {
                idleFramesWithoutNew = 0
            }

            frame += 1

            if frame >= profile.minFrames,
               idleFramesWithoutNew >= profile.requiredIdleFrames,
               stableViewportFrames >= profile.requiredStableViewportFrames {
                return .done
            }
            if frame >= profile.maxFrames {
                return .done
            }
            return .continue
        }
    }

    /// A scrollable container discovered from the accessibility hierarchy.
    ///
    /// `@MainActor` justification: holds a UIScrollView reference (non-Sendable);
    /// MainActor matches where these targets are resolved and consumed.
    @MainActor enum ScrollableTarget { // swiftlint:disable:this agent_main_actor_value_type
        case uiScrollView(UIScrollView)
        case swipeable(frame: CGRect, contentSize: CGSize)

        var frame: CGRect {
            switch self {
            case .uiScrollView(let sv): return sv.frame
            case .swipeable(let frame, _): return frame
            }
        }

        var contentSize: CGSize {
            switch self {
            case .uiScrollView(let sv): return sv.contentSize
            case .swipeable(_, let cs): return cs
            }
        }
    }

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    /// Cached state from the last explore of each scrollable container.
    struct ContainerExploreState {
        let visibleSubtreeFingerprint: Int
        let discoveredHeistIds: Set<String>
    }

    /// Bookkeeping for a single exploration pass.
    ///
    /// Only fields that are actually consumed downstream (by `ExploreResult` or
    /// explore-loop control flow) live here. Anything that was "tracked for future
    /// use" was removed — add fields back when they have a real consumer.
    struct ScreenManifest {

        /// Containers that have been fully explored.
        var exploredContainers = Set<AccessibilityContainer>()

        /// Containers discovered but not yet explored.
        var pendingContainers = Set<AccessibilityContainer>()

        /// Total scrollByPage calls during exploration. Surfaced as `ExploreResult.scrollCount`.
        var scrollCount = 0

        /// Wall-clock time spent exploring, in seconds. Surfaced as `ExploreResult.explorationTime`.
        var explorationTime: TimeInterval = 0

        /// Safety cap on per-container scroll iterations.
        static let maxScrollsPerContainer = 200

        // MARK: - Building

        mutating func markExplored(_ container: AccessibilityContainer) {
            exploredContainers.insert(container)
            pendingContainers.remove(container)
        }

        mutating func addPendingContainers(_ containers: [AccessibilityContainer]) {
            pendingContainers.formUnion(containers.filter { !exploredContainers.contains($0) })
        }
    }

    // MARK: - Refresh Convenience

    /// Refresh the accessibility tree into the stash. Returns the new Screen
    /// or nil if the parser couldn't produce one.
    @discardableResult
    func refresh() -> Screen? {
        stash.refresh()
    }

    // MARK: - Clear

    func clearCache() {
        containerExploreStates.removeAll()
        lastSwipeDirectionByTarget.removeAll()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
