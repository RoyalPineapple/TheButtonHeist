import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceBoolArgTests: XCTestCase {

    func testBooleanFromBool() throws {
        let args = try TheFence.CommandArgumentEnvelope(arguments: ["key": true])
        XCTAssertEqual(try args.schemaBoolean("key"), true)

        let falseArgs = try TheFence.CommandArgumentEnvelope(arguments: ["key": false])
        XCTAssertEqual(try falseArgs.schemaBoolean("key"), false)
    }

    func testBooleanRejectsInt() throws {
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": 1]).schemaBoolean("key"))
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": 0]).schemaBoolean("key"))
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": 42]).schemaBoolean("key"))
    }

    func testBooleanRejectsString() throws {
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": "true"]).schemaBoolean("key"))
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": "1"]).schemaBoolean("key"))
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": "false"]).schemaBoolean("key"))
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": "0"]).schemaBoolean("key"))
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": "yes"]).schemaBoolean("key"))
    }

    func testBooleanMissing() throws {
        let args = try TheFence.CommandArgumentEnvelope(arguments: [:])
        XCTAssertNil(try args.schemaBoolean("key"))
    }

    func testBooleanWrongType() throws {
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: ["key": 3.14]).schemaBoolean("key"))
    }
}
