#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

/// Pure execution state for one complete heist.
internal enum HeistExecution {}

extension HeistExecution {
    internal enum Decision {
        case perform(MainActorRequest)
        case wait
        case complete(Completion)
    }

    internal enum MainActorRequest {
        case currentSnapshot(RequestID, scope: SemanticObservationScope)
        case beginObservation(RequestID, ObservationRequest)
        case dispatch(RequestID, ResolvedHeistActionCommand)
        case explore(RequestID, Predicate)
        case finishObservation(
            requestID: RequestID,
            observationID: RequestID,
            exitPosition: Navigation.ViewportExitPosition
        )
        case captureFailureScreenshot(
            RequestID,
            failedPath: HeistExecutionPath,
            mode: ScreenCaptureMode
        )
    }

    internal enum Input {
        case currentSnapshot(RequestID, Observation.Snapshot?)
        case observationBegan(RequestID, baseline: Observation.Snapshot?)
        case event(Observation.Event)
        case dispatchCompleted(RequestID, TheSafecracker.ActionDispatchResult)
        case viewportExited(RequestID, Navigation.ViewportExit.Outcome)
        case observationFinished(
            source: ObservationFinishSource,
            observationID: RequestID,
            evidence: Observation.Evidence,
            outcome: LeafOutcome,
            timing: HeistExpectationTiming
        )
        case failureScreenshotCaptured(RequestID, HeistFailureCapture)
    }

    internal struct Completion {
        internal let steps: [HeistExecutionStepResult]
        internal let failureCapture: HeistFailureCapture?
    }

}

extension HeistExecution {
    internal struct RequestID: RawRepresentable, Sendable, Equatable, Hashable {
        internal let rawValue: UInt64
    }

    internal struct Predicate: Sendable, Equatable {
        internal let authored: AccessibilityPredicate
        internal let resolved: ObservationPredicate
        internal let bindings: HeistExecutionEnvironment

        internal init(
            authored: AccessibilityPredicate,
            bindings: HeistExecutionEnvironment
        ) throws {
            self.authored = authored
            self.resolved = try authored.resolve(in: bindings)
            self.bindings = bindings
        }

        internal var observationScope: SemanticObservationScope {
            resolved.observationScope
        }

        internal var isNotification: Bool {
            if case .notification = resolved { return true }
            return false
        }
    }

    internal enum ActionObservationExpectation: Sendable {
        case authoredThenNoChange(Predicate)
        case noChange

        internal init(
            _ expectation: ActionExecutionExpectation,
            bindings: HeistExecutionEnvironment
        ) throws {
            switch expectation {
            case .authoredThenNoChange(let expectation):
                self = .authoredThenNoChange(try Predicate(
                    authored: expectation.predicate,
                    bindings: bindings
                ))
            case .noChange:
                self = .noChange
            }
        }

        internal var predicates: [ObservationPredicate] {
            switch self {
            case .authoredThenNoChange(let predicate):
                [predicate.resolved, .noChange]
            case .noChange:
                [.noChange]
            }
        }

        internal var authoredPredicate: Predicate? {
            guard case .authoredThenNoChange(let predicate) = self else { return nil }
            return predicate
        }

        internal var observationScope: SemanticObservationScope {
            authoredPredicate?.observationScope ?? .visible
        }
    }

    internal struct ObservationRequest: Sendable, Equatable {
        internal let scope: SemanticObservationScope
        internal let timeout: Duration
    }

    internal enum LeafOutcome: Sendable, Equatable {
        case completed
        case timedOut
        case heistTimedOut
        case cancelled
        case unavailable
        case viewportExitFailed(Navigation.ViewportExit.Failure)
    }

    internal enum ObservationFinishSource: Sendable, Equatable {
        case request(RequestID)
        case deadline
    }
}

extension HeistExecution {
    internal struct Scope: Sendable {
        internal let rootPlan: HeistPlan
        internal let plan: HeistPlan
        internal let definitionPath: [HeistPlanName]
        internal let invocationStack: Set<HeistInvocationPath>

        internal init(
            plan: HeistPlan,
            rootPlan: HeistPlan? = nil,
            definitionPath: [HeistPlanName] = [],
            invocationStack: Set<HeistInvocationPath> = []
        ) {
            self.rootPlan = rootPlan ?? plan
            self.plan = plan
            self.definitionPath = definitionPath
            self.invocationStack = invocationStack
        }
    }

    internal struct StepContext: Sendable {
        internal let path: HeistExecutionPath
        internal let environment: HeistExecutionEnvironment
        internal let scope: Scope
    }

    /// The suspended control-flow operation resumed after the active leaf.
    internal enum Continuation: Sendable {
        case sequence(SequenceContinuation)
        case inline(InlineContinuation)
        case conditional(ConditionalContinuation)
        case forEachElement(ForEachElementContinuation)
        case forEachString(ForEachStringContinuation)
        case repeatUntil(RepeatUntilContinuation)
        case invocation(InvocationContinuation)
        case waitElse(WaitElseContinuation)
    }

    internal struct SequenceContinuation: Sendable {
        internal let steps: [HeistStep]
        internal let context: StepContext
        internal var nextIndex: Int
        internal var children: HeistExecutedChildren
    }

    internal struct InlineContinuation: Sendable {
        internal let plan: HeistPlan
        internal let context: StepContext
    }

    internal struct ConditionalContinuation: Sendable {
        internal let step: ConditionalStep
        internal let context: StepContext
        internal let progress: ConditionalProgress
    }

