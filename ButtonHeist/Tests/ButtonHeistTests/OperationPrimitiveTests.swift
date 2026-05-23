import XCTest
@testable import ButtonHeist
import TheScore

final class OperationPrimitiveTests: XCTestCase {

    func testBatchStepAlwaysCarriesActionExpectationAndDeadline() {
        let step = BatchStep.action(
            .setPasteboard(SetPasteboardTarget(text: "value")),
            expect: .screenChanged,
            deadline: Deadline(timeout: 2.0)
        )

        guard case .setPasteboard(let target) = step.action else {
            return XCTFail("Expected set_pasteboard action")
        }
        XCTAssertEqual(target.text, "value")
        XCTAssertEqual(step.expectation, .screenChanged)
        XCTAssertEqual(step.deadline, Deadline(timeout: 2.0))
    }

    @ButtonHeistActor
    func testReadObservationEntryStaysOutsideOperationPipeline() async throws {
        let fence = TheFence(configuration: .init())
        let request = try fence.decodeRunBatchRequest(TheFence.CommandArgumentEnvelope(arguments: [
            "steps": [
                ["command": "get_screen"],
            ],
        ]))

        guard case .invalid(let commandName, let failure)? = request.steps.first else {
            return XCTFail("Expected read command to stay outside batch operation pipeline")
        }
        XCTAssertEqual(commandName, "get_screen")
        XCTAssertTrue(failure.message.contains("not batch-executable"))
    }
}
