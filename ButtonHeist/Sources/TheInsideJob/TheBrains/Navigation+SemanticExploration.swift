#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ButtonHeistSupport

import TheScore
import ThePlans

extension Navigation {

    struct ContainerExploration {
        let semanticContainer: SemanticScreen.Container
        let scrollView: UIScrollView
        let hasHOverflow: Bool
        let hasVOverflow: Bool

        var container: AccessibilityContainer { semanticContainer.container }

        var path: TreePath { semanticContainer.path }

        @MainActor
        var savedVisualOrigin: CGPoint {
            Navigation.visualOrigin(in: scrollView)
        }
    }

    enum ScrollScanDirection: Equatable, Sendable {
        case forward
        case back
    }

    enum ScrollScanGoal: Equatable, Sendable {
        case exhaust
        case findTarget(AccessibilityTarget)
        case findHeistId(HeistId)
    }

    enum ScrollTraversalTerminal: Equatable, Sendable {
        case foundTarget(AccessibilityTarget)
        case foundHeistId(HeistId)
        case coverageComplete
    }

    enum ScrollContainerScanResult: Equatable, Sendable {
        case terminal(ScrollTraversalTerminal)
        case completed
        case omitted(ExplorationOmissionReason)
    }

    enum ScrollScanOutcome: Equatable, Sendable {
        case terminal(ScrollTraversalTerminal)
        case exhausted
        case limitHit(ExplorationOmissionReason)
    }

    struct ScrollScanPlan {
        let container: ContainerExploration
        let direction: ScrollScanDirection
        let goal: ScrollScanGoal
        let animated: Bool

        init(
            container: ContainerExploration,
            direction: ScrollScanDirection,
            goal: ScrollScanGoal,
            animated: Bool = false
        ) {
            self.container = container
            self.direction = direction
            self.goal = goal
            self.animated = animated
        }
    }

    enum ScrollContainerScanState: Equatable, Sendable {
        case idle
        case scanning(ScrollScanDirection)
        case restoring(ScrollContainerScanRestore)
        case finished(ScrollContainerScanResult)
    }

    enum ScrollContainerScanEvent: Equatable, Sendable {
        case begin
        case scanCompleted(ScrollScanOutcome)
        case restoreCompleted
    }

    enum ScrollContainerScanEffect: Equatable, Sendable {
        case run(ScrollScanDirection)
        case restore
        case finish(ScrollContainerScanResult)
    }

    enum ScrollContainerScanRejection: Equatable, Sendable {
        case alreadyStarted
        case alreadyFinished
        case scanOutcomeWithoutActiveScan
        case restoreWithoutPendingRestore
    }

    enum ScrollContainerScanRestore: Equatable, Sendable {
        case beforeBackwardScan
        case beforeOmission(ExplorationOmissionReason)
        case beforeCompletion
    }

    struct ScrollContainerScanMachine: SimpleStateMachine, Equatable {
        func advance(
            _ state: ScrollContainerScanState,
            with event: ScrollContainerScanEvent
        ) -> StateChange<ScrollContainerScanState, ScrollContainerScanEffect, ScrollContainerScanRejection> {
            switch (state, event) {
            case (.idle, .begin):
                return .changed(to: .scanning(.forward), effects: [.run(.forward)])

            case (.idle, .scanCompleted),
                 (.idle, .restoreCompleted):
                return .rejected(.scanOutcomeWithoutActiveScan, stayingIn: state)

            case (.scanning(let direction), .scanCompleted(let outcome)):
                return Self.advanceScanning(direction: direction, outcome: outcome)

            case (.scanning, .begin):
                return .rejected(.alreadyStarted, stayingIn: state)

            case (.scanning, .restoreCompleted):
                return .rejected(.restoreWithoutPendingRestore, stayingIn: state)

            case (.restoring(let restore), .restoreCompleted):
                return Self.advanceRestoring(restore)

            case (.restoring, .begin):
                return .rejected(.alreadyStarted, stayingIn: state)

            case (.restoring, .scanCompleted):
                return .rejected(.scanOutcomeWithoutActiveScan, stayingIn: state)

            case (.finished, _):
                return .rejected(.alreadyFinished, stayingIn: state)
            }
        }

        private static func advanceScanning(
            direction: ScrollScanDirection,
            outcome: ScrollScanOutcome
        ) -> StateChange<ScrollContainerScanState, ScrollContainerScanEffect, ScrollContainerScanRejection> {
            switch (direction, outcome) {
            case (_, .terminal(let terminal)):
                let result = ScrollContainerScanResult.terminal(terminal)
                return .changed(to: .finished(result), effects: [.finish(result)])

            case (.forward, .exhausted):
                return .changed(to: .restoring(.beforeBackwardScan), effects: [.restore])

            case (.forward, .limitHit(let reason)):
                return .changed(to: .restoring(.beforeOmission(reason)), effects: [.restore])

            case (.back, .exhausted):
                return .changed(to: .restoring(.beforeCompletion), effects: [.restore])

            case (.back, .limitHit(let reason)):
                return .changed(to: .restoring(.beforeOmission(reason)), effects: [.restore])
            }
        }

        private static func advanceRestoring(
            _ restore: ScrollContainerScanRestore
        ) -> StateChange<ScrollContainerScanState, ScrollContainerScanEffect, ScrollContainerScanRejection> {
            switch restore {
            case .beforeBackwardScan:
                return .changed(to: .scanning(.back), effects: [.run(.back)])

            case .beforeOmission(let reason):
                let result = ScrollContainerScanResult.omitted(reason)
                return .changed(to: .finished(result), effects: [.finish(result)])

            case .beforeCompletion:
                return .changed(to: .finished(.completed), effects: [.finish(.completed)])
            }
        }
    }

    struct ExploredScreen {
        let screen: Screen
        let manifest: ScreenManifest
    }

    struct SemanticExploration {
        var screen: Screen
        var manifest: ScreenManifest

        init(
            baseline: Screen,
            maxScrollsPerContainer: Int = ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = ScreenManifest.maxScrollsPerDiscovery
        ) {
            screen = baseline
            manifest = ScreenManifest(
                maxScrollsPerContainer: maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery
            )
        }

        mutating func absorb(_ parsed: Screen?) {
            guard let parsed else { return }
            screen = screen.merging(parsed)
            addDiscoveredContainers(parsed.orderedContainers.filter { $0.container.isScrollable })
        }

        mutating func markExplored(_ container: SemanticScreen.Container) {
            manifest.markExplored(container.path)
        }

        mutating func addDiscoveredContainers(_ containers: [SemanticScreen.Container]) {
            let newContainers = containers.filter {
                !manifest.exploredScrollPaths.contains($0.path)
                    && !manifest.pendingScrollPaths.contains($0.path)
            }
            manifest.addPendingContainers(newContainers)
        }

        mutating func finish(startTime: CFTimeInterval) -> ExploredScreen {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return ExploredScreen(screen: screen, manifest: manifest)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
