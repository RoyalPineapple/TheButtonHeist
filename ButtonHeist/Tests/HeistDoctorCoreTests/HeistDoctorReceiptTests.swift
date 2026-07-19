import ButtonHeistTestSupport
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistDoctorReceiptTests {
    @Test("Doctor derives suggestions from receipt pair")
    func doctorDerivesSuggestionsFromReceiptPair() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let lastPass = receipt(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ]),
            after: makeTestInterface(elements: [
                element(label: "Bread", traits: [.staticText]),
                element(label: "Archive", traits: [.button], actions: [.activate]),
            ]),
            actionSucceeded: true
        )
        let newFail = receipt(
            path: "$.body[0]",
            status: .failed,
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Archive"),
            ]),
            after: nil,
            actionSucceeded: false
        )

        let suggestion = try #require(HeistDoctor.diagnosis(lastPass: lastPass, newFail: newFail).suggestions.first)

        #expect(suggestion.stepPath == "$.body[0]")
        #expect(suggestion.failureKind == .missingTarget)
        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Remove")))
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
    }

    @Test func `doctor repair evidence uses action evidence result meanings`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Pay"))
        let before = makeTestInterface(elements: [
            element(label: "Pay", traits: [.button], actions: [.activate]),
        ])
        let dispatchAfter = makeTestInterface(elements: [
            element(label: "Processing", traits: [.staticText]),
        ])
        let expectationAfter = makeTestInterface(elements: [
            element(label: "Still Processing", traits: [.staticText]),
        ])
        let dispatchTrace = AccessibilityTrace(first: before).appending(dispatchAfter)
        let expectationTrace = AccessibilityTrace(first: dispatchAfter).appending(expectationAfter)
        let predicate = AccessibilityPredicate.changed(.screen())
        let failure = HeistFailureDetail(
            category: .expectation,
            contract: "action expectation is met",
            observed: "timed out waiting for checkout",
            expected: predicate.description
        )
        let step = HeistReceiptFixture.action(
            path: "$.body[0]",
            command: .activate(target),
            result: ActionResult.success(
                method: .activate,
                observation: .trace(makeTestTraceEvidence(dispatchTrace, completeness: .incomplete))
            ),
            expectationActionResult: ActionResult.failure(
                method: .wait,
                errorKind: .timeout,
                message: "wait timed out",
                observation: .trace(makeTestTraceEvidence(expectationTrace, completeness: .incomplete))
            ),
            expectation: ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "timed out waiting for checkout"
            ),
            durationMs: 1,
            failure: failure
        )

        let repairEvidence = try HeistDoctor.repairEvidence(from: step)

        #expect(repairEvidence.beforeSnapshot == before)
        #expect(repairEvidence.changeFacts == dispatchTrace.changeFacts)
        #expect(repairEvidence.command == .activate(target))
        #expect(repairEvidence.method == .activate)
        #expect(repairEvidence.expectation?.met == false)
        guard case .failed(let errorKind, let message) = repairEvidence.outcome else {
            Issue.record("Expected failed repair evidence")
            return
        }
        #expect(errorKind == .timeout)
        #expect(message == "timed out waiting for checkout")
    }

    @Test func `doctor diagnosis returns typed refusal for valid receipt pair`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let lastPass = receipt(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            after: nil,
            actionSucceeded: true
        )
        let newFail = receipt(
            path: "$.body[0]",
            status: .failed,
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ]),
            after: nil,
            actionSucceeded: false
        )

        let result = try HeistDoctor.diagnosis(lastPass: lastPass, newFail: newFail)
        guard case .refused(let diagnosis) = result else {
            Issue.record("Expected refused diagnosis")
            return
        }
        let refusal = diagnosis.refusal

        #expect(refusal.stage == .candidateRanking)
        #expect(refusal.reason == .noCandidateMetScoreThreshold)
        #expect(refusal.message.contains("old target is missing"))
        #expect(result.suggestions.isEmpty)
        #expect(result.noSuggestionReason == refusal.message)
    }

    private func receipt(
        path: String,
        status: HeistExecutionStepStatus,
        target: AccessibilityTarget,
        before: Interface,
        after: Interface?,
        actionSucceeded: Bool
    ) -> HeistExecutionResult {
        let trace = after
            .map { AccessibilityTrace(first: before).appending($0) }
            ?? AccessibilityTrace(first: before)
        let actionResult = if actionSucceeded {
            ActionResult.success(
                method: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        } else {
            ActionResult.failure(
                method: .activate,
                errorKind: .elementNotFound,
                message: "No element matching \(target)",
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        }
        let step = status == .failed
            ? HeistReceiptFixture.action(
                path: path,
                command: .activate(target),
                result: actionResult,
                durationMs: 1,
                failure: HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action dispatch succeeds",
                    observed: "No element matching \(target)",
                    expected: target.description
                )
            )
            : HeistReceiptFixture.action(
                path: path,
                command: .activate(target),
                result: actionResult,
                durationMs: 1
            )
        return HeistExecutionResult(
            steps: [step],
            durationMs: 1
        )
    }
}
