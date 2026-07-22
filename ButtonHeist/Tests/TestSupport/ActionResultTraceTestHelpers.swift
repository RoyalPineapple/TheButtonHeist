import Foundation
import ThePlans
@testable import TheScore

package func makeTestTraceEvidence(
    _ trace: AccessibilityTrace,
    completeness: AccessibilityTraceEvidence.Completeness
) -> AccessibilityTraceEvidence {
    guard let evidence = AccessibilityTraceEvidence(
        trace: trace,
        completeness: completeness
    ) else {
        preconditionFailure("test trace evidence requires a current capture")
    }
    return evidence
}

package enum HeistResultFixture {
    package static func actionResult(
        succeeded: Bool = true,
        payload: ActionResult.Payload = .activate,
        message: String? = nil,
        failureKind: ActionFailure.Kind? = nil,
        traceEvidence: AccessibilityTraceEvidence? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        screenActionHandler: ScreenActionHandlerName? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        let observation = traceEvidence.map(ActionResultObservationEvidence.trace) ?? .none
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
        command: HeistActionCommand = .activate(.predicate(ElementPredicateTemplate(label: "Button"))),
        result: ActionResult = actionResult(),
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        durationMs: ElapsedMilliseconds = 1,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let evidence: HeistActionEvidence
        if let expectationActionResult, let expectation {
            evidence = .expectation(
                dispatchResult: result,
                expectationResult: expectationActionResult,
                expectation: expectation
            )
        } else {
            precondition(expectationActionResult == nil && expectation == nil)
            evidence = .dispatch(dispatchResult: result)
        }

        let resolvedFailure = failure ?? inferredActionFailure(result)
        if let resolvedFailure {
            guard let evidence = HeistFailedActionEvidence(evidence) else {
                preconditionFailure("failed action result fixture requires failing evidence")
            }
            return HeistExecutionStepResult.action(
                path: executionPath(path),
                durationMs: durationMs,
                execution: .failed(command: command, evidence: evidence, failure: resolvedFailure)
            )
        }
        guard let evidence = HeistPassedActionEvidence(evidence) else {
            preconditionFailure("passed action result fixture requires passing evidence")
        }
        return HeistExecutionStepResult.action(
            path: executionPath(path),
            durationMs: durationMs,
            execution: .passed(command: command, evidence: evidence)
        )
    }

    package static func wait(
        path: String = "$.body[0]",
        actionResult: ActionResult = .success(payload: .wait),
        expectation: ExpectationResult = ExpectationResult(
            met: true,
            predicate: .exists(.label("Done"))
        ),
        durationMs: ElapsedMilliseconds = 1,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let evidence: HeistWaitEvidence
        if failure == nil {
            guard let met = ExpectationResult.Met(expectation),
                  let matched = HeistWaitEvidence.MatchedCheck(
                      actionResult: actionResult,
                      expectation: met
                  ) else {
                preconditionFailure("passed wait fixture requires matched evidence")
            }
            evidence = .matched(matched)
        } else {
            guard let unmatched = HeistWaitEvidence.UnmatchedCheck(
                actionResult: actionResult,
                expectation: expectation
            ) else {
                preconditionFailure("failed wait fixture requires unmatched evidence")
            }
            evidence = .failed(unmatched)
        }

        let predicate = expectation.predicate
            ?? AccessibilityPredicate.exists(.label("predicate"))
        let completion: HeistWaitCompletion
        if let failure {
            guard let evidence = HeistFailedWaitEvidence(evidence) else {
                preconditionFailure("failed wait result fixture requires failing evidence")
            }
            completion = .failed(evidence: .observed(evidence), failure: failure)
        } else {
            guard let evidence = HeistPassedWaitEvidence(evidence) else {
                preconditionFailure("passed wait result fixture requires matched evidence")
            }
            completion = .passed(evidence: evidence)
        }
        return .wait(
            path: executionPath(path),
            durationMs: durationMs,
            predicate: predicate,
            timeout: 1,
            completion: completion
        )
    }

    package static func warning(
        path: String = "$.body[0]",
        message: String,
        durationMs: ElapsedMilliseconds = 1
    ) -> HeistExecutionStepResult {
        .warning(
            path: executionPath(path),
            durationMs: durationMs,
            message: HeistWarningMessage(stringLiteral: message),
            completion: .passed()
        )
    }

    package static func explicitFailure(
        path: String = "$.body[0]",
        message: String,
        durationMs: ElapsedMilliseconds = 1
    ) -> HeistExecutionStepResult {
        .failure(
            path: executionPath(path),
            durationMs: durationMs,
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
        durationMs: ElapsedMilliseconds? = nil,
        failure: HeistFailureDetail? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let evidence = HeistCaseSelectionEvidence(selection: selection)
        let resolvedDuration = durationMs ?? selection.elapsedMs
        if let abortedAtChildPath = children.firstFailedStep?.path {
            guard let children = HeistAbortedChildren(children) else {
                preconditionFailure("conditional aborted children require the first failed path")
            }
            return .conditional(
                path: executionPath(path),
                durationMs: resolvedDuration,
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
                durationMs: resolvedDuration,
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
            durationMs: resolvedDuration,
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
        durationMs: ElapsedMilliseconds = 1,
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
                durationMs: durationMs,
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
                durationMs: durationMs,
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
            durationMs: durationMs,
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
}

package extension AccessibilityTrace {
    static func noChangeForTests(elementCount: Int) -> AccessibilityTrace {
        TestActionResultTrace.noChange(elementCount: elementCount)
    }

    static func elementsChangedForTests(
        elementCount: Int,
        edits: ElementEdits
    ) -> AccessibilityTrace {
        TestActionResultTrace.elementsChanged(elementCount: elementCount, edits: edits)
    }

    static func screenChangedForTests(replacementInterface: Interface) -> AccessibilityTrace {
        TestActionResultTrace.screenChanged(replacementInterface: replacementInterface)
    }
}

private enum TestActionResultTrace {
    static func noChange(elementCount: Int) -> AccessibilityTrace {
        let interface = interface(elements: placeholders(count: elementCount))
        return AccessibilityTrace(first: interface).appending(interface)
    }

    static func elementsChanged(elementCount: Int, edits: ElementEdits) -> AccessibilityTrace {
        let before = interface(elements: beforeElements(for: edits, elementCount: elementCount))
        let after = interface(elements: afterElements(for: edits, elementCount: elementCount))
        if edits.isEmpty {
            return AccessibilityTrace(first: before).appending(
                before,
                context: AccessibilityTrace.Context(keyboardVisible: true)
            )
        }
        return AccessibilityTrace(first: before).appending(after)
    }

    static func screenChanged(replacementInterface: Interface) -> AccessibilityTrace {
        AccessibilityTrace(
            capture: AccessibilityTrace.Capture(
                sequence: 1,
                interface: interface(elements: []),
                context: AccessibilityTrace.Context(screenId: "before")
            )
        ).appending(
            replacementInterface,
            context: AccessibilityTrace.Context(screenId: "after"),
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [
                AccessibilityNotificationEvidence(
                    sequence: 1,
                    kind: .screenChanged,
                    timestamp: Date(timeIntervalSince1970: 1),
                    notificationData: .none,
                    associatedElement: .none
                ),
            ])
        )
    }

    private static func interface(elements: [HeistElement]) -> Interface {
        makeTestInterface(elements: elements)
    }

    private static func beforeElements(for edits: ElementEdits, elementCount: Int) -> [HeistElement] {
        padded(edits.removed + edits.updated.map(\.before), count: elementCount)
    }

    private static func afterElements(for edits: ElementEdits, elementCount: Int) -> [HeistElement] {
        padded(edits.added + edits.updated.map(\.after), count: elementCount)
    }

    private static func padded(_ elements: [HeistElement], count: Int) -> [HeistElement] {
        let missing = max(0, count - elements.count)
        return elements + placeholders(count: missing, prefix: "__stable_")
    }

    private static func placeholders(count: Int, prefix: String = "__element_") -> [HeistElement] {
        guard count > 0 else { return [] }
        return (0..<count).map { placeholder(id: "\(prefix)\($0)", label: "Element \($0)") }
    }

    private static func placeholder(
        id: String,
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [.button]
    ) -> HeistElement {
        makeTestHeistElement(
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            actions: [.activate]
        )
    }
}
