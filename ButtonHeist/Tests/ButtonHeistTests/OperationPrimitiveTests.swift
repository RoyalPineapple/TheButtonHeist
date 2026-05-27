import XCTest
@testable import ButtonHeist
import TheScore

final class OperationPrimitiveTests: XCTestCase {

    func testBatchStepAlwaysCarriesActionExpectationAndDeadline() {
        let step = BatchStep(
            command: .setPasteboard(SetPasteboardTarget(text: "value")),
            expectation: .screenChanged,
            deadline: Deadline(timeout: 2.0)
        )

        guard case .setPasteboard(let target) = step.command else {
            return XCTFail("Expected set_pasteboard command")
        }
        XCTAssertEqual(target.text, "value")
        XCTAssertEqual(step.expectation, .screenChanged)
        XCTAssertEqual(step.deadline, Deadline(timeout: 2.0))
    }

    @ButtonHeistActor
    func testReadObservationEntryFailsAtBatchDecodeBoundary() async throws {
        let fence = TheFence(configuration: .init())
        XCTAssertThrowsError(try fence.decodeRunBatchRequest(TheFence.CommandArgumentEnvelope(arguments: [
            "steps": [["command": "get_screen"]],
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("run_batch step command \"get_screen\" is not supported"))
        }
    }
}
