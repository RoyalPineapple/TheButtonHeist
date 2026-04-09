import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceBoolArgTests: XCTestCase {

    func testBooleanFromBool() {
        let args: [String: Any] = ["key": true]
        XCTAssertEqual(args.boolean("key"), true)
        XCTAssertEqual(["key": false].boolean("key"), false)
    }

    func testBooleanFromInt() {
        XCTAssertEqual((["key": 1] as [String: Any]).boolean("key"), true)
        XCTAssertEqual((["key": 0] as [String: Any]).boolean("key"), false)
        XCTAssertEqual((["key": 42] as [String: Any]).boolean("key"), true)
    }

    func testBooleanFromString() {
        XCTAssertEqual((["key": "true"] as [String: Any]).boolean("key"), true)
        XCTAssertEqual((["key": "1"] as [String: Any]).boolean("key"), true)
        XCTAssertEqual((["key": "false"] as [String: Any]).boolean("key"), false)
        XCTAssertEqual((["key": "0"] as [String: Any]).boolean("key"), false)
        XCTAssertEqual((["key": "yes"] as [String: Any]).boolean("key"), false)
    }

    func testBooleanMissing() {
        let args: [String: Any] = [:]
        XCTAssertNil(args.boolean("key"))
    }

    func testBooleanWrongType() {
        XCTAssertNil((["key": 3.14] as [String: Any]).boolean("key"))
    }
}
