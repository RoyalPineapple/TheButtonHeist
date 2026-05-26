import XCTest

@testable import TheScore

final class ActionContractTests: XCTestCase {

    func testBatchStepCommandsDeclareDefaults() {
        for command in commandFixtures() {
            XCTAssertFalse(command.canonicalName.isEmpty)
            _ = command.defaultBatchExpectation
            _ = command.defaultBatchDeadline
        }
    }

    func testBatchStepRejectsNestedPlanOnEncode() throws {
        let plan = BatchPlan(steps: [
            .command(.setPasteboard(SetPasteboardTarget(text: "ready"))),
        ])
        let step = BatchStep.command(.batchExecutionPlan(plan))

        XCTAssertThrowsError(try JSONEncoder().encode(step)) { error in
            XCTAssertTrue(
                "\(error)".contains("cannot be a nested batch execution plan"),
                "Expected nested batch rejection, got \(error)"
            )
        }
    }

    func testWaitCommandsOwnDynamicBatchDefaults() {
        let absent = ClientMessage.waitFor(WaitForTarget(
            elementTarget: .matcher(ElementMatcher(identifier: "transient-toast")),
            absent: true,
            timeout: 60
        ))
        XCTAssertEqual(absent.defaultBatchExpectation, .elementDisappeared(ElementMatcher(identifier: "transient-toast")))
        XCTAssertEqual(absent.defaultBatchDeadline, Deadline(timeout: 30))

        let heistIdWait = ClientMessage.waitFor(WaitForTarget(elementTarget: .heistId("toast_1")))
        XCTAssertEqual(heistIdWait.defaultBatchExpectation, .elementAppeared(ElementMatcher(heistId: "toast_1")))

        let anyChange = ClientMessage.waitForChange(WaitForChangeTarget())
        XCTAssertEqual(anyChange.defaultBatchExpectation, .screenChanged)
        XCTAssertEqual(anyChange.defaultBatchDeadline, Deadline(timeout: 30))

        let idle = ClientMessage.waitForIdle(WaitForIdleTarget())
        XCTAssertEqual(idle.defaultBatchExpectation, .delivery)
        XCTAssertEqual(idle.defaultBatchDeadline, Deadline(timeout: 5))
    }

    func testBatchStepDefaultsComeFromCommand() throws {
        let command = ClientMessage.waitForChange(WaitForChangeTarget(
            expect: .elementsChanged,
            timeout: 0.25
        ))

        let constructed = BatchStep.command(command)
        XCTAssertEqual(constructed.expectation, command.defaultBatchExpectation)
        XCTAssertEqual(constructed.deadline, command.defaultBatchDeadline)

        let data = try JSONEncoder().encode(["command": command])
        let decoded = try JSONDecoder().decode(BatchStep.self, from: data)
        XCTAssertEqual(decoded.expectation, command.defaultBatchExpectation)
        XCTAssertEqual(decoded.deadline, command.defaultBatchDeadline)
    }

    private func commandFixtures() -> [ClientMessage] {
        let target = ElementTarget.matcher(ElementMatcher(label: "Save", traits: [.button]))
        let scrollTarget = ElementTarget.matcher(ElementMatcher(label: "Scroll area"))
        let waitTarget = ElementTarget.matcher(ElementMatcher(identifier: "result-row"))

        return [
            .activate(target),
            .increment(target),
            .decrement(target),
            .performCustomAction(CustomActionTarget(elementTarget: target, actionName: "Share")),
            .rotor(RotorTarget(elementTarget: target, rotor: "Links")),
            .touchTap(TouchTapTarget(elementTarget: target, pointX: 1, pointY: 2)),
            .touchLongPress(LongPressTarget(elementTarget: target, duration: 0.7)),
            .touchSwipe(SwipeTarget(elementTarget: target, direction: .left, duration: 0.4)),
            .touchDrag(DragTarget(elementTarget: target, startX: 1, startY: 2, endX: 3, endY: 4)),
            .touchPinch(PinchTarget(elementTarget: target, scale: 1.5)),
            .touchRotate(RotateTarget(elementTarget: target, angle: 0.5)),
            .touchTwoFingerTap(TwoFingerTapTarget(elementTarget: target, spread: 40)),
            .touchDrawPath(DrawPathTarget(points: [
                PathPoint(x: 1, y: 2),
                PathPoint(x: 3, y: 4),
            ])),
            .touchDrawBezier(DrawBezierTarget(
                startX: 1,
                startY: 2,
                segments: [
                    BezierSegment(cp1X: 3, cp1Y: 4, cp2X: 5, cp2Y: 6, endX: 7, endY: 8),
                ]
            )),
            .typeText(TypeTextTarget(text: "hello", elementTarget: target)),
            .editAction(EditActionTarget(action: .copy)),
            .setPasteboard(SetPasteboardTarget(text: "ready")),
            .scroll(ScrollTarget(elementTarget: scrollTarget, direction: .down)),
            .scrollToVisible(ScrollToVisibleTarget(elementTarget: scrollTarget)),
            .elementSearch(ElementSearchTarget(elementTarget: scrollTarget, direction: .down)),
            .scrollToEdge(ScrollToEdgeTarget(elementTarget: scrollTarget, edge: .bottom)),
            .waitForIdle(WaitForIdleTarget(timeout: 0.5)),
            .waitFor(WaitForTarget(elementTarget: waitTarget, timeout: 2)),
            .waitForChange(WaitForChangeTarget(expect: .elementsChanged, timeout: 1)),
            .explore,
            .resignFirstResponder,
        ]
    }
}
