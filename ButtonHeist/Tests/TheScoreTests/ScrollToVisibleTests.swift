import XCTest
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
        XCTAssertEqual(matcher.label, "Color Picker")
        XCTAssertEqual(matcher.traits, [.button])
    }

    func testScrollToVisibleTargetMinimal() throws {
        let target = ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Save")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .predicate(let matcher, _) = decoded.elementTarget else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Save")
    }

    func testScrollToVisibleClientMessageRoundTrip() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .predicate(ElementPredicate(label: "Settings", traits: [.header]))
        )
        let message = ClientMessage.scrollToVisible(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        guard case .scrollToVisible(let decodedTarget) = decoded,
              case .predicate(let matcher, _) = decodedTarget.elementTarget else {
            return XCTFail("Expected scrollToVisible with matcher")
        }
        XCTAssertEqual(matcher.label, "Settings")
        XCTAssertEqual(matcher.traits, [.header])
    }

    func testScrollToVisibleTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"label":"Settings","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains(#"Unknown scroll_to_visible target field "foo""#), "\(error)")
        }
    }

    func testScrollToVisibleTargetRejectsPublicStableId() throws {
        let data = Data(#"{"label":"Settings","stableId":"main_scroll"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains(#"Unknown scroll_to_visible target field "stableId""#), "\(error)")
        }
    }

    func testScrollToVisibleRequestEnvelopeRejectsUnknownPayloadKey() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(buttonHeistVersion)","type":"scrollToVisible","payload":{"label":"Settings","containerId":"main_scroll"}}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains(#"Unknown scroll_to_visible target field "containerId""#), "\(error)")
        }
    }

    func testActionResultWithoutPayload() throws {
        let result = ActionResult(success: true, method: .activate)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNil(decoded.payload)
    }
}
