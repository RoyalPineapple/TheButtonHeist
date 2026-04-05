import XCTest
@testable import TheScore

final class ScrollToVisibleTests: XCTestCase {

    // MARK: - ScrollToVisibleTarget

    func testScrollToVisibleTargetEncodeDecode() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .matcher(ElementMatcher(label: "Color Picker", traits: [.button])),
            direction: .up
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .matcher(let matcher, _) = decoded.elementTarget else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Color Picker")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertEqual(decoded.direction, .up)
    }

    func testScrollToVisibleTargetHeistIdEncodeDecode() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .heistId("buttonheist.longList.last"),
            direction: .down
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .heistId(let id) = decoded.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "buttonheist.longList.last")
        XCTAssertEqual(decoded.direction, .down)
    }

    func testScrollToVisibleTargetDefaults() {
        let target = ScrollToVisibleTarget(elementTarget: .matcher(ElementMatcher(label: "Test")))
        XCTAssertEqual(target.resolvedDirection, .down)
    }

    func testScrollToVisibleTargetMinimal() throws {
        let target = ScrollToVisibleTarget(elementTarget: .matcher(ElementMatcher(label: "Save")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .matcher(let matcher, _) = decoded.elementTarget else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertNil(decoded.direction)
    }

    // MARK: - ScrollSearchDirection

    func testScrollSearchDirectionAllCases() {
        let cases = ScrollSearchDirection.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.down))
        XCTAssertTrue(cases.contains(.up))
        XCTAssertTrue(cases.contains(.left))
        XCTAssertTrue(cases.contains(.right))
    }

    func testScrollSearchDirectionRawValues() {
        XCTAssertEqual(ScrollSearchDirection.down.rawValue, "down")
        XCTAssertEqual(ScrollSearchDirection.up.rawValue, "up")
        XCTAssertEqual(ScrollSearchDirection.left.rawValue, "left")
        XCTAssertEqual(ScrollSearchDirection.right.rawValue, "right")
    }

    // MARK: - ScrollSearchResult

    func testScrollSearchResultEncodeDecode() throws {
        let element = HeistElement(
            heistId: "button_color_picker", description: "Color Picker",
            label: "Color Picker", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 200, frameWidth: 375, frameHeight: 44,
            actions: [.activate]
        )
        let result = ScrollSearchResult(
            scrollCount: 6, uniqueElementsSeen: 47, totalItems: 80,
            exhaustive: false, foundElement: element
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ScrollSearchResult.self, from: data)
        XCTAssertEqual(decoded.scrollCount, 6)
        XCTAssertEqual(decoded.uniqueElementsSeen, 47)
        XCTAssertEqual(decoded.totalItems, 80)
        XCTAssertFalse(decoded.exhaustive)
        XCTAssertEqual(decoded.foundElement?.heistId, "button_color_picker")
    }

    func testScrollSearchResultNotFound() throws {
        let result = ScrollSearchResult(
            scrollCount: 20, uniqueElementsSeen: 80, totalItems: 80, exhaustive: true
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ScrollSearchResult.self, from: data)
        XCTAssertEqual(decoded.scrollCount, 20)
        XCTAssertTrue(decoded.exhaustive)
        XCTAssertNil(decoded.foundElement)
    }

    // MARK: - Wire Round-Trip (ClientMessage)

    func testScrollToVisibleClientMessageRoundTrip() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .matcher(ElementMatcher(label: "Settings", traits: [.header])),
            direction: .down
        )
        let message = ClientMessage.scrollToVisible(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        guard case .scrollToVisible(let decodedTarget) = decoded,
              case .matcher(let matcher, _) = decodedTarget.elementTarget else {
            return XCTFail("Expected scrollToVisible with matcher")
        }
        XCTAssertEqual(matcher.label, "Settings")
        XCTAssertEqual(matcher.traits, [.header])
        XCTAssertEqual(decodedTarget.direction, .down)
    }

    func testScrollToVisibleRequestEnvelopeRoundTrip() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .matcher(ElementMatcher(identifier: "market.row.colorPicker")),
            direction: .left
        )
        let envelope = RequestEnvelope(requestId: "test-123", message: .scrollToVisible(target))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestId, "test-123")
        guard case .scrollToVisible(let decodedTarget) = decoded.message,
              case .matcher(let matcher, _) = decodedTarget.elementTarget else {
            return XCTFail("Expected scrollToVisible with matcher")
        }
        XCTAssertEqual(matcher.identifier, "market.row.colorPicker")
        XCTAssertEqual(decodedTarget.direction, .left)
    }

    // MARK: - ActionResult with ScrollSearchResult

    func testActionResultWithScrollSearchResult() throws {
        let searchResult = ScrollSearchResult(
            scrollCount: 3, uniqueElementsSeen: 25, totalItems: 50, exhaustive: false
        )
        let result = ActionResult(
            success: true, method: .scrollToVisible,
            scrollSearchResult: searchResult
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNotNil(decoded.scrollSearchResult)
        XCTAssertEqual(decoded.scrollSearchResult?.scrollCount, 3)
        XCTAssertEqual(decoded.scrollSearchResult?.totalItems, 50)
    }

    func testActionResultWithoutScrollSearchResult() throws {
        let result = ActionResult(success: true, method: .activate)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNil(decoded.scrollSearchResult)
    }
}
