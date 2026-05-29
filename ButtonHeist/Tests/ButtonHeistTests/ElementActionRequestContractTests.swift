import XCTest
@testable import ButtonHeist
import TheScore

final class ElementActionRequestContractTests: XCTestCase {

    @ButtonHeistActor
    func testActivateMissingTargetKeepsContractDiagnostics() async throws {
        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(command: .activate)

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
        await assertExecutionError(
            command: .typeText,
            arguments: ["text": .string("")],
            contains: "schema validation failed for text: observed string \"\"; expected non-empty string"
        )
    }

    @ButtonHeistActor
    func testAdjustmentCountRangeDiagnosticKeepsObservedValue() async {
        await assertExecutionError(
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "counter"),
                "action": .string("increment"),
                "count": .int(0),
            ],
            contains: "schema validation failed for count: observed integer 0; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testRotorInvalidTextRangeDiagnosticKeepsObservedRange() async {
        await assertExecutionError(
            command: .rotor,
            arguments: [
                "target": targetValue(identifier: "body"),
                "currentHeistId": .string("body-current"),
                "currentTextStartOffset": .int(10),
                "currentTextEndOffset": .int(4),
            ],
            contains: "schema validation failed for currentTextStartOffset/currentTextEndOffset: " +
                "observed 10..<4; expected integer range with start >= 0 and end >= start"
        )
    }

    @ButtonHeistActor
    func testScrollRejectsMixedElementAndContainerTargetsAtTypedBoundary() async {
        await assertExecutionError(
            command: .scroll,
            arguments: [
                "target": targetValue(identifier: "row"),
                "container": .object(["stableId": .string("list")]),
            ],
            contains: "schema validation failed for target: observed"
                + " object; expected at most one of container or element target"
        )
    }

    @ButtonHeistActor
    private func assertExecutionError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(
                command: command,
                values: arguments
            )
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
}

private func targetValue(identifier: String) -> HeistValue {
    .object(["identifier": .string(identifier)])
}
