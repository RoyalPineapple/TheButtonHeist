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

    func testSwipeProjectionSeparatesStartAndDestination() throws {
        let target = SwipeTarget(
            selection: .point(
                start: .coordinate(ScreenPoint(x: 10, y: 20)),
                destination: .direction(.down)
            )
        )

        XCTAssertEqual(
            target.selection,
            .point(
                start: .coordinate(ScreenPoint(x: 10, y: 20)),
                destination: .direction(.down)
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
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "button")), actionName: "Archive"),
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "button")), actionName: "Archive")
        )
    }

}
