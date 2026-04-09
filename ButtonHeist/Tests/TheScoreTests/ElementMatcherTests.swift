import XCTest
@testable import TheScore

final class ElementMatcherTests: XCTestCase {

    func testHasPredicatesIgnoresEmptyTraitArrays() {
        XCTAssertFalse(ElementMatcher(traits: []).hasPredicates)
        XCTAssertFalse(ElementMatcher(excludeTraits: []).hasPredicates)
        XCTAssertFalse(ElementMatcher(traits: [], excludeTraits: []).hasPredicates)
        XCTAssertTrue(ElementMatcher(label: "Save", traits: []).hasPredicates)
    }

    func testNonEmptyReturnsNilForEmptyMatcher() {
        XCTAssertNil(ElementMatcher().nonEmpty)
        XCTAssertNil(ElementMatcher(traits: []).nonEmpty)
        XCTAssertEqual(ElementMatcher(label: "Save").nonEmpty, ElementMatcher(label: "Save"))
    }

    func testElementTargetMatcherInitializerDropsEmptyMatcher() {
        XCTAssertNil(ElementTarget(matcher: ElementMatcher()))

        let target = ElementTarget(heistId: "save_button", matcher: ElementMatcher())
        guard case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    func testScrollToVisibleTargetWithElementTarget() {
        // No element target
        let empty = ScrollToVisibleTarget()
        XCTAssertNil(empty.elementTarget)

        // With heistId
        let withId = ScrollToVisibleTarget(elementTarget: .heistId("save_button"))
        guard case .heistId(let id) = withId.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let matcher = ElementMatcher(
            label: "Save", identifier: "saveBtn",
            value: "active", traits: [.button], excludeTraits: [.unknown("disabled")]
        )
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    func testEncodeDecodeMinimal() throws {
        let matcher = ElementMatcher(label: "Save")
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    func testEncodeDecodeEmpty() throws {
        let matcher = ElementMatcher()
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {"label":"Settings","traits":["header","button"],"excludeTraits":["notEnabled"]}
        """
        let data = Data(json.utf8)
        let matcher = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher.label, "Settings")
        XCTAssertEqual(matcher.traits, [.header, .button])
        XCTAssertEqual(matcher.excludeTraits, [.notEnabled])
        XCTAssertNil(matcher.identifier)
        XCTAssertNil(matcher.value)
    }

    // MARK: - Equatable

    func testEqualMatchers() {
        let a = ElementMatcher(label: "Save", traits: [.button])
        let b = ElementMatcher(label: "Save", traits: [.button])
        XCTAssertEqual(a, b)
    }

    func testUnequalMatchers() {
        let a = ElementMatcher(label: "Save")
        let b = ElementMatcher(label: "Cancel")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Empty String Handling

    func testEmptyStringLabelHasNoPredicates() {
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(matcher.hasPredicates)
        XCTAssertNil(matcher.nonEmpty)
    }

    func testEmptyStringIdentifierHasNoPredicates() {
        let matcher = ElementMatcher(identifier: "")
        XCTAssertFalse(matcher.hasPredicates)
    }

    func testEmptyStringValueHasNoPredicates() {
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(matcher.hasPredicates)
    }

    func testEmptyStringLabelMatchesNothing() {
        let element = HeistElement.stub(label: "Save")
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(element.matches(matcher), "Empty-string label should match nothing")
    }

    func testEmptyStringMatcherTreatedAsNoPredicate() {
        let matcher = ElementMatcher(label: "", identifier: "", value: "")
        XCTAssertFalse(matcher.hasPredicates, "All-empty-string matcher should have no predicates")
        XCTAssertNil(matcher.nonEmpty, "All-empty-string matcher should be nonEmpty == nil")
    }
}
