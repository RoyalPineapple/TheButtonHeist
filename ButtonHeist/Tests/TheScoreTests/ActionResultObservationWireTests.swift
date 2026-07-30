import ButtonHeistTestSupport
import XCTest
import TheScore

final class ActionResultObservationWireTests: XCTestCase {
    func testObservedEvidenceUsesCanonicalWireShape() throws {
        let snapshot = makeTestObservationSnapshot(elements: [
            makeTestHeistElement(
                description: "Submit",
                label: "Submit",
                identifier: "submit_button",
                traits: [.button],
                actions: [.activate]
            ),
        ])
        let evidence = makeTestObservationEvidence(
            current: snapshot,
            events: [.elementsChanged(snapshot)],
            coverage: .incomplete(.historyUnavailable)
        )
        let result = ActionResult.success(
            payload: .activate,
            observation: .observed(evidence)
        )

        let json = try JSONProbe(data: JSONEncoder().encode(result))
        let observation = try json.object("evidence").object("observation")
        let encodedEvidence = try observation.object("observationEvidence")

        XCTAssertEqual(try observation.string("kind"), "observed")
        _ = try encodedEvidence
            .object("coverage")
            .object("incomplete")
            .object("_0")
            .object("historyUnavailable")
        _ = try encodedEvidence.object("current")
        _ = try encodedEvidence.array("events")
    }

    func testActionResultHasNoObservationProjectionWithoutEvidence() throws {
        let result = ActionResult.success(payload: .activate)

        let decoded = try JSONDecoder().decode(
            ActionResult.self,
            from: JSONEncoder().encode(result)
        )

        XCTAssertNil(decoded.observationEvidence)
    }

    func testCurrentScreenContextRoundTripsThroughObservationEvidence() throws {
        let current = Observation.Snapshot(
            interface: interfaceWithHeader("Current Screen", timestamp: 1),
            context: Observation.Context(screenId: "current_screen")
        )
        let evidence = makeTestObservationEvidence(
            current: current,
            events: [.elementsChanged(current)],
            coverage: .incomplete(.historyUnavailable)
        )
        let result = ActionResult.success(
            payload: .activate,
            observation: .observed(evidence)
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(decoded.observationEvidence?.current, current)
        XCTAssertEqual(decoded.observationEvidence?.current?.context.screenId, "current_screen")
    }

    private func interfaceWithHeader(
        _ label: String,
        timestamp: TimeInterval
    ) -> Interface {
        makeTestInterface(
            elements: [
                makeTestHeistElement(
                    description: label,
                    label: label,
                    traits: [.header],
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
