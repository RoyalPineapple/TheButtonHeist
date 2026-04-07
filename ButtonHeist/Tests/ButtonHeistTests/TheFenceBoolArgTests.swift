import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceBoolArgTests: XCTestCase {

    @ButtonHeistActor
    func testBoolArgFromBool() async {
        let fence = TheFence()
        XCTAssertEqual(fence.boolArg(["key": true], "key"), true)
        XCTAssertEqual(fence.boolArg(["key": false], "key"), false)
    }

    @ButtonHeistActor
    func testBoolArgFromInt() async {
        let fence = TheFence()
        XCTAssertEqual(fence.boolArg(["key": 1], "key"), true)
        XCTAssertEqual(fence.boolArg(["key": 0], "key"), false)
        XCTAssertEqual(fence.boolArg(["key": 42], "key"), true)
    }

    @ButtonHeistActor
    func testBoolArgFromString() async {
        let fence = TheFence()
        XCTAssertEqual(fence.boolArg(["key": "true"], "key"), true)
        XCTAssertEqual(fence.boolArg(["key": "1"], "key"), true)
        XCTAssertEqual(fence.boolArg(["key": "false"], "key"), false)
        XCTAssertEqual(fence.boolArg(["key": "0"], "key"), false)
        XCTAssertEqual(fence.boolArg(["key": "yes"], "key"), false)
    }

    @ButtonHeistActor
    func testBoolArgMissing() async {
        let fence = TheFence()
        XCTAssertNil(fence.boolArg([:], "key"))
    }

    @ButtonHeistActor
    func testBoolArgWrongType() async {
        let fence = TheFence()
        XCTAssertNil(fence.boolArg(["key": 3.14], "key"))
    }
}
