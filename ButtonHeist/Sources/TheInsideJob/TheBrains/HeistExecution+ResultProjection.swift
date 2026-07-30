#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension HeistExecution {
    internal enum ResultProjector {
        internal static func actionResolutionFailure(
            step: ActionStep,
            path: HeistExecutionPath,
            error: Error
        ) -> HeistExecutionStepResult {
            let evidence = HeistActionEvidence.commandResolutionFailure
            return .action(
                path: path,
                execution: .failed(
                    command: step.command,
                    evidence: .init(admitted: evidence),
                    failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "action command resolves before dispatch",
                        observed: "could not resolve heist action command: \(error)",
                        expected: step.command.reportTarget.map(String.init(describing:))
                    )
                )
            )
        }

        internal static func expectationResolutionFailure(
            step: ActionStep,
            command: ResolvedHeistActionCommand,
            path: HeistExecutionPath,
            error: Error
        ) -> HeistExecutionStepResult {
            let observed = "could not resolve heist expectation: \(error)"
            let actionResult = ActionResult.failure(
                payload: command.actionResultPayload,
                failureKind: .validationError,
                message: observed
            )
            let evidence = HeistActionEvidence.completed(
                result: actionResult,
                expectation: nil
            )
            return .action(
                path: path,
                execution: .failed(
                    command: step.command,
                    evidence: .init(admitted: evidence),
                    failure: HeistFailureDetail(
                        category: .expectation,
                        contract: "action expectation predicate resolves before evaluation",
                        observed: observed,
                        expected: step.expectationPolicy.expectedExpectation?.predicate.description
                    )
                )
            )
        }

        internal static func waitResolutionFailure(
            step: WaitStep,
            context: StepContext,
            error: Error
        ) -> HeistExecutionStepResult {
            .wait(
                path: context.path,
                predicate: step.predicate,
                timeout: step.timeout,
                completion: .failed(
                    evidence: .unavailable,
                    failure: HeistFailureDetail(
                        category: .wait,
                        contract: "wait predicate resolves before evaluation",
                        observed: "could not resolve heist wait predicate: \(error)",
                        expected: step.predicate.description
                    )
                )
            )
        }

        internal static func heistTimeout(
            action leaf: ActionLeaf
        ) -> HeistExecutionStepResult {
            let result = ActionResult.failure(
                payload: leaf.command.actionResultPayload,
                failureKind: .timeout,
                message: "whole-heist deadline expired before action dispatch"
            )
            let evidence = HeistActionEvidence.completed(
                result: result,
                expectation: nil
            )
            return .action(
                path: leaf.path,
                execution: .failed(
                    command: leaf.step.command,
                    evidence: .init(admitted: evidence),
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "action begins within the whole-heist deadline",
                        observed: "whole-heist deadline expired before action dispatch"
                    )
                )
            )
        }

        internal static func heistTimeout(
            wait leaf: WaitLeaf
        ) -> HeistExecutionStepResult {
            .wait(
                path: leaf.context.path,
                predicate: leaf.step.predicate,
                timeout: leaf.step.timeout,
                completion: .failed(
                    evidence: .unavailable,
                    failure: HeistFailureDetail(
                        category: .wait,
                        contract: "wait begins within the whole-heist deadline",
                        observed: "whole-heist deadline expired before wait observation",
                        expected: leaf.step.predicate.description
                    )
                )
            )
        }

        internal static func project(
            action leaf: ActionLeaf,
            evidence: Observation.Evidence,
            outcome: LeafOutcome,
            timing: HeistExpectationTiming
        ) -> HeistExecutionStepResult {
            let actionResult = actionResult(
                leaf: leaf,
                evidence: evidence,
                outcome: outcome
            )
            let expectation = leaf.predicate.flatMap { predicate -> HeistExpectationEvidence? in
                guard leaf.dispatch?.success == true else { return nil }
                return expectationEvidence(
                    predicate,
                    observation: evidence,
                    outcome: outcome,
                    timing: timing
                )
            }
            let evidence = HeistActionEvidence.completed(
                result: actionResult,
                expectation: expectation
            )
            let execution: HeistActionExecution
            if actionResult.outcome.isSuccess {
                execution = .passed(
                    command: leaf.step.command,
                    evidence: .init(admitted: evidence)
                )
            } else if leaf.predicate != nil, expectation != nil {
                execution = .failed(
                    command: leaf.step.command,
                    evidence: .init(admitted: evidence),
                    failure: actionExpectationFailure(
                        step: leaf.step,
                        evidence: evidence
                    )
                )
            } else {
                execution = .failed(
                    command: leaf.step.command,
                    evidence: .init(admitted: evidence),
                    failure: actionDispatchFailure(
                        command: leaf.step.command,
                        result: actionResult
                    )
                )
            }
            return .action(
                path: leaf.path,
                execution: execution
            )
        }

        internal static func project(
            wait leaf: WaitLeaf,
            evidence: Observation.Evidence,
            outcome: LeafOutcome,
            timing: HeistExpectationTiming
        ) -> HeistExecutionStepResult {
            let expectation = expectationEvidence(
                leaf.predicate,
                observation: evidence,
                outcome: outcome,
                timing: timing
            )
            let passedEvidence = HeistPassedWaitEvidence(expectation)
            let completion: HeistWaitCompletion
            if let passedEvidence,
               passedEvidence.matchesExpectation {
                completion = .passed(evidence: passedEvidence)
            } else {
                completion = .failed(
                    evidence: .observed(expectation),
                    failure: waitFailure(
                        step: leaf.step,
                        evidence: expectation,
                        outcome: outcome
                    )
                )
            }
            return .wait(
                path: leaf.context.path,
                predicate: leaf.step.predicate,
                timeout: leaf.step.timeout,
                completion: completion
            )
        }

    }
}

