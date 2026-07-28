#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

/// The single owner of heist progress and its next executable action.
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
        case dispatch(OperationID, ResolvedHeistActionCommand)
        case explore(OperationID, Predicate, SemanticObservationDeadline)
        case finishExploration(OperationID)
    }

    internal enum Input {
        case event(Observation.Event)
        case dispatchCompleted(OperationID, TheSafecracker.ActionDispatchResult)
        case viewportExited(OperationID, Navigation.ViewportExit.Outcome)
    }
}

extension HeistExecution {
    internal struct Predicate: Sendable, Equatable {
        internal let authored: AccessibilityPredicate
        internal let resolved: Observation.Event.Predicate

        internal var observationScope: SemanticObservationScope {
            resolved.observationScope
        }
    }

    internal enum Command: Sendable, Equatable {
        case currentState(scope: SemanticObservationScope)
        case wait(predicate: Predicate, timeout: Duration)
        case action(ActionCommand)

        internal init(
            observing authored: AccessibilityPredicate,
            resolved: Observation.Event.Predicate,
            timeout: WaitTimeout
        ) {
            self = .wait(
                predicate: Predicate(authored: authored, resolved: resolved),
                timeout: Self.duration(timeout)
            )
        }

        internal var predicate: Predicate? {
            switch self {
            case .currentState:
                nil
            case .wait(let predicate, _):
                predicate
            case .action(let action):
                action.expectation?.predicate
            }
        }

        internal var observationScope: SemanticObservationScope {
            switch self {
            case .currentState(let scope):
                scope
            case .wait(let predicate, _):
                predicate.observationScope
            case .action(let action):
                action.expectation?.predicate.observationScope ?? .visible
            }
        }

        internal var timeout: Duration? {
            switch self {
            case .currentState:
                nil
            case .wait(_, let timeout):
                timeout
            case .action(let action):
                action.timeout
            }
        }

        internal static func duration(_ timeout: WaitTimeout) -> Duration {
            .milliseconds(Int64((timeout.seconds * 1_000).rounded(.up)))
        }
    }

    internal struct ActionExpectation: Sendable, Equatable {
        internal let predicate: Predicate
        internal let timeout: Duration

        internal init(
            authored: AccessibilityPredicate,
            resolved: Observation.Event.Predicate,
            timeout: WaitTimeout
        ) {
            predicate = Predicate(authored: authored, resolved: resolved)
            self.timeout = Command.duration(timeout)
        }
    }

    internal struct ActionCommand: Sendable, Equatable {
        internal let command: ResolvedHeistActionCommand
        internal let expectation: ActionExpectation?
        internal let timeout: Duration

        internal init(
            command: ResolvedHeistActionCommand,
            expectation: ActionExpectation?,
            readinessAllowance: Duration
        ) {
            precondition(readinessAllowance >= .zero)
            self.command = command
            self.expectation = expectation
            timeout = readinessAllowance + (expectation?.timeout ?? .zero)
        }
    }
}

extension HeistExecution {
    internal enum Outcome: Sendable, Equatable {
        case completed
        case timedOut
        case cancelled
        case unavailable
        case viewportExitFailed(Navigation.ViewportExit.Failure)
    }

    internal struct ObservationResult: Sendable, Equatable {
        internal let predicate: Predicate?
        internal let evidence: Observation.Evidence
        internal let outcome: Outcome
        internal let outstandingDescription: String?
        internal let elapsed: ElapsedMilliseconds
    }

    internal struct ActionResult: Sendable {
        internal let action: ActionCommand
        internal let dispatch: TheSafecracker.ActionDispatchResult?
        internal let observation: ObservationResult
    }

    internal enum Result: Sendable {
        case currentState(Observation.Snapshot?)
        case wait(ObservationResult)
        case action(ActionResult)

        internal var currentObservation: Observation.Snapshot? {
            switch self {
            case .currentState(let snapshot):
                snapshot
            case .wait(let result):
                result.evidence.current
            case .action(let result):
                result.observation.evidence.current
            }
        }
    }
}

extension HeistExecution {
    internal struct Admission {
        internal let id: OperationID
        internal let command: Command
        internal let baseline: Observation.Snapshot?
        internal let historyStartIndex: Int
        internal let startedAt: RuntimeElapsed.Instant
    }

    internal struct Completion {
        internal let id: OperationID
        internal let command: Command
        internal let baseline: Observation.Snapshot?
        internal let historyStartIndex: Int
        internal let startedAt: RuntimeElapsed.Instant
        internal let outcome: Outcome
        internal let outstandingDescription: String?
        internal let dispatch: TheSafecracker.ActionDispatchResult?
    }

    internal struct OperationID: RawRepresentable, Sendable, Equatable {
        internal let rawValue: UInt64
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