    internal enum ConditionalProgress: Sendable {
        case awaitingSnapshot(RequestID)
        case selected(HeistCaseSelectionResult)
    }

    internal struct ForEachElementContinuation: Sendable {
        internal let step: ForEachElementStep
        internal let context: StepContext
        internal let resolvedMatching: ResolvedElementPredicate
        internal let matchedCount: Int
        internal var iterationIndex: Int
        internal let progress: ForEachElementProgress
        internal var iterations: HeistExecutedChildren
    }

    internal enum ForEachElementProgress: Sendable {
        case awaitingSnapshot(RequestID, previousMatchHash: SemanticHash?)
        case executing(targetOrdinal: Int, matchHash: SemanticHash)
    }

    internal struct ForEachStringContinuation: Sendable {
        internal let step: ForEachStringStep
        internal let context: StepContext
        internal var iterationIndex: Int
        internal var iterations: HeistExecutedChildren
    }

    internal struct RepeatUntilContinuation: Sendable {
        internal let step: RepeatUntilStep
        internal let resolved: ResolvedRepeatUntilStep
        internal let predicate: Predicate
        internal let context: StepContext
        internal var iterationIndex: Int
        internal var iterations: HeistExecutedChildren
    }

    internal struct InvocationContinuation: Sendable {
        internal let step: HeistInvocationStep
        internal let context: StepContext
        internal let resolvedPath: HeistInvocationPath
    }

    internal struct WaitElseContinuation: Sendable {
        internal let step: WaitStep
        internal let context: StepContext
        internal let evidence: HeistPassedWaitEvidence
    }
}

extension HeistExecution {
    internal enum ActiveLeaf: Sendable {
        case action(ActionLeaf)
        case wait(WaitLeaf)

        internal var id: RequestID {
            switch self {
            case .action(let leaf):
                leaf.id
            case .wait(let leaf):
                leaf.id
            }
        }

        internal func expectationIsProven(
            by evidence: Observation.Evidence
        ) -> Bool {
            proves(predicates, by: evidence)
        }

        internal func needsStabilityCapture(
            after evidence: Observation.Evidence
        ) -> Bool {
            proves(predicates.dropLast(), by: evidence)
                && !expectationIsProven(by: evidence)
        }

        private func proves(
            _ predicates: [ObservationPredicate], by evidence: Observation.Evidence
        ) -> Bool {
            evidence.coverage == .complete && Expectation(
                predicates,
                baseline: evidence.baseline,
                events: evidence.events
            ).result == .satisfied
        }

        private var predicates: [ObservationPredicate] {
            switch self {
            case .action(let leaf):
                leaf.expectation.predicates
            case .wait(let leaf):
                [leaf.predicate.resolved, .noChange]
            }
        }

        internal func admits(_ source: ObservationFinishSource) -> Bool {
            guard case .request(let requestID) = source else { return true }
            switch self {
            case .action(let leaf):
                guard case .finishingObservation(let activeRequestID, _, _) = leaf.phase else {
                    return false
                }
                return activeRequestID == requestID
            case .wait(let leaf):
                guard case .finishingObservation(let activeRequestID, _) = leaf.phase else {
                    return false
                }
                return activeRequestID == requestID
            }
        }
    }

    internal struct ActionLeaf: Sendable {
        internal let id: RequestID
        internal let step: ActionStep
        internal let command: ResolvedHeistActionCommand
        internal let expectation: ActionObservationExpectation
        internal let path: HeistExecutionPath
        internal var phase: ActionLeafPhase

    }

    internal struct WaitLeaf: Sendable {
        internal let id: RequestID
        internal let predicate: Predicate
        internal let purpose: WaitPurpose
        internal var phase: WaitLeafPhase

    }

    internal enum WaitPurpose: Sendable {
        case authored(step: WaitStep, context: StepContext)
        case repeatCheck(loop: RepeatUntilContinuation, bodyChildren: HeistPassingChildren)
    }

    internal enum ActionLeafPhase: Sendable {
        case beginningObservation
        case dispatching(Expectation)
        case observing(Expectation, dispatch: TheSafecracker.ActionDispatchResult)
        case exploring(Expectation, dispatch: TheSafecracker.ActionDispatchResult)
        case finishingObservation(
            RequestID, expectation: Expectation, dispatch: TheSafecracker.ActionDispatchResult
        )

        internal var expectation: Expectation? {
            switch self {
            case .beginningObservation:
                nil
            case .dispatching(let expectation),
                 .observing(let expectation, _),
                 .exploring(let expectation, _),
                 .finishingObservation(_, let expectation, _):
                expectation
            }
        }

        internal var dispatch: TheSafecracker.ActionDispatchResult? {
            switch self {
            case .beginningObservation, .dispatching:
                nil
            case .observing(_, let dispatch),
                 .exploring(_, let dispatch),
                 .finishingObservation(_, _, let dispatch):
                dispatch
            }
        }

    }

    internal enum WaitLeafPhase: Sendable {
        case beginningObservation
        case observing(Expectation)
        case exploring(Expectation)
        case finishingObservation(RequestID, expectation: Expectation)

        internal var expectation: Expectation? {
            switch self {
            case .beginningObservation:
                nil
            case .observing(let expectation),
                 .exploring(let expectation),
                 .finishingObservation(_, let expectation):
                expectation
            }
        }

    }
}

#endif // DEBUG
#endif // canImport(UIKit)
