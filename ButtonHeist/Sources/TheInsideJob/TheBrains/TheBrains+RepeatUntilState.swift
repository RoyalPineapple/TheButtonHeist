#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    internal enum RepeatUntil {}
}

extension TheBrains.RepeatUntil {
    internal struct Context {
        internal let path: HeistExecutionPath
        internal let start: RuntimeElapsed.Instant
        internal let runtime: TheBrains.HeistExecutionRuntime
        internal let environment: HeistExecutionEnvironment
        internal let scope: TheBrains.HeistExecutionScope
    }

    internal struct RunningState {
        internal let currentObservation: Observation?
        internal let iterationNodes: HeistPassingChildren

        internal init(
            currentObservation: Observation?,
            iterationNodes: HeistPassingChildren = .empty
        ) {
            self.currentObservation = currentObservation
            self.iterationNodes = iterationNodes
        }

        internal func appendingIteration(
            _ iteration: HeistPassingChildren,
            nextCheck: UnmetCheck
        ) -> RunningState {
            RunningState(
                currentObservation: nextCheck.observation,
                iterationNodes: iterationNodes.appending(iteration)
            )
        }
    }

    internal enum LoopState {
        case running(RunningState)
        case terminal(Terminal)

        internal static func reduce(_ state: LoopState, event: LoopEvent) -> LoopState {
            switch (state, event) {
            case (.running(let running), .deadlineElapsed(let expectation)):
                return .terminal(.timedOut(
                    observation: running.currentObservation,
                    expectation: expectation,
                    iterationCount: running.iterationNodes.values.count,
                    iterationNodes: running.iterationNodes
                ))
            case (.running(let running), .iterationPassed(let event)):
                return reduceIterationPassed(running: running, event: event)
            case (.running(let running), .iterationFailed(let event)):
                return reduceIterationFailed(running: running, event: event)
            case (.terminal, .deadlineElapsed),
                 (.terminal, .iterationPassed),
                 (.terminal, .iterationFailed):
                return state
            }
        }

        private static func reduceIterationPassed(
            running: RunningState,
            event: PassedIterationEvent
        ) -> LoopState {
            switch event.postBody {
            case .met(let check):
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes.appending(event.iteration)
                ))
            case .unmet(let check):
                return .running(running.appendingIteration(event.iteration, nextCheck: check))
            case .deadlineElapsed(let expectation):
                return .terminal(.timedOut(
                    observation: running.currentObservation,
                    expectation: expectation,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes.appending(event.iteration)
                ))
            case .noProgress(let observation, let expectation, _):
                return .terminal(.timedOut(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes.appending(event.iteration)
                ))
            }
        }

        private static func reduceIterationFailed(
            running: RunningState,
            event: FailedIterationEvent
        ) -> LoopState {
            if case .checked(.met(let check), let predicateMetIteration) = event.predicateEvaluation {
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes.appending(predicateMetIteration)
                ))
            }
            return .terminal(.bodyFailed(
                observation: running.currentObservation,
                expectation: event.failureExpectation,
                iterationIndex: event.frame.index,
                children: running.iterationNodes.appending(event.failedIteration)
            ))
        }

    }

    internal enum LoopEvent {
        case deadlineElapsed(ExpectationResult.Unmet)
        case iterationPassed(PassedIterationEvent)
        case iterationFailed(FailedIterationEvent)
    }

    internal enum Terminal {
        case predicateMet(check: MetCheck, iterationCount: Int, iterationNodes: HeistPassingChildren)
        case timedOut(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationCount: Int,
            iterationNodes: HeistPassingChildren
        )
        case bodyFailed(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationIndex: Int,
            children: HeistAbortedChildren
        )
    }

    internal struct IterationFrame {
        internal let path: HeistExecutionPath
        internal let start: RuntimeElapsed.Instant
        internal let index: Int
        internal let count: Int
    }

    internal struct PassedIterationEvent {
        internal let frame: IterationFrame
        internal let postBody: PostBodyCheck
        internal let iteration: HeistPassingChildren
    }

    internal struct FailedIterationEvent {
        internal let frame: IterationFrame
        internal let predicateEvaluation: FailedBodyPredicateEvaluation
        internal let failureExpectation: ExpectationResult.Unmet
        internal let failedIteration: HeistAbortedChildren
    }

    internal enum FailedBodyPredicateEvaluation {
        case notChecked
        case checked(PostBodyCheck, predicateMetIteration: HeistPassingChildren)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