private extension HeistExecution.ResultProjector {
    static func expectationEvidence(
        _ predicate: HeistExecution.Predicate,
        observation: Observation.Evidence,
        outcome: HeistExecution.LeafOutcome,
        timing: HeistExpectationTiming
    ) -> HeistExpectationEvidence {
        do {
            return try HeistExpectationEvidence(
                predicate: predicate.authored,
                bindings: predicate.bindings,
                observation: observation,
                terminalCause: outcome.expectationTerminalCause,
                timing: timing
            )
        } catch {
            preconditionFailure("Machine retained invalid predicate bindings: \(error)")
        }
    }

    static func actionResult(
        leaf: HeistExecution.ActionLeaf,
        evidence: Observation.Evidence,
        outcome: HeistExecution.LeafOutcome
    ) -> ActionResult {
        guard let dispatch = leaf.dispatch else {
            return .failure(
                payload: leaf.command.actionResultPayload,
                failureKind: .actionFailed,
                message: "action dispatch did not complete",
                observation: .observed(evidence)
            )
        }

        let resultOutcome: ActionResultOutcome
        let message: String?
        switch outcome {
        case .timedOut, .heistTimedOut:
            resultOutcome = .failure(.timeout)
            message = timeoutMessage(
                predicate: leaf.predicate,
                evidence: evidence,
                outstanding: leaf.expectation.result.outstandingDescription
            )
        case .completed:
            switch dispatch.outcome {
            case .failure(let failure):
                resultOutcome = .failure(TheBrains.actionFailureKind(for: failure))
                message = dispatch.message
            case .success:
                if leaf.expectation.result == .satisfied {
                    resultOutcome = .success
                    message = dispatch.message
                } else {
                    resultOutcome = .failure(.timeout)
                    message = timeoutMessage(
                        predicate: leaf.predicate,
                        evidence: evidence,
                        outstanding: leaf.expectation.result.outstandingDescription
                    )
                }
            }
        case .cancelled:
            resultOutcome = .failure(.actionFailed)
            message = "action observation cancelled"
        case .unavailable:
            resultOutcome = .failure(.accessibilityTreeUnavailable)
            message = TheBrains.treeUnavailableMessage
        case .viewportExitFailed:
            resultOutcome = .failure(.actionFailed)
            message = "Could not restore the accessibility viewport after observation"
        }

        return ActionResult(
            outcome: resultOutcome,
            payload: dispatch.payload,
            message: message,
            observation: .observed(evidence),
            subjectEvidence: dispatch.subjectEvidence,
            activationTrace: dispatch.activationTrace,
            screenActionHandler: dispatch.screenActionHandler,
            timing: timing(dispatch)
        )
    }

    static func timing(
        _ dispatch: TheSafecracker.ActionDispatchResult
    ) -> ActionPerformanceTiming {
        ActionPerformanceTiming(
            targetResolutionMs: dispatch.timing?.targetResolutionMs,
            actionDispatchMs: dispatch.timing?.actionDispatchMs,
            interactionMs: dispatch.timing?.interactionMs,
            totalMs: dispatch.timing?.totalMs
        )
    }

