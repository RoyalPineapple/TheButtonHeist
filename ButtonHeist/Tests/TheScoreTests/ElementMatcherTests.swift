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

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let matcher = ElementMatcher(
            label: "Save", identifier: "saveBtn", heistId: "button_save",
            value: "active", traits: [.button], excludeTraits: [.notEnabled],
            scope: .both, absent: true
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
        XCTAssertNil(matcher.heistId)
        XCTAssertNil(matcher.value)
        XCTAssertNil(matcher.absent)
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

    // MARK: - MatchScope

    func testScopeDefaultsToElements() {
        let matcher = ElementMatcher(label: "Save")
        XCTAssertNil(matcher.scope)
        XCTAssertEqual(matcher.resolvedScope, .elements)
    }

    func testScopeContainers() {
        let matcher = ElementMatcher(label: "Save", scope: .containers)
        XCTAssertEqual(matcher.scope, .containers)
        XCTAssertEqual(matcher.resolvedScope, .containers)
    }

    func testScopeBoth() {
        let matcher = ElementMatcher(label: "Save", scope: .both)
        XCTAssertEqual(matcher.resolvedScope, .both)
    }

    func testScopeEncodesDecodes() throws {
        let matcher = ElementMatcher(label: "Save", scope: .containers)
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(decoded.scope, .containers)
    }

    func testScopeDecodesFromJSON() throws {
        let json = """
        {"label":"Nav","scope":"both"}
        """
        let data = Data(json.utf8)
        let matcher = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher.scope, .both)
    }

    func testScopeMissingInJSONDefaultsToNil() throws {
        let json = """
        {"label":"Save"}
        """
        let data = Data(json.utf8)
        let matcher = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertNil(matcher.scope)
        XCTAssertEqual(matcher.resolvedScope, .elements)
    }

    func testScopeEqualityIncludesScope() {
        let a = ElementMatcher(label: "Save", scope: .elements)
        let b = ElementMatcher(label: "Save", scope: .containers)
        XCTAssertNotEqual(a, b)
    }

    func testEncodeDecodeAllFieldsWithScope() throws {
        let matcher = ElementMatcher(
            label: "Save", identifier: "saveBtn", heistId: "button_save",
            value: "active", traits: [.button], excludeTraits: [.notEnabled],
            scope: .both, absent: true
        )
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    // MARK: - MatchScope Enum

    func testMatchScopeAllCases() {
        XCTAssertEqual(MatchScope.allCases, [.elements, .containers, .both])
    }

    func testMatchScopeRawValues() {
        XCTAssertEqual(MatchScope.elements.rawValue, "elements")
        XCTAssertEqual(MatchScope.containers.rawValue, "containers")
        XCTAssertEqual(MatchScope.both.rawValue, "both")
    }
}
