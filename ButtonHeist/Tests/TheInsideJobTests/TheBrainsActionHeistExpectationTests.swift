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
            action.actionEvidence?.result?.observationEvidence?.completeness,
            .complete
        )
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

        XCTAssertEqual(evidence.completeness, .incomplete)
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
