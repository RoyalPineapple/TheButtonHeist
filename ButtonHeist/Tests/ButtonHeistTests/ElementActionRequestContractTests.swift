import XCTest
@testable import ButtonHeist

final class ElementActionRequestContractTests: XCTestCase {

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
        await assertExecutionError(
            ["command": "type_text", "text": ""],
            contains: "schema validation failed for text: observed string \"\"; expected non-empty string"
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
    func testRotorInvalidTextRangeDiagnosticKeepsObservedRange() async {
        await assertExecutionError(
            [
                "command": "rotor",
                "identifier": "body",
                "currentHeistId": "body-current",
                "currentTextStartOffset": 10,
                "currentTextEndOffset": 4,
            ],
            contains: "schema validation failed for currentTextStartOffset/currentTextEndOffset: " +
                "observed 10..<4; expected integer range with start >= 0 and end >= start"
        )
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
}
