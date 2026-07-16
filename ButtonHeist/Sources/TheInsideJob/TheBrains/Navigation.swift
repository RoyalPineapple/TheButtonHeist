#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

import AccessibilitySnapshotParser

@MainActor
final class Navigation {

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
                    searchOrder: .backwardFirst,
                )
            },
            revealKnownTarget: { [weak self] request in
                guard let self else { return nil }
                return await self.scanForHeistId(
                    request.heistId,
                    deadline: request.deadline,
                )
            },
            moveViewport: { [weak self] intent in
                guard let self else { return .unavailable() }
                return await self.performViewportTransition(intent)
            }
        )
    )

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
    }

    static let swipeGestureDuration: GestureDuration = .scrollSwipeDefault

    @MainActor enum ScrollableTarget { // swiftlint:disable:this agent_main_actor_value_type
        case uiScrollView(
            container: TheStash.LiveContainerTarget,
            scrollView: UIScrollView
        )
        case swipeable(container: TheStash.LiveContainerTarget, contentSize: CGSize)

        var containerTarget: InterfaceTree.Container {
            switch self {
            case .uiScrollView(let container, _), .swipeable(let container, _):
                return container.containerTarget
            }
        }

        var object: NSObject {
            switch self {
            case .uiScrollView(let container, _), .swipeable(let container, _):
                return container.object
            }
        }

        static func programmatic(
            _ scrollView: UIScrollView,
            in stash: TheStash
        ) -> ScrollableTarget? {
            let paths = stash.scrollableContainerViewsByPath
                .compactMap { path, reference in reference === scrollView ? path : nil }
                .sorted()
            for path in paths {
                guard let semanticContainer = stash.latestObservation.tree.containers[path],
                      case .resolved(let liveContainer) = stash.resolveLiveContainerTarget(
                          for: semanticContainer
                      ) else { continue }
                return .uiScrollView(container: liveContainer, scrollView: scrollView)
            }
            return nil
        }

        func dispatchOnFreshScrollView<Value: Sendable>(
            in stash: TheStash,
            operation: (UIScrollView) -> Value
        ) -> Value? {
            guard case .uiScrollView(let container, _) = self else { return nil }
            let dispatch = stash.dispatchOnFreshLiveContainerTarget(
                container,
            ) { currentContainer -> Value? in
                guard let scrollView = stash.liveScrollableContainerView(
                    forPath: currentContainer.containerTarget.path
                ) else { return nil }
                return operation(scrollView)
            }
            switch dispatch {
            case .success(let value):
                return value
            case .failure:
                return nil
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

    struct ScreenManifest {
        private(set) var exploredScrollPaths = Set<TreePath>()

        private(set) var pendingScrollPaths = Set<TreePath>()

        var scrollCount = 0

        var scrollCountByContainerPath: [TreePath: Int] = [:]

        var omittedScrollPathReasons: [TreePath: Set<ExplorationOmissionReason>] = [:]

        private(set) var discoveryLimitHit = false

        private(set) var containerLimitHit = false

        private(set) var leadingEdgeResetLimitHit = false

        var explorationTime: TimeInterval = 0

        let maxScrollsPerContainer: Int

        let maxScrollsPerDiscovery: Int

        init(
            maxScrollsPerContainer: Int = ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = ScreenManifest.maxScrollsPerDiscovery
        ) {
            self.maxScrollsPerContainer = maxScrollsPerContainer
            self.maxScrollsPerDiscovery = maxScrollsPerDiscovery
        }

        static var maxScrollsPerContainer: Int {
            ButtonHeistRuntimeKnobs.current.maxScrollsPerContainer
        }

        static var maxScrollsPerDiscovery: Int {
            ButtonHeistRuntimeKnobs.current.maxScrollsPerDiscovery
        }

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
