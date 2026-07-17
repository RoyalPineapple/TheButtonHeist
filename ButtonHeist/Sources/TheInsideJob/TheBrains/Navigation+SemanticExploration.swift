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

    enum DiscoveryCommitPolicy: Equatable {
        case mergeIntoInterface
        case replaceInterface
    }

    enum ViewportExplorationDecision: Equatable, Sendable {
        case `continue`
        case finish
    }

    enum ViewportExitPosition: Equatable, Sendable {
        case origin
        case current
    }

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

    enum ScrollContainerScanResult: Equatable, Sendable {
        case finished
        case completed
        case screenReplaced
        case omitted(InterfaceDiscoveryReasonCode)
        case interrupted
    }

    enum ScrollScanOutcome: Equatable, Sendable {
        case finished
        case exhausted
        case screenReplaced
        case limitHit(InterfaceDiscoveryReasonCode)
        case interrupted
    }

    struct InterfaceExplorationResult {
        let event: SettledObservationEvent
        let progress: InterfaceExplorationProgress
        let didMoveViewport: Bool

        internal init(
            event: SettledObservationEvent,
            progress: InterfaceExplorationProgress,
            didMoveViewport: Bool = false
        ) {
            self.event = event
            self.progress = progress
            self.didMoveViewport = didMoveViewport
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
            deadline?.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) ?? true
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
            event: SettledObservationEvent,
            didMoveViewport: Bool
        ) -> InterfaceExplorationResult {
            progress.explorationTime = CACurrentMediaTime() - startTime
            return InterfaceExplorationResult(
                event: event,
                progress: progress,
                didMoveViewport: didMoveViewport
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
