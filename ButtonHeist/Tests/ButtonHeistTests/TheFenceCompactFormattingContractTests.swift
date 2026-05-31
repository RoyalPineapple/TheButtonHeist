import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceCompactFormattingContractTests: XCTestCase {

    func testCompactActionRenderingUsesParsedCommandNames() {
        let cases: [(command: TheFence.Command, method: ActionMethod, expected: String)] = [
            (.typeText, .typeText, "type_text: ok"),
            (.waitFor, .waitFor, "wait_for: ok"),
            (.activate, .customAction, "activate: ok"),
            (.dismissKeyboard, .resignFirstResponder, "dismiss_keyboard: ok"),
            (.oneFingerTap, .syntheticTap, "one_finger_tap: ok"),
        ]

        for testCase in cases {
            let output = FenceResponse.action(
                command: testCase.command,
                result: ActionResult(success: true, method: testCase.method)
            ).compactFormatted()

            XCTAssertEqual(output, testCase.expected)
        }
    }

    func testCompactScrollSearchUsesDescriptorProjectedCommandName() {
        let search = ScrollSearchResult(
            scrollCount: 0,
            uniqueElementsSeen: 0,
            exhaustive: false
        )
        let output = FenceResponse.action(
            command: .scrollToVisible,
            result: ActionResult(
                success: true,
                method: .scrollToVisible,
                payload: .scrollSearch(search)
            )
        ).compactFormatted()

        XCTAssertEqual(output, "scroll_to_visible: already visible")
    }

    func testCompactActionRenderingDoesNotInferCommandFromActionMethod() {
        let output = FenceResponse.action(
            command: .drag,
            result: ActionResult(success: true, method: .syntheticTap)
        ).compactFormatted()

        XCTAssertEqual(output, "drag: ok")
    }

}
