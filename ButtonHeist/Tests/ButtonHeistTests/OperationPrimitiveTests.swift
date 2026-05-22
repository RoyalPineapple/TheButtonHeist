import XCTest
@testable import ButtonHeist
import TheScore

final class OperationPrimitiveTests: XCTestCase {

    func testBatchStepAlwaysCarriesOperationExpectationAndDeadline() {
        let step = BatchStep.action(
            .setPasteboard(SetPasteboardTarget(text: "value")),
            expect: .screenChanged,
            deadline: Deadline(timeout: 2.0)
        )

        guard case .action(let action) = step.operation,
              case .setPasteboard(let target) = action
        else {
            return XCTFail("Expected set_pasteboard action operation")
        }
        XCTAssertEqual(target.text, "value")
        XCTAssertEqual(step.expectation, .screenChanged)
        XCTAssertEqual(step.deadline, Deadline(timeout: 2.0))
    }

    func testCheckpointStepIsNotAUserAction() {
        let step = BatchStep.checkpoint(BatchExecutionCheckpoint(
            name: "loaded",
            expect: .screenChanged,
            timeout: 1.5
        ))

        guard case .checkpoint(let checkpoint) = step.operation else {
            return XCTFail("Expected checkpoint operation")
        }
        XCTAssertEqual(checkpoint.name, "loaded")
        guard case .checkpoint = step.action else {
            return XCTFail("Expected legacy checkpoint action projection")
        }
        XCTAssertEqual(step.expectation, .screenChanged)
        XCTAssertEqual(step.deadline, Deadline(timeout: 1.5))
    }

    @ButtonHeistActor
    func testReadObservationEntryStaysOutsideOperationPipeline() async throws {
        let fence = TheFence(configuration: .init())
        let request = try fence.decodeRunBatchRequest([
            "steps": [
                ["command": "get_screen"],
            ],
        ])

        guard case .invalid(let commandName, let failure)? = request.steps.first else {
            return XCTFail("Expected read command to stay outside batch operation pipeline")
        }
        XCTAssertEqual(commandName, "get_screen")
        XCTAssertTrue(failure.message.contains("not batch-executable"))
    }
}
