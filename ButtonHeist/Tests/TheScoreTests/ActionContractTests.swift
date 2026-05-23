import Foundation
import XCTest

@testable import TheScore

final class ActionContractTests: XCTestCase {

    func testActionDescriptorsDeclareContractForEveryActionKind() {
        let fixtures = actionFixtures()

        XCTAssertEqual(fixtures.map(\.action.descriptor.kind), ActionDescriptor.Kind.allCases)
        for fixture in fixtures {
            let descriptor = fixture.action.descriptor
            XCTAssertEqual(descriptor, fixture.descriptor)
            XCTAssertEqual(fixture.action.canonicalName, descriptor.canonicalName)
            XCTAssertEqual(fixture.action.actionMethod, descriptor.actionMethod)
            XCTAssertEqual(fixture.action.fulfillsOwnExpectation, descriptor.fulfillsOwnExpectation)
            XCTAssertEqual(fixture.action.defaultExpectation, descriptor.defaultExpectation)
            XCTAssertEqual(fixture.action.defaultDeadline, descriptor.defaultDeadline)
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
        for fixture in actionFixtures() {
            let data = try JSONEncoder().encode(fixture.action)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            XCTAssertEqual(payload["type"] as? String, fixture.descriptor.canonicalName)
            let decoded = try JSONDecoder().decode(Action.self, from: data)
            XCTAssertEqual(decoded.descriptor, fixture.descriptor)
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

    private func actionFixtures() -> [(action: Action, descriptor: ActionDescriptor)] {
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
    ) -> [(action: Action, descriptor: ActionDescriptor)] {
        [
            (.activate(target), ActionDescriptor(kind: .activate)),
            (.increment(target), ActionDescriptor(kind: .increment)),
            (.decrement(target), ActionDescriptor(kind: .decrement)),
            (
                .performCustomAction(BatchCustomActionTarget(target: target, actionName: "Share")),
                ActionDescriptor(kind: .performCustomAction)
            ),
            (
                .rotor(BatchRotorTarget(target: target, rotor: "Links")),
                ActionDescriptor(kind: .rotor)
            ),
        ]
    }

    private func touchFixtures(
        target: BatchExecutionTarget
    ) -> [(action: Action, descriptor: ActionDescriptor)] {
        [
            (
                .touchTap(BatchTouchTapTarget(target: target, pointX: 1, pointY: 2)),
                ActionDescriptor(kind: .touchTap)
            ),
            (
                .touchLongPress(BatchLongPressTarget(target: target, duration: 0.7)),
                ActionDescriptor(kind: .touchLongPress)
            ),
            (
                .touchSwipe(BatchSwipeTarget(target: target, direction: .left, duration: 0.4)),
                ActionDescriptor(kind: .touchSwipe)
            ),
            (
                .touchDrag(BatchDragTarget(target: target, startX: 1, startY: 2, endX: 3, endY: 4)),
                ActionDescriptor(kind: .touchDrag)
            ),
            (
                .touchPinch(BatchPinchTarget(target: target, scale: 1.5)),
                ActionDescriptor(kind: .touchPinch)
            ),
            (
                .touchRotate(BatchRotateTarget(target: target, angle: 0.5)),
                ActionDescriptor(kind: .touchRotate)
            ),
            (
                .touchTwoFingerTap(BatchTwoFingerTapTarget(target: target, spread: 40)),
                ActionDescriptor(kind: .touchTwoFingerTap)
            ),
            (
                .touchDrawPath(DrawPathTarget(points: [
                    PathPoint(x: 1, y: 2),
                    PathPoint(x: 3, y: 4),
                ])),
                ActionDescriptor(kind: .touchDrawPath)
            ),
            (
                .touchDrawBezier(DrawBezierTarget(
                    startX: 1,
                    startY: 2,
                    segments: [
                        BezierSegment(cp1X: 3, cp1Y: 4, cp2X: 5, cp2Y: 6, endX: 7, endY: 8),
                    ]
                )),
                ActionDescriptor(kind: .touchDrawBezier)
            ),
        ]
    }

    private func inputAndScrollFixtures(
        target: BatchExecutionTarget,
        scrollTarget: BatchExecutionTarget
    ) -> [(action: Action, descriptor: ActionDescriptor)] {
        [
            (
                .typeText(BatchTypeTextTarget(text: "hello", target: target)),
                ActionDescriptor(kind: .typeText)
            ),
            (.editAction(EditActionTarget(action: .copy)), ActionDescriptor(kind: .editAction)),
            (.setPasteboard(SetPasteboardTarget(text: "ready")), ActionDescriptor(kind: .setPasteboard)),
            (
                .scroll(BatchScrollTarget(target: scrollTarget, direction: .down)),
                ActionDescriptor(kind: .scroll)
            ),
            (
                .scrollToVisible(BatchScrollToVisibleTarget(target: scrollTarget)),
                ActionDescriptor(kind: .scrollToVisible)
            ),
            (
                .elementSearch(BatchElementSearchTarget(target: scrollTarget, direction: .down)),
                ActionDescriptor(kind: .elementSearch)
            ),
            (
                .scrollToEdge(BatchScrollToEdgeTarget(target: scrollTarget, edge: .bottom)),
                ActionDescriptor(kind: .scrollToEdge)
            ),
        ]
    }

    private func waitAndSystemFixtures(
        waitTarget: BatchExecutionTarget
    ) -> [(action: Action, descriptor: ActionDescriptor)] {
        [
            (
                .waitForIdle(WaitForIdleTarget(timeout: 0.5)),
                ActionDescriptor(
                    kind: .waitForIdle,
                    defaultExpectation: .delivery,
                    defaultDeadline: Deadline(timeout: 0.5)
                )
            ),
            (
                .waitForElement(BatchWaitForTarget(target: waitTarget, timeout: 2)),
                ActionDescriptor(
                    kind: .waitForElement,
                    defaultExpectation: .elementAppeared(waitTarget.matcher),
                    defaultDeadline: Deadline(timeout: 2)
                )
            ),
            (
                .waitForChange(WaitForChangeTarget(expect: .elementsChanged, timeout: 1)),
                ActionDescriptor(
                    kind: .waitForChange,
                    defaultExpectation: .elementsChanged,
                    defaultDeadline: Deadline(timeout: 1)
                )
            ),
            (.explore, ActionDescriptor(kind: .explore)),
            (.resignFirstResponder, ActionDescriptor(kind: .resignFirstResponder)),
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
