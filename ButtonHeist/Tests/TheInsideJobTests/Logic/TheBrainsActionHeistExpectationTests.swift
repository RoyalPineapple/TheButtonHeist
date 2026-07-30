#if canImport(UIKit)
import ButtonHeistTestSupport
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

    func testActionExpectationConsumesHistoryAfterDispatch() throws {
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
        guard case .perform(let beginRequest) = machine.start(),
              case .beginObservation(let id, _) = beginRequest else {
            return XCTFail("The wait must begin one observation")
        }
        let baseline = makeTestObservationSnapshot(labels: [])
        guard case .wait = machine.advance(
            .observationBegan(id, baseline: baseline)
        ),
              case .wait = machine.advance(.event(heistNotification("Saved"))),
              case .perform(let firstFinish) = machine.advance(.event(.noChange)),
              case .finishObservation(
                let firstFinishID,
                let firstObservationID,
                _
              ) = firstFinish else {
            return XCTFail("A matched, unchanged wait must request final evidence")
        }
        XCTAssertEqual(firstObservationID, id)
        XCTAssertTrue(
            machine.activeLeaf?.admits(.request(firstFinishID)) == true
        )

        guard case .wait = machine.advance(
            .event(.elementsChanged(makeTestObservationSnapshot(labels: ["Late Change"])))
        ) else {
            return XCTFail("A final-capture change must reopen observation")
        }
        XCTAssertNil(machine.activeLeaf?.finishingObservationRequestID)
        XCTAssertFalse(
            machine.activeLeaf?.admits(.request(firstFinishID)) == true
        )

        guard case .perform(let secondFinish) = machine.advance(
            .event(.noChange)
        ),
              case .finishObservation(
                let secondFinishID,
                let secondObservationID,
                _
              ) = secondFinish else {
            return XCTFail("Fresh stillness must request final evidence again")
        }
        XCTAssertEqual(secondObservationID, id)
        XCTAssertNotEqual(secondFinishID, firstFinishID)
        XCTAssertFalse(
            machine.activeLeaf?.admits(.request(firstFinishID)) == true
        )
        XCTAssertTrue(
            machine.activeLeaf?.admits(.request(secondFinishID)) == true
        )

        let lateChange = makeTestObservationSnapshot(labels: ["Late Change"])
        let events: [Observation.Event] = [
            heistNotification("Saved"),
            .noChange,
            .elementsChanged(lateChange),
            .noChange,
        ]
        var history = Observation.History(retentionLimit: events.count)
        let recorded = history.record(events, protectedBy: nil)
        let evidence = history.evidence(
            in: recorded,
            baseline: baseline,
            current: lateChange
        )
        guard case .wait = machine.advance(.observationFinished(
            source: .request(firstFinishID),
            observationID: id,
            evidence: evidence,
            outcome: .completed,
            timing: HeistResultFixture.expectationTiming
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
                outcome: .completed,
                timing: HeistResultFixture.expectationTiming
            )
        ) else {
            return XCTFail("Satisfied final evidence at the deadline must complete")
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

private extension HeistMachineExpectationTests {
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
