import XCTest
@testable import TheScore

final class CommandProjectionTests: XCTestCase {

    func testPointGestureProjectionUsesCoordinateWhenNoSemanticTargetExists() throws {
        let target = TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))

        XCTAssertEqual(target.gesturePointSelection(), GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20)))
    }

    func testSwipeProjectionPreservesElementDirectionIntent() {
        let target = SwipeTarget(
            selection: .elementDirection(.heistId("carousel"), .left)
        )

        XCTAssertEqual(
            target.gestureSelection(),
            .elementDirection(.heistId("carousel"), .left)
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

    func testScrollTargetOwnsOneSelection() {
        XCTAssertEqual(
            ScrollTarget(selection: .container(ScrollContainerTarget(stableId: "main"))).selection,
            .container(ScrollContainerTarget(stableId: "main"))
        )
        XCTAssertEqual(
            ScrollTarget(selection: .element(.heistId("row"))).selection,
            .element(.heistId("row"))
        )
        XCTAssertEqual(ScrollTarget().selection, .visibleContainer)
        XCTAssertEqual(
            ScrollToEdgeTarget(selection: .container(ScrollContainerTarget(stableId: "main"))).selection,
            .container(ScrollContainerTarget(stableId: "main"))
        )
    }

    func testCustomActionTargetOwnsElementSelection() {
        XCTAssertEqual(
            CustomActionTarget(elementTarget: .heistId("button"), actionName: "Archive"),
            CustomActionTarget(elementTarget: .heistId("button"), actionName: "Archive")
        )
    }

}
