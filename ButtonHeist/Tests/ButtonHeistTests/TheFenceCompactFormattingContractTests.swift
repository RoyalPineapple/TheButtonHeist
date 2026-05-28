import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceCompactFormattingContractTests: XCTestCase {

    func testCompactActionRenderingUsesDescriptorProjectedCommandNames() {
        let cases: [(method: ActionMethod, expected: String)] = [
            (.typeText, "type_text: ok"),
            (.waitFor, "wait_for: ok"),
            (.customAction, "activate: ok"),
            (.resignFirstResponder, "dismiss_keyboard: ok"),
            (.syntheticTap, "one_finger_tap: ok"),
        ]

        for testCase in cases {
            let output = FenceResponse.action(
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
            result: ActionResult(
                success: true,
                method: .scrollToVisible,
                payload: .scrollSearch(search)
            )
        ).compactFormatted()

        XCTAssertEqual(output, "scroll_to_visible: already visible")
    }

    func testActionResultMethodProjectionIsDescriptorOwnedAndUnambiguous() {
        let projections = TheFence.Command.descriptors.compactMap { descriptor in
            descriptor.actionResultMethod.map { (method: $0, command: descriptor.command) }
        }
        let duplicateDescriptions = Dictionary(grouping: projections, by: \.method)
            .filter { $0.value.count > 1 }
            .map { method, projections in
                let commands = projections.map(\.command.rawValue).sorted().joined(separator: ", ")
                return "\(method.rawValue): \(commands)"
            }
            .sorted()

        XCTAssertTrue(
            duplicateDescriptions.isEmpty,
            "Action result method projections must be unambiguous:\n\(duplicateDescriptions.joined(separator: "\n"))"
        )

        let descriptorExpected: [ActionMethod: TheFence.Command] = [
            .waitForChange: .waitForChange,
            .syntheticLongPress: .longPress,
            .syntheticSwipe: .swipe,
            .syntheticDrag: .drag,
            .syntheticPinch: .pinch,
            .syntheticRotate: .rotate,
            .syntheticTwoFingerTap: .twoFingerTap,
            .scroll: .scroll,
            .scrollToVisible: .scrollToVisible,
            .elementSearch: .elementSearch,
            .scrollToEdge: .scrollToEdge,
            .activate: .activate,
            .rotor: .rotor,
            .typeText: .typeText,
            .editAction: .editAction,
            .setPasteboard: .setPasteboard,
            .getPasteboard: .getPasteboard,
            .waitFor: .waitFor,
            .resignFirstResponder: .dismissKeyboard,
        ]

        for (method, command) in descriptorExpected {
            let descriptor = TheFence.Command.descriptor(forActionResultMethod: method)

            XCTAssertEqual(descriptor?.command, command)
            XCTAssertEqual(TheFence.Command.canonicalName(forActionResultMethod: method), command.rawValue)
        }

        let activateProjectedMethods: [ActionMethod] = [.increment, .decrement, .customAction]
        for method in activateProjectedMethods {
            XCTAssertNil(TheFence.Command.descriptor(forActionResultMethod: method))
            XCTAssertEqual(TheFence.Command.canonicalName(forActionResultMethod: method), TheFence.Command.activate.rawValue)
        }
        XCTAssertNil(TheFence.Command.descriptor(forActionResultMethod: .syntheticTap))
        XCTAssertNil(TheFence.Command.descriptor(forActionResultMethod: .syntheticDrawPath))
        XCTAssertEqual(TheFence.Command.canonicalName(forActionResultMethod: .syntheticTap), TheFence.Command.oneFingerTap.rawValue)
        XCTAssertEqual(TheFence.Command.canonicalName(forActionResultMethod: .syntheticDrawPath), TheFence.Command.drawPath.rawValue)
    }

}
