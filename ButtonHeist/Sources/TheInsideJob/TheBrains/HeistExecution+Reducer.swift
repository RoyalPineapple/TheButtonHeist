#if canImport(UIKit)
#if DEBUG
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    internal struct Machine {
        internal enum Root {
            case plan
            case action(ActionStep)
        }

        private enum State {
            case ready
            case running
            case awaitingFailureScreenshot(
                id: RequestID,
                children: HeistExecutedChildren
            )
            case complete(Completion)
        }

        internal let root: Root
        internal let failureCaptureMode: ScreenCaptureMode?
        internal let actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy
        internal var continuations: [Continuation]
        internal var activeLeaf: ActiveLeaf?
        internal var rootChildren = HeistExecutedChildren.empty
        internal var nextRequestID: UInt64 = 0
        private var state = State.ready

        internal init(
            plan: HeistPlan,
            argument: HeistArgument = .none,
            failureCaptureMode: ScreenCaptureMode? = nil,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) throws {
            root = .plan
            self.failureCaptureMode = failureCaptureMode
            self.actionExpectationTimeoutPolicy = actionExpectationTimeoutPolicy
            let environment = try HeistExecutionEnvironment.empty.binding(
                argument: argument,
                to: plan.parameter
            )
            continuations = [
                .sequence(SequenceContinuation(
                    steps: plan.body,
                    context: StepContext(
                        path: .body,
                        environment: environment,
                        scope: Scope(plan: plan)
                    ),
                    nextIndex: 0,
                    children: .empty
                )),
            ]
        }

        internal init(
            action: HeistActionCommand,
            failureCaptureMode: ScreenCaptureMode? = nil,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) {
            root = .action(ActionStep(command: action))
            self.failureCaptureMode = failureCaptureMode
            self.actionExpectationTimeoutPolicy = actionExpectationTimeoutPolicy
            continuations = []
        }

        internal mutating func start() -> Decision {
            guard case .ready = state else { return decision }
            state = .running
            switch root {
            case .plan:
                return advanceExecution()
            case .action(let action):
                return begin(
                    action: action,
                    path: .body.step(at: 0),
                    environment: .empty
                )
            }
        }

        internal mutating func advance(_ input: Input) -> Decision {
            switch state {
            case .running:
                if activeLeaf != nil {
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
                    failureCapture: failureCapture,
                    abortedAtPath: children.abortedAtPath
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

        internal mutating func nextID() -> RequestID {
            nextRequestID += 1
            return RequestID(rawValue: nextRequestID)
        }

        internal mutating func finish(
            children: HeistExecutedChildren
        ) -> Decision {
            rootChildren = children
            guard let failedPath = children.abortedAtPath,
                  let failureCaptureMode else {
                return complete(
                    steps: children.values,
                    abortedAtPath: children.abortedAtPath
                )
            }
            let id = nextID()
            state = .awaitingFailureScreenshot(
                id: id,
                children: children
            )
            return .perform(.captureFailureScreenshot(
                id,
                failedPath: failedPath,
                mode: failureCaptureMode
            ))
        }

        private mutating func complete(
            steps: [HeistExecutionStepResult],
            failureCapture: HeistFailureCapture? = nil,
            abortedAtPath: HeistExecutionPath?
        ) -> Decision {
            let completion = Completion(
                steps: steps,
                failureCapture: failureCapture,
                abortedAtPath: abortedAtPath
            )
            state = .complete(completion)
            return .complete(completion)
        }
    }
}

extension HeistExecution.Machine {
    /// Runs pure control flow until the host must perform an effect or the
    /// complete heist result is available.
    ///
    /// Leaf and control-flow extensions implement the exhaustive frame
    /// transitions. This root owns the loop and therefore prevents another
    /// executor from becoming a competing source of heist progress.
    internal mutating func advanceExecution() -> HeistExecution.Decision {
        guard !continuations.isEmpty else {
            return finish(children: rootChildren)
        }
        return advanceTopContinuation()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
