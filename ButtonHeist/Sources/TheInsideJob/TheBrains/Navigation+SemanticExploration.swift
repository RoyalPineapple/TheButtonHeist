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

        var screen: InterfaceObservation {
            switch self {
            case .interfaceMemory(let screen), .currentViewport(let screen):
                screen
            }
        }

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

    enum ExplorationGenerationDisposition: Equatable {
        case preservesGeneration
        case replacesGeneration(reason: AccessibilityObservationFallbackReason)

        mutating func record(_ classification: ScreenClassifier.Classification) {
            guard case .inferredScreenChange(let reason) = classification else { return }
            self = .replacesGeneration(reason: reason)
        }
    }

    enum SemanticExplorationScope {
        case manifestBoundedDiscovery
        case knownTargetReveal(SemanticObservationDeadline)
    }

    struct ContainerExploration {
        let semanticContainer: InterfaceTree.Container
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
        case screenReplaced
        case omitted(ExplorationOmissionReason)
    }

    enum ScrollScanOutcome: Equatable, Sendable {
        case terminal(ScrollTraversalTerminal)
        case exhausted
        case screenReplaced
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
            case (_, .screenReplaced):
                return .changed(to: .finished(.screenReplaced), effects: [.finish(.screenReplaced)])

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
        let screen: InterfaceObservation
        let manifest: ScreenManifest
        let generationDisposition: ExplorationGenerationDisposition
        let discoveryCommitPolicy: DiscoveryCommitPolicy

        internal init(
            screen: InterfaceObservation,
            manifest: ScreenManifest,
            generationDisposition: ExplorationGenerationDisposition,
            discoveryCommitPolicy: DiscoveryCommitPolicy
        ) {
            self.screen = screen
            self.manifest = manifest
            self.generationDisposition = generationDisposition
            self.discoveryCommitPolicy = discoveryCommitPolicy
        }
    }

    struct SemanticExploration {
        var screen: InterfaceObservation
        var manifest: ScreenManifest
        let scope: SemanticExplorationScope
        let discoveryCommitPolicy: DiscoveryCommitPolicy
        private(set) var generationDisposition = ExplorationGenerationDisposition.preservesGeneration

        init(
            baseline: ExplorationBaseline,
            maxScrollsPerContainer: Int = ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: Int = ScreenManifest.maxScrollsPerDiscovery
        ) {
            screen = baseline.screen
            scope = .manifestBoundedDiscovery
            discoveryCommitPolicy = baseline.discoveryCommitPolicy
            manifest = ScreenManifest(
                maxScrollsPerContainer: maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery
            )
        }

        init(baseline: InterfaceObservation, knownTargetDeadline: SemanticObservationDeadline) {
            screen = baseline
            scope = .knownTargetReveal(knownTargetDeadline)
            discoveryCommitPolicy = .mergeIntoInterface
            manifest = ScreenManifest()
        }

        var hasTimeRemaining: Bool {
            switch scope {
            case .manifestBoundedDiscovery:
                return true
            case .knownTargetReveal(let deadline):
                return deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent())
            }
        }

        func cappedAnimatedWait(_ maximum: TimeInterval) -> TimeInterval {
            switch scope {
            case .manifestBoundedDiscovery:
                return maximum
            case .knownTargetReveal(let deadline):
                return min(maximum, deadline.remainingSeconds())
            }
        }

        @discardableResult
        @MainActor
        mutating func absorb(_ parsed: InterfaceObservation?) -> ScreenClassifier.Classification? {
            guard let parsed else { return nil }
            let classification = ScreenClassifier.classify(
                before: ScreenClassifier.snapshot(of: screen.tree),
                after: ScreenClassifier.snapshot(of: parsed.tree),
                notifications: []
            )
            return absorb(parsed, classification: classification)
        }

        @discardableResult
        @MainActor
        mutating func absorbScrolledPage(
            _ parsed: InterfaceObservation,
            notificationBatch: AccessibilityNotificationBatch?
        ) -> ScreenClassifier.Classification {
            let classification: ScreenClassifier.Classification = if notificationBatch?.events.contains(where: {
                if case .screenChanged = $0.kind { return true }
                return false
            }) == true {
                .screenChangedNotification
            } else {
                .sameGeneration
            }
            return absorb(parsed, classification: classification)
        }

        private mutating func absorb(
            _ parsed: InterfaceObservation,
            classification: ScreenClassifier.Classification
        ) -> ScreenClassifier.Classification {
            generationDisposition.record(classification)
            if classification.isScreenReplacement {
                // A replacement starts a new graph, not a new execution budget.
                let scrollCount = manifest.scrollCount
                manifest = ScreenManifest(
                    maxScrollsPerContainer: manifest.maxScrollsPerContainer,
                    maxScrollsPerDiscovery: manifest.maxScrollsPerDiscovery
                )
                manifest.scrollCount = scrollCount
                screen = parsed
            } else {
                do {
                    screen = try parsed.replacingTreeWithCurrentCapture(
                        screen.tree.merging(parsed.tree)
                    )
                } catch {
                    preconditionFailure("Exploration observation failed validation: \(error)")
                }
            }
            addDiscoveredContainers(parsed.orderedContainers.filter { $0.container.isScrollable })
            return classification
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

        mutating func finish(startTime: CFTimeInterval) -> ExploredScreen {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return ExploredScreen(
                screen: screen,
                manifest: manifest,
                generationDisposition: generationDisposition,
                discoveryCommitPolicy: discoveryCommitPolicy
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
