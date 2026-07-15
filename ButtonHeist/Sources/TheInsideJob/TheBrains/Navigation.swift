#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

import AccessibilitySnapshotParser

/// Navigation — scroll orchestration and screen exploration.
///
/// Internal component of TheBrains. Owns the scroll and exploration engines,
/// and drives TheSafecracker's scroll primitives against TheStash's hierarchy.
@MainActor
final class Navigation {

    // MARK: - Properties

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    lazy var elementInflation = ElementInflation(
        stash: stash,
        safecracker: safecracker,
        tripwire: tripwire,
        exploration: ElementInflation.Exploration(
            discoverTarget: { [weak self] target in
                guard let self else { return nil }
                return await self.exploreScreen(
                    target: target,
                    baseline: .interfaceMemory(self.stash.actionDiscoveryBaseline()),
                    exitPosition: .current,
                    searchOrder: .backwardFirst
                )
            },
            revealKnownTarget: { [weak self] request in
                guard let self else { return nil }
                return await self.scanForHeistId(request.heistId, deadline: request.deadline)
            },
            moveViewport: { [weak self] intent in
                guard let self else { return .unavailable() }
                return await self.performViewportTransition(intent)
            }
        )
    )

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
    static let swipeGestureDuration: GestureDuration = .scrollSwipeDefault

    /// Capture-bound dispatch evidence for one scrollable semantic container.
    ///
    /// `@MainActor` justification: the programmatic case holds a UIScrollView
    /// reference. Both cases retain the capture token until final dispatch.
    @MainActor enum ScrollableTarget { // swiftlint:disable:this agent_main_actor_value_type
        case uiScrollView(
            containerTarget: InterfaceTree.Container,
            object: NSObject,
            scrollView: UIScrollView
        )
        case swipeable(container: TheStash.LiveContainerTarget, frame: CGRect, contentSize: CGSize)

        var containerTarget: InterfaceTree.Container {
            switch self {
            case .uiScrollView(let containerTarget, _, _):
                return containerTarget
            case .swipeable(let container, _, _):
                return container.containerTarget
            }
        }

        var object: NSObject {
            switch self {
            case .uiScrollView(_, let object, _):
                return object
            case .swipeable(let container, _, _):
                return container.object
            }
        }
    }

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    enum ExplorationOmissionReason: String, Hashable, Sendable {
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
        private(set) var exploredScrollPaths = Set<TreePath>()

        /// Containers discovered but not yet explored.
        private(set) var pendingScrollPaths = Set<TreePath>()

        /// Total scroll attempts during exploration, including edge resets.
        var scrollCount = 0

        /// Per-container scroll attempts during exploration, including edge resets.
        var scrollCountByContainerPath: [TreePath: Int] = [:]

        /// Containers that may have omitted content because exploration stopped early.
        var omittedScrollPathReasons: [TreePath: Set<ExplorationOmissionReason>] = [:]

        /// Whether the total discovery scroll-attempt cap stopped exploration.
        private(set) var discoveryLimitHit = false

        /// Whether a per-container scroll-attempt cap stopped exploration.
        private(set) var containerLimitHit = false

        /// Whether the swipeable leading-edge reset hard cap stopped exploration.
        private(set) var leadingEdgeResetLimitHit = false

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
            ButtonHeistRuntimeKnobs.current.maxScrollsPerContainer
        }

        /// Safety cap on total scroll iterations across one discovery pass.
        static var maxScrollsPerDiscovery: Int {
            ButtonHeistRuntimeKnobs.current.maxScrollsPerDiscovery
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
            exploredScrollPaths.insert(containerPath)
            pendingScrollPaths.remove(containerPath)
            omittedScrollPathReasons.removeValue(forKey: containerPath)
        }

        mutating func clearPendingContainers() {
            pendingScrollPaths.removeAll()
        }

        mutating func markDiscoveryLimitHit() {
            discoveryLimitHit = true
        }

        mutating func addPendingContainers(_ containers: [InterfaceTree.Container]) {
            addPendingScrollPaths(containers.map(\.path))
        }

        mutating func addPendingScrollPaths(_ paths: [TreePath]) {
            pendingScrollPaths.formUnion(paths.filter {
                !exploredScrollPaths.contains($0)
                    && omittedScrollPathReasons[$0] == nil
            })
        }

        mutating func markOmitted(
            _ containerPath: TreePath,
            reason: ExplorationOmissionReason
        ) {
            pendingScrollPaths.remove(containerPath)
            exploredScrollPaths.remove(containerPath)
            omittedScrollPathReasons[containerPath, default: []].insert(reason)
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
            for screen: InterfaceObservation,
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
                exploredScrollableContainerCount: exploredScrollPaths.count,
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

        private func omittedContainerDiagnostics(in screen: InterfaceObservation) -> [InterfaceDiscoveryOmittedContainer] {
            var containers = omittedScrollPathReasons
            let pendingReason: ExplorationOmissionReason = discoveryLimitHit ? .discoveryScrollLimit : .notExplored
            for containerPath in pendingScrollPaths where !exploredScrollPaths.contains(containerPath) {
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
            screen: InterfaceObservation
        ) -> InterfaceDiscoveryOmittedContainer? {
            guard let semanticContainer = screen.tree.containers[containerPath] else { return nil }
            let container = semanticContainer.container
            let frame = container.frame
            let containerName = semanticContainer.containerName

            guard let contentSize = container.scrollableContentSize else {
                return InterfaceDiscoveryOmittedContainer(
                    containerName: containerName,
                    type: container.containerPredicateFacts.role.kind,
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
                type: container.containerPredicateFacts.role.kind,
                reasonCodes: reasons.interfaceDiscoveryReasonCodes,
                scrollAxis: scrollAxis,
                viewportWidth: Double(frame.size.width),
                viewportHeight: Double(frame.size.height),
                contentWidth: Double(contentSize.width),
                contentHeight: Double(contentSize.height)
            )
        }

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
