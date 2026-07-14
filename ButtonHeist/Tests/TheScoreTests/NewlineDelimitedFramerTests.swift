import Foundation
import XCTest
@testable import TheScore

final class NewlineDelimitedFramerTests: XCTestCase {
    func testFragmentedFrameIsEmittedOnlyAfterDelimiterArrives() {
        var framer = NewlineDelimitedFramer()

        XCTAssertEqual(framer.append(Data("fir".utf8)), [])
        XCTAssertEqual(utf8String(framer.pendingData), "fir")

        XCTAssertEqual(framer.append(Data("st\nsec".utf8)).map(utf8String), ["first"])
        XCTAssertEqual(utf8String(framer.pendingData), "sec")
    }

    func testOneAppendReturnsEveryCompleteFrameInOrder() {
        var framer = NewlineDelimitedFramer()

        let frames = framer.append(Data("first\nsecond\nthird\n".utf8))

        XCTAssertEqual(frames.map(utf8String), ["first", "second", "third"])
        XCTAssertEqual(framer.pendingData, Data())
    }

    func testEmptyFramesAreIgnored() {
        var framer = NewlineDelimitedFramer()

        let frames = framer.append(Data("\n\nbody\n\n".utf8))

        XCTAssertEqual(frames.map(utf8String), ["body"])
        XCTAssertEqual(framer.pendingData, Data())
    }

    func testAppendRetainsOnlySuffixAfterFinalDelimiter() {
        var framer = NewlineDelimitedFramer()

        XCTAssertEqual(framer.append(Data("first\nsecond\npartial".utf8)).map(utf8String), ["first", "second"])
        XCTAssertEqual(utf8String(framer.pendingData), "partial")

        XCTAssertEqual(framer.append(Data()).map(utf8String), [])
        XCTAssertEqual(utf8String(framer.pendingData), "partial")
    }

    private func utf8String(_ data: Data) -> String {
        guard let string = String(bytes: data, encoding: .utf8) else {
            XCTFail("Expected UTF-8 data")
            return ""
        }
        return string
    }
}
