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
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            predicate: predicate,
            timeout: 1,
            completion: .passed(evidence: evidence)
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
            resolvedPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(current)],
                current: current,
                coverage: .complete
            ),
            terminalCause: .cancelled
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
            resolvedPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [.notification(matching), .notification(later)],
                current: nil,
                coverage: .complete
            ),
            terminalCause: .observed
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
            resolvedPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [],
                current: nil,
                coverage: .incomplete(gap)
            ),
            terminalCause: .observed
        )
        let evidence = HeistActionEvidence.completed(
            result: HeistResultFixture.actionResult(),
            expectation: expectation
        )

        #expect(throws: gap) {
            _ = try evidence.announcement
        }
    }

    @Test func encodedEvidenceContainsFactsAndNoStoredVerdict() throws {
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
            "resolvedPredicate",
            "observation",
            "terminalCause",
        ])
        #expect(object["met"] == nil)
        #expect(object["actual"] == nil)
        #expect(object["expectation"] == nil)
    }

    private func expectationEvidence(
        predicate: AccessibilityPredicate,
        current: Observation.Snapshot,
        coverage: Observation.Coverage = .complete
    ) throws -> HeistExpectationEvidence {
        HeistExpectationEvidence(
            predicate: predicate,
            resolvedPredicate: try predicate.resolve(in: .empty),
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(current)],
                current: current,
                coverage: coverage
            ),
            terminalCause: .observed
        )
    }
}
