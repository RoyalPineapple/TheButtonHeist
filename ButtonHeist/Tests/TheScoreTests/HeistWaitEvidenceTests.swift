import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
@testable import TheScore

@Suite struct HeistWaitEvidenceTests {
    @Test func decodedRecordingReplaysIdenticallyToLiveEvidence() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let evidence = try expectationEvidence(
            predicate: predicate,
            current: makeTestObservationSnapshot(elements: [
                makeTestHeistElement(label: "Done"),
            ])
        )
        let passedEvidence = try #require(HeistPassedWaitEvidence(evidence))
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            predicate: predicate,
            timeout: 1,
            completion: .passed(
                evidence: passedEvidence
            )
        )
        let result = try HeistResult(steps: [step], durationMs: 1)
        let plan = try HeistPlan(body: [.wait(WaitStep(predicate: predicate))])
        let recording = try HeistResultRecording(result: result, plan: plan)

        let decoded = try HeistResultCodec.decode(HeistResultCodec.encode(recording))
        let decodedEvidence = try #require(decoded.result.steps.first?.waitEvidence)

        #expect(try decodedEvidence.replay() == evidence.replay())
    }

    @Test func completeUnmatchedEvidenceProjectsUnmet() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let evidence = try expectationEvidence(
            predicate: predicate,
            current: makeTestObservationSnapshot(elements: [])
        )

        #expect(try evidence.replay().met == false)
    }

    @Test func deadlineMatchWithoutSettledNoChangeReplaysUnmetAfterDecoding() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .appeared(.label("Done")),
        ])
        let current = makeTestObservationSnapshot(elements: [
            makeTestHeistElement(label: "Done"),
        ])
        let evidence = HeistExpectationEvidence(
            predicate: predicate,
            boundPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: makeTestObservationSnapshot(elements: []),
                events: [.elementsChanged(current)],
                current: current,
                coverage: .complete
            ),
            terminalCause: .deadline,
            timing: HeistResultFixture.expectationTiming
        )
        let decoded = try JSONDecoder().decode(
            HeistExpectationEvidence.self,
            from: JSONEncoder().encode(evidence)
        )

        #expect(try evidence.replay().met == false)
        #expect(try decoded.replay().met == false)
        #expect(try decoded.replay().actual == ObservationPredicate.noChange.description)
    }

    @Test func incompleteUnresolvedEvidenceThrowsItsGap() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let sequenceGap = Observation.NotificationSequenceGap(
            afterSequence: 7,
            throughSequence: 9
        )
        let gap = Observation.Gap.notificationIngress(sequenceGap, additional: [])
        let evidence = try expectationEvidence(
            predicate: predicate,
            current: makeTestObservationSnapshot(elements: []),
            coverage: .incomplete(gap)
        )

        #expect(throws: gap) {
            _ = try evidence.replay()
        }
    }

    @Test func incompleteMatchedEvidenceThrowsItsGap() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let gap = Observation.Gap.captureUnavailable
        let evidence = try expectationEvidence(
            predicate: predicate,
            current: makeTestObservationSnapshot(elements: [
                makeTestHeistElement(label: "Done"),
            ]),
            coverage: .incomplete(gap)
        )

        #expect(throws: gap) {
            _ = try evidence.replay()
        }
    }

    @Test func reportProjectionPreservesIncompleteCoverageGap() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let sequenceGap = Observation.NotificationSequenceGap(
            afterSequence: 7,
            throughSequence: 9
        )
        let gap = Observation.Gap.notificationIngress(sequenceGap, additional: [])
        let evidence = try expectationEvidence(
            predicate: predicate,
            current: makeTestObservationSnapshot(elements: []),
            coverage: .incomplete(gap)
        )
        let result = HeistResultFixture.result(steps: [
            HeistResultFixture.failedWait(
                evidence: evidence,
                failure: HeistFailureDetail(
                    category: .timeout,
                    contract: "wait predicate is met",
                    observed: "deadline expired"
                )
            ),
        ])

        #expect(throws: gap) {
            _ = try HeistReport.project(result: result)
        }
    }

    @Test func cancelledTerminalCauseCannotReplayAsMatched() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let current = makeTestObservationSnapshot(elements: [
            makeTestHeistElement(label: "Done"),
        ])
        let evidence = HeistExpectationEvidence(
            predicate: predicate,
            boundPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(current)],
                current: current,
                coverage: .complete
            ),
            terminalCause: .cancelled,
            timing: HeistResultFixture.expectationTiming
        )

        let replay = try evidence.replay()

        #expect(replay.met == false)
        #expect(replay.actual == "terminal cause: cancelled")
    }

    @Test func notificationReplayUsesTheMatchingOrderedEvent() throws {
        let predicate = AccessibilityPredicate.notification("Saved")
        let matching = try #require(Observation.Notification(text: "Saved", element: nil))
        let later = try #require(Observation.Notification(text: "Unrelated", element: nil))
        let evidence = HeistExpectationEvidence(
            predicate: predicate,
            boundPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [.notification(matching), .notification(later), .noChange],
                current: nil,
                coverage: .complete
            ),
            terminalCause: .observed,
            timing: HeistResultFixture.expectationTiming
        )

        let replay = try evidence.replay()

        #expect(replay.met)
        #expect(replay.actual == "Saved")
    }

    @Test func announcementProjectionPreservesIncompleteCoverageGap() throws {
        let predicate = AccessibilityPredicate.notification("Saved")
        let sequenceGap = Observation.NotificationSequenceGap(
            afterSequence: 7,
            throughSequence: 9
        )
        let gap = Observation.Gap.notificationIngress(sequenceGap, additional: [])
        let expectation = HeistExpectationEvidence(
            predicate: predicate,
            boundPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [],
                current: nil,
                coverage: .incomplete(gap)
            ),
            terminalCause: .observed,
            timing: HeistResultFixture.expectationTiming
        )
        let evidence = HeistActionEvidence.completed(
            result: HeistResultFixture.actionResult(),
            expectation: expectation
        )

        #expect(throws: gap) {
            _ = try evidence.announcement
        }
    }

    @Test func encodedEvidenceContainsOneBoundPredicateAndNoStoredVerdict() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let evidence = try expectationEvidence(
            predicate: predicate,
            current: makeTestObservationSnapshot(elements: [])
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence))
                as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "predicate",
            "boundPredicate",
            "observation",
            "terminalCause",
            "timing",
        ])
        #expect(object["met"] == nil)
        #expect(object["actual"] == nil)
        #expect(object["expectation"] == nil)
    }

    @Test func boundPredicatePreservesResolvedReferenceAcrossWire() throws {
        let reference: HeistReferenceName = "label"
        let predicate = AccessibilityPredicate.exists(
            .predicate(.label(.exact(reference)))
        )
        let boundPredicate = try AccessibilityPredicate
            .exists(.label("Done"))
            .resolve(in: .empty)
        let current = makeTestObservationSnapshot(elements: [
            makeTestHeistElement(label: "Done"),
        ])
        let evidence = HeistExpectationEvidence(
            predicate: predicate,
            boundPredicate: boundPredicate,
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(current), .noChange],
                current: current,
                coverage: .complete
            ),
            terminalCause: .observed,
            timing: HeistResultFixture.expectationTiming
        )
        let decoded = try JSONDecoder().decode(
            HeistExpectationEvidence.self,
            from: JSONEncoder().encode(evidence)
        )

        #expect(try decoded.replay().met)
        #expect(decoded.predicate == predicate)
    }

    private func expectationEvidence(
        predicate: AccessibilityPredicate,
        current: Observation.Snapshot,
        coverage: Observation.Coverage = .complete
    ) throws -> HeistExpectationEvidence {
        HeistExpectationEvidence(
            predicate: predicate,
            boundPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(current), .noChange],
                current: current,
                coverage: coverage
            ),
            terminalCause: .observed,
            timing: HeistResultFixture.expectationTiming
        )
    }
}
