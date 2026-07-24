#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ButtonHeistSupport

import TheScore
import ThePlans

extension Navigation {

    enum ExplorationBaseline {
        case interfaceMemory(InterfaceObservation)
        case currentViewport(InterfaceObservation)

        var discoveryCommitPolicy: DiscoveryCommitPolicy {
            switch self {
            case .interfaceMemory:
                .mergeIntoInterface
            case .currentViewport:
                .replaceInterface
            }
        }
    }

    enum DiscoveryCommitPolicy: Equatable, Sendable {
        case mergeIntoInterface
        case replaceInterface
    }

    enum ViewportExplorationDecision: Equatable, Sendable {
        case `continue`
        case goalSatisfied
    }

    enum ViewportExitPosition: Equatable, Sendable {
        case origin
        case current
    }

    enum ViewportExit {}
}

extension Navigation.ViewportExit {
    enum Outcome: Equatable, Sendable {
        case restored
        case retained
        case superseded
        case failed(Failure)
    }

    enum Failure: Equatable, Sendable {
        case originUnavailable
    }
}

extension Navigation {
    enum ViewportSearchOrder: Equatable, Sendable {
        case forwardFirst
        case backwardFirst

        var directions: [ScrollScanDirection] {
            switch self {
            case .forwardFirst:
                [.forward, .back]
            case .backwardFirst:
                [.back, .forward]
            }
        }
    }

    struct ContainerExploration {
        let semanticContainer: InterfaceTree.Container
        let savedVisualOrigin: CGPoint
        let hasHOverflow: Bool
        let hasVOverflow: Bool

        var container: AccessibilityContainer { semanticContainer.container }

        var path: TreePath { semanticContainer.path }
    }

    enum ScrollScanDirection: Equatable, Sendable {
        case forward
        case back
    }

    enum ScrollScanOutcome: Equatable, Sendable {
        case goalSatisfied
        case exhausted
        case screenReplaced
        case limitHit(InterfaceDiscoveryReasonCode)
        case interrupted
    }

    struct InterfaceExplorationResult {
        let event: Observation.SnapshotEvent
        let progress: InterfaceExplorationProgress
        let didMoveViewport: Bool
        let viewportExit: ViewportExit.Outcome

        internal init(
            event: Observation.SnapshotEvent,
            progress: InterfaceExplorationProgress,
            didMoveViewport: Bool = false,
            viewportExit: ViewportExit.Outcome
        ) {
            self.event = event
            self.progress = progress
            self.didMoveViewport = didMoveViewport
            self.viewportExit = viewportExit
        }
    }

    struct SemanticExploration {
        var progress: InterfaceExplorationProgress
        private(set) var discoveryCommitPolicy: DiscoveryCommitPolicy
        let deadline: SemanticObservationDeadline?

        init(
            baseline: ExplorationBaseline,
            deadline: SemanticObservationDeadline? = nil,
            maxScrollsPerContainer: Int = InterfaceExplorationProgress.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = InterfaceExplorationProgress.maxScrollsPerDiscovery
        ) {
            discoveryCommitPolicy = baseline.discoveryCommitPolicy
            self.deadline = deadline
            progress = InterfaceExplorationProgress(
                maxScrollsPerContainer: maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery
            )
        }

        var hasTimeRemaining: Bool {
            deadline?.hasTimeRemaining(at: RuntimeElapsed.now) ?? true
        }

        mutating func recordCommittedObservation(
            continuity: ScreenContinuity,
            scrollableContainers: [InterfaceTree.Container]
        ) {
            discoveryCommitPolicy = .mergeIntoInterface
            if continuity.isReplacement {
                let scrollCount = progress.scrollCount
                progress = InterfaceExplorationProgress(
                    maxScrollsPerContainer: progress.maxScrollsPerContainer,
                    maxScrollsPerDiscovery: progress.maxScrollsPerDiscovery
                )
                progress.scrollCount = scrollCount
            }
            addDiscoveredContainers(scrollableContainers)
        }

        mutating func markExplored(_ container: InterfaceTree.Container) {
            progress.markExplored(container.path)
        }

        mutating func addDiscoveredContainers(_ containers: [InterfaceTree.Container]) {
            let newContainers = containers.filter {
                !progress.exploredScrollPaths.contains($0.path)
                    && !progress.pendingScrollPaths.contains($0.path)
            }
            progress.addPendingContainers(newContainers)
        }

        mutating func finish(
            startTime: CFTimeInterval,
            event: Observation.SnapshotEvent,
            didMoveViewport: Bool,
            viewportExit: ViewportExit.Outcome
        ) -> InterfaceExplorationResult {
            progress.explorationTime = CACurrentMediaTime() - startTime
            return InterfaceExplorationResult(
                event: event,
                progress: progress,
                didMoveViewport: didMoveViewport,
                viewportExit: viewportExit
            )
        }
    }

    func exploreForWait(
        target: ResolvedAccessibilityTarget?,
        deadline: SemanticObservationDeadline,
        stopWhen: @escaping @MainActor () -> Bool
    ) async -> ViewportExit.Outcome {
        guard deadline.hasTimeRemaining(at: RuntimeElapsed.now) else { return .restored }
        if let target,
           target.isElementTarget,
           case .resolved(.element) = vault.resolveTarget(target) {
            let inflation = await elementInflation.inflate(
                for: target,
                method: .scrollToVisible,
                operationDeadline: deadline
            )
            switch inflation {
            case .inflated:
                return .retained
            case .failed:
                return .restored
            }
        }

        guard let exploration = await exploreScreen(
            target: target,
            baseline: .currentViewport(
                vault.visibleExplorationBaseline(from: vault.latestObservation)
            ),
            exitPosition: .origin,
            deadline: deadline,
            onObservation: { _ in
                stopWhen() ? .goalSatisfied : .continue
            }
        ) else {
            return .restored
        }
        return exploration.viewportExit
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
