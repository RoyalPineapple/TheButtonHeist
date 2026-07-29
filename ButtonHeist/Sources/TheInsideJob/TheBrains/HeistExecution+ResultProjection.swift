#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension HeistExecution {
    internal enum ResultProjector {
        internal static func actionResolutionFailure(
            step: ActionStep,
            context: StepContext,
            error: Error
        ) -> HeistExecutionStepResult {
            let evidence = HeistActionEvidence.commandResolutionFailure
            return .action(
                path: context.path,
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
            context: StepContext,
            error: Error
        ) -> HeistExecutionStepResult {
            let observed = "could not resolve heist expectation: \(error)"
            let actionResult = ActionResult.failure(
                payload: command.actionResultPayload,
                failureKind: .validationError,
                message: observed
            )
            let expectation = ExpectationResult(
                met: false,
                predicate: nil,
                actual: observed
            )
            let evidence = HeistActionEvidence.completed(
                result: actionResult,
                expectation: expectation
            )
            return .action(
                path: context.path,
                execution: .failed(
                    command: step.command,
                    evidence: .init(admitted: evidence),
                    failure: HeistFailureDetail(
                        category: .expectation,
                        contract: "action expectation predicate resolves before evaluation",
                        observed: observed,
                        expected: step.expectationPolicy.expectedStep?.predicate.description
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
                    evidence: unmatchedWaitEvidence(
                        predicate: step.predicate,
                        actual: "could not resolve heist wait predicate: \(error)"
                    ),
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
            let expectation = leaf.predicate.map {
                ExpectationResult(
                    met: false,
                    predicate: $0.authored,
                    actual: "whole-heist deadline expired before observation"
                )
            }
            let evidence = HeistActionEvidence.completed(
                result: result,
                expectation: expectation
            )
            return .action(
                path: leaf.context.path,
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
                    evidence: unmatchedWaitEvidence(
                        predicate: leaf.step.predicate,
                        actual: "whole-heist deadline expired before wait observation"
                    ),
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
            outcome: LeafOutcome
        ) -> HeistExecutionStepResult {
            let actionResult = actionResult(
                leaf: leaf,
                evidence: evidence,
                outcome: outcome
            )
            let expectation: ExpectationResult? = leaf.predicate.flatMap { predicate -> ExpectationResult? in
                guard leaf.dispatch?.success == true else { return nil }
                return ExpectationResult(
                    met: outcome.admitsSatisfiedExpectation
                        && leaf.expectation.result == .satisfied,
                    predicate: predicate.authored,
                    actual: actualResult(
                        predicate: predicate,
                        evidence: evidence,
                        outstanding: leaf.expectation.result.outstandingDescription
                    )
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
                path: leaf.context.path,
                execution: execution
            )
        }

        internal static func project(
            wait leaf: WaitLeaf,
            evidence: Observation.Evidence,
            outcome: LeafOutcome
        ) -> HeistExecutionStepResult {
            let matched = outcome.admitsSatisfiedExpectation
                && leaf.expectation.result == .satisfied
            let actual = actualResult(
                predicate: leaf.predicate,
                evidence: evidence,
                outstanding: leaf.expectation.result.outstandingDescription
            )
            let completion: HeistWaitCompletion
            if matched {
                completion = .passed(
                    evidence: .matched(HeistWaitMatchedEvidence(
                        observation: evidence,
                        expectation: ExpectationResult.Met(
                            predicate: leaf.predicate.authored,
                            actual: actual
                        )
                    ))
                )
            } else {
                let unmatched = HeistWaitUnmatchedEvidence(
                    observation: evidence,
                    expectation: ExpectationResult.Unmet(
                        predicate: leaf.predicate.authored,
                        actual: actual
                    )
                )
                completion = .failed(
                    evidence: unmatched,
                    failure: waitFailure(
                        step: leaf.step,
                        evidence: unmatched,
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
        switch dispatch.outcome {
        case .failure(let failure):
            resultOutcome = .failure(TheBrains.actionFailureKind(for: failure))
            message = dispatch.message
        case .success:
            switch outcome {
            case .completed, .timedOut, .heistTimedOut:
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

    static func actualResult(
        predicate: HeistExecution.Predicate,
        evidence: Observation.Evidence,
        outstanding: String?
    ) -> String? {
        if let outstanding {
            return "still waiting on: \(outstanding)"
        }
        guard case .notification(let notificationPredicate) = predicate.resolved else {
            return nil
        }
        return evidence.events.lazy.compactMap { event -> Observation.Notification? in
            guard case .notification(let notification) = event else { return nil }
            return notification
        }
        .first(where: notificationPredicate.matches)?
        .text
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
        return HeistFailureDetail(
            category: .expectation,
            contract: "post-action expectation is met",
            observed: [
                evidence.expectation?.actual,
                result?.message,
                result?.outcome.failureKind.map { "failureKind=\($0.rawValue)" },
            ].compactMap { $0 }.joined(separator: "; "),
            expected: step.expectationPolicy.expectedStep?.predicate.description
        )
    }

    static func waitFailure(
        step: WaitStep,
        evidence: HeistWaitUnmatchedEvidence,
        outcome: HeistExecution.LeafOutcome
    ) -> HeistFailureDetail {
        let category: HeistFailureCategory
        let observed: String
        switch outcome {
        case .completed:
            category = .wait
            observed = evidence.expectation.actual ?? "wait predicate was not met"
        case .timedOut, .heistTimedOut:
            category = .timeout
            observed = evidence.expectation.actual ?? "wait deadline expired"
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

    static func unmatchedWaitEvidence(
        predicate: AccessibilityPredicate,
        actual: String
    ) -> HeistWaitUnmatchedEvidence {
        HeistWaitUnmatchedEvidence(
            observation: Observation.Evidence(
                baseline: nil,
                current: nil,
                events: [],
                completeness: .incomplete
            ),
            expectation: ExpectationResult.Unmet(
                predicate: predicate,
                actual: actual
            )
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

private extension HeistExecution.LeafOutcome {
    var admitsSatisfiedExpectation: Bool {
        switch self {
        case .completed, .timedOut, .heistTimedOut:
            true
        case .cancelled, .unavailable, .viewportExitFailed:
            false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
