#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

/// Pure execution state for one complete heist.
internal enum HeistExecution {}

extension HeistExecution {
    internal enum State {
        case pending(Action)
        case complete(Completion)
    }

    internal enum Action {
        case perform([MainActorRequest])
        case wait
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
        case observationBegan(RequestID, TheVault.State.HistoryBoundary)
        case event(Observation.Event)
        case dispatchCompleted(RequestID, TheSafecracker.ActionDispatchResult)
        case viewportExited(RequestID, Navigation.ViewportExit.Outcome)
        case observationFinished(
            source: ObservationFinishSource,
            observationID: RequestID,
            evidence: Observation.Evidence,
            outcome: LeafOutcome
        )
        case failureScreenshotCaptured(RequestID, HeistExecutionStepResult?)
    }

    internal struct Completion {
        internal let steps: [HeistExecutionStepResult]
        internal let abortedAtPath: HeistExecutionPath?
    }

    internal struct PendingFailureScreenshot {
        internal let id: RequestID
        internal let children: HeistExecutedChildren
    }
}

extension HeistExecution {
    internal struct RequestID: RawRepresentable, Sendable, Equatable, Hashable {
        internal let rawValue: UInt64
    }

    internal struct Predicate: Sendable, Equatable {
        internal let authored: AccessibilityPredicate
        internal let resolved: ObservationPredicate

        internal var observationScope: SemanticObservationScope {
            resolved.observationScope
        }

        internal var isNotification: Bool {
            if case .notification = resolved { return true }
            return false
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
        internal let evidence: HeistWaitUnmatchedEvidence
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

        internal var expectationIsSatisfied: Bool {
            switch self {
            case .action(let leaf):
                leaf.expectation.result == .satisfied
            case .wait(let leaf):
                leaf.expectation.result == .satisfied
            }
        }

        internal var finishingObservationRequestID: RequestID? {
            switch self {
            case .action(let leaf):
                leaf.phase.finishingObservationRequestID
            case .wait(let leaf):
                leaf.phase.finishingObservationRequestID
            }
        }
    }

    internal struct ActionLeaf: Sendable {
        internal let id: RequestID
        internal let step: ActionStep
        internal let command: ResolvedHeistActionCommand
        internal let predicate: Predicate?
        internal let timeout: Duration
        internal let context: StepContext
        internal var phase: LeafPhase
        internal var boundary: TheVault.State.HistoryBoundary?
        internal var expectation: Expectation
        internal var dispatch: TheSafecracker.ActionDispatchResult?
    }

    internal struct WaitLeaf: Sendable {
        internal let id: RequestID
        internal let step: WaitStep
        internal let predicate: Predicate
        internal let timeout: Duration
        internal let context: StepContext
        internal var phase: LeafPhase
        internal var boundary: TheVault.State.HistoryBoundary?
        internal var expectation: Expectation
    }

    internal enum LeafPhase: Sendable, Equatable {
        case beginningObservation
        case dispatching
        case observing
        case exploring
        case finishingObservation(RequestID)

        internal var finishingObservationRequestID: RequestID? {
            guard case .finishingObservation(let requestID) = self else {
                return nil
            }
            return requestID
        }

        internal func admits(_ source: ObservationFinishSource) -> Bool {
            switch source {
            case .request(let requestID):
                self == .finishingObservation(requestID)
            case .deadline:
                true
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
