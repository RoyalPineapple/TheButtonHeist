import XCTest
@testable import ButtonHeist
import TheScore

final class ElementActionRequestPayloadTests: XCTestCase {

    @ButtonHeistActor
    func testActivateRequestDecodesTypedActionAndCount() async throws {
        let payload = try parsedPayload(.activate, request: [
            "command": "activate",
            "identifier": "counter",
            "action": "increment",
            "count": 2,
        ])

        guard case .accessibility(.activate(let target, let actionName, let count)) = payload else {
            return XCTFail("Expected activate accessibility payload")
        }
        assertMatcherTarget(target, identifier: "counter")
        XCTAssertEqual(actionName, "increment")
        XCTAssertEqual(count.value, 2)
    }

    @ButtonHeistActor
    func testAdjustmentRequestsDecodeTypedCounts() async throws {
        let increment = try parsedPayload(.increment, request: [
            "command": "increment",
            "label": "Quantity",
            "count": 3,
        ])
        guard case .accessibility(.increment(let incrementTarget, let incrementCount)) = increment else {
            return XCTFail("Expected increment accessibility payload")
        }
        assertMatcherTarget(incrementTarget, label: "Quantity")
        XCTAssertEqual(incrementCount.value, 3)

        let decrement = try parsedPayload(.decrement, request: [
            "command": "decrement",
            "label": "Quantity",
            "count": 2,
        ])
        guard case .accessibility(.decrement(let decrementTarget, let decrementCount)) = decrement else {
            return XCTFail("Expected decrement accessibility payload")
        }
        assertMatcherTarget(decrementTarget, label: "Quantity")
        XCTAssertEqual(decrementCount.value, 2)
    }

    @ButtonHeistActor
    func testCustomActionRequestDecodesTypedAction() async throws {
        let payload = try parsedPayload(.performCustomAction, request: [
            "command": "perform_custom_action",
            "heistId": "card",
            "action": "Dismiss",
        ])

        guard case .accessibility(.performCustomAction(let target, let actionName, let count)) = payload else {
            return XCTFail("Expected perform_custom_action accessibility payload")
        }
        XCTAssertEqual(target, .heistId("card"))
        XCTAssertEqual(actionName, "Dismiss")
        XCTAssertNil(count.value)
    }

    @ButtonHeistActor
    func testRotorRequestDecodesFlatCursorShape() async throws {
        let payload = try parsedPayload(.rotor, request: [
            "command": "rotor",
            "label": "Body",
            "rotor": "Headings",
            "rotorIndex": 1,
            "direction": "previous",
            "currentHeistId": "body-current",
            "currentTextStartOffset": 4,
            "currentTextEndOffset": 10,
        ])

        guard case .rotor(let target) = payload else {
            return XCTFail("Expected rotor payload")
        }
        assertMatcherTarget(target.elementTarget, label: "Body")
        XCTAssertEqual(target.rotor, "Headings")
        XCTAssertEqual(target.rotorIndex, 1)
        XCTAssertEqual(target.direction, .previous)
        XCTAssertEqual(target.currentHeistId, "body-current")
        XCTAssertEqual(target.currentTextRange, TextRangeReference(startOffset: 4, endOffset: 10))
    }

    @ButtonHeistActor
    func testTypeTextRequestDecodesFlatTextAndOptionalTarget() async throws {
        let payload = try parsedPayload(.typeText, request: [
            "command": "type_text",
            "identifier": "note",
            "text": "hello",
        ])

        guard case .typeText(let target) = payload else {
            return XCTFail("Expected type_text payload")
        }
        XCTAssertEqual(target.text, "hello")
        guard let elementTarget = target.elementTarget else {
            return XCTFail("Expected element target")
        }
        assertMatcherTarget(elementTarget, identifier: "note")
    }

    @ButtonHeistActor
    func testActivateMissingTargetKeepsContractDiagnostics() async throws {
        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(request: ["command": "activate"])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected error response")
        }
        XCTAssertTrue(message.contains("activate request contract failed: missing target"))
        XCTAssertTrue(message.contains("Next: get_interface()"))
        XCTAssertEqual(details?.errorCode, "request.missing_target")
        XCTAssertEqual(details?.phase, .request)
        XCTAssertEqual(details?.retryable, false)
        XCTAssertEqual(details?.hint, "get_interface()")
    }

    @ButtonHeistActor
    func testTypeTextEmptyStringKeepsObservedValueDiagnostic() async {
        assertParseError(
            .typeText,
            request: ["command": "type_text", "text": ""],
            equals: "schema validation failed for text: observed string \"\"; expected non-empty string"
        )
    }

    @ButtonHeistActor
    func testAdjustmentCountRangeDiagnosticKeepsObservedValue() async {
        await assertExecutionError(
            ["command": "activate", "identifier": "counter", "action": "increment", "count": 0],
            contains: "schema validation failed for count: observed integer 0; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testCustomActionMissingActionDiagnostic() async {
        assertParseError(
            .performCustomAction,
            request: ["command": "perform_custom_action", "identifier": "card"],
            equals: "schema validation failed for action: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testRotorInvalidTextRangeDiagnosticKeepsObservedRange() async {
        assertParseError(
            .rotor,
            request: [
                "command": "rotor",
                "identifier": "body",
                "currentHeistId": "body-current",
                "currentTextStartOffset": 10,
                "currentTextEndOffset": 4,
            ],
            equals: "schema validation failed for currentTextStartOffset/currentTextEndOffset: " +
                "observed 10..<4; expected integer range with start >= 0 and end >= start"
        )
    }

    @ButtonHeistActor
    private func parsedPayload(
        _ command: TheFence.Command,
        request: [String: Any]
    ) throws -> TheFence.RequestPayload {
        try TheFence(configuration: .init()).parseRequest(command: command, request: request).payload
    }

    @ButtonHeistActor
    private func assertParseError(
        _ command: TheFence.Command,
        request: [String: Any],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try TheFence(configuration: .init()).parseRequest(command: command, request: request),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error.localizedDescription, expected, file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertExecutionError(
        _ request: [String: Any],
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: request)
            guard case .error(let message, _) = response else {
                return XCTFail("Expected error response", file: file, line: line)
            }
            XCTAssertTrue(
                message.contains(expected),
                "Expected error containing '\(expected)', got: \(message)",
                file: file,
                line: line
            )
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    private func assertMatcherTarget(
        _ target: ElementTarget,
        label: String? = nil,
        identifier: String? = nil,
        ordinal: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .matcher(let matcher, let actualOrdinal) = target else {
            return XCTFail("Expected matcher target, got \(target)", file: file, line: line)
        }
        XCTAssertEqual(matcher.label, label, file: file, line: line)
        XCTAssertEqual(matcher.identifier, identifier, file: file, line: line)
        XCTAssertEqual(actualOrdinal, ordinal, file: file, line: line)
    }
}
