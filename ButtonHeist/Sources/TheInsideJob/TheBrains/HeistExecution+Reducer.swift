#if canImport(UIKit)
#if DEBUG
import TheScore

extension HeistExecution {
    private enum DispatchProgress {
        case notRequired
        case pending
        case completed(TheSafecracker.ActionDispatchResult)

        var result: TheSafecracker.ActionDispatchResult? {
            guard case .completed(let result) = self else { return nil }
            return result
        }

        var permitsCompletion: Bool {
            switch self {
            case .notRequired, .completed:
                true
            case .pending:
                false
            }
        }
    }

    private enum MachineProgress {
        case active
        case finalizing(Outcome)
        case complete(Completion)
    }

    internal struct Machine {
        private let admission: Admission
        private let deadline: SemanticObservationDeadline
        private var expectation: Expectation
        private var verdict: Expectation.Result
        private var dispatch: DispatchProgress
        private var explorationStarted = false
        private var progress = MachineProgress.active

        internal init(_ admission: Admission) {
            guard let timeout = admission.command.timeout else {
                preconditionFailure("A machine requires a bounded command")
            }
            self.admission = admission
            deadline = SemanticObservationDeadline(
                start: admission.startedAt,
                timeout: timeout
            )
            let predicates = admission.command.predicate.map {
                [$0.resolved, .noChange]
            } ?? [.noChange]
            let expectation = Expectation(
                predicates,
                baseline: admission.baseline
            )
            self.expectation = expectation
            verdict = expectation.result
            switch admission.command {
            case .action:
                dispatch = .pending
            case .wait:
                dispatch = .notRequired
            case .currentState:
                preconditionFailure("Current state does not require a machine")
            }
        }

        internal mutating func start() -> State {
            guard case .active = progress else {
                return state
            }
            switch admission.command {
            case .action(let action):
                return .pending(.perform([
                    .dispatch(admission.id, action.command)
                ]))
            case .wait(let predicate, _):
                explorationStarted = !predicate.isNotification
                guard explorationStarted else {
                    return .pending(.wait)
                }
                return .pending(.perform([
                    .explore(admission.id, predicate, deadline)
                ]))
            case .currentState:
                preconditionFailure("Current state does not require a machine")
            }
        }

        internal mutating func advance(_ input: Input) -> State {
            switch progress {
            case .complete:
                return state
            case .finalizing:
                return finish(input)
            case .active:
                return advanceActive(input)
            }
        }

        internal var state: State {
            switch progress {
            case .active:
                return .pending(.wait)
            case .finalizing:
                return .pending(.wait)
            case .complete(let completion):
                return .complete(completion)
            }
        }

        internal func externalCompletion(_ outcome: Outcome) -> Completion {
            completion(outcome)
        }

        internal var requiresFinalDiscovery: Bool {
            guard case .active = progress,
                  admission.command.observationScope == .discovery,
                  admission.command.predicate?.isNotification == false else {
                return false
            }
            return true
        }

        internal var operationID: OperationID {
            admission.id
        }
    }
}

private extension HeistExecution.Machine {
    mutating func advanceActive(_ input: HeistExecution.Input) -> HeistExecution.State {
        switch input {
        case .event(let event):
            if case .pending = dispatch,
               case .noChange = event {
                return .pending(.wait)
            }
            verdict = expectation.evaluate(event)
            return completeIfPossible()

        case .dispatchCompleted(let id, let result):
            guard id == admission.id,
                  case .pending = dispatch else {
                return .pending(.wait)
            }
            dispatch = .completed(result)
            guard result.success else {
                return finalize(as: .completed)
            }
            guard verdict != .satisfied else {
                return finalize(as: .completed)
            }
            guard !explorationStarted,
                  let predicate = admission.command.predicate,
                  !predicate.isNotification else {
                return .pending(.wait)
            }
            explorationStarted = true
            return .pending(.perform([
                .explore(admission.id, predicate, deadline)
            ]))

        case .viewportExited:
            preconditionFailure("A viewport cannot finish before finalization")
        }
    }

    mutating func completeIfPossible() -> HeistExecution.State {
        guard dispatch.permitsCompletion,
              verdict == .satisfied else {
            return .pending(.wait)
        }
        return finalize(as: .completed)
    }

    mutating func finalize(
        as outcome: HeistExecution.Outcome
    ) -> HeistExecution.State {
        progress = .finalizing(outcome)
        return .pending(.perform([
            .finishExploration(admission.id)
        ]))
    }

    mutating func finish(_ input: HeistExecution.Input) -> HeistExecution.State {
        guard case .finalizing(let intendedOutcome) = progress else {
            preconditionFailure("Only finalizing work can finish")
        }
        guard case .viewportExited(let id, let viewport) = input,
              id == admission.id else {
            return .pending(.wait)
        }
        let outcome: HeistExecution.Outcome
        switch viewport {
        case .failed(let failure):
            outcome = .viewportExitFailed(failure)
        case .restored, .retained, .superseded:
            outcome = intendedOutcome
        }
        let completion = completion(outcome)
        progress = .complete(completion)
        return .complete(completion)
    }

    func completion(
        _ outcome: HeistExecution.Outcome
    ) -> HeistExecution.Completion {
        HeistExecution.Completion(
            id: admission.id,
            command: admission.command,
            baseline: admission.baseline,
            historyStartIndex: admission.historyStartIndex,
            startedAt: admission.startedAt,
            outcome: outcome,
            outstandingDescription: verdict.outstandingDescription,
            dispatch: dispatch.result
        )
    }
}

private extension HeistExecution.Predicate {
    var isNotification: Bool {
        if case .notification = resolved { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