    static func timeoutMessage(
        predicate: HeistExecution.Predicate?,
        evidence: Observation.Evidence,
        outstanding: String?
    ) -> String {
        var message = "timed out"
        if let outstanding {
            message += " while waiting on \(outstanding)"
        }
        if let predicate, let current = evidence.current {
            message += "; expected: \(predicate.authored)"
            message += "; interface: \(current.interface.projectedElements.count) elements"
        }
        let lanes = evidence.events.map { event in
            switch event {
            case .elementsChanged: "elements"
            case .screenChanged: "screen"
            case .notification: "notification"
            case .noChange: "still"
            }
        }
        if !lanes.isEmpty {
            message += "; events [\(lanes.joined(separator: ", "))]"
        }
        return message
    }

    static func actionDispatchFailure(
        command: HeistActionCommand,
        result: ActionResult
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: result.outcome.failureKind == .elementNotFound
                ? .targetResolution
                : .action,
            contract: "action dispatch succeeds",
            observed: [
                result.message,
                result.outcome.failureKind.map { "failureKind=\($0.rawValue)" },
            ].compactMap { $0 }.joined(separator: "; "),
            expected: command.reportTarget.map(String.init(describing:))
        )
    }

    static func actionExpectationFailure(
        step: ActionStep,
        evidence: HeistActionEvidence
    ) -> HeistFailureDetail {
        let result = evidence.result
        let expectationActual: String?
        do {
            expectationActual = try evidence.replayExpectation()?.actual
        } catch {
            expectationActual = nil
        }
        return HeistFailureDetail(
            category: .expectation,
            contract: "post-action expectation is met",
            observed: [
                expectationActual,
                result?.message,
                result?.outcome.failureKind.map { "failureKind=\($0.rawValue)" },
            ].compactMap { $0 }.joined(separator: "; "),
            expected: step.expectationPolicy.expectedExpectation?.predicate.description
        )
    }

    static func waitFailure(
        step: WaitStep,
        evidence: HeistExpectationEvidence,
        outcome: HeistExecution.LeafOutcome
    ) -> HeistFailureDetail {
        let replay: ExpectationResult?
        do {
            replay = try evidence.replay()
        } catch {
            replay = nil
        }
        let category: HeistFailureCategory
        let observed: String
        switch outcome {
        case .completed:
            category = .wait
            observed = replay?.actual ?? "wait predicate was not met"
        case .timedOut, .heistTimedOut:
            category = .timeout
            observed = replay?.actual ?? "wait deadline expired"
        case .cancelled:
            category = .wait
            observed = "wait observation was cancelled"
        case .unavailable:
            category = .runtimeUnavailable
            observed = TheBrains.treeUnavailableMessage
        case .viewportExitFailed:
            category = .action
            observed = "Could not restore the accessibility viewport after observation"
        }
        return HeistFailureDetail(
            category: category,
            contract: "wait predicate is met before timeout",
            observed: observed,
            expected: step.predicate.description
        )
    }
}

extension ResolvedHeistActionCommand {
    internal var actionResultPayload: ActionResult.Payload {
        switch self {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .customAction: .customAction
        case .rotor: .rotor(nil)
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .typeText: .typeText(nil)
        case .oneFingerTap: .oneFingerTap
        case .longPress: .longPress
        case .swipe: .swipe
        case .drag: .drag
        case .scroll: .scroll
        case .scrollToVisible: .scrollToVisible
        case .scrollToEdge: .scrollToEdge
        case .editAction: .editAction
        case .setPasteboard: .setPasteboard(nil)
        case .takeScreenshot: .screenshot(nil)
        case .dismissKeyboard: .dismissKeyboard
        }
    }
}

extension HeistActionCommand {
    internal var actionResultPayload: ActionResult.Payload {
        switch self {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .customAction: .customAction
        case .rotor: .rotor(nil)
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .typeText: .typeText(nil)
        case .oneFingerTap: .oneFingerTap
        case .longPress: .longPress
        case .swipe: .swipe
        case .drag: .drag
        case .scroll: .scroll
        case .scrollToVisible: .scrollToVisible
        case .scrollToEdge: .scrollToEdge
        case .editAction: .editAction
        case .setPasteboard: .setPasteboard(nil)
        case .takeScreenshot: .screenshot(nil)
        case .dismissKeyboard: .dismissKeyboard
        }
    }
}

private extension HeistExecution.LeafOutcome {
    var expectationTerminalCause: HeistExpectationEvidence.TerminalCause {
        switch self {
        case .completed:
            .observed
        case .timedOut, .heistTimedOut:
            .deadline
        case .cancelled:
            .cancelled
        case .unavailable:
            .unavailable
        case .viewportExitFailed:
            .viewportFailure
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
