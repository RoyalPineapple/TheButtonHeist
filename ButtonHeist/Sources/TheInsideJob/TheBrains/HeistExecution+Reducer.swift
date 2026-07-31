#if canImport(UIKit)
#if DEBUG
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    internal struct Machine {
        internal enum Root {
            case plan(SequenceContinuation)
            case action(ActionStep)
        }

        private enum State {
            case ready(Root)
            case running(Running)
            case awaitingFailureScreenshot(
                id: RequestID,
                children: HeistExecutedChildren
            )
            case complete(Completion)
        }

        internal struct Running {
            let root: Root
            var continuations: [Continuation]
            var activeLeaf: ActiveLeaf?
            var nextRequestID: UInt64
        }

        internal let failureCaptureMode: ScreenCaptureMode?
        internal let actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy
        private var state: State

        internal init(
            plan: HeistPlan,
            argument: HeistArgument = .none,
            failureCaptureMode: ScreenCaptureMode? = nil,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) throws {
            self.failureCaptureMode = failureCaptureMode
            self.actionExpectationTimeoutPolicy = actionExpectationTimeoutPolicy
            let environment = try HeistExecutionEnvironment.empty.binding(
                argument: argument,
                to: plan.parameter
            )
            state = .ready(.plan(.init(
                steps: plan.body,
                context: .init(
                    path: .body,
                    environment: environment,
                    scope: .init(plan: plan)
                ),
                nextIndex: 0,
                children: .empty
            )))
        }

        internal init(
            action: HeistActionCommand,
            failureCaptureMode: ScreenCaptureMode? = nil,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) {
            self.failureCaptureMode = failureCaptureMode
            self.actionExpectationTimeoutPolicy = actionExpectationTimeoutPolicy
            state = .ready(.action(.init(command: action)))
        }

        internal mutating func start() -> Decision {
            guard case .ready(let root) = state else { return decision }
            state = .running(Running(
                root: root,
                continuations: [],
                activeLeaf: nil,
                nextRequestID: 0
            ))
            switch root {
            case .plan(let sequence):
                running.continuations = [.sequence(sequence)]
                return advanceExecution()
            case .action(let action):
                return begin(action: action, path: .body.step(at: 0), environment: .empty)
            }
        }

        internal mutating func advance(_ input: Input) -> Decision {
            switch state {
            case .running(let running):
                if running.activeLeaf != nil {
                    return advanceActiveLeaf(input)
                }
                return advanceControlFlow(input)
            case .awaitingFailureScreenshot(let expectedID, let children):
                guard case .failureScreenshotCaptured(let id, let failureCapture) = input,
                      id == expectedID else {
                    return decision
                }
                return complete(
                    steps: children.values,
                    failureCapture: failureCapture
                )
            case .ready, .complete:
                return decision
            }
        }

        internal var decision: Decision {
            switch state {
            case .ready, .running, .awaitingFailureScreenshot:
                .wait
            case .complete(let completion):
                .complete(completion)
            }
        }

        internal var running: Running {
            get {
                guard case .running(let running) = state else {
                    preconditionFailure("Execution frames exist only while the machine is running")
                }
                return running
            }
            set {
                state = .running(newValue)
            }
        }

        internal mutating func nextID() -> RequestID {
            running.nextRequestID += 1
            return RequestID(rawValue: running.nextRequestID)
        }

        internal mutating func finish(
            children: HeistExecutedChildren
        ) -> Decision {
            guard let failedPath = children.abortedAtPath,
                  let failureCaptureMode else {
                return complete(
                    steps: children.values
                )
            }
            let id = nextID()
            state = .awaitingFailureScreenshot(id: id, children: children)
            return .perform(.captureFailureScreenshot(
                id,
                failedPath: failedPath,
                mode: failureCaptureMode
            ))
        }

        private mutating func complete(
            steps: [HeistExecutionStepResult],
            failureCapture: HeistFailureCapture? = nil
        ) -> Decision {
            let completion = Completion(
                steps: steps,
                failureCapture: failureCapture
            )
            state = .complete(completion)
            return .complete(completion)
        }
    }
}

extension HeistExecution.Machine {
    internal mutating func advanceExecution() -> HeistExecution.Decision {
        guard !running.continuations.isEmpty else {
            preconditionFailure("A running execution completes when its root sequence resumes")
        }
        return advanceTopContinuation()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
