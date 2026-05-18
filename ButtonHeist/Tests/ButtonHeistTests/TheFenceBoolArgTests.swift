import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceBoolArgTests: XCTestCase {

    func testBooleanFromBool() {
        let args: [String: Any] = ["key": true]
        XCTAssertEqual(args.boolean("key"), true)
        XCTAssertEqual(["key": false].boolean("key"), false)
    }

    func testBooleanRejectsInt() {
        XCTAssertNil((["key": 1] as [String: Any]).boolean("key"))
        XCTAssertNil((["key": 0] as [String: Any]).boolean("key"))
        XCTAssertNil((["key": 42] as [String: Any]).boolean("key"))
    }

    func testBooleanRejectsString() {
        XCTAssertNil((["key": "true"] as [String: Any]).boolean("key"))
        XCTAssertNil((["key": "1"] as [String: Any]).boolean("key"))
        XCTAssertNil((["key": "false"] as [String: Any]).boolean("key"))
        XCTAssertNil((["key": "0"] as [String: Any]).boolean("key"))
        XCTAssertNil((["key": "yes"] as [String: Any]).boolean("key"))
    }

    func testBooleanMissing() {
        let args: [String: Any] = [:]
        XCTAssertNil(args.boolean("key"))
    }

    func testBooleanWrongType() {
        XCTAssertNil((["key": 3.14] as [String: Any]).boolean("key"))
    }
}
