import XCTest
@testable import TheScore

final class CommandProjectionTests: XCTestCase {

    func testPointGestureProjectionUsesCoordinateWhenNoSemanticTargetExists() throws {
        let target = TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))

        XCTAssertEqual(target.gesturePointSelection(), GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20)))
    }

    func testSwipeProjectionConvertsElementDirectionIntoUnitFrameGesture() {
        let target = SwipeTarget(
            selection: .unitElement(
                .heistId("carousel"),
                start: SwipeDirection.left.defaultStart,
                end: SwipeDirection.left.defaultEnd,
                direction: .left
            )
        )

        XCTAssertEqual(
            target.gestureSelection(),
            .unitElement(
                .heistId("carousel"),
                start: SwipeDirection.left.defaultStart,
                end: SwipeDirection.left.defaultEnd,
                direction: .left
            )
        )
    }

    func testSwipeProjectionSeparatesStartAndDestination() throws {
        let target = SwipeTarget(
            selection: .point(
                start: .coordinate(ScreenPoint(x: 10, y: 20)),
                destination: .direction(.down)
            )
        )

        XCTAssertEqual(
            target.gestureSelection(),
            .point(
                start: .coordinate(ScreenPoint(x: 10, y: 20)),
                destination: .direction(.down)
            )
        )
    }

    func testScrollTargetProjectsToOneContainerSelection() {
        XCTAssertEqual(
            ScrollTarget(selection: .container(ScrollContainerTarget(stableId: "main"))).containerSelection,
            .container(ScrollContainerTarget(stableId: "main"))
        )
        XCTAssertEqual(
            ScrollTarget(selection: .element(.heistId("row"))).containerSelection,
            .element(.heistId("row"))
        )
        XCTAssertEqual(ScrollTarget().containerSelection, .visibleContainer)
        XCTAssertEqual(
            ScrollToEdgeTarget(selection: .container(ScrollContainerTarget(stableId: "main"))).containerSelection,
            .container(ScrollContainerTarget(stableId: "main"))
        )
    }

    func testCustomActionTargetProjectsToOneSelection() {
        XCTAssertEqual(
            CustomActionTarget(elementTarget: .heistId("button"), actionName: "Archive").selection,
            .element(.heistId("button"), actionName: "Archive")
        )
        XCTAssertEqual(
            CustomActionTarget(
                containerTarget: ContainerMatcher(stableId: "toolbar"),
                ordinal: 1,
                actionName: "Dismiss"
            ).selection,
            .container(ContainerMatcher(stableId: "toolbar"), ordinal: 1, actionName: "Dismiss")
        )
    }

    func testTraceValidationProjectsCapturesAndReceipts() throws {
        let interface = makeTestInterface(elements: [
            HeistElement(
                heistId: "save",
                description: "Save",
                label: "Save",
                value: nil,
                identifier: nil,
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 44,
                frameHeight: 44,
                actions: [.activate]
            ),
        ])
        let trace = AccessibilityTrace(first: interface)

        let validated = try trace.validated()

        XCTAssertEqual(validated.captures, trace.captures)
        XCTAssertEqual(validated.receipts, trace.receipts)
    }

    func testTraceValidationRejectsInvalidTrace() {
        let interface = makeTestInterface(elements: [])
        let invalidCapture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            hash: "sha256:invalid"
        )
        let trace = AccessibilityTrace(captures: [invalidCapture])

        XCTAssertThrowsError(try trace.validated()) { error in
            guard case .integrityIssues(let issues) = error as? AccessibilityTraceValidationError else {
                return XCTFail("Expected trace integrity issues, got \(error)")
            }
            XCTAssertEqual(issues.count, 1)
        }
    }
}
