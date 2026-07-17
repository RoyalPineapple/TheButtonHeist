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

    struct ExploredScreen {
        let event: SettledSemanticObservationEvent
        let manifest: ScreenManifest
        let didMoveViewport: Bool

        internal init(
            event: SettledSemanticObservationEvent,
            manifest: ScreenManifest,
            didMoveViewport: Bool = false
        ) {
            self.event = event
            self.manifest = manifest
            self.didMoveViewport = didMoveViewport
        }
    }

    struct SemanticExploration {
        var manifest: ScreenManifest
        private(set) var discoveryCommitPolicy: DiscoveryCommitPolicy
        let deadline: SemanticObservationDeadline?

        init(
            baseline: ExplorationBaseline,
            deadline: SemanticObservationDeadline? = nil,
            maxScrollsPerContainer: Int = ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = ScreenManifest.maxScrollsPerDiscovery
        ) {
            discoveryCommitPolicy = baseline.discoveryCommitPolicy
            self.deadline = deadline
            manifest = ScreenManifest(
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
                let scrollCount = manifest.scrollCount
                manifest = ScreenManifest(
                    maxScrollsPerContainer: manifest.maxScrollsPerContainer,
                    maxScrollsPerDiscovery: manifest.maxScrollsPerDiscovery
                )
                manifest.scrollCount = scrollCount
            }
            addDiscoveredContainers(scrollableContainers)
        }

        mutating func markExplored(_ container: InterfaceTree.Container) {
            manifest.markExplored(container.path)
        }

        mutating func addDiscoveredContainers(_ containers: [InterfaceTree.Container]) {
            let newContainers = containers.filter {
                !manifest.exploredScrollPaths.contains($0.path)
                    && !manifest.pendingScrollPaths.contains($0.path)
            }
            manifest.addPendingContainers(newContainers)
        }

        mutating func finish(
            startTime: CFTimeInterval,
            event: SettledSemanticObservationEvent,
            didMoveViewport: Bool
        ) -> ExploredScreen {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return ExploredScreen(
                event: event,
                manifest: manifest,
                didMoveViewport: didMoveViewport
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
