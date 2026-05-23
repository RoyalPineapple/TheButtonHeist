import Foundation
import XCTest

@testable import TheScore

final class ActionContractTests: XCTestCase {

    func testActionDescriptorsDeclareContractForEveryActionKind() {
        let actions = actionFixtures()

        XCTAssertEqual(actions.map(\.descriptor.kind), ActionDescriptor.Kind.allCases)
        for action in actions {
            let descriptor = action.descriptor
            let staticDescriptor = ActionDescriptor(kind: descriptor.kind)

            XCTAssertEqual(action.canonicalName, descriptor.canonicalName)
            XCTAssertEqual(action.actionMethod, descriptor.actionMethod)
            XCTAssertEqual(action.fulfillsOwnExpectation, descriptor.fulfillsOwnExpectation)
            XCTAssertEqual(action.defaultExpectation, descriptor.defaultExpectation)
            XCTAssertEqual(action.defaultDeadline, descriptor.defaultDeadline)
            XCTAssertEqual(descriptor.canonicalName, descriptor.kind.rawValue)
            XCTAssertEqual(descriptor.actionMethod, staticDescriptor.actionMethod)
            XCTAssertEqual(descriptor.fulfillsOwnExpectation, staticDescriptor.fulfillsOwnExpectation)
        }
    }

    func testActionCanonicalNamesMatchWireRawValues() {
        for kind in ActionDescriptor.Kind.allCases {
            XCTAssertEqual(
                ActionDescriptor(kind: kind).canonicalName,
                kind.rawValue,
                "\(kind) canonical name must match its wire raw value"
            )
        }
    }

    func testActionEncodingUsesDescriptorCanonicalNameAsWireType() throws {
        for action in actionFixtures() {
            let data = try JSONEncoder().encode(action)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            XCTAssertEqual(payload["type"] as? String, action.descriptor.canonicalName)
            let decoded = try JSONDecoder().decode(Action.self, from: data)
            XCTAssertEqual(decoded.canonicalName, action.canonicalName)
            XCTAssertEqual(decoded.actionMethod, action.actionMethod)
            XCTAssertEqual(decoded.fulfillsOwnExpectation, action.fulfillsOwnExpectation)
            XCTAssertEqual(decoded.defaultExpectation, action.defaultExpectation)
            XCTAssertEqual(decoded.defaultDeadline, action.defaultDeadline)
        }
    }

    func testWaitActionDescriptorsOwnDynamicDefaults() {
        let target = batchTarget(identifier: "transient-toast")
        let absent = Action.waitForElement(BatchWaitForTarget(
            target: target,
            absent: true,
            timeout: 60
        ))
        XCTAssertEqual(absent.descriptor.defaultExpectation, .elementDisappeared(target.matcher))
        XCTAssertEqual(absent.descriptor.defaultDeadline, Deadline(timeout: 30))

        let anyChange = Action.waitForChange(WaitForChangeTarget())
        XCTAssertEqual(anyChange.descriptor.defaultExpectation, .screenChanged)
        XCTAssertEqual(anyChange.descriptor.defaultDeadline, Deadline(timeout: 30))

        let idle = Action.waitForIdle(WaitForIdleTarget())
        XCTAssertEqual(idle.descriptor.defaultExpectation, .delivery)
        XCTAssertEqual(idle.descriptor.defaultDeadline, Deadline(timeout: 5))
    }

    func testBatchStepDefaultsComeFromActionDescriptor() throws {
        let action = Action.waitForChange(WaitForChangeTarget(
            expect: .elementsChanged,
            timeout: 0.25
        ))

        let constructed = BatchStep.action(action)
        XCTAssertEqual(constructed.expectation, action.descriptor.defaultExpectation)
        XCTAssertEqual(constructed.deadline, action.descriptor.defaultDeadline)

        let data = try JSONEncoder().encode(["action": action])
        let decoded = try JSONDecoder().decode(BatchStep.self, from: data)
        XCTAssertEqual(decoded.expectation, action.descriptor.defaultExpectation)
        XCTAssertEqual(decoded.deadline, action.descriptor.defaultDeadline)
    }

    private func actionFixtures() -> [Action] {
        let target = batchTarget(label: "Save")
        let scrollTarget = batchTarget(label: "Scroll area")
        let waitTarget = batchTarget(identifier: "result-row")

        return accessibilityFixtures(target: target)
            + touchFixtures(target: target)
            + inputAndScrollFixtures(target: target, scrollTarget: scrollTarget)
            + waitAndSystemFixtures(waitTarget: waitTarget)
    }

    private func accessibilityFixtures(
        target: BatchExecutionTarget
    ) -> [Action] {
        [
            .activate(target),
            .increment(target),
            .decrement(target),
            .performCustomAction(BatchCustomActionTarget(target: target, actionName: "Share")),
            .rotor(BatchRotorTarget(target: target, rotor: "Links")),
        ]
    }

    private func touchFixtures(
        target: BatchExecutionTarget
    ) -> [Action] {
        [
            .touchTap(BatchTouchTapTarget(target: target, pointX: 1, pointY: 2)),
            .touchLongPress(BatchLongPressTarget(target: target, duration: 0.7)),
            .touchSwipe(BatchSwipeTarget(target: target, direction: .left, duration: 0.4)),
            .touchDrag(BatchDragTarget(target: target, startX: 1, startY: 2, endX: 3, endY: 4)),
            .touchPinch(BatchPinchTarget(target: target, scale: 1.5)),
            .touchRotate(BatchRotateTarget(target: target, angle: 0.5)),
            .touchTwoFingerTap(BatchTwoFingerTapTarget(target: target, spread: 40)),
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
        ]
    }

    private func inputAndScrollFixtures(
        target: BatchExecutionTarget,
        scrollTarget: BatchExecutionTarget
    ) -> [Action] {
        [
            .typeText(BatchTypeTextTarget(text: "hello", target: target)),
            .editAction(EditActionTarget(action: .copy)),
            .setPasteboard(SetPasteboardTarget(text: "ready")),
            .scroll(BatchScrollTarget(target: scrollTarget, direction: .down)),
            .scrollToVisible(BatchScrollToVisibleTarget(target: scrollTarget)),
            .elementSearch(BatchElementSearchTarget(target: scrollTarget, direction: .down)),
            .scrollToEdge(BatchScrollToEdgeTarget(target: scrollTarget, edge: .bottom)),
        ]
    }

    private func waitAndSystemFixtures(
        waitTarget: BatchExecutionTarget
    ) -> [Action] {
        [
            .waitForIdle(WaitForIdleTarget(timeout: 0.5)),
            .waitForElement(BatchWaitForTarget(target: waitTarget, timeout: 2)),
            .waitForChange(WaitForChangeTarget(expect: .elementsChanged, timeout: 1)),
            .explore,
            .resignFirstResponder,
        ]
    }

    private func batchTarget(
        label: String? = nil,
        identifier: String? = nil
    ) -> BatchExecutionTarget {
        BatchExecutionTarget(
            sourceHeistId: "source-\(label ?? identifier ?? "element")",
            matcher: ElementMatcher(label: label, identifier: identifier)
        )
    }
}
