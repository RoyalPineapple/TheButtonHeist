#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

/// Navigation — scroll orchestration and screen exploration.
///
/// Internal component of TheBrains. Owns the scroll engine
/// (`ScrollableTarget`, `SettleSwipeLoopState`, swipe settle) and
/// the explore engine (`ScreenManifest`). Drives TheSafecracker's scroll
/// primitives against TheStash's hierarchy view.
@MainActor
final class Navigation {

    // MARK: - Properties

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let elementInflation: ElementInflation

    /// Last dispatched swipe direction per swipeable target key.
    var lastSwipeDirectionByTarget: [SwipeTargetKey: UIAccessibilityScrollDirection] = [:]

    // MARK: - Init

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.elementInflation = ElementInflation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire
        )
        self.elementInflation.discoverTarget = { [weak self] target in
            guard let self else { return nil }
            return await self.exploreScreen(
                target: target,
                baseline: self.stash.actionDiscoveryBaseline()
            ).screen
        }
        self.elementInflation.revealKnownTarget = { [weak self] heistId in
            guard let self else { return nil }
            return await self.scanForHeistId(heistId)
        }
    }

    // MARK: - Nested Types

    /// Keep swipe gesture timing stable; scrolling cadence is frame-driven.
    static let swipeGestureDuration: GestureDuration = .scrollSwipeDefault

    /// Layout frames to yield after a non-animated UIScrollView scroll before
    /// re-reading the accessibility tree.
    /// Empirical default: 3 frames covers a CATransaction flush plus a UIKit
    /// layout pass without waiting for animations.
    static var postScrollLayoutFrames: Int {
        InsideJobRuntimeKnobs.current.postScrollLayoutFrames
    }

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
        /// Consecutive frames with an unchanged visible id set needed to exit.
        var requiredStableVisibleFrames: Int

        static let directionChange = SettleSwipeProfile(
            minFrames: 6, maxFrames: 24,
            requiredIdleFrames: 2, requiredStableVisibleFrames: 3
        )
        static let sameDirection = SettleSwipeProfile(
            minFrames: 1, maxFrames: 3,
            requiredIdleFrames: 1, requiredStableVisibleFrames: 1
        )
    }

    /// Return value from `SettleSwipeLoopState.advance(...)` — whether the
    /// caller should feed another frame or treat the swipe as settled.
    enum SettleSwipeStep: Equatable { case `continue`, done }

    /// Stable target identity for swipe-dispatched scrolls.
    struct SwipeTargetKey: Hashable, Sendable {
        private let storage: SwipeTargetKeyStorage

        init(containerName: ContainerName) {
            storage = .containerName(containerName)
        }

        init(containerPath: TreePath) {
            storage = .containerPath(containerPath)
        }

        init(frame: CGRect, contentSize: CGSize) {
            storage = .geometry(CoarseScrollGeometry(frame: frame, contentSize: contentSize))
        }
    }

    private enum SwipeTargetKeyStorage: Hashable, Sendable {
        case containerName(ContainerName)
        case containerPath(TreePath)
        case geometry(CoarseScrollGeometry)
    }

    private struct CoarseScrollGeometry: Hashable, Sendable {
        let frame: CoarseRect
        let contentSize: CoarseSize

        init(frame: CGRect, contentSize: CGSize) {
            self.frame = CoarseRect(frame)
            self.contentSize = CoarseSize(contentSize)
        }
    }

    private struct CoarseSize: Hashable, Sendable {
        let width: Int
        let height: Int

        init(_ size: CGSize) {
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
        }
    }

    private struct CoarseRect: Hashable, Sendable {
        let minX: Int
        let minY: Int
        let width: Int
        let height: Int

        init(_ rect: CGRect) {
            minX = Int(rect.minX.rounded())
            minY = Int(rect.minY.rounded())
            width = Int(rect.width.rounded())
            height = Int(rect.height.rounded())
        }
    }

    /// Pure stepwise driver for the swipe-settle loop. Tracks motion-detected
    /// state, idle/stable counters, and exit conditions given a sequence of
    /// per-frame observations. `moved` only latches from false to true.
    ///
    /// **Settle signal boundary.** This is one of four distinct settle
    /// implementations; each watches a different signal because the callers
    /// need different answers:
    ///
    /// 1. `SettleSwipeLoopState` (here) — visible heistId set changes,
    ///    interleaved frame-by-frame with Stash visible observations.
    ///    Answers "did the swipe move us, and has the visible set stopped
    ///    accepting new heistIds?" — the only signal that distinguishes
    ///    spring-bounce-then-settle from edge-rejected gestures.
    /// 2. `SettleSession` / `SemanticQuietSettleSession` (`SettleSession.swift`)
    ///    — AX-tree fingerprint stability, plus VC-change preemption and
    ///    transient-element accumulation. Active heists use the semantic
    ///    quiet-window variant at frame cadence.
    /// 3. `TheTripwire.waitForAllClear(timeout:)` — CADisplayLink-driven
    ///    layer-level quiet detection (no AX tree). Used when we only care
    ///    that animations and layout have flushed.
    /// 4. `TheTripwire.yieldFrames(_:)` / `yieldRealFrames(_:)` — fixed-count
    ///    waits with no termination signal. Empirically calibrated budgets
    ///    for known animation timings (post-reveal SPI scrolls, etc.).
    ///
    /// This loop cannot be folded into (2) or (3): (2) doesn't expose a
    /// `moved` latch and runs its own polling cadence; (3) never reads the
    /// AX tree, so it can't tell whether new heistIds are still arriving.
    struct SettleSwipeLoopState: Equatable {
        let profile: SettleSwipeProfile
        let previousVisibleIds: Set<HeistId>
        private(set) var moved = false
        private(set) var frame = 0
        private var lastVisibleIds: Set<HeistId>
        private var idleFramesWithoutNew = 0
        private var stableVisibleFrames = 0

        init(
            profile: SettleSwipeProfile,
            previousVisibleIds: Set<HeistId>
        ) {
            self.profile = profile
            self.previousVisibleIds = previousVisibleIds
            self.lastVisibleIds = previousVisibleIds
        }

        /// Advance one frame. Pass the current visible id set and the heistIds
        /// newly discovered this frame.
        mutating func advance(
            visibleIds: Set<HeistId>,
            newHeistIds: Set<HeistId>
        ) -> SettleSwipeStep {
            if visibleIds != previousVisibleIds {
                moved = true
            }

            if visibleIds == lastVisibleIds {
                stableVisibleFrames += 1
            } else {
                lastVisibleIds = visibleIds
                stableVisibleFrames = 0
            }

            if newHeistIds.isEmpty {
                idleFramesWithoutNew += 1
            } else {
                idleFramesWithoutNew = 0
            }

            frame += 1

            if frame >= profile.minFrames,
               idleFramesWithoutNew >= profile.requiredIdleFrames,
               stableVisibleFrames >= profile.requiredStableVisibleFrames {
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
    }

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    enum ExplorationOmissionReason: String, Hashable {
        case discoveryScrollLimit = "scroll-attempt-budget"
        case containerScrollLimit = "container-scroll-budget"
        case leadingEdgeResetLimit = "leading-edge-reset-budget"
        case notExplored = "not-explored"
    }

    /// Bookkeeping for a single exploration pass.
    ///
    /// Only fields that are actually consumed by explore-loop control flow live
    /// here. Anything that was "tracked for future use" was removed — add fields
    /// back when they have a real consumer.
    struct ScreenManifest {
        /// Containers that have been fully explored.
        var exploredContainerPaths = Set<TreePath>()

        /// Containers discovered but not yet explored.
        var pendingContainerPaths = Set<TreePath>()

        /// Total scroll attempts during exploration, including edge resets.
        var scrollCount = 0

        /// Per-container scroll attempts during exploration, including edge resets.
        var scrollCountByContainerPath: [TreePath: Int] = [:]

        /// Containers that may have omitted content because exploration stopped early.
        var omittedContainerPaths: [TreePath: Set<ExplorationOmissionReason>] = [:]

        /// Whether the total discovery scroll-attempt cap stopped exploration.
        var discoveryLimitHit = false

        /// Whether a per-container scroll-attempt cap stopped exploration.
        var containerLimitHit = false

        /// Whether the swipeable leading-edge reset hard cap stopped exploration.
        var leadingEdgeResetLimitHit = false

        /// Wall-clock time spent exploring, in seconds.
        var explorationTime: TimeInterval = 0

        /// Safety cap on per-container scroll iterations for this exploration pass.
        let maxScrollsPerContainer: Int

        /// Safety cap on total scroll iterations across this exploration pass.
        let maxScrollsPerDiscovery: Int

        init(
            maxScrollsPerContainer: Int = ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = ScreenManifest.maxScrollsPerDiscovery
        ) {
            self.maxScrollsPerContainer = maxScrollsPerContainer
            self.maxScrollsPerDiscovery = maxScrollsPerDiscovery
        }

        /// Safety cap on per-container scroll iterations.
        static var maxScrollsPerContainer: Int {
            InsideJobRuntimeKnobs.current.maxScrollsPerContainer
        }

        /// Safety cap on total scroll iterations across one discovery pass.
        static var maxScrollsPerDiscovery: Int {
            InsideJobRuntimeKnobs.current.maxScrollsPerDiscovery
        }

        // MARK: - Building

        mutating func recordScrollAttempt(
            in containerPath: TreePath
        ) -> ExplorationOmissionReason? {
            guard scrollCount < maxScrollsPerDiscovery else {
                discoveryLimitHit = true
                return .discoveryScrollLimit
            }
            let containerScrollCount = scrollCountByContainerPath[containerPath, default: 0]
            guard containerScrollCount < maxScrollsPerContainer else {
                containerLimitHit = true
                return .containerScrollLimit
            }
            scrollCountByContainerPath[containerPath] = containerScrollCount + 1
            scrollCount += 1
            return nil
        }

        mutating func markExplored(_ containerPath: TreePath) {
            exploredContainerPaths.insert(containerPath)
            pendingContainerPaths.remove(containerPath)
            omittedContainerPaths.removeValue(forKey: containerPath)
        }

        mutating func addPendingContainers(_ containers: [SemanticScreen.Container]) {
            addPendingContainerPaths(containers.map(\.path))
        }

        mutating func addPendingContainerPaths(_ containerPaths: [TreePath]) {
            pendingContainerPaths.formUnion(containerPaths.filter { !exploredContainerPaths.contains($0) })
        }

        mutating func markOmitted(
            _ containerPath: TreePath,
            reason: ExplorationOmissionReason
        ) {
            pendingContainerPaths.insert(containerPath)
            omittedContainerPaths[containerPath, default: []].insert(reason)
            switch reason {
            case .discoveryScrollLimit:
                discoveryLimitHit = true
            case .containerScrollLimit:
                containerLimitHit = true
            case .leadingEdgeResetLimit:
                leadingEdgeResetLimitHit = true
            case .notExplored:
                break
            }
        }

        func interfaceDiagnostics(
            for screen: Screen,
            includedElementCount: Int
        ) -> InterfaceDiagnostics {
            let omittedContainerDetails = omittedContainerDiagnostics(in: screen)
            let reasonCodes = discoveryReasonCodes(omittedContainerDetails)
            let isLimited = !reasonCodes.isEmpty || !omittedContainerDetails.isEmpty
            return InterfaceDiagnostics(discovery: InterfaceDiscoveryDiagnostics(
                state: isLimited ? .limited : .complete,
                reasonCodes: reasonCodes,
                includedElementCount: includedElementCount,
                scrollAttempts: scrollCount,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery,
                maxScrollsPerContainer: maxScrollsPerContainer,
                exploredScrollableContainerCount: exploredContainerPaths.count,
                omittedScrollableContainerCount: omittedContainerDetails.count,
                omittedContainers: omittedContainerDetails,
                nextAction: isLimited ? nextAction(for: reasonCodes) : nil
            ))
        }

        private func discoveryReasonCodes(
            _ omittedContainerDetails: [InterfaceDiscoveryOmittedContainer]
        ) -> [InterfaceDiscoveryReasonCode] {
            var reasons = Set(omittedContainerDetails.flatMap(\.reasonCodes))
            if discoveryLimitHit { reasons.insert(.discoveryScrollLimit) }
            if containerLimitHit { reasons.insert(.containerScrollLimit) }
            if leadingEdgeResetLimitHit { reasons.insert(.leadingEdgeResetLimit) }
            return reasons.sorted()
        }

        private func nextAction(for reasonCodes: [InterfaceDiscoveryReasonCode]) -> String {
            if reasonCodes.contains(.discoveryScrollLimit) {
                return """
                    Retry get_interface with a higher maxScrollsPerDiscovery or narrow the query to a smaller subtree.
                    """
            }
            if reasonCodes.contains(.containerScrollLimit)
                || reasonCodes.contains(.leadingEdgeResetLimit) {
                return """
                    Retry get_interface with a higher maxScrollsPerContainer or request a smaller scroll container subtree.
                    """
            }
            return "Retry get_interface with a narrower subtree or after manually scrolling the omitted container."
        }

        private func omittedContainerDiagnostics(in screen: Screen) -> [InterfaceDiscoveryOmittedContainer] {
            var containers = omittedContainerPaths
            let pendingReason: ExplorationOmissionReason = discoveryLimitHit ? .discoveryScrollLimit : .notExplored
            for containerPath in pendingContainerPaths where !exploredContainerPaths.contains(containerPath) {
                containers[containerPath, default: []].insert(pendingReason)
            }

            let diagnostics: [InterfaceDiscoveryOmittedContainer] = containers.compactMap { entry in
                let (containerPath, reasons) = entry
                return omittedContainerDiagnostic(containerPath, reasons: reasons, screen: screen)
            }

            return diagnostics.sorted()
        }

        private func omittedContainerDiagnostic(
            _ containerPath: TreePath,
            reasons: Set<ExplorationOmissionReason>,
            screen: Screen
        ) -> InterfaceDiscoveryOmittedContainer? {
            guard let semanticContainer = screen.semantic.containers[containerPath] else { return nil }
            let container = semanticContainer.container
            let frame = container.frame
            let containerName = semanticContainer.containerName

            guard case .scrollable(let contentSize) = container.type else {
                return InterfaceDiscoveryOmittedContainer(
                    containerName: containerName,
                    type: container.typeName,
                    reasonCodes: reasons.interfaceDiscoveryReasonCodes,
                    viewportWidth: Double(frame.size.width),
                    viewportHeight: Double(frame.size.height)
                )
            }

            let scrollAxis = ScrollContainerMetrics.axis(
                contentWidth: Double(contentSize.width),
                contentHeight: Double(contentSize.height),
                viewportWidth: Double(frame.size.width),
                viewportHeight: Double(frame.size.height)
            )
            return InterfaceDiscoveryOmittedContainer(
                containerName: containerName,
                type: container.typeName,
                reasonCodes: reasons.interfaceDiscoveryReasonCodes,
                scrollAxis: scrollAxis,
                viewportWidth: Double(frame.size.width),
                viewportHeight: Double(frame.size.height),
                contentWidth: Double(contentSize.width),
                contentHeight: Double(contentSize.height)
            )
        }

    }

    // MARK: - Clear

    func clearCache() {
        lastSwipeDirectionByTarget.removeAll()
    }
}

private extension Set where Element == Navigation.ExplorationOmissionReason {
    var interfaceDiscoveryReasonCodes: [InterfaceDiscoveryReasonCode] {
        map(\.interfaceDiscoveryReasonCode).sorted()
    }
}

private extension Navigation.ExplorationOmissionReason {
    var interfaceDiscoveryReasonCode: InterfaceDiscoveryReasonCode {
        switch self {
        case .discoveryScrollLimit:
            .discoveryScrollLimit
        case .containerScrollLimit:
            .containerScrollLimit
        case .leadingEdgeResetLimit:
            .leadingEdgeResetLimit
        case .notExplored:
            .notExplored
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
