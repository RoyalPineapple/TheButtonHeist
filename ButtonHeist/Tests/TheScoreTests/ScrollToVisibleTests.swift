import XCTest
@testable import TheScore

final class ScrollToVisibleTests: XCTestCase {

    // MARK: - ScrollToVisibleTarget

    func testScrollToVisibleTargetEncodeDecode() throws {
        let target = ScrollToVisibleTarget(
            match: ElementMatcher(label: "Color Picker", traits: [.button]),
            maxScrolls: 30,
            direction: .up
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        XCTAssertEqual(decoded.match.label, "Color Picker")
        XCTAssertEqual(decoded.match.traits, [.button])
        XCTAssertEqual(decoded.maxScrolls, 30)
        XCTAssertEqual(decoded.direction, .up)
    }

    func testScrollToVisibleTargetDefaults() {
        let target = ScrollToVisibleTarget(match: ElementMatcher(label: "Test"))
        XCTAssertEqual(target.resolvedMaxScrolls, 20)
        XCTAssertEqual(target.resolvedDirection, .down)
    }

    func testScrollToVisibleTargetMinimal() throws {
        let target = ScrollToVisibleTarget(match: ElementMatcher(heistId: "button_save"))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        XCTAssertEqual(decoded.match.heistId, "button_save")
        XCTAssertNil(decoded.maxScrolls)
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
            heistId: "button_color_picker", order: 5, description: "Color Picker",
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
            match: ElementMatcher(label: "Settings", traits: [.header]),
            maxScrolls: 10,
            direction: .down
        )
        let message = ClientMessage.scrollToVisible(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        if case .scrollToVisible(let decodedTarget) = decoded {
            XCTAssertEqual(decodedTarget.match.label, "Settings")
            XCTAssertEqual(decodedTarget.match.traits, [.header])
            XCTAssertEqual(decodedTarget.maxScrolls, 10)
            XCTAssertEqual(decodedTarget.direction, .down)
        } else {
            XCTFail("Expected scrollToVisible, got \(decoded)")
        }
    }

    func testScrollToVisibleRequestEnvelopeRoundTrip() throws {
        let target = ScrollToVisibleTarget(
            match: ElementMatcher(identifier: "market.row.colorPicker"),
            direction: .left
        )
        let envelope = RequestEnvelope(requestId: "test-123", message: .scrollToVisible(target))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestId, "test-123")
        if case .scrollToVisible(let decodedTarget) = decoded.message {
            XCTAssertEqual(decodedTarget.match.identifier, "market.row.colorPicker")
            XCTAssertEqual(decodedTarget.direction, .left)
        } else {
            XCTFail("Expected scrollToVisible")
        }
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
