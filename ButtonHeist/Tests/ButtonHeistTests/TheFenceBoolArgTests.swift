import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class TheFenceBoolArgTests: XCTestCase {

    func testBooleanFromBool() throws {
        let args = TheFence.CommandArgumentEnvelope(values: [FenceParameterKey.inlineData.rawValue: .bool(true)])
        XCTAssertEqual(try args.schemaBoolean(.inlineData), true)

        let falseArgs = TheFence.CommandArgumentEnvelope(values: [FenceParameterKey.inlineData.rawValue: .bool(false)])
        XCTAssertEqual(try falseArgs.schemaBoolean(.inlineData), false)
    }

    func testBooleanRejectsInt() throws {
        for value in [1, 0, 42] {
            let args = TheFence.CommandArgumentEnvelope(values: [FenceParameterKey.inlineData.rawValue: .int(value)])
            XCTAssertThrowsError(try args.schemaBoolean(.inlineData))
        }
    }

    func testBooleanRejectsString() throws {
        for value in ["true", "1", "false", "0", "yes"] {
            let args = TheFence.CommandArgumentEnvelope(values: [FenceParameterKey.inlineData.rawValue: .string(value)])
            XCTAssertThrowsError(try args.schemaBoolean(.inlineData))
        }
    }

    func testBooleanMissing() throws {
        let args = TheFence.CommandArgumentEnvelope(values: [:])
        XCTAssertNil(try args.schemaBoolean(.inlineData))
    }

    func testBooleanWrongType() throws {
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(
            values: [FenceParameterKey.inlineData.rawValue: .double(3.14)]
        ).schemaBoolean(.inlineData))
    }
}
