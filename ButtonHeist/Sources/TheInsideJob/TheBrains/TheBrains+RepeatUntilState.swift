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
        internal let start: CFAbsoluteTime
        internal let runtime: TheBrains.HeistExecutionRuntime
        internal let environment: HeistExecutionEnvironment
        internal let scope: TheBrains.HeistExecutionScope

        internal init(
            path: HeistExecutionPath,
            start: CFAbsoluteTime,
            runtime: TheBrains.HeistExecutionRuntime,
            environment: HeistExecutionEnvironment,
            scope: TheBrains.HeistExecutionScope
        ) {
            self.path = path
            self.start = start
            self.runtime = runtime
            self.environment = environment
            self.scope = scope
        }
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
            case (.terminal(let terminal), .elseCompleted(let children)):
                return reduceElseCompleted(state: state, terminal: terminal, children: children)
            case (.running, .elseCompleted),
                 (.terminal, .deadlineElapsed),
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

        private static func reduceElseCompleted(
            state: LoopState,
            terminal: Terminal,
            children: HeistExecutedChildren
        ) -> LoopState {
            guard case .timedOut(let observation, let expectation, let iterationCount, let iterationNodes) = terminal else {
                return state
            }
            switch children {
            case .aborted(let elseChildren):
                return .terminal(.timeoutElseFailed(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: iterationCount,
                    children: iterationNodes.appending(elseChildren)
                ))
            case .passed(let elseChildren):
                return .terminal(.timeoutHandledByElse(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: iterationCount,
                    children: iterationNodes.appending(elseChildren)
                ))
            }
        }
    }

    internal enum LoopEvent {
        case deadlineElapsed(ExpectationResult.Unmet)
        case iterationPassed(PassedIterationEvent)
        case iterationFailed(FailedIterationEvent)
        case elseCompleted(HeistExecutedChildren)
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
        case timeoutHandledByElse(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationCount: Int,
            children: HeistPassingChildren
        )
        case timeoutElseFailed(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationCount: Int,
            children: HeistAbortedChildren
        )

    }

    internal struct IterationFrame {
        internal let path: HeistExecutionPath
        internal let start: CFAbsoluteTime
        internal let index: Int
        internal let count: Int

        internal init(path: HeistExecutionPath, start: CFAbsoluteTime, index: Int, count: Int) {
            self.path = path
            self.start = start
            self.index = index
            self.count = count
        }
    }

    internal struct PassedIterationEvent {
        internal let frame: IterationFrame
        internal let postBody: PostBodyCheck
        internal let iteration: HeistPassingChildren

        internal init(
            frame: IterationFrame,
            postBody: PostBodyCheck,
            iteration: HeistPassingChildren
        ) {
            self.frame = frame
            self.postBody = postBody
            self.iteration = iteration
        }
    }

    internal struct FailedIterationEvent {
        internal let frame: IterationFrame
        internal let predicateEvaluation: FailedBodyPredicateEvaluation
        internal let failureExpectation: ExpectationResult.Unmet
        internal let failedIteration: HeistAbortedChildren

        internal init(
            frame: IterationFrame,
            predicateEvaluation: FailedBodyPredicateEvaluation,
            failureExpectation: ExpectationResult.Unmet,
            failedIteration: HeistAbortedChildren
        ) {
            self.frame = frame
            self.predicateEvaluation = predicateEvaluation
            self.failureExpectation = failureExpectation
            self.failedIteration = failedIteration
        }
    }

    internal enum FailedBodyPredicateEvaluation {
        case notChecked
        case checked(PostBodyCheck, predicateMetIteration: HeistPassingChildren)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
