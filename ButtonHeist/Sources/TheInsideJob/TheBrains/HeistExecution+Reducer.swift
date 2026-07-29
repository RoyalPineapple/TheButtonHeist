#if canImport(UIKit)
#if DEBUG
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    internal struct Machine {
        private enum Progress {
            case ready
            case running
            case awaitingFailureScreenshot(PendingFailureScreenshot)
            case complete(Completion)
        }

        internal let plan: HeistPlan
        internal let argument: HeistArgument
        internal let rootEnvironment: HeistExecutionEnvironment
        internal let failureCaptureMode: ScreenCaptureMode?
        internal var continuations: [Continuation]
        internal var activeLeaf: ActiveLeaf?
        internal var rootChildren = HeistExecutedChildren.empty
        internal var nextRequestID: UInt64 = 0
        private var progress = Progress.ready

        internal init(
            plan: HeistPlan,
            argument: HeistArgument = .none,
            failureCaptureMode: ScreenCaptureMode? = nil
        ) throws {
            self.plan = plan
            self.argument = argument
            self.failureCaptureMode = failureCaptureMode
            rootEnvironment = try HeistExecutionEnvironment.empty.binding(
                argument: argument,
                to: plan.parameter
            )
            continuations = [
                .sequence(SequenceContinuation(
                    steps: plan.body,
                    context: StepContext(
                        path: .body,
                        environment: rootEnvironment,
                        scope: Scope(plan: plan)
                    ),
                    nextIndex: 0,
                    children: .empty
                )),
            ]
        }

        internal mutating func start() -> State {
            guard case .ready = progress else { return state }
            progress = .running
            return advanceExecution()
        }

        internal mutating func advance(_ input: Input) -> State {
            switch progress {
            case .running:
                if activeLeaf != nil {
                    return advanceActiveLeaf(input)
                }
                return advanceControlFlow(input)
            case .awaitingFailureScreenshot(let pending):
                guard case .failureScreenshotCaptured(let id, let screenshot) = input,
                      id == pending.id else {
                    return state
                }
                var steps = pending.children.values
                if let screenshot {
                    steps.append(screenshot)
                }
                return complete(
                    steps: steps,
                    abortedAtPath: pending.children.abortedAtPath
                )
            case .ready, .complete:
                return state
            }
        }

        internal var state: State {
            switch progress {
            case .ready, .running, .awaitingFailureScreenshot:
                .pending(.wait)
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
        ) -> State {
            rootChildren = children
            guard let failedPath = children.abortedAtPath,
                  let failureCaptureMode else {
                return complete(
                    steps: children.values,
                    abortedAtPath: children.abortedAtPath
                )
            }
            let id = nextID()
            progress = .awaitingFailureScreenshot(.init(
                id: id,
                children: children
            ))
            return .pending(.perform([
                .captureFailureScreenshot(
                    id,
                    failedPath: failedPath,
                    mode: failureCaptureMode
                ),
            ]))
        }

        private mutating func complete(
            steps: [HeistExecutionStepResult],
            abortedAtPath: HeistExecutionPath?
        ) -> State {
            let completion = Completion(
                steps: steps,
                abortedAtPath: abortedAtPath
            )
            progress = .complete(completion)
            return .complete(completion)
        }

        internal mutating func finishWithoutFailureScreenshot() -> State {
            guard case .awaitingFailureScreenshot(let pending) = progress else {
                return state
            }
            return complete(
                steps: pending.children.values,
                abortedAtPath: pending.children.abortedAtPath
            )
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
    internal mutating func advanceExecution() -> HeistExecution.State {
        guard !continuations.isEmpty else {
            return finish(children: rootChildren)
        }
        return advanceTopContinuation()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
