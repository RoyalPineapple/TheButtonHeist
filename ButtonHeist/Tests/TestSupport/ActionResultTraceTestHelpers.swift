import Foundation
import ThePlans
@testable import TheScore

package func makeTestScreenPayload(
    pngData: String = "",
    width: Double = 393,
    height: Double = 852,
    timestamp: Date = Date(timeIntervalSince1970: 0),
    interface: Interface? = nil
) -> ScreenPayload {
    ScreenPayload(
        pngData: pngData,
        width: width,
        height: height,
        timestamp: timestamp,
        interface: interface
    )
}

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
        command: HeistActionCommand? = .activate(.predicate(ElementPredicateTemplate(label: "Button"))),
        result: ActionResult = actionResult(),
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        durationMs: Int = 1,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let evidence: HeistActionEvidence
        if let expectationActionResult, let expectation {
            guard let command else {
                preconditionFailure("Expectation action evidence requires a command")
            }
            evidence = .expectation(
                command: command,
                dispatchResult: result,
                expectationResult: expectationActionResult,
                expectation: expectation
            )
        } else {
            precondition(expectationActionResult == nil && expectation == nil)
            evidence = command.map {
                .dispatch(command: $0, dispatchResult: result)
            } ?? .commandlessDispatch(dispatchResult: result)
        }

        let intent = command.map { HeistStepIntent.action(command: $0) }
        let resolvedFailure = failure ?? inferredActionFailure(result)
        if let resolvedFailure {
            return .failed(
                path: path,
                receiptKind: .action,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: resolvedFailure
            )
        }
        return .passed(
            path: path,
            receiptKind: .action,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence
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
            ?? AccessibilityPredicate<RootContext>.exists(.label("predicate"))
        let intent = HeistStepIntent.wait(predicate: predicate, timeout: 0)
        if let failure {
            return .failed(
                path: path,
                receiptKind: .wait,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure
            )
        }
        return .passed(
            path: path,
            receiptKind: .wait,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence
        )
    }

    package static func warning(
        path: String = "$.body[0]",
        message: String,
        durationMs: Int = 1
    ) -> HeistExecutionStepResult {
        .passed(
            path: path,
            receiptKind: .warning,
            durationMs: durationMs,
            intent: .warn(message: message),
            evidence: HeistExecutionWarning(path: path, message: message)
        )
    }

    package static func explicitFailure(
        path: String = "$.body[0]",
        message: String,
        durationMs: Int = 1
    ) -> HeistExecutionStepResult {
        .failed(
            path: path,
            kind: .fail,
            durationMs: durationMs,
            intent: .fail(message: message),
            failure: HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: message
            )
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
            return .childAborted(
                path: path,
                receiptKind: .conditional,
                durationMs: resolvedDuration,
                intent: .conditional,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .invocation,
                    contract: "selected case body completes without failure",
                    observed: "child failed at \(abortedAtChildPath)"
                ),
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        }
        if status == .failed {
            return .failed(
                path: path,
                receiptKind: .conditional,
                durationMs: resolvedDuration,
                intent: .conditional,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .validation,
                    contract: "conditional branch completes",
                    observed: "conditional failed"
                ),
                children: children
            )
        }
        return .passed(
            path: path,
            receiptKind: .conditional,
            durationMs: resolvedDuration,
            intent: .conditional,
            evidence: evidence,
            children: children
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
            parameter: parameter,
            count: count,
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
            return .childAborted(
                path: resolvedPath,
                receiptKind: .forEachStringIteration,
                durationMs: durationMs,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .loop,
                    contract: "iteration \(ordinal) completes",
                    observed: "child failed at \(abortedAtChildPath)"
                ),
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        }
        if status == .failed, let failure {
            return .failed(
                path: resolvedPath,
                receiptKind: .forEachStringIteration,
                durationMs: durationMs,
                evidence: evidence,
                failure: failure,
                children: children
            )
        }
        return .passed(
            path: resolvedPath,
            receiptKind: .forEachStringIteration,
            durationMs: durationMs,
            evidence: evidence,
            children: children
        )
    }

    package static func result(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 1,
        abortedAtPath: String? = nil
    ) -> HeistExecutionResult {
        HeistExecutionResult(
            steps: steps,
            durationMs: durationMs,
            abortedAtPath: abortedAtPath
        )
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
