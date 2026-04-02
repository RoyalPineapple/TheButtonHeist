import XCTest
@testable import ButtonHeist

final class TokenMeterTests: XCTestCase {

    @ButtonHeistActor
    func testEstimateTokensShortString() {
        let tokens = TokenMeter.estimateTokens("hello")
        XCTAssertEqual(tokens, 1)
    }

    @ButtonHeistActor
    func testEstimateTokensEmptyString() {
        let tokens = TokenMeter.estimateTokens("")
        XCTAssertEqual(tokens, 1, "Empty string should return minimum of 1 token")
    }

    @ButtonHeistActor
    func testEstimateTokensLongString() {
        let text = String(repeating: "abcd", count: 100)
        let tokens = TokenMeter.estimateTokens(text)
        XCTAssertEqual(tokens, 100)
    }

    @ButtonHeistActor
    func testEstimateTokensMultibyteCharacters() {
        let text = String(repeating: "\u{1F600}", count: 10)
        let tokens = TokenMeter.estimateTokens(text)
        XCTAssertEqual(tokens, 10, "Each emoji is 4 UTF-8 bytes = 1 estimated token")
    }

    @ButtonHeistActor
    func testRecordAccumulates() {
        var meter = TokenMeter()
        let first = meter.record("abcdefghijklmnop")
        XCTAssertEqual(first, 4)
        XCTAssertEqual(meter.cumulativeTokens, 4)
        XCTAssertEqual(meter.responseCount, 1)

        let second = meter.record("abcdefghijklmnop")
        XCTAssertEqual(second, 4)
        XCTAssertEqual(meter.cumulativeTokens, 8)
        XCTAssertEqual(meter.responseCount, 2)
    }

    @ButtonHeistActor
    func testReset() {
        var meter = TokenMeter()
        meter.record("abcdefghijklmnop")
        meter.record("abcdefghijklmnop")
        meter.reset()
        XCTAssertEqual(meter.cumulativeTokens, 0)
        XCTAssertEqual(meter.responseCount, 0)
    }

    @ButtonHeistActor
    func testFormatFooter() {
        var meter = TokenMeter()
        meter.record("abcdefghijklmnop")
        let footer = meter.formatFooter(responseTokens: 4)
        XCTAssertEqual(footer, "[tokens: ~4 | session: ~4 (1 responses)]")
    }

    @ButtonHeistActor
    func testApplyTelemetryDisabledByDefault() {
        let fence = TheFence()
        let text = "action: tap ok"
        let result = fence.applyTelemetry(to: text)
        XCTAssertEqual(result, text, "Telemetry should not be appended when disabled")
    }

    @ButtonHeistActor
    func testTelemetryDictDisabledByDefault() {
        let fence = TheFence()
        let result = fence.telemetryDict(for: "some text")
        XCTAssertNil(result, "telemetryDict should return nil when disabled")
    }
}
