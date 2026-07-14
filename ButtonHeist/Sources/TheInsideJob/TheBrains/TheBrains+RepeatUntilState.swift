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
        internal let path: String
        internal let start: CFAbsoluteTime
        internal let runtime: TheBrains.HeistExecutionRuntime
        internal let environment: HeistExecutionEnvironment
        internal let scope: TheBrains.HeistExecutionScope

        internal init(
            path: String,
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

    internal enum IterationOutcome {
        case predicateMet(ExpectationResult.Met)
        case continued(ExpectationResult.Unmet)
        case failed(expectation: ExpectationResult.Unmet, childPath: String)
    }

    internal struct RunningState {
        internal let currentCheck: UnmetCheck
        internal let iterationNodes: [HeistExecutionStepResult]

        internal init(
            currentCheck: UnmetCheck,
            iterationNodes: [HeistExecutionStepResult]
        ) {
            self.currentCheck = currentCheck
            self.iterationNodes = iterationNodes
        }

        internal func appendingIteration(
            _ node: HeistExecutionStepResult,
            nextCheck: UnmetCheck
        ) -> RunningState {
            RunningState(currentCheck: nextCheck, iterationNodes: iterationNodes + [node])
        }
    }

    internal enum LoopState {
        case awaitingInitial
        case running(RunningState)
        case terminal(Terminal)

        internal static func reduce(_ state: LoopState, event: LoopEvent) -> LoopState {
            switch (state, event) {
            case (.awaitingInitial, .initial(let check)):
                switch check {
                case .unavailable(let receipt):
                    return .terminal(.initialObservationUnavailable(receipt))
                case .met(let check):
                    return .terminal(.predicateMet(
                        check: check,
                        iterationCount: 0,
                        iterationNodes: []
                    ))
                case .unmet(let check):
                    return .running(RunningState(currentCheck: check, iterationNodes: []))
                }
            case (.running(let running), .deadlineElapsed(let expectation)):
                return .terminal(.timedOut(
                    observation: running.currentCheck.observation,
                    expectation: expectation,
                    iterationCount: running.iterationNodes.count,
                    iterationNodes: running.iterationNodes
                ))
            case (.running(let running), .iterationPassed(let event)):
                return reduceIterationPassed(running: running, event: event)
            case (.running(let running), .iterationFailed(let event)):
                return reduceIterationFailed(running: running, event: event)
            case (.terminal(let terminal), .elseCompleted(let children)):
                return reduceElseCompleted(state: state, terminal: terminal, children: children)
            case (.awaitingInitial, _),
                 (.running, .initial),
                 (.running, .elseCompleted),
                 (.terminal, .initial),
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
            case .changedMet(let check):
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            case .changedUnmet(let check):
                return .running(running.appendingIteration(event.iterationNode, nextCheck: check))
            case .deadlineElapsed(let expectation):
                return .terminal(.timedOut(
                    observation: running.currentCheck.observation,
                    expectation: expectation,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            case .noProgress(let observation, let expectation, _):
                return .terminal(.timedOut(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            }
        }

        private static func reduceIterationFailed(
            running: RunningState,
            event: FailedIterationEvent
        ) -> LoopState {
            if let postBody = event.postBody,
               case .changedMet(let check) = postBody {
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.predicateMetIterationNode]
                ))
            }
            return .terminal(.bodyFailed(
                observation: running.currentCheck.observation,
                expectation: event.failureExpectation,
                iterationIndex: event.frame.index,
                childPath: event.failedStep.path,
                iterationNodes: running.iterationNodes + [event.failedIterationNode]
            ))
        }

        private static func reduceElseCompleted(
            state: LoopState,
            terminal: Terminal,
            children: [HeistExecutionStepResult]
        ) -> LoopState {
            guard case .timedOut(let observation, let expectation, let iterationCount, let iterationNodes) = terminal else {
                return state
            }
            if let abortedAtChildPath = children.firstFailedStep?.path {
                return .terminal(.timeoutElseFailed(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: iterationCount,
                    iterationNodes: iterationNodes,
                    elseChildren: children,
                    childPath: abortedAtChildPath
                ))
            }
            return .terminal(.timeoutHandledByElse(
                observation: observation,
                expectation: expectation,
                iterationCount: iterationCount,
                iterationNodes: iterationNodes,
                elseChildren: children
            ))
        }
    }

    internal enum LoopEvent {
        case initial(InitialCheck)
        case deadlineElapsed(ExpectationResult.Unmet)
        case iterationPassed(PassedIterationEvent)
        case iterationFailed(FailedIterationEvent)
        case elseCompleted([HeistExecutionStepResult])
    }

    internal enum Terminal {
        case predicateMet(check: MetCheck, iterationCount: Int, iterationNodes: [HeistExecutionStepResult])
        case timedOut(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult]
        )
        case initialObservationUnavailable(HeistWaitReceipt)
        case bodyFailed(
            observation: Observation,
            expectation: ExpectationResult.Unmet,
            iterationIndex: Int,
            childPath: String,
            iterationNodes: [HeistExecutionStepResult]
        )
        case timeoutHandledByElse(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult],
            elseChildren: [HeistExecutionStepResult]
        )
        case timeoutElseFailed(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult],
            elseChildren: [HeistExecutionStepResult],
            childPath: String
        )

        internal var iterationNodes: [HeistExecutionStepResult] {
            switch self {
            case .predicateMet(_, _, let iterationNodes),
                 .timedOut(_, _, _, let iterationNodes),
                 .bodyFailed(_, _, _, _, let iterationNodes),
                 .timeoutHandledByElse(_, _, _, let iterationNodes, _),
                 .timeoutElseFailed(_, _, _, let iterationNodes, _, _):
                return iterationNodes
            case .initialObservationUnavailable:
                return []
            }
        }

        internal var children: [HeistExecutionStepResult] {
            switch self {
            case .timeoutHandledByElse(_, _, _, let iterationNodes, let elseChildren),
                 .timeoutElseFailed(_, _, _, let iterationNodes, let elseChildren, _):
                return iterationNodes + elseChildren
            case .predicateMet,
                 .timedOut,
                 .initialObservationUnavailable,
                 .bodyFailed:
                return iterationNodes
            }
        }
    }

    internal struct IterationFrame {
        internal let path: String
        internal let start: CFAbsoluteTime
        internal let index: Int
        internal let count: Int

        internal init(path: String, start: CFAbsoluteTime, index: Int, count: Int) {
            self.path = path
            self.start = start
            self.index = index
            self.count = count
        }
    }

    internal struct PassedIterationEvent {
        internal let frame: IterationFrame
        internal let postBody: PostBodyCheck
        internal let iterationNode: HeistExecutionStepResult

        internal init(
            frame: IterationFrame,
            postBody: PostBodyCheck,
            iterationNode: HeistExecutionStepResult
        ) {
            self.frame = frame
            self.postBody = postBody
            self.iterationNode = iterationNode
        }
    }

    internal struct FailedIterationEvent {
        internal let frame: IterationFrame
        internal let failedStep: HeistExecutionStepResult
        internal let postBody: PostBodyCheck?
        internal let failureExpectation: ExpectationResult.Unmet
        internal let predicateMetIterationNode: HeistExecutionStepResult
        internal let failedIterationNode: HeistExecutionStepResult

        internal init(
            frame: IterationFrame,
            failedStep: HeistExecutionStepResult,
            postBody: PostBodyCheck?,
            failureExpectation: ExpectationResult.Unmet,
            predicateMetIterationNode: HeistExecutionStepResult,
            failedIterationNode: HeistExecutionStepResult
        ) {
            self.frame = frame
            self.failedStep = failedStep
            self.postBody = postBody
            self.failureExpectation = failureExpectation
            self.predicateMetIterationNode = predicateMetIterationNode
            self.failedIterationNode = failedIterationNode
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
