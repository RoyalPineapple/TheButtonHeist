import ButtonHeistTestSupport
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistDoctorEvidenceEligibilityTests {
    @Test func `container-only targets are refused without element coercion`() {
        let target = AccessibilityTarget.container(.label("Checkout"))
        let interface = makeTestInterface(elements: [
            element(label: "Checkout", traits: [.button], actions: [.activate]),
        ])
        let request = request(
            passedEvidence(target: target, before: interface),
            failedEvidence(target: target, before: interface)
        )

        guard case .refused(let diagnosis) = HeistDoctor.diagnosis(for: request) else {
            Issue.record("Expected container-only target refusal")
            return
        }

        #expect(diagnosis.refusal.stage == .evidenceEligibility)
        #expect(diagnosis.refusal.reason == .containerTargetUnsupported)
        #expect(diagnosis.refusal.message == "container-only targets are not repairable as accessibility elements")
    }

    @Test("Last success must resolve exactly once")
    func lastSuccessMustResolveExactlyOnce() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ])
        )

        #expect(HeistDoctor.diagnosis(for: request(last, current)).suggestions.isEmpty)
    }

    @Test("Last success missing target returns no suggestion")
    func lastSuccessMissingTargetReturnsNoSuggestion() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Archive", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ])
        )

        #expect(HeistDoctor.diagnosis(for: request(last, current)).suggestions.isEmpty)
    }

    @Test("Evidence must belong to the same failing step")
    func evidenceMustBelongToTheSameFailingStep() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let last = passedEvidence(
            stepPath: "$.body[0]",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            stepPath: "$.body[1]",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ])
        )

        #expect(HeistDoctor.diagnosis(for: request(last, current)).suggestions.isEmpty)
    }

    @Test("Incompatible heist fingerprints return no suggestion")
    func incompatibleHeistFingerprintsReturnNoSuggestion() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let last = passedEvidence(
            heistFingerprint: "last-plan",
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ])
        )
        let current = failedEvidence(
            heistFingerprint: "different-plan",
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ])
        )

        #expect(HeistDoctor.diagnosis(for: request(last, current)).suggestions.isEmpty)
    }

    @Test("Current target that still resolves needs no target repair")
    func currentTargetThatStillResolvesNeedsNoTargetRepair() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let before = listInterface(rows: [
            ("Milk", "Delete"),
        ])
        let last = passedEvidence(
            target: target,
            before: before
        )
        let current = failedEvidence(
            target: target,
            before: before,
            expectation: ExpectationResult(met: false, predicate: nil, actual: "Expected item count to change")
        )

        #expect(HeistDoctor.diagnosis(for: request(last, current)).suggestions.isEmpty)
    }

    @Test("No suggestion reason reports no target repair needed")
    func noSuggestionReasonReportsNoTargetRepairNeeded() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let before = listInterface(rows: [
            ("Milk", "Delete"),
        ])
        let last = passedEvidence(
            target: target,
            before: before
        )
        let current = failedEvidence(
            target: target,
            before: before
        )

        let reason = HeistDoctor.diagnosis(for: request(last, current)).noSuggestionReason

        #expect(reason == "old target still resolves and supports the requested action; no target repair needed")
    }

    @Test("No suggestion reason reports missing target without a safe successor")
    func noSuggestionReasonReportsMissingTargetWithoutASafeSuccessor() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ])
        )

        let reason = HeistDoctor.diagnosis(for: request(last, current)).noSuggestionReason
        let expectedReason = "old target is missing in the current before snapshot; "
            + "no safe successor satisfied semantic continuity and unique-matcher requirements"

        #expect(reason == expectedReason)
    }
}
