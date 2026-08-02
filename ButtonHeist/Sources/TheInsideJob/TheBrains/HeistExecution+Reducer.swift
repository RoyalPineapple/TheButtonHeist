#if canImport(UIKit)
#if DEBUG
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

/// Pure execution reducer for one complete heist.
internal struct HeistExecution {
    internal enum Root {
        case plan(SequenceContinuation)
        case action(ActionStep)
    }

    private enum State {
        case ready(Root)
        case running(Running)
        case awaitingFailureScreenshot(effect: Effect, children: HeistExecutedChildren)
        case cancelling(Effect)
        case complete(Completion)
    }

    internal struct Running {
        let root: Root
        var continuations: [Continuation]
        var activeLeaf: ActiveLeaf?
        var awaiting: WaitRequest?
        var pendingEffect: Effect?
        var nextRequestID: UInt64
        let executionDeadline: SemanticObservationDeadline
        var observationDeadline: SemanticObservationDeadline?
        var now: RuntimeElapsed.Instant
    }

    internal let failureCaptureMode: ScreenCaptureMode?
    internal let actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy
    private var state: State
}

extension HeistExecution {
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

        internal mutating func start(
            at startedAt: RuntimeElapsed.Instant,
            timeout: HeistTimeout
        ) -> Decision {
            guard case .ready(let root) = state else { return unchangedDecision() }
            state = .running(Running(
                root: root,
                continuations: [],
                activeLeaf: nil,
                awaiting: nil,
                pendingEffect: nil,
                nextRequestID: 0,
                executionDeadline: .init(start: startedAt, timeout: .seconds(timeout.seconds)),
                observationDeadline: nil,
                now: startedAt
            ))
            switch root {
            case .plan(let sequence):
                running.continuations = [.sequence(sequence)]
                return advanceExecution()
            case .action(let action):
                return begin(action: action, path: .body.step(at: 0), environment: .empty)
            }
        }

        internal mutating func reduce(_ event: Event) -> Decision {
            if case .complete(let completion) = state {
                return .complete(completion)
            }
            if case .awaitingFailureScreenshot(let effect, let children) = state {
                guard case .failureScreenshotCaptured(let id, let failureCapture, _) = event,
                      effect.isFailureCapture(id) else {
                    return .perform(effect)
                }
                return complete(steps: children.values, failureCapture: failureCapture)
            }
            if case .cancelling(let effect) = state {
                guard case .cancellationCompleted(let id, _) = event,
                      effect.isCancellation(id) else {
                    return .perform(effect)
                }
                return complete(steps: [], outcome: .cancelled)
            }
            guard admits(event) else { return unchangedDecision() }
            record(event.time)
            switch event {
            case .deadlineElapsed:
                return reduceDeadline()
            case .cancellationRequested:
                return reduceCancellation()
            case .currentSnapshot, .observationBegan, .observation, .dispatchCompleted,
                 .viewportExited, .observationCloseSampled, .failureScreenshotCaptured,
                 .cancellationCompleted, .observationCloseCommitted:
                break
            }
            clearWait()
            clearEffect()
            switch state {
            case .running(let running):
                if running.activeLeaf != nil {
                    return advanceActiveLeaf(event)
                }
                return advanceControlFlow(event)
            case .awaitingFailureScreenshot, .cancelling, .ready, .complete:
                return unchangedDecision()
            }
        }

        private mutating func unchangedDecision() -> Decision {
            switch state {
            case .ready:
                preconditionFailure("A reducer must start before it can suspend")
            case .running(let running):
                if let effect = running.pendingEffect {
                    return .perform(effect)
                }
                return wait()
            case .awaitingFailureScreenshot(let effect, _):
                return .perform(effect)
            case .cancelling(let effect):
                return .perform(effect)
            case .complete(let completion):
                return .complete(completion)
            }
        }

