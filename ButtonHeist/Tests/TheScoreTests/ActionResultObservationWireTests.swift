import ButtonHeistTestSupport
import XCTest
import TheScore

final class ActionResultObservationWireTests: XCTestCase {
    func testActionResultAccessibilityTraceWireShape() throws {
        let interface = makeTestInterface(
            elements: [
                HeistElement(
                    description: "Submit",
                    label: "Submit",
                    value: nil,
                    identifier: "submit_button",
                    traits: [.button],
                    frameX: 10,
                    frameY: 20,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: [.activate]
                ),
            ]
        )
        let trace = AccessibilityTrace(first: interface).appending(interface)
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))

        )

        let data = try JSONEncoder().encode(result)
        let json = try JSONProbe(data: data)
        let traceEvidence = try json.object("evidence").object("observation").object("traceEvidence")

        XCTAssertEqual(try traceEvidence.string("completeness"), "incomplete")
        _ = try traceEvidence.object("accessibilityTrace")
    }

    func testActionResultHasNoTraceProjectionWithoutTrace() throws {
        let result = ActionResult.success(
            payload: .activate,
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertNil(decoded.accessibilityTrace)
    }

    func testActionResultScreenContextProjectsFromTrace() throws {
        let before = interfaceWithHeader("Before")
        let after = interfaceWithHeader("Trace Screen", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )

        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))

        )

        XCTAssertEqual(result.accessibilityTrace?.endpointScreenName, "Trace Screen")
        XCTAssertEqual(result.accessibilityTrace?.endpointScreenId, "trace_screen")
    }

    func testActionResultScreenContextRoundTripsTraceProjection() throws {
        let before = interfaceWithHeader("Before")
        let after = interfaceWithHeader("Trace Screen", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))

        )

        let data = try JSONEncoder().encode(result)
        let json = try JSONProbe(data: data)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertNoThrow(try json.assertMissing("screenName"))
        XCTAssertNoThrow(try json.assertMissing("screenId"))
        XCTAssertEqual(decoded.accessibilityTrace?.endpointScreenName, "Trace Screen")
        XCTAssertEqual(decoded.accessibilityTrace?.endpointScreenId, "trace_screen")
    }

    func testActionResultScreenContextDoesNotFallbackWhenTraceProjectsNil() throws {
        let before = interfaceWithHeader("Before")
        let trace = AccessibilityTrace(first: before).appending(interfaceWithoutHeader(timestamp: 1))
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))

        )

        XCTAssertNil(result.accessibilityTrace?.endpointScreenName)
        XCTAssertNil(result.accessibilityTrace?.endpointScreenId)
    }

    func testActionResultDecodedScreenContextProjectsFromTrace() throws {
        let before = interfaceWithHeader("Before")
        let after = interfaceWithHeader("Trace Screen", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )
        let data = try JSONEncoder().encode(ActionResult.success(
            payload: .activate,
            observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
        ))

        let result = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(result.accessibilityTrace?.endpointScreenName, "Trace Screen")
        XCTAssertEqual(result.accessibilityTrace?.endpointScreenId, "trace_screen")
    }

    func testActionResultRejectsStoredScreenContextFields() {
        let data = Data(#"{"outcome":{"kind":"success"},"method":"activate","screenName":"stored screen"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("screenName"), "\(error)")
        }
    }
    private func interfaceWithHeader(
        _ label: String,
        timestamp: TimeInterval = 0
    ) -> Interface {
        makeTestInterface(
            elements: [
                HeistElement(
                    description: label,
                    label: label,
                    value: nil,
                    identifier: nil,
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func interfaceWithoutHeader(timestamp: TimeInterval = 0) -> Interface {
        makeTestInterface(
            elements: [
                HeistElement(
                    description: "Continue",
                    label: "Continue",
                    value: nil,
                    identifier: nil,
                    traits: [.button],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
