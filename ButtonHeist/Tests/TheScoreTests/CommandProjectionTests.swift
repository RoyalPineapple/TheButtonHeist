import XCTest
import ThePlans
@testable import TheScore

final class CommandProjectionTests: XCTestCase {

    func testPointGestureProjectionUsesCoordinateWhenNoSemanticTargetExists() throws {
        let target = TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))

        XCTAssertEqual(target.selection, GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20)))
    }

    func testSwipeProjectionPreservesElementDirectionIntent() {
        let target = SwipeTarget(
            selection: .elementDirection(.predicate(ElementPredicate(label: "carousel")), .left)
        )

        XCTAssertEqual(
            target.selection,
            .elementDirection(.predicate(ElementPredicate(label: "carousel")), .left)
        )
    }

    func testSwipeProjectionPreservesPointDirectionIntent() throws {
        let target = SwipeTarget(
            selection: .pointDirection(
                start: ScreenPoint(x: 10, y: 20),
                direction: .down
            )
        )

        XCTAssertEqual(
            target.selection,
            .pointDirection(
                start: ScreenPoint(x: 10, y: 20),
                direction: .down
            )
        )
    }

    func testScrollTargetOwnsPublicSelection() {
        XCTAssertEqual(
            ScrollTarget(selection: .element(.predicate(ElementPredicate(label: "row")))).selection,
            .element(.predicate(ElementPredicate(label: "row")))
        )
        XCTAssertEqual(ScrollTarget().selection, .visibleContainer)
        XCTAssertEqual(
            ScrollTarget(selection: .container("main_scroll")).selection,
            .container("main_scroll")
        )
        XCTAssertEqual(
            ScrollToEdgeTarget(selection: .element(.predicate(ElementPredicate(label: "row")))).selection,
            .element(.predicate(ElementPredicate(label: "row")))
        )
        XCTAssertEqual(
            ScrollToEdgeTarget(selection: .container("main_scroll")).selection,
            .container("main_scroll")
        )
    }

    func testCustomActionTargetOwnsElementSelection() {
        XCTAssertEqual(
            CustomActionTarget(target: .predicate(ElementPredicate(label: "button")), actionName: "Archive"),
            CustomActionTarget(target: .predicate(ElementPredicate(label: "button")), actionName: "Archive")
        )
    }

}
