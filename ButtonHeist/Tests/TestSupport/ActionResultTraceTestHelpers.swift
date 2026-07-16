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

package enum HeistReceiptFixture {
    package static func actionResult(
        succeeded: Bool = true,
        method: ActionMethod = .activate,
        message: String? = nil,
        errorKind: ErrorKind? = nil,
        payload: ActionResultPayload? = nil,
        traceEvidence: AccessibilityTraceEvidence? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        let observation = traceEvidence.map(ActionResultObservationEvidence.trace) ?? .none
        if succeeded {
            let evidence = ActionResultSuccessEvidence(
                observation: observation,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: timing
            )
            if let payload {
                return .success(payload: payload, message: message, evidence: evidence)
            }
            return .success(method: method, message: message, evidence: evidence)
        }

        guard let errorKind else {
            preconditionFailure("failed test ActionResult requires errorKind")
        }
        let evidence = ActionResultFailureEvidence(
            observation: observation,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
        if let payload {
            return .failure(payload: payload, errorKind: errorKind, message: message, evidence: evidence)
        }
        return .failure(method: method, errorKind: errorKind, message: message, evidence: evidence)
    }

    package static func action(
        path: String = "$.body[0]",
        command: HeistActionCommand = .activate(.predicate(ElementPredicateTemplate(label: "Button"))),
        result: ActionResult = actionResult(),
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        durationMs: Int = 1,
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
                preconditionFailure("failed action receipt fixture requires failing evidence")
            }
            return .action(
                path: executionPath(path),
                durationMs: durationMs,
                command: command,
                completion: .failed(evidence: evidence, failure: resolvedFailure)
            )
        }
        guard let evidence = HeistPassedActionEvidence(evidence) else {
            preconditionFailure("passed action receipt fixture requires passing evidence")
        }
        return .action(
            path: executionPath(path),
            durationMs: durationMs,
            command: command,
            completion: .passed(evidence: evidence)
        )
    }

    package static func wait(
        path: String = "$.body[0]",
        actionResult: ActionResult = .success(method: .wait, evidence: .none),
        expectation: ExpectationResult = ExpectationResult(
            met: true,
            predicate: .exists(.label("Done"))
        ),
        durationMs: Int = 1,
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
        if let failure {
            guard let evidence = HeistFailedWaitEvidence(evidence) else {
                preconditionFailure("failed wait receipt fixture requires failing evidence")
            }
            return .wait(
                path: executionPath(path),
                durationMs: durationMs,
                predicate: predicate,
                timeout: 1,
                completion: .failed(evidence: .observed(evidence), failure: failure)
            )
        }
        guard let evidence = HeistPassedWaitEvidence(evidence) else {
            preconditionFailure("passed wait receipt fixture requires matched evidence")
        }
        return .wait(
            path: executionPath(path),
            durationMs: durationMs,
            predicate: predicate,
            timeout: 1,
            completion: .passed(evidence: evidence)
        )
    }

    package static func warning(
        path: String = "$.body[0]",
        message: String,
        durationMs: Int = 1
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
        durationMs: Int = 1
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
        durationMs: Int? = nil,
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
        durationMs: Int = 1,
        failureReason: String? = nil,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let resolvedPath = path ?? "$.body[0].for_each_string.iterations[\(ordinal)]"
        let evidence = HeistForEachStringEvidence(
            iterationCount: iterationCount ?? count,
            iterationOrdinal: ordinal,
            value: value,
            failureReason: failureReason
        )
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
            return .forEachStringIteration(
                path: executionPath(resolvedPath),
                durationMs: durationMs,
                parameter: parameter,
                count: count,
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
            return .forEachStringIteration(
                path: executionPath(resolvedPath),
                durationMs: durationMs,
                parameter: parameter,
                count: count,
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
        return .forEachStringIteration(
            path: executionPath(resolvedPath),
            durationMs: durationMs,
            parameter: parameter,
            count: count,
            completion: .passed(evidence: evidence, children: passingChildren(children))
        )
    }

    package static func result(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 1
    ) -> HeistExecutionResult {
        HeistExecutionResult(
            steps: steps,
            durationMs: durationMs
        )
    }

    private static func executionPath(_ description: String) -> HeistExecutionPath {
        do {
            return try HeistExecutionPath(validating: description)
        } catch {
            preconditionFailure("invalid receipt fixture path \(description): \(error)")
        }
    }

    private static func passingChildren(_ children: [HeistExecutionStepResult]) -> HeistPassingChildren {
        guard let children = HeistPassingChildren(children) else {
            preconditionFailure("passing receipt fixture cannot contain failed children")
        }
        return children
    }

    private static func inferredActionFailure(_ result: ActionResult) -> HeistFailureDetail? {
        guard !result.outcome.isSuccess else { return nil }
        return HeistFailureDetail(
            category: result.outcome.errorKind == .elementNotFound ? .targetResolution : .action,
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
        return AccessibilityTrace(captures: [
            capture(sequence: 1, interface: interface),
            capture(sequence: 2, interface: interface),
        ])
    }

    static func elementsChanged(elementCount: Int, edits: ElementEdits) -> AccessibilityTrace {
        let before = interface(elements: beforeElements(for: edits, elementCount: elementCount))
        let after = interface(elements: afterElements(for: edits, elementCount: elementCount))
        if edits.isEmpty {
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: before, context: .empty),
                capture(sequence: 2, interface: before, context: AccessibilityTrace.Context(keyboardVisible: true)),
            ])
        }
        return AccessibilityTrace(captures: [
            capture(sequence: 1, interface: before),
            capture(sequence: 2, interface: after),
        ])
    }

    static func screenChanged(replacementInterface: Interface) -> AccessibilityTrace {
        AccessibilityTrace(captures: [
            capture(
                sequence: 1,
                interface: interface(elements: []),
                context: AccessibilityTrace.Context(screenId: "before")
            ),
            capture(
                sequence: 2,
                interface: replacementInterface,
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
            ),
        ])
    }

    private static func capture(
        sequence: Int,
        interface: Interface,
        context: AccessibilityTrace.Context = .empty,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            context: context,
            transition: transition
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
