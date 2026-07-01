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

        let elseFailed = HeistRepeatUntilEvidence.timeoutElseFailed(
            predicate: predicate,
            timeout: 1,
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "Cart",
            failureReason: "else failed"
        )
        #expect(elseFailed.outcome == .failed)
        #expect(elseFailed.failureReason == "else failed")
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
        var invalidFixture = RepeatUntilEvidenceFixture(evidence)
        invalidFixture.expectation = ExpectationResult(
            met: false,
            predicate: invalidFixture.expectation.predicate,
            actual: invalidFixture.expectation.actual
        )
        let invalidData = try JSONEncoder().encode(invalidFixture)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistRepeatUntilEvidence.self, from: invalidData)
        }
    }
}

private struct RepeatUntilEvidenceFixture: Codable {
    var outcome: HeistPredicateEvidenceOutcome
    var predicate: AccessibilityPredicate
    var timeout: Double
    var iterationCount: Int
    var iterationOrdinal: Int?
    var expectation: ExpectationResult
    var actionResult: ActionResult?
    var lastObservedSummary: String?
    var failureReason: String?

    init(_ evidence: HeistRepeatUntilEvidence) {
        outcome = evidence.outcome
        predicate = evidence.predicate
        timeout = evidence.timeout
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        expectation = evidence.expectation
        actionResult = evidence.actionResult
        lastObservedSummary = evidence.lastObservedSummary
        failureReason = evidence.failureReason
    }
}