        internal var running: Running {
            get {
                guard case .running(let running) = state else {
                    preconditionFailure("Execution frames exist only while the reducer is running")
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

        internal mutating func wait(
            for deadline: SemanticObservationDeadline? = nil
        ) -> Decision {
            guard case .running(var running) = state else {
                return unchangedDecision()
            }
            if let awaiting = running.awaiting {
                return .wait(awaiting)
            }
            let request = WaitRequest(
                id: .init(rawValue: nextID().rawValue),
                deadline: boundaryDeadline(for: deadline)
            )
            running.awaiting = request
            state = .running(running)
            return .wait(request)
        }

        private func admits(_ event: Event) -> Bool {
            guard case .running(let running) = state else {
                return false
            }
            switch event {
            case .observation(let id, _, _), .deadlineElapsed(let id, _):
                return running.awaiting?.id == id
            case .cancellationRequested:
                return true
            case .cancellationCompleted:
                return false
            case .observationCloseCommitted(let id, _):
                return running.pendingEffect?.isObservationCommit(id) == true
            case .currentSnapshot(let id, _, _):
                return running.pendingEffect?.isCurrentSnapshot(id) == true
            case .observationBegan(let id, _, _):
                return running.pendingEffect?.isObservationBegin(id) == true
            case .dispatchCompleted(let id, _, _):
                return running.pendingEffect?.isDispatch(id) == true
            case .viewportExited(let id, _, _):
                return running.pendingEffect?.isExploration(id) == true
            case .observationCloseSampled(let requestID, let source, let observationID, _, _, _):
                return running.pendingEffect?.isObservationFinish(
                    requestID,
                    observationID: observationID,
                    source: source
                ) == true && running.activeLeaf?.admits(
                    sampleRequestID: requestID,
                    observationID: observationID,
                    source: source
                ) == true
            case .failureScreenshotCaptured:
                return false
            }
        }

        private mutating func clearWait() {
            guard case .running(var running) = state else { return }
            running.awaiting = nil
            state = .running(running)
        }

        private mutating func clearEffect() {
            guard case .running(var running) = state else { return }
            running.pendingEffect = nil
            state = .running(running)
        }

        private mutating func reduceDeadline() -> Decision {
            guard case .running = state else { return unchangedDecision() }
            if let activeLeaf = running.activeLeaf {
                switch activeLeaf {
                case .action(let leaf) where leaf.phase.dispatch != nil:
                    return sampleDeadlineClose(action: leaf)
                case .wait(let leaf):
                    return sampleDeadlineClose(wait: leaf)
                case .action(let leaf):
                    return resume(afterCompletedLeaf: HeistExecution.ResultProjector.heistTimeout(action: leaf))
                }
            }
            if !running.executionDeadline.hasTimeRemaining(at: running.now) {
                return finishAfterHeistTimeout()
            }
            return wait()
        }

        private mutating func reduceCancellation() -> Decision {
            let requestID = nextID()
            let effect = Effect.cancelObservation(
                requestID,
                observationID: running.activeLeaf?.id
            )
            state = .cancelling(effect)
            return .perform(effect)
        }

        internal mutating func perform(_ effect: Effect) -> Decision {
            running.pendingEffect = effect
            return .perform(effect)
        }

        private mutating func record(_ time: RuntimeElapsed.Instant) {
            guard case .running(var running) = state else { return }
            running.now = time
            state = .running(running)
        }

        internal func observationDeadline(_ timeout: Duration) -> SemanticObservationDeadline {
            .init(start: running.now, timeout: timeout)
        }

        internal var activeDeadline: SemanticObservationDeadline {
            boundaryDeadline(for: running.observationDeadline)
        }

        /// The deadline exposed to one boundary operation. The reducer retains
        /// both the whole-heist and leaf budgets in `Running`; only the
        /// operation is capped at the earlier absolute expiration.
        internal func boundaryDeadline(
            for requested: SemanticObservationDeadline?
        ) -> SemanticObservationDeadline {
            let leafDeadline = requested ?? running.observationDeadline
            guard let leafDeadline else { return running.executionDeadline }
            return leafDeadline.earlier(than: running.executionDeadline)
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
            let effect = Effect.captureFailureScreenshot(
                id,
                failedPath: failedPath,
                mode: failureCaptureMode
            )
            state = .awaitingFailureScreenshot(effect: effect, children: children)
            return .perform(effect)
        }

        private mutating func complete(
            steps: [HeistExecutionStepResult],
            failureCapture: HeistFailureCapture? = nil,
            outcome: Completion.Outcome = .completed
        ) -> Decision {
            let completion = Completion(
                steps: steps,
                failureCapture: failureCapture,
                outcome: outcome
            )
            state = .complete(completion)
            return .complete(completion)
        }
}

private extension HeistExecution.Effect {
    func isCurrentSnapshot(_ id: HeistExecution.RequestID) -> Bool {
        guard case .currentSnapshot(let expectedID, _, _) = self else { return false }
        return id == expectedID
    }

    func isObservationBegin(_ id: HeistExecution.RequestID) -> Bool {
        guard case .beginObservation(let expectedID, _, _) = self else { return false }
        return id == expectedID
    }

    func isDispatch(_ id: HeistExecution.RequestID) -> Bool {
        guard case .dispatch(let expectedID, _, _) = self else { return false }
        return id == expectedID
    }

    func isExploration(_ id: HeistExecution.RequestID) -> Bool {
        guard case .explore(let expectedID, _, _) = self else { return false }
        return id == expectedID
    }

    func isObservationFinish(
        _ requestID: HeistExecution.RequestID,
        observationID: HeistExecution.RequestID,
        source: HeistExecution.ObservationCloseSource
    ) -> Bool {
        guard case .sampleObservationClose(
            let expectedRequestID,
            let expectedObservationID,
            _,
            _,
            let expectedSource
        ) = self else { return false }
        return requestID == expectedRequestID
            && observationID == expectedObservationID
            && source == expectedSource
    }

    func isObservationCommit(_ id: HeistExecution.RequestID) -> Bool {
        guard case .commitObservationClose(let expectedID, _) = self else { return false }
        return id == expectedID
    }

    func isFailureCapture(_ id: HeistExecution.RequestID) -> Bool {
        guard case .captureFailureScreenshot(let expectedID, _, _) = self else { return false }
        return id == expectedID
    }

    func isCancellation(_ id: HeistExecution.RequestID) -> Bool {
        guard case .cancelObservation(let expectedID, _) = self else { return false }
        return id == expectedID
    }
}

private extension HeistExecution.Event {
    var time: RuntimeElapsed.Instant {
        switch self {
        case .currentSnapshot(_, _, let time),
             .observationBegan(_, _, let time),
             .observation(_, _, let time),
             .dispatchCompleted(_, _, let time),
             .viewportExited(_, _, let time),
             .observationCloseSampled(_, _, _, _, _, let time),
             .failureScreenshotCaptured(_, _, let time),
             .deadlineElapsed(_, let time),
             .cancellationRequested(let time),
             .cancellationCompleted(_, let time),
             .observationCloseCommitted(_, let time):
            time
        }
    }
}

extension HeistExecution {
    internal mutating func advanceExecution() -> HeistExecution.Decision {
        guard !running.continuations.isEmpty else {
            preconditionFailure("A running execution completes when its root sequence resumes")
        }
        return advanceTopContinuation()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
