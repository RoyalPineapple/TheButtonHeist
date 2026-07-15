import XCTest
import ThePlans
@testable import TheScore

final class ScrollToVisibleTests: XCTestCase {

    // MARK: - ScrollToVisibleTarget (one-shot, no direction)

    func testScrollToVisibleTargetEncodeDecode() throws {
        let target = ScrollToVisibleTarget(
            target: .predicate(ElementPredicateTemplate(label: "Color Picker", traits: [.button]))
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .predicate(let matcher, _) = decoded.target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.checks, [
            .label(.exact("Color Picker")),
            .traits([.button]),
        ])
    }

    func testScrollToVisibleTargetMinimal() throws {
        let target = ScrollToVisibleTarget(target: .predicate(ElementPredicateTemplate(label: "Save")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .predicate(let matcher, _) = decoded.target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.checks, [.label(.exact("Save"))])
    }

    func testScrollToVisibleRuntimeActionRoundTrip() throws {
        let target = ScrollToVisibleTarget(
            target: .predicate(ElementPredicateTemplate(label: "Settings", traits: [.header]))
        )
        let message = ClientMessage.runtimeAction(.viewportScrollToVisible(target.target))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        guard case .runtimeAction(let action) = decoded else {
            return XCTFail("Expected runtimeAction with scrollToVisible action")
        }
        XCTAssertEqual(action, .viewportScrollToVisible(target.target))
    }

    func testScrollToVisibleTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Settings"}}]},"foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_visible target field "foo""#])
        }
    }

    func testScrollToVisibleTargetRejectsPublicContainerName() throws {
        let data = Data(#"{"target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Settings"}}]},"containerName":"main_scroll"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_visible target field "containerName""#])
        }
    }

    func testScrollToVisibleTargetRejectsRemovedFlatTargetShape() throws {
        let data = Data(#"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Settings"}}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_visible target field "checks""#])
        }
    }

    func testScrollToVisiblePrimitiveRequestEnvelopeIsRejected() throws {
        let data = Data("""
        {
          "buttonHeistVersion": "\(buttonHeistVersion)",
          "type": "scrollToVisible",
          "payload": {
            "target": {
              "checks": [
                { "kind": "label", "match": { "mode": "exact", "value": "Settings" } }
              ]
            },
            "unexpected": "main_scroll"
          }
        }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unsupported client wire message type"])
        }
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
