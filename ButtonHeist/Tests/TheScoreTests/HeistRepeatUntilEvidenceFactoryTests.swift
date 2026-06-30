import Testing
import ThePlans
import TheScore

@Suite struct HeistRepeatUntilEvidenceFactoryTests {
    @Test func `predicate met evidence requires met expectation`() {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let unmet = ExpectationResult(met: false, predicate: predicate, actual: "not found")

        #expect(HeistRepeatUntilEvidence.predicateMet(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: unmet
        ) == nil)
    }

    @Test func `timed out evidence rejects met expectation`() {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let met = ExpectationResult(met: true, predicate: predicate)

        #expect(HeistRepeatUntilEvidence.timedOut(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: met,
            lastObservedSummary: "Done",
            failureReason: "timed out"
        ) == nil)
    }

    @Test func `continued iteration evidence rejects met expectation`() {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let met = ExpectationResult(met: true, predicate: predicate)

        #expect(HeistRepeatUntilEvidence.continued(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: met
        ) == nil)
    }
}
