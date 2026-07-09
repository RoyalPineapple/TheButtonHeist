import XCTest
import ThePlans
@testable import TheScore

final class ScrollToVisibleTests: XCTestCase {

    // MARK: - ScrollToVisibleTarget (one-shot, no direction)

    func testScrollToVisibleTargetEncodeDecode() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .predicate(ElementPredicate(label: "Color Picker", traits: [.button]))
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .predicate(let matcher, _) = decoded.elementTarget else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.checks, [
            .label(.exact("Color Picker")),
            .traits([.button]),
        ])
    }

    func testScrollToVisibleTargetMinimal() throws {
        let target = ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Save")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .predicate(let matcher, _) = decoded.elementTarget else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.checks, [.label(.exact("Save"))])
    }

    func testScrollToVisibleRuntimeActionRoundTrip() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .predicate(ElementPredicate(label: "Settings", traits: [.header]))
        )
        let message = ClientMessage.runtimeAction(.viewportScrollToVisible(.target(target.elementTarget)))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        guard case .runtimeAction(let action) = decoded,
              case .viewportScrollToVisible(let decodedTarget) = action,
              case .predicate(let matcher, _) = try decodedTarget.resolve(in: .empty) else {
            return XCTFail("Expected runtimeAction with scrollToVisible action")
        }
        XCTAssertEqual(matcher.checks, [
            .label(.exact("Settings")),
            .traits([.header]),
        ])
    }

    func testScrollToVisibleTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Settings"}}],"foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_visible target field "foo""#])
        }
    }

    func testScrollToVisibleTargetRejectsPublicContainerName() throws {
        let data = Data(#"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Settings"}}],"containerName":"main_scroll"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_visible target field "containerName""#])
        }
    }

    func testScrollToVisibleTargetRejectsPartialScopedTarget() throws {
        let containerOnly = Data(#"{"container":{"checks":[{"kind":"scrollable","value":true}]}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: containerOnly)) { error in
            assertDecodingError(error, contains: ["scoped element target requires target"])
        }

        let targetOnly = Data(#"{"target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Settings"}}]}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: targetOnly)) { error in
            assertDecodingError(error, contains: ["scoped element target requires container"])
        }
    }

    func testScrollToVisiblePrimitiveRequestEnvelopeIsRejected() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(buttonHeistVersion)","type":"scrollToVisible","payload":{"label":"Settings","unexpected":"main_scroll"}}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unsupported client wire message type"])
        }
    }

    func testActionResultWithoutPayload() throws {
        let result = ActionResult.success(method: .activate)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNil(decoded.payload)
    }

    private func assertDecodingError(
        _ error: Error,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case DecodingError.dataCorrupted(let context) = error else {
            XCTFail("Expected DecodingError.dataCorrupted, got \(error)", file: file, line: line)
            return
        }
        for fragment in fragments {
            XCTAssertTrue(
                context.debugDescription.contains(fragment),
                context.debugDescription,
                file: file,
                line: line
            )
        }
    }
}
