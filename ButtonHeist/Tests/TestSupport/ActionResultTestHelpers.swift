import Foundation
import ThePlans
@testable import TheScore

package enum HeistResultFixture {
    package static func actionResult(
        succeeded: Bool = true,
        payload: ActionResult.Payload = .activate,
        message: String? = nil,
        failureKind: ActionFailure.Kind? = nil,
        observationEvidence: Observation.Evidence? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        screenActionHandler: ScreenActionHandlerName? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        let observation = observationEvidence.map(ActionResultObservationEvidence.observed) ?? .none
        if succeeded {
            if let activationTrace {
                guard payload == .activate else {
                    preconditionFailure("activation trace fixture requires activate payload")
                }
                return .activationSuccess(
                    message: message,
                    observation: observation,
                    subjectEvidence: subjectEvidence,
                    activationTrace: activationTrace,
                    timing: timing
                )
            }
            return ActionResult(
                outcome: .success,
                payload: payload,
                message: message,
                observation: observation,
                subjectEvidence: subjectEvidence,
                activationTrace: nil,
                screenActionHandler: screenActionHandler,
                timing: timing
            )
        }

        guard let failureKind else {
            preconditionFailure("failed test ActionResult requires failureKind")
        }
        if let activationTrace {
            guard payload == .activate else {
                preconditionFailure("activation trace fixture requires activate payload")
            }
            return .activationFailure(
                failureKind: failureKind,
                message: message,
                observation: observation,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: timing
            )
        }
        return .failure(
            payload: payload,
            failureKind: failureKind,
            message: message,
            observation: observation,
            subjectEvidence: subjectEvidence,
            timing: timing
        )
    }

    package static func action(
        path: String = "$.body[0]",
        command: HeistActionCommand = .activate(.predicate(ElementPredicate(label: "Button"))),
        result: ActionResult = actionResult(),
        expectation: HeistExpectationEvidence? = nil,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let evidence = HeistActionEvidence.completed(result: result, expectation: expectation)

        let resolvedFailure = failure ?? inferredActionFailure(result)
        if let resolvedFailure {
            guard let evidence = HeistFailedActionEvidence(evidence) else {
                preconditionFailure("failed action result fixture requires failing evidence")
            }
            return HeistExecutionStepResult.action(
                path: executionPath(path),
                execution: .failed(command: command, evidence: evidence, failure: resolvedFailure)
            )
        }
        guard let evidence = HeistPassedActionEvidence(evidence) else {
            preconditionFailure("passed action result fixture requires passing evidence")
        }
        return HeistExecutionStepResult.action(
            path: executionPath(path),
            execution: .passed(command: command, evidence: evidence)
        )
    }

    package static func wait(
        path: String = "$.body[0]",
        evidence: HeistExpectationEvidence = HeistResultFixture.defaultWaitEvidence(met: true)
    ) -> HeistExecutionStepResult {
        guard let passedEvidence = HeistPassedWaitEvidence.matched(evidence) else {
            preconditionFailure("passed wait result fixture requires replay proof")
        }
        return .wait(
            path: executionPath(path),
            predicate: evidence.predicate,
            timeout: 1,
            completion: .passed(evidence: passedEvidence)
        )
    }

    package static func failedWait(
        path: String = "$.body[0]",
        evidence: HeistExpectationEvidence = HeistResultFixture.defaultWaitEvidence(met: false),
        failure: HeistFailureDetail
    ) -> HeistExecutionStepResult {
        .wait(
            path: executionPath(path),
            predicate: evidence.predicate,
            timeout: 1,
            completion: .failed(
                evidence: .observed(evidence),
                failure: failure
            )
        )
    }

    package static func expectationEvidence(
        predicate: AccessibilityPredicate,
        observation: Observation.Evidence,
        terminalCause: HeistExpectationEvidence.TerminalCause = .observed
    ) -> HeistExpectationEvidence {
        do {
            return HeistExpectationEvidence(
                predicate: predicate,
                observation: observation,
                terminalCause: terminalCause
            )
        } catch {
            preconditionFailure("test expectation predicate must resolve: \(error)")
        }
    }

    package static func warning(
        path: String = "$.body[0]",
        message: String
    ) -> HeistExecutionStepResult {
        .warning(
            path: executionPath(path),
            message: HeistWarningMessage(stringLiteral: message),
            completion: .passed()
        )
    }

    package static func explicitFailure(
        path: String = "$.body[0]",
        message: String
    ) -> HeistExecutionStepResult {
        .failure(
            path: executionPath(path),
            message: HeistFailureMessage(stringLiteral: message),
            completion: .failed(failure: HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: message
            ))
        )
    }

    package static func conditional(
        path: String = "$.body[0]",
        status: HeistExecutionStepStatus = .passed,
        selection: HeistCaseSelectionResult,
        failure: HeistFailureDetail? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let evidence = HeistCaseSelectionEvidence(selection: selection)
        if let abortedAtChildPath = children.firstFailedStep?.path {
            guard let children = HeistAbortedChildren(children) else {
                preconditionFailure("conditional aborted children require the first failed path")
            }
            return .conditional(
                path: executionPath(path),
                completion: .childAborted(
                    evidence: evidence,
                    failure: failure ?? HeistFailureDetail(
                        category: .invocation,
                        contract: "selected case body completes without failure",
                        observed: "child failed at \(abortedAtChildPath)"
                    ),
                    children: children
                )
            )
        }
        if status == .failed {
            return .conditional(
                path: executionPath(path),
                completion: .failed(
                    evidence: .observed(evidence),
                    failure: failure ?? HeistFailureDetail(
                        category: .validation,
                        contract: "conditional branch completes",
                        observed: "conditional failed"
                    ),
                    children: passingChildren(children)
                )
            )
        }
        return .conditional(
            path: executionPath(path),
            completion: .passed(evidence: evidence, children: passingChildren(children))
        )
    }

    package static func forEachStringIteration(
        path: String? = nil,
        parameter: HeistReferenceName = "item",
        count: Int = 2,
        iterationCount: Int? = nil,
        ordinal: Int,
        value: String,
        status: HeistExecutionStepStatus,
        failureReason: String? = nil,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let resolvedPath = path ?? "$.body[0].for_each_string.iterations[\(ordinal)]"
        guard let evidence = HeistForEachStringEvidence(
            iterationCount: iterationCount ?? ordinal + 1,
            iterationOrdinal: ordinal,
            value: value,
            failureReason: failureReason
        ) else {
            preconditionFailure("invalid string loop fixture progress")
        }
        guard let declaration = HeistForEachStringDeclaration(parameter: parameter, count: count) else {
            preconditionFailure("invalid string loop fixture declaration")
        }
        let failure = failureReason.map {
            HeistFailureDetail(
                category: .loop,
                contract: "iteration \(ordinal) completes",
                observed: $0
            )
        }
        if let abortedAtChildPath = children.firstFailedStep?.path {
            guard let admittedEvidence = HeistFailedForEachStringEvidence(evidence),
                  let admittedChildren = HeistAbortedChildren(children) else {
                preconditionFailure("aborted loop fixture requires failed evidence and children")
            }
            return HeistExecutionStepResult.forEachStringIteration(
                path: executionPath(resolvedPath),
                declaration: declaration,
                completion: .childAborted(
                    evidence: admittedEvidence,
                    failure: failure ?? HeistFailureDetail(
                        category: .loop,
                        contract: "iteration \(ordinal) completes",
                        observed: "child failed at \(abortedAtChildPath)"
                    ),
                    children: admittedChildren
                )
            )
        }
        if status == .failed, let failure {
            guard let evidence = HeistFailedForEachStringEvidence(evidence) else {
                preconditionFailure("failed loop fixture requires a failure reason")
            }
            return HeistExecutionStepResult.forEachStringIteration(
                path: executionPath(resolvedPath),
                declaration: declaration,
                completion: .failed(
                    evidence: .observed(evidence),
                    failure: failure,
                    children: passingChildren(children)
                )
            )
        }
        guard let evidence = HeistPassedForEachStringEvidence(evidence) else {
            preconditionFailure("passed loop fixture cannot carry a failure reason")
        }
        return HeistExecutionStepResult.forEachStringIteration(
            path: executionPath(resolvedPath),
            declaration: declaration,
            completion: .passed(evidence: evidence, children: passingChildren(children))
        )
    }

    package static func result(
        steps: [HeistExecutionStepResult],
        durationMs: ElapsedMilliseconds = 1
    ) -> HeistResult {
        do {
            return try HeistResult(steps: steps, durationMs: durationMs)
        } catch {
            preconditionFailure("invalid heist result fixture: \(error)")
        }
    }

    private static func executionPath(_ description: String) -> HeistExecutionPath {
        do {
            return try HeistExecutionPath(validating: description)
        } catch {
            preconditionFailure("invalid result fixture path \(description): \(error)")
        }
    }

    private static func passingChildren(_ children: [HeistExecutionStepResult]) -> HeistPassingChildren {
        guard let children = HeistPassingChildren(children) else {
            preconditionFailure("passing result fixture cannot contain failed children")
        }
        return children
    }

    private static func inferredActionFailure(_ result: ActionResult) -> HeistFailureDetail? {
        guard !result.outcome.isSuccess else { return nil }
        return HeistFailureDetail(
            category: result.outcome.failureKind == .elementNotFound ? .targetResolution : .action,
            contract: "action dispatch succeeds",
            observed: result.message ?? "action failed"
        )
    }

    package static func defaultWaitEvidence(met: Bool) -> HeistExpectationEvidence {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let current = makeTestObservationSnapshot(
            elements: met ? [makeTestHeistElement(label: "Done")] : []
        )
        return expectationEvidence(
            predicate: predicate,
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(current), .noChange],
                current: current,
                coverage: .complete
            )
        )
    }
}
