import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class TheFenceBoolArgTests: XCTestCase {

    func testBooleanFromBool() throws {
        let args = TheFence.CommandArgumentEnvelope(values: ["key": .bool(true)])
        XCTAssertEqual(try args.schemaBoolean("key"), true)

        let falseArgs = TheFence.CommandArgumentEnvelope(values: ["key": .bool(false)])
        XCTAssertEqual(try falseArgs.schemaBoolean("key"), false)
    }

    func testBooleanRejectsInt() throws {
        for value in [1, 0, 42] {
            let args = TheFence.CommandArgumentEnvelope(values: ["key": .int(value)])
            XCTAssertThrowsError(try args.schemaBoolean("key"))
        }
    }

    func testBooleanRejectsString() throws {
        for value in ["true", "1", "false", "0", "yes"] {
            let args = TheFence.CommandArgumentEnvelope(values: ["key": .string(value)])
            XCTAssertThrowsError(try args.schemaBoolean("key"))
        }
    }

    func testBooleanMissing() throws {
        let args = TheFence.CommandArgumentEnvelope(values: [:])
        XCTAssertNil(try args.schemaBoolean("key"))
    }

    func testBooleanWrongType() throws {
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(values: ["key": .double(3.14)]).schemaBoolean("key"))
    }
}
