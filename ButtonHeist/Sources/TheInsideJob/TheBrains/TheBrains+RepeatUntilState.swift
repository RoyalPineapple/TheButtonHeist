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

    internal enum IterationOutcome {
        case predicateMet(ExpectationResult.Met)
        case continued(ExpectationResult.Unmet)
        case failed(expectation: ExpectationResult.Unmet, childPath: HeistExecutionPath)
    }

    internal struct RunningState {
        internal let currentObservation: Observation?
        internal let iterationNodes: [HeistExecutionStepResult]

        internal init(
            currentObservation: Observation?,
            iterationNodes: [HeistExecutionStepResult] = []
        ) {
            self.currentObservation = currentObservation
            self.iterationNodes = iterationNodes
        }

        internal func appendingIteration(
            _ node: HeistExecutionStepResult,
            nextCheck: UnmetCheck
        ) -> RunningState {
            RunningState(
                currentObservation: nextCheck.observation,
                iterationNodes: iterationNodes + [node]
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
                    iterationCount: running.iterationNodes.count,
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
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            case .unmet(let check):
                return .running(running.appendingIteration(event.iterationNode, nextCheck: check))
            case .deadlineElapsed(let expectation):
                return .terminal(.timedOut(
                    observation: running.currentObservation,
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
               case .met(let check) = postBody {
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.predicateMetIterationNode]
                ))
            }
            return .terminal(.bodyFailed(
                observation: running.currentObservation,
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
        case bodyFailed(
            observation: Observation?,
            expectation: ExpectationResult.Unmet,
            iterationIndex: Int,
            childPath: HeistExecutionPath,
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
            childPath: HeistExecutionPath
        )

        internal var iterationNodes: [HeistExecutionStepResult] {
            switch self {
            case .predicateMet(_, _, let iterationNodes),
                 .timedOut(_, _, _, let iterationNodes),
                 .bodyFailed(_, _, _, _, let iterationNodes),
                 .timeoutHandledByElse(_, _, _, let iterationNodes, _),
                 .timeoutElseFailed(_, _, _, let iterationNodes, _, _):
                return iterationNodes
            }
        }

        internal var children: [HeistExecutionStepResult] {
            switch self {
            case .timeoutHandledByElse(_, _, _, let iterationNodes, let elseChildren),
                 .timeoutElseFailed(_, _, _, let iterationNodes, let elseChildren, _):
                return iterationNodes + elseChildren
            case .predicateMet,
                 .timedOut,
                 .bodyFailed:
                return iterationNodes
            }
        }
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
