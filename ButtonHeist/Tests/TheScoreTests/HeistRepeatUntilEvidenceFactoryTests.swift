import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistRepeatUntilEvidenceFactoryTests {
    @Test func `expectation result converts to typed predicate checks`() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let met = ExpectationResult(met: true, predicate: predicate)
        let unmet = ExpectationResult(met: false, predicate: predicate, actual: "not found")

        switch PredicateExpectationCheck(met) {
        case .met(let expectation):
            #expect(expectation.result == met)
        case .unmet:
            Issue.record("Expected met predicate check")
        }

        switch PredicateExpectationCheck(unmet) {
        case .met:
            Issue.record("Expected unmet predicate check")
        case .unmet(let expectation):
            #expect(expectation.result == unmet)
        }

        #expect(MetExpectationResult(unmet) == nil)
        #expect(UnmetExpectationResult(met) == nil)
        let convertedMet = try #require(MetExpectationResult(met))
        let convertedUnmet = try #require(UnmetExpectationResult(unmet))
        #expect(convertedMet.result == met)
        #expect(convertedUnmet.result == unmet)
    }

    @Test func `terminal evidence factories return evidence for typed polarity`() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let met = try #require(MetExpectationResult(ExpectationResult(met: true, predicate: predicate)))
        let unmet = try #require(UnmetExpectationResult(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "not found"
        )))

        let predicateMet = HeistRepeatUntilEvidence.predicateMet(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: met
        )
        #expect(predicateMet.outcome == .matched)
        #expect(predicateMet.expectation.met)

        let timedOut = HeistRepeatUntilEvidence.timedOut(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "Cart",
            failureReason: "timed out"
        )
        #expect(timedOut.outcome == .failed)
        #expect(!timedOut.expectation.met)

        let bodyFailed = HeistRepeatUntilEvidence.bodyFailed(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "Cart",
            failureReason: "body failed"
        )
        #expect(bodyFailed.outcome == .failed)

        let unavailable = HeistRepeatUntilEvidence.initialObservationUnavailable(
            predicate: predicate,
            timeout: 1,
            expectation: unmet,
            lastObservedSummary: nil,
            failureReason: "unavailable"
        )
        #expect(unavailable.outcome == .failed)

        let handledElse = HeistRepeatUntilEvidence.timeoutHandledByElse(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "Cart"
        )
        #expect(handledElse.outcome == .handledElse)
    }

    @Test func `iteration evidence factories return evidence for typed polarity`() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let met = try #require(MetExpectationResult(ExpectationResult(met: true, predicate: predicate)))
        let unmet = try #require(UnmetExpectationResult(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "not found"
        )))

        let predicateMet = HeistRepeatUntilEvidence.predicateMet(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: met
        )
        #expect(predicateMet.outcome == .matched)
        #expect(predicateMet.iterationOrdinal == 0)

        let continued = HeistRepeatUntilEvidence.continued(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: unmet
        )
        #expect(continued.outcome == .continued)
        #expect(continued.iterationOrdinal == 0)

        let failed = HeistRepeatUntilEvidence.failedIteration(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: unmet,
            lastObservedSummary: "Cart",
            failureReason: "child failed"
        )
        #expect(failed.outcome == .failed)
        #expect(failed.iterationOrdinal == 0)
    }

    @Test func `decode rejects invalid repeat until polarity at boundary`() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let evidence = HeistRepeatUntilEvidence.predicateMet(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: MetExpectationResult(predicate: predicate)
        )
        let data = try JSONEncoder().encode(evidence)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var expectation = try #require(object["expectation"] as? [String: Any])
        expectation["met"] = false
        object["expectation"] = expectation
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistRepeatUntilEvidence.self, from: invalidData)
        }
    }
}
