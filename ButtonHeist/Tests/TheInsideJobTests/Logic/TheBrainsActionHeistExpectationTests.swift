#if canImport(UIKit)
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistMachineExpectationTests: XCTestCase {
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
            .elementsChanged(heistSnapshot(labels: [])),
            .elementsChanged(heistSnapshot(labels: ["Ready"])),
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

    func testActionExpectationConsumesHistoryAfterDispatch() throws {
        let missing = heistSnapshot(labels: ["Submit"])
        let ready = heistSnapshot(labels: ["Submit", "Ready"])
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
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
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
        let initial = heistSnapshot(labels: ["Submit"])
        let processingStarted = heistSnapshot(labels: ["Processing", "Submit"])
        let processing = heistSnapshot(labels: ["Processing"])
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
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
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
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(events: [
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

    func testWaitRequiresNoChangeAfterMatchingEvent() throws {
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
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(events: events)
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.first?.status, .passed)
        XCTAssertEqual(Array(driver.history), events)
    }

    func testSubstantiveEventDuringFinalCaptureReopensObservation() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .notification("Saved"),
                timeout: try .seconds(1)
            )),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        guard case .pending(.perform(let beginRequests)) = machine.start(),
              beginRequests.count == 1,
              case .beginObservation(let id, _) = beginRequests[0] else {
            return XCTFail("The wait must begin one observation")
        }
        let baseline = heistSnapshot(labels: [])
        guard case .pending(.wait) = machine.advance(
            .observationBegan(id, baseline: baseline)
        ),
              case .pending(.wait) = machine.advance(.event(heistNotification("Saved"))),
              case .pending(.perform(let firstFinish)) = machine.advance(.event(.noChange)),
              firstFinish.count == 1,
              case .finishObservation(
                let firstFinishID,
                let firstObservationID,
                _
              ) = firstFinish[0] else {
            return XCTFail("A matched, unchanged wait must request final evidence")
        }
        XCTAssertEqual(firstObservationID, id)

        guard case .pending(.wait) = machine.advance(
            .event(.elementsChanged(heistSnapshot(labels: ["Late Change"])))
        ) else {
            return XCTFail("A final-capture change must reopen observation")
        }
        XCTAssertNil(machine.activeLeaf?.finishingObservationRequestID)

        guard case .pending(.perform(let secondFinish)) = machine.advance(
            .event(.noChange)
        ),
              secondFinish.count == 1,
              case .finishObservation(
                let secondFinishID,
                let secondObservationID,
                _
              ) = secondFinish[0] else {
            return XCTFail("Fresh stillness must request final evidence again")
        }
        XCTAssertEqual(secondObservationID, id)
        XCTAssertNotEqual(secondFinishID, firstFinishID)

        let evidence = Observation.History(retentionLimit: 1).evidence(
            in: 0..<0,
            baseline: baseline,
            current: baseline
        )
        guard case .pending(.wait) = machine.advance(.observationFinished(
            source: .request(firstFinishID),
            observationID: id,
            evidence: evidence,
            outcome: .completed
        )) else {
            return XCTFail("A superseded final-capture response must be ignored")
        }
        XCTAssertEqual(
            machine.activeLeaf?.finishingObservationRequestID,
            secondFinishID
        )

        guard case .complete(let completion) = machine.advance(
            .observationFinished(
                source: .deadline,
                observationID: id,
                evidence: evidence,
                outcome: .completed
            )
        ) else {
            return XCTFail("Satisfied final evidence at the deadline must complete")
        }
        XCTAssertEqual(completion.steps.first?.status, .passed)
    }

    func testIncompleteHistoryCannotManufactureSuccessfulEvidence() throws {
        var history = Observation.History(retentionLimit: 1)
        let baseline = heistSnapshot(labels: ["Before"])
        let current = heistSnapshot(labels: ["After"])
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

private extension HeistMachineExpectationTests {
    func totalSnapshot(value: String) -> Observation.Snapshot {
        heistSnapshot(elements: [
            AccessibilityElement.make(label: "Total", value: value),
        ])
    }
}

#endif // canImport(UIKit)
