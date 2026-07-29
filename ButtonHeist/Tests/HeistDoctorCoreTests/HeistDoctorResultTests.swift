import ButtonHeistTestSupport
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistDoctorResultTests {
    @Test("Doctor derives suggestions from result pair")
    func doctorDerivesSuggestionsFromResultPair() throws {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let lastPass = try result(
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
        let newFail = try result(
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
        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Remove")))
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
    }

    @Test func `doctor repair evidence uses action evidence result meanings`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Pay"))
        let before = makeTestInterface(elements: [
            element(label: "Pay", traits: [.button], actions: [.activate]),
        ])
        let dispatchAfter = makeTestInterface(elements: [
            element(label: "Processing", traits: [.staticText]),
        ])
        let expectationAfter = makeTestInterface(elements: [
            element(label: "Still Processing", traits: [.staticText]),
        ])
        let baseline = doctorSnapshot(interface: before)
        let dispatchSnapshot = doctorSnapshot(interface: dispatchAfter)
        let expectationSnapshot = doctorSnapshot(interface: expectationAfter)
        let observation = Observation.Evidence(
            baseline: baseline,
            current: expectationSnapshot,
            events: [
                .elementsChanged(dispatchSnapshot),
                .elementsChanged(expectationSnapshot),
            ],
            completeness: .incomplete
        )
        let predicate = AccessibilityPredicate.screenChanged
        let failure = HeistFailureDetail(
            category: .expectation,
            contract: "action expectation is met",
            observed: "timed out waiting for checkout",
            expected: predicate.description
        )
        let step = HeistResultFixture.action(
            path: "$.body[0]",
            command: .activate(target),
            result: ActionResult.failure(
                payload: .activate,
                failureKind: .timeout,
                message: "wait timed out",
                observation: .observed(observation)
            ),
            expectation: ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "timed out waiting for checkout"
            ),
            failure: failure
        )

        let repairEvidence = try HeistDoctor.repairEvidence(from: step)

        #expect(repairEvidence.beforeSnapshot == before)
        #expect(repairEvidence.observedChanges == [
            .semanticElementsRemoved,
            .semanticElementsAdded,
            .semanticElementsRemoved,
            .semanticElementsAdded,
        ])
        #expect(repairEvidence.semanticEvidence.contains("Processing"))
        #expect(repairEvidence.semanticEvidence.contains("Still Processing"))
        #expect(repairEvidence.command == .activate(target))
        #expect(repairEvidence.method == .activate)
        #expect(repairEvidence.expectation?.met == false)
        guard case .failed(let failureKind, let message) = repairEvidence.outcome else {
            Issue.record("Expected failed repair evidence")
            return
        }
        #expect(failureKind == .timeout)
        #expect(message == "timed out waiting for checkout")
    }

    @Test func `doctor diagnosis returns typed refusal for valid result pair`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let lastPass = try result(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            after: nil,
            actionSucceeded: true
        )
        let newFail = try result(
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

    private func result(
        path: String,
        status: HeistExecutionStepStatus,
        target: AccessibilityTarget,
        before: Interface,
        after: Interface?,
        actionSucceeded: Bool
    ) throws -> HeistResult {
        let observation = doctorObservationEvidence(before: before, after: after)
        let actionResult = if actionSucceeded {
            ActionResult.success(
                payload: .activate,
                observation: .observed(observation)
            )
        } else {
            ActionResult.failure(
                payload: .activate,
                failureKind: .elementNotFound,
                message: "No element matching \(target)",
                observation: .observed(observation)
            )
        }
        let step = status == .failed
            ? HeistResultFixture.action(
                path: path,
                command: .activate(target),
                result: actionResult,
                failure: HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action dispatch succeeds",
                    observed: "No element matching \(target)",
                    expected: target.description
                )
            )
            : HeistResultFixture.action(
                path: path,
                command: .activate(target),
                result: actionResult
            )
        return try HeistResult(
            steps: [step],
            durationMs: 1
        )
    }
}

private func doctorObservationEvidence(
    before: Interface,
    after: Interface?
) -> Observation.Evidence {
    let baseline = doctorSnapshot(interface: before)
    let current = after.map { doctorSnapshot(interface: $0) } ?? baseline
    return Observation.Evidence(
        baseline: baseline,
        current: current,
        events: after == nil ? [] : [.elementsChanged(current)],
        completeness: .incomplete
    )
}

private func doctorSnapshot(interface: Interface) -> Observation.Snapshot {
    Observation.Snapshot(
        interface: interface,
        context: .empty
    )
}
