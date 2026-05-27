import XCTest
@testable import TheScore

final class CommandProjectionTests: XCTestCase {

    func testPointGestureProjectionPrefersSemanticTargetOverCoordinates() throws {
        let target = TouchTapTarget(
            elementTarget: .heistId("save_button"),
            pointX: 10,
            pointY: 20
        )

        XCTAssertEqual(try target.gesturePointSelection(), .element(.heistId("save_button")))
    }

    func testPointGestureProjectionUsesCoordinateWhenNoSemanticTargetExists() throws {
        let target = TouchTapTarget(pointX: 10, pointY: 20)

        XCTAssertEqual(try target.gesturePointSelection(), .coordinate(ScreenPoint(x: 10, y: 20)))
    }

    func testPointGestureProjectionRejectsPartialCoordinate() {
        let target = TouchTapTarget(pointX: 10)

        XCTAssertThrowsError(try target.gesturePointSelection()) { error in
            XCTAssertEqual(
                error as? GestureProjectionError,
                .partialCoordinate(field: "point", xPresent: true, yPresent: false)
            )
        }
    }

    func testSwipeProjectionConvertsElementDirectionIntoUnitFrameGesture() throws {
        let target = SwipeTarget(elementTarget: .heistId("carousel"), direction: .left)

        XCTAssertEqual(
            try target.gestureSelection(),
            .unitElement(.heistId("carousel"), start: SwipeDirection.left.defaultStart, end: SwipeDirection.left.defaultEnd)
        )
    }

    func testSwipeProjectionRejectsHalfValidUnitPoints() {
        let target = SwipeTarget(elementTarget: .heistId("carousel"), start: UnitPoint(x: 0.8, y: 0.5))

        XCTAssertThrowsError(try target.gestureSelection()) { error in
            XCTAssertEqual(error as? GestureProjectionError, .partialUnitPoints)
        }
    }

    func testSwipeProjectionSeparatesStartAndDestination() throws {
        let target = SwipeTarget(startX: 10, startY: 20, direction: .down)

        XCTAssertEqual(
            try target.gestureSelection(),
            .point(
                start: .coordinate(ScreenPoint(x: 10, y: 20)),
                destination: .direction(.down)
            )
        )
    }

    func testScrollTargetProjectsToOneContainerSelection() {
        XCTAssertEqual(
            ScrollTarget(containerTarget: ScrollContainerTarget(stableId: "main")).containerSelection,
            .container(ScrollContainerTarget(stableId: "main"))
        )
        XCTAssertEqual(
            ScrollTarget(elementTarget: .heistId("row")).containerSelection,
            .element(.heistId("row"))
        )
        XCTAssertEqual(ScrollTarget().containerSelection, .visibleContainer)
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
        let trace = AccessibilityTrace(segments: [.init(baseline: invalidCapture)])

        XCTAssertThrowsError(try trace.validated()) { error in
            guard case .integrityIssues(let issues) = error as? AccessibilityTraceValidationError else {
                return XCTFail("Expected trace integrity issues, got \(error)")
            }
            XCTAssertEqual(issues.count, 1)
        }
    }
}
