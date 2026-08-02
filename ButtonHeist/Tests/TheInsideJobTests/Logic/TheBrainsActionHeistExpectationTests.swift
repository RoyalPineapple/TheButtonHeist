#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistExecutionExpectationTests: XCTestCase {
    func testOneEventCannotSatisfyBothTemporalLegs() throws {
        let predicate = try AccessibilityPredicate.elementsChanged([
            .updated(.label("Total"), .value()),
        ]).resolve(in: .empty)
        let first = Observation.Event.elementsChanged(totalSnapshot(value: "$1"))

        let afterFirst = Expectation([predicate]).evaluating(first)

        XCTAssertNotEqual(afterFirst.result, .satisfied)
        XCTAssertEqual(
            afterFirst.evaluating(.elementsChanged(totalSnapshot(value: "$2"))).result,
            .satisfied
        )
    }

    func testHistoryReplayProducesSameExpectationAtEveryPrefix() throws {
        let predicate = try AccessibilityPredicate.elementsChanged([
            .appeared(.label("Ready")),
        ]).resolve(in: .empty)
        let events: [Observation.Event] = [
            .elementsChanged(makeTestObservationSnapshot(labels: [])),
            .elementsChanged(makeTestObservationSnapshot(labels: ["Ready"])),
            .noChange,
        ]
        var history = Observation.History(retentionLimit: 16)
        var live = Expectation([predicate])

        for event in events {
            _ = history.record([event], protectedBy: nil)
            live = live.evaluating(event)
            let replayed = Expectation([predicate], events: Array(history))
            XCTAssertEqual(replayed, live)
        }
        XCTAssertEqual(live.result, .satisfied)
    }

    func testActionRequiresTerminalNoChangeAfterAuthoredMatchWhenEarlyNoChangeArrivesFirst() throws {
        let missing = makeTestObservationSnapshot(labels: ["Submit"])
        let ready = makeTestObservationSnapshot(labels: ["Submit", "Ready"])
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .dismiss,
                expectationPolicy: .expect(ActionExpectation(
                    predicate: .elementsChanged([
                        .appeared(.label("Ready")),
                    ]),
                    timeout: 1
                ))
            )),
        ])
        var driver = try HeistExecutionTestDriver(
            plan: plan,
            script: ExecutionRunScript(
                snapshots: [missing],
                events: [
                    .noChange,
                    .elementsChanged(ready),
                    .noChange,
                ]
            )
        )

        let completion = try driver.run()
        let action = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(action.status, .passed)
        XCTAssertEqual(Array(driver.history), [
            .noChange,
            .elementsChanged(ready),
            .noChange,
        ])
        XCTAssertEqual(
            action.actionEvidence?.result?.observationEvidence?.coverage,
            .complete
        )
    }

    func testActionElementTransitionWithoutWatchTargetObservesWithoutExploring() throws {
        let initial = makeTestObservationSnapshot(labels: ["Submit"])
        let processingStarted = makeTestObservationSnapshot(labels: ["Processing", "Submit"])
        let processing = makeTestObservationSnapshot(labels: ["Processing"])
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .dismiss,
                expectationPolicy: .expect(ActionExpectation(
                    predicate: .elementsChanged([
                        .appeared(.label("Processing")),
                        .disappeared(.label("Submit")),
                    ]),
                    timeout: 1
                ))
            )),
        ])
        var driver = try HeistExecutionTestDriver(
            plan: plan,
            script: ExecutionRunScript(
                snapshots: [initial],
                events: [
                    .elementsChanged(processingStarted),
                    .elementsChanged(processing),
                    .noChange,
                ]
            )
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.first?.status, .passed)
        XCTAssertFalse(driver.requests.contains { request in
            guard case .explore = request else { return false }
            return true
        })
    }

    func testNotificationExpectationConsumesOnlyMatchingNotificationEvent() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification("Saved"),
                timeout: try .seconds(1)
            )),
        ])
        var driver = try HeistExecutionTestDriver(
            plan: plan,
            script: ExecutionRunScript(events: [
                heistNotification("Saving"),
                heistNotification("Saved"),
                .noChange,
            ])
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.first?.status, .passed)
        XCTAssertEqual(
            completion.steps.first?.waitObservation?.notificationTexts,
            ["Saving", "Saved"]
        )
    }

    func testWaitRequiresTerminalNoChangeAfterMatchingEventWhenEarlyNoChangeArrivesFirst() throws {
        let events: [Observation.Event] = [
            .noChange,
            heistNotification("Saved"),
            .noChange,
        ]
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification("Saved"),
                timeout: try .seconds(1)
            )),
        ])
        var driver = try HeistExecutionTestDriver(
            plan: plan,
            script: ExecutionRunScript(events: events)
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.first?.status, .passed)
        XCTAssertEqual(Array(driver.history), events)
    }

    func testProvenCloseSampleRejectsStaleSampleAndSurvivesLateCommit() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification("Saved"),
                timeout: try .seconds(1)
            )),
        ])
        var execution = try HeistExecution(plan: plan)
        let now = ContinuousClock.now
        guard case .perform(.beginObservation(let observationID, _, _)) = execution.start(
            at: now,
            timeout: .default
        ),
              case .wait(let matchedWait) = execution.reduce(
                  .observationBegan(observationID, baseline: nil, at: now)
              ),
              case .wait(let settledWait) = execution.reduce(
                  .observation(matchedWait.id, heistNotification("Saved"), at: now)
              ),
              case .perform(.sampleObservationClose(let firstCloseID, let firstObservationID, _, _, _)) = execution.reduce(
                  .observation(settledWait.id, .noChange, at: now)
              ), firstObservationID == observationID else {
            return XCTFail("A settled wait must request its first close sample")
        }

        let lateChange = Observation.Event.elementsChanged(
            makeTestObservationSnapshot(labels: ["Late Change"])
        )
        let unprovenEvidence = Observation.Evidence(
            baseline: nil,
            events: [heistNotification("Saved"), lateChange],
            current: makeTestObservationSnapshot(labels: ["Late Change"]),
            coverage: .complete
        )
        guard case .perform(.sampleObservationClose(let refreshedCloseID, let refreshedObservationID, _, _, _)) = execution.reduce(
            .observationCloseSampled(
                firstCloseID,
                source: .request,
                observationID: observationID,
                evidence: unprovenEvidence,
                close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
                at: now
            )
        ), refreshedObservationID == observationID,
           refreshedCloseID != firstCloseID else {
            return XCTFail("An unproven close sample must request fresh evidence")
        }

        guard case .perform(.sampleObservationClose(let retainedCloseID, _, _, _, _)) = execution.reduce(
            .observationCloseSampled(
                firstCloseID,
                source: .request,
                observationID: observationID,
                evidence: unprovenEvidence,
                close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
                at: now
            )
        ), retainedCloseID == refreshedCloseID else {
            return XCTFail("A stale close sample must not replace the refreshed request")
        }

        let provenEvidence = Observation.Evidence(
            baseline: nil,
            events: [heistNotification("Saved"), lateChange, .noChange],
            current: makeTestObservationSnapshot(labels: ["Late Change"]),
            coverage: .complete
        )
        guard case .perform(.commitObservationClose(let commitID, let committedObservationID)) = execution.reduce(
            .observationCloseSampled(
                refreshedCloseID,
                source: .request,
                observationID: observationID,
                evidence: provenEvidence,
                close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
                at: now.advanced(by: .seconds(2))
            )
        ), committedObservationID == observationID,
           case .complete(let completion) = execution.reduce(
               .observationCloseCommitted(commitID, at: now.advanced(by: .seconds(3)))
           ) else {
            return XCTFail("The proven sample must remain complete while its close commit finishes")
        }
        XCTAssertEqual(completion.steps.first?.status, .passed)
    }

    func testIncompleteHistoryCannotManufactureSuccessfulEvidence() throws {
        var history = Observation.History(retentionLimit: 1)
        let baseline = makeTestObservationSnapshot(labels: ["Before"])
        let current = makeTestObservationSnapshot(labels: ["After"])
        let protectedRange = history.record(
            [.elementsChanged(baseline)],
            protectedBy: nil
        )
        _ = history.record([.elementsChanged(current)], protectedBy: nil)

        let evidence = history.evidence(
            in: protectedRange,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(evidence.coverage, .incomplete(.historyUnavailable))
        XCTAssertTrue(evidence.events.isEmpty)
    }
}

private extension HeistExecutionExpectationTests {
    func totalSnapshot(value: String) -> Observation.Snapshot {
        makeTestObservationSnapshot(nodes: [
            .parsedElement(
                AccessibilityElement.make(label: "Total", value: value),
                actions: []
            ),
        ])
    }
}

#endif // canImport(UIKit)
