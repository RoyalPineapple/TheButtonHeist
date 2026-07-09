#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
import ThePlans
import TheScore

extension TheBrains {

    internal enum HeistExecutionPhase: Equatable, Sendable {
        case ready
        case aborted(failedPath: String)
        case completed(abortedPath: String?)

        internal var abortedPath: String? {
            switch self {
            case .completed(let abortedPath):
                return abortedPath
            case .ready, .aborted:
                return nil
            }
        }
    }

    internal struct HeistExecutionTransitionRejection: Equatable, Sendable {
        internal let path: String
        internal let reason: String

        private init(path: String, reason: String) {
            self.path = path
            self.reason = reason
        }

        internal static func stepAfterCompletion(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot begin heist step after execution completed"
            )
        }

        internal static func skipBeforeAbort(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot skip heist step before execution aborts"
            )
        }

        internal static func executeAfterAbort(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot execute heist step after execution aborts"
            )
        }

        internal static func appendAfterCompletion(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot append heist step after execution completed"
            )
        }

        internal static func completeTwice(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot complete heist plan twice"
            )
        }
    }

    internal enum HeistStepTransitionResult: Equatable, Sendable {
        case accepted
        case rejected(HeistExecutionTransitionRejection)
    }

    internal enum HeistStepTransition: Equatable, Sendable {
        case executed(HeistExecutionStepResult)
        case skipped(HeistExecutionStepResult, abortedPath: String)

        internal var path: String {
            switch self {
            case .executed(let result),
                 .skipped(let result, _):
                return result.path
            }
        }
    }

    internal enum HeistStepLifecycleEvent: Equatable, Sendable {
        case transition(HeistStepTransition)
        case complete
        case reject(HeistExecutionTransitionRejection, result: HeistExecutionStepResult)
    }

    internal enum HeistStepLifecycleEffect: Equatable, Sendable {
        case appendStep(HeistExecutionStepResult)
    }

    internal typealias HeistStepLifecycleChange = StateChange<
        HeistExecutionPhase,
        HeistStepLifecycleEffect,
        HeistExecutionTransitionRejection
    >

    internal struct HeistStepLifecycleMachine: SimpleStateMachine {
        internal func advance(_ state: HeistExecutionPhase, with event: HeistStepLifecycleEvent) -> HeistStepLifecycleChange {
            switch (state, event) {
            case (.ready, .transition(.executed(let result))):
                return .changed(
                    to: result.isFailure
                        ? .aborted(failedPath: result.firstFailedStep?.path ?? result.path)
                        : .ready,
                    effects: [.appendStep(result)]
                )
            case (.aborted, .transition(.skipped(let result, let abortedPath))):
                return .changed(
                    to: .aborted(failedPath: abortedPath),
                    effects: [.appendStep(result)]
                )
            case (.ready, .transition(let transition)):
                return .rejected(.skipBeforeAbort(path: transition.path), stayingIn: state)
            case (.aborted, .transition(let transition)):
                return .rejected(.executeAfterAbort(path: transition.path), stayingIn: state)
            case (.completed, .transition(let transition)):
                return .rejected(.appendAfterCompletion(path: transition.path), stayingIn: state)
            case (.ready, .complete):
                return .changed(to: .completed(abortedPath: nil))
            case (.aborted(let failedPath), .complete):
                return .changed(to: .completed(abortedPath: failedPath))
            case (.completed, .complete):
                return .rejected(.completeTwice(path: "$.body"), stayingIn: state)
            case (_, .reject(let rejection, let result)):
                return .changed(
                    to: .completed(abortedPath: rejection.path),
                    effects: [.appendStep(result)]
                )
            }
        }
    }

    internal struct HeistExecutionAccumulator {
        internal private(set) var steps: [HeistExecutionStepResult] = []
        private var lifecycle = StateDriver(
            initial: HeistExecutionPhase.ready,
            machine: HeistStepLifecycleMachine()
        )

        internal init() {}

        private var phase: HeistExecutionPhase {
            lifecycle.state
        }

        internal var abortedPath: String? {
            phase.abortedPath
        }

        internal func decision(for path: String) -> HeistExecutionStepDecision {
            switch phase {
            case .ready:
                return .execute
            case .aborted(let failedPath):
                return .skip(abortedPath: failedPath)
            case .completed:
                return .reject(.stepAfterCompletion(path: path))
            }
        }

        internal mutating func apply(_ transition: HeistStepTransition) -> HeistStepTransitionResult {
            let change = lifecycle.send(.transition(transition))
            return record(change)
        }

        internal mutating func complete() -> HeistStepTransitionResult {
            let change = lifecycle.send(.complete)
            return record(change)
        }

        internal mutating func reject(
            _ rejection: HeistExecutionTransitionRejection,
            result: HeistExecutionStepResult
        ) {
            let change = lifecycle.send(.reject(rejection, result: result))
            record(change)
        }

        @discardableResult
        private mutating func record(_ change: HeistStepLifecycleChange) -> HeistStepTransitionResult {
            for effect in change.effects {
                switch effect {
                case .appendStep(let result):
                    steps.append(result)
                }
            }

            switch change {
            case .changed:
                return .accepted
            case .rejected(let rejection, _):
                return .rejected(rejection)
            }
        }
    }

    internal enum HeistExecutionStepDecision: Equatable, Sendable {
        case execute
        case skip(abortedPath: String)
        case reject(HeistExecutionTransitionRejection)
    }

    internal func rejectedAccumulator(
        rejecting rejection: HeistExecutionTransitionRejection,
        accumulated accumulator: HeistExecutionAccumulator
    ) -> HeistExecutionAccumulator {
        var rejected = accumulator
        rejected.reject(
            rejection,
            result: heistTransitionRejectionResult(rejection)
        )
        return rejected
    }

    private func heistTransitionRejectionResult(
        _ rejection: HeistExecutionTransitionRejection
    ) -> HeistExecutionStepResult {
        heistExplicitFailureReceipt(
            path: rejection.path,
            durationMs: 0,
            intent: .fail(message: rejection.reason),
            failure: HeistFailureDetail(
                category: .validation,
                contract: "heist execution state transitions are valid",
                observed: rejection.reason
            )
        )
    }

    internal func skippedHeistStep(
        _ step: HeistStep,
        path: String,
        scope: HeistExecutionScope
    ) -> HeistExecutionStepResult {
        let kind: HeistExecutionStepKind
        let children: [HeistExecutionStepResult]

        switch step {
        case .action:
            kind = .action
            children = []
        case .wait:
            kind = .wait
            children = []
        case .conditional:
            kind = .conditional
            children = []
        case .forEachElement:
            kind = .forEachElement
            children = []
        case .forEachString:
            kind = .forEachString
            children = []
        case .repeatUntil:
            kind = .repeatUntil
            children = []
        case .warn:
            kind = .warn
            children = []
        case .fail:
            kind = .fail
            children = []
        case .heist(let plan):
            kind = .heist
            children = skippedHeistSteps(plan.body, path: "\(path).heist.body", scope: scope)
        case .invoke:
            kind = .invoke
            children = []
        }

        return heistSkippedReceipt(
            path: path,
            kind: kind,
            children: children
        )
    }

    private func skippedHeistSteps(
        _ steps: [HeistStep],
        path: String,
        scope: HeistExecutionScope
    ) -> [HeistExecutionStepResult] {
        steps.enumerated().map { index, step in
            skippedHeistStep(step, path: "\(path)[\(index)]", scope: scope)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
