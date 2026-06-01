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

    func testScrollToVisibleTargetHeistIdEncodeDecode() throws {
        let target = ScrollToVisibleTarget(
            elementTarget: .heistId("buttonheist.longList.last")
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ScrollToVisibleTarget.self, from: data)
        guard case .heistId(let id) = decoded.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "buttonheist.longList.last")
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

    // MARK: - ElementSearchTarget (iterative, with direction)

    func testElementSearchTargetEncodeDecode() throws {
        let target = ElementSearchTarget(
            elementTarget: .predicate(ElementPredicate(label: "Color Picker", traits: [.button])),
            direction: .up
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementSearchTarget.self, from: data)
        guard case .predicate(let matcher, _) = decoded.elementTarget else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Color Picker")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertEqual(decoded.direction, .up)
    }

    func testElementSearchTargetHeistIdEncodeDecode() throws {
        let target = ElementSearchTarget(
            elementTarget: .heistId("buttonheist.longList.last"),
            direction: .down
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementSearchTarget.self, from: data)
        guard case .heistId(let id) = decoded.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "buttonheist.longList.last")
        XCTAssertEqual(decoded.direction, .down)
    }

    func testElementSearchTargetDefaults() {
        let target = ElementSearchTarget(elementTarget: .predicate(ElementPredicate(label: "Test")))
        XCTAssertEqual(target.direction, .down)
    }

    func testElementSearchClientMessageRoundTrip() throws {
        let target = ElementSearchTarget(
            elementTarget: .predicate(ElementPredicate(label: "Settings", traits: [.header])),
            direction: .down
        )
        let message = ClientMessage.elementSearch(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        guard case .elementSearch(let decodedTarget) = decoded,
              case .predicate(let matcher, _) = decodedTarget.elementTarget else {
            return XCTFail("Expected elementSearch with matcher")
        }
        XCTAssertEqual(matcher.label, "Settings")
        XCTAssertEqual(matcher.traits, [.header])
        XCTAssertEqual(decodedTarget.direction, .down)
    }

    func testElementSearchRequestEnvelopeRoundTrip() throws {
        let target = ElementSearchTarget(
            elementTarget: .predicate(ElementPredicate(identifier: "market.row.colorPicker")),
            direction: .left
        )
        let envelope = RequestEnvelope(requestId: "test-123", message: .elementSearch(target))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestId, "test-123")
        guard case .elementSearch(let decodedTarget) = decoded.message,
              case .predicate(let matcher, _) = decodedTarget.elementTarget else {
            return XCTFail("Expected elementSearch with matcher")
        }
        XCTAssertEqual(matcher.identifier, "market.row.colorPicker")
        XCTAssertEqual(decodedTarget.direction, .left)
    }

    // MARK: - ScrollSearchResult

    func testScrollSearchResultEncodeDecode() throws {
        let result = ScrollSearchResult(
            scrollCount: 6, uniqueElementsSeen: 47,
            exhaustive: false, foundHeistId: "button_color_picker"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ScrollSearchResult.self, from: data)
        XCTAssertEqual(decoded.scrollCount, 6)
        XCTAssertEqual(decoded.uniqueElementsSeen, 47)
        XCTAssertFalse(decoded.exhaustive)
        XCTAssertEqual(decoded.foundHeistId, "button_color_picker")
    }

    func testScrollSearchResultNotFound() throws {
        let result = ScrollSearchResult(
            scrollCount: 20, uniqueElementsSeen: 80, exhaustive: true
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ScrollSearchResult.self, from: data)
        XCTAssertEqual(decoded.scrollCount, 20)
        XCTAssertTrue(decoded.exhaustive)
        XCTAssertNil(decoded.foundHeistId)
    }

    func testScrollSearchResultRejectsObsoleteFoundElementSnapshot() throws {
        let json = Data("""
        {"scrollCount":1,"uniqueElementsSeen":1,"exhaustive":false,"foundElement":{"heistId":"old"}}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ScrollSearchResult.self, from: json))
    }

    func testScrollSearchResultRejectsObsoleteTotalItems() throws {
        let json = Data("""
        {"scrollCount":1,"uniqueElementsSeen":1,"totalItems":10,"exhaustive":false}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ScrollSearchResult.self, from: json))
    }

    // MARK: - ActionResult with ScrollSearchResult

    func testActionResultWithScrollSearchResult() throws {
        let searchResult = ScrollSearchResult(
            scrollCount: 3, uniqueElementsSeen: 25, exhaustive: false
        )
        let result = ActionResult(
            success: true, method: .elementSearch,
            payload: .scrollSearch(searchResult)
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        guard case .scrollSearch(let search) = decoded.payload else {
            XCTFail("Expected .scrollSearch payload, got \(String(describing: decoded.payload))")
            return
        }
        XCTAssertEqual(search.scrollCount, 3)
        XCTAssertEqual(search.uniqueElementsSeen, 25)
    }

    func testActionResultWithoutScrollSearchResult() throws {
        let result = ActionResult(success: true, method: .activate)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNil(decoded.payload)
    }
}
