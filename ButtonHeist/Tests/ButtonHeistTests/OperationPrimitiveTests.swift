import XCTest
@testable import ButtonHeist
import TheScore

final class OperationPrimitiveTests: XCTestCase {

    func testNonReadOperationRequiresActionExpectationAndDeadline() {
        let step = makeStep(
            action: makeAction(),
            expectation: .screenChanged,
            deadline: TheFence.Deadline(timeout: 2.0)
        )

        XCTAssertNotNil(step.action)
        XCTAssertEqual(step.expectation, .screenChanged)
        XCTAssertEqual(step.deadline, TheFence.Deadline(timeout: 2.0))
        XCTAssertTrue(step.isCompleteOperation)
    }

    func testActionWithoutExpectationIsNotACompleteOperation() {
        let step = makeStep(
            action: makeAction(),
            expectation: nil,
            deadline: TheFence.Deadline(timeout: 1.0)
        )

        XCTAssertNil(step.action)
        XCTAssertNil(step.expectation)
        XCTAssertNil(step.deadline)
        XCTAssertFalse(step.isCompleteOperation)
    }

    func testExpectationWithoutActionIsNotACompleteOperation() {
        let step = makeStep(
            action: nil,
            expectation: .screenChanged,
            deadline: TheFence.Deadline(timeout: 3.0)
        )

        XCTAssertNil(step.action)
        XCTAssertNil(step.expectation)
        XCTAssertNil(step.deadline)
        XCTAssertFalse(step.isCompleteOperation)
    }

    func testOperationWithoutDeadlineIsNotComplete() {
        let step = makeStep(
            action: makeAction(),
            expectation: .screenChanged,
            deadline: nil
        )

        XCTAssertNil(step.action)
        XCTAssertNil(step.expectation)
        XCTAssertNil(step.deadline)
        XCTAssertFalse(step.isCompleteOperation)
    }

    func testReadObservationEntryStaysOutsideOperationPipeline() {
        let step = makeStep(
            action: nil,
            expectation: nil,
            deadline: nil,
            command: .getScreen,
            operation: NormalizedOperation(command: .getScreen, arguments: [:]),
            payload: .screen(TheFence.ScreenRequest(
                outputPath: nil,
                requestId: "read-test",
                inlineData: false,
                includeInterface: false
            ))
        )

        XCTAssertNil(step.action)
        XCTAssertNil(step.expectation)
        XCTAssertNil(step.deadline)
        XCTAssertFalse(step.isCompleteOperation)
    }

    private func makeAction() -> TheFence.Action {
        .setPasteboard(SetPasteboardTarget(text: "value"))
    }

    private func makeStep(
        action: TheFence.Action?,
        expectation: ActionExpectation?,
        deadline: TheFence.Deadline?,
        command: TheFence.Command = .setPasteboard,
        operation: NormalizedOperation = NormalizedOperation(command: .setPasteboard, arguments: [:]),
        payload: TheFence.RequestPayload = .setPasteboard(SetPasteboardTarget(text: "value"))
    ) -> TheFence.BatchStep {
        let request = TheFence.ParsedRequest(
            command: command,
            requestId: "operation-test",
            payload: payload,
            expectationPayload: TheFence.ExpectationPayload(expectation: expectation, timeout: deadline?.timeout),
            immediateResponse: nil
        )
        return TheFence.BatchStep(
            command: command,
            operation: operation,
            adapterRequest: request,
            action: action,
            expectation: expectation,
            deadline: deadline
        )
    }
}
