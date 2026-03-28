import XCTest
@testable import TheScore

final class ElementMatcherTests: XCTestCase {

    // MARK: - Absent Flag

    func testAbsentDefaultsFalse() {
        let matcher = ElementMatcher(label: "Save")
        XCTAssertFalse(matcher.isAbsent)
    }

    func testAbsentTrue() {
        let matcher = ElementMatcher(label: "Save", absent: true)
        XCTAssertTrue(matcher.isAbsent)
    }

    func testAbsentNilIsFalse() {
        let matcher = ElementMatcher(label: "Save", absent: nil)
        XCTAssertFalse(matcher.isAbsent)
    }

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

    func testActionTargetMatcherInitializerDropsEmptyMatcher() {
        XCTAssertNil(ActionTarget(matcher: ElementMatcher()))

        let target = ActionTarget(heistId: "save_button", matcher: ElementMatcher())
        XCTAssertEqual(target?.heistId, "save_button")
        XCTAssertNil(target?.match)
    }

    func testScrollToVisibleTargetMatcherInitializerDropsEmptyMatcher() {
        XCTAssertNil(ScrollToVisibleTarget(matcher: ElementMatcher()))

        let target = ScrollToVisibleTarget(heistId: "save_button", matcher: ElementMatcher())
        XCTAssertEqual(target?.heistId, "save_button")
        XCTAssertNil(target?.match)
    }

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let matcher = ElementMatcher(
            label: "Save", identifier: "saveBtn",
            value: "active", traits: ["button"], excludeTraits: ["disabled"],
            absent: true
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
        {"label":"Settings","traits":["header","button"],"excludeTraits":["disabled"]}
        """
        let data = Data(json.utf8)
        let matcher = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher.label, "Settings")
        XCTAssertEqual(matcher.traits, ["header", "button"])
        XCTAssertEqual(matcher.excludeTraits, ["disabled"])
        XCTAssertNil(matcher.identifier)
        XCTAssertNil(matcher.value)
        XCTAssertNil(matcher.absent)
    }

    // MARK: - Equatable

    func testEqualMatchers() {
        let a = ElementMatcher(label: "Save", traits: ["button"])
        let b = ElementMatcher(label: "Save", traits: ["button"])
        XCTAssertEqual(a, b)
    }

    func testUnequalMatchers() {
        let a = ElementMatcher(label: "Save")
        let b = ElementMatcher(label: "Cancel")
        XCTAssertNotEqual(a, b)
    }
}
